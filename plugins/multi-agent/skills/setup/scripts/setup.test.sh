#!/usr/bin/env bash
# Self-contained tests for setup.sh: each case builds a git repository and an
# empty home beside it, so no real layer is read or written.
#
# SC2016 is disabled file-wide: the single-quoted backticks are literal Markdown
# fences written into fixtures, never shell expansions.
# shellcheck disable=SC2016
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PROJECT_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/setup.sh"
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

fixture() {
  mkdir -p "$T/$1/repo" "$T/$1/home"
  git -C "$T/$1/repo" init -q
}
run() { # run <case> <action> <args...>
  local c="$1" a="$2"
  shift 2
  "$SUT" "$a" --root "$T/$c/repo" --home "$T/$c/home" "$@" 2>"$T/$c.err"
}

fixture dry
out="$(run dry apply --layer local roles.worker.effort=high)"
assert_contains "dry run names the overlay path" "$out" "would write: $T/dry/repo/.claude/multi-agent.local.yaml"
assert_contains "dry run shows the new key in a diff" "$out" '+    effort: high'
state=absent
[[ -e "$T/dry/repo/.claude/multi-agent.local.yaml" ]] && state=present
assert_eq "dry run writes nothing" absent "$state"

fixture local
out="$(run local apply --layer local --write roles.worker.effort=high fanout.frontier_guard=false)"
assert_contains "write reports the path" "$out" "wrote: $T/local/repo/.claude/multi-agent.local.yaml (local layer)"
assert_contains "write reads the stored value back" "$out" '  fanout.frontier_guard: false'
assert_eq "written file is the rendered subset" "$(cat "$T/local/repo/.claude/multi-agent.local.yaml")" \
  $'schema: 1\nfanout:\n  frontier_guard: false\nroles:\n  worker:\n    effort: high'
out="$(run local check session=fable)"
assert_contains "check shows the overlay as the source" "$out" '"source":{"model":"bundled","effort":"overlay"}'
assert_contains "check shows the guard off: fan-out inherits under fable" "$out" '"fanout":{"model":"inherit","omit_model":true,"effort":"high","guarded":false}'
assert_contains "check warns when the overlay is not ignored" "$out" 'WARN overlay'
out="$(run local apply --layer local --write roles.worker.effort=high)"
assert_eq "rerun with the same value is unchanged" "unchanged: $T/local/repo/.claude/multi-agent.local.yaml" "$out"
run local apply --layer local --write fanout.frontier_guard= >/dev/null
assert_lacks "an empty value removes the key" "$(cat "$T/local/repo/.claude/multi-agent.local.yaml")" 'frontier_guard'

fixture reject
run reject apply --layer local --write roles.worker.model=claude-opus-5-5 >/dev/null
assert_eq "a value the resolver rejects exits 1" 1 "$?"
assert_contains "the rejection is relayed" "$(cat "$T/reject.err")" "roles.worker.model rejected"
state=absent
[[ -e "$T/reject/repo/.claude/multi-agent.local.yaml" ]] && state=present
assert_eq "a rejected candidate writes nothing" absent "$state"
run reject apply --layer local --write roles.judge.model=opus >/dev/null
assert_eq "an unknown role exits 1" 1 "$?"

fixture team
out="$(run team apply --layer team --write roles.verifier.effort=xhigh)"
assert_contains "team with no file creates the docs convention file" "$out" "wrote: $T/team/repo/docs/conventions/multi-agent.md"
out="$(run team check session=opus)"
assert_contains "the new docs block is the team layer" "$out" '"layer":"team","path":"'"$T/team/repo/docs/conventions/multi-agent.md"'","state":"read"'

fixture docs
mkdir -p "$T/docs/repo/docs/conventions"
printf '# Ours\n\nProse.\n\n````markdown\n```yaml config\nschema: 1\n```\n````\n\n```yaml config\nschema: 1\nroles:\n  worker:\n    effort: low\n```\n\nTrailer.\n' \
  >"$T/docs/repo/docs/conventions/multi-agent.md"
run docs apply --layer team --write roles.verifier.effort=high >/dev/null
f="$(cat "$T/docs/repo/docs/conventions/multi-agent.md")"
assert_contains "docs block: prose before is kept" "$f" $'# Ours\n\nProse.'
assert_contains "docs block: the example fence is untouched" "$f" $'````markdown\n```yaml config\nschema: 1\n```\n````'
assert_contains "docs block: existing and new keys merged" "$f" $'```yaml config\nschema: 1\nroles:\n  verifier:\n    effort: high\n  worker:\n    effort: low\n```\n\nTrailer.'

fixture claudefile
mkdir -p "$T/claudefile/repo/.claude"
printf 'schema: 1\n' >"$T/claudefile/repo/.claude/multi-agent.yaml"
out="$(run claudefile apply --layer team roles.worker.effort=low)"
assert_contains "team uses an existing .claude file" "$out" "would write: $T/claudefile/repo/.claude/multi-agent.yaml"

fixture broken
mkdir -p "$T/broken/repo/.claude"
printf 'schema: 1\nroles:\n\tworker:\n' >"$T/broken/repo/.claude/multi-agent.local.yaml"
run broken apply --layer local --write roles.worker.effort=low >/dev/null
assert_eq "an unparseable layer is not overwritten" 1 "$?"
assert_contains "the parse error names the line" "$(cat "$T/broken.err")" 'line 3: tab indentation'

fixture user
out="$(run user apply --layer user --write fanout.model=sonnet)"
assert_contains "user layer goes under the home" "$out" "wrote: $T/user/home/.claude/multi-agent.yaml"

mkdir -p "$T/homeroot"
git -C "$T/homeroot" init -q
"$SUT" apply --root "$T/homeroot" --home "$T/homeroot" --layer local roles.worker.effort=low >/dev/null 2>"$T/homeroot.err"
assert_eq "local layer refused at a home root" 2 "$?"
assert_contains "the refusal names the root class" "$(cat "$T/homeroot.err")" 'not applicable at a home root'

"$SUT" apply --root "$T/user/repo" --home "$T/user/home" --layer team >/dev/null 2>&1
assert_eq "apply without a pair is a usage error" 2 "$?"

printf '\n%d cases, %d failed\n' "$CASES" "$FAILED"
((FAILED == 0))
