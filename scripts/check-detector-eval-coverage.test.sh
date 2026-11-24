#!/usr/bin/env bash
# Unit tests for check-detector-eval-coverage.sh.
#
#   bash scripts/check-detector-eval-coverage.test.sh
#
# Every scenario builds a throwaway detector and eval suite and points the gate
# at them through DETECTOR_EVAL_COVERAGE_PAIRS, so no assertion here depends on
# the state of the real audit-permission-grants surfaces.
#
# The negative cases are the synthetic proof the gate catches each direction:
# an emitted id no case covers, and a case naming an id the detector cannot
# emit. The second is the one that matters most: an eval asserting a scope that
# is out of date is the shape a coverage-only check reads as green.
#
# THE N BLOCKS. Sections marked N1 and N2 guard against over-correcting in both
# of the directions a coverage check can: the negation screen reading ordinary
# covering prose as a disclaimer and FAILING a correct suite, and the emit-site
# accounting calling ordinary shell (quoted arguments, a line-continued call, a
# wrapper definition, an `emit`-prefixed variable) a partial extraction loss and
# exiting 2 on a well-formed detector.
#
# THE P BLOCKS. Sections marked P1..P6 below guard against verifying MENTION
# rather than coverage, losing emit call sites silently, counting the gate's own
# prose as call sites, having no stopping rule for an unregistered pair,
# streaming a partial discover report before an exit 2, and ignoring trailing
# argv.
#
# The "what the walk resolves, excludes and refuses" block pins the jq walk one
# rule per case: a shape it must resolve, an exclusion it must keep, and a shape
# it must refuse by naming the site.
#
# P7 guards the stopping rule's extractor: a greedy `.*` keeps only the LAST id
# on a line, so a detector spelling two emits as
# `emit warning Q1 ...; emit error Q2 ...` never reaches the two-distinct-ids bar
# and is silently unenforced. Its first case is that defect; the two beside it
# are preservation guards that keep the wider extraction from being bought with
# a false positive or a lowered threshold.
# shellcheck disable=SC2016  # fixture bodies are literal detector source in single quotes; expansion would destroy the shape under test
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

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

mk_tree() {
  fixture_tree::build root --sut "$SCRIPT" --label detector-eval-coverage || return 1
  mkdir -p "$root/surfaces"
}

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

mk_evals() {
  printf '%s' "$2" >"$root/surfaces/$1"
}

evals_json() {
  local out='{ "skill_name": "fixture", "evals": [' first=1 s
  for s in "$@"; do
    [[ $first -eq 1 ]] || out+=','
    first=0
    out+=$(printf '{ "id": 1, "name": "case", "prompt": "p", "expected_output": "%s", "files": [], "expectations": ["%s"] }' "$s" "$s")
  done
  out+='] }'
  printf '%s' "$out"
}

RC=0
OUT=""
ERR=""
run_gate() {
  local pairs="$1"
  shift
  local outf errf
  outf="$(mktemp "$TMP_ROOT/f.XXXXXX")"
  errf="$(mktemp "$TMP_ROOT/f.XXXXXX")"
  (cd "$root" && DETECTOR_EVAL_COVERAGE_PAIRS="$pairs" bash scripts/check-detector-eval-coverage.sh "$@") >"$outf" 2>"$errf"
  RC=$?
  OUT="$(cat "$outf")"
  ERR="$(cat "$errf")"
  rm -f "$outf" "$errf"
}

pair() { printf 'surfaces/%s|surfaces/%s|%s' "$1" "$2" "$ID_RE"; }

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

mk_tree
mk_detector det.sh 'emit warning RULE-1 SRC "message"'
mk_evals evals.json "$(evals_json 'names nothing in particular')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"resolved to a check id"* && -z "$OUT" ]]; then
  ok "a detector emitting no id under the row pattern exits 2 (extraction, not coverage)"
else
  fail "empty extraction not caught: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'report warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'names nothing in particular')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"no check ids extracted"* && -z "$OUT" ]]; then
  ok "a detector with no emit call sites at all exits 2 (the zero-ids guard)"
else
  fail "zero-candidate extraction not caught: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

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

mk_tree
run_gate ' ' --check
if [[ $RC -eq 2 && "$ERR" == *"nothing this run could have inspected"* && -z "$OUT" ]]; then
  ok "an empty registry exits 2 rather than reporting a vacuous pass"
else
  fail "empty registry not caught: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# path_without <tool> — sets NO_TOOL_PATH to PATH with <tool> gone. Entries
# without it pass through; each entry that holds it is replaced in place by a
# dir of native symlinks to its other files (Git Bash's default `ln -s` copies).
NO_TOOL_PATH=""
path_without() {
  local tool="$1" d exe mirror
  local -a kept=()
  while IFS= read -r d; do
    if [[ ! -e "$d/$tool" && ! -e "$d/$tool.exe" ]]; then
      kept+=("$d")
      continue
    fi
    mirror="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
    for exe in "$d"/*; do
      [[ -f "$exe" && "${exe##*/}" != "$tool" && "${exe##*/}" != "$tool.exe" ]] || continue
      MSYS=winsymlinks:nativestrict ln -s "$exe" "$mirror/"
    done
    kept+=("$mirror")
  done < <(printf '%s\n' "${PATH//:/$'\n'}")
  NO_TOOL_PATH="$(IFS=':' && printf '%s' "${kept[*]}")"
}

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'names P1')"
path_without jq
outf="$(mktemp "$TMP_ROOT/f.XXXXXX")"
errf="$(mktemp "$TMP_ROOT/f.XXXXXX")"
(cd "$root" && PATH="$NO_TOOL_PATH" DETECTOR_EVAL_COVERAGE_PAIRS="$(pair det.sh evals.json)" bash scripts/check-detector-eval-coverage.sh --check) >"$outf" 2>"$errf"
RC=$?
OUT="$(cat "$outf")"
ERR="$(cat "$errf")"
rm -f "$outf" "$errf"
if [[ $RC -eq 2 && "$ERR" == *"jq not found"* && -z "$OUT" ]]; then
  ok "a missing jq exits 2 with a diagnostic on stderr and nothing on stdout"
else
  fail "missing jq not handled: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'names P1')"
path_without shfmt
outf="$(mktemp "$TMP_ROOT/f.XXXXXX")"
errf="$(mktemp "$TMP_ROOT/f.XXXXXX")"
(cd "$root" && PATH="$NO_TOOL_PATH" DETECTOR_EVAL_COVERAGE_PAIRS="$(pair det.sh evals.json)" bash scripts/check-detector-eval-coverage.sh --check) >"$outf" 2>"$errf"
RC=$?
OUT="$(cat "$outf")"
ERR="$(cat "$errf")"
rm -f "$outf" "$errf"
if [[ $RC -eq 2 && "$ERR" == *"shfmt not found"* && -z "$OUT" ]]; then
  ok "a missing shfmt exits 2 with a diagnostic on stderr and nothing on stdout"
else
  fail "missing shfmt not handled: rc=$RC out='$OUT' err='$ERR'"
fi

