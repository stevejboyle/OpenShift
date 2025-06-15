#!/usr/bin/env bash
set -euo pipefail

YAML="$1"
CLUSTER_NAME=$(yq -r '.clusterName' "$YAML")
INSTALL_DIR="install-configs/$CLUSTER_NAME/manifests"
mkdir -p "$INSTALL_DIR"

echo "Generating MachineConfig with static IPs for post-boot config"
cat > "$INSTALL_DIR/99-static-network-config.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: static-network-config
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - path: /etc/NetworkManager/system-connections/ens192.nmconnection
        mode: 0600
        overwrite: true
        contents:
          source: data:text/plain;charset=utf-8;base64,$(echo -n "[connection]\nid=ens192\ntype=ethernet\ninterface-name=ens192\n[ipv4]\nmethod=manual\naddress1=192.168.42.40/24,192.168.42.1\ndns=192.168.1.1;" | base64 -w0)
EOF
