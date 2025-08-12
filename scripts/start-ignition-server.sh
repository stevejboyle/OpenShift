#!/usr/bin/env bash
# Simple HTTP server to serve ignition files from the install dir
set -euo pipefail
INSTALL_DIR="$1"
PORT="${2:-8088}"

if [[ -z "${INSTALL_DIR:-}" || ! -d "$INSTALL_DIR" ]]; then
  echo "Usage: $0 <install-dir> [port]"
  exit 1
fi
cd "$INSTALL_DIR"
echo "📦 Serving Ignition files from $INSTALL_DIR on port $PORT (http://0.0.0.0:$PORT/)"
# macOS + Linux compatible
python3 -m http.server "$PORT" --bind 0.0.0.0
