#!/usr/bin/env bash
# Сборка JAR-ов всех учебных приложений: Lab 1 (часть 1 MR + часть 2 Spark),
# Lab 2 (MapReduce Sales), Lab 3 (Spark Sales+Categories).  Maven запускается
# в контейнере maven:3.9-eclipse-temurin-11, поэтому на хосте достаточно
# Docker'а.
#
# Использование:
#   ./scripts/build-labs.sh            # собрать все четыре приложения
#   ./scripts/build-labs.sh <name>...  # собрать только указанные модули
#                                       (SimpleApp, lab1_spark, lab2_sales_mapreduce, lab3_spark)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAVEN_IMAGE="${MAVEN_IMAGE:-maven:3.9-eclipse-temurin-11}"

ALL_MODULES=(SimpleApp lab1_spark lab2_sales_mapreduce lab3_spark)
MODULES=("$@")
if [[ ${#MODULES[@]} -eq 0 ]]; then
    MODULES=("${ALL_MODULES[@]}")
fi

# Кешируем ~/.m2, чтобы пакеты Spark/Hadoop не качались каждый раз.
M2_CACHE="${HOME}/.m2-clustrer-hadoop"
mkdir -p "$M2_CACHE"

for module in "${MODULES[@]}"; do
    APP_DIR="${REPO_ROOT}/app/${module}"
    if [[ ! -f "${APP_DIR}/pom.xml" ]]; then
        echo "Пропускаю ${module}: ${APP_DIR}/pom.xml не найден" >&2
        continue
    fi

    echo "=== Сборка ${module} ==="
    docker run --rm \
        -v "${APP_DIR}:/app" \
        -v "${M2_CACHE}:/root/.m2" \
        -w /app \
        "${MAVEN_IMAGE}" \
        mvn -q -DskipTests clean package

    # Печатаем итоговый JAR.
    JAR=$(find "${APP_DIR}/target" -maxdepth 1 -name '*.jar' ! -name '*-sources.jar' ! -name '*-tests.jar' 2>/dev/null | head -n1)
    if [[ -n "$JAR" ]]; then
        echo "    -> ${JAR}"
    else
        echo "ОШИБКА: JAR не найден в ${APP_DIR}/target" >&2
        exit 1
    fi
done

echo "=== Готово ==="
