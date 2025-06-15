#!/usr/bin/env bash
set -euo pipefail

# Usage: ./generate-install-config.sh <cluster-yaml>

CLUSTER_YAML="$1"
if [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

SCRIPTS_DIR="$(dirname "$0")"
BASE_DIR="$(dirname "$SCRIPTS_DIR")"
CLUSTER_NAME="$(yq e '.clusterName' "$CLUSTER_YAML")"
INSTALL_DIR="$BASE_DIR/install-configs/$CLUSTER_NAME"
mkdir -p "$INSTALL_DIR"

# Load fields from YAML
BASE_DOMAIN="$(yq e '.baseDomain' "$CLUSTER_YAML")"
VCENTER_SERVER="$(yq e '.vcenter_server' "$CLUSTER_YAML")"
VCENTER_USERNAME="$(yq e '.vcenter_username' "$CLUSTER_YAML")"
VCENTER_DATACENTER="$(yq e '.vcenter_datacenter' "$CLUSTER_YAML")"
VCENTER_CLUSTER="$(yq e '.vcenter_cluster' "$CLUSTER_YAML")"
VCENTER_DATASTORE="$(yq e '.vcenter_datastore' "$CLUSTER_YAML")"
VCENTER_NETWORK="$(yq e '.vcenter_network' "$CLUSTER_YAML")"
SSH_KEY="$(<"$(yq e '.sshKeyFile' "$CLUSTER_YAML")")"
PULL_SECRET="$(<"$(yq e '.pullSecretFile' "$CLUSTER_YAML")")"

# Full paths required for OpenShift installer
CLUSTER_PATH="/$VCENTER_DATACENTER/host/$VCENTER_CLUSTER"
DATASTORE_PATH="/$VCENTER_DATACENTER/datastore/$VCENTER_DATASTORE"

cat > "$INSTALL_DIR/install-config.yaml" <<EOF
apiVersion: v1
baseDomain: $BASE_DOMAIN
metadata:
  name: $CLUSTER_NAME
platform:
  vsphere:
    vcenters:
    - server: $VCENTER_SERVER
      user: $VCENTER_USERNAME
      password: PLACEHOLDER_PASSWORD
      datacenters:
      - $VCENTER_DATACENTER
    failureDomains:
    - name: primary
      server: $VCENTER_SERVER
      region: region-a
      zone: zone-a
      topology:
        datacenter: $VCENTER_DATACENTER
        computeCluster: $CLUSTER_PATH
        datastore: $DATASTORE_PATH
        networks:
        - "$VCENTER_NETWORK"
pullSecret: |
  $PULL_SECRET
sshKey: |
  $SSH_KEY
controlPlane:
  name: master
  replicas: 3
compute:
- name: worker
  replicas: 0
EOF

echo "✅ Generated install-config.yaml at: $INSTALL_DIR/install-config.yaml"
echo "⚠️  Remember to inject credentials later (via manifests or automation script)."

