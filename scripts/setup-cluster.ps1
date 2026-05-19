<#
.SYNOPSIS
    Мастер настройки Hadoop-кластера.
.DESCRIPTION
    Генерирует docker-compose и .env файлы для каждой машины кластера
    на основе выбранных ролей. Результат — в папке generated/.

    Если в корне репозитория есть cluster.conf — IP и роли читаются
    из него автоматически. Иначе скрипт задаёт вопросы интерактивно.
.EXAMPLE
    .\scripts\setup-cluster.ps1
.EXAMPLE
    .\scripts\setup-cluster.ps1 -Config my-cluster.conf
#>

[CmdletBinding()]
param(
    [string]$Config = ""
)

$ErrorActionPreference = "Stop"
$HadoopVersion = "3.3.6"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$OutputDir = Join-Path $RepoRoot "generated"

# ─────────────────────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────────────────────

function Read-Validated {
    param(
        [string]$Prompt,
        [string]$Default = "",
        [scriptblock]$Check
    )
    while ($true) {
        $display = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
        $raw = Read-Host $display
        if (-not $raw -and $Default) { $raw = $Default }
        if ($raw -and (& $Check $raw)) { return $raw }
        Write-Host "  Некорректный ввод." -ForegroundColor Red
    }
}

# ─────────────────────────────────────────────────────────────
#  YAML service templates
# ─────────────────────────────────────────────────────────────

function Svc-Namenode {
    param([bool]$WithBuild)
    $build = ""
    if ($WithBuild) {
        $build = @"
    build:
      context: ..
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: `${HADOOP_VERSION:-$HadoopVersion}

"@
    }
    return @"
  namenode:
$build    image: *image
    container_name: namenode
    hostname: namenode
    environment:
      HADOOP_ROLE: namenode
    ports:
      - "9000:9000"
      - "9870:9870"
    volumes:
      - namenode_data:/data/hdfs/namenode
      - hadoop_logs:/opt/hadoop/logs
    extra_hosts: *extra_hosts
    restart: unless-stopped

"@
}

function Svc-SecondaryNamenode {
    param([bool]$WithBuild, [string[]]$Deps)
    $build = ""
    if ($WithBuild) {
        $build = @"
    build:
      context: ..
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: `${HADOOP_VERSION:-$HadoopVersion}

"@
    }
    $depBlock = ""
    if ($Deps.Count -gt 0) {
        $depBlock = "    depends_on:`n"
        foreach ($d in $Deps) { $depBlock += "      - $d`n" }
    }
    return @"
  secondarynamenode:
$build    image: *image
    container_name: secondarynamenode
    hostname: secondarynamenode
$depBlock    environment:
      HADOOP_ROLE: secondarynamenode
    ports:
      - "9868:9868"
    volumes:
      - secondary_data:/data/hdfs/secondary
      - hadoop_logs:/opt/hadoop/logs
    extra_hosts: *extra_hosts
    restart: unless-stopped

"@
}

function Svc-ResourceManager {
    param([bool]$WithBuild, [string[]]$Deps)
    $build = ""
    if ($WithBuild) {
        $build = @"
    build:
      context: ..
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: `${HADOOP_VERSION:-$HadoopVersion}

"@
    }
    $depBlock = ""
    if ($Deps.Count -gt 0) {
        $depBlock = "    depends_on:`n"
        foreach ($d in $Deps) { $depBlock += "      - $d`n" }
    }
    return @"
  resourcemanager:
$build    image: *image
    container_name: resourcemanager
    hostname: resourcemanager
$depBlock    environment:
      HADOOP_ROLE: resourcemanager
    ports:
      - "8030:8030"
      - "8031:8031"
      - "8032:8032"
      - "8033:8033"
      - "8088:8088"
    volumes:
      - hadoop_logs:/opt/hadoop/logs
    extra_hosts: *extra_hosts
    restart: unless-stopped

"@
}

