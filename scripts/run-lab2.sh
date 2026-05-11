#!/usr/bin/env bash
# Lab 2 — MapReduce SalesDriver.  Тонкая обёртка над submit-jar.sh.
#
# Использование:
#   ./scripts/run-lab2.sh                                                       # значения по умолчанию
#   ./scripts/run-lab2.sh <hdfs_input_csv> <hdfs_output_dir>
#   ./scripts/run-lab2.sh /data/sales.csv /user/HUser/Work/Sudilovskiy/output_full
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR_PATH="${REPO_ROOT}/app/lab2_sales_mapreduce/target/SimpleApp-1.0-SNAPSHOT.jar"
HDFS_INPUT="${1:-/user/HUser/Work/Sudilovskiy/data/sales_sample.csv}"
HDFS_OUTPUT="${2:-/user/HUser/Work/Sudilovskiy/output_lab2}"

if [[ ! -f "$JAR_PATH" ]]; then
    echo "Собираю lab2_sales_mapreduce, JAR не найден..."
    bash "${REPO_ROOT}/scripts/build-labs.sh" lab2_sales_mapreduce
fi

# Удаляем предыдущий output, если он есть — hadoop падает, если каталог существует.
docker exec namenode hdfs dfs -rm -r -f "$HDFS_OUTPUT" 2>/dev/null || true

bash "${REPO_ROOT}/scripts/submit-jar.sh" \
    --engine hadoop \
    -D dfs.client.use.datanode.hostname=true \
    -D mapreduce.input.fileinputformat.split.minsize=280000000 \
    "$JAR_PATH" \
    -- "$HDFS_INPUT" "$HDFS_OUTPUT"

echo ""
echo "=== Результат (${HDFS_OUTPUT}/part-r-00000) ==="
docker exec namenode hdfs dfs -cat "${HDFS_OUTPUT}/part-r-00000"
