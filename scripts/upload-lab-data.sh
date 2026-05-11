#!/usr/bin/env bash
# Загружает в HDFS все учебные входные данные:
#   /user/HUser/Work/Sudilovskiy/sample-text.txt        (для Lab 1)
#   /user/HUser/Work/Sudilovskiy/data/sales_sample.csv  (для Lab 2 и Lab 3)
#   /user/HUser/Work/Sudilovskiy/data/categories.csv    (для Lab 3)
#   /spark-logs                                          (для spark eventLog'ов)
#
# Файлы лежат в repo:/data/.  Если хочешь использовать другой набор,
# просто перепиши их там — скрипт идемпотентен (перезаливает каждый раз).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${REPO_ROOT}/data"

HDFS_BASE="/user/HUser/Work/Sudilovskiy"

# Берём namenode-контейнер для команд hdfs dfs.
HDFS_CONTAINER="namenode"
if ! docker inspect --format='{{.State.Running}}' "$HDFS_CONTAINER" 2>/dev/null | grep -q true; then
    echo "ОШИБКА: контейнер namenode не запущен. Сначала запусти кластер." >&2
    exit 1
fi

upload() {
    local local_file="$1"
    local hdfs_path="$2"
    if [[ ! -f "$local_file" ]]; then
        echo "ОШИБКА: локальный файл ${local_file} не найден" >&2
        return 1
    fi
    local hdfs_dir
    hdfs_dir="$(dirname "$hdfs_path")"
    docker exec "$HDFS_CONTAINER" hdfs dfs -mkdir -p "$hdfs_dir"
    docker cp "$local_file" "${HDFS_CONTAINER}:/tmp/$(basename "$local_file")"
    docker exec "$HDFS_CONTAINER" hdfs dfs -rm -f "$hdfs_path" 2>/dev/null || true
    docker exec "$HDFS_CONTAINER" hdfs dfs -put -f "/tmp/$(basename "$local_file")" "$hdfs_path"
    docker exec "$HDFS_CONTAINER" rm -f "/tmp/$(basename "$local_file")"
    echo "    -> ${hdfs_path}"
}

echo "=== Создаю директории в HDFS ==="
docker exec "$HDFS_CONTAINER" hdfs dfs -mkdir -p "${HDFS_BASE}/data" /spark-logs
docker exec "$HDFS_CONTAINER" hdfs dfs -chmod 1777 /spark-logs

echo "=== Заливаю учебные файлы ==="
upload "${DATA_DIR}/sample-text.txt"   "${HDFS_BASE}/sample-text.txt"
upload "${DATA_DIR}/sales_sample.csv"  "${HDFS_BASE}/data/sales_sample.csv"
upload "${DATA_DIR}/categories.csv"    "${HDFS_BASE}/data/categories.csv"

echo ""
echo "=== Что лежит в ${HDFS_BASE} ==="
docker exec "$HDFS_CONTAINER" hdfs dfs -ls -R "${HDFS_BASE}"
echo ""
echo "=== Готово ==="
