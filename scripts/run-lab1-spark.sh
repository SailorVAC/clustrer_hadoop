#!/usr/bin/env bash
# Lab 1 — часть 2 (Spark).  Тонкая обёртка над submit-jar.sh: подставляет
# нужный JAR и main-класс, всё остальное делает универсальный скрипт.
#
# Использование:
#   ./scripts/run-lab1-spark.sh                                              # значения по умолчанию
#   ./scripts/run-lab1-spark.sh <hdfs_input_file>                            # переопределить путь
#   DEPLOY_MODE=cluster ./scripts/run-lab1-spark.sh <hdfs_input_file>        # YARN cluster mode
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR_PATH="${REPO_ROOT}/app/lab1_spark/target/simpleapp_spark-1.0-SNAPSHOT.jar"
HDFS_INPUT="${1:-/user/HUser/Work/Sudilovskiy/sample-text.txt}"
DEPLOY_MODE="${DEPLOY_MODE:-client}"
APP_NAME="${APP_NAME:-Lab1 - Line count Spark App (${DEPLOY_MODE})}"

if [[ ! -f "$JAR_PATH" ]]; then
    echo "Собираю lab1_spark, JAR не найден..."
    bash "${REPO_ROOT}/scripts/build-labs.sh" lab1_spark
fi

exec bash "${REPO_ROOT}/scripts/submit-jar.sh" \
    --engine spark \
    --class by.bsu.rct.bigdata.LineCountDriverSpark \
    --deploy-mode "$DEPLOY_MODE" \
    --name "$APP_NAME" \
    "$JAR_PATH" \
    -- "$HDFS_INPUT"
