FROM eclipse-temurin:11-jre-jammy

ARG HADOOP_VERSION=3.3.6
ARG SPARK_VERSION=3.5.7
ARG SPARK_SCALA_VERSION=2.13
ENV HADOOP_VERSION=${HADOOP_VERSION} \
    SPARK_VERSION=${SPARK_VERSION} \
    SPARK_SCALA_VERSION=${SPARK_SCALA_VERSION} \
    HADOOP_HOME=/opt/hadoop \
    HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop \
    HADOOP_LOG_DIR=/opt/hadoop/logs \
    SPARK_HOME=/opt/spark \
    SPARK_CONF_DIR=/opt/spark/conf \
    HDFS_NAMENODE_USER=root \
    HDFS_DATANODE_USER=root \
    HDFS_SECONDARYNAMENODE_USER=root \
    YARN_RESOURCEMANAGER_USER=root \
    YARN_NODEMANAGER_USER=root \
    HADOOP_DATA_DIR=/data/hdfs \
    PATH=/opt/spark/bin:/opt/hadoop/bin:/opt/hadoop/sbin:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        netcat-openbsd \
        procps \
        python3 \
        tini \
    && rm -rf /var/lib/apt/lists/*

# Download Hadoop. Try the active mirror first, then fall back to the archive.
RUN set -eux; \
    for url in \
        "https://dlcdn.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz" \
        "https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz"; do \
        if curl -fSL --retry 5 --retry-connrefused "$url" -o /tmp/hadoop.tar.gz; then \
            break; \
        fi; \
    done; \
    test -s /tmp/hadoop.tar.gz; \
    tar -xzf /tmp/hadoop.tar.gz -C /opt; \
    mv "/opt/hadoop-${HADOOP_VERSION}" "${HADOOP_HOME}"; \
    rm /tmp/hadoop.tar.gz; \
    mkdir -p "${HADOOP_DATA_DIR}/namenode" "${HADOOP_DATA_DIR}/datanode" \
             "${HADOOP_DATA_DIR}/secondary" "${HADOOP_DATA_DIR}/tmp" \
             "${HADOOP_LOG_DIR}"

# Download Spark (precompiled with Hadoop3+Scala 2.13).  We use the same
# pattern as Hadoop above: active mirror first, archive as fallback.
#
# Spark is installed in /opt/spark so that `spark-submit --master yarn`
# works from any cluster container — HADOOP_CONF_DIR points it at the
# already-configured YARN/HDFS.
RUN set -eux; \
    SPARK_TGZ="spark-${SPARK_VERSION}-bin-hadoop3-scala${SPARK_SCALA_VERSION}.tgz"; \
    for url in \
        "https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/${SPARK_TGZ}" \
        "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/${SPARK_TGZ}"; do \
        if curl -fSL --retry 5 --retry-connrefused "$url" -o /tmp/spark.tgz; then \
            break; \
        fi; \
    done; \
    test -s /tmp/spark.tgz; \
    tar -xzf /tmp/spark.tgz -C /opt; \
    mv "/opt/spark-${SPARK_VERSION}-bin-hadoop3-scala${SPARK_SCALA_VERSION}" "${SPARK_HOME}"; \
    rm /tmp/spark.tgz

# Минимальные Spark-настройки: говорим Spark, что master = YARN, и где
# лежат конфиги Hadoop.  Этого достаточно, чтобы spark-submit без флагов
# отправлял job на YARN. Тонкости (память/ядра executors) можно
# переопределять флагами командной строки.
COPY config/spark-defaults.conf ${SPARK_CONF_DIR}/spark-defaults.conf
COPY config/ ${HADOOP_CONF_DIR}/
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

# Срезаем CR-символы на случай, если репо клонировали на Windows с
# core.autocrlf=true: иначе shebang `#!/usr/bin/env bash\r` ломает запуск.
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh \
        "${HADOOP_CONF_DIR}/hadoop-env.sh" \
        "${HADOOP_CONF_DIR}/workers" \
        "${SPARK_CONF_DIR}/spark-defaults.conf" \
    && chmod +x /usr/local/bin/entrypoint.sh \
    && rm -f "${HADOOP_CONF_DIR}/spark-defaults.conf"

# Информационно: NameNode RPC/UI, DataNode, SecondaryNameNode,
# ResourceManager, NodeManager, HistoryServer, MR shuffle, AM port range.
EXPOSE 9000 9870 9864 9866 9867 9868 \
       8030 8031 8032 8033 8088 \
       8040 8041 8042 13562 \
       19888 10020 \
       32000-32100

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