# An shfmt below the v3.13.0 floor drops call sites silently, so it must stop
# the gate the same way a missing one does.
stub="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
printf '#!/usr/bin/env bash\necho v3.12.0\n' >"$stub/shfmt"
chmod +x "$stub/shfmt"
outf="$(mktemp "$TMP_ROOT/f.XXXXXX")"
errf="$(mktemp "$TMP_ROOT/f.XXXXXX")"
(cd "$root" && PATH="$stub:$PATH" DETECTOR_EVAL_COVERAGE_PAIRS="$(pair det.sh evals.json)" bash scripts/check-detector-eval-coverage.sh --check) >"$outf" 2>"$errf"
RC=$?
OUT="$(cat "$outf")"
ERR="$(cat "$errf")"
rm -f "$outf" "$errf"
rm -rf "$stub"
if [[ $RC -eq 2 && "$ERR" == *"v3.12.0 is older than v3.13.0"* && -z "$OUT" ]]; then
  ok "an shfmt below the v3.13.0 floor exits 2 with a diagnostic on stderr and nothing on stdout"
else
  fail "old shfmt not refused: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

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

# ======= P1: coverage means an eval case, in a coverage-bearing field ======
# Each case below covers nothing, and passes at rc 0 if an id counts as covered
# whenever the string appears ANYWHERE in the file.
mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P4 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification' 'deliberately does NOT exercise P4')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && "$OUT" == *"DISCLAIMED CHECK ID: P4"* && "$OUT" != *"DISCLAIMED CHECK ID: P1"* && -z "$ERR" ]]; then
  ok "P1: an id named only inside a negative assertion is a DISCLAIMED advisory, not a finding"
else
  fail "P1 negative assertion not reported as an advisory: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification' 'deliberately does NOT exercise P9')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNEMITTABLE CHECK ID: P9"* ]]; then
  ok "P1: a negatively-named id still has to be emittable (the screen is one-directional)"
else
  fail "P1 negated id escaped the reverse direction: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P4 SRC "message"'
mk_evals evals.json '{ "skill_name": "fixture", "evals": [ { "id": 1, "name": "case", "prompt": "p", "expected_output": "exercises P1 classification", "files": ["~/w/P4/settings.json"], "expectations": ["exercises P1 classification"] } ] }'
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P4"* ]]; then
  ok "P1: an id appearing only as a path token in files[] does not count as covered"
else
  fail "P1 incidental path token counted as coverage: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit error P4 SRC "message"'
mk_evals evals.json '{ "skill_name": "fixture", "evals": [ { "id": 1, "name": "case", "prompt": "check P4 for me", "expected_output": "runs the detector", "files": [], "expectations": ["runs the detector"] } ] }'
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P4"* ]]; then
  ok "P1: an id appearing only in a case's prompt does not count as covered"
else
  fail "P1 prompt mention counted as coverage: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P4 SRC "message"'
mk_evals evals.json '{ "skill_name": "P1 P4 fixture", "evals": [] }'
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"non-empty array of objects"* && -z "$OUT" ]]; then
  ok "P1: a suite with zero eval cases exits 2, and skill_name never counts as coverage"
else
  fail "P1 empty evals[] with ids in skill_name not caught: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P4 SRC "message"'
mk_evals evals.json '"P1 P4"'
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"non-empty array of objects"* && -z "$OUT" ]]; then
  ok "P1: an evals.json that is a bare JSON string exits 2 rather than covering everything"
else
  fail "P1 bare JSON string not caught: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P4 SRC "message"'
mk_evals evals.json '{ "skill_name": "fixture", "evals": ["P1 P4"] }'
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"non-empty array of objects"* && -z "$OUT" ]]; then
  ok "P1: an evals array of non-objects exits 2"
else
  fail "P1 evals[] of strings not caught: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ===== N1: the negation screen may not fail a suite on ordinary prose ======
# A screen that scans 80 characters back to the previous `.`/`;`/`:` for a cue
# disclaims the id on any cue ANYWHERE in that span. Ordinary covering prose
# carries cues, so such a gate exits 1 on a correct suite: a false FAILURE with
# no remedy but editing the gate.
mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P4 SRC "message"'
mk_evals evals.json "$(evals_json 'Reports P1. A rule without a scope suffix must be flagged as P4.')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && "$ERR" != *"P4"* && "$OUT" != *"DISCLAIMED"* ]]; then
  ok "N1: a cue in an earlier clause ('without a scope suffix ... flagged as P4') still covers"
else
  fail "N1 false failure on 'without' in an earlier clause: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P4 SRC "message"'
mk_evals evals.json "$(evals_json 'Covers P1. A rule that does not name an interpreter is reported as P4.')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && "$ERR" != *"P4"* && "$OUT" != *"DISCLAIMED"* ]]; then
  ok "N1: 'does not name an interpreter ... reported as P4' still covers"
else
  fail "N1 false failure on a negated subject with a positive predicate: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P4 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1, and when a rule is not pinned, reports P4')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && "$ERR" != *"P4"* && "$OUT" != *"DISCLAIMED"* ]]; then
  ok "N1: a cue before a comma does not disclaim the id after it"
else
  fail "N1 false failure across a comma: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P4 SRC "message"' 'emit error P5 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1' 'never exercises P4')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$OUT" == *"DISCLAIMED CHECK ID: P4"* && "$ERR" == *"UNCOVERED CHECK ID: P5"* && "$ERR" != *"UNCOVERED CHECK ID: P4"* ]]; then
  ok "N1: a disclaimed id is an advisory while an unnamed id is still a finding"
else
  fail "N1 advisory/finding split wrong: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P4 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1' 'deliberately does NOT exercise P4')"
run_gate "$(pair det.sh evals.json)"
if [[ $RC -eq 0 && "$OUT" == *"DISCLAIMED P4"* && "$OUT" == *"COVERED    P1"* && "$OUT" == *"1 disclaimed-only id(s)"* ]]; then
  ok "N1: discover reports DISCLAIMED as its own status and counts it in the denominator"
else
  fail "N1 discover status wrong: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ============ P2: every emit call site is accounted for, or exit 2 =========
# Each shape below can drop an id from the emitted set while leaving the count
# non-zero, so a zero-ids guard alone never fires.
mk_tree
# shellcheck disable=SC2016  # the unexpanded $sev IS the fixture; expanding it erases the defect
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit "$sev" P4 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"emit call site"* && -z "$OUT" ]]; then
  ok "P2: an emit call site with a variable severity exits 2, never a silent partial set"
else
  fail "P2 variable severity lost silently: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
# shellcheck disable=SC2016  # see above: the literal $id is the call site under test
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error "$id" SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"emit call site"* && -z "$OUT" ]]; then
  ok "P2: an emit call site with a variable check id exits 2"
else
  fail "P2 variable id lost silently: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P2ab SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"emit call site"* && -z "$OUT" ]]; then
  ok "P2: an emitted id outside the row's pattern exits 2 rather than vanishing"
else
  fail "P2 out-of-pattern id lost silently: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "m"; emit error P2 SRC "m"'
