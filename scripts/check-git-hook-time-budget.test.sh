#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-git-hook-time-budget.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

g() { git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "${@:2}"; }

make_root() {
  local r=$1 cfg=plugins/dummy/git-hooks
  mkdir -p "$r/$cfg" "$r/plugins/absent/git-hooks" "$r/.lefthook/pre-commit" "$r/.lefthook/pre-push" "$r/rec"
  printf '%s\n' 'skip_lfs: true' >"$r/lefthook.yml"
  printf '%s\n' 'pre-commit:' '  jobs:' '    - name: commit-entry' '      script: commit-entry.sh' '      runner: sh' \
    'pre-push:' '  jobs:' '    - name: push-entry' '      script: push-entry.sh' '      runner: sh' '      use_stdin: true' >"$r/$cfg/lefthook-remote.yml"
  printf '%s\n' 'pre-commit:' '  jobs:' '    - name: skip-entry' '      script: skip-entry.sh' '      runner: sh' >"$r/plugins/absent/git-hooks/lefthook-remote.yml"
  printf '%s\n' '{"entries": [{"name": "skip", "event": "pre-commit", "tools": ["no-such-tool"]}]}' >"$r/plugins/absent/git-hooks/entries.json"
  printf '%s\n' "$2" >"$r/.lefthook/pre-commit/commit-entry.sh"
  printf '%s\n' "$3" >"$r/.lefthook/pre-push/push-entry.sh"
  # shellcheck disable=SC2016
  printf '%s\n' 'case ",$(git config --get checks.skipmissing)," in' \
    '*,no-such-tool,*) echo "SKIPPED: no-such-tool (missing)" >&2 && exit 0 ;;' 'esac' 'sleep 0.6' >"$r/.lefthook/pre-commit/skip-entry.sh"
  echo rec >"$r/.gitignore"
  printf 'root\n' >"$r/README.md"
  g "$r" init -q -b main && g "$r" add -A && g "$r" commit -q -m base
}

RECORD_COMMIT="git diff --cached --name-only | wc -l | tr -d ' ' >'$TMP/REC/staged'"
RECORD_PUSH="printf '%s %s\n' \"\$1\" \"\$2\" >'$TMP/REC/args'; wc -l | tr -d ' ' >'$TMP/REC/stdin'"

r="$TMP/fast"
make_root "$r" "${RECORD_COMMIT//REC/fast/rec}" "${RECORD_PUSH//REC/fast/rec}"
if out="$(bash "$SCRIPT" --root "$r" --force --runs 1 --budget-ms 400 2>&1)"; then
  ok "fast entries pass, with the entry whose tool is missing left out of the total"
else
  fail "fast entries should pass: $out"
fi
if [[ "$out" == *commit-entry*push-entry*"every hook is within its budget"* ]]; then
  ok "the report names each entry"
else
  fail "the report should name each entry: $out"
fi
if [[ "$out" == *"skip-entry"*"skipped: no-such-tool is not installed"* ]]; then
  ok "an entry whose tool is missing is reported as skipped with the tool"
else
  fail "the skipped entry should be named with its tool: $out"
fi
if [[ "$(cat "$r/rec/staged" 2>/dev/null)" == 10 ]]; then
  ok "the pre-commit entry sees a 10-file staged change"
else
  fail "the pre-commit entry should see 10 staged files, saw: $(cat "$r/rec/staged" 2>/dev/null)"
fi
if [[ "$(cat "$r/rec/args" 2>/dev/null)" == "origin https://example.invalid/fixture.git" ]]; then
  ok "the pre-push entry gets the remote name and URL"
else
  fail "the pre-push entry args were: $(cat "$r/rec/args" 2>/dev/null)"
fi
if [[ "$(cat "$r/rec/stdin" 2>/dev/null)" == 1 ]]; then
  ok "the pre-push entry reads one pushed ref on stdin"
else
  fail "the pre-push entry stdin lines were: $(cat "$r/rec/stdin" 2>/dev/null)"
fi

r="$TMP/slow"
make_root "$r" 'sleep 0.6' ':'
out="$(bash "$SCRIPT" --root "$r" --force --runs 1 --budget-ms 200 2>&1)"
rc=$?
if ((rc == 1)); then
  ok "an over-budget hook exits 1"
else
  fail "an over-budget hook should exit 1, got $rc: $out"
fi
if [[ "$out" == *"FAIL: pre-commit took"*"slowest entry: commit-entry"* ]]; then
  ok "the failure names the hook and its slowest entry"
else
  fail "the failure should name pre-commit and commit-entry: $out"
fi
if [[ "$out" != *"FAIL: pre-push"* ]]; then
  ok "the hook within budget does not fail"
else
  fail "pre-push should stay within budget: $out"
fi

r="$TMP/scoped"
make_root "$r" "touch '$TMP/scoped/rec/ran'" ':'
printf 'more\n' >>"$r/README.md"
g "$r" commit -q -am docs
out="$(bash "$SCRIPT" --root "$r" --base HEAD~1 2>&1)"
rc=$?
if [[ $rc -eq 0 && "$out" == *"not applicable"* && ! -e "$r/rec/ran" ]]; then
  ok "a change outside the hook surface is not applicable and runs no entry"
else
  fail "expected not applicable with no entry run (rc $rc): $out"
fi
printf '# touched\n' >>"$r/lefthook.yml"
g "$r" commit -q -am hooks
out="$(bash "$SCRIPT" --root "$r" --base HEAD~1 --runs 1 2>&1)"
rc=$?
if [[ $rc -eq 0 && "$out" == *"lefthook.yml changed"* && -e "$r/rec/ran" ]]; then
  ok "a change to lefthook.yml times the entries"
else
  fail "expected the entries to run after a lefthook.yml change (rc $rc): $out"
fi

test_harness::report
