#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GITHUB_ACTIONS

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-git-hook-time-budget.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

gate() { bash "$SCRIPT" --ref-ms 1000 --ref-host-ms 1000 "$@"; }

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
RECORD_PUSH="printf '%s %s\n' \"\$1\" \"\$2\" >'$TMP/REC/args'; cat >'$TMP/REC/stdin'"

r="$TMP/fast"
make_root "$r" "${RECORD_COMMIT//REC/fast/rec}" "${RECORD_PUSH//REC/fast/rec}"
if out="$(gate --root "$r" --force --runs 1 --budget-ms 400 2>&1)"; then
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
if [[ "$(cat "$r/rec/args" 2>/dev/null)" == "origin https://example.invalid/repo.git" ]]; then
  ok "the pre-push entry gets the remote name and URL"
else
  fail "the pre-push entry args were: $(cat "$r/rec/args" 2>/dev/null)"
fi
if [[ "$(cat "$r/rec/stdin" 2>/dev/null)" == "refs/heads/hook-budget-check $(g "$r" rev-parse HEAD) refs/heads/hook-budget-check 0000000000000000000000000000000000000000" ]]; then
  ok "the pre-push entry reads HEAD of the real tree pushed as a new non-default branch"
else
  fail "the pre-push entry stdin lines were: $(cat "$r/rec/stdin" 2>/dev/null)"
fi

r="$TMP/slow"
make_root "$r" 'sleep 0.6' ':'
out="$(gate --root "$r" --force --runs 1 --budget-ms 200 2>&1)"
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

r="$TMP/scaled"
make_root "$r" 'sleep 0.6' ':'
out="$(bash "$SCRIPT" --root "$r" --force --runs 1 --budget-ms 500 --ref-ms 2000 --ref-host-ms 1000 2>&1)"
rc=$?
if [[ $rc -eq 0 && "$out" == *"ratio 2.00; scaled budget 1.000 s"* ]]; then
  ok "a runner twice as slow as the reference host doubles the budget, so 0.6 s passes a 0.5 s budget"
else
  fail "expected ratio 2.00 to scale 0.5 s to 1.000 s and pass (rc $rc): $out"
fi

r="$TMP/slowpush"
make_root "$r" ':' 'sleep 0.6'
out="$(gate --root "$r" --force --runs 1 --budget-ms 500 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"FAIL: pre-push took"*"slowest entry: push-entry"* ]]; then
  ok "a slower pre-push entry fails its scaled budget"
else
  fail "expected the 0.6 s pre-push entry to fail a 0.5 s budget (rc $rc): $out"
fi

r="$TMP/leftci"
make_root "$r" ':' 'echo "changelog-fragments: origin/main is not fetched; fragment checks left to CI." >&2'
rm -r "$r/plugins/absent"
g "$r" commit -q -am "no absent tool"
out="$(env GITHUB_ACTIONS=true bash "$SCRIPT" --ref-ms 1000 --ref-host-ms 1000 --root "$r" --force --runs 1 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"FAIL: push-entry did not run every check on the pushed range"* ]]; then
  ok "in CI a pre-push entry that leaves a check to CI fails the gate"
else
  fail "expected exit 1 for a skipped pre-push check under GITHUB_ACTIONS=true (rc $rc): $out"
fi
out="$(gate --root "$r" --force --runs 1 2>&1)"
rc=$?
if [[ $rc -eq 0 && "$out" == *"WARNING: push-entry did not run every check"* ]]; then
  ok "locally the same skip is a warning"
else
  fail "expected a local warning and exit 0 (rc $rc): $out"
fi

# shellcheck disable=SC2016
WHOLE_TREE='git ls-files | while read -r f; do git hash-object "$f" >/dev/null; done'
r="$TMP/small"
make_root "$r" ':' "$WHOLE_TREE"
small="$(bash "$SCRIPT" --root "$r" --force --runs 1 --budget-ms 600 2>&1)"
small_rc=$?
r="$TMP/big"
make_root "$r" ':' "$WHOLE_TREE"
mkdir -p "$r/plugins/bulk"
for i in $(seq 1 1500); do printf 'file %d\n' "$i" >"$r/plugins/bulk/f$i.txt"; done
g "$r" add -A
g "$r" commit -q -m "a bigger repository"
big="$(bash "$SCRIPT" --root "$r" --force --runs 1 --budget-ms 600 2>&1)"
big_rc=$?
ref_small="$(sed -n 's/^reference workload: \([0-9]*\) ms.*/\1/p' <<<"$small")"
ref_big="$(sed -n 's/^reference workload: \([0-9]*\) ms.*/\1/p' <<<"$big")"
if [[ $small_rc -eq 0 && $big_rc -eq 1 && "$big" == *"FAIL: pre-push took"* ]]; then
  ok "a whole-tree pre-push entry passes on a small repository and fails on one with 1500 more files"