function Svc-HistoryServer {
    param([bool]$WithBuild, [string[]]$Deps)
    $build = ""
    if ($WithBuild) {
        $build = @"
    build:
      context: ..
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: `${HADOOP_VERSION:-$HadoopVersion}

"@
    }
    $depBlock = ""
    if ($Deps.Count -gt 0) {
        $depBlock = "    depends_on:`n"
        foreach ($d in $Deps) { $depBlock += "      - $d`n" }
    }
    return @"
  historyserver:
$build    image: *image
    container_name: historyserver
    hostname: historyserver
$depBlock    environment:
      HADOOP_ROLE: historyserver
    ports:
      - "10020:10020"
      - "19888:19888"
    volumes:
      - hadoop_logs:/opt/hadoop/logs
    extra_hosts: *extra_hosts
    restart: unless-stopped

"@
}

function Svc-Datanode {
    param([bool]$WithBuild, [string]$WorkerName, [int]$HttpPort, [int]$XferPort, [int]$IpcPort, [string[]]$Deps)
    $build = ""
    if ($WithBuild) {
        $build = @"
    build:
      context: ..
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: `${HADOOP_VERSION:-$HadoopVersion}

"@
    }
    $depBlock = ""
    if ($Deps.Count -gt 0) {
        $depBlock = "    depends_on:`n"
        foreach ($d in $Deps) { $depBlock += "      - $d`n" }
    }
    return @"
  datanode:
$build    image: *image
    container_name: datanode
    hostname: `${NODE_NAME:-$WorkerName}
$depBlock    environment:
      HADOOP_ROLE: datanode
      NODE_NAME: `${NODE_NAME:-$WorkerName}
      DN_HTTP_PORT: `${DN_HTTP_PORT:-$HttpPort}
      DN_XFER_PORT: `${DN_XFER_PORT:-$XferPort}
      DN_IPC_PORT: `${DN_IPC_PORT:-$IpcPort}
    ports:
      - "`${DN_HTTP_PORT:-$($HttpPort)}:`${DN_HTTP_PORT:-$($HttpPort)}"
      - "`${DN_XFER_PORT:-$($XferPort)}:`${DN_XFER_PORT:-$($XferPort)}"
      - "`${DN_IPC_PORT:-$($IpcPort)}:`${DN_IPC_PORT:-$($IpcPort)}"
    volumes:
      - datanode_data:/data/hdfs/datanode
      - hadoop_logs:/opt/hadoop/logs
    extra_hosts: *extra_hosts
    restart: unless-stopped

"@
}

function Svc-NodeManager {
    param([string]$WorkerName, [string[]]$Deps)
    $depBlock = ""
    if ($Deps.Count -gt 0) {
        $depBlock = "    depends_on:`n"
        foreach ($d in $Deps) { $depBlock += "      - $d`n" }
    }
    return @"
  nodemanager:
    image: *image
    container_name: nodemanager
    hostname: `${NODE_NAME:-$WorkerName}
$depBlock    environment:
      HADOOP_ROLE: nodemanager
      NODE_NAME: `${NODE_NAME:-$WorkerName}
    ports:
      - "8040:8040"
      - "8041:8041"
      - "8042:8042"
      - "13562:13562"
      # Spark driver + block-manager (см. config/spark-defaults.conf).
      # В YARN cluster mode driver живёт в AM-контейнере на NodeManager,
      # поэтому фиксированные порты должны быть проброшены наружу: иначе
      # executor'ы с других нод не достучатся до spark://...@workerN:7077
      # и драйвер не дотянется до BlockManager executor'а на 7079.
      - "7077:7077"
      - "7078:7078"
      - "7079:7079"
      - "32000:32000"
      - "32001:32001"
    volumes:
      - hadoop_logs:/opt/hadoop/logs
    extra_hosts: *extra_hosts
    restart: unless-stopped

"@
}

# ─────────────────────────────────────────────────────────────
#  Config file parser
# ─────────────────────────────────────────────────────────────

$RoleMap = @{
    "namenode"          = 1
    "secondarynamenode" = 2
    "resourcemanager"   = 3
    "historyserver"     = 4
    "datanode"          = 5
}

