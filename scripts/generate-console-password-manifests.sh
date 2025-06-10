#!/bin/zsh
set -e

CLUSTER_YAML="$1"
pwf=$(yq '.consolePasswordFile' "$CLUSTER_YAML")
if [[ -f "$pwf" ]]; then
  h=$(<"$pwf")
  BASE_DIR="$(dirname "$(dirname "$0")")"
  MANIFESTS_DIR="${BASE_DIR}/install-configs/manifests"
  mkdir -p "${MANIFESTS_DIR}"

  cat > "${MANIFESTS_DIR}/99-user-pass.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-user-pass
spec:
  config:
    ignition:
      version: 3.2.0
    passwd:
      users:
        - name: core
          passwordHash: "${h}"
EOF

  echo "✅ console-password manifest generated."
else
  echo "⚠ No console-password file defined; skipping."
fi
