#!/usr/bin/env bash
# Build SimpleApp and run the LineCount MapReduce job.
#
# Usage:
#   ./scripts/run-simpleapp.sh                                 # default paths
#   ./scripts/run-simpleapp.sh /my/input /my/output            # custom paths
#
# For multi-host cluster: run this on the master node where
# namenode and resourcemanager containers are available.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR_NAME="SimpleApp-1.0-SNAPSHOT.jar"
JAR_PATH="${REPO_ROOT}/app/SimpleApp/target/${JAR_NAME}"

# ---------- 1. Build JAR if not yet built ----------
if [[ ! -f "$JAR_PATH" ]]; then
    echo "=== JAR not found, starting build ==="
    bash "${REPO_ROOT}/scripts/build-app.sh"
fi

# ---------- 2. Find running container ----------
SUBMIT_CONTAINER=""
for c in resourcemanager namenode; do
    if docker inspect --format='{{.State.Running}}' "$c" 2>/dev/null | grep -q true; then
        SUBMIT_CONTAINER="$c"
        break
    fi
done
if [[ -z "$SUBMIT_CONTAINER" ]]; then
    echo "ERROR: no running namenode or resourcemanager container found." >&2
    echo "Make sure the cluster is up (docker compose ... up -d)." >&2
    exit 1
fi
echo "=== Using container: ${SUBMIT_CONTAINER} ==="

# Find HDFS client container (namenode)
HDFS_CONTAINER="namenode"
if ! docker inspect --format='{{.State.Running}}' "$HDFS_CONTAINER" 2>/dev/null | grep -q true; then
    HDFS_CONTAINER="$SUBMIT_CONTAINER"
fi

# ---------- 3. Copy JAR into container ----------
echo "=== Copying JAR into container ==="
docker cp "$JAR_PATH" "${SUBMIT_CONTAINER}:/tmp/${JAR_NAME}"

# ---------- 4. Verify input data exists in HDFS ----------
HDFS_INPUT="${1:-/user/demo/input}"
HDFS_OUTPUT="${2:-/user/demo/output}"

echo "=== Checking HDFS input (${HDFS_INPUT}) ==="

if ! docker exec "$HDFS_CONTAINER" hdfs dfs -test -d "$HDFS_INPUT" 2>/dev/null; then
    echo "ERROR: input directory ${HDFS_INPUT} does not exist in HDFS." >&2
    echo "Upload your data first, e.g.:" >&2
    echo "  docker exec namenode hdfs dfs -mkdir -p ${HDFS_INPUT}" >&2
    echo "  docker exec namenode hdfs dfs -put <local_file> ${HDFS_INPUT}/" >&2
    exit 1
fi

# Remove previous output if exists
docker exec "$HDFS_CONTAINER" hdfs dfs -rm -r -f "$HDFS_OUTPUT" 2>/dev/null || true

# ---------- 5. Run MapReduce job ----------
echo ""
echo "=== Running LineCount MapReduce on YARN ==="
echo "    Input:  ${HDFS_INPUT}"
echo "    Output: ${HDFS_OUTPUT}"
echo ""

# Main-Class is already set in the JAR manifest (pom.xml maven-jar-plugin),
# so do NOT pass the class name here — otherwise hadoop jar treats it as
# an extra argument and the app receives 3 args instead of 2.
docker exec "$SUBMIT_CONTAINER" \
    hadoop jar "/tmp/${JAR_NAME}" \
    -Ddfs.client.use.datanode.hostname=true \
    "$HDFS_INPUT" "$HDFS_OUTPUT"

# ---------- 6. Show results ----------
echo ""
echo "=== Result ==="
docker exec "$HDFS_CONTAINER" hdfs dfs -cat "${HDFS_OUTPUT}/part-r-00000"
echo ""
echo "=== Done! ==="
