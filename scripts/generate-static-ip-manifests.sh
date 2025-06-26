#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
if [[ -z "$CLUSTER_YAML" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Usage: $0 <cluster-yaml>"
  exit 1
fi

CLUSTER_NAME=$(yq -r '.clusterName' "$CLUSTER_YAML")
INSTALL_DIR="install-configs/$CLUSTER_NAME/manifests"
mkdir -p "$INSTALL_DIR"

echo "Generating MachineConfig with static IPs for worker nodes..."

# Get network details from cluster YAML
NETWORK_CIDR=$(yq -r '.network.cidr' "$CLUSTER_YAML")
NETWORK_GATEWAY=$(yq -r '.network.gateway' "$CLUSTER_YAML")
DNS_SERVERS_ARRAY=$(yq -r '.network.dns_servers[]' "$CLUSTER_YAML")
DNS_SERVERS=$(echo "$DNS_SERVERS_ARRAY" | paste -sd ';' -) # Joins DNS servers with ';'

# Get worker static IP configurations
WORKER_IPS_CONFIG=$(yq -r '.network.worker_static_ips[] | @json' "$CLUSTER_YAML" || true)

if [[ -z "$WORKER_IPS_CONFIG" ]]; then
  echo "ℹ️ No worker_static_ips found in cluster YAML. Skipping static IP manifest generation."
  exit 0
fi

WORKER_COUNT=0
echo "$WORKER_IPS_CONFIG" | while IFS= read -r worker_ip_config; do
  WORKER_COUNT=$((WORKER_COUNT + 1))
  IP_ADDRESS=$(echo "$worker_ip_config" | jq -r '.ip')
  INTERFACE_NAME=$(echo "$worker_ip_config" | jq -r '.interface_name')

  if [[ -z "$IP_ADDRESS" || -z "$INTERFACE_NAME" ]]; then
    echo "❌ Error: Missing 'ip' or 'interface_name' for a worker static IP entry in YAML."
    exit 1
  fi

  # Extract CIDR prefix length (e.g., /24 from 192.168.42.0/24)
  CIDR_LENGTH=$(echo "$NETWORK_CIDR" | cut -d'/' -f2)

  # Construct the NetworkManager connection string
  # Using address1 with gateway, and then dns.
  CONNECTION_STRING="[connection]\nid=${INTERFACE_NAME}\ntype=ethernet\ninterface-name=${INTERFACE_NAME}\n[ipv4]\nmethod=manual\naddress1=${IP_ADDRESS}/${CIDR_LENGTH},${NETWORK_GATEWAY}\ndns=${DNS_SERVERS}"

  # Encode the connection string
  ENCODED_CONNECTION=$(echo -n "$CONNECTION_STRING" | base64 -w0)

  cat > "$INSTALL_DIR/99-worker-${WORKER_COUNT}-static-network-config.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: static-network-config-worker-${WORKER_COUNT}
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - path: /etc/NetworkManager/system-connections/${INTERFACE_NAME}.nmconnection
        mode: 0600
        overwrite: true
        contents:
          source: data:text/plain;charset=utf-8;base64,${ENCODED_CONNECTION}
EOF
  echo "✅ Generated static IP manifest for worker ${WORKER_COUNT} (${IP_ADDRESS}) at: ${INSTALL_DIR}/99-worker-${WORKER_COUNT}-static-network-config.yaml"
done

echo "✅ Static IP manifests generation complete."