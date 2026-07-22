#!/usr/bin/env bash
# Enumerate EVERY per-project auto-memory directory on this machine.
#
# Machine-wide counterpart to the single-project resolver: lists each
# `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/memory` directory with its MEMORY.md
# line count and topic-file count, one line per store. Backs the `status all` /
# `purge all` flows of the `stateless` skill and is reusable by the sibling `audit`
# skill. Enumeration only — it never reads settings overrides (`autoMemoryDirectory`
# can relocate an individual project's store; the workflow folds those in separately)
# and never writes anything.
#
# Config root honors CLAUDE_CONFIG_DIR: when set, the whole `~/.claude` tree
# (including `projects/`) lives under it, per the official .claude-directory doc.
#
# Usage: bash "${CLAUDE_PLUGIN_ROOT}/skills/stateless/scripts/enumerate-all-projects.sh"
# Output: one line per memory dir: "<abs path>\tMEMORY.md:<lines|absent>\ttopics:<n>".
# Never exits non-zero for an absent tree — absence is data the caller reports.

set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
enumerate-all-projects.sh — list every per-project auto-memory dir machine-wide.

Usage:
  enumerate-all-projects.sh [--help]

Prints one line per `<config root>/projects/*/memory` directory:
  <abs path>  MEMORY.md:<line count|absent>  topics:<topic-file count>

The config root is ${CLAUDE_CONFIG_DIR:-~/.claude}. Enumeration only — per-project
`autoMemoryDirectory` overrides are not read here. Never fails on an absent tree.
EOF
  exit 0
fi

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
  if [[ -f "$mem/MEMORY.md" ]]; then
    lines=$(wc -l <"$mem/MEMORY.md" | tr -d ' \r')
  else
    lines="absent"
  fi
  topics=$(find "$mem" -maxdepth 1 -name '*.md' ! -name 'MEMORY.md' 2>/dev/null | wc -l | tr -d ' \r')
  printf '%s\tMEMORY.md:%s\ttopics:%s\n' "$mem" "$lines" "$topics"
done
shopt -u nullglob

if [[ "$found" -eq 0 ]]; then
  echo "No per-project memory directories under $projects_root."
fi
exit 0
