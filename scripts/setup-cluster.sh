#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Мастер настройки Hadoop-кластера.
#  Генерирует docker-compose и .env файлы для каждой машины.
#
#  Если есть cluster.conf — читает IP и роли оттуда.
#  Иначе — интерактивный режим.
#
#  Использование:
#    bash scripts/setup-cluster.sh                  # auto/interactive
#    bash scripts/setup-cluster.sh -c my-cluster.conf  # явный файл
# ─────────────────────────────────────────────────────────────
set -euo pipefail

HADOOP_VERSION="3.3.6"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$REPO_ROOT/generated"
CONFIG_FILE=""

# Parse CLI args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config) CONFIG_FILE="$2"; shift 2 ;;
        *) echo "Использование: $0 [-c cluster.conf]"; exit 1 ;;
    esac
done

# ─── colors ───
C_CYAN='\033[0;36m'
C_DCYAN='\033[0;96m'
C_YELLOW='\033[1;33m'
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_GRAY='\033[0;37m'
C_WHITE='\033[1;37m'
C_RESET='\033[0m'

# ─── helpers ───

read_validated() {
    local prompt="$1" default="${2:-}" check_re="$3"
    local raw
    while true; do
        if [[ -n "$default" ]]; then
            printf "  %s [%s]: " "$prompt" "$default" >&2
        else
            printf "  %s: " "$prompt" >&2
        fi
        read -r raw
        [[ -z "$raw" && -n "$default" ]] && raw="$default"
        if [[ "$raw" =~ $check_re ]]; then
            echo "$raw"
            return
        fi
        printf "  ${C_RED}Некорректный ввод.${C_RESET}\n" >&2
    done
}

# ─── YAML service generators ───

svc_namenode() {
    local with_build="$1"
    local build_block=""
    if [[ "$with_build" == "1" ]]; then
        build_block="    build:
      context: ..
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: \${HADOOP_VERSION:-$HADOOP_VERSION}
"
    fi
    cat <<EOF
  namenode:
${build_block}    image: *image
    container_name: namenode
    hostname: namenode
    environment:
      HADOOP_ROLE: namenode
    ports:
      - "9000:9000"
      - "9870:9870"
    volumes:
      - namenode_data:/data/hdfs/namenode
      - hadoop_logs:/opt/hadoop/logs
    extra_hosts: *extra_hosts
    restart: unless-stopped

EOF
}

