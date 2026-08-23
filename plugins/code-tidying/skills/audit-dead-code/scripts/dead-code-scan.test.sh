#!/usr/bin/env bash
# Self-contained tests for dead-code-scan.sh (no external test lib — ships with
# the plugin). The assertion primitives are duplicated here on purpose: house
# convention is that a plugin test carries its own harness rather than sourcing
# a shared one.
#
# WHAT IS UNDER TEST: the parsing and adjudication-input layer, exercised
# HERMETICALLY. Each lane is driven through --lane so it runs in isolation, and
# each detector is replaced by a replayer on PATH that prints one of the REAL
# captured tool outputs in evals/fixtures/ (knip-report.json,
# knip-degraded.stderr.txt, vulture-report.txt, vulture-parse-error.txt,
# gopls-hints.txt) with a chosen exit status. No knip, vulture, or gopls is
# installed in CI, so the canned-fixture cases ARE the gate and never skip; only
# the one live end-to-end smoke case degrades to a bare SKIP.
#
# The replayers are not a shortcut around the detectors: every byte they print
# is a committed capture of the real tool, and the script under test cannot tell
# the difference — which is the point, because what is graded here is this
# script's READING of that output, not the detectors themselves.
set -uo pipefail

# This suite builds throwaway git repositories as fixtures (the cap ordering is
# git-recency-based, so a fixture needs real commits). An inherited ABSOLUTE
# GIT_DIR overrides repository discovery and outranks -C, so without this the
# fixture's `git config user.email` would land in the CALLER's .git/config —
# shared by every worktree of the clone — instead of in the fixture. Any process
# can export it (a git hook is one way, an ad-hoc command another), so it is
# cleared unconditionally rather than conditionally.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$SCRIPT_DIR/dead-code-scan.sh"
FIXTURES="$SCRIPT_DIR/../evals/fixtures"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present" ;;
  *) pass "$1" ;;
  esac
}
assert_equal() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

# Probe for REAL detectors BEFORE the replayers go on PATH, so the live smoke
# case cannot be fooled by this suite's own fakes.
LIVE_MISSING=""
for probe_tool in knip vulture gopls; do
  command -v -- "$probe_tool" >/dev/null 2>&1 || LIVE_MISSING="$LIVE_MISSING $probe_tool"
done
REAL_PATH="$PATH"

# --- Detector replayers -----------------------------------------------------------
# Each answers its version probe (the script proves presence by INVOCATION, so a
# non-invocable stub would be reported `skipped` rather than exercised) and
# otherwise replays a fixture with a caller-chosen exit status.

BIN_DIR="$TEST_TMPDIR/bin"
mkdir -p "$BIN_DIR"

cat >"$BIN_DIR/knip" <<'REPLAYER_EOF'
#!/usr/bin/env bash
case "${1:-}" in
--version)
  printf '6.32.2\n'
  exit 0
  ;;
*) ;;
esac
# knip reports paths relative to the project root it was invoked in, so a
# multi-root case needs a different capture per root. `$FAKE_KNIP_OUT.<dirname>`
# is used when it exists, and the plain capture otherwise — the script under
# test sees only bytes either way.
knip_capture="${FAKE_KNIP_OUT:-}"
if [[ -n "$knip_capture" && -f "$knip_capture.$(basename -- "$PWD")" ]]; then
  knip_capture="$knip_capture.$(basename -- "$PWD")"
fi
if [[ -n "$knip_capture" && -f "$knip_capture" ]]; then
  cat "$knip_capture"
fi
if [[ -n "${FAKE_KNIP_ERR:-}" && -f "${FAKE_KNIP_ERR:-}" ]]; then
  cat "$FAKE_KNIP_ERR" >&2
fi
exit "${FAKE_KNIP_EXIT:-0}"
REPLAYER_EOF

cat >"$BIN_DIR/vulture" <<'REPLAYER_EOF'
#!/usr/bin/env bash
case "${1:-}" in
--version)
  printf 'vulture 2.16\n'
  exit 0
  ;;
*) ;;
esac
if [[ -n "${FAKE_VULTURE_OUT:-}" && -f "${FAKE_VULTURE_OUT:-}" ]]; then
  cat "$FAKE_VULTURE_OUT"
fi
if [[ -n "${FAKE_VULTURE_ERR:-}" && -f "${FAKE_VULTURE_ERR:-}" ]]; then
  cat "$FAKE_VULTURE_ERR" >&2
fi
exit "${FAKE_VULTURE_EXIT:-0}"
REPLAYER_EOF

# gopls reports ABSOLUTE, cwd-independent paths and exposes no flag to
# relativize them. The committed capture carries a placeholder root; the replayer
# anchors it at THIS repository root, derived exactly the way the script derives
# its own, so the two strings cannot drift apart. The test then asserts the
# emitted Location came back repo-relative.
cat >"$BIN_DIR/gopls" <<'REPLAYER_EOF'
#!/usr/bin/env bash
case "${1:-}" in
version)
  printf 'golang.org/x/tools/gopls v0.20.0\n'
  exit 0
  ;;
*) ;;
esac
gopls_root="$(git rev-parse --show-toplevel 2>/dev/null)"
if [[ -n "${FAKE_GOPLS_OUT:-}" && -f "${FAKE_GOPLS_OUT:-}" ]]; then
  sed "s|/gopls-fixture|$gopls_root|" "$FAKE_GOPLS_OUT"
fi
if [[ -n "${FAKE_GOPLS_ERR:-}" && -f "${FAKE_GOPLS_ERR:-}" ]]; then
  cat "$FAKE_GOPLS_ERR" >&2
