#!/bin/bash
set -e

# Always resolve absolute script root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Handle argument safely
CLUSTER_FILE_RELATIVE="$1"
if [ -z "$CLUSTER_FILE_RELATIVE" ]; then
  echo "Usage: $0 <cluster.yaml>"
  echo "Example: $0 clusters/ocp416.yaml"
  exit 1
fi

# Build full absolute path regardless of caller cwd
CLUSTER_FILE="${BASE_DIR}/${CLUSTER_FILE_RELATIVE}"

# Validate cluster file
if [ ! -f "${CLUSTER_FILE}" ]; then
  echo "❌ Cluster file not found: ${CLUSTER_FILE_RELATIVE}"
  exit 1
fi

# Load vCenter credentials
source "${SCRIPT_DIR}/load-vcenter-env.sh"

# Step 1: Delete existing cluster
echo "🧹 Starting full cleanup of cluster: ${CLUSTER_FILE_RELATIVE}..."
${SCRIPT_DIR}/delete-cluster.sh "${CLUSTER_FILE}"

# Step 2: Redeploy cluster
echo "🚀 Starting full redeploy of cluster: ${CLUSTER_FILE_RELATIVE}..."
${SCRIPT_DIR}/bootstrap-cluster.sh "${CLUSTER_FILE}"

echo "🎉 Full rebuild complete."
