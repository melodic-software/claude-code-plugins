#!/usr/bin/env bash
# Regression tests for fetch-failed-logs.sh.
#
# Black-box: invokes the script as a subprocess with a stubbed `gh` on PATH
# that emits fixture data instead of calling the real GitHub API. Covers:
#
#   1. Full-run ZIP mode — extracts ##[error] markers per job folder
#   2. Per-job mode — emits failure markers from plain-text response
#   3. --raw flag — dumps unfiltered content
#   4. --keep-zip flag — leaves ZIP under scratch/
#   5. Size cap (FETCH_LOGS_MAX_BYTES) — aborts with exit 3
#   6. gh api failure — exits 2
#   7. Tiny non-ZIP response — exits 2 with diagnostic
#   8. Missing arguments — exits 1

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/fetch-failed-logs.sh"
# POSIX path for stub PATH entries (Git Bash PATH lookup fails on Windows-form
# paths like C:/Users/...). Production script accepts either form via env vars.
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/test-helpers.sh"

# Skip suite if `unzip` (production dep) or `zip` (test fixture builder) is
# missing. CI runners have them preinstalled. Windows Git Bash users install
# via `winget install gnuwin32.zip`.
command -v unzip >/dev/null 2>&1 || skip_suite "unzip not installed"
command -v zip >/dev/null 2>&1 || skip_suite "zip not installed"

# ---- Build fixture ZIP ------------------------------------------------------
#
# Layout mirrors REAL GitHub Actions logs ZIP layout (verified 2026-05-08
# against example-org/example-repo run 25505236665):
#   TOP-LEVEL: <step-num>_<job-name>.txt      consolidated step log (errors here)
#   PER-JOB:   <job-name>/system.txt           agent metadata only
# Filenames may contain SPACES + special chars (matrix expansions encoded with
# underscores). Earlier fixture used <jobN>/01_step.txt — that layout does not
# exist in real ZIPs and silently passed the test while the production logic
# missed real errors.

FIXTURE_BUILD="$TEST_TMPDIR/fixture-build"
mkdir -p "$FIXTURE_BUILD/build/" "$FIXTURE_BUILD/shell _ Bash (tests)/"
# Top-level consolidated step logs (where ##[error] markers actually live)
{
  printf '2026-05-08T10:00:00Z setup\n'
  printf '##[error]CS0246: type or namespace not found\n'
  printf '##[warning]NU1701: package downgrade\n'
} >"$FIXTURE_BUILD/0_build.txt"
{
  printf '2026-05-08T10:01:00Z tests starting\n'
  printf '##[error]Assert.Equal failure in MyTest\n'
  printf '##[error]Process completed with exit code 1.\n'
} >"$FIXTURE_BUILD/4_shell _ Bash (tests).txt"
# Per-job system.txt — metadata only, no error markers
printf 'Hosted Compute Agent\nVersion: 20260507.1.0\n' >"$FIXTURE_BUILD/build/system.txt"
printf 'Hosted Compute Agent\nVersion: 20260507.1.0\n' >"$FIXTURE_BUILD/shell _ Bash (tests)/system.txt"

FIXTURE_ZIP="$TEST_TMPDIR/run-logs.zip"
(cd "$FIXTURE_BUILD" && zip -qr "$FIXTURE_ZIP" .)

# ---- Build fixture per-job text ---------------------------------------------

FIXTURE_JOB_TXT="$TEST_TMPDIR/job-logs.txt"
{
  printf '2026-05-08T10:00:00Z job starting\n'
  printf '##[error]ENOENT path not found\n'
  printf '##[warning]NETSDK1206: deprecated framework\n'
  printf 'job done\n'
} >"$FIXTURE_JOB_TXT"

# ---- Stub `gh` --------------------------------------------------------------
#
# The stub reads its first arg ('api' or 'repo'), then dispatches:
#   api repos/<owner>/<repo>/actions/runs/<id>/logs       → cat fixture ZIP
#   api repos/<owner>/<repo>/actions/jobs/<id>/logs       → cat fixture text
#   api repos/<owner>/<repo>/actions/runs/FAIL/logs       → exit 1 (failure)
#   api repos/<owner>/<repo>/actions/runs/TINY/logs       → emit 5 bytes (not a ZIP)
#   repo view --json nameWithOwner ...                    → echo example-org/example-repo

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
cat >"$STUB_DIR/gh" <<STUB_EOF
#!/usr/bin/env bash
set -uo pipefail
case "\$1" in
  api)
    case "\$2" in
      *runs/FAIL/logs) exit 1 ;;
      *runs/TINY/logs) printf 'BAD!\n'; exit 0 ;;
      *runs/*/logs) cat "$FIXTURE_ZIP"; exit 0 ;;
      *jobs/FAIL/logs) exit 1 ;;
      *jobs/*/logs) cat "$FIXTURE_JOB_TXT"; exit 0 ;;
      *) printf 'gh-stub: unknown api path %q\n' "\$2" >&2; exit 1 ;;
    esac
    ;;
  repo)
    if [[ "\$2" == "view" ]]; then
      echo "example-org/example-repo"
      exit 0
    fi
    ;;
  *) printf 'gh-stub: unknown command %q\n' "\$1" >&2; exit 1 ;;
