#!/usr/bin/env bash
# Lab 3 — Spark.  Тонкая обёртка над submit-jar.sh.
#
# Использование:
#   ./scripts/run-lab3-spark.sh
#   ./scripts/run-lab3-spark.sh <hdfs_sales_csv> <hdfs_categories_csv>
#   DEPLOY_MODE=cluster ./scripts/run-lab3-spark.sh ...
#
# Поведение приложения:
#   - "sample" в имени входа => результат в stdout;
#   - иначе пишет в hdfs:///user/HUser/Work/Sudilovskiy/result_lab3.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR_PATH="${REPO_ROOT}/app/lab3_spark/target/simpleapp_spark-1.0-SNAPSHOT.jar"
HDFS_SALES="${1:-/user/HUser/Work/Sudilovskiy/data/sales_sample.csv}"
HDFS_CATS="${2:-/user/HUser/Work/Sudilovskiy/data/categories.csv}"
DEPLOY_MODE="${DEPLOY_MODE:-client}"
APP_NAME="${APP_NAME:-Lab3 - Variant A Task 2 (${DEPLOY_MODE})}"

if [[ ! -f "$JAR_PATH" ]]; then
    echo "Собираю lab3_spark, JAR не найден..."
    bash "${REPO_ROOT}/scripts/build-labs.sh" lab3_spark
fi

# Приложение пишет в HDFS, если во входе нет "sample" — удалим старый output.
if [[ "$HDFS_SALES" != *sample* ]]; then
    docker exec namenode hdfs dfs -rm -r -f /user/HUser/Work/Sudilovskiy/result_lab3 2>/dev/null || true
fi

bash "${REPO_ROOT}/scripts/submit-jar.sh" \
    --engine spark \
    --class by.bsu.rct.bigdata.LineCountDriverSpark \
    --deploy-mode "$DEPLOY_MODE" \
    --name "$APP_NAME" \
    "$JAR_PATH" \
    -- "$HDFS_SALES" "$HDFS_CATS"

if [[ "$HDFS_SALES" != *sample* ]]; then
    echo ""
    echo "=== Результат (hdfs:///user/HUser/Work/Sudilovskiy/result_lab3) ==="
    docker exec namenode hdfs dfs -cat /user/HUser/Work/Sudilovskiy/result_lab3/part-00000
fi
