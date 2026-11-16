#!/usr/bin/env bash
# Gate: the shipped plugin profiles name only plugins this marketplace's catalog lists, under the
# catalog's own name, and interface-design keeps every planning member. The rules are the
# plugin-profiles check action's (plugins/plugin-profiles/lib/check.mjs); this runs it on a tree.
#
#   scripts/check-plugin-profiles.sh [<repository root>]   default: this checkout
#
# Exits and streams follow scripts/README.md, "The check-script contract".
set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
  printf 'check-plugin-profiles: node is not on PATH\n' >&2
  exit 2
fi
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="${1:-$here}"
home="$(mktemp -d)"
trap 'rm -rf "${home:?}"' EXIT
HOME="$home" USERPROFILE="$home" CLAUDE_CONFIG_DIR="$home/.claude" CLAUDE_PROJECT_DIR="$root" \
  node "$here/plugins/plugin-profiles/scripts/profiles.mjs" check \
  --catalog "$root/.claude-plugin/marketplace.json" \
  --shipped "$root/plugins/plugin-profiles/profiles"
