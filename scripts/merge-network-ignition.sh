#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"
INSTALL_DIR="${2:-install-configs/$(basename "$CLUSTER_YAML" .yaml)}"

if [[ -z "${CLUSTER_YAML:-}" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

echo "🔧 Merging network configurations into ignition files..."

merge_network_config() {
  local ignition_file="$1"
  local network_config="$2"
  local node_name="$3"

  echo "📝 Processing $node_name ignition file..."

  cp "$ignition_file" "${ignition_file}.backup"

  if [[ -f "$network_config" ]]; then
    jq --slurpfile network "$network_config" '
      .storage.files = (.storage.files // []) + ($network[0].files // []) |
      .systemd.units = (.systemd.units // []) + ($network[0].systemd.units // [])
    ' "$ignition_file" > "${ignition_file}.tmp"
    mv "${ignition_file}.tmp" "$ignition_file"
    echo "✅ Merged network config for $node_name"
  else
    echo "⚠️  Network config not found for $node_name: $network_config"
  fi
}

if [[ -f "$INSTALL_DIR/master.ign" ]]; then
  MASTER_REPLICAS=$(yq '.node_counts.master // 0' "$CLUSTER_YAML")
  if (( MASTER_REPLICAS > 0 )); then
    for i in $(seq 0 $((MASTER_REPLICAS - 1))); do
      master_ign="$INSTALL_DIR/master-${i}.ign"
      cp "$INSTALL_DIR/master.ign" "$master_ign"
      if [[ -f "$INSTALL_DIR/network-configs/master-${i}-network.json" ]]; then
        merge_network_config "$master_ign" "$INSTALL_DIR/network-configs/master-${i}-network.json" "master-${i}"
      fi
    done
    echo "📋 Created individual master ignition files with network configs"
  fi
fi

if [[ -f "$INSTALL_DIR/worker.ign" ]]; then
  WORKER_REPLICAS=$(yq '.node_counts.worker // 0' "$CLUSTER_YAML")
  if (( WORKER_REPLICAS > 0 )); then
    for i in $(seq 0 $((WORKER_REPLICAS - 1))); do
      worker_ign="$INSTALL_DIR/worker-${i}.ign"
      cp "$INSTALL_DIR/worker.ign" "$worker_ign"
      if [[ -f "$INSTALL_DIR/network-configs/worker-${i}-network.json" ]]; then
        merge_network_config "$worker_ign" "$INSTALL_DIR/network-configs/worker-${i}-network.json" "worker-${i}"
      fi
    done
    echo "📋 Created individual worker ignition files with network configs"
  fi
fi

if [[ -f "$INSTALL_DIR/bootstrap.ign" ]] && [[ -f "$INSTALL_DIR/network-configs/bootstrap-network.json" ]]; then
  merge_network_config "$INSTALL_DIR/bootstrap.ign" "$INSTALL_DIR/network-configs/bootstrap-network.json" "bootstrap"
fi

echo "✅ Network configurations merged into ignition files"