mk_evals evals.json "$(evals_json 'exercises P2 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P1"* ]]; then
  ok "P2: two emit call sites on one line are both extracted"
else
  fail "P2 first of two emits on a line lost: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit_finding error P4 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P4"* ]]; then
  ok "P2: a partially renamed emitter (emit_finding) is still a call site"
else
  fail "P2 renamed emitter lost silently: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ============ P3: the detector's own prose is not a call site =============
# The mirror-image false FAILURE: a quoted or heredoc'd emit in help text was
# counted as a real emit, yielding a permanent uncoverable gap.
mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' "printf 'usage: emit error P9 <src> <detail>\\n'"
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && "$ERR" != *"P9"* && -z "$ERR" ]]; then
  ok "P3: an emit inside a quoted string is prose, not a call site"
else
  fail "P3 quoted emit counted as a call site: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' \
  "usage() { cat <<'USAGE'" \
  'emit error P9 SRC "someday"' \
  'USAGE' \
  '}'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && "$ERR" != *"P9"* && -z "$ERR" ]]; then
  ok "P3: an emit inside a heredoc body is prose, not a call site"
else
  fail "P3 heredoc emit counted as a call site: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"  # emit error P9 SRC "someday"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && "$ERR" != *"P9"* && -z "$ERR" ]]; then
  ok "P3: a trailing comment on a real call site is not a second call site"
else
  fail "P3 trailing comment counted: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ===== P3b: a `<<` that is not a heredoc operator arms no heredoc body =====
# The defect this section is the regression guard for: the opening scan read the
# RAW line, so a `<<` inside
# a quoted string or an arithmetic left shift armed a body whose delimiter no
# later line could close, and the skip ran to EOF. Every call site below the
# line disappeared from the extraction AND from the candidate count at once, so
# the accounting that turns a partial loss into exit 2 had nothing to compare
# and the gate passed clean on a detector with uncovered ids. One line of
# ordinary shell, no advisory, exit 0.
#
# Each case puts the shape between a COVERED id and an UNCOVERED one: exit 1
# naming P4 proves the sites below the shape were still read.
p3b_case() {
  local label="$1"
  shift
  mk_tree
  mk_detector det.sh 'emit warning P1 SRC "message"' "$@" 'emit error P4 SRC "message"'
  mk_evals evals.json "$(evals_json 'exercises P1 classification')"
  run_gate "$(pair det.sh evals.json)" --check
  if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P4"* ]]; then
    ok "P3b: $label arms no heredoc"
  else
    fail "P3b $label swallowed the rest of the file: rc=$RC out='$OUT' err='$ERR'"
  fi
  rm -rf "$root"
}

p3b_case 'an arithmetic left shift by a variable' 'v=$((x << n))'
p3b_case 'an arithmetic left shift by a literal' 'v=$((x << 3))'
p3b_case 'a nested arithmetic left shift' 'v=$(( (x + 1) << n ))'
p3b_case 'a `<<` inside a double-quoted argument' 'emit error P1 SRC "redact <<secret>> now"'
p3b_case 'a `<<` inside double-quoted prose' 'echo "a << b"'
p3b_case 'a `<<` inside single-quoted prose' "echo 'a << b'"
p3b_case 'a `<<` inside a trailing comment' 'emit error P1 SRC "m"  # see <<EOF'
p3b_case 'a `<<` in a comment opened after `;`' 'foo;#<<EOF'
p3b_case 'a bare arithmetic COMMAND left shift' '(( mask = 1 << bits ))'
p3b_case 'a bare arithmetic command, literal shift' '(( mask = 1 << 3 ))'
p3b_case 'a `<<` inside a parameter expansion' 'x=${v//y/<<EOF}'

parsed_span_case() {
  local label="$1"
  shift
  mk_tree
  mk_detector det.sh 'emit warning P1 SRC "message"' "$@"
  mk_evals evals.json "$(evals_json 'exercises P1 classification')"
  run_gate "$(pair det.sh evals.json)" --check
  if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P4"* && "$ERR" != *"emit call site"* ]]; then
    ok "P3b: $label is parsed, and the call after it is still seen"
  else
    fail "P3b $label was not read through: rc=$RC out='$OUT' err='$ERR'"
  fi
  rm -rf "$root"
}

parsed_span_case 'an unterminated `${` carrying a heredoc opener' \
  'x=${unset:-$(cat <<EOF' 'cat <<HELP' 'EOF' ')}' 'emit error P4 SRC "message"' 'HELP'
parsed_span_case 'an unterminated `((` carrying a heredoc opener' \
  'x=$(( a + $(cat <<EOF' 'cat <<HELP' 'EOF' ') ))' 'emit error P4 SRC "message"' 'HELP'
# `hint=${HINT:-<<EOF ...}` prints the text `<<EOF ...`; bash opens no heredoc.
parsed_span_case 'a `<<` that is data inside an unterminated `${`' \
  'hint=${HINT:-<<EOF opens a heredoc body' '}' 'emit error P4 SRC "message"' \
  'cat <<EOF' 'usage text' 'EOF' 'emit warning P1 SRC "message"'
parsed_span_case 'a left shift inside an unterminated `$((`' \
  'mask=$(( (1 << SHIFT) -' '         1 ))' 'emit error P4 SRC "message"' \
  'cat <<SHIFT' 'usage text' 'SHIFT' 'emit warning P1 SRC "message"'
parsed_span_case 'an unterminated `${` whose tail holds a subshell `)`' \
  'usage=${U:-$( (echo banner) && cat <<HELP' '  prog <<DATA' 'HELP' ')}' \
  'emit error P4 SRC "message"' "cat <<'DATA'" 'fixture text' 'DATA'
parsed_span_case 'an unterminated `${` carrying a backtick substitution' \
  'x=${UNSET:-`cat <<EOF' 'body' 'EOF' '`}' 'emit error P4 SRC "message"'

p3b_case 'an unterminated `${` with no `<<` in its tail' 'x=${v:-$(printf "%s" "a"' ')}'
p3b_case 'an unterminated `((` with no `<<` in its tail' 'v=$(( 1 + (2 * 3)' '))'
p3b_case 'an escaped `<` is not an operator' 'printf "%s\\n" \<\<EOF' # portability-ok: fixture shell containing an escaped redirection operator, not a GNU grep word boundary
# The escaped character must leave a SEPARATOR behind, not vanish. Emitting ""
# instead of a space rejoins two non-adjacent `<` into a `<<` operator, which
# arms a heredoc bash never opened. The walk's comment asserts both halves --
# not the literal character, and not nothing -- and only the first half was
# guarded until an audit mutated the second and no case failed.
p3b_case 'an escaped char that vanishes rejoins `<` into `<<`' 'cat <\<<EOF' # portability-ok: fixture shell with an escaped redirection operator, not a GNU grep word boundary
p3b_case 'a left shift in an array subscript' 'a[1<<3]=5'
p3b_case 'a left shift in `$[ ]` arithmetic' 'v=$[ 1 << 3 ]'
p3b_case 'a comment opened after `(`' 'f() (#<<EOF' ':' ')'

p3b_arms() {
  local label="$1"
  shift
  mk_tree
  mk_detector det.sh 'emit warning P1 SRC "message"' "$@" 'emit error P4 SRC "message"'
  mk_evals evals.json "$(evals_json 'exercises P1 classification')"
  run_gate "$(pair det.sh evals.json)" --check
  if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P4"* && "$ERR" != *"P9"* ]]; then
    ok "P3b: $label arms the body skip and closes it"
  else
    fail "P3b $label did not arm-and-close: rc=$RC out='$OUT' err='$ERR'"
  fi
  rm -rf "$root"
}

p3b_arms 'an unquoted delimiter' 'usage() { cat <<USAGE' 'emit error P9 SRC "someday"' 'USAGE' '}'
p3b_arms 'a tab-stripped `<<-` delimiter' 'usage() { cat <<-USAGE' 'emit error P9 SRC "someday"' \
  '	USAGE' '}'
p3b_arms 'a double-quoted delimiter' 'usage() { cat <<"USAGE"' 'emit error P9 SRC "someday"' \
  'USAGE' '}'
p3b_arms 'a redirected heredoc (`>&2 <<EOF`)' 'usage() { cat >&2 <<USAGE' \
  'emit error P9 SRC "someday"' 'USAGE' '}'
p3b_arms 'a single-quoted delimiter' "usage() { cat <<'USAGE'" 'emit error P9 SRC "someday"' \
  'USAGE' '}'

# The four spellings a narrowed delimiter matcher armed on the WRONG word, each
# swallowing to EOF. `<<\USAGE` is a plain POSIX heredoc: the backslash only
# suppresses expansion, exactly as quoting the delimiter does.
p3b_arms 'a backslash-escaped delimiter' 'usage() { cat <<\USAGE' \
  'emit error P9 SRC "someday"' 'USAGE' '}'
p3b_arms 'a backslash-escaped `<<-` delimiter' 'usage() { cat <<-\USAGE' \
  'emit error P9 SRC "someday"' '	USAGE' '}'
# A delimiter carrying punctuation is a delimiter. bash accepts all of these,
# and REFUSING one is not safe: the body
# is then read as code and a `<<` inside it arms and swallows. They assert the
# whole delimiter is read, which is what stops that cascade.
p3b_arms 'a delimiter carrying `@`' 'usage() { cat <<USAGE@1' \
  'emit error P9 SRC "someday"' 'USAGE@1' '}'
p3b_arms 'a delimiter carrying `=`' 'usage() { cat <<USAGE=1' \
  'emit error P9 SRC "someday"' 'USAGE=1' '}'
p3b_arms 'a delimiter carrying `!`' 'usage() { cat <<USAGE!' \
  'emit error P9 SRC "someday"' 'USAGE!' '}'
p3b_arms 'a delimiter carrying `{`' 'usage() { cat <<USAGE{' \
  'emit error P9 SRC "someday"' 'USAGE{' '}'
p3b_arms 'a delimiter carrying `#`' 'usage() { cat <<USAGE#' \
  'emit error P9 SRC "someday"' 'USAGE#' '}'

p3b_arms 'a quoted delimiter carrying a dot' "usage() { cat <<'PY.END'" \
  'emit error P9 SRC "someday"' 'PY.END' '}'
p3b_arms 'an unquoted hyphenated delimiter' 'usage() { cat <<USAGE-1' \
  'emit error P9 SRC "someday"' 'USAGE-1' '}'
# Removing `${ ... }` from the scan's copy must not cost a real opener sharing
# the line with one.
# CLOSING EARLY IS AS SILENT AS NEVER CLOSING, and the unclosed-at-EOF rule
# cannot see it: a skip that closes on a line bash treats as body re-syncs on
# some later line, so it swallows the real call sites in between and still
# finishes with nothing outstanding. These three are that direction, and each
# needs the terminator matched exactly the way bash matches it.
#
# The fixture is the CASCADE, not just the early close, because "the body's own
# emit is hidden" is satisfied by a swallow too. A line bash reads as body but
# the scanner reads as a terminator is followed by a second `<<`: on the buggy
# path that second opener arms, eats the true terminator and the code past it,
# and closes later, so the call site after the function disappears. On the
# correct path the whole block is body and that call site is plain code.
early_close_case() {
  local label="$1" fake="$2" true_term="$3" opener="$4"
  mk_tree
  mk_detector det.sh 'emit warning P1 SRC "message"' \
    "usage() { cat $opener" 'body' "$fake" 'cat <<HELP' 'emit error P9 SRC "someday"' \
    "$true_term" '}' 'emit error P4 SRC "message"' 'HELP'
  mk_evals evals.json "$(evals_json 'exercises P1 classification')"
  run_gate "$(pair det.sh evals.json)" --check
  if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P4"* && "$ERR" != *"P9"* ]]; then
    ok "P3b: $label does not close the skip early"
  else
    fail "P3b $label closed early and swallowed: rc=$RC out='$OUT' err='$ERR'"
  fi
  rm -rf "$root"
}

# `USAGE ` with a trailing space is BODY to bash, not a terminator.
early_close_case 'a terminator carrying a trailing space' 'USAGE ' 'USAGE' '<<USAGE'
# `<<-` strips TABS only, so a space-indented terminator is body.
early_close_case 'a `<<-` terminator indented by spaces' '  USAGE' '	USAGE' '<<-USAGE'
early_close_case 'a plain `<<` terminator indented by a tab' '	USAGE' 'USAGE' '<<USAGE'

# `#` after `)` or a backtick is NOT reliably a comment: `$(printf a)#tag`
# prints `a#tag`. Reading it as one truncates the line and loses what followed,
# so the call site has to be ON THE SAME LINE, after the `#`. With it on the
# next line the fixture proves nothing: truncating a line that carries no emit
# costs nothing, and the guard passes even when the bug is present.
p3b_samecase() {
  local label="$1" shape="$2"
  mk_tree
  mk_detector det.sh 'emit warning P1 SRC "message"' "$shape"
  mk_evals evals.json "$(evals_json 'exercises P1 classification')"
  run_gate "$(pair det.sh evals.json)" --check
  if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P4"* ]]; then
    ok "P3b: $label does not truncate the line"
  else
    fail "P3b $label truncated the line: rc=$RC out='$OUT' err='$ERR'"
  fi
  rm -rf "$root"
}
p3b_samecase 'a `#` after a command substitution `)`' 'echo $(printf a)#tag; emit error P4 SRC "x"'
p3b_samecase 'a `#` after a backtick' 'echo `printf a`#tag; emit error P4 SRC "x"'

unclosed_case() {
  local label="$1"
  shift
  mk_tree
  mk_detector det.sh 'emit warning P1 SRC "message"' "$@"
  mk_evals evals.json "$(evals_json 'exercises P1 classification')"
  run_gate "$(pair det.sh evals.json)" --check
  if [[ $RC -eq 2 && "$ERR" == *"emit call site"* ]]; then
    ok "P3b: $label is exit 2, not a clean finish"
  else
    fail "P3b $label did not fail closed: rc=$RC out='$OUT' err='$ERR'"
  fi
  rm -rf "$root"
}

unclosed_case 'a heredoc never closed before EOF' 'usage() { cat <<USAGE' 'emit error P9 SRC "x"'

mk_tree
# shellcheck disable=SC1003  # the trailing backslash is the continuation under test
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P4 SRC "x" \'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P4"* && "$ERR" != *"emit call site"* ]]; then
  ok "P3b: a trailing continuation the parser accepts is a finished call"
else
  fail "P3b trailing continuation: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

p3b_arms 'a heredoc opened beside a parameter expansion' 'usage() { cat ${opt} <<USAGE' \
  'emit error P9 SRC "someday"' 'USAGE' '}'

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error ${id} SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"emit call site"* ]]; then
  ok "P3b: an id carried by a parameter expansion is still unreadable, not dropped"
