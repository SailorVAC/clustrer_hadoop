#!/usr/bin/env bash
# Сборка SimpleApp, загрузка тестового файла в HDFS и запуск MapReduce-job.
#
# Использование:
#   ./scripts/run-simpleapp.sh                         # smoke-тест со встроенным файлом
#   ./scripts/run-simpleapp.sh /demo/input /demo/output # свои пути в HDFS
#
# Для multi-host кластера: скрипт запускается на мастер-ноуте, где
# доступны контейнеры namenode и resourcemanager.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR_NAME="SimpleApp-1.0-SNAPSHOT.jar"
JAR_PATH="${REPO_ROOT}/app/SimpleApp/target/${JAR_NAME}"

# ---------- 1. Сборка, если JAR ещё не собран ----------
if [[ ! -f "$JAR_PATH" ]]; then
    echo "=== JAR не найден, запускаю сборку ==="
    bash "${REPO_ROOT}/scripts/build-app.sh"
fi

# ---------- 2. Определяем контейнер для запуска ----------
# В local-compose resourcemanager — отдельный контейнер;
# в multi-host — тоже. Ищем первый живой из списка.
SUBMIT_CONTAINER=""
for c in resourcemanager namenode; do
    if docker inspect --format='{{.State.Running}}' "$c" 2>/dev/null | grep -q true; then
        SUBMIT_CONTAINER="$c"
        break
    fi
done
if [[ -z "$SUBMIT_CONTAINER" ]]; then
    echo "Ошибка: не найден запущенный контейнер namenode или resourcemanager." >&2
    echo "Убедитесь, что кластер поднят (docker compose ... up -d)." >&2
    exit 1
fi
echo "=== Используем контейнер: ${SUBMIT_CONTAINER} ==="

# Определяем контейнер с HDFS-клиентом (namenode)
HDFS_CONTAINER="namenode"
if ! docker inspect --format='{{.State.Running}}' "$HDFS_CONTAINER" 2>/dev/null | grep -q true; then
    HDFS_CONTAINER="$SUBMIT_CONTAINER"
fi

# ---------- 3. Копируем JAR в контейнер ----------
echo "=== Копирую JAR в контейнер ==="
docker cp "$JAR_PATH" "${SUBMIT_CONTAINER}:/tmp/${JAR_NAME}"

# ---------- 4. Готовим входные данные в HDFS ----------
HDFS_INPUT="${1:-/simpleapp/input}"
HDFS_OUTPUT="${2:-/simpleapp/output}"

echo "=== Подготовка HDFS (input=${HDFS_INPUT}, output=${HDFS_OUTPUT}) ==="

# Удалим предыдущий output, если есть
docker exec "$HDFS_CONTAINER" hdfs dfs -rm -r -f "$HDFS_OUTPUT" 2>/dev/null || true

# Если входная директория пуста — кладём тестовый файл
EXISTING=$(docker exec "$HDFS_CONTAINER" hdfs dfs -ls "$HDFS_INPUT" 2>/dev/null || true)
if [[ -z "$EXISTING" || "$EXISTING" == *"No such file"* ]]; then
    echo "=== Создаю тестовый файл в HDFS ==="
    docker exec "$HDFS_CONTAINER" bash -c "
        cat > /tmp/sample.txt <<'EOF'
Hadoop — фреймворк для распределённой обработки больших данных.
Он работает на кластере из обычных серверов.
MapReduce делит задачу на маленькие подзадачи.
Каждый узел обрабатывает свою часть данных.
Результаты объединяются на этапе Reduce.
HDFS обеспечивает надёжное хранение с репликацией.
YARN управляет ресурсами кластера.
Hadoop широко используется в индустрии.
Это учебный пример — LineCount считает строки.
Привет, Hadoop!
EOF"
    docker exec "$HDFS_CONTAINER" hdfs dfs -mkdir -p "$HDFS_INPUT"
    docker exec "$HDFS_CONTAINER" hdfs dfs -put -f /tmp/sample.txt "$HDFS_INPUT/"
fi

# ---------- 5. Запускаем MapReduce-задачу ----------
echo ""
echo "=== Запускаю LineCount MapReduce на YARN ==="
echo "    Вход:  ${HDFS_INPUT}"
echo "    Выход: ${HDFS_OUTPUT}"
echo ""

# Main-Class is already set in the JAR manifest (pom.xml maven-jar-plugin),
# so do NOT pass the class name here — otherwise hadoop jar treats it as
# an extra argument and the app receives 3 args instead of 2.
# Uber mode: map+reduce run inside the AM JVM (avoids cross-host Docker
# networking issues where internal bridge IPs are unreachable).
docker exec "$SUBMIT_CONTAINER" \
    hadoop jar "/tmp/${JAR_NAME}" \
    -Dmapreduce.job.ubertask.enable=true \
    "$HDFS_INPUT" "$HDFS_OUTPUT"

# ---------- 6. Показываем результат ----------
echo ""
echo "=== Результат ==="
docker exec "$HDFS_CONTAINER" hdfs dfs -cat "${HDFS_OUTPUT}/part-r-00000"
echo ""
echo "=== Готово! ==="
