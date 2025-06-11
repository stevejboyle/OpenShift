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

# Read additional config from cluster YAML
CLUSTER_NAME=$(yq -r '.clusterName' "$CLUSTER_YAML")
BASE_DOMAIN=$(yq -r '.baseDomain' "$CLUSTER_YAML")

echo "🌐 Injecting static IPs directly into ignition files..."

# Read network configuration from cluster YAML
NETWORK_CIDR=$(yq -r '.network.cidr' "$CLUSTER_YAML")
GATEWAY=$(yq -r '.network.gateway // "192.168.42.1"' "$CLUSTER_YAML")

# Read DNS servers and format for NetworkManager
DNS_SERVERS_ARRAY=($(yq -r '.network.dns_servers[]? // "8.8.8.8"' "$CLUSTER_YAML"))
DNS_SERVERS_STRING=""
for dns in "${DNS_SERVERS_ARRAY[@]}"; do
  DNS_SERVERS_STRING="${DNS_SERVERS_STRING}${dns};"
done
# Remove trailing semicolon
DNS_SERVERS_STRING="${DNS_SERVERS_STRING%?}"

# Extract network base from CIDR for IP assignment
NETWORK_BASE=$(echo "$NETWORK_CIDR" | cut -d'.' -f1-3)

echo "  Network configuration:"
echo "    CIDR: $NETWORK_CIDR"
echo "    Gateway: $GATEWAY"
echo "    DNS Servers: ${DNS_SERVERS_STRING%?}"  # Remove trailing semicolon for display
echo "    Network Base: $NETWORK_BASE"

# Create NetworkManager connection file content
create_nm_config() {
  local ip=$1
  cat <<EOF
[connection]
id=ens192
type=ethernet
interface-name=ens192
autoconnect=true

[ethernet]

[ipv4]
method=manual
address1=${ip}/24,${GATEWAY}
dns=${DNS_SERVER};8.8.8.8;
dns-search=

[ipv6]
method=auto
addr-gen-mode=eui64
EOF
}

# Function to inject network config into ignition file
inject_network_config() {
  local ignition_file=$1
  local ip_address=$2
  local role=$3
  
  echo "  Injecting ${ip_address} into ${role} ignition..."
  
  # Determine hostname based on role and IP
  local hostname
  if [[ "$role" == "bootstrap" ]]; then
    hostname="bootstrap.${CLUSTER_NAME}.${BASE_DOMAIN}"
  else
    # Extract last octet for master naming
    local last_octet="${ip_address##*.}"
    local master_num=$((last_octet - 31))  # 31->0, 32->1, 33->2
    hostname="master-${master_num}.${CLUSTER_NAME}.${BASE_DOMAIN}"
  fi
  
  echo "    Setting hostname: $hostname"
  
  # Create the NetworkManager config
  nm_config=$(create_nm_config "$ip_address")
  nm_config_b64=$(echo "$nm_config" | base64 -w0)
  
  # Create hostname file content
  hostname_content=$(echo "$hostname")
  hostname_b64=$(echo "$hostname_content" | base64 -w0)
  
  # Create temporary file with updated ignition
  tmp_file=$(mktemp)
  
  # Add both network configuration and hostname to the ignition file
  jq --arg content "data:text/plain;charset=utf-8;base64,$nm_config_b64" \
     --arg hostname_content "data:text/plain;charset=utf-8;base64,$hostname_b64" \
     '.storage.files += [
       {
         "path": "/etc/NetworkManager/system-connections/ens192.nmconnection",
         "mode": 384,
         "overwrite": true,
         "contents": {
           "source": $content
         }
       },
       {
         "path": "/etc/hostname",
         "mode": 420,
         "overwrite": true,
         "contents": {
           "source": $hostname_content
         }
       }
     ]' "$ignition_file" > "$tmp_file"
  
  # Also add a generic ethernet connection as backup
  generic_nm_config=$(cat <<EOF
[connection]
id=Wired connection 1
type=ethernet
autoconnect=true

[ethernet]

[ipv4]
method=manual
address1=${ip_address}/24,${GATEWAY}
dns=${DNS_SERVER};8.8.8.8;
dns-search=

[ipv6]
method=auto
addr-gen-mode=eui64
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

# For masters, we need to create individual ignition files with unique IPs
if [[ -f "${INSTALL_DIR}/master.ign" ]]; then
  # Create individual master ignition files
  cp "${INSTALL_DIR}/master.ign" "${INSTALL_DIR}/master-0.ign"
  cp "${INSTALL_DIR}/master.ign" "${INSTALL_DIR}/master-1.ign" 
  cp "${INSTALL_DIR}/master.ign" "${INSTALL_DIR}/master-2.ign"
  
  # Inject unique IPs into each master ignition file
  inject_network_config "${INSTALL_DIR}/master-0.ign" "${NETWORK_BASE}.31" "master-0"
  inject_network_config "${INSTALL_DIR}/master-1.ign" "${NETWORK_BASE}.32" "master-1"
  inject_network_config "${INSTALL_DIR}/master-2.ign" "${NETWORK_BASE}.33" "master-2"
  
  echo "✅ Created individual master ignition files with unique IPs"
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
