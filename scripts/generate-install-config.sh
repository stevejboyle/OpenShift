#!/usr/bin/env zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

CLUSTER_YAML=$1
if [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster file not found: $CLUSTER_YAML"
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/load-vcenter-env.sh"
BASE_DIR=$(dirname "$SCRIPT_DIR")
mkdir -p "${BASE_DIR}/install-configs"

# Parse values
CLUSTER_NAME=$(yq -r '.clusterName' "$CLUSTER_YAML")
BASE_DOMAIN=$(yq -r '.baseDomain'  "$CLUSTER_YAML")
VCENTER_SERVER=$(yq -r '.vcenter_server'   "$CLUSTER_YAML")
VCENTER_USERNAME=$(yq -r '.vcenter_username' "$CLUSTER_YAML")
VCENTER_PASSWORD=$(yq -r '.vcenter_password' "$CLUSTER_YAML")
VCENTER_DATACENTER=$(yq -r '.vcenter_datacenter' "$CLUSTER_YAML")
VCENTER_CLUSTER=$(yq -r '.vcenter_cluster'   "$CLUSTER_YAML")
VCENTER_DATASTORE=$(yq -r '.vcenter_datastore' "$CLUSTER_YAML")
VCENTER_NETWORK=$(yq -r '.vcenter_network'   "$CLUSTER_YAML")
SSH_KEY_FILE=$(yq -r '.sshKeyFile' "$CLUSTER_YAML")
PULL_SECRET_FILE=$(yq -r '.pullSecretFile' "$CLUSTER_YAML")

# Validate pull-secret and SSH key
if [[ ! -f "$SSH_KEY_FILE" || ! -f "$PULL_SECRET_FILE" ]]; then
  echo "❌ Missing SSH key or Pull Secret file"
  exit 1
fi

SSH_KEY=$(<"$SSH_KEY_FILE")
PULL_SECRET=$(<"$PULL_SECRET_FILE")

# Build vSphere paths
CLUSTER_PATH="/${VCENTER_DATACENTER}/host/${VCENTER_CLUSTER}"
DATASTORE_PATH="/${VCENTER_DATACENTER}/datastore/${VCENTER_DATASTORE}"

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
    vcenters:
    - server: ${VCENTER_SERVER}
      username: ${VCENTER_USERNAME}
      password: ${VCENTER_PASSWORD}
      datacenters:
      - ${VCENTER_DATACENTER}
    failureDomains:
    - name: primary
      region: region-a
      zone: zone-a
      server: ${VCENTER_SERVER}
      topology:
        datacenter: ${VCENTER_DATACENTER}
        computeCluster: ${CLUSTER_PATH}
        datastore: ${DATASTORE_PATH}
        networks:
        - ${VCENTER_NETWORK}
networking:
  machineNetwork:
  - cidr: $(yq -r '.network.cidr' "$CLUSTER_YAML")
  networkType: OVNKubernetes
pullSecret: |
$(printf '  %s\n' "${PULL_SECRET}")
sshKey: |
  ${SSH_KEY}
EOF

echo "✅ install-config.yaml generated at ${BASE_DIR}/install-configs/install-config.yaml"
