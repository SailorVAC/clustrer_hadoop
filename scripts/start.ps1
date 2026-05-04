<#
.SYNOPSIS
    Zapusk Hadoop-klastera na etoj mashine.
.DESCRIPTION
    Chitaet cluster.conf, opredelyaet rol etoj mashiny po lokalnomu IP,
    generiruet docker-compose.yml, zapuskaet kontejnery.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$HadoopVersion = "3.3.6"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

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
        $output = ipconfig 2>$null
        foreach ($ln in $output) {
            if ($ln -match 'IPv4.*:\s*(\d+\.\d+\.\d+\.\d+)') {
                $foundIp = $Matches[1]
                if ($foundIp -ne "127.0.0.1") { $ips += $foundIp }
            }
        }
    }
    return $ips
}

function Build-Block {
    $lines = @()
    $lines += "    build:"
    $lines += "      context: ."
    $lines += "      dockerfile: Dockerfile"
    $lines += "      args:"
    $lines += "        HADOOP_VERSION: $HadoopVersion"
    return ($lines -join "`n") + "`n"
}

function Depends-Block {
    param([string[]]$Deps)
    if ($Deps.Count -eq 0) { return "" }
    $lines = @("    depends_on:")
    foreach ($d in $Deps) { $lines += "      - $d" }
    return ($lines -join "`n") + "`n"
}

function Svc-Namenode {
    param([bool]$WithBuild)
    $lines = @()
    $lines += "  namenode:"
    if ($WithBuild) { $lines += Build-Block }
    $lines += "    image: *image"
    $lines += "    container_name: namenode"
    $lines += "    hostname: namenode"
    $lines += "    environment:"
    $lines += "      HADOOP_ROLE: namenode"
    $lines += "    ports:"
    $lines += '      - "9000:9000"'
    $lines += '      - "9870:9870"'
    $lines += "    volumes:"
    $lines += "      - namenode_data:/data/hdfs/namenode"
    $lines += "      - hadoop_logs:/opt/hadoop/logs"
    $lines += "    extra_hosts: *extra_hosts"
    $lines += "    restart: unless-stopped"
    $lines += ""
    return ($lines -join "`n") + "`n"
}

function Svc-SecondaryNamenode {
    param([bool]$WithBuild, [string[]]$Deps)
    $lines = @()
    $lines += "  secondarynamenode:"
    if ($WithBuild) { $lines += Build-Block }
    $lines += "    image: *image"
    $lines += "    container_name: secondarynamenode"
    $lines += "    hostname: secondarynamenode"
    if ($Deps.Count -gt 0) { $lines += Depends-Block -Deps $Deps }
    $lines += "    environment:"
    $lines += "      HADOOP_ROLE: secondarynamenode"
    $lines += "    ports:"
    $lines += '      - "9868:9868"'
    $lines += "    volumes:"
    $lines += "      - secondary_data:/data/hdfs/secondary"
    $lines += "      - hadoop_logs:/opt/hadoop/logs"
    $lines += "    extra_hosts: *extra_hosts"
    $lines += "    restart: unless-stopped"
    $lines += ""
    return ($lines -join "`n") + "`n"
}

function Svc-ResourceManager {
    param([bool]$WithBuild, [string[]]$Deps)
    $lines = @()
    $lines += "  resourcemanager:"
    if ($WithBuild) { $lines += Build-Block }
    $lines += "    image: *image"
    $lines += "    container_name: resourcemanager"
    $lines += "    hostname: resourcemanager"
    if ($Deps.Count -gt 0) { $lines += Depends-Block -Deps $Deps }
    $lines += "    environment:"
    $lines += "      HADOOP_ROLE: resourcemanager"
    $lines += "    ports:"
    $lines += '      - "8030:8030"'
    $lines += '      - "8031:8031"'
    $lines += '      - "8032:8032"'
    $lines += '      - "8033:8033"'
    $lines += '      - "8088:8088"'
    $lines += "    volumes:"
    $lines += "      - hadoop_logs:/opt/hadoop/logs"
    $lines += "    extra_hosts: *extra_hosts"
    $lines += "    restart: unless-stopped"
    $lines += ""
    return ($lines -join "`n") + "`n"
}