svc_secondarynamenode() {
    local with_build="$1"; shift
    local deps=("$@")
    local build_block="" dep_block=""
    if [[ "$with_build" == "1" ]]; then
        build_block="    build:
      context: ..
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: \${HADOOP_VERSION:-$HADOOP_VERSION}
"
    fi
    if [[ ${#deps[@]} -gt 0 ]]; then
        dep_block="    depends_on:"$'\n'
        for d in "${deps[@]}"; do dep_block+="      - $d"$'\n'; done
    fi
    cat <<EOF
  secondarynamenode:
${build_block}    image: *image
    container_name: secondarynamenode
    hostname: secondarynamenode
${dep_block}    environment:
      HADOOP_ROLE: secondarynamenode
    ports:
      - "9868:9868"
    volumes:
      - secondary_data:/data/hdfs/secondary
      - hadoop_logs:/opt/hadoop/logs
    extra_hosts: *extra_hosts
    restart: unless-stopped

EOF
}

svc_resourcemanager() {
    local with_build="$1"; shift
    local deps=("$@")
    local build_block="" dep_block=""
    if [[ "$with_build" == "1" ]]; then
        build_block="    build:
      context: ..
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: \${HADOOP_VERSION:-$HADOOP_VERSION}
"
    fi
    if [[ ${#deps[@]} -gt 0 ]]; then
        dep_block="    depends_on:"$'\n'
        for d in "${deps[@]}"; do dep_block+="      - $d"$'\n'; done
    fi
    cat <<EOF
  resourcemanager:
${build_block}    image: *image
    container_name: resourcemanager
    hostname: resourcemanager
${dep_block}    environment:
      HADOOP_ROLE: resourcemanager
    ports:
      - "8030:8030"
      - "8031:8031"
      - "8032:8032"
      - "8033:8033"
      - "8088:8088"
      # Spark driver/UI in client-mode: spark-submit runs from this
      # container, so the driver listens here and must be reachable from
      # other LAN hosts. Must match the fixed ports in
      # config/spark-defaults.conf.
      - "4040:4040"
      - "7077:7077"
      - "7078:7078"
    volumes:
      - hadoop_logs:/opt/hadoop/logs
    extra_hosts: *extra_hosts
    restart: unless-stopped

EOF
}

svc_historyserver() {
    local with_build="$1"; shift
    local deps=("$@")
    local build_block="" dep_block=""
    if [[ "$with_build" == "1" ]]; then
        build_block="    build:
      context: ..
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: \${HADOOP_VERSION:-$HADOOP_VERSION}
"
    fi
    if [[ ${#deps[@]} -gt 0 ]]; then
        dep_block="    depends_on:"$'\n'
        for d in "${deps[@]}"; do dep_block+="      - $d"$'\n'; done
    fi
    cat <<EOF
  historyserver:
${build_block}    image: *image
    container_name: historyserver
    hostname: historyserver
${dep_block}    environment:
      HADOOP_ROLE: historyserver
    ports:
      - "10020:10020"
      - "19888:19888"
    volumes:
      - hadoop_logs:/opt/hadoop/logs
    extra_hosts: *extra_hosts
    restart: unless-stopped

EOF
}

svc_datanode() {
    local with_build="$1" worker_name="$2" http_port="$3" xfer_port="$4" ipc_port="$5"
    shift 5
    local deps=("$@")
    local build_block="" dep_block=""
    if [[ "$with_build" == "1" ]]; then
        build_block="    build:
      context: ..
      dockerfile: Dockerfile
      args:
        HADOOP_VERSION: \${HADOOP_VERSION:-$HADOOP_VERSION}
"
    fi
    if [[ ${#deps[@]} -gt 0 ]]; then
        dep_block="    depends_on:"$'\n'
        for d in "${deps[@]}"; do dep_block+="      - $d"$'\n'; done
    fi
    cat <<EOF
  datanode:
${build_block}    image: *image
    container_name: datanode
    hostname: \${NODE_NAME:-$worker_name}
${dep_block}    environment:
      HADOOP_ROLE: datanode
      NODE_NAME: \${NODE_NAME:-$worker_name}
      DN_HTTP_PORT: \${DN_HTTP_PORT:-$http_port}
      DN_XFER_PORT: \${DN_XFER_PORT:-$xfer_port}
      DN_IPC_PORT: \${DN_IPC_PORT:-$ipc_port}
    ports:
      - "\${DN_HTTP_PORT:-$http_port}:\${DN_HTTP_PORT:-$http_port}"
      - "\${DN_XFER_PORT:-$xfer_port}:\${DN_XFER_PORT:-$xfer_port}"
      - "\${DN_IPC_PORT:-$ipc_port}:\${DN_IPC_PORT:-$ipc_port}"
    volumes:
      - datanode_data:/data/hdfs/datanode
      - hadoop_logs:/opt/hadoop/logs
    extra_hosts: *extra_hosts
    restart: unless-stopped

EOF
}

svc_nodemanager() {
    local worker_name="$1"; shift
    local deps=("$@")
    local dep_block=""
    if [[ ${#deps[@]} -gt 0 ]]; then
        dep_block="    depends_on:"$'\n'
        for d in "${deps[@]}"; do dep_block+="      - $d"$'\n'; done
    fi
    cat <<EOF
  nodemanager:
    image: *image
    container_name: nodemanager
    hostname: \${NODE_NAME:-$worker_name}
${dep_block}    environment:
      HADOOP_ROLE: nodemanager
      NODE_NAME: \${NODE_NAME:-$worker_name}
    ports:
      - "8040:8040"
      - "8041:8041"
      - "8042:8042"
      - "13562:13562"
      - "32000:32000"
      - "32001:32001"
      # Spark-порты на worker'е:
      #   7077, 7078 — driver-RPC/block-manager. Нужны в --deploy-mode
      #     cluster, когда AM=driver запускается в воркер-контейнере.
      #   7079-7084 — executor block-manager (spark.blockManager.port +
      #     port.maxRetries=5).
      # Без публикации этих портов driver и executor'ы в multi-host
      # Docker не достучатся друг до друга.
      - "7077:7077"
      - "7078:7078"
      - "7079-7084:7079-7084"
    volumes:
      - hadoop_logs:/opt/hadoop/logs
    extra_hosts: *extra_hosts
    restart: unless-stopped

EOF
}

# ─────────────────────────────────────────────────────────────
#  Config file parser
# ─────────────────────────────────────────────────────────────

role_name_to_num() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        namenode)          echo 1 ;;
        secondarynamenode) echo 2 ;;
        resourcemanager)   echo 3 ;;
        historyserver)     echo 4 ;;
        datanode)          echo 5 ;;
        *) echo "ОШИБКА: неизвестная роль '$1'" >&2; exit 1 ;;
    esac
}

parse_cluster_conf() {
    local conf_file="$1"
    local idx=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
        [[ -z "$line" || "$line" == \#* ]] && continue

        local ip roles_str
        ip="$(echo "$line" | awk '{print $1}')"
        roles_str="$(echo "$line" | awk '{$1=""; print}' | sed 's/^[[:space:]]*//')"

        if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            printf "${C_RED}  ОШИБКА: неверный IP в строке: %s${C_RESET}\n" "$line" >&2
            exit 1
        fi

        # Convert role names to numbers
        local nums=""
        for r in $(echo "$roles_str" | tr ',' ' '); do
            r="$(echo "$r" | tr -d ' ')"
            [[ -z "$r" ]] && continue
            local n
            n=$(role_name_to_num "$r")
            nums+="$n,"
        done
        nums="$(echo "$nums" | sed 's/,$//' | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')"

        MACHINE_IPS+=("$ip")
        MACHINE_ROLES+=("$nums")
        MACHINE_WORKER_NAMES+=("")
        idx=$(( idx + 1 ))
    done < "$conf_file"
    machine_count=$idx
}

# ─────────────────────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────────────────────

printf "\n"
printf "${C_CYAN}================================================${C_RESET}\n"
printf "${C_CYAN}  Мастер настройки Hadoop-кластера${C_RESET}\n"
printf "${C_DCYAN}  Hadoop $HADOOP_VERSION  |  Docker  |  Multi-host${C_RESET}\n"
printf "${C_CYAN}================================================${C_RESET}\n"

# Arrays to hold machine data
declare -a MACHINE_IPS=()
declare -a MACHINE_ROLES=()
declare -a MACHINE_WORKER_NAMES=()

# ── Determine config file ──
conf_file=""
if [[ -n "$CONFIG_FILE" ]]; then
    if [[ -f "$CONFIG_FILE" ]]; then
        conf_file="$CONFIG_FILE"
    else
        printf "${C_RED}  ОШИБКА: файл %s не найден${C_RESET}\n" "$CONFIG_FILE"
        exit 1
    fi
elif [[ -f "$REPO_ROOT/cluster.conf" ]]; then
    conf_file="$REPO_ROOT/cluster.conf"
fi

if [[ -n "$conf_file" ]]; then
    # ── Read from config file ──
    printf "\n${C_CYAN}>>> Читаю конфигурацию из %s${C_RESET}\n\n" "$conf_file"
    parse_cluster_conf "$conf_file"

    if (( machine_count < 2 )); then
        printf "${C_RED}  ОШИБКА: в конфиге меньше 2 машин${C_RESET}\n"
        exit 1
    fi

    for (( i = 0; i < machine_count; i++ )); do
        local_names=""
        for r in $(echo "${MACHINE_ROLES[$i]}" | tr ',' ' '); do
            case "$r" in
                1) local_names+="NameNode " ;;
                2) local_names+="SNN " ;;
                3) local_names+="ResourceManager " ;;
                4) local_names+="HistoryServer " ;;
                5) local_names+="DataNode+NM " ;;
            esac
        done
        printf "  ${C_GREEN}%s  ->  %s${C_RESET}\n" "${MACHINE_IPS[$i]}" "$local_names"
    done
else
    # ── Interactive mode ──
    printf "\n${C_YELLOW}>>> cluster.conf не найден — интерактивный режим${C_RESET}\n"
    printf "${C_GRAY}    (создайте cluster.conf из cluster.conf.example для автоматического режима)${C_RESET}\n"

    printf "\n${C_CYAN}>>> Шаг 1: Количество машин${C_RESET}\n"
    machine_count=$(read_validated "Сколько машин в кластере?" "3" '^[0-9]+$')
    if (( machine_count < 2 || machine_count > 20 )); then
        printf "${C_RED}  Допустимо от 2 до 20 машин.${C_RESET}\n"
        exit 1
    fi

    printf "\n${C_CYAN}>>> Шаг 2: Информация о каждой машине${C_RESET}\n\n"
    printf "${C_GRAY}  Роли:${C_RESET}\n"
    printf "${C_GRAY}    1) NameNode              — хранение метаданных HDFS (нужен ровно 1)${C_RESET}\n"
    printf "${C_GRAY}    2) SecondaryNameNode     — чекпоинт NameNode${C_RESET}\n"
    printf "${C_GRAY}    3) ResourceManager       — управление YARN (нужен ровно 1)${C_RESET}\n"
    printf "${C_GRAY}    4) HistoryServer         — история MapReduce-задач${C_RESET}\n"
    printf "${C_GRAY}    5) DataNode + NodeManager — хранение данных + выполнение задач${C_RESET}\n\n"

    for (( i = 1; i <= machine_count; i++ )); do
        printf "${C_YELLOW}  --- Машина $i из $machine_count ---${C_RESET}\n"

        ip=$(read_validated "IP-адрес" "" '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$')
        roles=$(read_validated "Роли (номера через запятую, напр. 1,2,3,4 или 5)" "" '^[1-5](,[[:space:]]*[1-5])*$')

        # Normalize: remove spaces, sort unique
        roles=$(echo "$roles" | tr -d ' ' | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')

        local_names=""
        for r in $(echo "$roles" | tr ',' ' '); do
            case "$r" in
                1) local_names+="NameNode " ;;
                2) local_names+="SNN " ;;
                3) local_names+="ResourceManager " ;;
                4) local_names+="HistoryServer " ;;
                5) local_names+="DataNode+NM " ;;
            esac
        done
        printf "  ${C_GREEN}  -> $local_names${C_RESET}\n\n"

        MACHINE_IPS+=("$ip")
        MACHINE_ROLES+=("$roles")
        MACHINE_WORKER_NAMES+=("")
    done
fi

# ── Validate ──
printf "\n${C_CYAN}>>> Проверка конфигурации${C_RESET}\n"

nn_count=0; rm_count=0; dn_count=0
for roles in "${MACHINE_ROLES[@]}"; do
    [[ "$roles" == *1* ]] && (( nn_count++ )) || true
    [[ "$roles" == *3* ]] && (( rm_count++ )) || true
    [[ "$roles" == *5* ]] && (( dn_count++ )) || true
done

errors=0
if (( nn_count != 1 )); then printf "${C_RED}  ОШИБКА: Нужен ровно 1 NameNode (сейчас: $nn_count)${C_RESET}\n"; errors=1; fi
if (( rm_count != 1 )); then printf "${C_RED}  ОШИБКА: Нужен ровно 1 ResourceManager (сейчас: $rm_count)${C_RESET}\n"; errors=1; fi
if (( dn_count < 1 )); then printf "${C_RED}  ОШИБКА: Нужен минимум 1 DataNode+NodeManager (сейчас: $dn_count)${C_RESET}\n"; errors=1; fi
if (( errors )); then printf "\n${C_YELLOW}Запустите скрипт заново.${C_RESET}\n"; exit 1; fi

# ── 4. Assign worker names ──
w_idx=1
for (( i = 0; i < machine_count; i++ )); do
    if [[ "${MACHINE_ROLES[$i]}" == *5* ]]; then
        MACHINE_WORKER_NAMES[$i]="worker$w_idx"
        (( w_idx++ ))
    fi
done

# Service → IP mappings
nn_ip="" snn_ip="" rm_ip="" hs_ip=""
for (( i = 0; i < machine_count; i++ )); do
    [[ "${MACHINE_ROLES[$i]}" == *1* ]] && nn_ip="${MACHINE_IPS[$i]}"
    [[ "${MACHINE_ROLES[$i]}" == *2* ]] && snn_ip="${MACHINE_IPS[$i]}"
    [[ "${MACHINE_ROLES[$i]}" == *3* ]] && rm_ip="${MACHINE_IPS[$i]}"
    [[ "${MACHINE_ROLES[$i]}" == *4* ]] && hs_ip="${MACHINE_IPS[$i]}"
done
[[ -z "$snn_ip" ]] && snn_ip="$nn_ip"
[[ -z "$hs_ip"  ]] && hs_ip="$rm_ip"

printf "${C_GREEN}  NameNode:           $nn_ip${C_RESET}\n"
[[ "$snn_ip" != "$nn_ip" || "$snn_ip" == "$nn_ip" ]] && printf "${C_GREEN}  SecondaryNameNode:  $snn_ip${C_RESET}\n"
printf "${C_GREEN}  ResourceManager:    $rm_ip${C_RESET}\n"
printf "${C_GREEN}  HistoryServer:      $hs_ip${C_RESET}\n"
for (( i = 0; i < machine_count; i++ )); do
    wn="${MACHINE_WORKER_NAMES[$i]}"
    [[ -n "$wn" ]] && printf "${C_GREEN}  $wn:            ${MACHINE_IPS[$i]}${C_RESET}\n"
done

# ── 5. Build extra_hosts ──
extra_hosts=()
extra_hosts+=("namenode:$nn_ip")
extra_hosts+=("secondarynamenode:$snn_ip")
extra_hosts+=("resourcemanager:$rm_ip")
extra_hosts+=("historyserver:$hs_ip")
for (( i = 0; i < machine_count; i++ )); do
    wn="${MACHINE_WORKER_NAMES[$i]}"
    [[ -n "$wn" ]] && extra_hosts+=("$wn:${MACHINE_IPS[$i]}")
done

extra_hosts_yaml=""
for eh in "${extra_hosts[@]}"; do
    extra_hosts_yaml+="  - \"$eh\""$'\n'
done

# ── 6. Generate files ──
printf "\n${C_CYAN}>>> Шаг 4: Генерация файлов${C_RESET}\n"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

for (( i = 0; i < machine_count; i++ )); do
    ip="${MACHINE_IPS[$i]}"
    roles="${MACHINE_ROLES[$i]}"
    wn="${MACHINE_WORKER_NAMES[$i]}"

    # Label
    if [[ -n "$wn" ]]; then
        label="$wn"
    else
        parts=""
        [[ "$roles" == *1* ]] && parts+="nn-"
        [[ "$roles" == *2* ]] && parts+="snn-"
        [[ "$roles" == *3* ]] && parts+="rm-"
        [[ "$roles" == *4* ]] && parts+="hs-"
        label="${parts%-}"
        [[ -z "$label" ]] && label="node$((i+1))"
    fi

    # ── .env ──
    env_file="$OUTPUT_DIR/$label.env"
    {
        echo "# Сгенерировано setup-cluster.sh"
        echo "# Машина: $label ($ip)"
        echo ""
        echo "HADOOP_VERSION=$HADOOP_VERSION"
    } > "$env_file"

    if [[ -n "$wn" ]]; then
        worker_num="${wn#worker}"
        offset=$(( (worker_num - 1) * 10 ))
        {
            echo ""
            echo "NODE_NAME=$wn"
            echo "DN_HTTP_PORT=$((9864 + offset))"
            echo "DN_XFER_PORT=$((9866 + offset))"
            echo "DN_IPC_PORT=$((9867 + offset))"
        } >> "$env_file"
    fi

    # ── docker-compose ──
    compose_file="$OUTPUT_DIR/$label.yml"
    cat > "$compose_file" <<YAML_HEADER
# Сгенерировано setup-cluster.sh
# Машина: $label ($ip)

x-extra-hosts: &extra_hosts
${extra_hosts_yaml}
x-image: &image clustrer-hadoop:\${HADOOP_VERSION:-$HADOOP_VERSION}

services:

YAML_HEADER

    need_build=1
    volume_list=""

    # NameNode
    if [[ "$roles" == *1* ]]; then
        svc_namenode "$need_build" >> "$compose_file"
        need_build=0
        volume_list+=" namenode_data hadoop_logs"
    fi

    # SecondaryNameNode
    if [[ "$roles" == *2* ]]; then
        deps=()
        [[ "$roles" == *1* ]] && deps+=("namenode")
        svc_secondarynamenode "$need_build" "${deps[@]}" >> "$compose_file"
        need_build=0
        volume_list+=" secondary_data hadoop_logs"
    fi

    # ResourceManager
    if [[ "$roles" == *3* ]]; then
        deps=()
        [[ "$roles" == *1* ]] && deps+=("namenode")
        svc_resourcemanager "$need_build" "${deps[@]}" >> "$compose_file"
        need_build=0
        volume_list+=" hadoop_logs"
    fi

    # HistoryServer
    if [[ "$roles" == *4* ]]; then
        deps=()
        [[ "$roles" == *3* ]] && deps+=("resourcemanager")
        svc_historyserver "$need_build" "${deps[@]}" >> "$compose_file"
        need_build=0
        volume_list+=" hadoop_logs"
    fi

    # DataNode + NodeManager
    if [[ "$roles" == *5* ]]; then
        worker_num="${wn#worker}"
        offset=$(( (worker_num - 1) * 10 ))
        http_port=$((9864 + offset))
        xfer_port=$((9866 + offset))
        ipc_port=$((9867 + offset))

        dn_deps=()
        [[ "$roles" == *1* ]] && dn_deps+=("namenode")
        svc_datanode "$need_build" "$wn" "$http_port" "$xfer_port" "$ipc_port" "${dn_deps[@]}" >> "$compose_file"
        need_build=0
        volume_list+=" datanode_data hadoop_logs"

        nm_deps=("datanode")
        [[ "$roles" == *3* ]] && nm_deps+=("resourcemanager")
        svc_nodemanager "$wn" "${nm_deps[@]}" >> "$compose_file"
    fi

    # Volumes
    unique_volumes=$(echo "$volume_list" | tr ' ' '\n' | sort -u | grep -v '^$')
    echo "volumes:" >> "$compose_file"
    for vn in $unique_volumes; do
        echo "  $vn:" >> "$compose_file"
    done

    printf "  ${C_GREEN}$label.yml  +  $label.env${C_RESET}\n"
done

# ── 7. Update .gitignore ──
gitignore="$REPO_ROOT/.gitignore"
if ! grep -q 'generated/' "$gitignore" 2>/dev/null; then
    echo "" >> "$gitignore"
    echo "generated/" >> "$gitignore"
fi

# ── 8. Instructions ──
printf "\n${C_CYAN}================================================${C_RESET}\n"
printf "${C_CYAN}  Развёртывание кластера${C_RESET}\n"
printf "${C_CYAN}================================================${C_RESET}\n\n"
printf "${C_WHITE}На КАЖДОЙ машине должен быть клонирован репозиторий.${C_RESET}\n"
printf "${C_WHITE}Скопируйте файлы и запускайте в таком порядке:${C_RESET}\n\n"

order=1

# NameNode machine
for (( i = 0; i < machine_count; i++ )); do
    if [[ "${MACHINE_ROLES[$i]}" == *1* ]]; then
        wn="${MACHINE_WORKER_NAMES[$i]}"
        if [[ -n "$wn" ]]; then lbl="$wn"; else
            p=""
            [[ "${MACHINE_ROLES[$i]}" == *1* ]] && p+="nn-"
            [[ "${MACHINE_ROLES[$i]}" == *2* ]] && p+="snn-"
            [[ "${MACHINE_ROLES[$i]}" == *3* ]] && p+="rm-"
            [[ "${MACHINE_ROLES[$i]}" == *4* ]] && p+="hs-"
            lbl="${p%-}"
        fi
        printf "${C_YELLOW}  $order. Машина с NameNode (${MACHINE_IPS[$i]}):${C_RESET}\n"
        printf "${C_WHITE}     cp generated/$lbl.env .env${C_RESET}\n"
        printf "${C_WHITE}     docker compose -f generated/$lbl.yml up -d --build${C_RESET}\n\n"
        (( order++ ))
        break
    fi
done

# Other master-role machines
for (( i = 0; i < machine_count; i++ )); do
    roles="${MACHINE_ROLES[$i]}"
    [[ "$roles" == *1* ]] && continue  # already printed
    has_master=0
    [[ "$roles" == *2* ]] && has_master=1
    [[ "$roles" == *3* ]] && has_master=1
    [[ "$roles" == *4* ]] && has_master=1
    [[ "$has_master" == "0" ]] && continue

    wn="${MACHINE_WORKER_NAMES[$i]}"
    if [[ -n "$wn" ]]; then lbl="$wn"; else
        p=""
        [[ "$roles" == *1* ]] && p+="nn-"
        [[ "$roles" == *2* ]] && p+="snn-"
        [[ "$roles" == *3* ]] && p+="rm-"
        [[ "$roles" == *4* ]] && p+="hs-"
        lbl="${p%-}"
    fi
    rnames=""
    [[ "$roles" == *2* ]] && rnames+="SNN+"
    [[ "$roles" == *3* ]] && rnames+="RM+"
    [[ "$roles" == *4* ]] && rnames+="HS+"
    rnames="${rnames%+}"
    printf "${C_YELLOW}  $order. Машина с $rnames (${MACHINE_IPS[$i]}):${C_RESET}\n"
    printf "${C_WHITE}     cp generated/$lbl.env .env${C_RESET}\n"
    printf "${C_WHITE}     docker compose -f generated/$lbl.yml up -d --build${C_RESET}\n\n"
    (( order++ ))
done

# Worker machines
for (( i = 0; i < machine_count; i++ )); do
    wn="${MACHINE_WORKER_NAMES[$i]}"
    [[ -z "$wn" ]] && continue
    roles="${MACHINE_ROLES[$i]}"
    # skip if already printed as master
    has_master=0
    [[ "$roles" == *1* ]] && has_master=1
    [[ "$roles" == *2* ]] && has_master=1
    [[ "$roles" == *3* ]] && has_master=1
    [[ "$roles" == *4* ]] && has_master=1
    [[ "$has_master" == "1" ]] && continue

    printf "${C_YELLOW}  $order. $wn (${MACHINE_IPS[$i]}):${C_RESET}\n"
    printf "${C_WHITE}     cp generated/$wn.env .env${C_RESET}\n"
    printf "${C_WHITE}     docker compose -f generated/$wn.yml up -d --build${C_RESET}\n\n"
    (( order++ ))
done

printf "${C_WHITE}После запуска всех машин проверьте кластер:${C_RESET}\n"
printf "${C_GRAY}  docker exec namenode hdfs dfsadmin -report${C_RESET}\n"
printf "${C_GRAY}  docker exec resourcemanager yarn node -list${C_RESET}\n\n"
