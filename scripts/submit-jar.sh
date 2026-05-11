#!/usr/bin/env bash
# Универсальный submit JAR-а на наш Hadoop+Spark-кластер.
#
# Скрипт сам:
#   * находит работающий submit-контейнер (resourcemanager → namenode);
#   * проверяет, что Docker-кластер вообще поднят;
#   * копирует локальный JAR во `tmp` контейнера;
#   * вызывает `hadoop jar` или `spark-submit` с нужными флагами;
#   * пробрасывает аргументы в саму программу (всё, что после `--`).
#
# Использование:
#   scripts/submit-jar.sh -e hadoop <local-jar> [-- <program args>...]
#   scripts/submit-jar.sh -e spark  <local-jar> [-- <program args>...]
#
# Опции:
#   -e, --engine        hadoop | spark         (обязательно)
#   -c, --class         org.example.Main       (опционально, иначе из манифеста JAR-а)
#   -m, --deploy-mode   client | cluster       (только spark, по умолчанию client)
#   -n, --name          "My app"               (только spark; default — имя JAR-а)
#   -D  key=value       —D-флаг hadoop jar     (повторяемо)
#       --conf key=val  spark.* конфиг         (повторяемо)
#       --jars a.jar,b.jar   extra-jars        (только spark)
#       --files /local/f1,/hdfs/f2  файлы рассылаемые в --files
#                                              (только spark)
#       --submit-host CONTAINER  принудительно подменить submit-контейнер
#                                (default: resourcemanager → namenode)
#   -h, --help          эта справка
#
# Примеры:
#
#   # MapReduce-задача, main-класс из манифеста
#   scripts/submit-jar.sh -e hadoop ./SimpleApp-1.0-SNAPSHOT.jar -- \
#       /user/HUser/Work/input /user/HUser/Work/output
#
#   # MapReduce с переопределением класса и доп. -D
#   scripts/submit-jar.sh -e hadoop \
#       -c org.example.MyDriver \
#       -D mapreduce.job.reduces=4 \
#       -D dfs.client.use.datanode.hostname=true \
#       ./mr.jar -- /in /out
#
#   # Spark client mode
#   scripts/submit-jar.sh -e spark -c org.example.Main ./app.jar -- arg1 arg2
#
#   # Spark cluster mode + дополнительный конфиг
#   scripts/submit-jar.sh -e spark -m cluster \
#       -n "My Spark Job" \
#       --conf spark.executor.memory=1g \
#       --conf spark.executor.cores=2 \
#       ./app.jar -- /hdfs/in
#
set -euo pipefail

usage() {
    sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

ENGINE=""
MAIN_CLASS=""
DEPLOY_MODE="client"
APP_NAME=""
SUBMIT_HOST=""
EXTRA_JARS=""
EXTRA_FILES=""
HADOOP_D_FLAGS=()
SPARK_CONFS=()

# Парсим опции до первого позиционного аргумента (JAR-а).
JAR_PATH=""
PROGRAM_ARGS=()

while (( $# > 0 )); do
    case "$1" in
        -e|--engine)        ENGINE="$2"; shift 2 ;;
        --engine=*)         ENGINE="${1#*=}"; shift ;;
        -c|--class)         MAIN_CLASS="$2"; shift 2 ;;
        --class=*)          MAIN_CLASS="${1#*=}"; shift ;;
        -m|--deploy-mode)   DEPLOY_MODE="$2"; shift 2 ;;
        --deploy-mode=*)    DEPLOY_MODE="${1#*=}"; shift ;;
        -n|--name)          APP_NAME="$2"; shift 2 ;;
        --name=*)           APP_NAME="${1#*=}"; shift ;;
        --submit-host)      SUBMIT_HOST="$2"; shift 2 ;;
        --submit-host=*)    SUBMIT_HOST="${1#*=}"; shift ;;
        --jars)             EXTRA_JARS="$2"; shift 2 ;;
        --jars=*)           EXTRA_JARS="${1#*=}"; shift ;;
        --files)            EXTRA_FILES="$2"; shift 2 ;;
        --files=*)          EXTRA_FILES="${1#*=}"; shift ;;
        -D)                 HADOOP_D_FLAGS+=("-D" "$2"); shift 2 ;;
        -D*)                HADOOP_D_FLAGS+=("-D" "${1#-D}"); shift ;;
        --conf)             SPARK_CONFS+=("--conf" "$2"); shift 2 ;;
        --conf=*)           SPARK_CONFS+=("--conf" "${1#*=}"); shift ;;
        -h|--help)          usage; exit 0 ;;
        --)                 shift; PROGRAM_ARGS=("$@"); break ;;
        -*)                 echo "Неизвестная опция: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [[ -z "$JAR_PATH" ]]; then
                JAR_PATH="$1"; shift
            else
                # Позиционные аргументы после JAR-а пойдут в программу.
                # На случай, если пользователь забыл `--`.
                PROGRAM_ARGS+=("$1"); shift
            fi
            ;;
    esac
