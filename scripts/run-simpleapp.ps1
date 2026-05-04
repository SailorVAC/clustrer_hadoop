# Сборка SimpleApp, загрузка тестового файла в HDFS и запуск MapReduce-job.
#
# Использование (из корня репозитория):
#   .\scripts\run-simpleapp.ps1                                  # smoke-тест
#   .\scripts\run-simpleapp.ps1 -InputPath /demo/in -OutputPath /demo/out
#
# Для multi-host кластера: скрипт запускается на мастер-ноуте, где
# доступны контейнеры namenode и resourcemanager.

param(
    [string]$InputPath  = "/simpleapp/input",
    [string]$OutputPath = "/simpleapp/output"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$JarName  = "SimpleApp-1.0-SNAPSHOT.jar"
$JarPath  = Join-Path $RepoRoot "app\SimpleApp\target\$JarName"

# ---------- 1. Сборка, если JAR ещё не собран ----------
if (-not (Test-Path $JarPath)) {
    Write-Host "=== JAR не найден, запускаю сборку ==="
    & (Join-Path $RepoRoot "scripts\build-app.ps1")
}

# ---------- 2. Определяем контейнер для запуска ----------
$SubmitContainer = $null
foreach ($c in @("resourcemanager", "namenode")) {
    $running = docker inspect --format '{{.State.Running}}' $c 2>$null
    if ($running -eq "true") {
        $SubmitContainer = $c
        break
    }
}
if (-not $SubmitContainer) {
    Write-Error "Ошибка: не найден запущенный контейнер namenode или resourcemanager.`nУбедитесь, что кластер поднят (docker compose ... up -d)."
    exit 1
}
Write-Host "=== Используем контейнер: $SubmitContainer ==="

# Определяем контейнер с HDFS-клиентом (namenode)
$HdfsContainer = "namenode"
$nnRunning = docker inspect --format '{{.State.Running}}' $HdfsContainer 2>$null
if ($nnRunning -ne "true") {
    $HdfsContainer = $SubmitContainer
}

# ---------- 3. Копируем JAR в контейнер ----------
Write-Host "=== Копирую JAR в контейнер ==="
docker cp $JarPath "${SubmitContainer}:/tmp/${JarName}"

# ---------- 4. Готовим входные данные в HDFS ----------
Write-Host "=== Подготовка HDFS (input=$InputPath, output=$OutputPath) ==="

# Удалим предыдущий output, если есть
docker exec $HdfsContainer hdfs dfs -rm -r -f $OutputPath 2>$null

# Если входная директория пуста — кладём тестовый файл
$existing = docker exec $HdfsContainer hdfs dfs -ls $InputPath 2>&1
if ($LASTEXITCODE -ne 0 -or $existing -match "No such file") {
    Write-Host "=== Создаю тестовый файл в HDFS ==="
    $sampleText = @"
Hadoop — фреймворк для распределённой обработки больших данных.
Он работает на кластере из обычных серверов.
MapReduce делит задачу на маленькие подзадачи.
Каждый узел обрабатывает свою часть данных.
Результаты объединяются на этапе Reduce.
HDFS обеспечивает надёжное хранение с репликацией.
YARN управляет ресурсами кластера.
Hadoop широко используется в индустрии.
Это учебный пример — LineCount считает строки.
Привет, Hadoop!
"@
    # Записываем файл через docker exec
    docker exec $HdfsContainer bash -c "cat > /tmp/sample.txt << 'ENDOFFILE'
$sampleText
ENDOFFILE"
    docker exec $HdfsContainer hdfs dfs -mkdir -p $InputPath
    docker exec $HdfsContainer hdfs dfs -put -f /tmp/sample.txt "$InputPath/"
}

# ---------- 5. Запускаем MapReduce-задачу ----------
Write-Host ""
Write-Host "=== Запускаю LineCount MapReduce на YARN ==="
Write-Host "    Вход:  $InputPath"
Write-Host "    Выход: $OutputPath"
Write-Host ""

docker exec $SubmitContainer `
    hadoop jar "/tmp/$JarName" `
    by.bsu.rct.bigdata.LineCountDriverMR `
    $InputPath $OutputPath

if ($LASTEXITCODE -ne 0) {
    Write-Error "MapReduce-задача завершилась с ошибкой"
    exit 1
}

# ---------- 6. Показываем результат ----------
Write-Host ""
Write-Host "=== Результат ==="
docker exec $HdfsContainer hdfs dfs -cat "$OutputPath/part-r-00000"
Write-Host ""
Write-Host "=== Готово! ==="
