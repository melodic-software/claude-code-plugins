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

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
TMP=""
fixture_tree::build TMP --label drive-root-litter

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

export DRIVE_ROOT_LITTER_IGNORE_SINKS=tmp

# --- Fixtures ---------------------------------------------------------------
# A "mount root" is what Git Bash exposes as `/`: every mounted drive appears as
# a single-letter directory under it.

mkdir -p "$TMP/clean/c/data" "$TMP/clean/d/repos" "$TMP/clean/d/worktrees"

# litter: the defect's fingerprint — <drive>:\d\ , a `/d/...` literal resolved
# against the current drive's root instead of against D:.
mkdir -p "$TMP/litter/c/data" "$TMP/litter/d/repos"
mkdir -p "$TMP/litter/d/d/worktrees/harness" "$TMP/litter/c/d/worktrees"

mkdir -p "$TMP/nearmiss/c/data" "$TMP/nearmiss/d/repos"
mkdir -p "$TMP/nearmiss/d/a" "$TMP/nearmiss/d/z" "$TMP/nearmiss/c/q"

mkdir -p "$TMP/nodrives/usr" "$TMP/nodrives/opt"

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

mkdir -p "$TMP/sinkcheckout/c/data" "$TMP/sinkcheckout/c/tmp/work/repo"

mkdir -p "$TMP/both/c/data" "$TMP/both/d/repos" "$TMP/both/c/d" "$TMP/both/d/tmp"

run linux-gnu -
if ((RC == 0)) && grep -qi 'no-op on a non-Windows host' <<<"$OUT"; then
  ok "bare invocation on a POSIX host is a reported no-op (exit 0)"
else
  fail "POSIX host should no-op with a reason: rc=$RC out=$OUT"
fi

run darwin24 "$TMP/litter"
if ((RC == 0)) && grep -qi 'no-op on a non-Windows host' <<<"$OUT"; then
  ok "the mount-root seam does not bypass the non-Windows gate"
else
  fail "seam bypassed the host gate: rc=$RC out=$OUT"
fi

run msys "$TMP/clean"
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  ok "clean drive roots pass (exit 0)"
else
  fail "clean roots should pass: rc=$RC out=$OUT"
fi
if ! grep -q 'worktrees' <<<"$OUT"; then
  ok "multi-character directories at a drive root are ignored"
else
  fail "multi-character directory reported as litter: $OUT"
fi

run msys "$TMP/litter"
if ((RC == 1)); then
  ok "a drive-root directory named for a mounted drive fails (exit 1)"
else
  fail "litter should fail with exit 1: rc=$RC out=$OUT"
fi
if grep -q "$TMP/litter/d/d" <<<"$OUT"; then
  ok "the failure names the offending path"
else
  fail "failure output should name the path: $OUT"
fi
if grep -q "$TMP/litter/c/d" <<<"$OUT"; then
  ok "litter is detected on every drive root, not only the first"
else
  fail "second drive root not scanned: $OUT"
fi
if grep -q 'windows-path-emit' <<<"$OUT"; then
  ok "the failure routes the reader to the owning convention"
else
  fail "failure output should cite the convention doc: $OUT"
fi
if grep -qi 'may have measured something other than what' <<<"$OUT"; then
  ok "the failure names the test-validity cost, not just the litter"
else
  fail "failure output should flag the run's results as suspect: $OUT"
fi
# A phantom tree can hold a REGISTERED worktree. Deleting it first strands the
# registry entry, so the remediation text must send the reader to
# deregistration before removal.
if grep -qi 'registered git worktree' <<<"$OUT"; then
  ok "the remediation warns that the tree may hold a registered worktree"
else
  fail "remediation should warn about a registered worktree before removal: $OUT"
fi
if grep -q 'worktree remove --force' <<<"$OUT"; then
  ok "the remediation names the deregistering command, not a bare delete"
else
  fail "remediation should name 'git worktree remove --force': $OUT"
fi

run msys "$TMP/nearmiss"
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  ok "single-letter directories naming no mounted drive are not litter"
else
  fail "near-miss names should not fire: rc=$RC out=$OUT"
fi

run msys "$TMP/nodrives"
if ((RC == 0)) && grep -q 'no drives found' <<<"$OUT"; then
  ok "a mount root with no drives reports and exits 0"
else
  fail "no-drives root should report and pass: rc=$RC out=$OUT"
fi

OUT="$(cd "$TMP/checkout/d/c/work/repo" && OSTYPE=msys DRIVE_ROOT_LITTER_MOUNT_ROOT="$TMP/checkout" DRIVE_ROOT_LITTER_IGNORE_SINKS='' bash "$SUT" 2>&1)"
RC=$?
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  ok "a drive-root directory containing the cwd is not reported as litter"
else
  fail "cwd-ancestor exclusion failed: rc=$RC out=$OUT"
