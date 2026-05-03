# Минимальный hadoop-env.sh для контейнерного запуска.

export JAVA_HOME=${JAVA_HOME:-/opt/java/openjdk}
export HADOOP_HOME=${HADOOP_HOME:-/opt/hadoop}
export HADOOP_CONF_DIR=${HADOOP_CONF_DIR:-/opt/hadoop/etc/hadoop}
export HADOOP_LOG_DIR=${HADOOP_LOG_DIR:-/opt/hadoop/logs}

# Демоны запускаются от root внутри контейнера — это безопасно для учебного
# кластера, и Hadoop требует явного объявления пользователя для каждой роли.
export HDFS_NAMENODE_USER=root
export HDFS_DATANODE_USER=root
export HDFS_SECONDARYNAMENODE_USER=root
export YARN_RESOURCEMANAGER_USER=root
export YARN_NODEMANAGER_USER=root
export MAPRED_HISTORYSERVER_USER=root

# Heap для демонов учебного кластера.
export HADOOP_HEAPSIZE_MAX=1024m
export HADOOP_HEAPSIZE_MIN=256m
