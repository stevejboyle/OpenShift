#!/usr/bin/env bash
# Use guestinfo.ignition.config.url to bypass vSphere guestinfo size limits.
# macOS Bash 3.2–compatible; cross-platform base64 not required here.
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

: "${VCENTER_NETWORK:=${GOVC_NETWORK:-}}"
: "${VCENTER_DATASTORE:=${GOVC_DATASTORE:-}}"
: "${VCENTER_CLUSTER:=${GOVC_CLUSTER:-}}"
: "${VCENTER_DATACENTER:=${GOVC_DATACENTER:-}}"
: "${GOVC_FOLDER:=/}"

CLUSTER_NAME="$(yq e -r '.clusterName' "$CLUSTER_YAML")"
VM_CLUSTER_FOLDER_NAME="${CLUSTER_NAME}"
FULL_VCENTER_VM_FOLDER_PATH="${GOVC_FOLDER}/${VM_CLUSTER_FOLDER_NAME}"

RHCOS_VM_TEMPLATE_PATH="$(yq e -r '.rhcos_vm_template' "$CLUSTER_YAML")"
if [[ -z "$RHCOS_VM_TEMPLATE_PATH" || "$RHCOS_VM_TEMPLATE_PATH" == "null" ]]; then
  echo "❌ rhcos_vm_template not set in $CLUSTER_YAML"
  exit 1
fi

IGNITION_HOST="$(yq e -r '.ignition_server.host_ip // "127.0.0.1"' "$CLUSTER_YAML")"
IGNITION_PORT="$(yq e -r '.ignition_server.port // 8080' "$CLUSTER_YAML")"
IGN_BASE_URL="http://${IGNITION_HOST}:${IGNITION_PORT}"

echo "🔍 Ensuring VM folder exists: ${FULL_VCENTER_VM_FOLDER_PATH}"
if ! govc folder.info "${FULL_VCENTER_VM_FOLDER_PATH}" >/dev/null 2>&1; then
  govc folder.create "${FULL_VCENTER_VM_FOLDER_PATH}"
fi

MASTER_REPLICAS="$(yq e -r '.node_counts.master // 0' "$CLUSTER_YAML")"
WORKER_REPLICAS="$(yq e -r '.node_counts.worker // 0' "$CLUSTER_YAML")"

# Node list
NODES="bootstrap"
i=0; while (( i < MASTER_REPLICAS )); do NODES="$NODES master-${i}"; i=$((i+1)); done
i=0; while (( i < WORKER_REPLICAS )); do NODES="$NODES worker-${i}"; i=$((i+1)); done

echo "VMs to deploy: $NODES"
echo "⏱ $(date '+%Y-%m-%d %H:%M:%S') - 🚀 Deploying VMs (Ignition via URL: $IGN_BASE_URL)..."

# Quick check that the HTTP server is up (warn only)
if ! curl -sSf -o /dev/null "${IGN_BASE_URL}/"; then
  echo "⚠️  WARNING: ${IGN_BASE_URL}/ is not reachable from this host. Ensure your HTTP server is running and accessible by the VMs."
fi

for node in $NODES; do
  vm_name="${CLUSTER_NAME}-${node}"

  # Choose ignition filename (per-node if present; else role-wide)
  case "$node" in
    bootstrap) ign_file="bootstrap.ign" ;;
    master-*)  ign_file="${node}.ign"; if [[ ! -f "$INSTALL_DIR/$ign_file" ]]; then ign_file="master.ign"; fi ;;
    worker-*)  ign_file="${node}.ign"; if [[ ! -f "$INSTALL_DIR/$ign_file" ]]; then ign_file="worker.ign"; fi ;;
    *) echo "❌ Unknown node type: $node"; exit 1 ;;
  esac

  if [[ ! -f "$INSTALL_DIR/$ign_file" ]]; then
    echo "❌ Ignition file not found: $INSTALL_DIR/$ign_file"
    exit 1
  fi

  IGN_URL="${IGN_BASE_URL}/${ign_file}"
  # Optional: HEAD check (warn only)
  if ! curl -sI "$IGN_URL" | head -1 | grep -q "200"; then
    echo "⚠️  WARNING: $IGN_URL not returning HTTP 200 from this host. VMs may still reach it if network differs."
  fi

  # Defaults
  CPU=4; MEMORY_GB=16; DISK_GB=120; VM_MAC=""

  case "$node" in
    bootstrap)
      CPU="$(yq e -r '.vm_sizing.bootstrap.cpu // 4' "$CLUSTER_YAML")"
      MEMORY_GB="$(yq e -r '.vm_sizing.bootstrap.memory_gb // 16' "$CLUSTER_YAML")"
      DISK_GB="$(yq e -r '.vm_sizing.bootstrap.disk_gb // 120' "$CLUSTER_YAML")"
      VM_MAC="$(yq e -r '.node_macs.bootstrap // ""' "$CLUSTER_YAML")"
      ;;
    master-*)
      CPU="$(yq e -r '.vm_sizing.master.cpu // 8' "$CLUSTER_YAML")"
      MEMORY_GB="$(yq e -r '.vm_sizing.master.memory_gb // 32' "$CLUSTER_YAML")"
      DISK_GB="$(yq e -r '.vm_sizing.master.disk_gb // 120' "$CLUSTER_YAML")"
      VM_MAC="$(yq e -r ".node_macs[\"${node}\"] // \"\"" "$CLUSTER_YAML")"
      ;;
    worker-*)
      CPU="$(yq e -r '.vm_sizing.worker.cpu // 4' "$CLUSTER_YAML")"
      MEMORY_GB="$(yq e -r '.vm_sizing.worker.memory_gb // 16' "$CLUSTER_YAML")"
      DISK_GB="$(yq e -r '.vm_sizing.worker.disk_gb // 120' "$CLUSTER_YAML")"
      VM_MAC="$(yq e -r ".node_macs[\"${node}\"] // \"\"" "$CLUSTER_YAML")"
      ;;
  esac

  echo "Creating VM: $vm_name (${CPU} vCPU, ${MEMORY_GB}GB RAM, ${DISK_GB}GB Disk)"
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
  CLONE_OUT="$(govc vm.clone "${GOVC_CLONE_OPTIONS[@]}" "$vm_name" 2>&1)"
  CLONE_STATUS=$?
  set -e
  if [[ "$CLONE_STATUS" -ne 0 ]]; then
    echo "❌ govc vm.clone failed ($CLONE_STATUS):"
    echo "$CLONE_OUT"
    exit 1
  fi
  echo "✅ Clone OK."

  echo "⚙️  Resizing disk for $vm_name to ${DISK_GB}GB..."
  govc vm.disk.change -vm "$vm_name" -disk.label="Hard disk 1" -size="${DISK_GB}GB" || {
    echo "❌ Disk resize failed for $vm_name"; exit 1; }
  sleep 3

  # Use URL instead of embedding ignition
  KERNEL_ARGS="console=ttyS0,115200 ignition.firstboot ignition.platform.id=vsphere"
  govc vm.change -vm "$vm_name" \
    -e "guestinfo.ignition.config.url=${IGN_URL}" \
    -e "guestinfo.ignition.config.data.encoding=" \
    -e "guestinfo.ignition.config.data=" \
    -e "guestinfo.kernel.args=${KERNEL_ARGS}" || {
      echo "❌ Failed to set guestinfo URL for $vm_name"; exit 1; }

  echo "⚡ Powering on: $vm_name (Ignition: $IGN_URL)"
  govc vm.power -on=true "$vm_name"
done

echo "✅ VM deployment complete (URL mode)!"
