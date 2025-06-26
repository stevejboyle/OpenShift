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

# Network details from YAML
NETWORK_CIDR=$(yq e '.network.cidr' "$CLUSTER_YAML")

# Ignition Server details from YAML
IGNITION_SERVER_IP=$(yq e '.ignition_server.host_ip' "$CLUSTER_YAML")
IGNITION_SERVER_PORT=$(yq e '.ignition_server.port' "$CLUSTER_YAML")

# --- NEW: Read vCenter CA Certificate File Path from cluster YAML ---
VCENTER_CA_CERT_FILE_PATH=$(yq e '.vcenter_ca_cert_file' "$CLUSTER_YAML")
if [[ ! -f "$VCENTER_CA_CERT_FILE_PATH" ]]; then
  echo "❌ vCenter CA certificate file not found: $VCENTER_CA_CERT_FILE_PATH"
  echo "   Please ensure the path in your cluster YAML is correct and the file exists."
  exit 1
fi
VCENTER_CA_CERT="$(<"$VCENTER_CA_CERT_FILE_PATH")" # Read the certificate content

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
# Add the vCenter CA certificate bundle here
additionalTrustBundle: |
  $VCENTER_CA_CERT
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
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: $NETWORK_CIDR
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
ignition:
  version: 3.2.0
  url: http://${IGNITION_SERVER_IP}:${IGNITION_SERVER_PORT}/${CLUSTER_NAME}/bootstrap.ign
EOF

echo "✅ Generated install-config.yaml at: $INSTALL_DIR/install-config.yaml"
echo "⚠️  Remember to inject vSphere credentials into manifests later (via generate-vsphere-creds-manifest.sh)."
