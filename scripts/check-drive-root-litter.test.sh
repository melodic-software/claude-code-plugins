#!/usr/bin/env bash
# Black-box contract test for check-drive-root-litter.sh.
#
# Self-contained and cwd-independent: builds throwaway mount-root fixtures,
# points the SUT at them through DRIVE_ROOT_LITTER_MOUNT_ROOT, and asserts on
# exit code + output. Mutates only its own mktemp dir. Runs identically on every
# host: the SUT's Windows branch is reached by exporting a Windows OSTYPE into
# the child shell (an inherited OSTYPE survives bash startup), and the fixture
# supplies the "drives", so a Linux runner exercises the DETECTION logic rather
# than skipping it. The no-op branch is exercised with a POSIX OSTYPE the same
# way, so both directions are covered from either host.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-drive-root-litter.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run <ostype> <mount-root|-> [args...] — sets OUT (stdout+stderr) and RC.
# Deliberately NOT called through a command substitution: that would fork a
# subshell and the exit code would never reach the caller.
#
# HERMETIC against the invoking environment: every env var the SUT reads is set
# explicitly here. DRIVE_ROOT_LITTER_IGNORE_SINKS is a documented operator
# opt-out an operator may export in a shell profile; inherited into these
# invocations it would silently flip the sink-detection assertions into false
# failures unrelated to the code under test. Empty is equivalent to unset for
# both seams (the SUT reads them with ${...:-}). The two opt-out tests set a
# live value per-call, on top of this baseline.
run() {
  local ostype="$1" root="$2"
  shift 2
  [[ "$root" == "-" ]] && root=''
  OUT="$(OSTYPE="$ostype" DRIVE_ROOT_LITTER_MOUNT_ROOT="$root" DRIVE_ROOT_LITTER_IGNORE_SINKS='' bash "$SUT" "$@" 2>&1)"
  RC=$?
}

# Poison the outer environment with the opt-out so the hermeticity above is a
# STANDING assertion, not a comment: if a future invocation forgets to clear
# DRIVE_ROOT_LITTER_IGNORE_SINKS, the sink-detection tests fail loudly right
# here in CI instead of only on an operator's machine.
export DRIVE_ROOT_LITTER_IGNORE_SINKS=tmp

# --- Fixtures ---------------------------------------------------------------
# A "mount root" is what Git Bash exposes as `/`: every mounted drive appears as
# a single-letter directory under it.

# clean: two drives, ordinary contents at each root.
mkdir -p "$TMP/clean/c/data" "$TMP/clean/d/repos" "$TMP/clean/d/worktrees"

# litter: the defect's fingerprint — <drive>:\d\ , a `/d/...` literal resolved
# against the current drive's root instead of against D:.
mkdir -p "$TMP/litter/c/data" "$TMP/litter/d/repos"
mkdir -p "$TMP/litter/d/d/worktrees/harness" "$TMP/litter/c/d/worktrees"

# nearmiss: single-letter directories whose letters are NOT mounted drives.
mkdir -p "$TMP/nearmiss/c/data" "$TMP/nearmiss/d/repos"
mkdir -p "$TMP/nearmiss/d/a" "$TMP/nearmiss/d/z" "$TMP/nearmiss/c/q"

# nodrives: a mount root with nothing single-letter under it at all.
mkdir -p "$TMP/nodrives/usr" "$TMP/nodrives/opt"

# checkout: a repo that genuinely lives under a single-letter drive-root folder.
mkdir -p "$TMP/checkout/c/data" "$TMP/checkout/d/c/work/repo"

# sink: the temp-sink fingerprint — C:\tmp, a POSIX /tmp literal resolved
# against the current drive's root. The inner mktemp-named entry mirrors the
# real instance this class was added for.
mkdir -p "$TMP/sink/c/data" "$TMP/sink/d/repos"
mkdir -p "$TMP/sink/c/tmp/tmp.rSFIkHm5DO"

# sinkupper: the same fingerprint in uppercase — Windows filesystems are
# case-insensitive, so C:\TMP is C:\tmp and must be caught even on the
# case-sensitive filesystem this fixture lives on.
mkdir -p "$TMP/sinkupper/c/data" "$TMP/sinkupper/d/repos" "$TMP/sinkupper/c/TMP"

# sinkcheckout: a repo that genuinely lives under a drive-root tmp folder.
mkdir -p "$TMP/sinkcheckout/c/data" "$TMP/sinkcheckout/c/tmp/work/repo"

# both: single-letter litter AND a temp sink on the same host.
mkdir -p "$TMP/both/c/data" "$TMP/both/d/repos" "$TMP/both/c/d" "$TMP/both/d/tmp"

