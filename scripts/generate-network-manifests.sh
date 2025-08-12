#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
INSTALL_DIR="${2:-install-configs/$(basename "$CLUSTER_YAML" .yaml)}"

if [[ -z "${CLUSTER_YAML:-}" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

echo "🔧 Generating network configuration to fix OVS conflicts..."

NETWORK_CIDR=$(yq e '.network.cidr' "$CLUSTER_YAML")
GATEWAY=$(yq e '.network.gateway' "$CLUSTER_YAML")
DNS_SERVERS=($(yq e '.network.dns_servers[]' "$CLUSTER_YAML"))
INTERFACE_NAME=$(yq e '.network.interface // "ens192"' "$CLUSTER_YAML")

if ! yq e '.node_ips' "$CLUSTER_YAML" >/dev/null 2>&1 || [[ "$(yq e '.node_ips' "$CLUSTER_YAML")" == "null" ]]; then
  echo "❌ ERROR: 'node_ips' section not found in cluster YAML"
  exit 1
fi
echo "✅ Found node_ips configuration in cluster YAML"

SUBNET=$(echo "$NETWORK_CIDR" | cut -d'/' -f1)
PREFIX=$(echo "$NETWORK_CIDR" | cut -d'/' -f2)

generate_nm_config() {
  local node_ip="$1"
  local mac_addr="$2"

  cat << EOF
[connection]
id=$INTERFACE_NAME
type=ethernet
interface-name=$INTERFACE_NAME
autoconnect-priority=100

[ethernet]
$( [[ -n "$mac_addr" ]] && echo "mac-address=$mac_addr" )

[ipv4]
method=manual
addresses=$node_ip/$PREFIX
gateway=$GATEWAY
dns=${DNS_SERVERS[0]};${DNS_SERVERS[1]:-$GATEWAY}

[ipv6]
method=disabled
EOF
}

create_ignition_network_config() {
  local node="$1"
  local node_ip="$2"

  local mac_addr
  mac_addr=$(yq ".node_macs.\"${node}\" // \""" "$CLUSTER_YAML")

  nm_config=$(generate_nm_config "$node_ip" "$mac_addr")

  cat << EOF
{
  "files": [
    {
      "path": "/etc/NetworkManager/system-connections/${INTERFACE_NAME}.nmconnection",
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

mkdir -p "$INSTALL_DIR/network-configs"

get_node_ip() {
  local node="$1"
  local node_ip
  node_ip=$(yq ".node_ips.\"${node}\" // \""" "$CLUSTER_YAML" 2>/dev/null)
  if [[ -z "$node_ip" ]]; then
    echo "❌ ERROR: IP address not found for node '$node' in cluster YAML"
    exit 1
  fi
  echo "$node_ip"
}

MASTER_REPLICAS=$(yq '.node_counts.master // 0' "$CLUSTER_YAML")
WORKER_REPLICAS=$(yq '.node_counts.worker // 0' "$CLUSTER_YAML")

node="bootstrap"
node_ip=$(get_node_ip "$node")
echo "📝 Generating network config for $node (IP: $node_ip)"
create_ignition_network_config "$node" "$node_ip" > "$INSTALL_DIR/network-configs/${node}-network.json"

if (( MASTER_REPLICAS > 0 )); then
  for i in $(seq 0 $((MASTER_REPLICAS - 1))); do
    node="master-${i}"
    node_ip=$(get_node_ip "$node")
    echo "📝 Generating network config for $node (IP: $node_ip)"
    create_ignition_network_config "$node" "$node_ip" > "$INSTALL_DIR/network-configs/${node}-network.json"
  done
fi

if (( WORKER_REPLICAS > 0 )); then
  for i in $(seq 0 $((WORKER_REPLICAS - 1))); do
    node="worker-${i}"
    node_ip=$(get_node_ip "$node")
    echo "📝 Generating network config for $node (IP: $node_ip)"
    create_ignition_network_config "$node" "$node_ip" > "$INSTALL_DIR/network-configs/${node}-network.json"
  done
fi

echo "✅ Network configurations generated in: $INSTALL_DIR/network-configs/"
echo "💡 Next: merge them into your ignition files."
