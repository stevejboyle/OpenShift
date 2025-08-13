#!/usr/bin/env bash
# Deploy VMs using a tiny inline Ignition that replaces itself with the real URL.
# This guarantees Ignition sees "user config provided" and then pulls the full .ign.
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
FULL_VCENTER_VM_FOLDER_PATH="${GOVC_FOLDER%/}/${CLUSTER_NAME}"

RHCOS_VM_TEMPLATE_PATH="$(yq e -r '.rhcos_vm_template' "$CLUSTER_YAML")"
if [[ -z "$RHCOS_VM_TEMPLATE_PATH" || "$RHCOS_VM_TEMPLATE_PATH" == "null" ]]; then
  echo "❌ rhcos_vm_template not set in $CLUSTER_YAML"
  exit 1
fi

IGNITION_HOST="$(yq e -r '.ignition_server.host_ip // "127.0.0.1"' "$CLUSTER_YAML")"
IGNITION_PORT="$(yq e -r '.ignition_server.port // 8088' "$CLUSTER_YAML")"
IGN_BASE_URL="http://${IGNITION_HOST}:${IGNITION_PORT}"

echo "🔍 Ensuring VM folder exists: ${FULL_VCENTER_VM_FOLDER_PATH}"
if ! govc folder.info "${FULL_VCENTER_VM_FOLDER_PATH}" >/dev/null 2>&1; then
  govc folder.create "${FULL_VCENTER_VM_FOLDER_PATH}"
fi

MASTER_REPLICAS="$(yq e -r '.node_counts.master // 0' "$CLUSTER_YAML")"
WORKER_REPLICAS="$(yq e -r '.node_counts.worker // 0' "$CLUSTER_YAML")"

NODES="bootstrap"
i=0; while (( i < MASTER_REPLICAS )); do NODES="$NODES master-${i}"; i=$((i+1)); done
i=0; while (( i < WORKER_REPLICAS )); do NODES="$NODES worker-${i}"; i=$((i+1)); done

# Fail-fast if server not responding locally
if ! curl -sSf -o /dev/null "${IGN_BASE_URL}/"; then
  echo "❌ Ignition HTTP server is not responding at ${IGN_BASE_URL}/"
  exit 1
fi

