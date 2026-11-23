#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SUT="python3:$SCRIPT_DIR/check-coverage-complete.py"
SUTS=(
  "bash:$SCRIPT_DIR/check-coverage-complete.sh"
  "$PY_SUT"
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# shellcheck source=../lib/test-helpers.sh
source "$SCRIPT_DIR/../lib/test-helpers.sh"

run_one() {
  local sut_spec="$1" expected="$2" label="$3"
  shift 3
  local runner="${sut_spec%%:*}" path="${sut_spec#*:}"
  local out actual
  out="$("$runner" "$path" "$@" 2>&1)"
  actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    pass "$label [$runner] (exit $actual)"
  else
    fail "$label [$runner] — expected exit $expected, got $actual: $out"
  fi
}

run() {
  local expected="$1" label="$2"
  shift 2
  local sut
  for sut in "${SUTS[@]}"; do
    run_one "$sut" "$expected" "$label" "$@"
  done
}

ledger() {
  local path="$WORK/$1"
  shift
  {
    printf '# Coverage ledger\n\n'
    printf '| # | Corpus item | Depth criterion | Done |\n'
    printf '|---|-------------|-----------------|------|\n'
    printf '%s\n' "$@"
  } >"$path"
  printf '%s' "$path"
}

all_marked="$(ledger all-marked.md \
  '| 1 | alpha | its API reference read end to end | [x] |' \
  '| 2 | beta  | its changelog fetched this turn   | [X] |')"
run 0 "all rows marked passes" "$all_marked"

other_col="$(ledger other-column.md \
  '| 1 | alpha [ ] | criterion mentioning [ ] literally | [x] |')"
run 0 "unmarked box outside the Done column passes" "$other_col"

one_unmarked="$(ledger one-unmarked.md \
  '| 1 | alpha | its API reference read end to end | [x] |' \
  '| 2 | beta  | its changelog fetched this turn   | [ ] |')"
run 1 "one unmarked row fails" "$one_unmarked"

none_marked="$(ledger none-marked.md \
  '| 1 | alpha | criterion | [ ] |' \
  '| 2 | beta  | criterion | [ ] |')"
run 1 "no rows marked fails" "$none_marked"

run 2 "missing file fails closed" "$WORK/does-not-exist.md"
run 2 "no arguments fails closed"

no_table="$WORK/no-table.md"
printf '# Coverage ledger\n\nNothing tabular here.\n' >"$no_table"
run 2 "no table at all fails closed" "$no_table"

no_rows="$WORK/no-rows.md"
{
  printf '| # | Corpus item | Depth criterion | Done |\n'
  printf '|---|-------------|-----------------|------|\n'
} >"$no_rows"
run 2 "header with zero data rows fails closed" "$no_rows"

foreign_table="$WORK/foreign-table.md"
{
  printf '# Notes\n\n'
  printf '| Done | Note |\n'
  printf '|------|------|\n'
  printf '| [x] | status |\n'
} >"$foreign_table"
run 2 "unrelated table with a Done column is not the ledger" "$foreign_table"

foreign_then_real="$WORK/foreign-then-real.md"
{
  printf '| Done | Note |\n'
  printf '|------|------|\n'
  printf '| [x] | status |\n\n'
  printf '| # | Corpus item | Depth criterion | Done |\n'
  printf '|---|-------------|-----------------|------|\n'
  printf '| 1 | alpha | criterion | [x] |\n'
} >"$foreign_then_real"
run 0 "a real ledger after an unrelated table is still graded" "$foreign_then_real"

escaped_pipe="$(ledger escaped-pipe.md \
  '| 1 | the read \| grep \| inferred union | every member documented | [x] |')"
run 0 "escaped pipes inside a cell are content, not delimiters" "$escaped_pipe"

no_hash="$WORK/no-hash-column.md"
{
  printf '| Corpus item | Depth criterion | Done |\n'
  printf '|-------------|-----------------|------|\n'
  printf '| alpha | criterion | [x] |\n'
} >"$no_hash"
run 2 "header missing the # column fails closed" "$no_hash"

dup_header="$WORK/duplicate-header.md"
{
  printf '| # | Corpus item | Depth criterion | Done | Done |\n'
  printf '|---|-------------|-----------------|------|------|\n'
  printf '| 1 | alpha | criterion | [x] | [x] |\n'
} >"$dup_header"
run 2 "duplicated required column fails closed" "$dup_header"

partial_header="$WORK/partial-header.md"
{
  printf '| # | Corpus item | Done |\n'
  printf '|---|-------------|------|\n'
  printf '| 1 | alpha | [x] |\n'
} >"$partial_header"
run 2 "header missing the depth-criterion column fails closed" "$partial_header"

no_done_col="$WORK/no-done-column.md"
{
  printf '| # | Corpus item | Depth criterion |\n'
  printf '|---|-------------|-----------------|\n'
  printf '| 1 | alpha | criterion |\n'
} >"$no_done_col"
run 2 "table without a Done column fails closed" "$no_done_col"

mangled="$(ledger mangled.md \
  '| 1 | alpha | criterion | [x] |' \
  '| 2 | beta | criterion |')"
run 2 "row with too few columns fails closed" "$mangled"

wide="$(ledger too-wide.md \
  '| 1 | alpha | criterion with a stray | pipe | [x] |')"
run 2 "row with too many columns fails closed" "$wide"

no_criterion="$(ledger no-criterion.md '| 1 | alpha |  | [x] |')"
run 2 "marked row with an empty depth criterion fails closed" "$no_criterion"

no_item="$(ledger no-item.md '| 1 |  | criterion | [x] |')"
run 2 "marked row with an empty corpus item fails closed" "$no_item"

unmarked_no_criterion="$(ledger unmarked-no-criterion.md '| 1 | alpha |  | [ ] |')"
run 2 "unmarked row with an empty depth criterion fails closed" "$unmarked_no_criterion"

junk_cell="$(ledger junk-cell.md '| 1 | alpha | criterion | done? |')"
run 2 "Done cell that is neither marked nor unmarked fails closed" "$junk_cell"

empty="$WORK/empty.md"
: >"$empty"
run 2 "empty file fails closed" "$empty"

bad_utf8="$WORK/bad-utf8.md"
{
  printf '| # | Corpus item | Depth criterion | Done |\n'
  printf '|---|-------------|-----------------|------|\n'
  printf '| 1 | '
  printf '\xff'
  printf ' alpha | criterion | [x] |\n'
} >"$bad_utf8"
run_one "$PY_SUT" 2 "non-UTF-8 ledger fails closed as ungradeable" "$bad_utf8"

unreadable="$(ledger unreadable.md '| 1 | alpha | criterion | [x] |')"

sim_out="$(
  PY_TWIN="$SCRIPT_DIR/check-coverage-complete.py" \
    LEDGER="$unreadable" \
    python3 - <<'PY' 2>&1
import contextlib
import errno
import importlib.util
import io
import os
import pathlib
import sys
from unittest.mock import patch

twin = os.environ["PY_TWIN"]
ledger = os.environ["LEDGER"]
spec = importlib.util.spec_from_file_location("check_coverage_complete", twin)
if spec is None or spec.loader is None:
    print("could not load Python twin", file=sys.stderr)
    sys.exit(1)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

target = pathlib.Path(ledger)
with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
    baseline = mod.grade(target)
if baseline != 0:
    print(
        f"fixture is not an otherwise regular complete ledger: grade() returned {baseline}",
        file=sys.stderr,
    )
    sys.exit(1)

err = io.StringIO()
denied = PermissionError(errno.EACCES, os.strerror(errno.EACCES), str(target))
with patch.object(pathlib.Path, "read_text", side_effect=denied):
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
        rc = mod.grade(target)
diag = err.getvalue()
if rc != 2:
    print(f"expected grade() to return 2, got {rc}; stderr={diag!r}", file=sys.stderr)
    sys.exit(1)
if "ledger unreadable" not in diag:
    print(f"expected 'ledger unreadable' in stderr, got {diag!r}", file=sys.stderr)
    sys.exit(1)
PY
)"
sim_rc=$?
if [[ "$sim_rc" -eq 0 ]]; then
  pass "simulated PermissionError on read_text fails closed as ungradeable [python]"
