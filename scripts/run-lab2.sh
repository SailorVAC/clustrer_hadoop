#!/usr/bin/env bash
# Lab 2 — MapReduce SalesDriver.  Считает максимальную сумму продажи в
# каждой категории по записям из 2-й декады месяца (11-20 число) с дробной
# частью суммы из диапазона [.95, .99].
#
# Использование:
#   ./scripts/run-lab2.sh                                                       # значения по умолчанию
#   ./scripts/run-lab2.sh <hdfs_input_csv> <hdfs_output_dir>
#   ./scripts/run-lab2.sh /data/sales.csv /user/HUser/Work/Sudilovskiy/output_full
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR_NAME="SimpleApp-1.0-SNAPSHOT.jar"
JAR_PATH="${REPO_ROOT}/app/lab2_sales_mapreduce/target/${JAR_NAME}"
HDFS_INPUT="${1:-/user/HUser/Work/Sudilovskiy/data/sales_sample.csv}"
HDFS_OUTPUT="${2:-/user/HUser/Work/Sudilovskiy/output_lab2}"

if [[ ! -f "$JAR_PATH" ]]; then
    echo "Собираю lab2_sales_mapreduce, JAR не найден..."
    bash "${REPO_ROOT}/scripts/build-labs.sh" lab2_sales_mapreduce
fi

SUBMIT_CONTAINER=""
for c in resourcemanager namenode; do
    if docker inspect --format='{{.State.Running}}' "$c" 2>/dev/null | grep -q true; then
        SUBMIT_CONTAINER="$c"
        break
    fi
done
if [[ -z "$SUBMIT_CONTAINER" ]]; then
    echo "ОШИБКА: ни namenode, ни resourcemanager не запущены." >&2
    exit 1
fi
echo "=== Submit-контейнер: ${SUBMIT_CONTAINER} ==="

docker cp "$JAR_PATH" "${SUBMIT_CONTAINER}:/tmp/${JAR_NAME}"

HDFS_CONTAINER="namenode"
docker exec "$HDFS_CONTAINER" hdfs dfs -test -e "$HDFS_INPUT"

# Удаляем предыдущий output, если он есть.
docker exec "$HDFS_CONTAINER" hdfs dfs -rm -r -f "$HDFS_OUTPUT" 2>/dev/null || true

echo ""
echo "=== hadoop jar SalesDriver ==="
echo "    Input:  ${HDFS_INPUT}"
echo "    Output: ${HDFS_OUTPUT}"

# Main-Class фиксирован в манифесте, передаём только пути и нужные -D.
docker exec "$SUBMIT_CONTAINER" \
    hadoop jar "/tmp/${JAR_NAME}" \
        -D dfs.client.use.datanode.hostname=true \
        -D mapreduce.input.fileinputformat.split.minsize=280000000 \
        "$HDFS_INPUT" "$HDFS_OUTPUT"

echo ""
echo "=== Результат (${HDFS_OUTPUT}/part-r-00000) ==="
docker exec "$HDFS_CONTAINER" hdfs dfs -cat "${HDFS_OUTPUT}/part-r-00000"
echo ""
echo "=== Готово ==="