fi
exit "${FAKE_GOPLS_EXIT:-0}"
REPLAYER_EOF

chmod +x "$BIN_DIR/knip" "$BIN_DIR/vulture" "$BIN_DIR/gopls"
PATH="$BIN_DIR:$PATH"
export PATH

# --- Repository fixtures (inline tmpdirs; the shipped fixtures are the INPUT) ------
# evals/fixtures/** is never scanning input (dc_is_excluded_path), so the fixture
# sources are COPIED into each throwaway repo under ordinary paths.

init_repo() {
  mkdir -p "$1"
  git -C "$1" init -q >/dev/null 2>&1
  git -C "$1" config user.email 'dead-code-test@example.invalid' >/dev/null 2>&1
  git -C "$1" config user.name 'dead-code-test' >/dev/null 2>&1
}

stage_repo() {
  git -C "$1" add -A >/dev/null 2>&1
}

# knip needs a package.json root, TS files in scope, and a NON-EMPTY node_modules
# (probed directly — an unrestored run manufactures false unused-file findings).
TS_REPO="$TEST_TMPDIR/ts-repo"
init_repo "$TS_REPO"
mkdir -p "$TS_REPO/node_modules"
printf 'restored\n' >"$TS_REPO/node_modules/marker"
printf '%s\n' '{"name":"fixture","version":"0.0.0","private":true}' >"$TS_REPO/package.json"
cp "$FIXTURES/ts-orphan.ts" "$FIXTURES/ts-used.ts" "$FIXTURES/ts-entry.ts" \
  "$FIXTURES/dead-and-dynamic.ts" "$TS_REPO/"
stage_repo "$TS_REPO"

PY_REPO="$TEST_TMPDIR/py-repo"
init_repo "$PY_REPO"
cp "$FIXTURES/dead-and-dynamic.py" "$FIXTURES/py-entry.py" "$PY_REPO/"
stage_repo "$PY_REPO"

GO_REPO="$TEST_TMPDIR/go-repo"
init_repo "$GO_REPO"
cp "$FIXTURES/dead-and-dynamic.go" "$GO_REPO/"
printf 'module fixture\n\ngo 1.21\n' >"$GO_REPO/go.mod"
stage_repo "$GO_REPO"

# The grep lane needs no detector at all — system `grep -w -F` is the whole
# implementation — so this lane is fully hermetic and never skips.
SH_REPO="$TEST_TMPDIR/sh-repo"
init_repo "$SH_REPO"
cp "$FIXTURES/dead-and-dynamic.sh" "$SH_REPO/"
stage_repo "$SH_REPO"

# A package.json root with no TS file at all — the scanned-zero-files state.
EMPTY_REPO="$TEST_TMPDIR/empty-repo"
init_repo "$EMPTY_REPO"
mkdir -p "$EMPTY_REPO/node_modules"
printf 'restored\n' >"$EMPTY_REPO/node_modules/marker"
printf '%s\n' '{"name":"empty","version":"0.0.0","private":true}' >"$EMPTY_REPO/package.json"
printf 'no typescript here\n' >"$EMPTY_REPO/README.md"
stage_repo "$EMPTY_REPO"

# --- 1. knip report parsing (evals/fixtures/knip-report.json) ----------------------

knip_exit=0
knip_out="$(cd "$TS_REPO" && FAKE_KNIP_OUT="$FIXTURES/knip-report.json" FAKE_KNIP_EXIT=1 bash "$SCAN" --lane knip 2>/dev/null)" || knip_exit=$?
assert_exit "knip fixture scan exits 0" 0 "$knip_exit"
assert_contains "knip lane ran over the four TS files" "$knip_out" "Lane: knip | root=. | state=ran | files=4 | detail=3 candidate(s)"
assert_contains "orphan file reported as ts-unused-file" "$knip_out" "Finding shape: ts-unused-file"
assert_contains "orphan file is the fixture's orphan module" "$knip_out" "File: ts-orphan.ts"
assert_contains "orphan-file excerpt names the module" "$knip_out" "Finding excerpt: ts-orphan.ts"
assert_contains "unused export formatLegacyRow" "$knip_out" "Finding excerpt: formatLegacyRow"
assert_contains "unused export renderPanel" "$knip_out" "Finding excerpt: renderPanel"
assert_contains "unused-export shape" "$knip_out" "Finding shape: ts-unused-export"
assert_contains "formatLegacyRow line number is 13" "$knip_out" "Finding line: 13"
assert_contains "renderPanel line number is 17" "$knip_out" "Finding line: 17"
assert_contains "both exports attributed to their file" "$knip_out" "Summary file: dead-and-dynamic.ts | T1=0 T2=2 T3=0"
assert_contains "orphan file carries one T2" "$knip_out" "Summary file: ts-orphan.ts | T1=0 T2=1 T3=0"
# The used-export control: ts-used.ts / formatBytes is statically imported, so it
# is absent from the capture and must be absent from the records.
assert_not_contains "used-export control file not reported" "$knip_out" "File: ts-used.ts"
assert_not_contains "used-export control symbol not reported" "$knip_out" "formatBytes"
assert_not_contains "statically imported export not reported" "$knip_out" "mountPanel"

# --- 2. knip degradation (evals/fixtures/knip-degraded.stderr.txt) -----------------
# The degraded run's STDOUT is a healthy-looking blob — measured. Health comes
# from stderr, and a degraded lane must WITHHOLD every record it would otherwise
# have manufactured from that blob.

