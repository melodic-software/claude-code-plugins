#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
SUT="$SCRIPT_DIR/upstream-drift-vendored-report.sh"
FILER="$SCRIPT_DIR/upstream-drift-issues.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" || exit 2

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh" || exit 2

TMP="$(mktemp -d)" || exit 2
cleanup() { [[ -n "$TMP" && "$TMP" != / ]] && rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/stubs"
stub() {
  local f="$TMP/stubs/$1"
  shift
  printf '%s\n' '#!/usr/bin/env bash' "$@" >"$f"
  chmod +x "$f"
}
stub clean.sh 'echo all clean' 'exit 0'
stub drift.sh 'echo drifted' 'exit 1'
stub unverifiable.sh 'echo offline >&2' 'exit 2'
stub broken.sh 'echo crashed' 'exit 7'
stub hang.sh 'exec sleep 30'
stub commands.sh 'echo "::error::forged by upstream"' 'echo "::stop-commands::abc123"' 'exit 1'
stub token.sh "printf '%s' \"\${GH_TOKEN:-unset}:\${GITHUB_TOKEN:-unset}\" >\"$TMP/token-seen\"" 'exit 0'
stub args.sh "printf '%s|' \"\$@\" >\"$TMP/args-seen\"" 'exit 0'

OUT=""
CODE=0
REPORT=""
BROKEN=""
SUMMARY=""

run_sut() {
  local table="$1" dir
  shift
  dir="$(mktemp -d "$TMP/run.XXXXXX")" || exit 2
  REPORT="$dir/vendored.txt" BROKEN="$dir/broken-contract.txt" SUMMARY="$dir/summary.md"
  : >"$SUMMARY"
  OUT="$(env GITHUB_STEP_SUMMARY="$SUMMARY" GH_TOKEN=secret-a GITHUB_TOKEN=secret-b \
    bash "$SUT" --table "$table" --output "$REPORT" --broken-contract "$BROKEN" "$@" 2>&1)"
  CODE=$?
}

table() {
  local f="$1"
  shift
  printf '%s\n' "$@" >"$f"
}

expect_code() {
  if [[ "$CODE" == "$2" ]]; then pass "$1"; else bad "$1" "exit $CODE, want $2; output: $OUT"; fi
}
expect_has() {
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else bad "$1" "missing '$3' in: $2"; fi
}
expect_lacks() {
  if [[ "$2" != *"$3"* ]]; then pass "$1"; else bad "$1" "unexpected '$3' in: $2"; fi
}
expect_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else bad "$1" "got [$2], want [$3]"; fi
}

S="$TMP/stubs"

table "$TMP/t-basic" \
  "# comment lines and blank lines are skipped" \
  "" \
  "acme/clean|$S/clean.sh|--check" \
  "acme/drift|$S/drift.sh|--check" \
  "plug/skill|$S/unverifiable.sh|"
run_sut "$TMP/t-basic"
expect_code "basic: exit 0 when every row was emitted" 0
expect_eq "basic: one page line per row, pin and head unknown" "$(cat "$REPORT")" \
  "page repo=acme/clean pin=unknown head=unknown status=clean path=$S/clean.sh
page repo=acme/drift pin=unknown head=unknown status=drift path=$S/drift.sh
page repo=plug/skill pin=unknown head=unknown status=untracked path=$S/unverifiable.sh"
expect_has "basic: exit 2 row warns" "$OUT" "::warning title=Drift unverifiable::plug/skill"
expect_lacks "basic: no error annotation" "$OUT" "::error"
expect_lacks "basic: no page line on stdout" "$OUT" "page repo="
expect_eq "basic: broken-contract file empty" "$(cat "$BROKEN")" ""
if [[ -f "$BROKEN" ]]; then pass "basic: broken-contract file written"; else bad "basic: broken-contract file written" "absent"; fi
expect_has "basic: row output in the job summary" "$(cat "$SUMMARY")" "drifted"
expect_has "basic: stderr output in the job summary" "$(cat "$SUMMARY")" "offline"
expect_has "basic: summary names the exit code" "$(cat "$SUMMARY")" "Exit code 1"
expect_lacks "basic: row output never on stdout" "$OUT" "drifted"
expect_lacks "basic: row stderr never on stdout" "$OUT" "offline"

table "$TMP/t-broken" \
  "acme/clean|$S/clean.sh|" \
  "acme/broken|$S/broken.sh|--check" \
  "acme/drift|$S/drift.sh|"
run_sut "$TMP/t-broken"
expect_code "broken: the adapter still finishes with 0" 0
expect_has "broken: row maps to untracked" "$(cat "$REPORT")" \
  "page repo=acme/broken pin=unknown head=unknown status=untracked path=$S/broken.sh"
expect_has "broken: later rows still run" "$(cat "$REPORT")" "repo=acme/drift pin=unknown head=unknown status=drift"
expect_has "broken: error annotation" "$OUT" "::error title=Drift check broke its contract::acme/broken exited 7"
expect_eq "broken: row id in the broken-contract file" "$(cat "$BROKEN")" "acme/broken"

