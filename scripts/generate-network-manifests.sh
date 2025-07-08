#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
INSTALL_DIR="${2:-install-configs/$(basename "$CLUSTER_YAML" .yaml)}"

if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

echo "🔧 Generating network configuration to fix OVS conflicts..."

# Read network configuration from cluster YAML
NETWORK_CIDR=$(yq e '.network.cidr' "$CLUSTER_YAML")
GATEWAY=$(yq e '.network.gateway' "$CLUSTER_YAML")
DNS_SERVERS=($(yq e '.network.dns_servers[]' "$CLUSTER_YAML"))

# Extract network details
SUBNET=$(echo "$NETWORK_CIDR" | cut -d'/' -f1)
PREFIX=$(echo "$NETWORK_CIDR" | cut -d'/' -f2)

# Function to generate NetworkManager configuration for a specific IP
generate_nm_config() {
  local node_ip="$1"
  local interface_name="ens192"  # Adjust if your interface name is different
  
  cat << EOF
[connection]
id=$interface_name
type=ethernet
interface-name=$interface_name

[ipv4]
method=manual
addresses=$node_ip/$PREFIX
gateway=$GATEWAY
dns=${DNS_SERVERS[0]};${DNS_SERVERS[1]:-$GATEWAY}

[ipv6]
method=disabled
EOF
}

# Function to create ignition network configuration
create_ignition_network_config() {
  local node_ip="$1"
  local config_name="$2"
  
  # Generate the NetworkManager config
  nm_config=$(generate_nm_config "$node_ip")
  
  # Create ignition storage configuration
  cat << EOF
{
  "files": [
    {
      "path": "/etc/NetworkManager/system-connections/$config_name.nmconnection",
      "mode": 384,
      "contents": {
        "source": "data:text/plain;base64,$(echo "$nm_config" | base64 -w0)"
      }
    },
    {
      "path": "/etc/systemd/system/remove-ovs-bridges.service",
      "mode": 384,
      "contents": {
        "source": "data:text/plain;base64,$(cat << 'UNIT_EOF' | base64 -w0
[Unit]
Description=Remove OVS Bridges for OVN-Kubernetes
Before=kubelet.service
After=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'nmcli con delete br-ex || true; nmcli con delete ovs-if-br-ex || true; nmcli con delete ovs-port-br-ex || true; nmcli con delete ovs-port-phys0 || true; nmcli con delete ovs-if-phys0 || true; ovs-vsctl del-br br-ex || true; systemctl restart NetworkManager'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT_EOF
)"
      }
    }
  ],
  "systemd": {
    "units": [
      {
        "name": "remove-ovs-bridges.service",
        "enabled": true
      }
    ]
  }
}
EOF
}

# Generate network configs for each node type
mkdir -p "$INSTALL_DIR/network-configs"

# Calculate IP addresses based on MAC addresses from cluster YAML
declare -A NODE_IPS
NODE_IPS["bootstrap"]="192.168.42.50"
NODE_IPS["master-0"]="192.168.42.51"
NODE_IPS["master-1"]="192.168.42.52"
NODE_IPS["master-2"]="192.168.42.53"
NODE_IPS["worker-0"]="192.168.42.61"
NODE_IPS["worker-1"]="192.168.42.62"

# Generate individual network configs
for node in "${!NODE_IPS[@]}"; do
  echo "📝 Generating network config for $node (IP: ${NODE_IPS[$node]})"
  create_ignition_network_config "${NODE_IPS[$node]}" "primary-nic" > "$INSTALL_DIR/network-configs/${node}-network.json"
done

echo "✅ Network configurations generated in: $INSTALL_DIR/network-configs/"
echo "💡 Next: Update your ignition files to include these network configurations"