for node in $NODES; do
  vm_name="${CLUSTER_NAME}-${node}"
  VM_IPATH="${FULL_VCENTER_VM_FOLDER_PATH%/}/${vm_name}"

  case "$node" in
    bootstrap) ign_file="bootstrap.ign" ;;
    master-*)  ign_file="${node}.ign"; if [[ ! -f "$INSTALL_DIR/$ign_file" ]]; then ign_file="master.ign"; fi ;;
    worker-*)  ign_file="${node}.ign"; if [[ ! -f "$INSTALL_DIR/$ign_file" ]]; then ign_file="worker.ign"; fi ;;
  esac

  if [[ ! -f "$INSTALL_DIR/$ign_file" ]]; then
    echo "❌ Ignition file not found: $INSTALL_DIR/$ign_file"
    exit 1
  fi

  IGN_URL="${IGN_BASE_URL}/${ign_file}"

  # Resources & MAC
  CPU="$(yq e -r '.vm_sizing.bootstrap.cpu // 4' "$CLUSTER_YAML")"; MEMORY_GB="$(yq e -r '.vm_sizing.bootstrap.memory_gb // 16' "$CLUSTER_YAML")"; DISK_GB="$(yq e -r '.vm_sizing.bootstrap.disk_gb // 120' "$CLUSTER_YAML")"; VM_MAC=""
  case "$node" in
    bootstrap) VM_MAC="$(yq e -r '.node_macs.bootstrap // ""' "$CLUSTER_YAML")" ;;
    master-*)  CPU="$(yq e -r '.vm_sizing.master.cpu // 8' "$CLUSTER_YAML")"; MEMORY_GB="$(yq e -r '.vm_sizing.master.memory_gb // 32' "$CLUSTER_YAML")"; DISK_GB="$(yq e -r '.vm_sizing.master.disk_gb // 120' "$CLUSTER_YAML")"; VM_MAC="$(yq e -r ".node_macs[\"${node}\"] // \"\"" "$CLUSTER_YAML")" ;;
    worker-*)  CPU="$(yq e -r '.vm_sizing.worker.cpu // 4' "$CLUSTER_YAML")"; MEMORY_GB="$(yq e -r '.vm_sizing.worker.memory_gb // 16' "$CLUSTER_YAML")"; DISK_GB="$(yq e -r '.vm_sizing.worker.disk_gb // 120' "$CLUSTER_YAML")"; VM_MAC="$(yq e -r ".node_macs[\"${node}\"] // \"\"" "$CLUSTER_YAML")" ;;
  esac

  echo "Creating VM: $vm_name (${CPU} vCPU, ${MEMORY_GB}GB RAM, ${DISK_GB}GB Disk)"
  [[ -n "$VM_MAC" && "$VM_MAC" != "null" ]] && echo "   Desired MAC: $VM_MAC" || echo "   MAC: auto"

  govc vm.destroy -vm.ipath "${VM_IPATH}" 2>/dev/null || true

  GOVC_CLONE_OPTIONS=(
    -vm="$RHCOS_VM_TEMPLATE_PATH"
    -net="$VCENTER_NETWORK"
    -ds="$VCENTER_DATASTORE"
    -cluster="$VCENTER_CLUSTER"
    -folder="${FULL_VCENTER_VM_FOLDER_PATH}"
    -on=false
    -c="${CPU}" -m=$((MEMORY_GB * 1024))
  )
  [[ -n "$VM_MAC" && "$VM_MAC" != "null" ]] && GOVC_CLONE_OPTIONS+=("-net.address=${VM_MAC}")

  govc vm.clone "${GOVC_CLONE_OPTIONS[@]}" "$vm_name"

  govc vm.disk.change -vm.ipath "${VM_IPATH}" -disk.label="Hard disk 1" -size="${DISK_GB}GB"
  sleep 1

  # Force vmware platform and enable UUID
  KERNEL_ARGS="console=ttyS0,115200 ignition.firstboot ignition.platform.id=vmware coreos.platform_id=vmware"
  govc vm.change -vm.ipath "${VM_IPATH}" \
    -e "disk.enableUUID=TRUE" \
    -e "guestinfo.ignition.config.data.encoding=base64" \
    -e "guestinfo.kernel.args=${KERNEL_ARGS}"

  # Set tiny inline config that replaces with the URL
  MIN_IGN="{\"ignition\":{\"version\":\"3.4.0\",\"config\":{\"replace\":{\"source\":\"${IGN_URL}\"}}}}"
  B64=$(printf "%s" "$MIN_IGN" | base64 | tr -d '\n')
  govc vm.change -vm.ipath "${VM_IPATH}" \
    -e "guestinfo.ignition.config.data=${B64}" \
    -e "guestinfo.ignition.config.url="

  # Verify
  EC="$(govc vm.info -e -vm.ipath "${VM_IPATH}")"
  echo "$EC" | grep -E 'guestinfo\.ignition\.config\.data' >/dev/null || { echo "❌ guestinfo.ignition.config.data missing"; exit 1; }
  echo "$EC" | grep -E 'guestinfo\.ignition\.config\.data\.encoding.*base64' >/dev/null || { echo "❌ guestinfo.ignition.config.data.encoding != base64"; exit 1; }
  echo "$EC" | grep -E 'ignition\.platform\.id=vmware' >/dev/null || { echo "❌ kernel args missing ignition.platform.id=vmware"; exit 1; }

  echo "⚡ Powering on: $vm_name"
  govc vm.power -on=true -vm.ipath "${VM_IPATH}"
done

echo "✅ VM deployment complete (inline replace → URL)"
