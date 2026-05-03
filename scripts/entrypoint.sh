#!/usr/bin/env bash
# Запуск Hadoop-сервиса в зависимости от $HADOOP_ROLE.
# Поддерживаемые роли: namenode | secondarynamenode | datanode |
#                      resourcemanager | nodemanager | historyserver
set -euo pipefail

ROLE="${HADOOP_ROLE:-}"
if [[ -z "$ROLE" ]]; then
    echo "[entrypoint] HADOOP_ROLE не задан. Допустимые значения:"
    echo "             namenode, secondarynamenode, datanode,"
    echo "             resourcemanager, nodemanager, historyserver"
    exit 1
fi

# JAVA_HOME уже выставлен базовым образом eclipse-temurin, но подстрахуемся.
if [[ -z "${JAVA_HOME:-}" && -d /opt/java/openjdk ]]; then
    export JAVA_HOME=/opt/java/openjdk
fi

mkdir -p "${HADOOP_DATA_DIR}/namenode" \
         "${HADOOP_DATA_DIR}/datanode" \
         "${HADOOP_DATA_DIR}/secondary" \
         "${HADOOP_DATA_DIR}/tmp" \
         "${HADOOP_LOG_DIR}"

# Ждём, пока удалённый сервис начнёт принимать соединения.
wait_for() {
    local host="$1" port="$2"
    local timeout="${3:-180}"
    local waited=0
    echo "[entrypoint] жду ${host}:${port} (таймаут ${timeout}s)..."
    while ! nc -z "${host}" "${port}" 2>/dev/null; do
        sleep 2
        waited=$((waited + 2))
        if (( waited >= timeout )); then
            echo "[entrypoint] таймаут ожидания ${host}:${port}" >&2
            return 1
        fi
    done
    echo "[entrypoint] ${host}:${port} доступен"
}

MASTER_HOST="${MASTER_HOST:-master}"

case "$ROLE" in
    namenode)
        if [[ ! -f "${HADOOP_DATA_DIR}/namenode/current/VERSION" ]]; then
            echo "[entrypoint] форматирую NameNode (первый запуск)"
            hdfs namenode -format -nonInteractive -force \
                -clusterId "${HADOOP_CLUSTER_ID:-clustrer-hadoop}"
        fi
        exec hdfs namenode
        ;;

    secondarynamenode)
        wait_for "${MASTER_HOST}" 9000
        exec hdfs secondarynamenode
        ;;

    datanode)
        : "${NODE_NAME:?NODE_NAME (worker1|worker2|...) обязателен для datanode}"
        wait_for "${MASTER_HOST}" 9000
        export HDFS_DATANODE_OPTS="-Ddfs.datanode.hostname=${NODE_NAME} ${HDFS_DATANODE_OPTS:-}"
        exec hdfs datanode
        ;;

    resourcemanager)
        exec yarn resourcemanager
        ;;

    nodemanager)
        : "${NODE_NAME:?NODE_NAME (worker1|worker2|...) обязателен для nodemanager}"
        wait_for "${MASTER_HOST}" 8032
        export YARN_NODEMANAGER_OPTS="-Dyarn.nodemanager.hostname=${NODE_NAME} ${YARN_NODEMANAGER_OPTS:-}"
        exec yarn nodemanager
        ;;

    historyserver)
        wait_for "${MASTER_HOST}" 8032
        exec mapred historyserver
        ;;

    *)
        echo "[entrypoint] неизвестная роль: $ROLE" >&2
        exit 1
        ;;
esac
