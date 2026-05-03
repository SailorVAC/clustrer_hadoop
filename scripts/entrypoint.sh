#!/usr/bin/env bash
# Запуск Hadoop-сервиса в зависимости от $HADOOP_ROLE.
# Поддерживаемые роли:
#   namenode | secondarynamenode | datanode |
#   resourcemanager | nodemanager | historyserver |
#   worker  (DataNode + NodeManager в одном контейнере, для local-compose)
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

NAMENODE_HOST="${NAMENODE_HOST:-namenode}"
RESOURCEMANAGER_HOST="${RESOURCEMANAGER_HOST:-resourcemanager}"

# DataNode'ы на разных воркерах НЕ должны иметь одинаковый xferPort,
# когда они идут к NameNode через NAT мастер-ноута: иначе NameNode видит
# у обоих source-IP мастер-bridge gateway (например 172.18.0.1) и тот же
# порт 9866, и считает их одним и тем же узлом, выкидывая друг друга
# по очереди. Поэтому DN на workerN получает xferPort 9866 + (N-1)*10.
compute_dn_port_offset() {
    local name="${1:-worker1}"
    case "$name" in
        worker[0-9]|worker[0-9][0-9])
            local num="${name#worker}"
            echo $(( (num - 1) * 10 ))
            ;;
        *)
            echo 0
            ;;
    esac
}

# Hadoop Configuration НЕ читает JVM system-properties (-D перед main-классом),
# а только XML из HADOOP_CONF_DIR + аргумент -conf. Поэтому per-DN-настройки
# (адреса/порты + hostname) дописываем напрямую в hdfs-site.xml перед стартом.
inject_dn_overrides() {
    local node_name="$1" xfer="$2" http="$3" ipc="$4"
    local cfg="${HADOOP_CONF_DIR}/hdfs-site.xml"
    python3 - "$cfg" "$node_name" "$xfer" "$http" "$ipc" <<'PY'
import sys, xml.etree.ElementTree as ET
cfg, node, xfer, http, ipc = sys.argv[1:6]
tree = ET.parse(cfg)
root = tree.getroot()
overrides = {
    "dfs.datanode.address": f"0.0.0.0:{xfer}",
    "dfs.datanode.http.address": f"0.0.0.0:{http}",
    "dfs.datanode.ipc.address": f"0.0.0.0:{ipc}",
    "dfs.datanode.hostname": node,
}
existing = {p.find("name").text: p for p in root.findall("property")
            if p.find("name") is not None}
for name, value in overrides.items():
    prop = existing.get(name)
    if prop is None:
        prop = ET.SubElement(root, "property")
        ET.SubElement(prop, "name").text = name
        ET.SubElement(prop, "value").text = value
    else:
        v = prop.find("value")
        if v is None:
            v = ET.SubElement(prop, "value")
        v.text = value
tree.write(cfg, encoding="UTF-8", xml_declaration=True)
PY
}

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
        wait_for "${NAMENODE_HOST}" 9000
        exec hdfs secondarynamenode
        ;;

    datanode)
        : "${NODE_NAME:?NODE_NAME (worker1|worker2|...) обязателен для datanode}"
        wait_for "${NAMENODE_HOST}" 9000
        # Если порты заданы явно в .env — используем их, иначе считаем
        # из NODE_NAME (worker1 → 9866, worker2 → 9876, ...).
        DN_OFFSET="$(compute_dn_port_offset "${NODE_NAME}")"
        DN_HTTP_PORT="${DN_HTTP_PORT:-$((9864 + DN_OFFSET))}"
        DN_XFER_PORT="${DN_XFER_PORT:-$((9866 + DN_OFFSET))}"
        DN_IPC_PORT="${DN_IPC_PORT:-$((9867 + DN_OFFSET))}"
        echo "[entrypoint] DN ports: http=${DN_HTTP_PORT} xfer=${DN_XFER_PORT} ipc=${DN_IPC_PORT}"
        inject_dn_overrides "${NODE_NAME}" "${DN_XFER_PORT}" "${DN_HTTP_PORT}" "${DN_IPC_PORT}"
        exec hdfs datanode
        ;;

    resourcemanager)
        exec yarn resourcemanager
        ;;

    nodemanager)
        : "${NODE_NAME:?NODE_NAME (worker1|worker2|...) обязателен для nodemanager}"
        wait_for "${RESOURCEMANAGER_HOST}" 8032
        export YARN_NODEMANAGER_OPTS="-Dyarn.nodemanager.hostname=${NODE_NAME} ${YARN_NODEMANAGER_OPTS:-}"
        exec yarn nodemanager
        ;;

    historyserver)
        wait_for "${RESOURCEMANAGER_HOST}" 8032
        exec mapred historyserver
        ;;

    worker)
        # Combined-режим только для docker-compose.local.yml: один
        # контейнер с DN+NM, чтобы не было коллизий hostname'ов worker1/2
        # на одной bridge-сети.
        : "${NODE_NAME:?NODE_NAME (worker1|worker2|...) обязателен для worker}"
        wait_for "${NAMENODE_HOST}" 9000
        DN_OFFSET="$(compute_dn_port_offset "${NODE_NAME}")"
        DN_HTTP_PORT=$((9864 + DN_OFFSET))
        DN_XFER_PORT=$((9866 + DN_OFFSET))
        DN_IPC_PORT=$((9867 + DN_OFFSET))
        echo "[entrypoint] DN ports: http=${DN_HTTP_PORT} xfer=${DN_XFER_PORT} ipc=${DN_IPC_PORT}"
        inject_dn_overrides "${NODE_NAME}" "${DN_XFER_PORT}" "${DN_HTTP_PORT}" "${DN_IPC_PORT}"
        echo "[entrypoint] стартую DataNode в фоне"
        hdfs --daemon start datanode
        wait_for "${RESOURCEMANAGER_HOST}" 8032
        export YARN_NODEMANAGER_OPTS="-Dyarn.nodemanager.hostname=${NODE_NAME} ${YARN_NODEMANAGER_OPTS:-}"
        echo "[entrypoint] стартую NodeManager (foreground)"
        exec yarn nodemanager
        ;;

    *)
        echo "[entrypoint] неизвестная роль: $ROLE" >&2
        exit 1
        ;;
esac
