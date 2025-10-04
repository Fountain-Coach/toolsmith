#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == "" ]]; then
  echo "Usage: $0 <tag>  # e.g. v2025.10.04" >&2
  exit 1
fi

TAG="$1"
OWNER_REPO="Fountain-Coach/fountainkit-toolsmith-image"
ASSET_URL="https://github.com/${OWNER_REPO}/releases/download/${TAG}/manifest-snippet.json"

echo "Fetching manifest snippet from ${ASSET_URL}"
mkdir -p .toolsmith
curl -fL "${ASSET_URL}" -o .toolsmith/tools.json
echo "Wrote .toolsmith/tools.json"
sed -n '1,120p' .toolsmith/tools.json || true

