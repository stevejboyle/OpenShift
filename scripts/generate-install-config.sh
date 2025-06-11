#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

CLUSTER_YAML="$(realpath "$1")"
if [ ! -f "$CLUSTER_YAML" ]; then
  echo "❌ Cluster file not found: $CLUSTER_YAML"
  exit 1
fi

# Load govc credentials
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/load-vcenter-env.sh"

BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Read cluster settings
CN=$(yq -r '.clusterName'       "$CLUSTER_YAML")
BD=$(yq -r '.baseDomain'        "$CLUSTER_YAML")
PS=$(<"$(yq -r '.pullSecretFile' "$CLUSTER_YAML")")
SK=$(<"$(yq -r '.sshKeyFile'     "$CLUSTER_YAML")")

VC_SERVER=$(yq -r '.vcenter_server'   "$CLUSTER_YAML")
VC_DC=$(yq -r '.vcenter_datacenter'   "$CLUSTER_YAML")
VC_CLUSTER=$(yq -r '.vcenter_cluster' "$CLUSTER_YAML")
VC_DS=$(yq -r '.vcenter_datastore'    "$CLUSTER_YAML")
VC_NET=$(yq -r '.vcenter_network'     "$CLUSTER_YAML")
NETWORK_CIDR=$(yq -r '.network.cidr'  "$CLUSTER_YAML")

# Create cluster-specific directory
INSTALL_DIR="${BASE_DIR}/install-configs/${CN}"
mkdir -p "$INSTALL_DIR"

# Use placeholder for password - it will be replaced by environment variables during openshift-install
PLACEHOLDER_PASSWORD="WILL_BE_SET_BY_ENVIRONMENT"

# Emit clean install-config.yaml
cat > "${INSTALL_DIR}/install-config.yaml" <<EOF
apiVersion: v1
baseDomain: ${BD}
metadata:
  name: ${CN}
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: 3
platform:
  vsphere:
    vcenters:
    - server: ${VC_SERVER}
      user: ${GOVC_USERNAME}
      password: ${PLACEHOLDER_PASSWORD}
      datacenters:
      - ${VC_DC}
    failureDomains:
    - name: primary
      region: region-a
      zone: zone-a
      server: ${VC_SERVER}
      topology:
        datacenter: ${VC_DC}
        computeCluster: "/${VC_DC}/host/${VC_CLUSTER}"
        datastore: "/${VC_DC}/datastore/${VC_DS}"
        networks:
        - ${VC_NET}
networking:
  machineNetwork:
  - cidr: ${NETWORK_CIDR}
  networkType: OVNKubernetes
pullSecret: '${PS}'
sshKey: |
  ${SK}
EOF

echo "✅ install-config.yaml generated at: ${INSTALL_DIR}/install-config.yaml"
echo "⚠️  Password placeholder will be replaced by VSPHERE_PASSWORD environment variable"
