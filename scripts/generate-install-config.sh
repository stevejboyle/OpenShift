#!/usr/bin/env bash
set -euo pipefail

# Usage: ./generate-install-config.sh <cluster-yaml>

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
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

# Load fields from YAML with explicit error handling and debug output
BASE_DOMAIN=$(yq e '.baseDomain' "$CLUSTER_YAML" || { echo "❌ Failed to read baseDomain from $CLUSTER_YAML"; exit 1; })
VCENTER_SERVER=$(yq e '.vcenter_server' "$CLUSTER_YAML" || { echo "❌ Failed to read vcenter_server from $CLUSTER_YAML"; exit 1; })
VCENTER_USERNAME=$(yq e '.vcenter_username' "$CLUSTER_YAML" || { echo "❌ Failed to read vcenter_username from $CLUSTER_YAML"; exit 1; })
VCENTER_DATACENTER=$(yq e '.vcenter_datacenter' "$CLUSTER_YAML" || { echo "❌ Failed to read vcenter_datacenter from $CLUSTER_YAML"; exit 1; })
VCENTER_CLUSTER=$(yq e '.vcenter_cluster' "$CLUSTER_YAML" || { echo "❌ Failed to read vcenter_cluster from $CLUSTER_YAML"; exit 1; })
VCENTER_DATASTORE=$(yq e '.vcenter_datastore' "$CLUSTER_YAML" || { echo "❌ Failed to read vcenter_datastore from $CLUSTER_YAML"; exit 1; })
VCENTER_NETWORK=$(yq e '.vcenter_network' "$CLUSTER_YAML" || { echo "❌ Failed to read vcenter_network from $CLUSTER_YAML"; exit 1; })

# Use GOVC_PASSWORD from environment
if [[ -z "${GOVC_PASSWORD:-}" ]]; then
  echo "❌ GOVC_PASSWORD environment variable is not set."
  echo "   Ensure load-vcenter-env.sh was sourced correctly before calling this script."
  exit 1
fi
echo "DEBUG: GOVC_PASSWORD_LENGTH=${#GOVC_PASSWORD} bytes"

SSH_KEY_FILE_PATH=$(yq e '.sshKeyFile' "$CLUSTER_YAML" || { echo "❌ Failed to read sshKeyFile path from $CLUSTER_YAML"; exit 1; })
if [[ ! -f "$SSH_KEY_FILE_PATH" ]]; then echo "❌ SSH key file not found: $SSH_KEY_FILE_PATH"; exit 1; fi
SSH_KEY=$(cat "$SSH_KEY_FILE_PATH" | tr -d '\r\n' | sed 's/^[ \t]*//;s/[ \t]*$//')
echo "DEBUG: SSH_KEY_LENGTH=${#SSH_KEY} bytes"

PULL_SECRET_FILE_PATH=$(yq e '.pullSecretFile' "$CLUSTER_YAML" || { echo "❌ Failed to read pullSecretFile path from $CLUSTER_YAML"; exit 1; })
if [[ ! -f "$PULL_SECRET_FILE_PATH" ]]; then echo "❌ Pull secret file not found: $PULL_SECRET_FILE_PATH"; exit 1; fi
PULL_SECRET=$(<"$PULL_SECRET_FILE_PATH")
echo "DEBUG: PULL_SECRET_LENGTH=${#PULL_SECRET} bytes"

# Network details from YAML
NETWORK_CIDR=$(yq e '.network.cidr' "$CLUSTER_YAML" || { echo "❌ Failed to read network.cidr from $CLUSTER_YAML"; exit 1; })

# Ignition Server details from YAML
IGNITION_SERVER_IP=$(yq e '.ignition_server.host_ip' "$CLUSTER_YAML" || { echo "❌ Failed to read ignition_server.host_ip from $CLUSTER_YAML"; exit 1; })
IGNITION_SERVER_PORT=$(yq e '.ignition_server.port' "$CLUSTER_YAML" || { echo "❌ Failed to read ignition_server.port from $CLUSTER_YAML"; exit 1; })

# --- NEW: Read node counts from cluster YAML ---
MASTER_REPLICAS=$(yq '.node_counts.master' "$CLUSTER_YAML" || { echo "❌ Failed to read node_counts.master from $CLUSTER_YAML"; exit 1; })
WORKER_REPLICAS=$(yq '.node_counts.worker' "$CLUSTER_YAML" || { echo "❌ Failed to read node_counts.worker from $CLUSTER_YAML"; exit 1; })
echo "DEBUG: MASTER_REPLICAS=$MASTER_REPLICAS"
echo "DEBUG: WORKER_REPLICAS=$WORKER_REPLICAS"
# --- END NEW ---