esac
STUB_EOF
chmod +x "$STUB_DIR/gh"

run_script() {
  PATH="$STUB_DIR:$PATH" \
    FETCH_LOGS_REPO="example-org/example-repo" \
    FETCH_LOGS_SCRATCH="$TEST_TMPDIR/scratch" \
    bash "$SCRIPT" "$@" 2>&1
}

# Variant that lets a case pick its own scratch dir (case isolation for
# size-cap / failure paths) and discards output. Returns exit code via $?.
run_script_with_scratch_silent() {
  local scratch="$1"
  shift
  PATH="$STUB_DIR:$PATH" \
    FETCH_LOGS_REPO="example-org/example-repo" \
    FETCH_LOGS_SCRATCH="$scratch" \
    bash "$SCRIPT" "$@" >/dev/null 2>&1
}

# Variant that lets a case pick its own scratch dir and capture combined output.
run_script_with_scratch() {
  local scratch="$1"
  shift
  PATH="$STUB_DIR:$PATH" \
    FETCH_LOGS_REPO="example-org/example-repo" \
    FETCH_LOGS_SCRATCH="$scratch" \
    bash "$SCRIPT" "$@" 2>&1
}

# ---- Cases ------------------------------------------------------------------

# Case 1: Full-run ZIP — extracts ##[error] from real-shape top-level files
out=$(run_script 12345)
if [[ "$out" == *"0_build.txt"* && "$out" == *"##[error]CS0246"* &&
  "$out" == *"4_shell _ Bash (tests).txt"* && "$out" == *"##[error]Assert.Equal"* ]]; then
  pass "full-run ZIP emits error markers from real-shape top-level files"
else
  fail "full-run ZIP emits error markers from real-shape top-level files" "filename headers + error markers" "$out"
fi

# Case 2: Per-job mode — emits ##[error] from plain text
out=$(run_script --job 99999)
if [[ "$out" == *"##[error]ENOENT"* && "$out" != *"job done"* ]]; then
  pass "per-job mode greps error/warning markers only"
else
  fail "per-job mode greps error/warning markers only" "ENOENT marker but no plain content" "$out"
fi

# Case 3: --raw mode dumps everything (no grep filter, includes system.txt)
out=$(run_script 12345 --raw)
if [[ "$out" == *"Hosted Compute Agent"* && "$out" == *"##[error]CS0246"* ]]; then
  pass "--raw dumps full content unfiltered (incl. per-job system.txt)"
else
  fail "--raw dumps full content unfiltered (incl. per-job system.txt)" "all txt files dumped" "$out"
fi

# Case 4: --keep-zip leaves ZIP under scratch
out=$(run_script 22222 --keep-zip)
if [[ -f "$TEST_TMPDIR/scratch/run-22222-logs.zip" ]]; then
  pass "--keep-zip preserves ZIP under scratch/"
else
  fail "--keep-zip preserves ZIP under scratch/" "ZIP at scratch/run-22222-logs.zip" "missing"
fi

# Case 5: Size cap aborts with exit 3
FETCH_LOGS_MAX_BYTES=10 run_script_with_scratch_silent "$TEST_TMPDIR/scratch5" 33333
assert_exit "size cap returns exit 3" 3 "$?"

# Case 6: gh api failure — exits 2
run_script_with_scratch_silent "$TEST_TMPDIR/scratch6" FAIL
assert_exit "gh api failure returns exit 2" 2 "$?"

# Case 7: Tiny non-ZIP response (5 bytes) — exits 2 with diagnostic
out=$(run_script_with_scratch "$TEST_TMPDIR/scratch7" TINY)
ec=$?
if [[ $ec -eq 2 && "$out" == *"likely an API error"* ]]; then
  pass "tiny non-ZIP response exits 2 with diagnostic"
else
  fail "tiny non-ZIP response exits 2 with diagnostic" "exit 2 + diagnostic" "exit $ec, out: $out"
fi

# Case 8: Missing arguments — exits 1
ec=0
run_script_with_scratch_silent "$TEST_TMPDIR/scratch8" || ec=$?
assert_exit "missing run-id and --job exits 1" 1 "$ec"

