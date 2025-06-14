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

# Extract network configuration from cluster.yaml
# Try different possible YAML structures
SUBNET_CIDR="$(yq '.network.cidr // .network // .subnet.cidr // .subnet' "$CLUSTER_YAML")"
GATEWAY_FROM_YAML="$(yq '.network.gateway // .gateway' "$CLUSTER_YAML")"

if [[ -z "$SUBNET_CIDR" ]] || [[ "$SUBNET_CIDR" == "null" ]]; then
  echo "❌ No network configuration found in cluster.yaml"
  echo "   Expected one of:"
  echo "     network:"
  echo "       cidr: 192.168.42.0/24"
  echo "       gateway: 192.168.42.1"
  echo "     OR"
  echo "     network: 192.168.42.0/24"
  exit 1
fi

# Parse network base from CIDR
NETWORK_BASE="$(echo "$SUBNET_CIDR" | cut -d'/' -f1 | sed 's/\.[0-9]*$//')"

# Use provided gateway or default to .1
if [[ -z "$GATEWAY_FROM_YAML" ]] || [[ "$GATEWAY_FROM_YAML" == "null" ]]; then
  GATEWAY="${NETWORK_BASE}.1"
else
  GATEWAY="$GATEWAY_FROM_YAML"
fi

# Use provided DNS servers or default to gateway
DNS_SERVER="$(yq '.network.dns_servers[0] // .dns_servers[0] // .network.dns[0] // .dns[0]' "$CLUSTER_YAML")"
if [[ -z "$DNS_SERVER" ]] || [[ "$DNS_SERVER" == "null" ]]; then
  DNS_SERVER="$GATEWAY"
fi

echo "📡 Using network: $SUBNET_CIDR"
echo "🏠 Network base: $NETWORK_BASE" 
echo "🚪 Gateway: $GATEWAY"
echo "🌐 DNS: $DNS_SERVER"
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
autoconnect=true
autoconnect-priority=999

[ethernet]

[ipv4]
address1=${NETWORK_BASE}.30/24,${GATEWAY}
dns=${DNS_SERVER};
method=manual

[ipv6]
addr-gen-mode=eui64
method=disabled' | base64 -w0)
        mode: 0600
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
  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: master-0
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
autoconnect=true
autoconnect-priority=999

[ethernet]

[ipv4]
address1=${NETWORK_BASE}.31/24,${GATEWAY}
dns=${DNS_SERVER};
method=manual

[ipv6]
addr-gen-mode=eui64
method=disabled' | base64 -w0)
        mode: 0600
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
  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: master-1
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
autoconnect=true
autoconnect-priority=999

[ethernet]

[ipv4]
address1=${NETWORK_BASE}.32/24,${GATEWAY}
dns=${DNS_SERVER};
method=manual

[ipv6]
addr-gen-mode=eui64
method=disabled' | base64 -w0)
        mode: 0600
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
  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: master-2
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
autoconnect=true
autoconnect-priority=999

[ethernet]

[ipv4]
address1=${NETWORK_BASE}.33/24,${GATEWAY}
dns=${DNS_SERVER};
method=manual

[ipv6]
addr-gen-mode=eui64
method=disabled' | base64 -w0)
        mode: 0600
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
  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: worker-0
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
autoconnect=true
autoconnect-priority=999

[ethernet]

[ipv4]
address1=${NETWORK_BASE}.40/24,${GATEWAY}
dns=${DNS_SERVER};
method=manual

[ipv6]
addr-gen-mode=eui64
method=disabled' | base64 -w0)
        mode: 0600
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
  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: worker-1
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
autoconnect=true
autoconnect-priority=999

[ethernet]

[ipv4]
address1=${NETWORK_BASE}.41/24,${GATEWAY}
dns=${DNS_SERVER};
method=manual

[ipv6]
addr-gen-mode=eui64
method=disabled' | base64 -w0)
        mode: 0600
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
echo "   Worker-0:  ${NETWORK_BASE}.40"
echo "   Worker-1:  ${NETWORK_BASE}.41"
echo ""
echo "📝 Next steps:"
echo "   1. Manifests are already in the correct location"
echo "   2. Run: openshift-install create ignition-configs"
echo "   3. Deploy VMs using the generated ignition files"
echo "   4. Update load balancer with these IPs"
echo ""
echo "🔧 Load balancer configuration needed:"
echo "   API Backend (port 6443): ${NETWORK_BASE}.30, ${NETWORK_BASE}.31, ${NETWORK_BASE}.32, ${NETWORK_BASE}.33"
echo "   Apps Backend (ports 80/443): ${NETWORK_BASE}.40, ${NETWORK_BASE}.41"