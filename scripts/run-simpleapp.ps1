# Build SimpleApp, upload test data to HDFS and run the MapReduce job.
#
# Usage (from repo root):
#   .\scripts\run-simpleapp.ps1                                  # smoke test
#   .\scripts\run-simpleapp.ps1 -InputPath /demo/in -OutputPath /demo/out
#
# For multi-host cluster: run this on the master node where
# namenode and resourcemanager containers are available.

param(
    [string]$InputPath  = "/simpleapp/input",
    [string]$OutputPath = "/simpleapp/output"
)

$ErrorActionPreference = "Continue"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$JarName  = "SimpleApp-1.0-SNAPSHOT.jar"
$JarPath  = Join-Path $RepoRoot "app\SimpleApp\target\$JarName"

# ---------- 1. Build JAR if not yet built ----------
if (-not (Test-Path $JarPath)) {
    Write-Host "=== JAR not found, starting build ==="
    & (Join-Path $RepoRoot "scripts\build-app.ps1")
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: build failed" -ForegroundColor Red
        exit 1
    }
}

# ---------- 2. Find running container ----------
$SubmitContainer = $null
foreach ($c in @("resourcemanager", "namenode")) {
    $running = docker inspect --format '{{.State.Running}}' $c 2>$null
    if ($running -eq "true") {
        $SubmitContainer = $c
        break
    }
}
if (-not $SubmitContainer) {
    Write-Host "ERROR: no running namenode or resourcemanager container found." -ForegroundColor Red
    Write-Host "Make sure the cluster is up (docker compose ... up -d)."
    exit 1
}
Write-Host "=== Using container: $SubmitContainer ==="

# Find HDFS client container (namenode)
$HdfsContainer = "namenode"
$nnRunning = docker inspect --format '{{.State.Running}}' $HdfsContainer 2>$null
if ($nnRunning -ne "true") {
    $HdfsContainer = $SubmitContainer
}

# ---------- 3. Copy JAR into container ----------
Write-Host "=== Copying JAR into container ==="
docker cp $JarPath "${SubmitContainer}:/tmp/${JarName}"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: failed to copy JAR" -ForegroundColor Red
    exit 1
}

# ---------- 4. Prepare input data in HDFS ----------
Write-Host "=== Preparing HDFS (input=$InputPath, output=$OutputPath) ==="

# Remove previous output if exists
docker exec $HdfsContainer hdfs dfs -rm -r -f $OutputPath 2>$null

# If input directory does not exist, create a sample file
$needSample = $false
docker exec $HdfsContainer hdfs dfs -test -d $InputPath 2>$null
if ($LASTEXITCODE -ne 0) {
    $needSample = $true
}

if ($needSample) {
    Write-Host "=== Creating sample file in HDFS ==="
    docker exec $HdfsContainer bash -c "cat > /tmp/sample.txt << 'ENDOFFILE'
Hadoop is a framework for distributed processing of large data sets.
It runs on a cluster of commodity servers.
MapReduce splits a task into small subtasks.
Each node processes its own portion of data.
Results are combined during the Reduce phase.
HDFS provides reliable storage with replication.
YARN manages cluster resources.
Hadoop is widely used in industry.
This is a demo - LineCount counts lines.
Hello, Hadoop!
ENDOFFILE"
    docker exec $HdfsContainer hdfs dfs -mkdir -p $InputPath
    docker exec $HdfsContainer hdfs dfs -put -f /tmp/sample.txt "$InputPath/"
}

# ---------- 5. Run MapReduce job ----------
Write-Host ""
Write-Host "=== Running LineCount MapReduce on YARN ==="
Write-Host "    Input:  $InputPath"
Write-Host "    Output: $OutputPath"
Write-Host ""

$cmd = "hadoop jar /tmp/$JarName by.bsu.rct.bigdata.LineCountDriverMR $InputPath $OutputPath"
docker exec $SubmitContainer bash -c $cmd

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: MapReduce job failed" -ForegroundColor Red
    exit 1
}

# ---------- 6. Show results ----------
Write-Host ""
Write-Host "=== Result ==="
docker exec $HdfsContainer hdfs dfs -cat "$OutputPath/part-r-00000"
Write-Host ""
Write-Host "=== Done! ==="