else
  fail "P3b parameter-expansion id: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

p3b_case 'a here-string (`<<<`) opens no body, by either mechanism' 'grep x <<<"$v"'

# ====== N2: ordinary shell is not a partial extraction loss (exit 2) ======
# Each shape below can make a well-formed detector un-gateable, when the site
# counter and the id extractor disagree, and any disagreement is exit 2 ("cannot determine"). Where the id IS readable the
# assertion is exit 1 naming it, which proves the site was EXTRACTED rather
# than merely skipped; where the line is not a call site at all the assertion
# is a clean exit 0.
mk_tree
mk_detector det.sh 'emit "error" P1 SRC "message"' 'emit warning P2 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P2 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P1"* && "$ERR" != *"emit call site"* ]]; then
  ok "N2: a quoted severity resolves normally instead of exiting 2"
else
  fail "N2 quoted severity: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit error "P1" SRC "message"' 'emit warning P2 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P2 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P1"* && "$ERR" != *"emit call site"* ]]; then
  ok "N2: a quoted check id resolves normally instead of exiting 2"
else
  fail "N2 quoted id: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
# shellcheck disable=SC1003  # the trailing backslash IS the fixture: it is the
# line continuation under test, not an attempt to escape a quote.
mk_detector det.sh 'emit \' 'warning P4 SRC "message"' 'emit error P1 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P4"* && "$ERR" != *"emit call site"* ]]; then
  ok "N2: a backslash-continued call is one site and resolves"
