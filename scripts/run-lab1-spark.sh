#!/usr/bin/env bash
# Lab 1 — часть 2 (Spark).  Запускает LineCountDriverSpark на YARN и
# печатает количество строк во входном HDFS-файле.
#
# Использование:
#   ./scripts/run-lab1-spark.sh                                              # значения по умолчанию
#   ./scripts/run-lab1-spark.sh <hdfs_input_file>                            # переопределить путь
#   DEPLOY_MODE=cluster ./scripts/run-lab1-spark.sh <hdfs_input_file>        # YARN cluster mode
#
# Запускается на той ноде, где доступны контейнеры namenode/resourcemanager
# (по сути, на master-ноуте). Скрипт сам подберёт нужный контейнер.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR_NAME="simpleapp_spark-1.0-SNAPSHOT.jar"
JAR_PATH="${REPO_ROOT}/app/lab1_spark/target/${JAR_NAME}"
HDFS_INPUT="${1:-/user/HUser/Work/Sudilovskiy/sample-text.txt}"
DEPLOY_MODE="${DEPLOY_MODE:-client}"
APP_NAME="${APP_NAME:-Lab1 - Line count Spark App (${DEPLOY_MODE})}"

if [[ ! -f "$JAR_PATH" ]]; then
    echo "Собираю lab1_spark, JAR не найден..."
    bash "${REPO_ROOT}/scripts/build-labs.sh" lab1_spark
fi

# Контейнер для submit'а: предпочитаем resourcemanager, fallback namenode.
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

# Копируем JAR.
docker cp "$JAR_PATH" "${SUBMIT_CONTAINER}:/tmp/${JAR_NAME}"

# Проверяем HDFS-вход.
HDFS_CONTAINER="namenode"
docker exec "$HDFS_CONTAINER" hdfs dfs -test -e "$HDFS_INPUT"

echo ""
echo "=== spark-submit (--master yarn --deploy-mode ${DEPLOY_MODE}) ==="
echo "    Input: ${HDFS_INPUT}"

# В client mode стандартный stdout приложения попадает прямо в наш терминал,
# в cluster mode — нужно потом вытянуть `yarn logs -applicationId ...`.
docker exec "$SUBMIT_CONTAINER" \
    spark-submit \
        --master yarn \
        --deploy-mode "$DEPLOY_MODE" \
        --name "$APP_NAME" \
        --class by.bsu.rct.bigdata.LineCountDriverSpark \
        --conf spark.yarn.submit.waitAppCompletion=true \
        "/tmp/${JAR_NAME}" \
        "$HDFS_INPUT"

echo ""
echo "=== Готово ==="
