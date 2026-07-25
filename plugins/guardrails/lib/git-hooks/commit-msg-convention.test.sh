#!/usr/bin/env bash
# Contract test for lib/git-hooks/commit-msg-convention.sh (guardrails plugin).
#
# Black-box: installs the hook template + resolver copy into an isolated repo's
# .git/hooks, writes commit-message files, invokes the hook directly, asserts
# on exit code (1 = rejected, 0 = accepted).

set -uo pipefail

HOOK_DIR_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HOOK_DIR_SRC/../.." && pwd)"
TEMPLATE="$PLUGIN_ROOT/lib/git-hooks/commit-msg-convention.sh"
RESOLVER_SRC="$PLUGIN_ROOT/hooks/resolve-convention-pattern.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

PASS=0
FAIL=0
ok() {
  PASS=$((PASS + 1))
  printf 'ok: %s\n' "$1"
}
bad() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1" >&2
}
assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then ok "$label (exit $actual)"; else bad "$label: expected exit $expected, got $actual"; fi
}

# Isolated repo with the hook installed and an optional team convention body.
newrepo() {
  local d
  d="$(mktemp -d "$TEST_TMPDIR/repo.XXXXXX")"
  git -C "$d" init -q -b main
  mkdir -p "$d/.claude"
  [[ -n "${1:-}" ]] && printf '%s\n' "$1" >"$d/.claude/source-control.md"
  local hooks
  hooks="$(git -C "$d" rev-parse --absolute-git-dir)/hooks"
  mkdir -p "$hooks"
  cp "$TEMPLATE" "$hooks/commit-msg"
  cp "$RESOLVER_SRC" "$hooks/guardrails-resolve-convention.sh"
  chmod +x "$hooks/commit-msg"
  printf '%s' "$d"
}

# run <label> <repo> <message-content> <expected-exit>
run() {
  local label="$1" repo="$2" msg="$3" expected="$4" rc hooks
  hooks="$(git -C "$repo" rev-parse --absolute-git-dir)/hooks"
  printf '%s\n' "$msg" >"$repo/.git-commit-msg-under-test"
  (cd "$repo" && bash "$hooks/commit-msg" "$repo/.git-commit-msg-under-test") >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

TICKET=$'## subject_pattern\n^[A-Z]+-[0-9]+: .+'
CC=$'## subject_pattern\nConventional Commits'
PCRE=$'## subject_pattern\n^(?:feat|fix): .+'

# --- unresolved -> pass-through ------------------------------------------------
r="$(newrepo "")"
run "no team file: any subject accepted" "$r" "whatever subject" 0
r="$(newrepo "$PCRE")"
run "PCRE pattern: non-enforceable, accepted" "$r" "whatever subject" 0

# --- enforcement ---------------------------------------------------------------
r="$(newrepo "$TICKET")"
run "ticket pattern: conforming accepted" "$r" $'ABC-123: do the thing\n\nBody.' 0
run "ticket pattern: violating rejected" "$r" $'junk subject\n\nBody.' 1
run "comment lines skipped before subject" "$r" $'# comment from template\nABC-9: real subject' 0
run "fixup! subject exempt (autosquash)" "$r" "fixup! anything at all" 0
run "squash! subject exempt (autosquash)" "$r" "squash! anything" 0
run "empty message: git's problem, accepted here" "$r" "" 0
r="$(newrepo "$CC")"
run "CC keyword: feat accepted" "$r" "feat: add thing" 0
run "CC keyword: junk rejected" "$r" "junk subject" 1

# --- resolver removed -> fail open, never block blind ---------------------------
r="$(newrepo "$TICKET")"
hooks="$(git -C "$r" rev-parse --absolute-git-dir)/hooks"
rm -f "$hooks/guardrails-resolve-convention.sh"
run "resolver removed: accepted (no blind block)" "$r" "junk subject" 0

# --- chaining ------------------------------------------------------------------
r="$(newrepo "$TICKET")"
hooks="$(git -C "$r" rev-parse --absolute-git-dir)/hooks"
printf '#!/usr/bin/env bash\nexit 1\n' >"$hooks/commit-msg.pre-guardrails"
chmod +x "$hooks/commit-msg.pre-guardrails"
run "chained pre-existing hook rejection is final" "$r" "ABC-1: fine subject" 1
printf '#!/usr/bin/env bash\nexit 0\n' >"$hooks/commit-msg.pre-guardrails"
run "chained hook passes, convention still enforced" "$r" "junk subject" 1
run "chained hook passes, conforming accepted" "$r" "ABC-2: fine" 0

# --- sentinel present (inference-exclusion contract) ---------------------------
if grep -q "guardrails-commit-msg-convention" "$TEMPLATE"; then
  ok "sentinel marker present in template"
else
  bad "sentinel marker missing from template"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
