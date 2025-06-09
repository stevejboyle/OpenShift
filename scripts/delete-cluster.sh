#!/bin/bash
set -e

CLUSTER_FILE=$1
if [ -z "$CLUSTER_FILE" ]; then
  echo "Usage: $0 <cluster.yaml>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/load-vcenter-env.sh"

BASE_DIR="$(dirname "$SCRIPT_DIR")"
VM_FOLDER=$(yq '.vsphere.folder' "$CLUSTER_FILE")

echo "⚠ WARNING: This will delete all VMs AND generated ignition/config files for cluster: ${CLUSTER_FILE}!"
read -p "Type 'DELETE' to confirm: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
  echo "Aborted."
  exit 1
fi

# Hardened deletion loop
for VM in $(yq -r '.vms | keys[]' "$CLUSTER_FILE"); do
  VM_PATH="${VM_FOLDER}/${VM}"

  if govc vm.info "$VM_PATH" &>/dev/null; then
    echo "🗑 Deleting VM: $VM_PATH"

    if ! govc vm.power -off -force "$VM_PATH" &>/dev/null; then
      echo "⚠ Failed to power off $VM_PATH (may already be off)"
    fi

    if ! govc vm.destroy "$VM_PATH" &>/dev/null; then
      echo "⚠ Failed to destroy $VM_PATH (may already be deleted)"
    fi

  else
    echo "⚠ VM not found: $VM_PATH"
  fi
done

# Cleanup ignition/config files
INSTALL_DIR="${BASE_DIR}/install-configs"
if [ -d "$INSTALL_DIR" ]; then
  echo "🧹 Cleaning up ignition/config files..."
  for VM in $(yq -r '.vms | keys[]' "$CLUSTER_FILE"); do rm -f "${INSTALL_DIR}/${VM}.ign"; done
  rm -f "${INSTALL_DIR}/bootstrap.ign" "${INSTALL_DIR}/master.ign" "${INSTALL_DIR}/worker.ign"
  rm -f "${INSTALL_DIR}/install-config.yaml" "${INSTALL_DIR}/metadata.json"
fi

echo "✅ Cluster VMs and generated files deleted."
