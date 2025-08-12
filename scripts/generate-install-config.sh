#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ -z "${CLUSTER_YAML:-}" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

SCRIPTS_DIR="$(dirname "$0")"
BASE_DIR="$(dirname "$SCRIPTS_DIR")"
CLUSTER_NAME="$(yq e '.clusterName' "$CLUSTER_YAML")"
INSTALL_DIR="$BASE_DIR/install-configs/$CLUSTER_NAME"
mkdir -p "$INSTALL_DIR" || { echo "❌ Failed to create directory: $INSTALL_DIR"; exit 1; }

echo "DEBUG: CLUSTER_NAME=$CLUSTER_NAME"
echo "DEBUG: INSTALL_DIR=$INSTALL_DIR"

BASE_DOMAIN=$(yq e '.baseDomain' "$CLUSTER_YAML")
VCENTER_SERVER=$(yq e '.vcenter_server' "$CLUSTER_YAML")
VCENTER_USERNAME=$(yq e '.vcenter_username' "$CLUSTER_YAML")
VCENTER_DATACENTER=$(yq e '.vcenter_datacenter' "$CLUSTER_YAML")
VCENTER_CLUSTER=$(yq e '.vcenter_cluster' "$CLUSTER_YAML")
VCENTER_DATASTORE=$(yq e '.vcenter_datastore' "$CLUSTER_YAML")
VCENTER_NETWORK=$(yq e '.vcenter_network' "$CLUSTER_YAML")

if [[ -z "${GOVC_PASSWORD:-}" ]]; then
  echo "❌ GOVC_PASSWORD is not set (source load-vcenter-env.sh first)."
  exit 1
fi
echo "DEBUG: GOVC_PASSWORD_LENGTH=${#GOVC_PASSWORD} bytes"

SSH_KEY_FILE_PATH=$(yq e '.sshKeyFile' "$CLUSTER_YAML")
[[ -f "$SSH_KEY_FILE_PATH" ]] || { echo "❌ SSH key file not found: $SSH_KEY_FILE_PATH"; exit 1; }
SSH_KEY=$(<"$SSH_KEY_FILE_PATH")
echo "DEBUG: SSH_KEY_LENGTH=${#SSH_KEY} bytes"

PULL_SECRET_FILE_PATH=$(yq e '.pullSecretFile' "$CLUSTER_YAML")
[[ -f "$PULL_SECRET_FILE_PATH" ]] || { echo "❌ Pull secret file not found: $PULL_SECRET_FILE_PATH"; exit 1; }
PULL_SECRET=$(<"$PULL_SECRET_FILE_PATH")
echo "DEBUG: PULL_SECRET_LENGTH=${#PULL_SECRET} bytes"

NETWORK_CIDR=$(yq e '.network.cidr' "$CLUSTER_YAML")

MASTER_REPLICAS=$(yq '.node_counts.master // 3' "$CLUSTER_YAML")
WORKER_REPLICAS=$(yq '.node_counts.worker // 2' "$CLUSTER_YAML")
echo "DEBUG: MASTER_REPLICAS=$MASTER_REPLICAS"
echo "DEBUG: WORKER_REPLICAS=$WORKER_REPLICAS"

VCENTER_CA_CERT_FILE_PATH=$(yq e '.vcenter_ca_cert_file' "$CLUSTER_YAML")
[[ -f "$VCENTER_CA_CERT_FILE_PATH" ]] || { echo "❌ vCenter CA certificate file not found: $VCENTER_CA_CERT_FILE_PATH"; exit 1; }

cat > "$INSTALL_DIR/install-config.yaml" <<EOF || { echo "❌ Failed to write install-config.yaml"; exit 1; }
apiVersion: v1
baseDomain: $BASE_DOMAIN
metadata:
  name: $CLUSTER_NAME
platform:
  none: {}
additionalTrustBundle: |
$(tr -d '\r' < "$VCENTER_CA_CERT_FILE_PATH" | awk '{printf "      %s\n", $0}')
pullSecret: |
  $PULL_SECRET
sshKey: |
  $SSH_KEY
controlPlane:
  name: master
  replicas: ${MASTER_REPLICAS}
compute:
- name: worker
  replicas: ${WORKER_REPLICAS}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: $NETWORK_CIDR
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
EOF

GENERATED_FILE_SIZE=$(stat -f %z "$INSTALL_DIR/install-config.yaml" 2>/dev/null || stat -c %s "$INSTALL_DIR/install-config.yaml" 2>/dev/null)
if [[ "$GENERATED_FILE_SIZE" -eq 0 ]]; then
  echo "❌ Error: install-config.yaml is zero bytes!"
  exit 1
else
  echo "DEBUG: Generated install-config.yaml size: $GENERATED_FILE_SIZE bytes"
fi

echo "✅ Generated install-config.yaml at: $INSTALL_DIR/install-config.yaml"
