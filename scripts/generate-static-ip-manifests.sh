#!/usr/bin/env bash
set -e

CLUSTER_YAML="$(realpath "$1")"
if [[ -z "$CLUSTER_YAML" ]] || [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  echo "❌ Cluster file not found: $1"
  exit 1
fi

# Get cluster name
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
BASE_DIR="$(dirname "$(dirname "$0")")"
MANIFESTS_DIR="${BASE_DIR}/install-configs/${CLUSTER_NAME}/manifests"

# Network configuration
NETWORK_BASE="192.168.42"
GATEWAY="${NETWORK_BASE}.1"
DNS_SERVER="${NETWORK_BASE}.1"

echo "🌐 Generating static IP manifests for cluster ${CLUSTER_NAME}..."

# Create machine manifests with static IPs
mkdir -p "${MANIFESTS_DIR}"

# Bootstrap machine manifest
cat > "${MANIFESTS_DIR}/99-bootstrap-static-ip.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: bootstrap
  name: 99-bootstrap-static-ip
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(echo '[connection]
id=ens192
type=ethernet
interface-name=ens192

[ethernet]

[ipv4]
address1='${NETWORK_BASE}'.30/24,'${GATEWAY}'
dns='${DNS_SERVER}';
method=manual

[ipv6]
addr-gen-mode=eui64
method=auto' | base64 -w0)
        mode: 0644
        path: /etc/NetworkManager/system-connections/ens192.nmconnection
        overwrite: true
    systemd:
      units:
      - name: NetworkManager.service
        enabled: true
EOF

# Master-0 machine manifest
cat > "${MANIFESTS_DIR}/99-master-0-static-ip.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-0-static-ip
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(echo '[connection]
id=ens192
type=ethernet
interface-name=ens192

[ethernet]

[ipv4]
address1='${NETWORK_BASE}'.31/24,'${GATEWAY}'
dns='${DNS_SERVER}';
method=manual

[ipv6]
addr-gen-mode=eui64
method=auto' | base64 -w0)
        mode: 0644
        path: /etc/NetworkManager/system-connections/ens192.nmconnection
        overwrite: true
    systemd:
      units:
      - name: NetworkManager.service
        enabled: true
EOF

# Master-1 machine manifest
cat > "${MANIFESTS_DIR}/99-master-1-static-ip.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-1-static-ip
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(echo '[connection]
id=ens192
type=ethernet
interface-name=ens192

[ethernet]

[ipv4]
address1='${NETWORK_BASE}'.32/24,'${GATEWAY}'
dns='${DNS_SERVER}';
method=manual

[ipv6]
addr-gen-mode=eui64
method=auto' | base64 -w0)
        mode: 0644
        path: /etc/NetworkManager/system-connections/ens192.nmconnection
        overwrite: true
    systemd:
      units:
      - name: NetworkManager.service
        enabled: true
EOF

# Master-2 machine manifest
cat > "${MANIFESTS_DIR}/99-master-2-static-ip.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-2-static-ip
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,$(echo '[connection]
id=ens192
type=ethernet
interface-name=ens192

[ethernet]

[ipv4]
address1='${NETWORK_BASE}'.33/24,'${GATEWAY}'
dns='${DNS_SERVER}';
method=manual

[ipv6]
addr-gen-mode=eui64
method=auto' | base64 -w0)
        mode: 0644
        path: /etc/NetworkManager/system-connections/ens192.nmconnection
        overwrite: true
    systemd:
      units:
      - name: NetworkManager.service
        enabled: true
EOF

echo "✅ Static IP manifests generated:"
echo "   Bootstrap: ${NETWORK_BASE}.30"
echo "   Master-0:  ${NETWORK_BASE}.31"
echo "   Master-1:  ${NETWORK_BASE}.32"
echo "   Master-2:  ${NETWORK_BASE}.33"