fi
run msys "$TMP/checkout"
if ((RC == 1)) && grep -q "$TMP/checkout/d/c" <<<"$OUT"; then
  ok "the same directory is litter when it does not contain the cwd"
else
  fail "exclusion suppressed too much: rc=$RC out=$OUT"
fi

run msys "$TMP/sink"
if ((RC == 1)) && grep -q "$TMP/sink/c/tmp" <<<"$OUT"; then
  ok "a drive-root tmp directory fails and is named (exit 1)"
else
  fail "drive-root tmp should fail with exit 1: rc=$RC out=$OUT"
fi
if ! grep -q "$TMP/sink/c/data" <<<"$OUT" && ! grep -q "$TMP/sink/d/repos" <<<"$OUT"; then
  ok "ordinary non-sink directories at a drive root are not reported"
else
  fail "non-sink directory reported as litter: $OUT"
fi
# Windows filesystems fold case, so an uppercase TMP is the same sink.
run msys "$TMP/sinkupper"
if ((RC == 1)) && grep -q "$TMP/sinkupper/c/TMP" <<<"$OUT"; then
  ok "an uppercase drive-root TMP is detected (case-insensitive match)"
else
  fail "uppercase TMP should be detected: rc=$RC out=$OUT"
fi

OUT="$(OSTYPE=msys DRIVE_ROOT_LITTER_MOUNT_ROOT="$TMP/sink" DRIVE_ROOT_LITTER_IGNORE_SINKS=tmp bash "$SUT" 2>&1)"
RC=$?
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  ok "DRIVE_ROOT_LITTER_IGNORE_SINKS=tmp exempts a deliberate drive-root tmp"
else
  fail "sink opt-out should pass: rc=$RC out=$OUT"
fi
OUT="$(OSTYPE=msys DRIVE_ROOT_LITTER_MOUNT_ROOT="$TMP/sink" DRIVE_ROOT_LITTER_IGNORE_SINKS=TMP bash "$SUT" 2>&1)"
RC=$?
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  ok "an uppercase opt-out value (TMP) exempts a lowercase tmp"
else
  fail "uppercase opt-out should exempt: rc=$RC out=$OUT"
fi
OUT="$(OSTYPE=msys DRIVE_ROOT_LITTER_MOUNT_ROOT="$TMP/sinkupper" DRIVE_ROOT_LITTER_IGNORE_SINKS=tmp bash "$SUT" 2>&1)"
RC=$?
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  ok "a lowercase opt-out value exempts an uppercase TMP directory"
else
  fail "opt-out should exempt an uppercase directory: rc=$RC out=$OUT"
fi
OUT="$(OSTYPE=msys DRIVE_ROOT_LITTER_MOUNT_ROOT="$TMP/litter" DRIVE_ROOT_LITTER_IGNORE_SINKS=tmp bash "$SUT" 2>&1)"
RC=$?
if ((RC == 1)); then
  ok "the sink opt-out leaves the single-letter class armed"
else
  fail "sink opt-out suppressed the single-letter class: rc=$RC out=$OUT"
fi

OUT="$(cd "$TMP/sinkcheckout/c/tmp/work/repo" && OSTYPE=msys DRIVE_ROOT_LITTER_MOUNT_ROOT="$TMP/sinkcheckout" DRIVE_ROOT_LITTER_IGNORE_SINKS='' bash "$SUT" 2>&1)"
RC=$?
if ((RC == 0)) && grep -q 'no drive-root litter found' <<<"$OUT"; then
  ok "a drive-root tmp containing the cwd is not reported as litter"
else
  fail "sink cwd-ancestor exclusion failed: rc=$RC out=$OUT"
fi
run msys "$TMP/sinkcheckout"
if ((RC == 1)) && grep -q "$TMP/sinkcheckout/c/tmp" <<<"$OUT"; then
  ok "the same tmp directory is litter when it does not contain the cwd"
else
  fail "sink exclusion suppressed too much: rc=$RC out=$OUT"
fi

run msys "$TMP/both"
if ((RC == 1)) && grep -q "$TMP/both/c/d" <<<"$OUT" && grep -q "$TMP/both/d/tmp" <<<"$OUT"; then
  ok "single-letter and temp-sink hits are reported in one run"
else
  fail "both classes should be reported together: rc=$RC out=$OUT"
fi

run msys "$TMP/clean" --check
if ((RC == 2)) && grep -q 'usage' <<<"$OUT"; then
  ok "an unexpected argument is a usage error (exit 2)"
else
  fail "arguments should exit 2: rc=$RC out=$OUT"
fi

test_harness::report
