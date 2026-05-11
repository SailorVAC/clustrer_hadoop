#!/usr/bin/env bash
# Lab 3 — Spark.  Для каждой категории находит максимальную сумму продажи
# (тот же фильтр, что и в Lab 2), а затем подставляет вместо catID имя
# категории из справочника categories.csv через `JavaPairRDD.join`.
#
# Использование:
#   ./scripts/run-lab3-spark.sh
#   ./scripts/run-lab3-spark.sh <hdfs_sales_csv> <hdfs_categories_csv>
#   DEPLOY_MODE=cluster ./scripts/run-lab3-spark.sh ...
#
# Поведение по умолчанию:
#   - входы: /user/HUser/Work/Sudilovskiy/data/sales_sample.csv
#            /user/HUser/Work/Sudilovskiy/data/categories.csv
#   - "sample" в имени входа => приложение печатает результат в stdout
#     (его видно в client mode или в `yarn logs ...` в cluster mode);
#   - иначе пишет результат в hdfs://namenode:9000/user/HUser/Work/Sudilovskiy/result_lab3
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR_NAME="simpleapp_spark-1.0-SNAPSHOT.jar"
JAR_PATH="${REPO_ROOT}/app/lab3_spark/target/${JAR_NAME}"
HDFS_SALES="${1:-/user/HUser/Work/Sudilovskiy/data/sales_sample.csv}"
HDFS_CATS="${2:-/user/HUser/Work/Sudilovskiy/data/categories.csv}"
DEPLOY_MODE="${DEPLOY_MODE:-client}"
APP_NAME="${APP_NAME:-Lab3 - Variant A Task 2 (${DEPLOY_MODE})}"

if [[ ! -f "$JAR_PATH" ]]; then
    echo "Собираю lab3_spark, JAR не найден..."
    bash "${REPO_ROOT}/scripts/build-labs.sh" lab3_spark
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
docker exec "$HDFS_CONTAINER" hdfs dfs -test -e "$HDFS_SALES"
docker exec "$HDFS_CONTAINER" hdfs dfs -test -e "$HDFS_CATS"

# Если приложение собирается писать результат в HDFS (а не печатать в stdout),
# то предыдущее содержимое /user/HUser/Work/Sudilovskiy/result_lab3 нужно удалить.
if [[ "$HDFS_SALES" != *sample* ]]; then
    docker exec "$HDFS_CONTAINER" hdfs dfs -rm -r -f /user/HUser/Work/Sudilovskiy/result_lab3 2>/dev/null || true
fi

echo ""
echo "=== spark-submit (--master yarn --deploy-mode ${DEPLOY_MODE}) ==="
echo "    Sales:      ${HDFS_SALES}"
echo "    Categories: ${HDFS_CATS}"

docker exec "$SUBMIT_CONTAINER" \
    spark-submit \
        --master yarn \
        --deploy-mode "$DEPLOY_MODE" \
        --name "$APP_NAME" \
        --class by.bsu.rct.bigdata.LineCountDriverSpark \
        --conf spark.yarn.submit.waitAppCompletion=true \
        "/tmp/${JAR_NAME}" \
        "$HDFS_SALES" "$HDFS_CATS"

if [[ "$HDFS_SALES" != *sample* ]]; then
    echo ""
    echo "=== Результат (hdfs:///user/HUser/Work/Sudilovskiy/result_lab3) ==="
    docker exec "$HDFS_CONTAINER" hdfs dfs -cat /user/HUser/Work/Sudilovskiy/result_lab3/part-00000
fi
echo ""
echo "=== Готово ==="
