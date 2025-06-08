#!/bin/bash
set -e

# Where am I?
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Validate argument
CLUSTER_FILE="$1"
if [ -z "$CLUSTER_FILE" ]; then
  echo "Usage: $0 <cluster.yaml>"
  echo "Example: $0 clusters/ocp416.yaml"
  exit 1
fi

# Validate cluster file exists
if [ ! -f "${BASE_DIR}/${CLUSTER_FILE}" ]; then
  echo "❌ Cluster file not found: ${CLUSTER_FILE}"
  exit 1
fi

# Load govc.env
if [ ! -f "${BASE_DIR}/govc.env" ]; then
  echo "❌ govc.env not found!"
  exit 1
fi
source "${BASE_DIR}/govc.env"

# Prompt for govc password (interactive as usual)
echo "🔐 Please enter your vSphere password for ${GOVC_USERNAME}:"
read -s GOVC_PASSWORD
export GOVC_PASSWORD

# Step 1: Delete existing cluster
echo "🧹 Starting full cleanup of cluster: ${CLUSTER_FILE}..."
${BASE_DIR}/scripts/delete-cluster.sh "${BASE_DIR}/${CLUSTER_FILE}"

# Step 2: Redeploy cluster
echo "🚀 Starting full redeploy of cluster: ${CLUSTER_FILE}..."
${BASE_DIR}/scripts/bootstrap-cluster.sh "${BASE_DIR}/${CLUSTER_FILE}"

echo "🎉 Full rebuild complete."
