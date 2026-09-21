#!/bin/bash
# Builds a single-file MCP server: one .pyz to copy to another machine, runnable with
# the python3 macOS ships. Uses zipapp from the standard library; nothing to install.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$here/dist/olai-mcp.pyz}"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

mkdir -p "$staging/olai_mcp" "$(dirname "$out")"
# Only the standard-library server: server.py needs the mcp package and is left out.
cp "$here"/olai_mcp/{__init__,mirror,tools,standalone}.py "$staging/olai_mcp/"

python3 -m zipapp "$staging" \
  --main "olai_mcp.standalone:main" \
  --python "/usr/bin/env python3" \
  --output "$out"

echo "built $out ($(du -h "$out" | cut -f1))"
