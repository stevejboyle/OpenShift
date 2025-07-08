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

# Validate that node_ips section exists
echo "🔍 Checking for node_ips configuration in cluster YAML..."
if ! yq e '.node_ips' "$CLUSTER_YAML" >/dev/null 2>&1 || [[ "$(yq e '.node_ips' "$CLUSTER_YAML")" == "null" ]]; then
  echo "❌ ERROR: 'node_ips' section not found in cluster YAML"
  echo ""
  echo "💡 Please add the following section to your $CLUSTER_YAML file:"
  echo ""
  echo "# Static IP addresses for each node"
  echo "node_ips:"
  echo "  bootstrap: \"192.168.42.30\""
  echo "  master-0: \"192.168.42.31\""
  echo "  master-1: \"192.168.42.32\""
  echo "  master-2: \"192.168.42.33\""
  echo "  worker-0: \"192.168.42.40\""
  echo "  worker-1: \"192.168.42.41\""
  echo ""
  echo "📝 Adjust the IP addresses to match your desired network plan."
  echo "   The IPs should be within your network CIDR: $NETWORK_CIDR"
  exit 1
fi

echo "✅ Found node_ips configuration in cluster YAML"

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

# Function to get IP for a node from YAML (compatible with older bash)
get_node_ip() {
  local node="$1"
  
  # Try to read IP from cluster YAML
  local node_ip=$(yq ".node_ips.\"${node}\"" "$CLUSTER_YAML" 2>/dev/null)
  
  # Check if we got a valid IP (not null and not empty)
  if [[ "$node_ip" != "null" && -n "$node_ip" && "$node_ip" != "" ]]; then
    echo "$node_ip"
    return 0
  fi
  
  # If no IP found in YAML, show error and exit
  echo "❌ ERROR: IP address not found for node '$node' in cluster YAML"
  echo "💡 Please add a 'node_ips' section to your cluster YAML file:"
  echo ""
  echo "node_ips:"
  echo "  bootstrap: \"192.168.42.30\""
  echo "  master-0: \"192.168.42.31\""
  echo "  master-1: \"192.168.42.32\""
  echo "  master-2: \"192.168.42.33\""
  echo "  worker-0: \"192.168.42.40\""
  echo "  worker-1: \"192.168.42.41\""
  echo ""
  echo "Adjust the IP addresses to match your network plan."
  exit 1
}

# Get node counts from cluster YAML
MASTER_REPLICAS=$(yq '.node_counts.master' "$CLUSTER_YAML")
WORKER_REPLICAS=$(yq '.node_counts.worker' "$CLUSTER_YAML")

# Generate network configs for bootstrap
node="bootstrap"
node_ip=$(get_node_ip "$node")
echo "📝 Generating network config for $node (IP: $node_ip)"
create_ignition_network_config "$node_ip" "primary-nic" > "$INSTALL_DIR/network-configs/${node}-network.json"

# Generate network configs for masters
for i in $(seq 0 $((MASTER_REPLICAS - 1))); do
  node="master-${i}"
  node_ip=$(get_node_ip "$node")
  echo "📝 Generating network config for $node (IP: $node_ip)"
  create_ignition_network_config "$node_ip" "primary-nic" > "$INSTALL_DIR/network-configs/${node}-network.json"
done

# Generate network configs for workers
for i in $(seq 0 $((WORKER_REPLICAS - 1))); do
  node="worker-${i}"
  node_ip=$(get_node_ip "$node")
  echo "📝 Generating network config for $node (IP: $node_ip)"
  create_ignition_network_config "$node_ip" "primary-nic" > "$INSTALL_DIR/network-configs/${node}-network.json"
done

echo "✅ Network configurations generated in: $INSTALL_DIR/network-configs/"
echo "💡 Next: Update your ignition files to include these network configurations"
