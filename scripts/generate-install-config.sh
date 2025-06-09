#!/bin/bash
set -e

CLUSTER_FILE=$1
if [ -z "$CLUSTER_FILE" ]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/load-vcenter-env.sh"

BASE_DIR="$(dirname "$SCRIPT_DIR")"
mkdir -p "${BASE_DIR}/install-configs"

CLUSTER_NAME=$(yq '.clusterName' "$CLUSTER_FILE")
BASE_DOMAIN=$(yq '.baseDomain' "$CLUSTER_FILE")
PULL_SECRET=$(cat "$(yq '.pullSecretFile' "$CLUSTER_FILE")")
SSH_KEY=$(cat "$(yq '.sshKeyFile' "$CLUSTER_FILE")")

cat > "${BASE_DIR}/install-configs/install-config.yaml" <<EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: 3
platform:
  vsphere:
    vcenter: $(yq '.vsphere.hostname' "$CLUSTER_FILE")
    username: ${GOVC_USERNAME}
    password: ${GOVC_PASSWORD}
    datacenter: $(yq '.vsphere.datacenter' "$CLUSTER_FILE")
    defaultDatastore: $(yq '.vsphere.datastore' "$CLUSTER_FILE")
networking:
  machineNetwork:
  - cidr: $(yq '.network.cidr' "$CLUSTER_FILE")
  networkType: OVNKubernetes
pullSecret: '${PULL_SECRET}'
sshKey: |
  ${SSH_KEY}
EOF

if [ -f "$(yq '.consolePasswordFile' "$CLUSTER_FILE")" ]; then
  PASSWORD_HASH=$(cat "$(yq '.consolePasswordFile' "$CLUSTER_FILE")")
  cat >> "${BASE_DIR}/install-configs/install-config.yaml" <<EOF2
passwd:
  users:
    - name: core
      passwordHash: "${PASSWORD_HASH}"
EOF2
fi

echo "✅ install-config.yaml generated successfully."
