#!/usr/bin/env bash
set -e

CLUSTER_YAML="$(realpath "$1")"
if [[ -z "$CLUSTER_YAML" ]] || [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
BASE_DIR="$(dirname "$(dirname "$0")")"
INSTALL_DIR="${BASE_DIR}/install-configs/${CLUSTER_NAME}"

echo "🌐 Injecting static IPs directly into ignition files..."

# Network configuration
NETWORK_BASE="192.168.42"
GATEWAY="${NETWORK_BASE}.1"
DNS_SERVER="${NETWORK_BASE}.1"

# Create NetworkManager connection file content
create_nm_config() {
  local ip=$1
  cat <<EOF
[connection]
id=ens192
type=ethernet
interface-name=ens192

[ethernet]

[ipv4]
address1=${ip}/24,${GATEWAY}
dns=${DNS_SERVER};
method=manual

[ipv6]
addr-gen-mode=eui64
method=auto
EOF
}

# Function to inject network config into ignition file
inject_network_config() {
  local ignition_file=$1
  local ip_address=$2
  local role=$3
  
  echo "  Injecting ${ip_address} into ${role} ignition..."
  
  # Create the NetworkManager config
  nm_config=$(create_nm_config "$ip_address")
  nm_config_b64=$(echo "$nm_config" | base64 -w0)
  
  # Create temporary file with updated ignition
  tmp_file=$(mktemp)
  
  # Add the network configuration to the ignition file
  jq --arg content "data:text/plain;charset=utf-8;base64,$nm_config_b64" \
     '.storage.files += [{
       "path": "/etc/NetworkManager/system-connections/ens192.nmconnection",
       "mode": 384,
       "overwrite": true,
       "contents": {
         "source": $content
       }
     }]' "$ignition_file" > "$tmp_file"
  
  # Also add a generic ethernet connection as backup
  generic_nm_config=$(cat <<EOF
[connection]
id=Wired connection 1
type=ethernet

[ethernet]

[ipv4]
address1=${ip_address}/24,${GATEWAY}
dns=${DNS_SERVER};
method=manual

[ipv6]
addr-gen-mode=eui64
method=auto
EOF
)
  generic_nm_config_b64=$(echo "$generic_nm_config" | base64 -w0)
  
  jq --arg content2 "data:text/plain;charset=utf-8;base64,$generic_nm_config_b64" \
     '.storage.files += [{
       "path": "/etc/NetworkManager/system-connections/Wired connection 1.nmconnection",
       "mode": 384,
       "overwrite": true,
       "contents": {
         "source": $content2
       }
     }]' "$tmp_file" > "${tmp_file}.2"
  
  # Replace original file
  mv "${tmp_file}.2" "$ignition_file"
  rm -f "$tmp_file"
}

# Inject static IPs into ignition files
if [[ -f "${INSTALL_DIR}/bootstrap.ign" ]]; then
  inject_network_config "${INSTALL_DIR}/bootstrap.ign" "${NETWORK_BASE}.30" "bootstrap"
fi

if [[ -f "${INSTALL_DIR}/master.ign" ]]; then
  inject_network_config "${INSTALL_DIR}/master.ign" "${NETWORK_BASE}.31" "master"
fi

echo "✅ Static IP configuration injected into ignition files:"
echo "   Bootstrap: ${NETWORK_BASE}.30"
echo "   Masters:   ${NETWORK_BASE}.31"

# Verify injection worked
echo ""
echo "🔍 Verifying bootstrap ignition contains NetworkManager config..."
if cat "${INSTALL_DIR}/bootstrap.ign" | jq '.storage.files[] | select(.path | contains("system-connections"))' | grep -q "path"; then
  echo "✅ Static IP configuration found in bootstrap ignition file"
else
  echo "❌ Static IP configuration NOT found in bootstrap ignition file"
fi