# ---- Audit flag fixture extension ----
# Add a step file with: a ##[group]/##[endgroup] pair with timestamps,
# a ##[notice] marker, and a "0 tests" suspicious-pattern line. Reuses the
# existing fixture path so existing assertions keep working.
{
  printf '2026-05-08T10:02:00.000Z ##[group]Restore packages\n'
  printf '2026-05-08T10:02:01.500Z restoring...\n'
  printf '2026-05-08T10:02:03.250Z ##[endgroup]\n'
  printf '2026-05-08T10:02:04.000Z ##[notice]informational note\n'
  printf '2026-05-08T10:02:05.000Z 0 tests passed\n'
  printf '2026-05-08T10:02:06.000Z Retrying download (attempt 2 of 3)\n'
} >>"$FIXTURE_BUILD/0_build.txt"
# Rebuild ZIP with extended fixture
(cd "$FIXTURE_BUILD" && zip -qr "$FIXTURE_ZIP" .)

# Case 9: --errors-only suppresses warnings
out=$(run_script 12345 --errors-only)
if [[ "$out" == *"##[error]CS0246"* && "$out" != *"##[warning]NU1701"* ]]; then
  pass "--errors-only excludes warning markers"
else
  fail "--errors-only excludes warning markers" "errors yes warnings no" "$out"
fi

# Case 10: --notices includes ##[notice]
out=$(run_script 12345 --notices)
if [[ "$out" == *"##[notice]informational"* ]]; then
  pass "--notices surfaces notice markers"
else
  fail "--notices surfaces notice markers" "informational note included" "$out"
fi

# Case 11: --groups shows step structure
out=$(run_script 12345 --groups)
if [[ "$out" == *"##[group]Restore packages"* && "$out" == *"##[endgroup]"* ]]; then
  pass "--groups extracts group/endgroup structure"
else
  fail "--groups extracts group/endgroup structure" "group markers" "$out"
fi

# Case 12: --timing computes per-group duration
out=$(run_script 12345 --timing)
# Restore packages spans 10:02:00.000 → 10:02:03.250 = 3250 ms
if [[ "$out" == *"timing"* && "$out" =~ [[:space:]]+3250[[:space:]]+ms[[:space:]]+Restore\ packages ]]; then
  pass "--timing computes 3250 ms duration for Restore packages group"
else
  fail "--timing computes 3250 ms duration for Restore packages group" "3250 ms Restore packages" "$out"
fi

# Case 13: --suspicious surfaces retry/0-tests patterns
out=$(run_script 12345 --suspicious)
if [[ "$out" == *"0 tests"* && "$out" == *"Retrying"* ]]; then
  pass "--suspicious greps retry + 0-tests patterns"
else
  fail "--suspicious greps retry + 0-tests patterns" "0 tests + Retrying" "$out"
fi

# Case 14: --audit macro fires groups + timing + suspicious sections
out=$(run_script 12345 --audit)
if [[ "$out" == *"groups (step structure)"* && "$out" == *"timing (per group"* && "$out" == *"suspicious patterns"* ]]; then
  pass "--audit macro emits groups + timing + suspicious sections"
else
  fail "--audit macro emits groups + timing + suspicious sections" "all 3 sections" "$out"
fi

# ---- Integration cases (opt-in: INTEGRATION=1) -----------------------------
#
# These hit the REAL GitHub API against a known-failed run in this repo.
# Skipped by default to keep unit tests fast + offline. Run with:
#   INTEGRATION=1 bash fetch-failed-logs.test.sh
#
# Point INTEGRATION_REPO + INTEGRATION_RUN_ID at a repo/run you can read
# (the run should contain ##[error] markers).

if [[ "${INTEGRATION:-0}" == "1" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    skip_case "INTEGRATION mode but gh CLI not available"
  elif [[ -z "${GH_TOKEN:-}" ]]; then
    skip_case "INTEGRATION mode but GH_TOKEN not set"
  elif [[ -z "${INTEGRATION_REPO:-}" || -z "${INTEGRATION_RUN_ID:-}" ]]; then
    skip_case "INTEGRATION mode but INTEGRATION_REPO / INTEGRATION_RUN_ID not set"
  else
    REAL_RUN_ID="$INTEGRATION_RUN_ID"
    INT_SCRATCH="$TEST_TMPDIR/int-scratch"
    out=$(FETCH_LOGS_REPO="$INTEGRATION_REPO" \
      FETCH_LOGS_SCRATCH="$INT_SCRATCH" \
      bash "$SCRIPT" "$REAL_RUN_ID" 2>&1)
    ec=$?
    if [[ $ec -eq 0 && "$out" == *"##[error]"* ]]; then
      pass "INTEGRATION: real run $REAL_RUN_ID returns error markers via API"
    else
      fail "INTEGRATION: real run $REAL_RUN_ID returns error markers via API" \
        "exit 0 + error marker in output" "exit $ec, head: $(printf '%s' "$out" | head -3)"
    fi
  fi
fi

# Final
[[ $FAILED -eq 0 ]] || exit 1
exit 0
