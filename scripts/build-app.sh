#!/usr/bin/env bash
# Сборка SimpleApp JAR с помощью Maven (в Docker-контейнере).
#
# Результат: app/SimpleApp/target/SimpleApp-1.0-SNAPSHOT.jar
#
# Использование:
#   ./scripts/build-app.sh
#
# Maven запускается внутри контейнера maven:3.9-eclipse-temurin-11,
# поэтому на хост-машине Maven/JDK устанавливать не нужно.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${REPO_ROOT}/app/SimpleApp"

if [[ ! -f "${APP_DIR}/pom.xml" ]]; then
    echo "Ошибка: не найден ${APP_DIR}/pom.xml" >&2
    exit 1
fi

echo "=== Сборка SimpleApp (Maven в Docker) ==="
docker run --rm \
    -v "${APP_DIR}:/app" \
    -w /app \
    maven:3.9-eclipse-temurin-11 \
    mvn clean package -q -DskipTests

JAR="${APP_DIR}/target/SimpleApp-1.0-SNAPSHOT.jar"
if [[ -f "$JAR" ]]; then
    echo "=== Готово: ${JAR} ==="
else
    echo "Ошибка: JAR не найден после сборки" >&2
    exit 1
fi