else
  fail "N2 line continuation: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
# shellcheck disable=SC2016  # the unexpanded "$@" IS the fixture
mk_detector det.sh 'emit_x() { emit error "$@"; }' 'emit_x error P4 SRC "message"' 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P4"* && "$ERR" != *"emit call site"* ]]; then
  ok "N2: an emit* wrapper DEFINITION is not a call site, while its call sites still are"
else
  fail "N2 wrapper definition: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
# shellcheck disable=SC2016  # see above
mk_detector det.sh 'emit_x() {' '  emit error "$@"' '}' 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && -z "$ERR" ]]; then
  ok "N2: a multi-line emit* wrapper definition is not a call site"
else
  fail "N2 multi-line wrapper definition: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
# shellcheck disable=SC2016  # the literal $emit_count is part of the fixture
mk_detector det.sh 'local emit_count' 'declare -i emit_total' 'emit_count=0' \
  'echo "$emit_count"' 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && -z "$ERR" ]]; then
  ok "N2: an identifier beginning with emit (local emit_count) is not a call site"
else
  fail "N2 bare emit-prefixed identifier: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'echo "emit"' 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && -z "$ERR" ]]; then
  ok "N2: a quoted word is a value, never an emitter name"
else
  fail "N2 quoted emitter name counted: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error "P2ab" SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 2 && "$ERR" == *"emit call site"* && -z "$OUT" ]]; then
  ok "N2: a quoted literal that is not an id is unreadable, not silently dropped"
else
  fail "N2 quoted non-id wrongly resolved: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ===== #4222: calls a line walk lost, which the parser must still see =====
# Round 6 is the simplest one: a command substitution inside double quotes.
# The others are the rest of the open set that the syntax tree represents as
# a CallExpr. A quoted `eval` or `trap` body is data, not a call, which is
# the same answer as help text (P3); re-parsing those strings would count
# prose again.

parser_sees_p1() {
  local label="$1"
  shift
  mk_tree
  mk_detector det.sh 'emit warning P2 SRC "message"' "$@"
  mk_evals evals.json "$(evals_json 'exercises P2 classification')"
  run_gate "$(pair det.sh evals.json)" --check
  if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P1"* && "$ERR" != *"P9"* && "$ERR" != *"emit call site"* ]]; then
    ok "parser: $label"
  else
    fail "parser $label: rc=$RC out='$OUT' err='$ERR'"
  fi
  rm -rf "$root"
}

# shellcheck disable=SC2016  # the unexpanded $(emit ...) IS the call under test
parser_sees_p1 'a command substitution inside double quotes (round 6)' 'x="$(emit error P1)"'
parser_sees_p1 'a quoted command word' '"emit" error P1 SRC "message"'
parser_sees_p1 'time -p in front of the call' 'time -p emit error P1 SRC "message"'
parser_sees_p1 'coproc in front of the call' 'coproc emit error P1 SRC "message"'
parser_sees_p1 'a leading redirection' '>/dev/null emit error P1 SRC "message"'
parser_sees_p1 'a += assignment prefix' 'x+=1 emit error P1 SRC "message"'
parser_sees_p1 'bare eval whose next word is the emitter' 'eval emit error P1 SRC "message"'
parser_sees_p1 'two heredocs on one line' \
  'cat <<A <<B' 'emit error P9 SRC "someday"' 'A' 'body' 'B' 'emit error P1 SRC "message"'
parser_sees_p1 'deprecated $[ ] arithmetic before a real heredoc' \
  'x=$[ 1 << EOF ]' 'cat <<EOF' 'emit error P9 SRC "someday"' 'EOF' 'emit error P1 SRC "message"'

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' "eval 'emit error P9'"
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && -z "$ERR" ]]; then
  ok "parser: a quoted eval body is data, not a call site"
else
  fail "parser quoted eval counted: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

wrapper_unresolved() {
  local label="$1" wrapped="$2"
  mk_tree
  mk_detector det.sh 'emit warning P1 SRC "message"' "$wrapped"
  mk_evals evals.json "$(evals_json 'exercises P1 classification')"
  run_gate "$(pair det.sh evals.json)" --check
  if [[ $RC -eq 2 && "$ERR" == *"emit call site"* && "$ERR" == *"line 4: ${wrapped%% *} ... emit"* && -z "$OUT" ]]; then
    ok "wrapper: $label is UNRESOLVED and named"
  else
    fail "wrapper $label: rc=$RC out='$OUT' err='$ERR'"
  fi
  rm -rf "$root"
}
wrapper_unresolved 'command -p emit' 'command -p emit error P1 SRC "message"'
wrapper_unresolved 'env X=1 emit' 'env X=1 emit error P1 SRC "message"'
wrapper_unresolved 'xargs emit' 'xargs emit error P1 SRC "message"'