deg_exit=0
deg_out="$(cd "$TS_REPO" && FAKE_KNIP_OUT="$FIXTURES/knip-report.json" FAKE_KNIP_ERR="$FIXTURES/knip-degraded.stderr.txt" FAKE_KNIP_EXIT=1 bash "$SCAN" --lane knip 2>/dev/null)" || deg_exit=$?
assert_exit "degraded knip scan still exits 0" 0 "$deg_exit"
assert_contains "ERROR: on stderr marks the lane degraded" "$deg_out" "state=degraded"
assert_not_contains "degraded lane is not also ran" "$deg_out" "state=ran"
# The ABSENCE of records, not merely the presence of the marker.
assert_not_contains "degraded lane emits no unused-file record" "$deg_out" "Finding shape: ts-unused-file"
assert_not_contains "degraded lane emits no unused-export record" "$deg_out" "Finding shape: ts-unused-export"
assert_not_contains "degraded lane emits no finding at all" "$deg_out" "Finding tier:"
assert_not_contains "degraded lane leaks no symbol from the blob" "$deg_out" "formatLegacyRow"
assert_contains "degraded lane counts zero candidates" "$deg_out" "Summary candidates: total=0 emitted=0 dropped-by-cap=0 cap=0"
assert_contains "degraded lane counts zero findings" "$deg_out" "Summary total: files=0 T1=0 T2=0 T3=0"
assert_contains "degraded-only run is called a scan of nothing" "$deg_out" "Note: no lane ran"

# --- 2b. Per-root OWNERSHIP: a degraded nested root's files appear in NO record ----
# The contract (SKILL.md): "knip runs per project root … Each root carries its own
# state — one degraded workspace does not condemn the others." Running knip AT a
# root does not restrict what it REPORTS: knip walks the whole subtree, nested
# workspaces included. Measured on this marketplace before the ownership filter,
# the repo-root run emitted 213 of its 288 candidates for files belonging to roots
# the SAME scan had declared `degraded` and promised would "emit no records" —
# findings manufactured by exactly the unrestored run the degraded state exists to
# withhold. The outer root may only report the files it OWNS.

MULTI_DEG="$TEST_TMPDIR/multi-degraded"
init_repo "$MULTI_DEG"
mkdir -p "$MULTI_DEG/node_modules" "$MULTI_DEG/packages/inner"
printf 'restored\n' >"$MULTI_DEG/node_modules/marker"
printf '%s\n' '{"name":"outer","version":"0.0.0","private":true}' >"$MULTI_DEG/package.json"
cp "$FIXTURES/dead-and-dynamic.ts" "$FIXTURES/ts-used.ts" "$FIXTURES/ts-entry.ts" "$MULTI_DEG/"
# The nested root gets NO node_modules — the measured `degraded` trigger.
printf '%s\n' '{"name":"inner","version":"0.0.0","private":true}' >"$MULTI_DEG/packages/inner/package.json"
cp "$FIXTURES/ts-orphan.ts" "$FIXTURES/ts-entry.ts" "$MULTI_DEG/packages/inner/"
stage_repo "$MULTI_DEG"
# The committed capture, with the orphan module's path moved INTO the nested
# root — exactly the shape an outer-root knip run produces for a nested
# workspace. Everything else stays owned by the outer root.
MULTI_DEG_KNIP="$TEST_TMPDIR/knip-report-nested.json"
sed 's|"ts-orphan.ts"|"packages/inner/ts-orphan.ts"|g' "$FIXTURES/knip-report.json" >"$MULTI_DEG_KNIP"

md_exit=0
md_out="$(cd "$MULTI_DEG" && FAKE_KNIP_OUT="$MULTI_DEG_KNIP" FAKE_KNIP_EXIT=1 bash "$SCAN" --lane knip 2>/dev/null)" || md_exit=$?
assert_exit "multi-root scan exits 0" 0 "$md_exit"
assert_contains "the nested root is its own lane line, degraded" "$md_out" "Lane: knip | root=packages/inner | state=degraded | files=2"
# `files=3`: the outer root counts only what it OWNS — the nested root's two
# files are not the outer root's to scan.
assert_contains "the outer root counts only the files it owns" "$md_out" "Lane: knip | root=. | state=ran | files=3 | detail=2 candidate(s);"
assert_contains "the outer root says what it dropped" "$md_out" "1 finding(s) this root does not own dropped"
# THE ASSERTION: a degraded root's files appear in NO record, from any root.
assert_not_contains "no record names a file inside the degraded nested root" "$md_out" "File: packages/inner"
assert_not_contains "the degraded root's module leaks nowhere at all" "$md_out" "ts-orphan"
assert_not_contains "the degraded root emits no unused-file record" "$md_out" "Finding shape: ts-unused-file"
# The other half of the contract: one degraded workspace does not condemn the
# others — the healthy outer root still reports its own findings.
assert_contains "the healthy outer root still reports its own file" "$md_out" "File: dead-and-dynamic.ts"
assert_contains "the healthy outer root still reports its own export" "$md_out" "Finding excerpt: formatLegacyRow"
assert_contains "and the second one" "$md_out" "Finding excerpt: renderPanel"
assert_contains "totals count only the owned findings" "$md_out" "Summary total: files=1 T1=0 T2=2 T3=0"
assert_contains "the lane roster carries both roots' states" "$md_out" "Summary lanes: ran=1 skipped=0 degraded=1 scanned-zero-files=0"

