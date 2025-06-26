#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Usage: $0 <cluster-yaml>"
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source load-vcenter-env.sh to ensure GOVC_USERNAME and GOVC_PASSWORD are set
# This script is responsible for securely prompting for the password.
source "${SCRIPTS_DIR}/load-vcenter-env.sh"

# Now, GOVC_USERNAME and GOVC_PASSWORD should be available in the environment.
# Check if they are set (though load-vcenter-env.sh should handle this).
if [[ -z "${GOVC_USERNAME:-}" || -z "${GOVC_PASSWORD:-}" ]]; then
  echo "❌ vCenter credentials (GOVC_USERNAME or GOVC_PASSWORD) are not set in the environment."
  echo "   Ensure load-vcenter-env.sh is correctly setting them."
  exit 1
fi

CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
MANIFEST_DIR="${SCRIPTS_DIR}/../install-configs/${CLUSTER_NAME}/manifests"

mkdir -p "$MANIFEST_DIR"

cat > "${MANIFEST_DIR}/vsphere-creds-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-cloud-credentials
  namespace: openshift-machine-api
type: Opaque
data:
  username: $(echo -n "$GOVC_USERNAME" | base64)
  password: $(echo -n "$GOVC_PASSWORD" | base64)
EOF

echo "✅ Generated vSphere credentials secret manifest at: ${MANIFEST_DIR}/vsphere-creds-secret.yaml"