mk_tree
mk_detector det.sh 'emit warning P2 SRC "message"' 'command emit error P1 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P2 classification')"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNCOVERED CHECK ID: P1"* && "$ERR" != *"emit call site"* ]]; then
  ok "wrapper: command emit still resolves"
else
  fail "wrapper command emit: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ===== what the walk resolves, excludes and refuses =========================
# A real call must end as an id, as an UNRESOLVED line naming its site, or as a
# stated exclusion; never as nothing.
parser_sees_p1 'a single-quoted command word' "'emit' error P1 SRC \"message\""
parser_sees_p1 'single-quoted severity and id' "emit 'error' 'P1' SRC \"message\""
parser_sees_p1 'a dollar-quoted command word' "\$'emit' error P1 SRC \"message\""
parser_sees_p1 'a hyphenated emitter name' 'emit-finding error P1 SRC "message"'
parser_sees_p1 'a namespaced emitter name' 'emit::finding error P1 SRC "message"'
parser_sees_p1 'a brace-expanded emitter name' 'emit{1..1} error P1 SRC "message"'
parser_sees_p1 'command shifts to a hyphenated emitter' 'command emit-finding error P1 SRC "message"'
parser_sees_p1 'builtin shifts to the emitter' 'builtin emit error P1 SRC "message"'
parser_sees_p1 'exec shifts to the emitter' 'exec emit error P1 SRC "message"'
parser_sees_p1 'nohup shifts to the emitter' 'nohup emit error P1 SRC "message"'
parser_sees_p1 'a single-quoted wrapper shifts too' "'command' emit error P1 SRC \"message\""
parser_sees_p1 'a forwarder after the id is still a site' 'emit error P1 "$@"'

wrapper_unresolved 'exec -a NAME emit' 'exec -a name emit error P1 SRC "message"'
wrapper_unresolved 'nohup -- emit' 'nohup -- emit error P1 SRC "message"'
wrapper_unresolved 'builtin -- emit' 'builtin -- emit error P1 SRC "message"'
wrapper_unresolved 'eval -- emit' 'eval -- emit error P1 SRC "message"'
wrapper_unresolved 'command -p emit with a later -v argument' 'command -p emit error P1 SRC "message" -v'
wrapper_unresolved 'command -- emit with a later -V argument' 'command -- emit error P1 SRC "message" -V'
wrapper_unresolved 'env -v emit' 'env -v X=1 emit error P1 SRC "message"'
wrapper_unresolved 'a word that only ends in -v' 'command -p x-v emit error P1 SRC "message"'
wrapper_unresolved 'an option that only starts like -v' 'command -vx emit error P1 SRC "message"'
wrapper_unresolved 'a computed option before the emitter' 'command "$opt" emit error P1 SRC "message"'
wrapper_unresolved 'the first of two emit names' 'command -p emit emit_b'
wrapper_unresolved 'a wrapped call with one argument' 'command -p emit error'
wrapper_unresolved 'a wrapped call with a forwarder after the id' 'command -p emit error P1 "$@"'
wrapper_unresolved 'a wrapped call with a word after a forwarder' 'command -- emit "$@" error P1 SRC "message"'

unresolved_case() {
  local label="$1" n=4 named=1
  shift
  mk_tree
  mk_detector det.sh 'emit warning P1 SRC "message"' "$@"
  mk_evals evals.json "$(evals_json 'exercises P1 classification')"
  run_gate "$(pair det.sh evals.json)" --check
  for _ in "$@"; do
    [[ "$ERR" == *"unparsed: line $n:"* ]] || named=0
    n=$((n + 1))
  done
  if [[ $RC -eq 2 && $named -eq 1 && "$ERR" == *"emit call site"* && -z "$OUT" ]]; then
    ok "unresolved: $label"
  else
    fail "unresolved $label: rc=$RC out='$OUT' err='$ERR'"
  fi
  rm -rf "$root"
}

not_a_site_case() {
  local label="$1"
  shift
  mk_tree
  mk_detector det.sh 'emit warning P1 SRC "message"' "$@"
  mk_evals evals.json "$(evals_json 'exercises P1 classification')"
  run_gate "$(pair det.sh evals.json)" --check
  if [[ $RC -eq 0 && -z "$ERR" ]]; then
    ok "not a site: $label"
  else
    fail "not a site $label: rc=$RC out='$OUT' err='$ERR'"
  fi
  rm -rf "$root"
}

not_a_site_case 'every forwarder spelling' \
  'emit error "$@"' 'emit error $@' 'emit error "$*"' 'emit error $*' 'emit error ${@}' \
  'emit error "${*}"' 'emit "$@"' 'command -p emit error "$@"' 'env X=1 emit "$@"'
not_a_site_case 'a command lookup' \
  'command -v emit emit_finding' 'command -pv emit git' "command '-v' emit x" 'command -V emit x' \
  'command -vp emit x'
not_a_site_case 'a call with no arguments' 'emit' 'command emit' 'builtin emit'
not_a_site_case 'a wrapped call with no arguments' 'command -p emit' 'env emit' 'xargs emit'
not_a_site_case 'a command word that is not a static literal' \
  '"$cmd" arg' '$emitter error P1' '"${cmd[@]}" x' 'x=$(date); "$x" y'
not_a_site_case 'a wrapper with no static second word' \
  'exec "$@"' 'eval "$body"' 'command "$cmd"' 'nohup' 'exec >/dev/null 2>&1'
not_a_site_case 'a double-quoted eval body is text' 'eval "emit error P9" more'
not_a_site_case 'a wrapper argument holding help text' 'command printf "%s %s" "emit error P9" more'
not_a_site_case 'a command that only contains emit' 'remit error P9' 'xemit_finding warning P9'

unresolved_case 'a modified or longer $@ is not a forwarder' \
  'emit error ${@:1}' 'emit error ${@:-x}' 'emit error ${#@}' 'emit error ${@/a/b}' \
  'emit error ${!@}' 'emit error "${!*}"' 'emit error "$@"x' 'emit error $@x' 'emit error "$@$x"' \
  "emit error '\$@'"
unresolved_case 'a word after a forwarder' \
  'emit error "$@" P1' 'emit "$@" error P1' 'emit "$@" "$src"'
unresolved_case 'an id that is only partly static' 'emit error P1$x' 'emit error "P1$x"'
unresolved_case 'an id the row pattern matches only in part' 'emit error xP1' 'emit error P1xx'
unresolved_case 'a computed severity or id' 'emit "$sev" P4' 'emit error ${id}'
unresolved_case 'a severity that is not a plain word' \
  'emit -x P1' 'emit error-x P1' 'emit 1x P1' 'emit "a b" P1'
# `$` in the row pattern is not the end of the string: it also matches before a
# final newline. The id is matched from \A to \z.
unresolved_case 'an id with a trailing newline is not a full-string match' $'emit error "P1\n"'
# The full-string match reads \A ... \z, so a leading newline is not part of an id.
unresolved_case 'an id with a leading newline is not a full-string match' $'emit error "\nP1"'

