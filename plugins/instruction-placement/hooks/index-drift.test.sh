#!/usr/bin/env bash
# Contract tests for the index-drift PostToolUse hook.
#
# The matcher is Write|Edit, which the fleet hook-budget convention counts as
# always-on. The most important case here is therefore not a behavior case but
# the HOT PATH one: a write outside a rules tree must return before spawning
# anything, and its cost is measured rather than asserted by eye.
#
# fixture-isolation-scope: this suite builds git fixtures and clears the
# inherited git environment itself rather than sourcing a harness, so the plugin
# stays self-contained and portable outside this marketplace.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/index-drift.sh"

PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  printf 'ok: %s\n' "$1"
}
bad() {
  FAIL=$((FAIL + 1))
  printf 'BAD: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
expect_eq() {
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "$2" "$3"; fi
}
expect_has() {
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1" "contains: $3" "$2"; fi
}
expect_lacks() {
  if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1" "must not contain: $3" "$2"; fi
}

payload_for() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"; }
run_hook() { printf '%s' "$1" | bash "$HOOK" 2>&1; }

# A repo with an index that is deliberately stale: a rule exists which the
# committed index block does not mention.
build_drifted() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/.claude/rules" "$dir/src"
  printf 'class X {}\n' >"$dir/src/a.cs"
  printf '@AGENTS.md\n' >"$dir/CLAUDE.md"
  {
    printf '# Project\n\n'
    printf '%s\n' "<!-- BEGIN GENERATED: instruction-placement rules index -->"
    printf '\nNo path-scoped rules or nested instruction files are present in this repository.\n\n'
    printf '%s\n' "<!-- END GENERATED: instruction-placement rules index -->"
  } >"$dir/AGENTS.md"
  printf -- '---\npaths:\n  - "**/*.cs"\n---\n\n# C# rule\n' >"$dir/.claude/rules/csharp.md"
  git -C "$dir" init -q .
  git -C "$dir" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm t >/dev/null 2>&1
  printf '%s' "$dir"
}

# --------------------------------------------------------------------------
# Hot path — the case that runs on every write in the fleet
# --------------------------------------------------------------------------
repo="$(build_drifted)"

out="$(run_hook "$(payload_for "$repo/src/a.cs")")"
expect_eq "a write outside a rules tree produces no output" "" "$out"

printf '%s' "$(payload_for "$repo/src/a.cs")" | bash "$HOOK" >/dev/null 2>&1
expect_eq "a write outside a rules tree exits 0" "0" "$?"

# Cost: the always-on path must be dominated by process startup, not by work.
# Ten runs, reported rather than threshold-asserted on a shared CI host — the
# assertion is a generous ceiling that still catches an accidental git or
# render call landing on this path.
if [[ -n "${EPOCHREALTIME:-}" ]]; then
  start="${EPOCHREALTIME/,/.}"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    printf '%s' "$(payload_for "$repo/src/a.cs")" | bash "$HOOK" >/dev/null 2>&1
  done
  end="${EPOCHREALTIME/,/.}"
  per_ms="$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%d", ((e - s) * 1000) / 10 }')"
  printf 'note: hot-path cost ~%s ms per invocation (10 runs, includes bash startup)\n' "$per_ms"
  if ((per_ms < 400)); then
    ok "the hot path stays well inside the per-tool-call budget"
  else
    bad "the hot path stays well inside the per-tool-call budget" "<400 ms" "${per_ms} ms"
  fi
else
  printf 'note: EPOCHREALTIME unavailable (bash < 5.0); hot-path cost not measured\n'
fi

# --------------------------------------------------------------------------
# Drift detection
# --------------------------------------------------------------------------
out="$(run_hook "$(payload_for "$repo/.claude/rules/csharp.md")")"
expect_has "a rules-tree write on a drifted index reports drift" "$out" "stale"
expect_has "the notice names the rule that changed" "$out" "csharp.md"
expect_has "the notice says why it matters" "$out" "subagents"

printf '%s' "$(payload_for "$repo/.claude/rules/csharp.md")" | bash "$HOOK" >/dev/null 2>&1
expect_eq "the hook is advisory — it exits 0 even on drift" "0" "$?"

# --------------------------------------------------------------------------
# In-sync and opted-out repositories must stay silent
# --------------------------------------------------------------------------
"$HOOK_DIR/../scripts/render-index.sh" write --file "$repo/AGENTS.md" --root "$repo" >/dev/null 2>&1
out="$(run_hook "$(payload_for "$repo/.claude/rules/csharp.md")")"
expect_eq "an in-sync index produces no notice" "" "$out"

noindex="$(mktemp -d)"
mkdir -p "$noindex/.claude/rules"
printf '# Project\n' >"$noindex/CLAUDE.md"
printf -- '---\npaths: ["**/*.cs"]\n---\n\n# Rule\n' >"$noindex/.claude/rules/r.md"
git -C "$noindex" init -q .
git -C "$noindex" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$noindex" -c user.email=t@t -c user.name=t commit -qm t >/dev/null 2>&1
out="$(run_hook "$(payload_for "$noindex/.claude/rules/r.md")")"
expect_eq "a repo that never adopted an index is not nagged" "" "$out"

# --------------------------------------------------------------------------
# Robustness — a hook must never break the tool call that triggered it
# --------------------------------------------------------------------------
printf '' | bash "$HOOK" >/dev/null 2>&1
expect_eq "empty stdin exits 0" "0" "$?"

printf 'not json at all' | bash "$HOOK" >/dev/null 2>&1
expect_eq "malformed stdin exits 0" "0" "$?"

printf '{"tool_name":"Write","tool_input":{}}' | bash "$HOOK" >/dev/null 2>&1
expect_eq "a payload with no file_path exits 0" "0" "$?"

out="$(run_hook "$(payload_for "/nonexistent/.claude/rules/x.md")")"
expect_eq "a path outside any repository produces no output" "" "$out"

# --------------------------------------------------------------------------
# Kill switch
# --------------------------------------------------------------------------
out="$(printf '%s' "$(payload_for "$repo/.claude/rules/csharp.md")" |
  CLAUDE_PLUGIN_OPTION_INSTRUCTION_PLACEMENT_INDEX_DRIFT_ENABLED=false bash "$HOOK" 2>&1)"
expect_lacks "the kill switch silences the hook" "$out" "stale"

rm -rf "$repo" "$noindex"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