function Parse-ClusterConf {
    param([string]$Path)
    $result = @()
    $idx = 0
    foreach ($line in (Get-Content $Path)) {
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }

        if ($line -match '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+(.+)$') {
            $ip = $Matches[1]
            $rolesRaw = $Matches[2].Trim()
            $idx++

            $selectedRoles = @()
            foreach ($r in ($rolesRaw -split ',')) {
                $r = $r.Trim().ToLower()
                if ($RoleMap.ContainsKey($r)) {
                    $selectedRoles += $RoleMap[$r]
                } else {
                    Write-Host "  ОШИБКА: неизвестная роль '$r' в строке: $line" -ForegroundColor Red
                    exit 1
                }
            }
            $selectedRoles = @($selectedRoles | Sort-Object -Unique)

            $result += [PSCustomObject]@{
                Index      = $idx
                IP         = $ip
                Roles      = $selectedRoles
                WorkerName = $null
            }
        } else {
            Write-Host "  ОШИБКА: неверный формат строки: $line" -ForegroundColor Red
            Write-Host "  Ожидается: IP_АДРЕС  роль1,роль2,..." -ForegroundColor Yellow
            exit 1
        }
    }
    return $result
}

# ─────────────────────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Мастер настройки Hadoop-кластера" -ForegroundColor Cyan
Write-Host "  Hadoop $HadoopVersion  |  Docker  |  Multi-host" -ForegroundColor DarkCyan
Write-Host "================================================" -ForegroundColor Cyan

# ── Determine config file path ──
$confFile = ""
if ($Config) {
    if (Test-Path $Config) {
        $confFile = $Config
    } else {
        Write-Host "  ОШИБКА: файл $Config не найден" -ForegroundColor Red
        exit 1
    }
} else {
    $defaultConf = Join-Path $RepoRoot "cluster.conf"
    if (Test-Path $defaultConf) { $confFile = $defaultConf }
}

$machines = @()

