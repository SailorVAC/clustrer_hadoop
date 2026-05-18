#!/usr/bin/env bash
# Spark env-script.  Sourced by spark-submit / spark-shell / executor launch
# scripts before any JVM starts.
#
# In our multi-host Docker setup each container has two IPs in /etc/hosts:
#   - the Docker bridge IP (added by Docker, e.g. 172.18.0.5)
#   - the LAN IP (added via `extra_hosts` so peers can reach this container)
#
# Java's InetAddress.getLocalHost() typically picks the bridge IP, and
# without an explicit hint Spark would advertise it as `driver.host` /
# executor address.  Peers on other LAN hosts can't route to 172.18.x.y,
# so they hang on Spark RPC connect.
#
# Setting SPARK_LOCAL_HOSTNAME to the container's logical hostname
# (`resourcemanager`, `namenode`, `worker1`, `worker2`, ...) makes Spark
# advertise that name; every container in the cluster has the matching
# hostname → LAN IP mapping via `extra_hosts`, so peers can connect.
export SPARK_LOCAL_HOSTNAME="${SPARK_LOCAL_HOSTNAME:-$(hostname)}"
