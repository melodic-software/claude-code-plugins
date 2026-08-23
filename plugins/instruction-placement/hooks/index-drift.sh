#!/usr/bin/env bash
# PostToolUse hook: notice when a rules-tree edit leaves the generated index stale.
#
# ADVISORY / NON-BLOCKING: always exits 0. The authoritative gate is
# `/instruction-placement:check`, which belongs in CI. This hook only shortens
# the feedback loop from "next CI run" to "next tool call".
#
# WHY IT IS CHEAP ON THE HOT PATH. The matcher is `Write|Edit`, which the fleet
# hook-budget convention counts as always-on: it fires on every file write in
# every session where this plugin is installed. So the FIRST thing after the
# kill switch is a substring test on the written path, and every write that is
# not inside a `.claude/rules/` tree returns before any subprocess, any git
# call, or any index render. Rules files change rarely; the 99.9% case costs a
# string comparison.
#
# WHY IT EXISTS AT ALL. Index drift is silent by construction. A rule added
# without regenerating the index is a rule that no subagent can reach, and
# nothing about the repository looks wrong until someone runs the gate.
#
# Kill switch: the plugin's `index_drift_hook_enabled` userConfig boolean,
# surfaced as $CLAUDE_PLUGIN_OPTION_INSTRUCTION_PLACEMENT_INDEX_DRIFT_ENABLED.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "INSTRUCTION_PLACEMENT_INDEX_DRIFT"

# Read inherited fd0 directly. stdin is read ONCE — reading it twice drains the
# pipe, and on Windows Git Bash `</dev/stdin` cannot resolve the Win32 pipe CC
# spawns hooks with, which would make this a silent no-op rather than an error.
payload="$(cat 2>/dev/null || true)"
[[ -n "$payload" ]] || exit 0

file_path="$(hook::raw_file_path "$payload" 2>/dev/null || true)"
[[ -n "$file_path" ]] || exit 0

# ---- THE HOT-PATH GUARD -----------------------------------------------------
# Everything above is string handling; everything below spawns processes. A
# write outside a rules tree stops here.
case "$file_path" in
*/.claude/rules/*.md | .claude/rules/*.md) ;;
*) exit 0 ;;
esac
# -----------------------------------------------------------------------------

# repo_root resolves from a DIRECTORY; handing it the file path returns the
# path unchanged with a non-zero status, which an `|| true` would swallow into
# a silent no-op — the exact shape of failure this hook exists to prevent
# elsewhere.
repo_root="$(hook::repo_root "$(dirname "$file_path")" 2>/dev/null || true)"
[[ -n "$repo_root" && -d "$repo_root" ]] || exit 0

renderer="$(dirname "${BASH_SOURCE[0]}")/../scripts/render-index.sh"
[[ -x "$renderer" ]] || exit 0

# Resolve the index target the same way the check skill documents: an explicit
# AGENTS.md first, then CLAUDE.md. A repository with neither has no index home
# and nothing to be stale.
target=""
for candidate in "$repo_root/AGENTS.md" "$repo_root/CLAUDE.md"; do
  if [[ -f "$candidate" ]]; then
    target="$candidate"
    break
  fi
done
[[ -n "$target" ]] || exit 0

verdict="$("$renderer" check --file "$target" --root "$repo_root" 2>/dev/null || true)"
case "$verdict" in
DRIFTED*)
  hook::emit_system_message \
    "instruction-placement: ${file_path##*/} changed and the generated rules index in ${target##*/} is now stale. Regenerate it (render-index.sh write --file ${target##*/}) — an un-indexed rule is unreachable from subagents." \
    2>/dev/null || true
  ;;
*)
  # IN-SYNC, or NO-BLOCK (this repository has not adopted an index). Neither is
  # a drift, and a repository that never opted in should not be nagged.
  :
  ;;
esac

exit 0
