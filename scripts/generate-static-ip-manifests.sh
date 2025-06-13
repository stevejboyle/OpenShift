#!/usr/bin/env bash
set -e

CLUSTER_YAML="$(realpath "$1")"
if [[ -z "$CLUSTER_YAML" ]] || [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  echo "❌ Cluster file not found: $1"
  exit 1
fi

# Get cluster name and network configuration from cluster.yaml
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
BASE_DIR="$(dirname "$(dirname "$0")")"
MANIFESTS_DIR="${BASE_DIR}/install-configs/${CLUSTER_NAME}/manifests"

# Extract network configuration from cluster.yaml
# Supports both 'network' and 'subnet' fields
SUBNET_CIDR="$(yq '.network // .subnet' "$CLUSTER_YAML")"
if [[ -z "$SUBNET_CIDR" ]] || [[ "$SUBNET_CIDR" == "null" ]]; then
  echo "❌ No network/subnet found in cluster.yaml"
  echo "   Expected 'network: 192.168.42.0/24' or 'subnet: 192.168.42.0/24'"
  exit 1
fi

# Parse network base and calculate gateway
NETWORK_BASE="$(echo "$SUBNET_CIDR" | cut -d'/' -f1 | sed 's/\.[0-9]*$//')"
GATEWAY="${NETWORK_BASE}.1"
DNS_SERVER="${NETWORK_BASE}.1"

echo "📡 Using network: $SUBNET_CIDR"
echo "🏠 Network base: $NETWORK_BASE"
echo "🚪 Gateway: $GATEWAY"

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

# Worker-0 machine manifest
cat > "${MANIFESTS_DIR}/99-worker-0-static-ip.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-0-static-ip
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
address1='${NETWORK_BASE}'.40/24,'${GATEWAY}'
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

# Worker-1 machine manifest
cat > "${MANIFESTS_DIR}/99-worker-1-static-ip.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-1-static-ip
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
address1='${NETWORK_BASE}'.41/24,'${GATEWAY}'
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

echo "✅ Static IP manifests generated for subnet $SUBNET_CIDR:"
echo "   Bootstrap: ${NETWORK_BASE}.30"
echo "   Master-0:  ${NETWORK_BASE}.31"
echo "   Master-1:  ${NETWORK_BASE}.32"
echo "   Master-2:  ${NETWORK_BASE}.33"
echo "   Worker-0:  ${NETWORK_BASE}.40"
echo "   Worker-1:  ${NETWORK_BASE}.41"
echo ""
echo "📝 Next steps:"
echo "   1. Apply worker MachineConfigs to existing cluster:"
echo "      oc apply -f ${MANIFESTS_DIR}/99-worker-0-static-ip.yaml"
echo "      oc apply -f ${MANIFESTS_DIR}/99-worker-1-static-ip.yaml"
echo "   2. Update your load balancer backend pool:"
echo "      - Worker-0: ${NETWORK_BASE}.40:80,443"
echo "      - Worker-1: ${NETWORK_BASE}.41:80,443"
echo "   3. Watch workers restart and get new IPs:"
echo "      oc get nodes -w"