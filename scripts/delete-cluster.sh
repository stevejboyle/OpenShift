#!/usr/bin/env bash
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPTS")"

CLUSTER_YAML="$1"

if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

# Load values from cluster YAML
CLUSTER_NAME=$(yq e '.clusterName' "$CLUSTER_YAML")
VM_FOLDER=$(yq e '.vcenter_folder' "$CLUSTER_YAML")
VM_FOLDER="${VM_FOLDE
