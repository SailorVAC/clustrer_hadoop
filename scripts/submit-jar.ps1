# Универсальный submit JAR-а на наш Hadoop+Spark-кластер (PowerShell-версия).
#
# Скрипт сам:
#   * находит работающий submit-контейнер (resourcemanager → namenode);
#   * проверяет, что Docker-кластер вообще поднят;
#   * копирует локальный JAR в /tmp/ контейнера;
#   * вызывает `hadoop jar` или `spark-submit` с нужными флагами;
#   * пробрасывает аргументы в саму программу.
#
# Использование (из корня репо):
#   .\scripts\submit-jar.ps1 -Engine hadoop -Jar .\my.jar -- /hdfs/in /hdfs/out
#   .\scripts\submit-jar.ps1 -Engine spark  -Jar .\my.jar -Class org.example.Main -- arg1 arg2
#   .\scripts\submit-jar.ps1 -Engine spark  -Jar .\my.jar -DeployMode cluster `
#       -Conf @("spark.executor.memory=1g","spark.executor.cores=2") -- /hdfs/in
#
# Примечание: аргументы, идущие в саму программу, перечислите ПОСЛЕ `--`.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("hadoop", "spark")]
    [string]$Engine,

    [Parameter(Mandatory=$true)]
    [string]$Jar,

    [string]$Class = "",

    [ValidateSet("client", "cluster")]
    [string]$DeployMode = "client",

    [string]$Name = "",

    # -D key=value для hadoop jar (повторяемо)
    [string[]]$DConf = @(),

    # --conf key=value для spark-submit (повторяемо)
    [string[]]$Conf = @(),

    # --jars a.jar,b.jar для spark
    [string]$ExtraJars = "",

    # --files /local/f1,/hdfs/f2 для spark
    [string]$Files = "",

    # Принудительно подменить submit-контейнер
    [string]$SubmitHost = "",

    # Всё, что идёт после `--`, попадает сюда автоматически
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ProgramArgs = @()
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Jar)) {
    Write-Host "ОШИБКА: JAR не найден: $Jar" -ForegroundColor Red
    exit 1
}
$JarPath = (Resolve-Path $Jar).Path
$JarName = Split-Path -Leaf $JarPath

# PowerShell кладёт в $ProgramArgs всё, включая `--`. Уберём его.
if ($ProgramArgs.Count -gt 0 -and $ProgramArgs[0] -eq "--") {
    $ProgramArgs = $ProgramArgs[1..($ProgramArgs.Count - 1)]
}

# ---------- Выбираем submit-контейнер ----------
function Find-SubmitContainer {
    if ($SubmitHost) {
        $running = docker inspect --format '{{.State.Running}}' $SubmitHost 2>$null
        if ($running -eq "true") { return $SubmitHost }
        Write-Host "ОШИБКА: контейнер '$SubmitHost' не запущен." -ForegroundColor Red
        exit 1
    }
    foreach ($c in @("resourcemanager", "namenode")) {
        $running = docker inspect --format '{{.State.Running}}' $c 2>$null
        if ($running -eq "true") { return $c }
    }
    Write-Host "ОШИБКА: не нашёл работающего submit-контейнера (resourcemanager/namenode)." -ForegroundColor Red
    exit 1
}
$SubmitContainer = Find-SubmitContainer

Write-Host "=== Submit-контейнер: $SubmitContainer ==="
Write-Host "    JAR:        $JarPath"
Write-Host "    Engine:     $Engine"
if ($Class) { Write-Host "    Main class: $Class" }
if ($Engine -eq "spark") { Write-Host "    Mode:       --master yarn --deploy-mode $DeployMode" }
if ($ProgramArgs.Count -gt 0) { Write-Host "    Args:       $($ProgramArgs -join ' ')" }
Write-Host ""

# ---------- Копируем JAR ----------
docker cp $JarPath "${SubmitContainer}:/tmp/${JarName}"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ОШИБКА: не удалось скопировать JAR в контейнер." -ForegroundColor Red
    exit 1
}

# ---------- Запускаем ----------
if ($Engine -eq "hadoop") {
    $cmd = @("hadoop", "jar", "/tmp/$JarName")
    if ($Class) { $cmd += $Class }
    foreach ($d in $DConf) { $cmd += "-D"; $cmd += $d }
    foreach ($a in $ProgramArgs) { $cmd += $a }

    Write-Host "=== $($cmd -join ' ') ==="
    docker exec $SubmitContainer @cmd
}
else {
    $appName = if ($Name) { $Name } else { [System.IO.Path]::GetFileNameWithoutExtension($JarName) }
    $cmd = @(
        "spark-submit",
        "--master", "yarn",
        "--deploy-mode", $DeployMode,
        "--name", $appName,
        "--conf", "spark.yarn.submit.waitAppCompletion=true"
    )
    if ($Class)     { $cmd += "--class"; $cmd += $Class }
    if ($ExtraJars) { $cmd += "--jars";  $cmd += $ExtraJars }
    if ($Files)     { $cmd += "--files"; $cmd += $Files }
    foreach ($c in $Conf) { $cmd += "--conf"; $cmd += $c }
    $cmd += "/tmp/$JarName"
    foreach ($a in $ProgramArgs) { $cmd += $a }

    Write-Host "=== $($cmd -join ' ') ==="
    docker exec $SubmitContainer @cmd
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ОШИБКА: задача завершилась с кодом $LASTEXITCODE." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "=== Готово ==="
