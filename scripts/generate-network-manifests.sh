#!/usr/bin/env bash
# macOS Bash 3.2–compatible (no mapfile), cross‑platform base64
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
INTERFACE_NAME=$(yq e '.network.interface // "ens192"' "$CLUSTER_YAML")

# Read DNS servers (0, 1, or 2) without mapfile
DNS_SERVERS_STR=$(yq e '.network.dns_servers[]' "$CLUSTER_YAML" 2>/dev/null || true)
DNS1=""; DNS2=""
if [[ -n "$DNS_SERVERS_STR" ]]; then
  # Split by newlines into array (works on bash 3)
  IFS=$'\n' set -f
  DNS_ARRAY=($DNS_SERVERS_STR)
  set +f
  DNS1="${DNS_ARRAY[0]:-}"
  DNS2="${DNS_ARRAY[1]:-}"
fi
# Fallback to gateway if none provided
if [[ -z "$DNS1" ]]; then DNS1="$GATEWAY"; fi

# Validate node_ips block
if ! yq e '.node_ips' "$CLUSTER_YAML" >/dev/null 2>&1 || [[ "$(yq e '.node_ips' "$CLUSTER_YAML")" == "null" ]]; then
  echo "❌ ERROR: 'node_ips' section not found in cluster YAML"
  exit 1
fi
echo "✅ Found node_ips configuration in cluster YAML"

PREFIX="${NETWORK_CIDR#*/}"

# Cross-platform base64 (GNU/Linux and macOS/BSD)
b64_inline() {
  if base64 --help 2>/dev/null | grep -q -- "-w"; then
    base64 -w0
  else
    base64 | tr -d '\n'
  fi
}

# Systemd unit content captured in a variable, then base64-encoded
REMOVE_OVS_UNIT=$(cat <<'UNIT_EOF'
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
)
REMOVE_OVS_UNIT_B64="$(printf "%s" "$REMOVE_OVS_UNIT" | b64_inline)"

mkdir -p "$INSTALL_DIR/network-configs"

generate_nm_config() {
  local node="$1"
  local node_ip="$2"
  local mac_addr
  mac_addr=$(yq ".node_macs.\"${node}\" // \"\"" "$CLUSTER_YAML")

  # Build the NetworkManager keyfile text
  local nm_cfg="[connection]
id=${INTERFACE_NAME}
type=ethernet
interface-name=${INTERFACE_NAME}
autoconnect-priority=100

[ethernet]"
  if [[ -n "$mac_addr" && "$mac_addr" != "null" ]]; then
    nm_cfg=$nm_cfg$'\n'"mac-address=${mac_addr}"
  fi
  nm_cfg=$nm_cfg$'\n\n'"[ipv4]
method=manual
addresses=${node_ip}/${PREFIX}
gateway=${GATEWAY}
dns=${DNS1}"
  if [[ -n "$DNS2" ]]; then
    nm_cfg="${nm_cfg};${DNS2}"
  fi
  nm_cfg=$nm_cfg$'\n\n'"[ipv6]
method=disabled
"

  printf "%s" "$nm_cfg"
}

write_network_ign() {
  local node="$1"
  local node_ip="$2"

  local nm_cfg
  nm_cfg="$(generate_nm_config "$node" "$node_ip")"
  local nm_b64
  nm_b64="$(printf "%s" "$nm_cfg" | b64_inline)"

  cat > "$INSTALL_DIR/network-configs/${node}-network.json" <<EOF
{
  "files": [
    {
      "path": "/etc/NetworkManager/system-connections/${INTERFACE_NAME}.nmconnection",
      "mode": 384,
      "contents": {
        "source": "data:text/plain;base64,${nm_b64}"
      }
    },
    {
      "path": "/etc/systemd/system/remove-ovs-bridges.service",
      "mode": 384,
      "contents": {
        "source": "data:text/plain;base64,${REMOVE_OVS_UNIT_B64}"
      }
    }
  ],
  "systemd": {
    "units": [
      { "name": "remove-ovs-bridges.service", "enabled": true }
    ]
  }
}
EOF
}

get_node_ip() {
  local node="$1"
  local ip
  ip=$(yq ".node_ips.\"${node}\" // \"\"" "$CLUSTER_YAML" 2>/dev/null)
  if [[ -z "$ip" ]]; then
    echo "❌ ERROR: IP not found for node '${node}' in cluster YAML" >&2
    exit 1
  fi
  printf "%s" "$ip"
}

MASTER_REPLICAS=$(yq '.node_counts.master // 0' "$CLUSTER_YAML")
WORKER_REPLICAS=$(yq '.node_counts.worker // 0' "$CLUSTER_YAML")

# Bootstrap
node="bootstrap"
ip="$(get_node_ip "$node")"
echo "📝 Generating network config for $node (IP: $ip)"
write_network_ign "$node" "$ip"

# Masters
if (( MASTER_REPLICAS > 0 )); then
  i=0
  while (( i < MASTER_REPLICAS )); do
    node="master-${i}"
    ip="$(get_node_ip "$node")"
    echo "📝 Generating network config for $node (IP: $ip)"
    write_network_ign "$node" "$ip"
    i=$((i+1))
  done
fi

# Workers
if (( WORKER_REPLICAS > 0 )); then
  i=0
  while (( i < WORKER_REPLICAS )); do
    node="worker-${i}"
    ip="$(get_node_ip "$node")"
    echo "📝 Generating network config for $node (IP: $ip)"
    write_network_ign "$node" "$ip"
    i=$((i+1))
  done
fi

echo "✅ Network configurations generated in: $INSTALL_DIR/network-configs/"
echo "💡 Next: merge them into your ignition files."