# --- 2c. Per-root OWNERSHIP holds when BOTH roots are healthy ----------------------
# Ownership is not a degradation special case: a nested root's file is reported by
# that nested root's run and by no other, even when every root is healthy. Each
# root's knip run replays its own capture, because knip reports paths relative to
# the root it was invoked in.

MULTI_OK="$TEST_TMPDIR/multi-healthy"
init_repo "$MULTI_OK"
mkdir -p "$MULTI_OK/node_modules" "$MULTI_OK/packages/inner/node_modules"
printf 'restored\n' >"$MULTI_OK/node_modules/marker"
printf 'restored\n' >"$MULTI_OK/packages/inner/node_modules/marker"
printf '%s\n' '{"name":"outer","version":"0.0.0","private":true}' >"$MULTI_OK/package.json"
cp "$FIXTURES/ts-used.ts" "$FIXTURES/ts-entry.ts" "$MULTI_OK/"
printf '%s\n' '{"name":"inner","version":"0.0.0","private":true}' >"$MULTI_OK/packages/inner/package.json"
cp "$FIXTURES/ts-orphan.ts" "$FIXTURES/dead-and-dynamic.ts" "$MULTI_OK/packages/inner/"
stage_repo "$MULTI_OK"
# Outer capture: every path lies inside the nested root, so a correct outer run
# reports NOTHING. Nested capture: the committed one verbatim, whose paths are
# already relative to the nested root.
MULTI_OK_KNIP="$TEST_TMPDIR/knip-report-outer.json"
sed -e 's|"ts-orphan.ts"|"packages/inner/ts-orphan.ts"|g' \
  -e 's|"dead-and-dynamic.ts"|"packages/inner/dead-and-dynamic.ts"|g' \
  "$FIXTURES/knip-report.json" >"$MULTI_OK_KNIP"
cp "$FIXTURES/knip-report.json" "$MULTI_OK_KNIP.inner"

mo_out="$(cd "$MULTI_OK" && FAKE_KNIP_OUT="$MULTI_OK_KNIP" FAKE_KNIP_EXIT=1 bash "$SCAN" --lane knip 2>/dev/null)"
assert_contains "both roots ran" "$mo_out" "Lane: knip | root=packages/inner | state=ran | files=2 | detail=3 candidate(s)"
# THE ASSERTION: the outer root owns none of those paths, so it reports none of
# them — not one record, even though its own run named all three.
assert_contains "the outer root reports none of the nested root's files" "$mo_out" "Lane: knip | root=. | state=ran | files=2 | detail=0 candidate(s); 3 finding(s) this root does not own dropped"
# Each nested-root path is reported ONCE, by the nested root, at its real location.
assert_contains "the nested root reports its own orphan module" "$mo_out" "File: packages/inner/ts-orphan.ts"
assert_contains "the nested root reports its own exports' file" "$mo_out" "File: packages/inner/dead-and-dynamic.ts"
assert_not_contains "no nested path is re-reported at the outer root" "$mo_out" "File: ts-orphan.ts"
assert_not_contains "and neither is the exports' file" "$mo_out" "File: dead-and-dynamic.ts"
assert_contains "three findings total, none duplicated across roots" "$mo_out" "Summary total: files=2 T1=0 T2=3 T3=0"
assert_contains "the candidate count matches the owned findings" "$mo_out" "Summary candidates: total=3 emitted=3 dropped-by-cap=0 cap=0"

# --- 3. vulture's TWO stderr shapes must not be conflated --------------------------
# `<path>:<line>: <msg>` on stderr is ONE unparsable INPUT file — every other file
# was still analyzed, so the lane stays `ran`. If this regresses, a single stray
# non-Python file in scope marks the lane degraded and suppresses every real
# Python finding. The lane state is asserted EXPLICITLY, both ways.

parse_exit=0
parse_out="$(cd "$PY_REPO" && FAKE_VULTURE_OUT="$FIXTURES/vulture-report.txt" FAKE_VULTURE_ERR="$FIXTURES/vulture-parse-error.txt" FAKE_VULTURE_EXIT=3 bash "$SCAN" --lane vulture 2>/dev/null)" || parse_exit=$?
assert_exit "vulture input-note scan exits 0" 0 "$parse_exit"
assert_contains "input parse error keeps the lane RAN" "$parse_out" "Lane: vulture | root=. | state=ran"
assert_not_contains "input parse error does NOT degrade the lane" "$parse_out" "state=degraded"
assert_contains "unparsable input is reported as a Note" "$parse_out" "Note: vulture could not parse one input and skipped it (an input note, not a degraded run):"
assert_contains "the note carries the captured stderr line" "$parse_out" "vulture-parse-error-input.toml:8: cannot assign to expression here."
assert_contains "the unparsable input is counted in the lane detail" "$parse_out" "1 input file(s) skipped as unparsable"
# The findings that coexist with the input note must still be emitted.
assert_contains "real findings survive the input note" "$parse_out" "Finding excerpt: unused function 'format_legacy_row' (60% confidence)"
assert_contains "all four captured findings emitted" "$parse_out" "Summary total: files=2 T1=0 T2=4 T3=0"

# The discriminating counterpart: stderr NOT in the input-note shape (a usage
# error or traceback) IS a degraded run and withholds everything.
TRACEBACK_ERR="$TEST_TMPDIR/vulture-traceback.stderr.txt"
printf '%s\n' 'Traceback (most recent call last):' \
  '  File "/usr/lib/vulture/core.py", line 1, in <module>' \
  'TypeError: unsupported operand' >"$TRACEBACK_ERR"
