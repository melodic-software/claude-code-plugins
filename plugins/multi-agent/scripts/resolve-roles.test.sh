#!/usr/bin/env bash
# Self-contained tests for resolve-roles.sh: it ships inside the plugin, so the
# suite must run wherever the plugin is installed. Assertions match substrings
# of the resolver's compact JSON, so no JSON tool is needed.
#
# SC2016 is disabled file-wide: the single-quoted backticks are literal Markdown
# fences written into fixtures, never shell expansions.
# shellcheck disable=SC2016
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PROJECT_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/resolve-roles.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

FAILED=0
CASES=0
pass() {
  CASES=$((CASES + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASES=$((CASES + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_lacks() {
  case "$2" in
  *"$3"*) fail "$1" "does not contain: $3" "$2" ;;
  *) pass "$1" ;;
  esac
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

# A fixture: <case>/repo is a git repository, <case>/home an empty home beside it.
fixture() {
  mkdir -p "$T/$1/repo/.claude" "$T/$1/home/.claude"
  git -C "$T/$1/repo" init -q
}
run() { # run <case> <args...>
  local c="$1"
  shift
  "$SUT" --root "$T/$c/repo" --home "$T/$c/home" "$@" 2>"$T/$c.err"
}

fixture plain
out="$(run plain all --session-model fable)"
assert_contains "frontier session: worker fan-out names opus" "$out" '"worker":{"role":"worker","single":{"model":"inherit","omit_model":true,"effort":"medium","guarded":false},"fanout":{"model":"opus","omit_model":false,"effort":"medium","guarded":true}'
assert_contains "frontier session: verifier fan-out names opus at high" "$out" '"fanout":{"model":"opus","omit_model":false,"effort":"high","guarded":true}'
assert_contains "frontier session: retrieval keeps sonnet medium in both variants" "$out" '"retrieval":{"role":"retrieval","single":{"model":"sonnet","omit_model":false,"effort":"medium","guarded":false},"fanout":{"model":"sonnet","omit_model":false,"effort":"medium","guarded":false}'
assert_contains "frontier session: the single judge may inherit" "$out" '"verifier":{"role":"verifier","single":{"model":"inherit","omit_model":true'
assert_contains "frontier session flagged" "$out" '"session_frontier":true'

out="$(run plain all --session-model opus)"
assert_contains "non-frontier session: worker fan-out omits model" "$out" '"fanout":{"model":"inherit","omit_model":true,"effort":"medium","guarded":false}'
assert_lacks "non-frontier session: no variant is guarded" "$out" '"guarded":true'

out="$(run plain all)"
assert_contains "unknown session: worker fan-out names opus" "$out" '"worker":{"role":"worker","single":{"model":"inherit","omit_model":true,"effort":"medium","guarded":false},"fanout":{"model":"opus"'
assert_contains "unknown session is treated as frontier" "$out" '"session_model":null,"session_frontier":true'

out="$(run plain worker --session-model sonnet --workload research)"
assert_contains "research workload keeps the worker's own effort" "$out" '"single":{"model":"inherit","omit_model":true,"effort":"medium"'
assert_lacks "one role asked, one role returned" "$out" '"verifier"'

run plain nosuch >/dev/null
assert_eq "unknown role exits 2" 2 "$?"
assert_contains "unknown role lists the valid roles" "$(cat "$T/plain.err")" "valid roles: orchestrator worker verifier retrieval"

run plain all --session-model gpt >/dev/null
assert_eq "unknown session model exits 2" 2 "$?"

# Per-key override across layers, with the source layer named per value.
fixture layered
printf 'schema: 1\nroles:\n  worker:\n    effort: high\n' >"$T/layered/home/.claude/multi-agent.yaml"
printf 'schema: 1\nroles:\n  worker:\n    model: sonnet\n' >"$T/layered/repo/.claude/multi-agent.local.yaml"
out="$(run layered worker --session-model opus)"
assert_contains "user-global effort and overlay model merge per key" "$out" '"single":{"model":"sonnet","omit_model":false,"effort":"high"'
assert_contains "source names the layer per value" "$out" '"source":{"model":"overlay","effort":"user-global"}'

# The docs convention block is the team layer and wins over .claude/multi-agent.yaml.
fixture docs
mkdir -p "$T/docs/repo/docs/conventions"
printf '# multi-agent\n\n```yaml config\nschema: 1\nroles:\n  verifier:\n    effort: xhigh\n```\n' >"$T/docs/repo/docs/conventions/multi-agent.md"
printf 'schema: 1\nroles:\n  verifier:\n    effort: low\n' >"$T/docs/repo/.claude/multi-agent.yaml"
out="$(run docs verifier --session-model opus)"
assert_contains "docs block supplies the team layer" "$out" '"effort":"xhigh"'
assert_contains "both team files named in a note" "$out" "both exist; using the docs block"

# Two config blocks in one docs file make an invalid team layer.
fixture twoblocks
mkdir -p "$T/twoblocks/repo/docs/conventions"
printf '```yaml config\nschema: 1\n```\n\n```yaml config\nschema: 1\n```\n' >"$T/twoblocks/repo/docs/conventions/multi-agent.md"
out="$(run twoblocks worker --session-model opus)"
assert_contains "two blocks: team layer skipped with the line" "$out" 'multi-agent.md:5: a second ```yaml config block'

# An example of the block inside a longer outer fence is not a block.
fixture example
mkdir -p "$T/example/repo/docs/conventions"
printf '# x\n\n````markdown\n```yaml config\nschema: 1\nroles:\n  worker:\n    effort: max\n```\n````\n' >"$T/example/repo/docs/conventions/multi-agent.md"
printf 'schema: 1\nroles:\n  worker:\n    effort: high\n' >"$T/example/repo/.claude/multi-agent.yaml"
out="$(run example worker --session-model opus)"
assert_contains "fenced example ignored: .claude file is the team layer" "$out" '"effort":"high"'
assert_lacks "fenced example ignored: no both-exist note" "$out" "both exist"

# Turning the guard off is the explicit opt-in to frontier fan-outs.
fixture optout
printf 'schema: 1\nfanout:\n  frontier_guard: false\n' >"$T/optout/repo/.claude/multi-agent.yaml"
out="$(run optout worker --session-model fable)"
assert_contains "guard off: frontier fan-out inherits" "$out" '"fanout":{"model":"inherit","omit_model":true'

# An explicit frontier alias is guarded too.
fixture explicit
printf 'schema: 1\nroles:\n  worker:\n    model: fable\n' >"$T/explicit/repo/.claude/multi-agent.yaml"
out="$(run explicit worker --session-model opus)"
assert_contains "explicit fable worker: single keeps fable" "$out" '"single":{"model":"fable"'
assert_contains "explicit fable worker: fan-out names opus" "$out" '"fanout":{"model":"opus","omit_model":false,"effort":"medium","guarded":true}'

# A malformed layer is skipped and named; the others still apply.
fixture malformed
printf 'schema: 1\nroles:\n\tworker:\n' >"$T/malformed/repo/.claude/multi-agent.yaml"
printf 'schema: 1\nroles:\n  worker:\n    effort: low\n' >"$T/malformed/repo/.claude/multi-agent.local.yaml"
out="$(run malformed worker --session-model opus)"
assert_eq "malformed layer still exits 0" 0 "$?"
assert_contains "malformed layer is named with its line" "$out" 'team layer skipped:'
assert_contains "malformed layer state is skipped" "$out" '"layer":"team"'
assert_contains "the overlay still applies" "$out" '"effort":"low"'

# Wrong schema skips the layer.
fixture schema
printf 'schema: 2\nroles:\n  worker:\n    effort: low\n' >"$T/schema/repo/.claude/multi-agent.yaml"
out="$(run schema worker --session-model opus)"
assert_contains "schema 2 layer skipped" "$out" 'does not declare schema: 1'
assert_contains "bundled effort kept" "$out" '"effort":"medium"'

# Non-alias model ids and unknown values are rejected per key.
fixture reject
printf 'schema: 1\nroles:\n  worker:\n    model: claude-opus-5-5\n    effort: turbo\n  judge:\n    model: opus\n' >"$T/reject/repo/.claude/multi-agent.yaml"
out="$(run reject all --session-model opus)"
assert_contains "full model id rejected" "$out" "roles.worker.model rejected: 'claude-opus-5-5'"
assert_contains "unknown effort rejected" "$out" "roles.worker.effort rejected: 'turbo'"
assert_contains "unknown role in a layer ignored" "$out" "unknown role 'judge'"
fixture ctrl
printf 'schema: 1\nroles:\n  worker:\n    effort: \033[31mred\n' >"$T/ctrl/repo/.claude/multi-agent.yaml"
out="$(run ctrl all --session-model opus)"
assert_contains "control characters in a rejected value are replaced" "$out" "effort rejected: '?[31mred'"
if ! command -v node >/dev/null 2>&1; then
  pass "output with a control-character value is valid JSON (skipped: no node)"
elif printf '%s' "$out" | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))' 2>/dev/null; then
  pass "output with a control-character value is valid JSON"
else
  fail "output with a control-character value is valid JSON" "parses" "$out"
fi
assert_contains "rejected keys fall back to the layer below" "$out" '"worker":{"role":"worker","single":{"model":"inherit","omit_model":true,"effort":"medium"'

# Team and overlay are not read at a home root.
mkdir -p "$T/homeroot/.claude"
git -C "$T/homeroot" init -q
printf 'schema: 1\nroles:\n  worker:\n    effort: low\n' >"$T/homeroot/.claude/multi-agent.local.yaml"
out="$("$SUT" --root "$T/homeroot" --home "$T/homeroot" worker 2>/dev/null)"
assert_contains "home root: overlay not applicable" "$out" 'not-applicable (home root)'
assert_contains "home root: overlay value not applied" "$out" '"effort":"medium"'

# A role resolving to haiku is not blocked, but gains a note pointing at the rubric.
fixture haikurole
printf 'schema: 1\nroles:\n  retrieval:\n    model: haiku\n' >"$T/haikurole/home/.claude/multi-agent.yaml"
out="$(run haikurole all --session-model opus)"
assert_contains "user layer haiku retrieval: still resolves" "$out" '"retrieval":{"role":"retrieval","single":{"model":"haiku"'
assert_contains "user layer haiku retrieval: noted" "$out" 'retrieval: resolves to haiku'
assert_lacks "user layer haiku retrieval: other roles not noted" "$out" 'worker: resolves to haiku'

out="$(run plain all --session-model haiku)"
assert_contains "haiku session: inheriting role noted" "$out" 'worker: resolves to haiku'
assert_lacks "haiku session: sonnet retrieval not noted" "$out" 'retrieval: resolves to haiku'

out="$(run plain all --session-model opus)"
assert_lacks "no haiku anywhere: no haiku note" "$out" 'resolves to haiku'

out="$("$SUT" pointers)"
assert_contains "pointers lists each role's as_of" "$out" $'worker\tas_of\t2026-10-10'
assert_contains "pointers lists the fan-out guard basis" "$out" $'fanout\tpointer\thttps://code.claude.com/docs/en/workflows#cost'

printf '\n%d cases, %d failed\n' "$CASES" "$FAILED"
((FAILED == 0))
