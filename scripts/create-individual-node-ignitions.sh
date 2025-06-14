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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="${BASE_DIR}/install-configs/${CLUSTER_NAME}"

# Extract network configuration from cluster.yaml
SUBNET_CIDR="$(yq '.network.cidr // .network // .subnet.cidr // .subnet' "$CLUSTER_YAML")"
GATEWAY_FROM_YAML="$(yq '.network.gateway // .gateway' "$CLUSTER_YAML")"

if [[ -z "$SUBNET_CIDR" ]] || [[ "$SUBNET_CIDR" == "null" ]]; then
  echo "❌ No network configuration found in cluster.yaml"
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

echo "🔧 Creating individual master and worker ignition files with static IPs..."

# Check if base ignition files exist
if [[ ! -f "${INSTALL_DIR}/master.ign" ]]; then
  echo "❌ master.ign not found. Run 'openshift-install create ignition-configs' first"
  exit 1
fi

if [[ ! -f "${INSTALL_DIR}/worker.ign" ]]; then
  echo "❌ worker.ign not found. Run 'openshift-install create ignition-configs' first"
  exit 1
fi

# Function to create network config and encode it
create_network_config() {
  local ip="$1"
  local network_config="[connection]
id=ens192
type=ethernet
interface-name=ens192
autoconnect=true
autoconnect-priority=999

[ethernet]

[ipv4]
address1=${ip}/24,${GATEWAY}
dns=${DNS_SERVER};
method=manual

[ipv6]
addr-gen-mode=eui64
method=disabled"
  
  echo "$network_config" | base64 -w0
}

# Function to inject static IP into ignition file
inject_static_ip() {
  local base_ign="$1"
  local target_ign="$2"
  local ip="$3"
  local node_type="$4"
  
  echo "   Creating ${node_type} with IP ${ip}..."
  
  # Create static IP file entry
  STATIC_IP_FILE='{
    "path": "/etc/NetworkManager/system-connections/ens192.nmconnection",
    "mode": 384,
    "overwrite": true,
    "contents": {
      "source": "data:text/plain;charset=utf-8;base64,'$(create_network_config "$ip")'"
    }
  }'
  
  # Merge the static IP configuration into base ignition
  jq --argjson staticFile "$STATIC_IP_FILE" '
    .storage.files += [$staticFile] |
    .systemd.units += [{"name": "NetworkManager.service", "enabled": true}] |
    .systemd.units |= unique_by(.name)
  ' "$base_ign" > "$target_ign"
  
  if ! jq empty "$target_ign" 2>/dev/null; then
    echo "❌ Failed to create valid ignition file for ${node_type}"
    rm -f "$target_ign"
    exit 1
  fi
  
  # Verify the static IP was injected
  if jq '.storage.files[] | select(.path | contains("system-connections"))' "$target_ign" | grep -q "path"; then
    echo "✅ Static IP configuration verified in ${node_type}"
  else
    echo "❌ Static IP configuration NOT found in ${node_type}"
    exit 1
  fi
}

# Create individual master ignition files
echo "📋 Creating master ignition files..."
for i in 0 1 2; do
  IP="${NETWORK_BASE}.$((31 + i))"
  MASTER_FILE="${INSTALL_DIR}/master-${i}.ign"
  inject_static_ip "${INSTALL_DIR}/master.ign" "$MASTER_FILE" "$IP" "master-${i}.ign"
done

# Create individual worker ignition files
echo "📋 Creating worker ignition files..."
for i in 0 1; do
  IP="${NETWORK_BASE}.$((40 + i))"
  WORKER_FILE="${INSTALL_DIR}/worker-${i}.ign"
  inject_static_ip "${INSTALL_DIR}/worker.ign" "$WORKER_FILE" "$IP" "worker-${i}.ign"
done

echo ""
echo "✅ Individual ignition files created:"
echo "   master-0.ign -> ${NETWORK_BASE}.31"
echo "   master-1.ign -> ${NETWORK_BASE}.32"  
echo "   master-2.ign -> ${NETWORK_BASE}.33"
echo "   worker-0.ign -> ${NETWORK_BASE}.40"
echo "   worker-1.ign -> ${NETWORK_BASE}.41"
echo ""
echo "📝 Your deploy-vms.sh script will automatically use these files:"
echo "   - ${CLUSTER_NAME}-master-0 VM: uses master-0.ign"
echo "   - ${CLUSTER_NAME}-master-1 VM: uses master-1.ign"
echo "   - ${CLUSTER_NAME}-master-2 VM: uses master-2.ign"
echo "   - ${CLUSTER_NAME}-worker-0 VM: uses worker-0.ign"
echo "   - ${CLUSTER_NAME}-worker-1 VM: uses worker-1.ign"