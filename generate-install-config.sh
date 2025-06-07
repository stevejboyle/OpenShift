#!/bin/bash

set -e

CLUSTER_NAME="ocp416"
BASE_DOMAIN="openshift.sboyle.internal"

PULL_SECRET_FILE="./pull-secret.json"
SSH_KEY_FILE="./ssh-key.pub"

PULL_SECRET=$(cat $PULL_SECRET_FILE)
SSH_KEY=$(cat $SSH_KEY_FILE)

mkdir -p build-config

cat > build-config/install-config.yaml <<EOL
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
compute:
- name: worker
  replicas: 1
  platform:
    vsphere:
      cpus: 4
      memoryMB: 16384
      osDisk:
        diskSizeGB: 120
controlPlane:
  name: master
  replicas: 3
  platform:
    vsphere:
      cpus: 4
      memoryMB: 16384
      osDisk:
        diskSizeGB: 120
platform:
  vsphere:
    vcenters:
    - server: vcenter1.sboyle.internal
      user: administrator@vsphere.sboyle.internal
      password: "<YOUR_VSPHERE_PASSWORD_HERE>"
      datacenters:
      - Lab
    failureDomains:
    - name: Lab-FD
      server: vcenter1.sboyle.internal
      region: us-east
      zone: zone-a
      topology:
        datacenter: Lab
        computeCluster: /Lab/host/Lab Cluster
        datastore: /Lab/datastore/datastore-san1
        networks:
        - OpenShift_192.168.42.0
pullSecret: |
$(echo "$PULL_SECRET" | sed 's/^/  /')
sshKey: |
  ${SSH_KEY}
EOL

cp build-config/install-config.yaml .

echo "✅ install-config.yaml generated (backup in build-config/)"
