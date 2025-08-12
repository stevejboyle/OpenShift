#!/usr/bin/env bash
set -euo pipefail

CLUSTER_YAML="$1"

if [[ -z "${CLUSTER_YAML:-}" || ! -f "$CLUSTER_YAML" ]]; then
  echo "❌ Cluster YAML not found: $CLUSTER_YAML"
  exit 1
fi

echo "📖 Reading label definitions from: $CLUSTER_YAML"

get_labels() {
  local role="$1"
  yq e ".labels.${role}[]" "$CLUSTER_YAML" 2>/dev/null || true
}

for node in $(oc get nodes -o name); do
  node_name=$(basename "$node")

  if [[ "$node_name" == master-* ]]; then
    echo "🔹 Labeling master node: $node_name"
    mapfile -t labels < <(get_labels master)
    for label in "${labels[@]}"; do
      [[ -n "$label" ]] && oc label --overwrite "$node" "$label"
    done
  elif [[ "$node_name" == worker-* ]]; then
    echo "🔸 Labeling worker node: $node_name"
    mapfile -t labels < <(get_labels worker)
    for label in "${labels[@]}"; do
      [[ -n "$label" ]] && oc label --overwrite "$node" "$label"
    done
  else
    echo "⚠️ Skipping unrecognized node: $node_name"
  fi
done

echo "✅ Labels from YAML applied to nodes."