vdeg_out="$(cd "$PY_REPO" && FAKE_VULTURE_OUT="$FIXTURES/vulture-report.txt" FAKE_VULTURE_ERR="$TRACEBACK_ERR" FAKE_VULTURE_EXIT=1 bash "$SCAN" --lane vulture 2>/dev/null)"
assert_contains "non-input stderr DOES degrade the lane" "$vdeg_out" "Lane: vulture | root=. | state=degraded"
assert_not_contains "degraded vulture emits no records" "$vdeg_out" "Finding shape: py-unused-symbol"
assert_contains "degraded vulture counts zero findings" "$vdeg_out" "Summary total: files=0 T1=0 T2=0 T3=0"

# --- 4. vulture finding parsing and the message-verb gate --------------------------

vul_out="$(cd "$PY_REPO" && FAKE_VULTURE_OUT="$FIXTURES/vulture-report.txt" FAKE_VULTURE_EXIT=3 bash "$SCAN" --lane vulture 2>/dev/null)"
assert_contains "vulture finding at line 13" "$vul_out" "Finding line: 13"
assert_contains "vulture finding at line 18" "$vul_out" "Finding line: 18"
assert_contains "vulture finding at line 23" "$vul_out" "Finding line: 23"
assert_contains "vulture finding at line 10" "$vul_out" "Finding line: 10"
assert_contains "vulture findings carry the py-unused-symbol shape" "$vul_out" "Finding shape: py-unused-symbol"
assert_contains "the dynamic-dispatch trap is a candidate, not a verdict" "$vul_out" "Finding excerpt: unused function 'handle_alpha' (60% confidence)"
assert_contains "entry-point file attributed separately" "$vul_out" "Summary file: py-entry.py | T1=0 T2=1 T3=0"
assert_contains "no unrecognized stdout lines for the clean capture" "$vul_out" "0 unrecognized stdout line(s)"

# The verb gate: only unused|unreachable|unsatisfiable is a finding. A look-alike
# in the exact same `<path>:<line>: <msg>` grammar with any other verb must become
# drift, never a silently coerced finding.
VERB_OUT="$TEST_TMPDIR/vulture-verbs.txt"
cat "$FIXTURES/vulture-report.txt" >"$VERB_OUT"
printf '%s\n' "dead-and-dynamic.py:36: unreachable code after 'raise' (100% confidence)" >>"$VERB_OUT"
printf '%s\n' "dead-and-dynamic.py:31: obsolete function 'ghost' (60% confidence)" >>"$VERB_OUT"
verb_out="$(cd "$PY_REPO" && FAKE_VULTURE_OUT="$VERB_OUT" FAKE_VULTURE_EXIT=3 bash "$SCAN" --lane vulture 2>/dev/null)"
assert_contains "unreachable verb maps to py-unreachable" "$verb_out" "Finding shape: py-unreachable"
assert_contains "py-unreachable is tier 1" "$verb_out" "Finding tier: 1"
assert_contains "non-verb look-alike becomes drift" "$verb_out" "Finding excerpt: vulture line not in the finding grammar: dead-and-dynamic.py:31: obsolete function 'ghost' (60% confidence)"
assert_contains "drift is filed under the no-file marker" "$verb_out" "Summary file: - | T1=0 T2=0 T3=1"
assert_contains "verb gate tallies 1/4/1 across three files" "$verb_out" "Summary total: files=3 T1=1 T2=4 T3=1"
assert_contains "drift is counted in the lane detail" "$verb_out" "1 unrecognized stdout line(s)"

# --- 5. gopls path relativization and the exported-symbol control ------------------

go_exit=0
go_out="$(cd "$GO_REPO" && FAKE_GOPLS_OUT="$FIXTURES/gopls-hints.txt" bash "$SCAN" --lane gopls 2>/dev/null)" || go_exit=$?
assert_exit "gopls fixture scan exits 0" 0 "$go_exit"
assert_contains "gopls lane ran" "$go_out" "Lane: gopls | root=. | state=ran"
# The capture's path is ABSOLUTE; the emitted Location must be repo-relative so
# the report reads as one document.
assert_contains "absolute gopls path relativized to the repo root" "$go_out" "File: dead-and-dynamic.go"
assert_not_contains "no absolute path leaks into a Location" "$go_out" "File: $GO_REPO"
assert_not_contains "no absolute path leaks anywhere in the record" "$go_out" "$GO_REPO/dead-and-dynamic.go"
assert_contains "unexported dead symbol reported" "$go_out" 'Finding excerpt: function "deadHandler" is unused'
assert_contains "gopls shape is go-unused-unexported" "$go_out" "Finding shape: go-unused-unexported"
assert_contains "go-unused-unexported is tier 1" "$go_out" "Finding tier: 1"
assert_contains "gopls line number preserved" "$go_out" "Finding line: 17"
assert_contains "one unexported candidate, no drift" "$go_out" "1 unexported candidate(s), 0 unrecognized line(s)"
assert_not_contains "exported symbol absent from the capture stays absent" "$go_out" "ExportedEntry"