done

if [[ -z "$ENGINE" || -z "$JAR_PATH" ]]; then
    echo "ОШИБКА: нужно указать --engine <hadoop|spark> и путь к JAR-у." >&2
    usage >&2
    exit 2
fi
case "$ENGINE" in
    hadoop|spark) ;;
    *) echo "ОШИБКА: --engine должен быть hadoop или spark, получили: ${ENGINE}" >&2; exit 2 ;;
esac
if [[ "$ENGINE" == "spark" ]]; then
    case "$DEPLOY_MODE" in
        client|cluster) ;;
        *) echo "ОШИБКА: --deploy-mode для spark должен быть client или cluster." >&2; exit 2 ;;
    esac
fi
if [[ ! -f "$JAR_PATH" ]]; then
    echo "ОШИБКА: JAR не найден: ${JAR_PATH}" >&2
    exit 1
fi

JAR_NAME="$(basename "$JAR_PATH")"

# Выбираем submit-контейнер.
pick_submit_container() {
    if [[ -n "$SUBMIT_HOST" ]]; then
        if docker inspect --format='{{.State.Running}}' "$SUBMIT_HOST" 2>/dev/null | grep -q true; then
            echo "$SUBMIT_HOST"
            return
        fi
        echo "ОШИБКА: контейнер '${SUBMIT_HOST}' не запущен." >&2
        exit 1
    fi
    local candidates=(resourcemanager namenode)
    for c in "${candidates[@]}"; do
        if docker inspect --format='{{.State.Running}}' "$c" 2>/dev/null | grep -q true; then
            echo "$c"
            return
        fi
    done
    echo "ОШИБКА: не нашёл работающего submit-контейнера (resourcemanager/namenode)." >&2
    exit 1
}
SUBMIT_CONTAINER="$(pick_submit_container)"

echo "=== Submit-контейнер: ${SUBMIT_CONTAINER} ==="
echo "    JAR:        ${JAR_PATH}"
echo "    Engine:     ${ENGINE}"
if [[ -n "$MAIN_CLASS" ]]; then
    echo "    Main class: ${MAIN_CLASS}"
fi
if [[ "$ENGINE" == "spark" ]]; then
    echo "    Mode:       --master yarn --deploy-mode ${DEPLOY_MODE}"
fi
if (( ${#PROGRAM_ARGS[@]} > 0 )); then
    echo "    Args:       ${PROGRAM_ARGS[*]}"
fi
echo ""

# Копируем JAR.
docker cp "$JAR_PATH" "${SUBMIT_CONTAINER}:/tmp/${JAR_NAME}"

run_hadoop() {
    local cmd=(hadoop jar "/tmp/${JAR_NAME}")
    if [[ -n "$MAIN_CLASS" ]]; then
        cmd+=("$MAIN_CLASS")
    fi
    if (( ${#HADOOP_D_FLAGS[@]} > 0 )); then
        cmd+=("${HADOOP_D_FLAGS[@]}")
    fi
    if (( ${#PROGRAM_ARGS[@]} > 0 )); then
        cmd+=("${PROGRAM_ARGS[@]}")
    fi
    echo "=== ${cmd[*]} ==="
    docker exec "$SUBMIT_CONTAINER" "${cmd[@]}"
}

run_spark() {
    local name="${APP_NAME:-${JAR_NAME%.jar}}"
    local cmd=(spark-submit
               --master yarn
               --deploy-mode "$DEPLOY_MODE"
               --name "$name"
               --conf spark.yarn.submit.waitAppCompletion=true)
    if [[ -n "$MAIN_CLASS" ]]; then
        cmd+=(--class "$MAIN_CLASS")
    fi
    if [[ -n "$EXTRA_JARS" ]]; then
        cmd+=(--jars "$EXTRA_JARS")
    fi
    if [[ -n "$EXTRA_FILES" ]]; then
        cmd+=(--files "$EXTRA_FILES")
    fi
    if (( ${#SPARK_CONFS[@]} > 0 )); then
        cmd+=("${SPARK_CONFS[@]}")
    fi
    cmd+=("/tmp/${JAR_NAME}")
    if (( ${#PROGRAM_ARGS[@]} > 0 )); then
        cmd+=("${PROGRAM_ARGS[@]}")
    fi
    echo "=== ${cmd[*]} ==="
    docker exec "$SUBMIT_CONTAINER" "${cmd[@]}"
}

case "$ENGINE" in
    hadoop) run_hadoop ;;
    spark)  run_spark  ;;
esac

echo ""
echo "=== Готово ==="
