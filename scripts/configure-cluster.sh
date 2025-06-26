#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster config not found: $CLUSTER_YAML"
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment and validate credentials (this is handled by the master script now)
# source "${SCRIPTS_DIR}/load-vcenter-env.sh"
# echo "✅ vSphere credentials loaded"

# Generate install-config.yaml (This is called before this script in the master script)
# "${SCRIPTS_DIR}/generate-install-config.sh" "$CLUSTER_YAML"

# Create manifests
echo "🛠 Generating OpenShift manifests..."
openshift-install create manifests --dir="install-configs/$(yq '.clusterName' "$CLUSTER_YAML")"

# Inject vSphere credentials into manifests (This is called after this script in the master script)
# "${SCRIPTS_DIR}/generate-vsphere-creds-manifest.sh" "$CLUSTER_YAML"

# Inject console password (This is called after this script in the master script)
# "${SCRIPTS_DIR}/generate-console-password-manifests.sh" "$CLUSTER_YAML"

# Create ignition configs
echo "📦 Creating ignition configs..."
openshift-install create ignition-configs --dir="install-configs/$(yq '.clusterName' "$CLUSTER_YAML")"

echo "✅ Cluster configuration complete"