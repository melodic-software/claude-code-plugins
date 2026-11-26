#!/usr/bin/env bash
set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
  printf 'check-plugin-profiles: node is not on PATH\n' >&2
  exit 2
fi
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="${1:-$here}"
home="$(mktemp -d)"
trap 'rm -rf "${home:?}"' EXIT
changed=()
if [[ -n "${DIFF_BASE:-}" ]] && git -C "$root" -c core.quotePath=false diff --no-renames --name-only "$DIFF_BASE...HEAD" -- >"$home/changed" 2>/dev/null; then
  changed=(--changed "$home/changed")
fi
HOME="$home" USERPROFILE="$home" CLAUDE_CONFIG_DIR="$home/.claude" CLAUDE_PROJECT_DIR="$root" \
  node "$here/plugins/plugin-profiles/scripts/profiles.mjs" check \
  --catalog "$root/.claude-plugin/marketplace.json" \
  --shipped "$root/plugins/plugin-profiles/profiles" \
  --skills "$root/plugins" "${changed[@]}"