# The exported-symbol control, in the identical measured diagnostic grammar
# (`<path>:<line>:<col-range>: <msg>`), appended to the same capture: it must be
# filtered as a diagnostic this lane does not own — NOT counted as drift, which
# would be a different and wrong reading.
GO_EXPORTED="$TEST_TMPDIR/gopls-hints-exported.txt"
cat "$FIXTURES/gopls-hints.txt" >"$GO_EXPORTED"
printf '%s\n' '/gopls-fixture/dead-and-dynamic.go:9:6-19: function "ExportedEntry" is unused' >>"$GO_EXPORTED"
goexp_out="$(cd "$GO_REPO" && FAKE_GOPLS_OUT="$GO_EXPORTED" bash "$SCAN" --lane gopls 2>/dev/null)"
assert_contains "unexported symbol still reported alongside the control" "$goexp_out" 'Finding excerpt: function "deadHandler" is unused'
assert_not_contains "exported symbol is not reported" "$goexp_out" "ExportedEntry"
assert_contains "exported symbol is filtered, not counted as drift" "$goexp_out" "1 unexported candidate(s), 0 unrecognized line(s)"
assert_contains "exported control does not inflate the totals" "$goexp_out" "Summary total: files=1 T1=1 T2=0 T3=0"

# --- 5b. A degraded gopls module emits NO records ----------------------------------
# gopls degrades toward false NEGATIVES: the module graph did not load, hints are
# suppressed, and it still exits 0. The lane line says the module "emits no
# records", and that claim has to be true. It was not: health used to be decided
# INSIDE the parse loop, so add_candidate had already appended this module's rows
# before the gate fired.

GO_DEGRADED="$TEST_TMPDIR/gopls-degraded.txt"
cat "$FIXTURES/gopls-hints.txt" >"$GO_DEGRADED"
printf '%s\n' '/gopls-fixture/dead-and-dynamic.go:6:1: could not import example.com/missing (no required module provides package example.com/missing)' >>"$GO_DEGRADED"
godeg_out="$(cd "$GO_REPO" && FAKE_GOPLS_OUT="$GO_DEGRADED" bash "$SCAN" --lane gopls 2>/dev/null)"
assert_contains "an import error on stdout degrades the module" "$godeg_out" "Lane: gopls | root=. | state=degraded"
assert_not_contains "degraded gopls emits no unexported record" "$godeg_out" "Finding shape: go-unused-unexported"
assert_not_contains "degraded gopls emits no finding at all" "$godeg_out" "Finding tier:"
assert_not_contains "degraded gopls leaks no symbol parsed before the gate" "$godeg_out" "deadHandler"
assert_contains "degraded gopls counts zero candidates" "$godeg_out" "Summary candidates: total=0 emitted=0 dropped-by-cap=0 cap=0"
assert_contains "degraded gopls counts zero findings" "$godeg_out" "Summary total: files=0 T1=0 T2=0 T3=0"

# The second degradation trigger: ANY byte on gopls stderr. The gate is `-s`, so
# this is deliberately conservative — routine chatter would degrade a healthy
# module — but it must at least be consistent with its own lane line.
GO_ERR="$TEST_TMPDIR/gopls-stderr.txt"
printf '%s\n' 'gopls: loading workspace: go.mod file not found in any parent directory' >"$GO_ERR"
goerr_out="$(cd "$GO_REPO" && FAKE_GOPLS_OUT="$FIXTURES/gopls-hints.txt" FAKE_GOPLS_ERR="$GO_ERR" bash "$SCAN" --lane gopls 2>/dev/null)"
assert_contains "a non-empty gopls stderr degrades the module" "$goerr_out" "Lane: gopls | root=. | state=degraded"
assert_not_contains "stderr-degraded gopls emits no records" "$goerr_out" "deadHandler"
assert_contains "stderr-degraded gopls counts zero findings" "$goerr_out" "Summary total: files=0 T1=0 T2=0 T3=0"

# --- 5c. grep lane (evals/fixtures/dead-and-dynamic.sh) ----------------------------
# The portable floor: a shell function whose name matches nowhere in the
# repository beyond its own definition sites. Both the genuinely dead function
# and the indirect-dispatch trap must surface as candidates — the lane cannot
# tell them apart, and pretending it can is what adjudication exists to prevent.

grep_exit=0
grep_out="$(cd "$SH_REPO" && bash "$SCAN" --lane grep 2>/dev/null)" || grep_exit=$?
assert_exit "grep lane scan exits 0" 0 "$grep_exit"
assert_contains "grep lane ran over the one shell file" "$grep_out" "Lane: grep | root=. | state=ran | files=1 | detail=2 candidate(s) from 3 distinct definition name(s)"
# The fixture used to name both symbols in its own header comment, and `grep -w -F`
# counted the prose mention as a reference — the fixture saved the very symbols it
# exists to condemn, and the lane produced nothing at all.
assert_not_contains "the fixture is not self-referencing into zero candidates" "$grep_out" "detail=0 candidate(s)"
assert_contains "grep shape is unreferenced-symbol" "$grep_out" "Finding shape: unreferenced-symbol"
assert_contains "unreferenced-symbol is tier 1" "$grep_out" "Finding tier: 1"
assert_contains "the genuinely dead function is a candidate" "$grep_out" "Finding excerpt: format_legacy_row() {"
assert_contains "the indirect-dispatch trap is also a candidate" "$grep_out" "Finding excerpt: handle_alpha() {"
assert_contains "dead function line number" "$grep_out" "Finding line: 22"
assert_contains "trap function line number" "$grep_out" "Finding line: 26"
assert_contains "both candidates attributed to the one file" "$grep_out" "Summary file: dead-and-dynamic.sh | T1=2 T2=0 T3=0"
assert_contains "grep lane totals" "$grep_out" "Summary total: files=1 T1=2 T2=0 T3=0"
# The referenced control: main is called literally, so a literal search saves it.
assert_not_contains "the literally called function is not a candidate" "$grep_out" "Finding excerpt: main() {"

# --- 6. Record protocol shape ------------------------------------------------------
# The `Finding …:` prefixes are a contract with the SKILL.md body's grep. Exact
# spelling is asserted here so a rename cannot pass silently.