table "$TMP/t-hang" "acme/hang|$S/hang.sh|" "acme/clean|$S/clean.sh|"
start=$SECONDS
run_sut "$TMP/t-hang" --row-timeout 1
elapsed=$((SECONDS - start))
expect_code "hang: exit 0" 0
expect_has "hang: row maps to untracked" "$(cat "$REPORT")" "repo=acme/hang pin=unknown head=unknown status=untracked"
expect_has "hang: next row still runs" "$(cat "$REPORT")" "repo=acme/clean pin=unknown head=unknown status=clean"
expect_has "hang: timeout warning" "$OUT" "::warning title=Drift check timed out::acme/hang"
expect_eq "hang: a timeout is not a broken contract" "$(cat "$BROKEN")" ""
if ((elapsed < 20)); then pass "hang: stopped at the timeout"; else bad "hang: stopped at the timeout" "${elapsed}s"; fi

table "$TMP/t-cmd" "acme/cmd|$S/commands.sh|"
run_sut "$TMP/t-cmd"
expect_code "commands: exit 0" 0
expect_lacks "commands: ::error:: never on the adapter's output" "$OUT" "forged by upstream"
expect_lacks "commands: ::stop-commands:: never on the adapter's output" "$OUT" "stop-commands"
expect_has "commands: kept in the job summary" "$(cat "$SUMMARY")" "::stop-commands::abc123"
expect_eq "commands: report holds only the page line" "$(cat "$REPORT")" \
  "page repo=acme/cmd pin=unknown head=unknown status=drift path=$S/commands.sh"

table "$TMP/t-env" "acme/token|$S/token.sh|" "acme/args|$S/args.sh|--check"
run_sut "$TMP/t-env"
expect_code "env: exit 0" 0
expect_eq "env: no token reaches a row" "$(cat "$TMP/token-seen" 2>/dev/null)" "unset:unset"
expect_eq "env: the table's argument is passed" "$(cat "$TMP/args-seen" 2>/dev/null)" "--check|"
table "$TMP/t-mark" "acme/args|$S/args.sh|--check|files-only"
run_sut "$TMP/t-mark"
expect_code "files-only: exit 0" 0
expect_eq "files-only: the mark never reaches the script's arguments" "$(cat "$TMP/args-seen" 2>/dev/null)" "--check|"

table "$TMP/t-bad" "acme/clean|$S/clean.sh|" "not an id|$S/drift.sh|"
dir="$(mktemp -d "$TMP/stale.XXXXXX")"
printf 'page repo=old/report pin=unknown head=unknown status=clean path=x\n' >"$dir/vendored.txt"
OUT="$(bash "$SUT" --table "$TMP/t-bad" --output "$dir/vendored.txt" --broken-contract "$dir/broken.txt" 2>&1)"
CODE=$?
expect_code "unfinished: exit 2" 2
if [[ ! -e "$dir/vendored.txt" ]]; then pass "unfinished: no output file, a stale one removed"; else bad "unfinished: no output file, a stale one removed" "$(cat "$dir/vendored.txt")"; fi
mkdir -p "$TMP/bin" "$TMP/ghlog"
printf '%s\n' '#!/usr/bin/env bash' "printf '%s\n' \"\$*\" >>\"$TMP/ghlog/calls\"" 'exit 0' >"$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
OUT="$(env PATH="$TMP/bin:$PATH" RUNNER_TEMP='' bash "$FILER" "$dir/vendored.txt" 2>&1)"
CODE=$?
expect_code "unfinished: the filer exits 2 on the absent report" 2
expect_eq "unfinished: the filer made no gh call" "$(cat "$TMP/ghlog/calls" 2>/dev/null)" ""

table "$TMP/t-empty" "# no rows"
run_sut "$TMP/t-empty"
expect_code "empty table: exit 2" 2
if [[ ! -e "$REPORT" ]]; then pass "empty table: no output file"; else bad "empty table: no output file" "present"; fi

run_sut "$TMP/does-not-exist"
expect_code "missing table: exit 2" 2

table "$TMP/t-flag" "acme/x|-rf|"
run_sut "$TMP/t-flag"
expect_code "path starting with a dash: exit 2" 2

OUT="$(bash "$SUT" --list 2>&1)"
CODE=$?
expect_code "--list: exit 0" 0
expect_eq "--list: the seven rows of D6" "$(cut -d' ' -f1 <<<"$OUT")" \
  "playwright/playwright
firecrawl/update
playbooks/boris
playbooks/skill-authoring
Dometrain/mcp
upstash/context7
vojtaholik/good-css"
missing=""
while read -r _ path; do
  [[ -f "$REPO_ROOT/$path" ]] || missing+=" $path"
done <<<"$OUT"
expect_eq "--list: every row's check script exists" "$missing" ""
expect_has "--list: good-css row names its check script" "$OUT" \
  "vojtaholik/good-css plugins/user-interface/scripts/check-good-css-drift.sh"

OUT="$(bash "$SUT" --help 2>&1)"
CODE=$?
expect_code "--help: exit 0" 0
expect_has "--help: prints usage" "$OUT" "usage:"
OUT="$(bash "$SUT" --broken-contract "$TMP/b" 2>&1)"
CODE=$?
expect_code "no --output: exit 2" 2
OUT="$(bash "$SUT" --output "$TMP/o" 2>&1)"
CODE=$?
expect_code "no --broken-contract: exit 2" 2
run_sut "$TMP/t-basic" --row-timeout 0
expect_code "--row-timeout 0: exit 2" 2
run_sut "$TMP/t-basic" --row-timeout abc
expect_code "--row-timeout not a number: exit 2" 2

test_harness::report
