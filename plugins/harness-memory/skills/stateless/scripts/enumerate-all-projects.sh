#!/usr/bin/env bash
# Enumerate EVERY per-project auto-memory directory on this machine.
# Enumeration only: never reads `autoMemoryDirectory` overrides (the workflow folds
# those in) and never writes.

set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
enumerate-all-projects.sh — list every per-project auto-memory dir machine-wide.

Usage:
  enumerate-all-projects.sh [--help]

Prints one line per `<config root>/projects/*/memory` directory (tab-separated):
  <abs path>\tMEMORY.md:<line count|absent>\ttopics:<topic-file count>

The config root is ${CLAUDE_CONFIG_DIR:-~/.claude}. Enumeration only — per-project
`autoMemoryDirectory` overrides are not read here. Never fails on an absent tree.
EOF
  exit 0
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The topic-file counting rule is shared with the sibling scope-report.sh, whose
# printed count is a contract of its own.
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$script_dir/../../.." && pwd)}"
# shellcheck source=../../../lib/topic-count.sh
source "$plugin_root/lib/topic-count.sh"

config_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
projects_root="$config_root/projects"

if [[ ! -d "$projects_root" ]]; then
  echo "No projects directory at $projects_root — no auto-memory stores on this machine."
  exit 0
fi

found=0
shopt -s nullglob
for mem in "$projects_root"/*/memory; do
  [[ -d "$mem" ]] || continue
  found=$((found + 1))
  # No -f pre-check: a file deleted mid-read (concurrent purge) must degrade to "absent".
  # 2>/dev/null precedes the input redirect so a missing file's shell error is silenced.
  lines=$(wc -l 2>/dev/null <"$mem/MEMORY.md" | tr -d ' \r') || true
  lines="${lines:-absent}"
  topics=$(mtopics::count "$mem")
  printf '%s\tMEMORY.md:%s\ttopics:%s\n' "$mem" "$lines" "$topics"
done
shopt -u nullglob

if [[ "$found" -eq 0 ]]; then
  echo "No per-project memory directories under $projects_root."
fi
exit 0