assert_contains "File: prefix" "$knip_out" "File: dead-and-dynamic.ts"
assert_contains "Finding tier: prefix" "$knip_out" "Finding tier: 2"
assert_contains "Finding shape: prefix" "$knip_out" "Finding shape: ts-unused-export"
assert_contains "Finding line: prefix" "$knip_out" "Finding line: 13"
assert_contains "Finding excerpt: prefix" "$knip_out" "Finding excerpt: formatLegacyRow"
assert_contains "record separator" "$knip_out" "---"
assert_contains "Lane: prefix" "$knip_out" "Lane: knip |"
assert_contains "per-file summary with T1/T2/T3 counters" "$knip_out" "Summary file: ts-orphan.ts | T1=0 T2=1 T3=0"
assert_contains "lane roster summary" "$knip_out" "Summary lanes: ran=1 skipped=0 degraded=0 scanned-zero-files=0"
assert_contains "candidate/cap summary" "$knip_out" "Summary candidates: total=3 emitted=3 dropped-by-cap=0 cap=0"
assert_contains "total summary with T1/T2/T3 counters" "$knip_out" "Summary total: files=2 T1=0 T2=3 T3=0"
# A cap truncates candidates, not files: the per-file block reflects what was
# emitted, and the summary says how many were dropped.
cap_out="$(cd "$TS_REPO" && FAKE_KNIP_OUT="$FIXTURES/knip-report.json" FAKE_KNIP_EXIT=1 bash "$SCAN" --lane knip --max 1 2>/dev/null)"
assert_contains "cap reports what it dropped" "$cap_out" "Summary candidates: total=3 emitted=1 dropped-by-cap=2 cap=1"
assert_contains "cap keeps the counters honest" "$cap_out" "Summary total: files=1 T1=0 T2=1 T3=0"

# --- 7. Unrecognized detector output is T3 drift, never a clean result -------------
# The false-green guard: output no parser recognizes must never read as "nothing
# to report".

GARBAGE="$TEST_TMPDIR/knip-garbage.json"
printf '%s\n' '<!DOCTYPE html><html><body>knip changed its reporter</body></html>' >"$GARBAGE"
drift_exit=0
drift_out="$(cd "$TS_REPO" && FAKE_KNIP_OUT="$GARBAGE" FAKE_KNIP_EXIT=1 bash "$SCAN" --lane knip 2>/dev/null)" || drift_exit=$?
assert_exit "unrecognized knip output still exits 0" 0 "$drift_exit"
assert_contains "unrecognized output becomes a drift record" "$drift_out" "Finding shape: detector-drift"
assert_contains "drift is tier 3" "$drift_out" "Finding tier: 3"
assert_contains "drift record explains itself" "$drift_out" "Finding excerpt: knip produced output no parser recognized"
assert_contains "drift is named in the lane detail" "$drift_out" "output not recognized — recorded as T3 drift, never as clean"
assert_contains "drift is counted as T3, not as clean" "$drift_out" "Summary total: files=1 T1=0 T2=0 T3=1"
assert_not_contains "unrecognized output never reports zero findings" "$drift_out" "Summary total: files=0 T1=0 T2=0 T3=0"
assert_not_contains "unrecognized output is never called clean" "$drift_out" "Note: no candidates from the lanes that ran"

# A cap must never silence the drift alarm. A drift record has no commit recency,
# so it sorts NEWEST and was the first row --max threw away — SKILL.md promises
# T3 is "recorded, never silently dropped", so T3 is exempt from the cap.
driftcap_out="$(cd "$PY_REPO" && FAKE_VULTURE_OUT="$VERB_OUT" FAKE_VULTURE_EXIT=3 bash "$SCAN" --lane vulture --max 1 2>/dev/null)"
assert_contains "drift survives a cap of 1" "$driftcap_out" "Finding shape: detector-drift"
assert_contains "drift is exempt from the cap, ordinary candidates are not" "$driftcap_out" "Summary candidates: total=6 emitted=2 dropped-by-cap=4 cap=1"
assert_contains "the capped run still counts its T3" "$driftcap_out" "Summary total: files=2 T1=0 T2=1 T3=1"

# --- 8. Usage contract -------------------------------------------------------------

help_exit=0
bash "$SCAN" --help >/dev/null 2>&1 || help_exit=$?
assert_exit "--help exits 0" 0 "$help_exit"

unknown_exit=0
bash "$SCAN" --bogus >/dev/null 2>&1 || unknown_exit=$?
assert_exit "unknown flag exits 2" 2 "$unknown_exit"

badlane_exit=0
bash "$SCAN" --lane nosuchlane >/dev/null 2>&1 || badlane_exit=$?
assert_exit "unknown --lane exits 2" 2 "$badlane_exit"

badmax_exit=0
bash "$SCAN" --max notanumber >/dev/null 2>&1 || badmax_exit=$?
assert_exit "non-numeric --max exits 2" 2 "$badmax_exit"

missingval_exit=0
timeout 30 bash "$SCAN" --lane >/dev/null 2>&1 || missingval_exit=$?
assert_exit "--lane with no value exits 2" 2 "$missingval_exit"

# --- 9. scanned-zero-files is distinguishable from clean ---------------------------
# Both are what a detector otherwise reports as exit 0 with no output. One means
# "nothing was looked at", the other "everything was looked at and was clean" —
# they must not read the same.

