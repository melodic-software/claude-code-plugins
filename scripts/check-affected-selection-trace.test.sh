#!/usr/bin/env bash
# test-scope: scripts/check-affected.sh scripts/check-affected-gates.txt
# shellcheck disable=SC2016
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh" || exit 2
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh" || exit 2

tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo/scripts" "$tmp/bin"
git_init_test_repo "$repo" || exit 2
cp "$SELF_DIR/check-affected.sh" "$SELF_DIR/check-affected-gates.txt" "$repo/scripts/"
printf '#!/usr/bin/env bash\nexit 0\n' >"$repo/scripts/setup-env.sh"
printf '#!/usr/bin/env bash\nsleep "${STUB_AFFECTED_SLEEP:-0}"\n' >"$repo/scripts/affected-tests.sh"
cat >"$repo/scripts/selection-audit.sh" <<'STUB'
#!/usr/bin/env bash
cmd="$1"
shift
if [[ "$cmd" == changed ]]; then
  [[ -z "${STUB_CHANGED_SUITES:-}" ]] || printf '%s\n' "$STUB_CHANGED_SUITES"
  exit "${STUB_SELECTION_CHANGED:-0}"
fi
[[ -z "${STUB_TRACE_LOG:-}" ]] || printf '%s\n' "$*" >"$STUB_TRACE_LOG"
sleep "${STUB_TRACE_SLEEP:-0}"
while (($#)); do
  [[ "$1" == --out ]] && out="$2"
  shift
done
mkdir -p "$out"
echo "stub trace report: ${STUB_TRACE_REPORT:-No gap}" >"$out/report.md"
printf '%s' "${STUB_TRACE_SUITES:-}" >"$out/suites.tsv"
printf '%s' "${STUB_TRACE_VERDICTS:-}" >"$out/verdicts.tsv"
exit "${STUB_SELECTION_AUDIT:-0}"
STUB
chmod +x "$repo"/scripts/*.sh
printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/bin/strace"
chmod +x "$tmp/bin/strace"
export PATH="$tmp/bin:$PATH"
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m base
git_test_config "$repo" branch -q base
printf 'data\n' >"$repo/notes.txt"
git_test_config "$repo" add notes.txt
git_test_config "$repo" commit -q -m change

run() {
  local -a envs=()
  while [[ "$1" != -- ]]; do
    envs+=("$1")
    shift
  done
  shift
  RC=0
  OUT="$(cd "$repo" && env ${envs[@]+"${envs[@]}"} bash scripts/check-affected.sh --no-fetch "$@" 2>"$tmp/err")" || RC=$?
  ERR="$(cat "$tmp/err")"
}
check() {
  if eval "$2"; then ok "$1"; else bad "$1" "rc=$RC out=$OUT err=$ERR"; fi
}

run -- --base base --tests
check "selection-trace skips a change that adds or changes no suite" \
  '[[ $RC == 0 && $ERR == *"SKIP selection-trace (no changed suite)"* ]]'
run STUB_CHANGED_SUITES=scripts/a.test.sh -- --base base
check "without --tests there is no selection-trace" \
  '[[ $RC == 0 && $ERR != *"selection-trace"* ]]'

trace_log="$tmp/trace.log"
run STUB_CHANGED_SUITES=$'scripts/a.test.sh\nscripts/b.test.mjs' STUB_TRACE_LOG="$trace_log" -- --base base --tests --budget 45
check "selection-trace passes when the trace finds no gap and checks everything" \
  '[[ $RC == 0 && $ERR != *"selection-trace"* && $OUT == *"passed"* ]]'
check "selection-trace traces each changed suite with one job inside the run's budget" \
  '[[ $(cat "$trace_log") =~ ^--jobs\ 1\ --budget\ (4[0-5])\ --out\ .*\ scripts/a.test.sh\ scripts/b.test.mjs$ ]]'

run STUB_CHANGED_SUITES=scripts/a.test.sh STUB_SELECTION_AUDIT=1 STUB_TRACE_REPORT="1 gap: a.test.sh reads x.yml" -- --base base --tests
check "selection-trace fails on a gap and shows the trace's report" \
  '[[ $RC == 1 && $ERR == *"FAIL selection-trace"* && $ERR == *"1 gap: a.test.sh reads x.yml"* ]]'
run STUB_CHANGED_SUITES=scripts/a.test.sh STUB_TRACE_SUITES=$'scripts/a.test.sh\tnot-traced\t0\t0\n' -- --base base --tests
check "a suite the budget left untraced is a selection-trace SKIP, never a pass" \
  '[[ $RC == 0 && $ERR == *"SKIP selection-trace (could not run, exit 2: 1 suite(s) or file(s) left unchecked past the 120s budget, left to CI)"* ]]'
run STUB_CHANGED_SUITES=scripts/a.test.sh STUB_TRACE_VERDICTS=$'x.yml\tnot checked\n' -- --base base --tests
check "a file the budget left unchecked is a selection-trace SKIP" \
  '[[ $RC == 0 && $ERR == *"SKIP selection-trace (could not run, exit 2: 1 suite(s) or file(s) left unchecked"* ]]'
run STUB_CHANGED_SUITES=scripts/a.test.sh STUB_SELECTION_AUDIT=2 -- --base base --tests
check "a trace that could not run is a selection-trace SKIP" \
  '[[ $RC == 0 && $ERR == *"SKIP selection-trace (could not run, exit 2"* ]]'
run STUB_CHANGED_SUITES=scripts/a.test.sh STUB_SELECTION_CHANGED=2 -- --base base --tests
check "a failed listing is a selection-trace SKIP" \
  '[[ $RC == 0 && $ERR == *"SKIP selection-trace (could not list the changed suites"* ]]'
run STUB_CHANGED_SUITES=scripts/a.test.sh -- --base base --tests --uncommitted
check "--uncommitted skips selection-trace, so a lane's self-check keeps its wall" \
  '[[ $ERR == *"SKIP selection-trace (--uncommitted has no commit here to list the changed suites from)"* ]]'

start=$SECONDS
run STUB_CHANGED_SUITES=scripts/a.test.sh -- --base base --tests
plain=$((SECONDS - start))
start=$SECONDS
run STUB_CHANGED_SUITES=scripts/a.test.sh STUB_TRACE_SLEEP=3 STUB_AFFECTED_SLEEP=3 -- --base base --tests
check "selection-trace runs beside the suites, not after them" \
  "[[ \$RC == 0 && $((SECONDS - start - plain)) -lt 5 ]]"

test_harness::report