# A quoted array subscript is a string bash evaluates later, the same class as
# `eval '...'`: the header's "any other string bash evaluates later" covers it.
not_a_site_case 'a quoted array subscript is text until bash evaluates it' \
  "[[ -v 'a[\$(emit error P9)]' ]]" "let 'a[\$(emit error P9)]=1'" "unset 'a[\$(emit error P9)]'"

multiline_id_case() {
  local label="$1" pattern="$2" id="$3" want_rc="$4"
  mk_tree
  mk_detector det.sh 'emit warning P1 SRC "message"' "emit error \"$id\""
  mk_evals evals.json "$(evals_json 'exercises P1 classification')"
  run_gate "surfaces/det.sh|surfaces/evals.json|$pattern" --check
  if [[ $RC -eq $want_rc ]] && { [[ $want_rc -eq 0 && -z "$ERR" ]] || [[ $want_rc -eq 2 && "$ERR" == *"has 2 emit call site(s) but only 3 resolved"* ]]; }; then
    ok "multiline id: $label"
  else
    fail "multiline id $label: rc=$RC out='$OUT' err='$ERR'"
  fi
  rm -rf "$root"
}
multiline_id_case 'a second ID line makes the resolved count exceed the candidates' \
  'P1|P1[[:space:]]ID[[:space:]]P2' $'P1\nID P2' 2
multiline_id_case 'a later line that only contains "ID " is not an ID line' \
  'P1|P1[[:space:]]xID[[:space:]]P2' $'P1\nxID P2' 0
multiline_id_case 'a CANDIDATES line inside an id does not replace the last one' \
  'P1|P1[[:space:]]CANDIDATES[[:space:]]7' $'P1\nCANDIDATES 7' 0

mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"' 'emit error P1x SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate 'surfaces/det.sh|surfaces/evals.json|P[0-9]|Q[0-9]' --check
if [[ $RC -eq 2 && "$ERR" == *"unparsed: line 4:"* ]]; then
  ok "an alternation row pattern is matched as a whole"
else
  fail "alternation row pattern: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

nested_ids_case() {
  local label="$1" n=10 shape k missing=""
  shift
  local -a shapes=("$@") lines=()
  for shape in "${shapes[@]}"; do
    n=$((n + 1))
    lines+=("${shape//@ID@/P$n}")
  done
  mk_tree
  mk_detector det.sh 'emit warning P1 SRC "message"' "${lines[@]}"
  mk_evals evals.json "$(evals_json 'exercises P1 classification')"
  run_gate "$(pair det.sh evals.json)" --check
  for ((k = 11; k <= n; k++)); do
    [[ "$ERR" == *"UNCOVERED CHECK ID: P$k "* ]] || missing+=" [${shapes[k - 11]}]"
  done
  if [[ $RC -eq 1 && -z "$missing" && "$ERR" != *"emit call site"* ]]; then
    ok "nested: $label"
  else
    fail "nested $label: rc=$RC lost:$missing out='$OUT' err='$ERR'"
  fi
  rm -rf "$root"
}
nested_ids_case 'a call inside each compound command, expansion and redirection' \
  '{ emit error @ID@; }' '( emit error @ID@ )' 'f() { emit error @ID@; }' 'function g { emit error @ID@; }' \
  'if emit error @ID@; then :; fi' 'if :; then emit error @ID@; fi' 'if :; then :; else emit error @ID@; fi' \
  'while emit error @ID@; do :; done' 'while :; do emit error @ID@; done' \
  'for i in 1; do emit error @ID@; done' 'for i in $(emit error @ID@); do :; done' \
  'case x in x) emit error @ID@ ;; esac' 'case $(emit error @ID@) in *) :;; esac' \
  'case x in $(emit error @ID@)) :;; esac' \
  'x=${v:$(emit error @ID@):1}' 'x=${v/$(emit error @ID@)/y}' 'x=${v//a/$(emit error @ID@)}' \
  ': && emit error @ID@' 'emit error @ID@ && :' ': | emit error @ID@' 'emit error @ID@ | cat' '! emit error @ID@' \
  'cat >"$(emit error @ID@)"' \
  'x=$(emit error @ID@)' 'x=`emit error @ID@`' 'declare y=$(emit error @ID@)' 'arr=($(emit error @ID@))' \
  'printf %s "$(emit error @ID@)"' 'diff <(emit error @ID@) /dev/null' 'x=${v:-$(emit error @ID@)}' \
  'x=$(( $(emit error @ID@) + 1 ))' '[[ $(emit error @ID@) ]]' 'let x=$(emit error @ID@)' \
  $'cat <<EOF\n$(emit error @ID@)\nEOF'

# A span neither shfmt nor bash accepts is a file the parser cannot read: exit 2.
# The line walk read these three (exit 1 naming P4), and this suite asserted so
# before shfmt became the reader; the parser's refusal is the answer now.
unparsable_case() {
  local label="$1"
  shift
  mk_tree
  mk_detector det.sh 'emit warning P1 SRC "message"' "$@" 'emit error P4 SRC "message"'
  mk_evals evals.json "$(evals_json 'exercises P1 classification')"
  run_gate "$(pair det.sh evals.json)" --check
  if [[ $RC -eq 2 && "$ERR" == *"shfmt could not parse"* && -z "$OUT" ]]; then
    ok "unparsable: $label is exit 2, not a guess"
  else
    fail "unparsable $label: rc=$RC out='$OUT' err='$ERR'"
  fi
  rm -rf "$root"
}
unparsable_case 'an unterminated `${` with no `<<` in its tail' 'x=${v:-$(printf "%s" "a"'
unparsable_case 'an unterminated `((` with no `<<` in its tail' 'v=$(( 1 + (2 * 3'
unparsable_case 'a comment opened after `(`' 'f() (#<<EOF'

# ============== P4: the registry is the stopping rule =====================
# A qualifying skill absent from the registry is unenforced, which is the same
# false-green one level up. Following check-script-contract.test.sh's precedent.
mk_tree
mkdir -p "$root/plugins/demo/skills/thing/scripts" "$root/plugins/demo/skills/thing/evals"
mk_detector det.sh 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
{
  printf '#!/usr/bin/env bash\n'
  printf 'emit() { return 0; }\n'
  printf 'emit warning Q1 SRC "message"\n'
  printf 'emit error Q2 SRC "message"\n'
} >"$root/plugins/demo/skills/thing/scripts/thing-check.sh"
evals_json 'exercises Q1 and Q2' >"$root/plugins/demo/skills/thing/evals/evals.json"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNREGISTERED PAIR: plugins/demo/skills/thing/scripts/thing-check.sh"* ]]; then
  ok "P4: a qualifying detector-plus-evals skill with no registry row fails loudly"
