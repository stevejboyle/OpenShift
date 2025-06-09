#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_FILE="$1"

if [[ -z "$CLUSTER_FILE" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

if [[ ! -f "$CLUSTER_FILE" ]]; then
  echo "❌ Cluster file not found: $CLUSTER_FILE"
  exit 1
fi

source "${SCRIPT_DIR}/load-vcenter-env.sh"

# Export for OpenShift installer compatibility
export VSPHERE_USERNAME="${GOVC_USERNAME}"
export VSPHERE_PASSWORD="${GOVC_PASSWORD}"
export OPENSHIFT_INSTALL_EXPERIMENTAL_OVERRIDES='{ "disableTemplatedInstallConfig": true }'

CLUSTER_NAME=$(yq '.clusterName' "$CLUSTER_FILE")
BASE_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_CONFIGS_DIR="${BASE_DIR}/install-configs"

echo "🧼 Cleaning previous install-configs..."
rm -rf "${INSTALL_CONFIGS_DIR}"
mkdir -p "${INSTALL_CONFIGS_DIR}"

echo "🛠️  Generating install-config.yaml..."
"${SCRIPT_DIR}/generate-install-config.sh" "$CLUSTER_FILE"

cd "$INSTALL_CONFIGS_DIR"

echo "🛠️  Creating manifests..."
openshift-install create manifests

cd "$BASE_DIR"
echo "🔐 Injecting vsphere-creds manifest..."
"${SCRIPT_DIR}/generate-vsphere-creds-manifest.sh"

if [[ -f "${SCRIPT_DIR}/generate-console-password-manifests.sh" ]]; then
  echo "🔑 Injecting optional console password manifest (if configured)..."
  "${SCRIPT_DIR}/generate-console-password-manifests.sh" "$CLUSTER_FILE"
fi

cd "$INSTALL_CONFIGS_DIR"
echo "🔥 Creating ignition-configs..."
openshift-install create ignition-configs

cd "$BASE_DIR"
echo "🚀 Ready to deploy. Use:"
echo "./scripts/deploy-vms.sh $CLUSTER_FILE"