else
  fail "simulated PermissionError on read_text fails closed as ungradeable [python] - ${sim_out}"
fi

chmod 000 "$unreadable" 2>/dev/null
if [[ -r "$unreadable" ]]; then
  echo "SKIP: chmod-000 unreadable-ledger integration check - this platform/user does not enforce chmod 000 on the fixture (simulated PermissionError case above already covered the contract)" >&2
else
  run_one "$PY_SUT" 2 "unreadable ledger fails closed as ungradeable" "$unreadable"
fi
chmod 644 "$unreadable" 2>/dev/null || true

run 0 "--help exits 0" --help
run 2 "unknown flag fails closed" --nope "$all_marked"
run 2 "two ledgers is a usage error" "$all_marked" "$one_unmarked"

for sut in "${SUTS[@]}"; do
  runner="${sut%%:*}"
  path="${sut#*:}"
  out="$("$runner" "$path" "$all_marked" 2>&1)"
  if [[ "$out" == *"rows=2"* && "$out" == *"unmarked=0"* && "$out" == *"status=complete"* ]]; then
    pass "complete ledger prints a greppable summary [$runner]"
  else
    fail "complete ledger summary [$runner] — got: $out"
  fi

  out="$("$runner" "$path" "$one_unmarked" 2>&1)"
  if [[ "$out" == *"rows=2"* && "$out" == *"unmarked=1"* && "$out" == *"status=incomplete"* ]]; then
    pass "incomplete ledger prints a greppable summary [$runner]"
  else
    fail "incomplete ledger summary [$runner] — got: $out"
  fi

  out="$("$runner" "$path" "$none_marked" 2>&1)"
  if [[ "$out" == *"alpha"* && "$out" == *"beta"* ]]; then
    pass "incomplete ledger names the unmarked items [$runner]"
  else
    fail "incomplete ledger should name unmarked items [$runner] — got: $out"
  fi
done

if [[ "$fails" -eq 0 ]]; then
  printf '\nAll checks passed.\n'
  exit 0
fi
printf '\n%d check(s) failed.\n' "$fails" >&2
exit 1
