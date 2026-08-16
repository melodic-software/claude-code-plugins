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
run() {
  local ostype="$1" root="$2"
  shift 2
  if [[ "$root" == "-" ]]; then
    OUT="$(OSTYPE="$ostype" bash "$SUT" "$@" 2>&1)"
  else
    OUT="$(OSTYPE="$ostype" DRIVE_ROOT_LITTER_MOUNT_ROOT="$root" bash "$SUT" "$@" 2>&1)"
  fi
  RC=$?
}

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
OUT="$(cd "$TMP/checkout/d/c/work/repo" && OSTYPE=msys DRIVE_ROOT_LITTER_MOUNT_ROOT="$TMP/checkout" bash "$SUT" 2>&1)"
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

# --- 8. Arguments are a usage error -----------------------------------------
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