else
  fail "expected small to pass and big to fail (small rc $small_rc, big rc $big_rc): $small // $big"
fi
if [[ -n "$ref_small" && -n "$ref_big" ]] && ((ref_big * 2 > ref_small && ref_small * 2 > ref_big)); then
  ok "the reference stays flat as the repository grows (${ref_small} ms, then ${ref_big} ms)"
else
  fail "the reference should not grow with the repository: ${ref_small:-none} ms, then ${ref_big:-none} ms"
fi

r="$TMP/piped"
make_root "$r" ':' ':'
printf '%s\n' 'pre-commit:' '  jobs:' '    - name: pair' '      group:' '        piped: true' '        jobs:' \
  '          - name: pair-format' '            script: pair-format.sh' '            runner: sh' \
  '          - name: pair-lint' '            script: pair-lint.sh' '            runner: sh' >"$r/plugins/dummy/git-hooks/pair.yml"
printf '%s\n' 'echo formatted >>src/one.sh && git add src/one.sh' >"$r/.lefthook/pre-commit/pair-format.sh"
printf '%s\n' 'grep -q formatted src/one.sh || sleep 1' >"$r/.lefthook/pre-commit/pair-lint.sh"
g "$r" add -A
g "$r" commit -q -m "a piped pair"
out="$(gate --root "$r" --force --runs 1 --budget-ms 500 2>&1)"
rc=$?
if [[ $rc -eq 0 && "$out" == *"group pair (piped):"*"pair-format"*"pair-lint"*"group pair total"* ]]; then
  ok "a piped group runs its members in order on one staged state, so the lint that reuses the format's work stays fast"
else
  fail "expected the piped pair to pass a 0.5 s budget with its lint after its format (rc $rc): $out"
fi

r="$TMP/ci"
make_root "$r" ':' ':'
out="$(env GITHUB_ACTIONS=true bash "$SCRIPT" --ref-ms 1000 --ref-host-ms 1000 --root "$r" --force --runs 1 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"skip-entry"*"FAIL: no-such-tool is not installed on this runner"* ]]; then
  ok "in CI an entry whose tool is missing fails the gate with the tool's name"
else
  fail "expected exit 1 naming no-such-tool under GITHUB_ACTIONS=true (rc $rc): $out"
fi

r="$TMP/runnerless"
make_root "$r" ':' ':'
printf '%s\n' 'pre-commit:' '  jobs:' '    - name: runnerless-entry' '      run: sleep 1' >"$r/plugins/dummy/git-hooks/extra.yml"
g "$r" add -A
g "$r" commit -q -m runnerless
out="$(gate --root "$r" --force --runs 1 --budget-ms 500 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"FAIL: pre-commit took"*"slowest entry: runnerless-entry"* ]]; then
  ok "a runner-less run: entry is timed, so a 1 s sleep fails a 0.5 s budget"
else
  fail "expected the runner-less sleep 1 to fail the 0.5 s budget (rc $rc): $out"
fi

r="$TMP/nostart"
make_root "$r" ':' ':'
rm "$r/.lefthook/pre-commit/commit-entry.sh"
g "$r" commit -q -am "drop the entry script"
out="$(gate --root "$r" --force --runs 1 2>&1)"
rc=$?
if [[ $rc -eq 1 && "$out" == *"FAIL: commit-entry could not start"* ]]; then
  ok "an entry whose script is missing fails the gate instead of passing silently"
else
  fail "expected exit 1 naming commit-entry as unable to start (rc $rc): $out"
fi

r="$TMP/scoped"
make_root "$r" "touch '$TMP/scoped/rec/ran'" ':'
printf 'more\n' >>"$r/README.md"
g "$r" commit -q -am docs
out="$(gate --root "$r" --base HEAD~1 2>&1)"
rc=$?
if [[ $rc -eq 0 && "$out" == *"not applicable"* && ! -e "$r/rec/ran" ]]; then
  ok "a change outside the hook surface is not applicable and runs no entry"