function Svc-HistoryServer {
    param([bool]$WithBuild, [string[]]$Deps)
    $lines = @()
    $lines += "  historyserver:"
    if ($WithBuild) { $lines += Build-Block }
    $lines += "    image: *image"
    $lines += "    container_name: historyserver"
    $lines += "    hostname: historyserver"
    if ($Deps.Count -gt 0) { $lines += Depends-Block -Deps $Deps }
    $lines += "    environment:"
    $lines += "      HADOOP_ROLE: historyserver"
    $lines += "    ports:"
    $lines += '      - "10020:10020"'
    $lines += '      - "19888:19888"'
    $lines += "    volumes:"
    $lines += "      - hadoop_logs:/opt/hadoop/logs"
    $lines += "    extra_hosts: *extra_hosts"
    $lines += "    restart: unless-stopped"
    $lines += ""
    return ($lines -join "`n") + "`n"
}

function Svc-Datanode {
    param([bool]$WithBuild, [string]$WorkerName, [int]$HttpPort, [int]$XferPort, [int]$IpcPort, [string[]]$Deps)
    $lines = @()
    $lines += "  datanode:"
    if ($WithBuild) { $lines += Build-Block }
    $lines += "    image: *image"
    $lines += "    container_name: datanode"
    $lines += "    hostname: $WorkerName"
    if ($Deps.Count -gt 0) { $lines += Depends-Block -Deps $Deps }
    $lines += "    environment:"
    $lines += "      HADOOP_ROLE: datanode"
    $lines += "      NODE_NAME: $WorkerName"
    $lines += "      DN_HTTP_PORT: $HttpPort"
    $lines += "      DN_XFER_PORT: $XferPort"
    $lines += "      DN_IPC_PORT: $IpcPort"
    $lines += "    ports:"
    $lines += "      - `"$($HttpPort):$($HttpPort)`""
    $lines += "      - `"$($XferPort):$($XferPort)`""
    $lines += "      - `"$($IpcPort):$($IpcPort)`""
    $lines += "    volumes:"
    $lines += "      - datanode_data:/data/hdfs/datanode"
    $lines += "      - hadoop_logs:/opt/hadoop/logs"
    $lines += "    extra_hosts: *extra_hosts"
    $lines += "    restart: unless-stopped"
    $lines += ""
    return ($lines -join "`n") + "`n"
}

function Svc-NodeManager {
    param([string]$WorkerName, [string[]]$Deps)
    $lines = @()
    $lines += "  nodemanager:"
    $lines += "    image: *image"
    $lines += "    container_name: nodemanager"
    $lines += "    hostname: $WorkerName"
    if ($Deps.Count -gt 0) { $lines += Depends-Block -Deps $Deps }
    $lines += "    environment:"
    $lines += "      HADOOP_ROLE: nodemanager"
    $lines += "      NODE_NAME: $WorkerName"
    $lines += "    ports:"
    $lines += '      - "8040:8040"'
    $lines += '      - "8041:8041"'
    $lines += '      - "8042:8042"'
    $lines += '      - "13562:13562"'
    $lines += '      - "32000:32000"'
    $lines += '      - "32001:32001"'
    $lines += "    volumes:"
    $lines += "      - hadoop_logs:/opt/hadoop/logs"
    $lines += "    extra_hosts: *extra_hosts"
    $lines += "    restart: unless-stopped"
    $lines += ""
    return ($lines -join "`n") + "`n"
}

# =============================================
#  Main
# =============================================

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Hadoop cluster - start" -ForegroundColor Cyan
Write-Host "  Hadoop $HadoopVersion  |  Docker" -ForegroundColor DarkCyan
Write-Host "================================================" -ForegroundColor Cyan

# -- 1. Read cluster.conf --
$confPath = Join-Path $RepoRoot "cluster.conf"
if (-not (Test-Path $confPath)) {
    Write-Host ""
    Write-Host "  ERROR: cluster.conf not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Copy the template and fill in IPs:" -ForegroundColor Yellow
    Write-Host "    copy cluster.conf.example cluster.conf" -ForegroundColor White
    Write-Host "    notepad cluster.conf" -ForegroundColor White
    Write-Host ""
    exit 1
}

$allMachines = @()
$idx = 0
foreach ($cline in (Get-Content $confPath)) {
    $cline = $cline.Trim()
    if (-not $cline -or $cline.StartsWith('#')) { continue }

    if ($cline -match '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+(.+)$') {
        $ip = $Matches[1]
        $rolesRaw = $Matches[2].Trim()
        $idx++

        $selectedRoles = @()
        foreach ($r in ($rolesRaw -split ',')) {
            $r = $r.Trim().ToLower()
            if ($RoleMap.ContainsKey($r)) {
                $selectedRoles += $RoleMap[$r]
            } else {
                Write-Host "  ERROR: unknown role '$r'" -ForegroundColor Red
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
        Write-Host "  ERROR: invalid format: $cline" -ForegroundColor Red
        exit 1
    }
}

if ($allMachines.Count -lt 2) {
    Write-Host "  ERROR: need at least 2 machines in cluster.conf" -ForegroundColor Red
    exit 1
}

# -- 2. Validate --
$nnCount  = @($allMachines | Where-Object { $_.Roles -contains 1 }).Count
$rmCount  = @($allMachines | Where-Object { $_.Roles -contains 3 }).Count
$dnCount  = @($allMachines | Where-Object { $_.Roles -contains 5 }).Count

if ($nnCount -ne 1) { Write-Host "  ERROR: need exactly 1 NameNode (got: $nnCount)" -ForegroundColor Red; exit 1 }
if ($rmCount -ne 1) { Write-Host "  ERROR: need exactly 1 ResourceManager (got: $rmCount)" -ForegroundColor Red; exit 1 }
if ($dnCount -lt 1) { Write-Host "  ERROR: need at least 1 DataNode (got: $dnCount)" -ForegroundColor Red; exit 1 }

# -- 3. Assign worker names --
$wIdx = 1
foreach ($m in ($allMachines | Where-Object { $_.Roles -contains 5 })) {
    $m.WorkerName = "worker$wIdx"
    $wIdx++
}

# -- 4. Detect local machine --
Write-Host ""
$localIPs = Get-LocalIPs
Write-Host "  Local IPs: $($localIPs -join ', ')" -ForegroundColor Gray

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
    Write-Host "  ERROR: no IP from cluster.conf matches this machine!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  IPs in cluster.conf:" -ForegroundColor Yellow
    foreach ($m in $allMachines) {
        Write-Host "    $($m.IP)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  This machine IPs:" -ForegroundColor Yellow
    foreach ($lip in $localIPs) {
        Write-Host "    $lip" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  Check IPs in cluster.conf (ipconfig)" -ForegroundColor Yellow
    exit 1
}

$roleLabels = $myMachine.Roles | ForEach-Object { $RoleNames[$_] }
Write-Host "  This machine: $($myMachine.IP) -> $($roleLabels -join ', ')" -ForegroundColor Green

# -- 5. Build extra_hosts --
$nnMachine  = $allMachines | Where-Object { $_.Roles -contains 1 } | Select-Object -First 1
$snnMachine = $allMachines | Where-Object { $_.Roles -contains 2 } | Select-Object -First 1
$rmMachine  = $allMachines | Where-Object { $_.Roles -contains 3 } | Select-Object -First 1
$hsMachine  = $allMachines | Where-Object { $_.Roles -contains 4 } | Select-Object -First 1

if ($snnMachine) { $snnIP = $snnMachine.IP } else { $snnIP = $nnMachine.IP }
if ($hsMachine)  { $hsIP = $hsMachine.IP }   else { $hsIP = $rmMachine.IP }

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

# -- 6. Generate docker-compose.yml --
$composeFile = Join-Path $RepoRoot "docker-compose.generated.yml"
$roles = $myMachine.Roles

$yaml = "# Generated by start.ps1 for $($myMachine.IP)`n"
$yaml += "`n"
$yaml += "x-extra-hosts: &extra_hosts`n"
$yaml += "$extraHostsYaml`n"
$yaml += "`n"
$yaml += "x-image: &image clustrer-hadoop:$HadoopVersion`n"
$yaml += "`n"
$yaml += "services:`n"
$yaml += "`n"

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
    $yaml += "  $($v):`n"
}

# Write file (UTF-8 no BOM)
[System.IO.File]::WriteAllText($composeFile, $yaml, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "  Compose: docker-compose.generated.yml" -ForegroundColor Gray

# -- 7. Docker compose up --
Write-Host ""
Write-Host ">>> Starting containers..." -ForegroundColor Cyan
Write-Host ""

Push-Location $RepoRoot
try {
    docker compose -f docker-compose.generated.yml up -d --build
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  ERROR: docker compose failed" -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Containers started!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""

if ($roles -contains 1) {
    Write-Host "  Wait ~30 sec for NameNode, then check:" -ForegroundColor Yellow
    Write-Host "    docker exec namenode hdfs dfsadmin -report" -ForegroundColor White
}
if ($roles -contains 3) {
    Write-Host "    docker exec resourcemanager yarn node -list" -ForegroundColor White
}
if ($roles -contains 5) {
    Write-Host "  DataNode ($($myMachine.WorkerName)) started" -ForegroundColor Green
}
Write-Host ""
