# Build SimpleApp JAR using Maven (inside a Docker container).
#
# Result: app\SimpleApp\target\SimpleApp-1.0-SNAPSHOT.jar
#
# Usage (from repo root):
#   .\scripts\build-app.ps1
#
# Maven runs inside maven:3.9-eclipse-temurin-11 container,
# so you don't need Maven/JDK installed on the host.

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$AppDir   = Join-Path $RepoRoot "app\SimpleApp"

if (-not (Test-Path (Join-Path $AppDir "pom.xml"))) {
    Write-Error "Error: pom.xml not found in $AppDir"
    exit 1
}

Write-Host "=== Building SimpleApp (Maven in Docker) ==="

docker run --rm `
    -v "${AppDir}:/app" `
    -w /app `
    maven:3.9-eclipse-temurin-11 `
    mvn clean package -q -DskipTests

$Jar = Join-Path $AppDir "target\SimpleApp-1.0-SNAPSHOT.jar"
if (Test-Path $Jar) {
    Write-Host "=== Done: $Jar ==="
} else {
    Write-Error "Error: JAR not found after build"
    exit 1
}
