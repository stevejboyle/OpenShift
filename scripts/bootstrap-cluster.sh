#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Unified credential loader
source "${SCRIPT_DIR}/load-vcenter-env.sh"

# Handle cluster file input
CLUSTER_FILE_RELATIVE="$1"
if [ -z "$CLUSTER_FILE_RELATIVE" ]; then
  echo "Usage: $0 <cluster.yaml>"
  echo "Example: $0 clusters/ocp416.yaml"
  exit 1
fi

# Normalize full absolute path
CLUSTER_FILE="$(cd "${BASE_DIR}" && realpath "${CLUSTER_FILE_RELATIVE}")"

if [ ! -f "${CLUSTER_FILE}" ]; then
  echo "❌ Cluster file not found: ${CLUSTER_FILE_RELATIVE}"
  exit 1
fi

# Verify all required assets
REQUIRED_ASSETS=(
  "assets/pull-secret.json"
  "assets/ssh-key.pub"
  "assets/rhcos-4.16.36-x86_64-vmware.x86_64.ova"
)

for file in "${REQUIRED_ASSETS[@]}"; do
  if [ ! -f "${BASE_DIR}/${file}" ]; then
    echo "❌ Missing required asset: ${file}"
    exit 1
  fi
done

echo "✅ All required files found. Starting deployment..."

# Call deploy-cluster
${BASE_DIR}/scripts/deploy-cluster.sh "${CLUSTER_FILE}"

echo "🎉 Deployment complete."
