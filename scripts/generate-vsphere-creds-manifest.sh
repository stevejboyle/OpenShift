#!/usr/bin/env bash
set -eo pipefail

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" ]]; then
  echo "❌ Usage: $0 <cluster-yaml>"
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_NAME="$(basename "$CLUSTER_YAML" .yaml)"
CLUSTER_DIR="${SCRIPTS_DIR}/../install-configs/${CLUSTER_NAME}"
MANIFEST_DIR="${CLUSTER_DIR}/manifests"

VC_USERNAME=$(yq '.vcenter_username' "$CLUSTER_YAML")
VC_PASSWORD=$(yq '.vcenter_password' "$CLUSTER_YAML")

if [[ -z "$VC_USERNAME" || -z "$VC_PASSWORD" ]]; then
  echo "❌ Missing vCenter credentials in cluster YAML"
  exit 1
fi

mkdir -p "$MANIFEST_DIR"

cat > "${MANIFEST_DIR}/vsphere-creds-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-cloud-credentials
  namespace: openshift-machine-api
type: Opaque
data:
  username: $(echo -n "$VC_USERNAME" | base64)
  password: $(echo -n "$VC_PASSWORD" | base64)
EOF

echo "✅ Generated vSphere credentials secret manifest at: ${MANIFEST_DIR}/vsphere-creds-secret.yaml"
