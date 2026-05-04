<#
.SYNOPSIS
    Запуск Hadoop-кластера на этой машине.
.DESCRIPTION
    Читает cluster.conf, определяет роль этой машины по локальному IP,
    генерирует docker-compose.yml и .env, запускает контейнеры.

    На каждом ноуте должен быть одинаковый cluster.conf.
    Запустите start.bat на каждом ноуте — и кластер поднимется.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$HadoopVersion = "3.3.6"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

# ─────────────────────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────────────────────

$RoleMap = @{
    "namenode"          = 1
    "secondarynamenode" = 2
    "resourcemanager"   = 3
    "historyserver"     = 4
    "datanode"          = 5
}

$RoleNames = @{
    1 = "NameNode"
    2 = "SecondaryNameNode"
    3 = "ResourceManager"
    4 = "HistoryServer"
    5 = "DataNode+NodeManager"
}

function Get-LocalIPs {
    $ips = @()
    try {
        $adapters = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -ne "127.0.0.1" }
        foreach ($a in $adapters) { $ips += $a.IPAddress }
    } catch {
        # Fallback: parse ipconfig
        $output = ipconfig 2>$null
        foreach ($line in $output) {
            if ($line -match 'IPv4.*:\s*(\d+\.\d+\.\d+\.\d+)') {
                $ip = $Matches[1]
                if ($ip -ne "127.0.0.1") { $ips += $ip }
            }
        }
    }
    return $ips
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
      context: .
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: $HadoopVersion

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
      context: .
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: $HadoopVersion

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
      context: .
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: $HadoopVersion

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
      context: .
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: $HadoopVersion

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
      context: .
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: $HadoopVersion

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
    hostname: $WorkerName
$depBlock    environment:
      HADOOP_ROLE: datanode
      NODE_NAME: $WorkerName
      DN_HTTP_PORT: $HttpPort
      DN_XFER_PORT: $XferPort
      DN_IPC_PORT: $IpcPort
    ports:
      - "$($HttpPort):$($HttpPort)"
      - "$($XferPort):$($XferPort)"
      - "$($IpcPort):$($IpcPort)"
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
    hostname: $WorkerName
$depBlock    environment:
      HADOOP_ROLE: nodemanager
      NODE_NAME: $WorkerName
    ports:
      - "8040:8040"
      - "8041:8041"
      - "8042:8042"
      - "13562:13562"
      - "32000:32000"
      - "32001:32001"
    volumes:
      - hadoop_logs:/opt/hadoop/logs
    extra_hosts: *extra_hosts
    restart: unless-stopped

"@
}

# ─────────────────────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Hadoop-кластер — запуск" -ForegroundColor Cyan
Write-Host "  Hadoop $HadoopVersion  |  Docker" -ForegroundColor DarkCyan
Write-Host "================================================" -ForegroundColor Cyan

# ── 1. Read cluster.conf ──
$confPath = Join-Path $RepoRoot "cluster.conf"
if (-not (Test-Path $confPath)) {
    Write-Host ""
    Write-Host "  ОШИБКА: cluster.conf не найден!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Скопируйте шаблон и впишите IP:" -ForegroundColor Yellow
    Write-Host "    copy cluster.conf.example cluster.conf" -ForegroundColor White
    Write-Host "    notepad cluster.conf" -ForegroundColor White
    Write-Host ""
    exit 1
}

# Parse config
$allMachines = @()
$idx = 0
foreach ($line in (Get-Content $confPath)) {
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
                Write-Host "  ОШИБКА: неизвестная роль '$r'" -ForegroundColor Red
                exit 1
            }
        }
        $selectedRoles = @($selectedRoles | Sort-Object -Unique)

        $allMachines += [PSCustomObject]@{
            IP         = $ip
            Roles      = $selectedRoles
            WorkerName = $null
        }
    } else {
        Write-Host "  ОШИБКА: неверный формат: $line" -ForegroundColor Red
        exit 1
    }
}

if ($allMachines.Count -lt 2) {
    Write-Host "  ОШИБКА: нужно минимум 2 машины в cluster.conf" -ForegroundColor Red
    exit 1
}

# ── 2. Validate ──
$nnCount  = @($allMachines | Where-Object { $_.Roles -contains 1 }).Count
$rmCount  = @($allMachines | Where-Object { $_.Roles -contains 3 }).Count
$dnCount  = @($allMachines | Where-Object { $_.Roles -contains 5 }).Count

if ($nnCount -ne 1) { Write-Host "  ОШИБКА: нужен ровно 1 NameNode (сейчас: $nnCount)" -ForegroundColor Red; exit 1 }
if ($rmCount -ne 1) { Write-Host "  ОШИБКА: нужен ровно 1 ResourceManager (сейчас: $rmCount)" -ForegroundColor Red; exit 1 }
if ($dnCount -lt 1) { Write-Host "  ОШИБКА: нужен минимум 1 DataNode (сейчас: $dnCount)" -ForegroundColor Red; exit 1 }

# ── 3. Assign worker names ──
$wIdx = 1
foreach ($m in ($allMachines | Where-Object { $_.Roles -contains 5 })) {
    $m.WorkerName = "worker$wIdx"
    $wIdx++
}

# ── 4. Detect local machine ──
Write-Host ""
$localIPs = Get-LocalIPs
Write-Host "  Локальные IP: $($localIPs -join ', ')" -ForegroundColor Gray

$myMachine = $null
$myIndex = -1
for ($i = 0; $i -lt $allMachines.Count; $i++) {
    if ($localIPs -contains $allMachines[$i].IP) {
        $myMachine = $allMachines[$i]
        $myIndex = $i
        break
    }
}

