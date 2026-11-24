#!/usr/bin/env bash
# fixture-isolation-scope: this suite builds git fixtures and clears the
# inherited git environment itself rather than sourcing a harness, so the plugin
# stays self-contained and portable outside this marketplace.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/verify-load.sh"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# shellcheck source=../lib/test-helpers.sh
source "$SCRIPT_DIR/../lib/test-helpers.sh"
SKIPPED=0

skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP: %s\n  reason: %s\n' "$1" "$2"
}

run() { bash "$SCRIPT" "$@" 2>&1; }

build_fixture() {
  local dir
  dir="$(mktemp -d "$SCRATCH/fx.XXXXXX")"
  mkdir -p "$dir/.claude/rules" "$dir/src"
  printf 'public class Invoice { }\n' >"$dir/src/Invoice.cs"
  printf 'export const x = 1;\n' >"$dir/src/client.ts"
  {
    printf -- '---\n'
    printf 'paths:\n  - "**/*.cs"\n'
    printf -- '---\n\n# C# conventions\n\nInterfaces are prefixed with I.\n'
  } >"$dir/.claude/rules/csharp.md"
  {
    printf -- '---\n'
    printf 'paths:\n  - "**/*.ts"\n'
    printf -- '---\n\n# TypeScript conventions\n\nUse strict mode.\n'
  } >"$dir/.claude/rules/typescript.md"
  printf '@AGENTS.md\n' >"$dir/CLAUDE.md"
  printf '# Project\n\nAlways run the tests.\n' >"$dir/AGENTS.md"
  git -C "$dir" init -q .
  git -C "$dir" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm t >/dev/null 2>&1
  printf '%s' "$dir"
}

out="$(run --help)"
assert_contains "--help prints usage" "$out" "verify-load.sh"

run >/dev/null 2>&1
assert_eq "a missing --trigger is a usage error" "2" "$?"

run --trigger nope.txt >/dev/null 2>&1
assert_eq "an unreadable --trigger is a usage error" "2" "$?"

run --trigger x --timeout abc >/dev/null 2>&1
assert_eq "a non-integer --timeout is a usage error" "2" "$?"

repo="$(build_fixture)"

run --root "$repo" --trigger src/Invoice.cs --claude /nonexistent-cli-xyz >/dev/null 2>&1
assert_eq "an absent CLI reports UNKNOWN, exit 3" "3" "$?"
out="$(run --root "$repo" --trigger src/Invoice.cs --claude /nonexistent-cli-xyz)"
assert_contains "the UNKNOWN verdict names the missing CLI" "$out" "UNKNOWN"
assert_contains "it does not claim a pass" "$out" "not available"
if [[ "$out" == *"VERDICT	PASS"* ]]; then
  fail "an unmeasurable run never reports PASS" "no PASS verdict" "$out"
else
  pass "an unmeasurable run never reports PASS"
fi

CLI=""
for candidate in \
  "${VERIFY_LOAD_CLAUDE_BIN:-}" \
  "$SCRIPT_DIR/../../../node_modules/.bin/claude" \
  "$(command -v claude 2>/dev/null || true)"; do
  [[ -n "$candidate" && -x "$candidate" ]] && "$candidate" --version >/dev/null 2>&1 && {
    CLI="$candidate"
    break
  }
done

if [[ -z "$CLI" ]]; then
  skip "live probe: a path-scoped rule loads when a matching file is read" \
    "no Claude Code CLI found (set VERIFY_LOAD_CLAUDE_BIN to run this case)"
  skip "live probe: a non-matching rule does NOT load" \
    "no Claude Code CLI found (set VERIFY_LOAD_CLAUDE_BIN to run this case)"
else
  out="$(run --root "$repo" --trigger src/Invoice.cs --claude "$CLI" \
    --expect .claude/rules/csharp.md --expect AGENTS.md --timeout 300)"
  rc=$?

  if [[ "$out" == *"VERDICT	UNKNOWN"* ]]; then
    skip "live probe: a path-scoped rule loads when a matching file is read" \
      "probe could not run: $(printf '%s' "$out" | grep UNKNOWN | head -1)"
    skip "live probe: a non-matching rule does NOT load" "probe could not run"
  else
    assert_eq "a covering rule and the imported AGENTS.md both load (exit 0)" "0" "$rc"
    assert_contains "the covering rule is reported MET" "$out" \
      "$(printf 'EXPECTED\t.claude/rules/csharp.md\tMET')"
    assert_contains "the imported root surface is reported MET" "$out" \
      "$(printf 'EXPECTED\tAGENTS.md\tMET')"
    assert_contains "the load reason is reported" "$out" "path_glob_match"

    if [[ "$out" == *"typescript.md"* ]]; then
      fail "a non-matching rule does NOT load" "no typescript.md in the load set" "$out"
    else
      pass "a non-matching rule does NOT load"
    fi

    out_fail="$(run --root "$repo" --trigger src/Invoice.cs --claude "$CLI" \
      --expect .claude/rules/typescript.md --timeout 300)"
    rc_fail=$?
    if [[ "$out_fail" == *"VERDICT	UNKNOWN"* ]]; then
      skip "an unmet expectation fails" "probe could not run"
    else
      assert_eq "an unmet expectation exits 1" "1" "$rc_fail"
      assert_contains "the unmet surface is reported MISSING" "$out_fail" \
        "$(printf 'EXPECTED\t.claude/rules/typescript.md\tMISSING')"
    fi
  fi
fi

if [[ -n "$CLI" ]]; then
  near="$(build_fixture)"
  mkdir -p "$near/.claude/rules"
  out="$(run --root "$near" --trigger src/Invoice.cs --claude "$CLI" \
    --expect old-rules/csharp.md --timeout 300)"
  if [[ "$out" == *"VERDICT	UNKNOWN"* ]]; then
    skip "a near-miss expectation is MISSING, not MET" "probe could not run"
  else
    assert_contains "a near-miss expectation is MISSING, not MET" "$out" \
      "$(printf 'EXPECTED\told-rules/csharp.md\tMISSING')"
    assert_contains "the real path-component suffix still matches" \
      "$(run --root "$near" --trigger src/Invoice.cs --claude "$CLI" \
        --expect rules/csharp.md --timeout 300)" \
      "$(printf 'EXPECTED\trules/csharp.md\tMET')"
  fi
else
  skip "a near-miss expectation is MISSING, not MET" "no Claude Code CLI found"
fi

dirty="$(git -C "$repo" status --porcelain | wc -l | tr -d ' ')"
assert_eq "the probe leaves the repository under test untouched" "0" "$dirty"

printf '\n%d case(s), %d failure(s), %d skipped\n' "$CASE_NUM" "$FAILED" "$SKIPPED"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
