#!/bin/bash
set -e

# Where am I?
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Verify govc.env exists
if [ ! -f "${BASE_DIR}/govc.env" ]; then
  echo "❌ govc.env not found in base directory: ${BASE_DIR}"
  exit 1
fi

# Source govc.env
source "${BASE_DIR}/govc.env"

# Prompt for govc password
echo "🔐 Please enter your vSphere password for ${GOVC_USERNAME}:"
read -s GOVC_PASSWORD
export GOVC_PASSWORD

# Verify cluster YAML exists
CLUSTER_FILE="$1"
if [ -z "$CLUSTER_FILE" ]; then
  echo "Usage: $0 <cluster.yaml>"
  echo "Example: $0 clusters/ocp416.yaml"
  exit 1
fi

if [ ! -f "${BASE_DIR}/${CLUSTER_FILE}" ]; then
  echo "❌ Cluster file not found: ${CLUSTER_FILE}"
  exit 1
fi

# Verify required asset files
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

# Call main deployment script
${BASE_DIR}/scripts/deploy-cluster.sh "${BASE_DIR}/${CLUSTER_FILE}"

echo "🎉 Deployment complete."