else
  fail "P4 unregistered pair not caught: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mkdir -p "$root/plugins/demo/skills/thing/scripts" "$root/plugins/demo/skills/thing/evals"
{
  printf '#!/usr/bin/env bash\n'
  printf 'emit() { return 0; }\n'
  printf 'emit warning Q1 SRC "message"\n'
  printf 'emit error Q2 SRC "message"\n'
} >"$root/plugins/demo/skills/thing/scripts/thing-check.sh"
evals_json 'exercises Q1 and Q2 classification' >"$root/plugins/demo/skills/thing/evals/evals.json"
run_gate 'plugins/demo/skills/thing/scripts/thing-check.sh|plugins/demo/skills/thing/evals/evals.json|Q[0-9]+' --check
if [[ $RC -eq 0 && "$ERR" != *"UNREGISTERED"* ]]; then
  ok "P4: a registered qualifying pair raises no stopping-rule finding"
else
  fail "P4 registered pair still flagged: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mkdir -p "$root/plugins/demo/skills/quoted/scripts" "$root/plugins/demo/skills/quoted/evals"
mk_detector det.sh 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
{
  printf '#!/usr/bin/env bash\n'
  printf 'emit() { return 0; }\n'
  printf 'emit "warning" "Q1" SRC "message"\n'
  printf 'emit error "Q2" SRC "message"\n'
} >"$root/plugins/demo/skills/quoted/scripts/quoted-check.sh"
evals_json 'exercises Q1 and Q2' >"$root/plugins/demo/skills/quoted/evals/evals.json"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNREGISTERED PAIR: plugins/demo/skills/quoted/scripts/quoted-check.sh"* ]]; then
  ok "N2: a detector spelled with quoted arguments still qualifies for the stopping rule"
else
  fail "N2 quoted detector invisible to the stopping rule: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mkdir -p "$root/plugins/demo/skills/printer/scripts" "$root/plugins/demo/skills/printer/evals"
mk_detector det.sh 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
{
  printf '#!/usr/bin/env bash\n'
  printf 'emit() { return 0; }\n'
  # shellcheck disable=SC2016  # the printer's own literal text, written verbatim
  printf 'emit managed dropin "$path"\n'
  # shellcheck disable=SC2016  # see above
  printf 'emit user settings "$path"\n'
} >"$root/plugins/demo/skills/printer/scripts/printer.sh"
evals_json 'lists the scopes it read' >"$root/plugins/demo/skills/printer/evals/evals.json"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && "$ERR" != *"UNREGISTERED"* ]]; then
  ok "P4: an emit-<scope>-<kind> printer is not mistaken for a check-id vocabulary"
else
  fail "P4 false candidate: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# ===== P7: the stopping rule scans EVERY emit call site on a line ==========
# A greedy sed retains only the LAST id on a line, so a detector spelling its
# two emits as `emit warning Q1 ...; emit error Q2 ...` would resolve to one id,
# fall short of the two-distinct-ids bar, and go silently unenforced. Discovery
# runs the verdict scanner, so the two halves cannot disagree.
mk_tree
mkdir -p "$root/plugins/demo/skills/oneline/scripts" "$root/plugins/demo/skills/oneline/evals"
mk_detector det.sh 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
{
  printf '#!/usr/bin/env bash\n'
  printf 'emit() { return 0; }\n'
  printf 'emit warning Q1 SRC "message"; emit error Q2 SRC "message"\n'
} >"$root/plugins/demo/skills/oneline/scripts/oneline-check.sh"
evals_json 'exercises Q1 and Q2' >"$root/plugins/demo/skills/oneline/evals/evals.json"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 1 && "$ERR" == *"UNREGISTERED PAIR: plugins/demo/skills/oneline/scripts/oneline-check.sh"* ]]; then
  ok "P7: two emits on ONE line qualify a pair, so an unregistered one still fails"
else
  fail "P7 one-line emit pair escaped the stopping rule: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mkdir -p "$root/plugins/demo/skills/oneline/scripts" "$root/plugins/demo/skills/oneline/evals"
{
  printf '#!/usr/bin/env bash\n'
  printf 'emit() { return 0; }\n'
  printf 'emit warning Q1 SRC "message"; emit error Q2 SRC "message"\n'
} >"$root/plugins/demo/skills/oneline/scripts/oneline-check.sh"
evals_json 'exercises Q1 and Q2 classification' >"$root/plugins/demo/skills/oneline/evals/evals.json"
run_gate 'plugins/demo/skills/oneline/scripts/oneline-check.sh|plugins/demo/skills/oneline/evals/evals.json|Q[0-9]+' --check
if [[ $RC -eq 0 && "$ERR" != *"UNREGISTERED"* && "$OUT" == *"2 emitted id(s)"* ]]; then
  ok "P7: a REGISTERED pair with two emits on one line passes, both ids resolved"
else
  fail "P7 registered one-line pair wrongly flagged: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

mk_tree
mkdir -p "$root/plugins/demo/skills/single/scripts" "$root/plugins/demo/skills/single/evals"
mk_detector det.sh 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
{
  printf '#!/usr/bin/env bash\n'
  printf 'emit() { return 0; }\n'
  printf 'emit warning Q1 SRC "one"; emit error Q1 SRC "two"\n'
} >"$root/plugins/demo/skills/single/scripts/single-check.sh"
evals_json 'exercises Q1' >"$root/plugins/demo/skills/single/evals/evals.json"
run_gate "$(pair det.sh evals.json)" --check
if [[ $RC -eq 0 && "$ERR" != *"UNREGISTERED"* ]]; then
  ok "P7: one DISTINCT emitted id does not qualify, however many call sites carry it"
else
  fail "P7 single-id script wrongly qualified: rc=$RC out='$OUT' err='$ERR'"
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

# ===== P5: discover stdout is buffered, so an exit 2 emits nothing there ====
# With two rows, a per-row exit 2 must not leave the FIRST row's report on
# stdout with no denominator trailer under it.
mk_tree
mk_detector a.sh 'emit warning P1 SRC "message"'
mk_evals a.json "$(evals_json 'exercises P1 classification')"
mk_detector b.sh 'emit error P2 SRC "message"'
run_gate "$(pair a.sh a.json)"$'\n'"$(pair b.sh missing.json)"
if [[ $RC -eq 2 && -z "$OUT" && "$ERR" == *"eval suite not readable"* ]]; then
  ok "P5: a per-row exit 2 in discover mode leaves nothing on stdout"
else
  fail "P5 partial discover report leaked to stdout: rc=$RC out='$OUT' err='$ERR'"
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

# P6: silently ignored trailing argv reads as a mode the gate accepted and did
# not run.
mk_tree
mk_detector det.sh 'emit warning P1 SRC "message"'
mk_evals evals.json "$(evals_json 'exercises P1 classification')"
run_gate "$(pair det.sh evals.json)" --check extra
if [[ $RC -eq 2 && "$ERR" == *"usage:"* && -z "$OUT" ]]; then
  ok "P6: excess argv after a valid mode exits 2 rather than being ignored"
else
  fail "P6 excess argv ignored: rc=$RC out='$OUT' err='$ERR'"
fi
rm -rf "$root"

# The built-in registry is checked against the live tree by the
# detector_eval_coverage gate step of pr-require-checks.yml, which runs --check
# whenever a skill script or eval set changes and fails on an unresolved row or
# an unregistered pair. Run here, that check reads every skill script of the tree.
test_harness::report
