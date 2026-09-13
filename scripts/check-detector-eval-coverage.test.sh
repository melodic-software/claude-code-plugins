#!/usr/bin/env bash
# Unit tests for check-detector-eval-coverage.sh.
#
#   bash scripts/check-detector-eval-coverage.test.sh
#
# Every scenario builds a throwaway detector and eval suite and points the gate
# at them through DETECTOR_EVAL_COVERAGE_PAIRS, so no assertion here depends on
# the state of the real audit-permission-grants surfaces -- which are being
# backfilled in the same change set this gate landed in, and would otherwise
# make this suite red for someone else's in-flight work.
#
# The negative cases are the synthetic proof the gate catches each direction:
# an emitted id no case names, and a case naming an id the detector cannot
# emit. The second is the one that matters most, because it is the shape
# claude-code-plugins#4149 found already merged (an eval asserting a scope two
# checks out of date) and the shape a coverage-only check reads as green.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-detector-eval-coverage.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
root=""

ID_RE='P[0-9]+[a-z]?'

# mk_tree — a fixture carrying a copy of the gate plus an empty surfaces/ dir.
mk_tree() {
  fixture_tree::build root --sut "$SCRIPT" --label detector-eval-coverage || return 1
  mkdir -p "$root/surfaces"
}

# mk_detector <name> <emit-line>... — a shell script whose emit call sites are
# the gate's input. The emitter body is present so the fixture reads like a real
# detector rather than a list of needles.
mk_detector() {
  local name="$1"
  shift
  {
    printf '#!/usr/bin/env bash\n'
    printf 'emit() { return 0; }\n'
    local line
    for line in "$@"; do printf '%s\n' "$line"; done
  } >"$root/surfaces/$name"
}

# mk_evals <name> <json> — written verbatim so a malformed-JSON case can be
# spelled as malformed JSON.
mk_evals() {
  printf '%s' "$2" >"$root/surfaces/$1"
}

# evals_json <string>... — a minimally shaped suite whose expectations carry the
# given prose. Matches the real schema (skill_name + evals[]) closely enough
# that the gate is exercised through `.. | strings`, not a flat blob.
evals_json() {
  local out='{ "skill_name": "fixture", "evals": [' first=1 s
  for s in "$@"; do
    [[ $first -eq 1 ]] || out+=','
    first=0
    out+=$(printf '{ "id": 1, "name": "case", "prompt": "p", "expected_output": "%s", "expectations": ["%s"] }' "$s" "$s")
  done
  out+='] }'
  printf '%s' "$out"
}

# run_gate <pairs> [argv...] — runs the fixture's copy from the fixture root
# with the two streams kept apart. Sets RC / OUT / ERR.
RC=0
OUT=""
ERR=""
run_gate() {
  local pairs="$1"
  shift
  local outf errf
  outf="$(mktemp)"
  errf="$(mktemp)"
  (cd "$root" && DETECTOR_EVAL_COVERAGE_PAIRS="$pairs" bash scripts/check-detector-eval-coverage.sh "$@") >"$outf" 2>"$errf"
  RC=$?
  OUT="$(cat "$outf")"
  ERR="$(cat "$errf")"
  rm -f "$outf" "$errf"
}

pair() { printf 'surfaces/%s|surfaces/%s|%s' "$1" "$2" "$ID_RE"; }

# ============================== full coverage ==============================

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P2 SRC "message"' 'emit error P4 SRC "message"'
mk_evals evals.json "$(evals_json 'classifies P1 and P2 findings' 'reports P4 inert-token findings')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && "$OUT" == *"passed"* && "$OUT" == *"3 emitted id(s)"* && -z "$ERR" ]]; then
  ok "full coverage passes --check and states its denominator on stdout"
else
  fail "full coverage: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ===================== emitted id with no eval case ========================

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P4 SRC "message"'
mk_evals evals.json "$(evals_json 'classifies P1 findings')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P4"* && "$OUT" != *"P4"* ]]; then
  ok "an emitted id no eval case names fails --check (finding on stderr, not stdout)"
