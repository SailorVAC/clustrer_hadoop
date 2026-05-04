# Сборка SimpleApp JAR с помощью Maven (в Docker-контейнере).
#
# Результат: app\SimpleApp\target\SimpleApp-1.0-SNAPSHOT.jar
#
# Использование (из корня репозитория):
#   .\scripts\build-app.ps1
#
# Maven запускается внутри контейнера maven:3.9-eclipse-temurin-11,
# поэтому на хост-машине Maven/JDK устанавливать не нужно.

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$AppDir   = Join-Path $RepoRoot "app\SimpleApp"

if (-not (Test-Path (Join-Path $AppDir "pom.xml"))) {
    Write-Error "Ошибка: не найден $AppDir\pom.xml"
    exit 1
}

Write-Host "=== Сборка SimpleApp (Maven в Docker) ==="

# Преобразуем путь в формат для Docker Desktop на Windows
# Docker Desktop понимает как Windows-пути, так и /c/Users/... формат
docker run --rm `
    -v "${AppDir}:/app" `
    -w /app `
    maven:3.9-eclipse-temurin-11 `
    mvn clean package -q -DskipTests

$Jar = Join-Path $AppDir "target\SimpleApp-1.0-SNAPSHOT.jar"
if (Test-Path $Jar) {
    Write-Host "=== Готово: $Jar ==="
} else {
    Write-Error "Ошибка: JAR не найден после сборки"
    exit 1
}