if (-not $myMachine) {
    Write-Host ""
    Write-Host "  ОШИБКА: ни один IP из cluster.conf не совпал с этой машиной!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  IP в cluster.conf:" -ForegroundColor Yellow
    foreach ($m in $allMachines) {
        Write-Host "    $($m.IP)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  IP этой машины:" -ForegroundColor Yellow
    foreach ($ip in $localIPs) {
        Write-Host "    $ip" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  Проверьте IP в cluster.conf (ipconfig)" -ForegroundColor Yellow
    exit 1
}

$roleLabels = $myMachine.Roles | ForEach-Object { $RoleNames[$_] }
Write-Host "  Эта машина: $($myMachine.IP) -> $($roleLabels -join ', ')" -ForegroundColor Green

# ── 5. Build extra_hosts ──
$nnMachine  = $allMachines | Where-Object { $_.Roles -contains 1 } | Select-Object -First 1
$snnMachine = $allMachines | Where-Object { $_.Roles -contains 2 } | Select-Object -First 1
$rmMachine  = $allMachines | Where-Object { $_.Roles -contains 3 } | Select-Object -First 1
$hsMachine  = $allMachines | Where-Object { $_.Roles -contains 4 } | Select-Object -First 1

$snnIP = if ($snnMachine) { $snnMachine.IP } else { $nnMachine.IP }
$hsIP  = if ($hsMachine)  { $hsMachine.IP }  else { $rmMachine.IP }

$extraHosts = @()
$extraHosts += "  - `"namenode:$($nnMachine.IP)`""
$extraHosts += "  - `"secondarynamenode:$snnIP`""
$extraHosts += "  - `"resourcemanager:$($rmMachine.IP)`""
$extraHosts += "  - `"historyserver:$hsIP`""
foreach ($m in $allMachines) {
    if ($m.WorkerName) {
        $extraHosts += "  - `"$($m.WorkerName):$($m.IP)`""
    }
}
$extraHostsYaml = $extraHosts -join "`n"

# ── 6. Generate docker-compose.yml ──
$composeFile = Join-Path $RepoRoot "docker-compose.generated.yml"
$roles = $myMachine.Roles

$yaml = @"
# Сгенерировано start.ps1 для $($myMachine.IP)

x-extra-hosts: &extra_hosts
$extraHostsYaml

x-image: &image clustrer-hadoop:$HadoopVersion

services:

"@

$needBuild = $true
$volumeList = @()

# NameNode
if ($roles -contains 1) {
    $yaml += Svc-Namenode -WithBuild $needBuild
    $needBuild = $false
    $volumeList += "namenode_data"
    $volumeList += "hadoop_logs"
}

# SecondaryNameNode
if ($roles -contains 2) {
    $deps = @()
    if ($roles -contains 1) { $deps += "namenode" }
    $yaml += Svc-SecondaryNamenode -WithBuild $needBuild -Deps $deps
    $needBuild = $false
    $volumeList += "secondary_data"
    $volumeList += "hadoop_logs"
}

# ResourceManager
if ($roles -contains 3) {
    $deps = @()
    if ($roles -contains 1) { $deps += "namenode" }
    $yaml += Svc-ResourceManager -WithBuild $needBuild -Deps $deps
    $needBuild = $false
    $volumeList += "hadoop_logs"
}

# HistoryServer
if ($roles -contains 4) {
    $deps = @()
    if ($roles -contains 3) { $deps += "resourcemanager" }
    $yaml += Svc-HistoryServer -WithBuild $needBuild -Deps $deps
    $needBuild = $false
    $volumeList += "hadoop_logs"
}

# DataNode + NodeManager
if ($roles -contains 5) {
    $wn = $myMachine.WorkerName
    $workerNum = [int]($wn -replace 'worker','')
    $offset = ($workerNum - 1) * 10
    $httpPort = 9864 + $offset
    $xferPort = 9866 + $offset
    $ipcPort  = 9867 + $offset

    $dnDeps = @()
    if ($roles -contains 1) { $dnDeps += "namenode" }
    $yaml += Svc-Datanode -WithBuild $needBuild -WorkerName $wn -HttpPort $httpPort -XferPort $xferPort -IpcPort $ipcPort -Deps $dnDeps
    $needBuild = $false
    $volumeList += "datanode_data"
    $volumeList += "hadoop_logs"

    $nmDeps = @("datanode")
    if ($roles -contains 3) { $nmDeps += "resourcemanager" }
    $yaml += Svc-NodeManager -WorkerName $wn -Deps $nmDeps
}

# Volumes
$uniqueVolumes = $volumeList | Sort-Object -Unique
$yaml += "volumes:`n"
foreach ($v in $uniqueVolumes) {
    $yaml += "  ${v}:`n"
}

# Write file (UTF-8 no BOM)
[System.IO.File]::WriteAllText($composeFile, $yaml, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "  Compose: docker-compose.generated.yml" -ForegroundColor Gray

# ── 7. Docker compose up ──
Write-Host ""
Write-Host ">>> Запуск контейнеров..." -ForegroundColor Cyan
Write-Host ""

Push-Location $RepoRoot
try {
    docker compose -f docker-compose.generated.yml up -d --build
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  ОШИБКА: docker compose завершился с ошибкой" -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Контейнеры запущены!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""

if ($roles -contains 1) {
    Write-Host "  Ожидайте ~30 сек для запуска NameNode, затем:" -ForegroundColor Yellow
    Write-Host "    docker exec namenode hdfs dfsadmin -report" -ForegroundColor White
}
if ($roles -contains 3) {
    Write-Host "    docker exec resourcemanager yarn node -list" -ForegroundColor White
}
if ($roles -contains 5) {
    Write-Host "  DataNode ($($myMachine.WorkerName)) запущен" -ForegroundColor Green
}
Write-Host ""
