#!/bin/zsh
set -e

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

SCRIPTS="$(dirname "$0")"
source "${SCRIPTS}/load-vcenter-env.sh"

# 1. Generate install-config
"${SCRIPTS}/generate-install-config.sh" "$CLUSTER_YAML"

# 2. Create manifests
cd "$(dirname "$SCRIPTS")/install-configs"
export OPENSHIFT_INSTALL_EXPERIMENTAL_OVERRIDES='{ "disableTemplatedInstallConfig": true }'
openshift-install create manifests
cd "${SCRIPTS}"

# 3. Inject vsphere-creds
"${SCRIPTS}/generate-vsphere-creds-manifest.sh"

# 4. Inject console password
"${SCRIPTS}/generate-console-password-manifests.sh" "$CLUSTER_YAML"

# 5. Create ignitions
cd "$(dirname "$SCRIPTS")/install-configs"
openshift-install create ignition-configs
cd "${SCRIPTS}"

echo "✅ Manifests & ignitions ready; run deploy-vms.sh now."