zero_out="$(cd "$EMPTY_REPO" && bash "$SCAN" --lane knip 2>/dev/null)"
assert_contains "no TS file under the root is scanned-zero-files" "$zero_out" "state=scanned-zero-files"
assert_contains "scanned-zero-files says so in words" "$zero_out" "a scan of nothing, not a clean bill"
assert_contains "scanned-zero-files counts as no lane run" "$zero_out" "Summary lanes: ran=0 skipped=0 degraded=0 scanned-zero-files=1"
assert_contains "scanned-zero-files closes with the scan-of-nothing note" "$zero_out" "Note: no lane ran — this is a scan of nothing, not a clean bill."
assert_not_contains "scanned-zero-files is not the clean note" "$zero_out" "Note: no candidates from the lanes that ran"

clean_out="$(cd "$TS_REPO" && bash "$SCAN" --lane knip 2>/dev/null)"
assert_contains "an empty knip report is a RAN lane" "$clean_out" "Lane: knip | root=. | state=ran | files=4"
assert_contains "clean lane names what it covered" "$clean_out" "no unused file, export, type, or enum member reported"
assert_contains "clean lane counts as a run" "$clean_out" "Summary lanes: ran=1 skipped=0 degraded=0 scanned-zero-files=0"
assert_contains "clean closes with the lanes-that-ran note" "$clean_out" "Note: no candidates from the lanes that ran"
assert_not_contains "clean is not scanned-zero-files" "$clean_out" "scanned-zero-files=1"
# Both produce zero findings; only the surrounding state tells them apart.
assert_contains "clean has zero findings" "$clean_out" "Summary total: files=0 T1=0 T2=0 T3=0"
assert_contains "scanned-zero-files has zero findings too" "$zero_out" "Summary total: files=0 T1=0 T2=0 T3=0"

# --- 10. A detector's exit code is never read as run health ------------------------
# Measured: knip exits 1 for BOTH findings and hard errors; vulture exits 3 for
# findings and 1 for an input error; gopls check always exits 0. Reading $? would
# be reading noise, so the same bytes must produce the same report whatever the
# status.

knip_rc1="$(cd "$TS_REPO" && FAKE_KNIP_OUT="$FIXTURES/knip-report.json" FAKE_KNIP_EXIT=1 bash "$SCAN" --lane knip 2>/dev/null)"
knip_rc0="$(cd "$TS_REPO" && FAKE_KNIP_OUT="$FIXTURES/knip-report.json" FAKE_KNIP_EXIT=0 bash "$SCAN" --lane knip 2>/dev/null)"
knip_rc2="$(cd "$TS_REPO" && FAKE_KNIP_OUT="$FIXTURES/knip-report.json" FAKE_KNIP_EXIT=2 bash "$SCAN" --lane knip 2>/dev/null)"
assert_equal "knip exit 1 and exit 0 give the same report" "$knip_rc1" "$knip_rc0"
assert_equal "knip exit 2 and exit 0 give the same report" "$knip_rc2" "$knip_rc0"

vul_rc3="$(cd "$PY_REPO" && FAKE_VULTURE_OUT="$FIXTURES/vulture-report.txt" FAKE_VULTURE_EXIT=3 bash "$SCAN" --lane vulture 2>/dev/null)"
vul_rc0="$(cd "$PY_REPO" && FAKE_VULTURE_OUT="$FIXTURES/vulture-report.txt" FAKE_VULTURE_EXIT=0 bash "$SCAN" --lane vulture 2>/dev/null)"
vul_rc1="$(cd "$PY_REPO" && FAKE_VULTURE_OUT="$FIXTURES/vulture-report.txt" FAKE_VULTURE_EXIT=1 bash "$SCAN" --lane vulture 2>/dev/null)"
assert_equal "vulture exit 3 and exit 0 give the same report" "$vul_rc3" "$vul_rc0"
assert_equal "vulture exit 1 alone does not degrade the lane" "$vul_rc1" "$vul_rc0"

# A nonzero exit with EMPTY stdout is still a ran-and-clean lane, not a failure.
knip_rc1_empty="$(cd "$TS_REPO" && FAKE_KNIP_EXIT=1 bash "$SCAN" --lane knip 2>/dev/null)"
assert_contains "nonzero exit with no output is still a ran lane" "$knip_rc1_empty" "Lane: knip | root=. | state=ran"
assert_not_contains "nonzero exit alone never degrades a lane" "$knip_rc1_empty" "state=degraded"

# And the scan's own exit is 0 on every scan path.
scan_exit=0
(cd "$TS_REPO" && FAKE_KNIP_ERR="$FIXTURES/knip-degraded.stderr.txt" FAKE_KNIP_EXIT=1 bash "$SCAN" --lane knip) >/dev/null 2>&1 || scan_exit=$?
assert_exit "a degraded lane never fails the caller" 0 "$scan_exit"

# --- 11. Live end-to-end smoke (skipped when the detectors are absent) -------------
# CI installs none of the detectors; every canned-fixture case above is the real
# gate and does not skip.

if [[ -n "$LIVE_MISSING" ]]; then
  printf 'SKIP: live end-to-end detector run needs real tools on PATH; missing:%s. Every canned-fixture case above ran.\n' "$LIVE_MISSING"
else
  live_exit=0
  live_out="$(cd "$PY_REPO" && PATH="$REAL_PATH" bash "$SCAN" --lane vulture 2>/dev/null)" || live_exit=$?
  assert_exit "live vulture scan exits 0" 0 "$live_exit"
  assert_contains "live vulture lane reports a state" "$live_out" "Lane: vulture | root=. | state="
fi

# --- Final report ------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
