#!/usr/bin/env bash
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPTS")"

CLUSTER_YAML="$1"

if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

CLUSTER_NAME=$(yq e '.clusterName' "$CLUSTER_YAML")
INSTALL_DIR="$BASE_DIR/install-configs/$CLUSTER_NAME"
MANIFESTS_DIR="$INSTALL_DIR/manifests"

mkdir -p "$MANIFESTS_DIR"

VCENTER_SERVER=$(yq e '.vcenter.server' "$CLUSTER_YAML")
VCENTER_USERNAME=$(yq e '.vcenter.username' "$CLUSTER_YAML")
VCENTER_PASSWORD=$(yq e '.vcenter.password' "$CLUSTER_YAML")

if [[ -z "$VCENTER_SERVER" || -z "$VCENTER_USERNAME" || -z "$VCENTER_PASSWORD" ]]; then
  echo "❌ Missing vCenter credentials in YAML"
  exit 1
fi

cat > "${MANIFESTS_DIR}/vsphere-cloud-creds.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-creds
  namespace: openshift-config
type: Opaque
stringData:
  ${VCENTER_SERVER}.username: ${VCENTER_USERNAME}
  ${VCENTER_SERVER}.password: ${VCENTER_PASSWORD}
EOF

echo "✅ vSphere credentials manifest created: ${MANIFESTS_DIR}/vsphere-cloud-creds.yaml"
