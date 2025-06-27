#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster config not found: $CLUSTER_YAML"
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
INSTALL_DIR="install-configs/${CLUSTER_NAME}"

# Generate manifests
openshift-install create manifests --dir="${INSTALL_DIR}"

# Create ignition configs
openshift-install create ignition-configs --dir="${INSTALL_DIR}"

echo "✅ Cluster configuration complete"