# Read vCenter CA Certificate File Path from cluster YAML
VCENTER_CA_CERT_FILE_PATH=$(yq e '.vcenter_ca_cert_file' "$CLUSTER_YAML" || { echo "❌ Failed to read vcenter_ca_cert_file path from $CLUSTER_YAML"; exit 1; })
if [[ ! -f "$VCENTER_CA_CERT_FILE_PATH" ]]; then
  echo "❌ vCenter CA certificate file not found: $VCENTER_CA_CERT_FILE_PATH"
  echo "   Please ensure the path in your cluster YAML is correct and the file exists."
  exit 1
fi
VCENTER_CA_CERT="$(cat "$VCENTER_CA_CERT_FILE_PATH" | tr -d '\r' | sed 's/^[ \t]*//g')"

# Debugging: Print a few critical variables
echo "DEBUG: BASE_DOMAIN=$BASE_DOMAIN"
echo "DEBUG: VCENTER_SERVER=$VCENTER_SERVER"
echo "DEBUG: PULL_SECRET_LENGTH=${#PULL_SECRET} bytes"
echo "DEBUG: SSH_KEY_LENGTH=${#SSH_KEY} bytes"
# Only print if VCENTER_CA_CERT is not empty
if [[ -n "$VCENTER_CA_CERT" ]]; then
  echo "DEBUG: VCENTER_CA_CERT_LENGTH=${#VCENTER_CA_CERT} bytes"
  echo "DEBUG: Processed cert content (first 5 lines, stripped of internal leading spaces):"
  echo "$VCENTER_CA_CERT" | head -n 5
else
  echo "DEBUG: VCENTER_CA_CERT is empty or not found."
fi

# Full paths required for OpenShift installer
CLUSTER_PATH="/$VCENTER_DATACENTER/host/$VCENTER_CLUSTER"
DATASTORE_PATH="/$VCENTER_DATACENTER/datastore/$VCENTER_DATASTORE"

# Execute the cat command and redirect to the install-config.yaml
cat > "$INSTALL_DIR/install-config.yaml" <<EOF || { echo "❌ Failed to write install-config.yaml content due to 'cat' failure."; exit 1; }
apiVersion: v1
baseDomain: $BASE_DOMAIN
metadata:
  name: $CLUSTER_NAME
platform:
  vsphere:
    vcenters:
    - server: $VCENTER_SERVER
      user: $VCENTER_USERNAME
      password: $GOVC_PASSWORD
      datacenters:
      - Lab
    failureDomains:
    - name: primary
      server: $VCENTER_SERVER
      region: region-a
      zone: zone-a
      topology:
        datacenter: Lab
        computeCluster: $CLUSTER_PATH
        datastore: $DATASTORE_PATH
        networks:
        - "$VCENTER_NETWORK"
  additionalTrustBundle: |
    $(echo "$VCENTER_CA_CERT" | awk '{printf "    %s\n", $0}') # Ensure 4-space indent
pullSecret: |
  $PULL_SECRET
sshKey: |
  $SSH_KEY # SSH key should be on a single line, no extra newlines
controlPlane:
  name: master
  replicas: ${MASTER_REPLICAS} # <--- FIX: Use dynamic MASTER_REPLICAS
compute:
- name: worker
  replicas: ${WORKER_REPLICAS} # <--- FIX: Use dynamic WORKER_REPLICAS
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
  url: http://${IGNITION_SERVER_IP}:${IGNITION_SERVER_PORT}/bootstrap.ign
EOF

# Add a check for file size after creation
GENERATED_FILE_SIZE=$(stat -f %z "$INSTALL_DIR/install-config.yaml" 2>/dev/null || stat -c %s "$INSTALL_DIR/install-config.yaml" 2>/dev/null)
if [[ "$GENERATED_FILE_SIZE" -eq 0 ]]; then
  echo "❌ Error: install-config.yaml was generated as a zero-byte file!"
  echo "   This means content was not written or the 'cat' command failed."
  exit 1
else
  echo "DEBUG: Generated install-config.yaml size: $GENERATED_FILE_SIZE bytes"
fi

echo "✅ Generated install-config.yaml at: $INSTALL_DIR/install-config.yaml"
echo "⚠️  Remember to inject vSphere credentials into manifests later (via generate-vsphere-creds-manifests.sh)."