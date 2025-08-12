#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
INSTALL_DIR="${2:-install-configs/$(basename "$CLUSTER_YAML" .yaml)}"

if [[ -z "${CLUSTER_YAML:-}" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi
if [[ -z "${INSTALL_DIR:-}" ]]; then
  echo "❌ INSTALL_DIR not provided. Usage: $0 <cluster-yaml> <install-dir>"
  exit 1
fi

SCRIPTS_DIR="$(dirname "$0")"
source "${SCRIPTS_DIR}/load-vcenter-env.sh" "$CLUSTER_YAML"

: "${VCENTER_NETWORK:=${GOVC_NETWORK}}"
: "${VCENTER_DATASTORE:=${GOVC_DATASTORE}}"
: "${VCENTER_CLUSTER:=${GOVC_CLUSTER}}"
: "${VCENTER_DATACENTER:=${GOVC_DATACENTER}}"
: "${GOVC_FOLDER:=/}"

CLUSTER_NAME="$(yq '.clusterName' "$CLUSTER_YAML")"
VM_CLUSTER_FOLDER_NAME="${CLUSTER_NAME}"
FULL_VCENTER_VM_FOLDER_PATH="${GOVC_FOLDER}/${VM_CLUSTER_FOLDER_NAME}"

RHCOS_VM_TEMPLATE_PATH=$(yq '.rhcos_vm_template' "$CLUSTER_YAML" || { echo "❌ Failed to read rhcos_vm_template"; exit 1; })

IGNITION_SERVER_IP=$(yq '.ignition_server.host_ip // "127.0.0.1"' "$CLUSTER_YAML")
IGNITION_SERVER_PORT=$(yq '.ignition_server.port // 8080' "$CLUSTER_YAML")

echo "🔍 Checking for VM folder: ${FULL_VCENTER_VM_FOLDER_PATH}..."
if ! govc folder.info "${FULL_VCENTER_VM_FOLDER_PATH}" &>/dev/null; then
  echo "📁 Creating VM folder: ${FULL_VCENTER_VM_FOLDER_PATH}"
  govc folder.create "${FULL_VCENTER_VM_FOLDER_PATH}"
else
  echo "✅ VM folder exists: ${FULL_VCENTER_VM_FOLDER_PATH}"
fi

MASTER_REPLICAS=$(yq '.node_counts.master // 0' "$CLUSTER_YAML")
WORKER_REPLICAS=$(yq '.node_counts.worker // 0' "$CLUSTER_YAML")

NODES=("bootstrap")
if (( MASTER_REPLICAS > 0 )); then
  for i in $(seq 0 $((MASTER_REPLICAS - 1))); do NODES+=("master-${i}"); done
fi
if (( WORKER_REPLICAS > 0 )); then
  for i in $(seq 0 $((WORKER_REPLICAS - 1))); do NODES+=("worker-${i}"); done
fi

echo "VMs to deploy: ${NODES[*]}"
echo "⏱ $(date '+%Y-%m-%d %H:%M:%S') - 🚀 Deploying VMs..."

for node in "${NODES[@]}"; do
  vm_name="${CLUSTER_NAME}-${node}"

  case "$node" in
    bootstrap) ignition_file_local="$INSTALL_DIR/bootstrap.ign" ;;
    master-*)  ignition_file_local="$INSTALL_DIR/${node}.ign"; [[ -f "$ignition_file_local" ]] || ignition_file_local="$INSTALL_DIR/master.ign" ;;
    worker-*)  ignition_file_local="$INSTALL_DIR/${node}.ign"; [[ -f "$ignition_file_local" ]] || ignition_file_local="$INSTALL_DIR/worker.ign" ;;
    *) echo "❌ Unknown node type: $node"; exit 1 ;;
  esac

  CPU=4; MEMORY_GB=16; DISK_GB=120; VM_MAC=""
  case "$node" in
    bootstrap)
      CPU=$(yq '.vm_sizing.bootstrap.cpu // 4' "$CLUSTER_YAML")
      MEMORY_GB=$(yq '.vm_sizing.bootstrap.memory_gb // 16' "$CLUSTER_YAML")
      DISK_GB=$(yq '.vm_sizing.bootstrap.disk_gb // 120' "$CLUSTER_YAML")
      VM_MAC=$(yq '.node_macs.bootstrap // ""' "$CLUSTER_YAML")
      ;;
    master-*)
      CPU=$(yq '.vm_sizing.master.cpu // 8' "$CLUSTER_YAML")
      MEMORY_GB=$(yq '.vm_sizing.master.memory_gb // 32' "$CLUSTER_YAML")
      DISK_GB=$(yq '.vm_sizing.master.disk_gb // 120' "$CLUSTER_YAML")
      VM_MAC=$(yq ".node_macs.\"${node}\" // \""" "$CLUSTER_YAML")
      ;;
    worker-*)
      CPU=$(yq '.vm_sizing.worker.cpu // 4' "$CLUSTER_YAML")
      MEMORY_GB=$(yq '.vm_sizing.worker.memory_gb // 16' "$CLUSTER_YAML")
      DISK_GB=$(yq '.vm_sizing.worker.disk_gb // 120' "$CLUSTER_YAML")
      VM_MAC=$(yq ".node_macs.\"${node}\" // \""" "$CLUSTER_YAML")
      ;;
  esac

  echo "Creating VM: $vm_name (${CPU} vCPU, ${MEMORY_GB}GB RAM, ${DISK_GB}GB Disk)"
  [[ -n "$VM_MAC" && "$VM_MAC" != "null" ]] and_echo="   Desired MAC: $VM_MAC"
  if [[ -n "$VM_MAC" && "$VM_MAC" != "null" ]]; then echo "   Desired MAC: $VM_MAC"; else echo "   MAC: auto"; fi

  govc vm.destroy -vm.ipath="${FULL_VCENTER_VM_FOLDER_PATH}/${vm_name}" 2>/dev/null || true

  GOVC_CLONE_OPTIONS=(
    -vm="$RHCOS_VM_TEMPLATE_PATH"
    -net="$VCENTER_NETWORK"
    -ds="$VCENTER_DATASTORE"
    -cluster="$VCENTER_CLUSTER"
    -folder="${FULL_VCENTER_VM_FOLDER_PATH}"
    -on=false
    -c="${CPU}" -m=$((MEMORY_GB * 1024))
  )
  if [[ -n "$VM_MAC" && "$VM_MAC" != "null" ]]; then
    GOVC_CLONE_OPTIONS+=("-net.address=${VM_MAC}")
  fi

  set +e
  FULL_GOVC_CLONE_OUTPUT=$(govc vm.clone "${GOVC_CLONE_OPTIONS[@]}" "$vm_name" 2>&1)
  CLONE_STATUS=$?
  set -e
  if [[ "$CLONE_STATUS" -ne 0 ]]; then
    echo "❌ govc vm.clone failed ($CLONE_STATUS):"
    echo "$FULL_GOVC_CLONE_OUTPUT"
    exit 1
  fi
  echo "✅ Clone OK."

  echo "⚙️  Resizing disk for $vm_name to ${DISK_GB}GB..."
  govc vm.disk.change -vm "$vm_name" -disk.label="Hard disk 1" -size="${DISK_GB}GB" || {
    echo "❌ Disk resize failed for $vm_name"; exit 1; }
  sleep 5

  echo "DEBUG: Checking local ignition file: $ignition_file_local"
  [[ -f "$ignition_file_local" ]] || { echo "❌ Missing ign: $ignition_file_local"; exit 1; }

  LOCAL_IGN_SIZE=$(stat -f %z "$ignition_file_local" 2>/dev/null || stat -c %s "$ignition_file_local" 2>/dev/null)
  echo "DEBUG: Local ignition size: $LOCAL_IGN_SIZE bytes"

  set +e
  IGNITION_CONFIG_B64=$(cat "$ignition_file_local" | base64 -w0 2>/dev/null | tr -d '\n')
  BASE64_STATUS=$?
  set -e
  if [[ $BASE64_STATUS -ne 0 ]]; then
    echo "❌ base64 encoding failed for $ignition_file_local"; exit 1
  fi

  if (( ${#IGNITION_CONFIG_B64} > 65000 )); then
    echo "❌ Ignition too large for guestinfo (>${#IGNITION_CONFIG_B64} bytes)."
    echo "💡 Use guestinfo.ignition.config.url via an HTTP server instead."
    exit 1
  fi

  KERNEL_ARGS="console=ttyS0,115200 ignition.debug coreos.platform=vsphere cgroup_no_v1=all systemd.unified_cgroup_hierarchy=1 swapaccount=1 noswap"

  govc vm.change -vm "$vm_name"     -e "guestinfo.ignition.config.data=${IGNITION_CONFIG_B64}"     -e "guestinfo.ignition.config.data.encoding=base64"     -e "guestinfo.kernel.args=${KERNEL_ARGS}" || {
      echo "❌ Failed to set guestinfo for $vm_name"; exit 1; }

  echo "⚡ Powering on: $vm_name"
  govc vm.power -on=true "$vm_name"
done

echo "✅ VM deployment complete!"
