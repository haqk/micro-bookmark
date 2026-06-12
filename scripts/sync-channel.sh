#!/usr/bin/env bash
# Emit a plugin-channel manifest from repo.json so it can be PR'd into
# micro-editor/plugin-channel (plugins/micro-bookmark.json).
#
# Usage: scripts/sync-channel.sh [out-path]
#   out-path defaults to ./micro-bookmark.json
#
# After running, open a PR against https://github.com/micro-editor/plugin-channel
# replacing plugins/micro-bookmark.json with the emitted file.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

OUT="${1:-./micro-bookmark.json}"

if ! [[ -f repo.json ]]; then
    echo "error: repo.json not found" >&2
    exit 2
fi

# The plugin-channel expects the same shape as repo.json (an array with one
# object), so we just emit repo.json — formatted and validated.
jq '.' repo.json > "$OUT"

echo "✓ wrote $OUT"
echo ""
echo "Next:"
echo "  1. Fork https://github.com/micro-editor/plugin-channel"
echo "  2. Replace plugins/micro-bookmark.json with $OUT"
echo "  3. Open a PR"