# --- 1. Non-Windows host: no-op, reported, exit 0 ---------------------------
run linux-gnu -
if ((RC == 0)) && grep -qi 'no-op on a non-Windows host' <<<"$OUT"; then
  pass "bare invocation on a POSIX host is a reported no-op (exit 0)"
else
  fail "POSIX host should no-op with a reason: rc=$RC out=$OUT"
fi

# --- 2. The fixture seam cannot defeat the host gate ------------------------
# That gate is what guarantees a Linux CI runner can never fail this check; a
# seam able to bypass it would put the guarantee at the mercy of an env var.
run darwin24 "$TMP/litter"
if ((RC == 0)) && grep -qi 'no-op on a non-Windows host' <<<"$OUT"; then
  pass "the mount-root seam does not bypass the non-Windows gate"
else
  fail "seam bypassed the host gate: rc=$RC out=$OUT"
fi

# --- 3. Clean drive roots: exit 0 -------------------------------------------
run msys "$TMP/clean"
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  pass "clean drive roots pass (exit 0)"
else
  fail "clean roots should pass: rc=$RC out=$OUT"
fi
if ! grep -q 'worktrees' <<<"$OUT"; then
  pass "multi-character directories at a drive root are ignored"
else
  fail "multi-character directory reported as litter: $OUT"
fi

# --- 4. The fingerprint fires -----------------------------------------------
run msys "$TMP/litter"
if ((RC == 1)); then
  pass "a drive-root directory named for a mounted drive fails (exit 1)"
else
  fail "litter should fail with exit 1: rc=$RC out=$OUT"
fi
if grep -q "$TMP/litter/d/d" <<<"$OUT"; then
  pass "the failure names the offending path"
else
  fail "failure output should name the path: $OUT"
fi
if grep -q "$TMP/litter/c/d" <<<"$OUT"; then
  pass "litter is detected on every drive root, not only the first"
else
  fail "second drive root not scanned: $OUT"
fi
if grep -q 'windows-path-emit' <<<"$OUT"; then
  pass "the failure routes the reader to the owning convention"
else
  fail "failure output should cite the convention doc: $OUT"
fi
if grep -qi 'may have measured something other than what' <<<"$OUT"; then
  pass "the failure names the test-validity cost, not just the litter"
else
  fail "failure output should flag the run's results as suspect: $OUT"
fi
# A phantom tree can hold a REGISTERED worktree — that is what the first real
# hit on this machine was (#2870). Deleting it first strands the registry entry,
# so the remediation text must send the reader to deregistration before removal.
if grep -qi 'registered git worktree' <<<"$OUT"; then
  pass "the remediation warns that the tree may hold a registered worktree"
else
  fail "remediation should warn about a registered worktree before removal: $OUT"
fi
if grep -q 'worktree remove --force' <<<"$OUT"; then
  pass "the remediation names the deregistering command, not a bare delete"
else
  fail "remediation should name 'git worktree remove --force': $OUT"
fi

# --- 5. Precision: a single letter that is not a mounted drive --------------
run msys "$TMP/nearmiss"
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  pass "single-letter directories naming no mounted drive are not litter"
else
  fail "near-miss names should not fire: rc=$RC out=$OUT"
fi

# --- 6. A mount root with no drives -----------------------------------------
run msys "$TMP/nodrives"
if ((RC == 0)) && grep -q 'no drives found' <<<"$OUT"; then
  pass "a mount root with no drives reports and exits 0"
else
  fail "no-drives root should report and pass: rc=$RC out=$OUT"
fi

# --- 7. A candidate containing the cwd is a checkout, not litter -------------
OUT="$(cd "$TMP/checkout/d/c/work/repo" && OSTYPE=msys DRIVE_ROOT_LITTER_MOUNT_ROOT="$TMP/checkout" DRIVE_ROOT_LITTER_IGNORE_SINKS='' bash "$SUT" 2>&1)"
RC=$?
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  pass "a drive-root directory containing the cwd is not reported as litter"
else
  fail "cwd-ancestor exclusion failed: rc=$RC out=$OUT"
fi
# ... and the same tree IS litter from elsewhere, so the exclusion is narrow
# rather than a blanket suppression.
run msys "$TMP/checkout"
if ((RC == 1)) && grep -q "$TMP/checkout/d/c" <<<"$OUT"; then
  pass "the same directory is litter when it does not contain the cwd"
else
  fail "exclusion suppressed too much: rc=$RC out=$OUT"
fi

# --- 8. Temp-sink class: a drive-root tmp fires ------------------------------
run msys "$TMP/sink"
if ((RC == 1)) && grep -q "$TMP/sink/c/tmp" <<<"$OUT"; then
  pass "a drive-root tmp directory fails and is named (exit 1)"