if ($confFile) {
    # ── Read from config file ──
    Write-Host ""
    Write-Host ">>> Читаю конфигурацию из $confFile" -ForegroundColor Cyan
    $machines = @(Parse-ClusterConf $confFile)

    if ($machines.Count -lt 2) {
        Write-Host "  ОШИБКА: в конфиге меньше 2 машин" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    foreach ($m in $machines) {
        $names = $m.Roles | ForEach-Object {
            switch ($_) { 1 {"NameNode"} 2 {"SNN"} 3 {"ResourceManager"} 4 {"HistoryServer"} 5 {"DataNode+NM"} }
        }
        Write-Host "  $($m.IP)  ->  $($names -join ', ')" -ForegroundColor Green
    }
} else {
    # ── Interactive mode ──
    Write-Host ""
    Write-Host ">>> cluster.conf не найден — интерактивный режим" -ForegroundColor Yellow
    Write-Host "    (создайте cluster.conf из cluster.conf.example для автоматического режима)" -ForegroundColor Gray
    Write-Host ""
    Write-Host ">>> Шаг 1: Количество машин" -ForegroundColor Cyan

    $machineCount = [int](Read-Validated `
        -Prompt "Сколько машин в кластере?" `
        -Default "3" `
        -Check { param($v) $v -match '^\d+$' -and [int]$v -ge 2 -and [int]$v -le 20 })

    Write-Host ""
    Write-Host ">>> Шаг 2: Информация о каждой машине" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Роли:" -ForegroundColor Gray
    Write-Host "    1) NameNode              — хранение метаданных HDFS (нужен ровно 1)" -ForegroundColor Gray
    Write-Host "    2) SecondaryNameNode     — чекпоинт NameNode" -ForegroundColor Gray
    Write-Host "    3) ResourceManager       — управление YARN (нужен ровно 1)" -ForegroundColor Gray
    Write-Host "    4) HistoryServer         — история MapReduce-задач" -ForegroundColor Gray
    Write-Host "    5) DataNode + NodeManager — хранение данных + выполнение задач" -ForegroundColor Gray
    Write-Host ""

    for ($i = 1; $i -le $machineCount; $i++) {
        Write-Host "  --- Машина $i из $machineCount ---" -ForegroundColor Yellow

        $ip = Read-Validated `
            -Prompt "    IP-адрес" `
            -Check { param($v) $v -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' }

        $roleStr = Read-Validated `
            -Prompt "    Роли (номера через запятую, напр. 1,2,3,4 или 5)" `
            -Check { param($v) $v -match '^[1-5](,\s*[1-5])*$' }

        $selectedRoles = @($roleStr -split ',' | ForEach-Object { [int]$_.Trim() } | Sort-Object -Unique)

        $names = $selectedRoles | ForEach-Object {
            switch ($_) { 1 {"NameNode"} 2 {"SNN"} 3 {"ResourceManager"} 4 {"HistoryServer"} 5 {"DataNode+NM"} }
        }
        Write-Host "    -> $($names -join ', ')" -ForegroundColor Green
        Write-Host ""

        $machines += [PSCustomObject]@{
            Index      = $i
            IP         = $ip
            Roles      = $selectedRoles
            WorkerName = $null
        }
    }
}

# ── Validate ──
Write-Host ""
Write-Host ">>> Проверка конфигурации" -ForegroundColor Cyan

$nnCount  = @($machines | Where-Object { $_.Roles -contains 1 }).Count
$rmCount  = @($machines | Where-Object { $_.Roles -contains 3 }).Count
$dnCount  = @($machines | Where-Object { $_.Roles -contains 5 }).Count

$errors = @()
if ($nnCount -ne 1)  { $errors += "Нужен ровно 1 NameNode (сейчас: $nnCount)" }
if ($rmCount -ne 1)  { $errors += "Нужен ровно 1 ResourceManager (сейчас: $rmCount)" }
if ($dnCount -lt 1)  { $errors += "Нужен минимум 1 DataNode+NodeManager (сейчас: $dnCount)" }

if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Host "  ОШИБКА: $e" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Запустите скрипт заново." -ForegroundColor Yellow
    exit 1
}

# ── 4. Assign worker names ──
$wIdx = 1
foreach ($m in ($machines | Where-Object { $_.Roles -contains 5 })) {
    $m.WorkerName = "worker$wIdx"
    $wIdx++
}

$nnMachine  = $machines | Where-Object { $_.Roles -contains 1 } | Select-Object -First 1
$snnMachine = $machines | Where-Object { $_.Roles -contains 2 } | Select-Object -First 1
$rmMachine  = $machines | Where-Object { $_.Roles -contains 3 } | Select-Object -First 1
$hsMachine  = $machines | Where-Object { $_.Roles -contains 4 } | Select-Object -First 1
$dnMachines = @($machines | Where-Object { $_.Roles -contains 5 })

$nnIP  = $nnMachine.IP
$snnIP = if ($snnMachine) { $snnMachine.IP } else { $nnIP }
$rmIP  = $rmMachine.IP
$hsIP  = if ($hsMachine) { $hsMachine.IP } else { $rmIP }

Write-Host "  NameNode:           $nnIP" -ForegroundColor Green
if ($snnMachine) {
    Write-Host "  SecondaryNameNode:  $snnIP" -ForegroundColor Green
}
Write-Host "  ResourceManager:    $rmIP" -ForegroundColor Green
if ($hsMachine) {
    Write-Host "  HistoryServer:      $hsIP" -ForegroundColor Green
}
foreach ($w in $dnMachines) {
    Write-Host "  $($w.WorkerName):            $($w.IP)" -ForegroundColor Green
}

# ── 5. Build extra_hosts ──
$extraHosts = @()
$extraHosts += "namenode:$nnIP"
$extraHosts += "secondarynamenode:$snnIP"
$extraHosts += "resourcemanager:$rmIP"
$extraHosts += "historyserver:$hsIP"
foreach ($w in $dnMachines) {
    $extraHosts += "$($w.WorkerName):$($w.IP)"
}

$extraHostsYaml = ($extraHosts | ForEach-Object { "  - `"$_`"" }) -join "`n"

# ── 6. Generate files ──
Write-Host ""
Write-Host ">>> Шаг 4: Генерация файлов" -ForegroundColor Cyan

if (Test-Path $OutputDir) {
    Remove-Item -Recurse -Force $OutputDir
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

foreach ($m in $machines) {
    # Label for file naming
    $label = if ($m.WorkerName) { $m.WorkerName } else {
        $parts = @()
        if ($m.Roles -contains 1) { $parts += "nn" }
        if ($m.Roles -contains 2) { $parts += "snn" }
        if ($m.Roles -contains 3) { $parts += "rm" }
        if ($m.Roles -contains 4) { $parts += "hs" }
        if ($parts.Count -gt 0) { $parts -join "-" } else { "node$($m.Index)" }
    }

    # ── .env ──
    $envLines = @(
        "# Сгенерировано setup-cluster.ps1"
        "# Машина: $label ($($m.IP))"
        ""
        "HADOOP_VERSION=$HadoopVersion"
    )

    if ($m.WorkerName) {
        $workerNum = [int]($m.WorkerName -replace 'worker','')
        $offset = ($workerNum - 1) * 10
        $envLines += ""
        $envLines += "NODE_NAME=$($m.WorkerName)"
        $envLines += "DN_HTTP_PORT=$((9864 + $offset))"
        $envLines += "DN_XFER_PORT=$((9866 + $offset))"
        $envLines += "DN_IPC_PORT=$((9867 + $offset))"
    }

    $envPath = Join-Path $OutputDir "$label.env"
    $envLines -join "`n" | Set-Content -Path $envPath -Encoding UTF8 -NoNewline

    # ── docker-compose.yml ──
    $yaml = @"
# Сгенерировано setup-cluster.ps1
# Машина: $label ($($m.IP))

x-extra-hosts: &extra_hosts
$extraHostsYaml

x-image: &image clustrer-hadoop:`${HADOOP_VERSION:-$HadoopVersion}

services:

"@

    $volumeSet = [System.Collections.Generic.HashSet[string]]::new()
    $needBuild = $true   # first service gets the build: block

    # NameNode
    if ($m.Roles -contains 1) {
        $yaml += Svc-Namenode -WithBuild $needBuild
        $needBuild = $false
        [void]$volumeSet.Add("namenode_data")
        [void]$volumeSet.Add("hadoop_logs")
    }

    # SecondaryNameNode
    if ($m.Roles -contains 2) {
        $deps = @(); if ($m.Roles -contains 1) { $deps = @("namenode") }
        $yaml += Svc-SecondaryNamenode -WithBuild $needBuild -Deps $deps
        $needBuild = $false
        [void]$volumeSet.Add("secondary_data")
        [void]$volumeSet.Add("hadoop_logs")
    }

    # ResourceManager
    if ($m.Roles -contains 3) {
        $deps = @(); if ($m.Roles -contains 1) { $deps = @("namenode") }
        $yaml += Svc-ResourceManager -WithBuild $needBuild -Deps $deps
        $needBuild = $false
        [void]$volumeSet.Add("hadoop_logs")
    }

    # HistoryServer
    if ($m.Roles -contains 4) {
        $deps = @(); if ($m.Roles -contains 3) { $deps = @("resourcemanager") }
        $yaml += Svc-HistoryServer -WithBuild $needBuild -Deps $deps
        $needBuild = $false
        [void]$volumeSet.Add("hadoop_logs")
    }

    # DataNode + NodeManager
    if ($m.Roles -contains 5) {
        $wn = $m.WorkerName
        $workerNum = [int]($wn -replace 'worker','')
        $offset = ($workerNum - 1) * 10
        $httpPort = 9864 + $offset
        $xferPort = 9866 + $offset
        $ipcPort  = 9867 + $offset

        $dnDeps = @(); if ($m.Roles -contains 1) { $dnDeps = @("namenode") }
        $yaml += Svc-Datanode -WithBuild $needBuild -WorkerName $wn `
            -HttpPort $httpPort -XferPort $xferPort -IpcPort $ipcPort -Deps $dnDeps
        $needBuild = $false
        [void]$volumeSet.Add("datanode_data")
        [void]$volumeSet.Add("hadoop_logs")

        $nmDeps = @("datanode")
        if ($m.Roles -contains 3) { $nmDeps += "resourcemanager" }
        $yaml += Svc-NodeManager -WorkerName $wn -Deps $nmDeps
    }

    # Volumes
    $yaml += "volumes:`n"
    foreach ($vn in ($volumeSet | Sort-Object)) {
        $yaml += "  $($vn):`n"
    }

    $composePath = Join-Path $OutputDir "$label.yml"
    $yaml | Set-Content -Path $composePath -Encoding UTF8 -NoNewline

    Write-Host "  $label.yml  +  $label.env" -ForegroundColor Green
}

# ── 7. Update .gitignore ──
$gitignorePath = Join-Path $RepoRoot ".gitignore"
$gitignoreContent = if (Test-Path $gitignorePath) { Get-Content $gitignorePath -Raw } else { "" }
if ($gitignoreContent -notmatch 'generated/') {
    Add-Content -Path $gitignorePath -Value "`ngenerated/"
}

# ── 8. Instructions ──
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Развёртывание кластера" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "На КАЖДОЙ машине должен быть клонирован репозиторий." -ForegroundColor White
Write-Host "Скопируйте соответствующие файлы и запускайте в таком порядке:" -ForegroundColor White
Write-Host ""

$order = 1

# NameNode first
$nnLabel = if ($nnMachine.WorkerName) { $nnMachine.WorkerName } else {
    $p = @(); if ($nnMachine.Roles -contains 1) { $p += "nn" }; if ($nnMachine.Roles -contains 2) { $p += "snn" }
    if ($nnMachine.Roles -contains 3) { $p += "rm" }; if ($nnMachine.Roles -contains 4) { $p += "hs" }; $p -join "-"
}
Write-Host "  $order. Машина с NameNode ($($nnMachine.IP)):" -ForegroundColor Yellow
Write-Host "     copy generated\$nnLabel.env .env" -ForegroundColor White
Write-Host "     docker compose -f generated\$nnLabel.yml up -d --build" -ForegroundColor White
Write-Host ""
$order++

# Other master services (SNN, RM, HS) on different machines
foreach ($m in $machines) {
    if ($m -eq $nnMachine) { continue }
    if ($m.Roles -contains 5 -and -not ($m.Roles -contains 2 -or $m.Roles -contains 3 -or $m.Roles -contains 4)) { continue }

    $lbl = if ($m.WorkerName) { $m.WorkerName } else {
        $p = @(); if ($m.Roles -contains 1) { $p += "nn" }; if ($m.Roles -contains 2) { $p += "snn" }
        if ($m.Roles -contains 3) { $p += "rm" }; if ($m.Roles -contains 4) { $p += "hs" }; $p -join "-"
    }
    $rn = ($m.Roles | Where-Object { $_ -ne 5 } | ForEach-Object {
        switch ($_) { 1 {"NN"} 2 {"SNN"} 3 {"RM"} 4 {"HS"} }
    }) -join "+"

    if ($rn) {
        Write-Host "  $order. Машина с $rn ($($m.IP)):" -ForegroundColor Yellow
        Write-Host "     copy generated\$lbl.env .env" -ForegroundColor White
        Write-Host "     docker compose -f generated\$lbl.yml up -d --build" -ForegroundColor White
        Write-Host ""
        $order++
    }
}

# Workers
foreach ($w in $dnMachines) {
    Write-Host "  $order. $($w.WorkerName) ($($w.IP)):" -ForegroundColor Yellow
    Write-Host "     copy generated\$($w.WorkerName).env .env" -ForegroundColor White
    Write-Host "     docker compose -f generated\$($w.WorkerName).yml up -d --build" -ForegroundColor White
    Write-Host ""
    $order++
}

Write-Host "После запуска всех машин проверьте кластер с NameNode-машины:" -ForegroundColor White
Write-Host "  docker exec namenode hdfs dfsadmin -report" -ForegroundColor Gray
Write-Host "  docker exec resourcemanager yarn node -list" -ForegroundColor Gray
Write-Host ""
