#!/usr/bin/env bash
set -e

CLUSTER_YAML="$(realpath "$1")"
BOOTSTRAP_MODE="${2:-bootstrap}"  # Default to bootstrap mode if not specified

if [[ -z "$CLUSTER_YAML" ]] || [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "Usage: $0 <cluster.yaml> [bootstrap|post-install]"
  echo "❌ Cluster file not found: $1"
  echo ""
  echo "Modes:"
  echo "  bootstrap    - Generate configs for initial install (masters + workers only)"
  echo "  post-install - Generate configs for running cluster (masters + workers only)"
  exit 1
fi

# Get cluster name and network configuration from cluster.yaml
CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
BASE_DIR="$(dirname "$(dirname "$0")")"
MANIFESTS_DIR="${BASE_DIR}/install-configs/${CLUSTER_NAME}/manifests"

# Extract network configuration from cluster.yaml
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
echo "🌐 DNS: $DNS_SERVERS"
echo "🌐 Generating static IP manifests for cluster ${CLUSTER_NAME}..."

# Create machine manifests with static IPs
mkdir -p "${MANIFESTS_DIR}"

# Function to create machine config with node selector
create_machine_config() {
  local role="$1"
  local name="$2" 
  local ip="$3"
  local node_selector="$4"
  
  local selector_config=""
  if [[ -n "$node_selector" ]]; then
    selector_config="  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: $node_selector"
  fi

cat > "${MANIFESTS_DIR}/99-${name}-static-ip.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: $role
  name: 99-${name}-static-ip
spec:
$selector_config
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
address1=${ip}/24,${GATEWAY}
dns=${DNS_SERVERS};
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
}

# Generate configs based on mode
if [[ "$BOOTSTRAP_MODE" == "bootstrap" ]]; then
  echo "🚀 Bootstrap mode: Generating configs for initial install (including bootstrap)"
  
  # Bootstrap node with static IP .30
  create_machine_config "bootstrap" "bootstrap" "${NETWORK_BASE}.30" ""
  
  # Masters
  create_machine_config "master" "master-0" "${NETWORK_BASE}.31" "master-0.${CLUSTER_NAME}.openshift.sboyle.internal"
  create_machine_config "master" "master-1" "${NETWORK_BASE}.32" "master-1.${CLUSTER_NAME}.openshift.sboyle.internal"  
  create_machine_config "master" "master-2" "${NETWORK_BASE}.33" "master-2.${CLUSTER_NAME}.openshift.sboyle.internal"
  
  # Workers
  create_machine_config "worker" "worker-0" "${NETWORK_BASE}.40" "worker-0.${CLUSTER_NAME}.openshift.sboyle.internal"
  create_machine_config "worker" "worker-1" "${NETWORK_BASE}.41" "worker-1.${CLUSTER_NAME}.openshift.sboyle.internal"
  
  echo "✅ Bootstrap static IP manifests generated for subnet $SUBNET_CIDR:"
  echo "   Bootstrap: ${NETWORK_BASE}.30"
  echo "   Master-0:  ${NETWORK_BASE}.31"
  echo "   Master-1:  ${NETWORK_BASE}.32"  
  echo "   Master-2:  ${NETWORK_BASE}.33"
  echo "   Worker-0:  ${NETWORK_BASE}.40"
  echo "   Worker-1:  ${NETWORK_BASE}.41"
  echo ""
  echo "📝 Next steps for bootstrap:"
  echo "   1. Include these manifests in your manifests/ directory"
  echo "   2. Update load balancer to include all IPs"
  echo "   3. Run: openshift-install create cluster --dir=."
  echo ""
  echo "🔧 Load balancer configuration needed:"
  echo "   API Backend (port 6443): ${NETWORK_BASE}.30, ${NETWORK_BASE}.31, ${NETWORK_BASE}.32, ${NETWORK_BASE}.33"
  echo "   Apps Backend (ports 80/443): ${NETWORK_BASE}.40, ${NETWORK_BASE}.41"
  
elif [[ "$BOOTSTRAP_MODE" == "post-install" ]]; then
  echo "🔧 Post-install mode: Generating configs for running cluster"
  
  # Masters without node selectors for running cluster
  create_machine_config "master" "master-0" "${NETWORK_BASE}.31" ""
  create_machine_config "master" "master-1" "${NETWORK_BASE}.32" ""
  create_machine_config "master" "master-2" "${NETWORK_BASE}.33" ""
  
  # Workers without node selectors
  create_machine_config "worker" "worker-0" "${NETWORK_BASE}.40" ""
  create_machine_config "worker" "worker-1" "${NETWORK_BASE}.41" ""
  
  echo "✅ Post-install static IP manifests generated for subnet $SUBNET_CIDR:"
  echo "   Master-0:  ${NETWORK_BASE}.31"
  echo "   Master-1:  ${NETWORK_BASE}.32"
  echo "   Master-2:  ${NETWORK_BASE}.33"
  echo "   Worker-0:  ${NETWORK_BASE}.40"
  echo "   Worker-1:  ${NETWORK_BASE}.41"
  echo ""
  echo "📝 Next steps for post-install:"
  echo "   1. Apply to running cluster:"
  echo "      oc apply -f ${MANIFESTS_DIR}/99-master-*-static-ip.yaml"
  echo "      oc apply -f ${MANIFESTS_DIR}/99-worker-*-static-ip.yaml"
  echo "   2. Update your load balancer backend pools with these IPs"
  echo "   3. Watch nodes restart: oc get nodes -w"
  
else
  echo "❌ Invalid mode. Use 'bootstrap' or 'post-install'"
  echo ""
  echo "Examples:"
  echo "  $0 cluster.yaml bootstrap     # For initial install"
  echo "  $0 cluster.yaml post-install  # For running cluster"
  exit 1
fi