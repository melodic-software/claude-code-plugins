#!/usr/bin/env bash
# Black-box contract test for comment-tooling-probe.sh.
#
# Proves the probe's two load-bearing promises: it never fails on a missing
# tool (a downgrade is not an error), and every absent layer names the
# capability lost, because a bare "absent" gives the reader nothing to act on.
#
# Self-contained: no external test library. Tool absence is simulated with an
# emptied PATH and a PYTHONPATH pointing at an empty directory, so the test
# exercises the absent branch on a machine where the tools are installed.
set -u

PROBE="$(cd "$(dirname "$0")" && pwd)/comment-tooling-probe.sh"
PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  printf 'PASS: %s\n' "$1"
}
no() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1"
}
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else
  no "$1 (expected '$3', got '$2')"
fi; }

out="$(bash "$PROBE")"
check "exits 0 in the normal case" "$?" "0"

check "emits a header row" "$(printf '%s\n' "$out" | head -1)" "$(printf 'layer\ttool\tstatus\tcost-if-absent')"

check "emits one row per layer" "$(printf '%s\n' "$out" | tail -n +2 | grep -c .)" "5"

for layer in count extract attach commented-out rules; do
  if printf '%s\n' "$out" | awk -F'\t' -v l="$layer" 'NR>1 && $1==l {f=1} END{exit !f}'; then
    ok "reports the $layer layer"
  else
    no "reports the $layer layer"
  fi
done

# Every row is either present, or absent WITH a stated cost. An absent row
# carrying "-" would tell the reader nothing about what to install or why.
if printf '%s\n' "$out" | awk -F'\t' 'NR>1 && $3=="absent" && (length($4)<20 || $4=="-") {bad=1} END{exit bad+0}'; then
  ok "every absent layer states the capability lost"
else
  no "every absent layer states the capability lost"
fi

if printf '%s\n' "$out" | awk -F'\t' 'NR>1 && $3!="present" && $3!="absent" {bad=1} END{exit bad+0}'; then
  ok "status is only ever present or absent"
else
  no "status is only ever present or absent"
fi

json="$(bash "$PROBE" --json)"
check "--json exits 0" "$?" "0"
if printf '%s' "$json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert isinstance(d,list) and len(d)==5, d
assert {r['layer'] for r in d} == {'count','extract','attach','commented-out','rules'}, d
assert all(r['status'] in ('present','absent') for r in d), d
" 2>/dev/null; then
  ok "--json emits valid JSON with all four layers"
else
  no "--json emits valid JSON with all four layers"
fi

# The degradation path: with nothing resolvable, every layer must read absent
# and the probe must still exit 0.
EMPTY="$(mktemp -d)"
trap 'rm -rf "$EMPTY"' EXIT
# BASH must be an absolute path: with PATH emptied, the interpreter itself is
# unresolvable and the run dies at 127 before the probe executes, which would
# leave the assertions below inspecting empty output and passing vacuously.
BASH_ABS="$(command -v bash)"
bare="$(PATH="$EMPTY" PYTHONPATH="$EMPTY" "$BASH_ABS" "$PROBE" 2>/dev/null)"
bare_rc=$?
check "exits 0 with no tools resolvable" "$bare_rc" "0"
check "still emits every layer with no tools resolvable" \
  "$(printf '%s\n' "$bare" | tail -n +2 | grep -c .)" "5"
if printf '%s\n' "$bare" | awk -F'\t' 'NR>1 && $3!="absent" {bad=1} END{exit bad+0}'; then
  ok "reports every layer absent when nothing resolves"
else
  no "reports every layer absent when nothing resolves"
fi

# Determinism: the same environment must produce byte-identical output, or a
# report diffed across runs shows phantom churn.
check "output is deterministic" "$(bash "$PROBE" | md5sum)" "$(bash "$PROBE" | md5sum)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
