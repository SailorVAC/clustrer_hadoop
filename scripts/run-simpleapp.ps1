# Build SimpleApp and run the LineCount MapReduce job.
#
# Usage (from repo root):
#   .\scripts\run-simpleapp.ps1                                  # default paths
#   .\scripts\run-simpleapp.ps1 -InputPath /my/in -OutputPath /my/out
#
# For multi-host cluster: run this on the master node where
# namenode and resourcemanager containers are available.

param(
    [string]$InputPath  = "/user/demo/input",
    [string]$OutputPath = "/user/demo/output"
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

# ---------- 4. Verify input data exists in HDFS ----------
Write-Host "=== Checking HDFS input ($InputPath) ==="

docker exec $HdfsContainer hdfs dfs -test -d $InputPath 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: input directory $InputPath does not exist in HDFS." -ForegroundColor Red
    Write-Host "Upload your data first, e.g.:"
    Write-Host "  docker exec namenode hdfs dfs -mkdir -p $InputPath"
    Write-Host "  docker exec namenode hdfs dfs -put <local_file> $InputPath/"
    exit 1
}

# Remove previous output if exists
docker exec $HdfsContainer hdfs dfs -rm -r -f $OutputPath 2>$null

# ---------- 5. Run MapReduce job ----------
Write-Host ""
Write-Host "=== Running LineCount MapReduce on YARN ==="
Write-Host "    Input:  $InputPath"
Write-Host "    Output: $OutputPath"
Write-Host ""

# Main-Class is already set in the JAR manifest (pom.xml maven-jar-plugin),
# so do NOT pass the class name here — otherwise hadoop jar treats it as
# an extra argument and the app receives 3 args instead of 2.
#
# Uber mode runs map+reduce inside the ApplicationMaster JVM.
# Required for multi-host Docker clusters where each host has its own
# bridge network: without it, reduce tasks on host B cannot reach the AM
# on host A via internal Docker IPs (172.18.x.x).
docker exec $SubmitContainer hadoop jar "/tmp/$JarName" `
    "-Dmapreduce.job.ubertask.enable=true" `
    "-Dmapreduce.job.ubertask.maxmaps=20" `
    "-Dmapreduce.job.ubertask.maxbytes=536870912" `
    $InputPath $OutputPath

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
