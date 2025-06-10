#!/usr/bin/env bash
set -e

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

SCRIPTS="$(dirname "$0")"
source "${SCRIPTS}/load-vcenter-env.sh"

# Get cluster name for directory structure
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
BASE_DIR="$(dirname "$SCRIPTS")"
INSTALL_DIR="${BASE_DIR}/install-configs/${CLUSTER_NAME}"

# Ensure install directory exists
mkdir -p "$INSTALL_DIR"

# 1. Generate install-config
"${SCRIPTS}/generate-install-config.sh" "$CLUSTER_YAML"

# 2. Create manifests
cd "$INSTALL_DIR"
export OPENSHIFT_INSTALL_EXPERIMENTAL_OVERRIDES='{ "disableTemplatedInstallConfig": true }'
openshift-install create manifests
cd "${SCRIPTS}"

# 3. Inject vsphere-creds
"${SCRIPTS}/generate-vsphere-creds-manifest.sh" "$CLUSTER_NAME"

# 4. Inject console password
"${SCRIPTS}/generate-console-password-manifests.sh" "$CLUSTER_YAML"

# 5. Create ignitions
cd "$INSTALL_DIR"
openshift-install create ignition-configs
cd "${SCRIPTS}"

echo "✅ Manifests & ignitions ready; run deploy-vms.sh now."
