#!/usr/bin/env bash
set -euo pipefail

YAML="$1"
CLUSTER_NAME=$(yq -r '.clusterName' "$YAML")
VCENTER_DATACENTER=$(yq -r '.vcenter_datacenter' "$YAML")
DATASTORE=$(yq -r '.vcenter_datastore' "$YAML")
CLUSTER=$(yq -r '.vcenter_cluster' "$YAML")
NETWORK=$(yq -r '.vcenter_network' "$YAML")
ISO_PATH="iso/$CLUSTER_NAME-rhcos-live.iso"

create_vm() {
  NAME=$1
  echo "Creating VM: $NAME"
  govc vm.create -dc="$VCENTER_DATACENTER" -ds="$DATASTORE" -net="$NETWORK" -pool="/$VCENTER_DATACENTER/host/$CLUSTER/Resources" -c=4 -m=16384 -g=otherGuest64 -disk=100G "$NAME"
  govc device.cdrom.add -vm "$NAME"
  govc device.cdrom.insert -vm "$NAME" "$ISO_PATH"
  govc vm.change -vm "$NAME" -e=guestinfo.ignition.config.data= -e=guestinfo.ignition.config.data.encoding=base64
  govc vm.power -on "$NAME"
}

create_vm "$CLUSTER_NAME-bootstrap"
create_vm "$CLUSTER_NAME-master-0"
create_vm "$CLUSTER_NAME-master-1"
create_vm "$CLUSTER_NAME-master-2"
create_vm "$CLUSTER_NAME-worker-0"
create_vm "$CLUSTER_NAME-worker-1"