else
  fail "uncovered emitted id not caught: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ================= eval names an id the detector cannot emit ===============
# The #4149 shape: the suite asserts a scope the detector outgrew.

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'audits only the question it owns (P1/P2/P3)')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNEMITTABLE CHECK ID: P2"* && "$ERR" == *"UNEMITTABLE CHECK ID: P3"* ]]; then
  ok "an eval naming an id the detector cannot emit fails --check (the stale-scope shape)"
else
  fail "unemittable eval id not caught: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ========================= inputs the gate cannot see =======================

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"'
run_gate "$(pair det.sh missing.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"eval suite not readable"* && -z "$OUT" ]]; then
  ok "a missing eval suite exits 2, not a pass"
else
  fail "missing evals: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_evals evals.json "$(evals_json 'names P1')"
run_gate "$(pair missing.sh evals.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"detector not readable"* && -z "$OUT" ]]; then
  ok "a missing detector exits 2, not a pass"
else
  fail "missing detector: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# MALFORMED evals.json: a suite that does not parse is not an answer. Spelled so
# that a grep-based reader would happily find P1 and P2 in it and report a clean
# run over a file no eval runner can load.
mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P2 SRC "message"'
mk_evals evals.json '{ "skill_name": "fixture", "evals": [ { "expected_output": "P1 and P2", } '
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"not valid JSON"* && -z "$OUT" ]]; then
  ok "a malformed evals.json exits 2 rather than passing on its readable text"
else
  fail "malformed evals not caught: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# EXTRACTION BROKEN: the detector no longer spells any id the row's pattern
# matches. Zero emitted ids means the gate cannot see its input, never that the
# suite is complete.
mk_tree
mk_detector det.sh 'emit warning RULE-1 SRC "message"'
mk_evals evals.json "$(evals_json 'names nothing in particular')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"no check ids extracted"* && -z "$OUT" ]]; then
  ok "a detector emitting no id under the row pattern exits 2 (extraction, not coverage)"
else
  fail "empty extraction not caught: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# MALFORMED REGISTRY ROW: a row missing its id pattern cannot be compared.
mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'names P1')"
run_gate 'surfaces/det.sh|surfaces/evals.json' --check
if [[ $RC -eq 2 && "$ERR" == *"malformed registry row"* && -z "$OUT" ]]; then
  ok "a registry row without an id pattern exits 2"
else
  fail "malformed row not caught: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# NO ROWS AT ALL: a run that inspected nothing is not a clean run.
mk_tree
run_gate ' ' --check
if [[ $RC -eq 2 && "$ERR" == *"nothing this run could have inspected"* && -z "$OUT" ]]; then
  ok "an empty registry exits 2 rather than reporting a vacuous pass"
else
  fail "empty registry not caught: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# PREREQUISITE REMOVED: jq gone is an environment answer, before any stdout.
mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'names P1')"
mirror="$(mktemp -d)"
while IFS= read -r d; do
  [[ -d "$d" ]] || continue
  for exe in "$d"/*; do
    [[ -f "$exe" && -x "$exe" ]] || continue
    [[ "$(basename "$exe")" == "jq" ]] && continue
    [[ -e "$mirror/$(basename "$exe")" ]] || ln -s "$exe" "$mirror/$(basename "$exe")"
  done
done < <(printf '%s\n' "${PATH//:/$'\n'}")
outf="$(mktemp)"
errf="$(mktemp)"
(cd "$root" && PATH="$mirror" DETECTOR_EVAL_COVERAGE_PAIRS="$(pair det.sh evals.json)" bash scripts/check-detector-eval-coverage.sh --check) >"$outf" 2>"$errf"
RC=$?
OUT="$(cat "$outf")"
ERR="$(cat "$errf")"
rm -f "$outf" "$errf"
rm -rf "$mirror"
if [[ $RC -eq 2 && "$ERR" == *"jq not found"* && -z "$OUT" ]]; then
  ok "a missing jq exits 2 with a diagnostic on stderr and nothing on stdout"
else
  fail "missing jq not handled: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ============================ extraction precision =========================

# A COMMENTED emit call site is prose about the detector, not a call site. A
# gate that counted it would invent a permanent uncoverable gap.
mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' '# emit error P9 SRC "someday"'
mk_evals evals.json "$(evals_json 'names P1')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && "$ERR" != *"P9"* ]]; then
  ok "a commented-out emit call site is not counted as emitted"
else
  fail "commented emit counted: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# WORD BOUNDARIES: eval prose containing PLAN1 or xP4 names neither P1-in-PLAN1
# nor P4, so neither may register as an eval-named id. (P4x is deliberately NOT
# in this fixture: under the row's own pattern that string IS a well-formed id,
# and reading it as one is correct.)
mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'names P1 but also mentions PLAN1 and xP4 in passing')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && "$ERR" != *"UNEMITTABLE"* ]]; then
  ok "substring hits (PLAN1, xP4) are not read as eval-named ids"
else
  fail "word boundaries leaked: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ================================ discover =================================

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P4 SRC "message"'
mk_evals evals.json "$(evals_json 'names P1 and P7')"
run_gate "$(pair det.sh evals.json)"
if [[ $RC -eq 0 && "$OUT" == *"COVERED    P1"* && "$OUT" == *"UNCOVERED  P4"* && "$OUT" == *"UNEMITTABLE P7"* ]]; then
  ok "discover prints per-id status in both directions and exits 0"
else
  fail "discover report wrong: rc=$RC out='$OUT' err='$ERR'"
fi
if [[ "$OUT" == *"1 pair(s), 2 emitted id(s), 2 eval-named id(s)"* ]]; then
  ok "discover reports a coverage denominator (pairs, emitted, eval-named)"
else
  fail "discover denominator missing: out='$OUT'"
fi
rm -rf "$root"

# ============================= multiple pairs ==============================
# The registry is a list, so the denominator must sum and a gap in the SECOND
# row must still fail.

mk_tree
mk_detector a.sh 'emit warning P1 SRC "message"'
mk_evals a.json "$(evals_json 'names P1')"
mk_detector b.sh 'emit error P2 SRC "message"' 'emit error P4 SRC "message"'
mk_evals b.json "$(evals_json 'names P2')"
run_gate "$(pair a.sh a.json)"$'\n'"$(pair b.sh b.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P4"* && "$ERR" == *"2 pair(s), 3 emitted id(s), 2 eval-named id(s)"* ]]; then
  ok "a gap in the second registered pair fails, and the denominator sums both rows"
else
  fail "multi-pair handling wrong: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ================================= usage ===================================

mk_tree
run_gate "$(pair det.sh evals.json)" --bogus
if [[ $RC -eq 2 && "$ERR" == *"usage:"* && -z "$OUT" ]]; then
  ok "an unrecognized mode exits 2 with usage on stderr"
else
  fail "usage handling wrong: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ====================== the built-in registry resolves =====================
# The shipped rows are paths into this repository, and a renamed or moved
# surface must not sit undetected behind an env override every test uses. This
# asserts only that the rows RESOLVE (exit 0 or 1), never what they report:
# the coverage verdict belongs to the tree, and asserting it here would make
# this suite red for a backfill in flight.
out="$(cd "$SELF_DIR/.." && bash scripts/check-detector-eval-coverage.sh --check 2>&1)"
rc=$?
if [[ $rc -eq 0 || $rc -eq 1 ]]; then
  ok "the built-in registry rows resolve against this tree (exit $rc, not an environment answer)"
else
  fail "built-in registry does not resolve: rc=$rc out='$out'"
fi

test_harness::report