else
  fail "drive-root tmp should fail with exit 1: rc=$RC out=$OUT"
fi
if ! grep -q "$TMP/sink/c/data" <<<"$OUT" && ! grep -q "$TMP/sink/d/repos" <<<"$OUT"; then
  pass "ordinary non-sink directories at a drive root are not reported"
else
  fail "non-sink directory reported as litter: $OUT"
fi
# Windows filesystems fold case, so an uppercase TMP is the same sink.
run msys "$TMP/sinkupper"
if ((RC == 1)) && grep -q "$TMP/sinkupper/c/TMP" <<<"$OUT"; then
  pass "an uppercase drive-root TMP is detected (case-insensitive match)"
else
  fail "uppercase TMP should be detected: rc=$RC out=$OUT"
fi

# --- 9. Temp-sink opt-out ----------------------------------------------------
OUT="$(OSTYPE=msys DRIVE_ROOT_LITTER_MOUNT_ROOT="$TMP/sink" DRIVE_ROOT_LITTER_IGNORE_SINKS=tmp bash "$SUT" 2>&1)"
RC=$?
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  pass "DRIVE_ROOT_LITTER_IGNORE_SINKS=tmp exempts a deliberate drive-root tmp"
else
  fail "sink opt-out should pass: rc=$RC out=$OUT"
fi
# ... in any casing, both of the opt-out value and of the directory.
OUT="$(OSTYPE=msys DRIVE_ROOT_LITTER_MOUNT_ROOT="$TMP/sink" DRIVE_ROOT_LITTER_IGNORE_SINKS=TMP bash "$SUT" 2>&1)"
RC=$?
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  pass "an uppercase opt-out value (TMP) exempts a lowercase tmp"
else
  fail "uppercase opt-out should exempt: rc=$RC out=$OUT"
fi
OUT="$(OSTYPE=msys DRIVE_ROOT_LITTER_MOUNT_ROOT="$TMP/sinkupper" DRIVE_ROOT_LITTER_IGNORE_SINKS=tmp bash "$SUT" 2>&1)"
RC=$?
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  pass "a lowercase opt-out value exempts an uppercase TMP directory"
else
  fail "opt-out should exempt an uppercase directory: rc=$RC out=$OUT"
fi
# ... and the opt-out does not bleed into the single-letter class.
OUT="$(OSTYPE=msys DRIVE_ROOT_LITTER_MOUNT_ROOT="$TMP/litter" DRIVE_ROOT_LITTER_IGNORE_SINKS=tmp bash "$SUT" 2>&1)"
RC=$?
if ((RC == 1)); then
  pass "the sink opt-out leaves the single-letter class armed"
else
  fail "sink opt-out suppressed the single-letter class: rc=$RC out=$OUT"
fi

# --- 10. A drive-root tmp containing the cwd is a checkout, not litter --------
OUT="$(cd "$TMP/sinkcheckout/c/tmp/work/repo" && OSTYPE=msys DRIVE_ROOT_LITTER_MOUNT_ROOT="$TMP/sinkcheckout" DRIVE_ROOT_LITTER_IGNORE_SINKS='' bash "$SUT" 2>&1)"
RC=$?
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  pass "a drive-root tmp containing the cwd is not reported as litter"
else
  fail "sink cwd-ancestor exclusion failed: rc=$RC out=$OUT"
fi
# ... and the same tree IS litter from elsewhere.
run msys "$TMP/sinkcheckout"
if ((RC == 1)) && grep -q "$TMP/sinkcheckout/c/tmp" <<<"$OUT"; then
  pass "the same tmp directory is litter when it does not contain the cwd"
else
  fail "sink exclusion suppressed too much: rc=$RC out=$OUT"
fi

# --- 11. Both classes report together ----------------------------------------
run msys "$TMP/both"
if ((RC == 1)) && grep -q "$TMP/both/c/d" <<<"$OUT" && grep -q "$TMP/both/d/tmp" <<<"$OUT"; then
  pass "single-letter and temp-sink hits are reported in one run"
else
  fail "both classes should be reported together: rc=$RC out=$OUT"
fi

# --- 12. Arguments are a usage error -----------------------------------------
run msys "$TMP/clean" --check
if ((RC == 2)) && grep -q 'usage' <<<"$OUT"; then
  pass "an unexpected argument is a usage error (exit 2)"
else
  fail "arguments should exit 2: rc=$RC out=$OUT"
fi

if ((fails > 0)); then
  printf '\n%d assertion(s) failed.\n' "$fails" >&2
  exit 1
fi
printf '\nAll assertions passed.\n'