else
  fail "expected not applicable with no entry run (rc $rc): $out"
fi
printf '# touched\n' >>"$r/lefthook.yml"
g "$r" commit -q -am hooks
out="$(gate --root "$r" --base HEAD~1 --runs 1 2>&1)"
rc=$?
if [[ $rc -eq 0 && "$out" == *"lefthook.yml changed"* && -e "$r/rec/ran" ]]; then
  ok "a change to lefthook.yml times the entries"
else
  fail "expected the entries to run after a lefthook.yml change (rc $rc): $out"
fi
out="$(gate --root "$r" --base HEAD~1 --scope-only 2>/dev/null)"
if [[ "$out" == applies=true ]]; then
  ok "--scope-only prints only applies=true when the change touches a hook config"
else
  fail "--scope-only should print applies=true after a lefthook.yml change, got: $out"
fi
out="$(gate --root "$r" --base HEAD --scope-only 2>/dev/null)"
if [[ "$out" == applies=false ]]; then
  ok "--scope-only prints only applies=false when the change touches no hook surface"
else
  fail "--scope-only should print applies=false on an empty change, got: $out"
fi
mkdir -p "$r/plugins/new/.claude-plugin"
echo '{"name": "new"}' >"$r/plugins/new/.claude-plugin/plugin.json"
g "$r" add -A
g "$r" commit -q -m "add a plugin"
out="$(gate --root "$r" --base HEAD~1 --scope-only 2>/dev/null)"
if [[ "$out" == applies=true ]]; then
  ok "adding a plugin makes the gate apply, so growth is timed without a hook change"
else
  fail "--scope-only should print applies=true after a plugin.json is added, got: $out"
fi
echo '{"name": "new", "version": "1"}' >"$r/plugins/new/.claude-plugin/plugin.json"
g "$r" commit -q -am "edit a plugin"
out="$(gate --root "$r" --base HEAD~1 --scope-only 2>/dev/null)"
if [[ "$out" == applies=false ]]; then
  ok "editing an existing plugin.json does not make the gate apply"
else
  fail "--scope-only should print applies=false for a plugin.json edit, got: $out"
fi

r="$TMP/runscope"
make_root "$r" ':' ':'
mkdir -p "$r/scripts/lib"
printf '%s\n' 'pre-push:' '  jobs:' '    - name: local-push' '      run: scripts/pp.sh {1}' >>"$r/lefthook.yml"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'SCRIPT_DIR="$(dirname "$0")"' '. "$SCRIPT_DIR/lib/helper.sh"' 'gate="$SCRIPT_DIR/check-x.sh"' '"$gate"' '# see scripts/other.sh' 'echo "run scripts/other.sh" >&2' 'true # scripts/other.sh' >"$r/scripts/pp.sh"
printf '%s\n' 'helper() { :; }' >"$r/scripts/lib/helper.sh"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$r/scripts/check-x.sh"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$r/scripts/other.sh"
g "$r" add -A
g "$r" commit -q -m "a local pre-push run entry"
printf '%s\n' 'exit 0' >>"$r/scripts/check-x.sh"
g "$r" commit -q -am "touch only the script the entry calls"
out="$(gate --root "$r" --base HEAD~1 --scope-only 2>/dev/null)"
if [[ "$out" == applies=true ]]; then
  ok "a change to a script a lefthook.yml run: entry calls makes the gate apply"
else
  fail "--scope-only should print applies=true after scripts/check-x.sh changed, got: $out"
fi
printf '%s\n' 'helper2() { :; }' >>"$r/scripts/lib/helper.sh"
g "$r" commit -q -am "touch only the file the entry sources"
out="$(gate --root "$r" --base HEAD~1 --scope-only 2>/dev/null)"
if [[ "$out" == applies=true ]]; then
  ok "a change to a file a lefthook.yml run: entry sources makes the gate apply"
else
  fail "--scope-only should print applies=true after scripts/lib/helper.sh changed, got: $out"
fi
printf '%s\n' 'exit 0' >>"$r/scripts/other.sh"
g "$r" commit -q -am "touch an unrelated script"
out="$(gate --root "$r" --base HEAD~1 --scope-only 2>/dev/null)"
if [[ "$out" == applies=false ]]; then
  ok "a change to a script no entry reaches leaves the gate not applicable"
else
  fail "--scope-only should print applies=false after scripts/other.sh changed, got: $out"
fi

test_harness::report
