#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

source "${SCRIPT_DIR}/load-vcenter-env.sh"
export VSPHERE_USERNAME="$GOVC_USERNAME"
export VSPHERE_PASSWORD="$GOVC_PASSWORD"

# Full rebuild
"${SCRIPT_DIR}/delete-cluster.sh" "$CLUSTER_YAML"
"${SCRIPT_DIR}/deploy-cluster.sh" "$CLUSTER_YAML"
"${SCRIPT_DIR}/deploy-vms.sh"     "$CLUSTER_YAML"
