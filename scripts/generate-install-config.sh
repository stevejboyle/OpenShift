#!/bin/zsh

set -e

CLUSTER_YAML="$1"

if [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster config file not found: $CLUSTER_YAML"
  exit 1
fi

CLUSTER_NAME=$(yq '.clusterName' "$CLUSTER_YAML")
BASE_DOMAIN=$(yq '.baseDomain' "$CLUSTER_YAML")
VCENTER_SERVER=$(yq '.vcenter_server' "$CLUSTER_YAML")
VCENTER_USERNAME=$(yq '.vcenter_username' "$CLUSTER_YAML")
VCENTER_PASSWORD=$(yq '.vcenter_password' "$CLUSTER_YAML")
VCENTER_DATACENTER=$(yq '.vcenter_datacenter' "$CLUSTER_YAML")
VCENTER_CLUSTER=$(yq '.vcenter_cluster' "$CLUSTER_YAML")
VCENTER_DATASTORE=$(yq '.vcenter_datastore' "$CLUSTER_YAML")
VCENTER_NETWORK=$(yq '.vcenter_network' "$CLUSTER_YAML")
SSH_KEY_FILE=$(yq '.sshKeyFile' "$CLUSTER_YAML")
PULL_SECRET_FILE=$(yq '.pullSecretFile' "$CLUSTER_YAML")

if [[ ! -f "$SSH_KEY_FILE" || ! -f "$PULL_SECRET_FILE" ]]; then
  echo "❌ SSH key or pull secret file not found."
  exit 1
fi

SSH_KEY=$(<"$SSH_KEY_FILE")
PULL_SECRET=$(<"$PULL_SECRET_FILE")

cat > install-configs/install-config.yaml <<EOF
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
    - name: primary-vcenter
      server: ${VCENTER_SERVER}
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
        computeCluster: /${VCENTER_DATACENTER}/host/${VCENTER_CLUSTER}
        datastore: /${VCENTER_DATACENTER}/datastore/${VCENTER_DATASTORE}
        networks:
        - ${VCENTER_NETWORK}
networking:
  machineNetwork:
  - cidr: 192.168.42.0/24
  networkType: OVNKubernetes
pullSecret: '${PULL_SECRET}'
sshKey: |
  ${SSH_KEY}
EOF

echo "✅ install-config.yaml generated successfully."
