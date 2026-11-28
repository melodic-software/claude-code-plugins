#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--help" ]]; then
  echo "usage: capabilities.sh  (emits this adapter's capabilities.json manifest)"
  exit 0
fi
if [[ $# -gt 0 ]]; then
  echo "capabilities.sh: unexpected argument: $1" >&2
  exit 2
fi

MANIFEST="$SCRIPT_DIR/capabilities.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "capabilities.sh: manifest not found: $MANIFEST" >&2
  exit 3
fi

jq -c . "$MANIFEST" || {
  echo "capabilities.sh: manifest is not valid JSON: $MANIFEST" >&2
  exit 3
}
