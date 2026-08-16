#!/usr/bin/env bash
# Black-box contract test for emit-windows-path.sh.
#
# Self-contained and cwd-independent. The argument handling and the POSIX
# pass-through run on every host (the SUT reads OSTYPE, and an inherited OSTYPE
# survives bash startup, so both host branches are reachable from either).
#
# The CONVERSION itself cannot be faked: it is cygpath's answer on a real
# Windows host. Those cases run only where cygpath exists, and where they do not
# they print a visible NOT EXERCISED line — read that as absence of coverage on
# this host, never as the conversion passing. CI runs this suite on both a Linux
# and a Windows runner precisely so the Windows branch is never green-by-absence
# (the failure mode #2774 recorded for an NT-only allowlist).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/emit-windows-path.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}
note() { printf 'NOT EXERCISED - %s\n' "$1"; }

# run <ostype> [args...] — sets OUT (stdout+stderr) and RC. Not called through a
# command substitution, which would fork a subshell and lose the exit code.
run() {
  local ostype="$1"
  shift
  OUT="$(OSTYPE="$ostype" bash "$SUT" "$@" 2>&1)"
  RC=$?
}

# --- 1. Usage errors --------------------------------------------------------
run msys
if ((RC == 2)) && grep -q 'at least one path' <<<"$OUT"; then
  pass "no arguments is a usage error (exit 2)"
else
  fail "missing path should exit 2: rc=$RC out=$OUT"
fi

run msys --nope /tmp/x
if ((RC == 2)) && grep -q 'unknown option' <<<"$OUT"; then
  pass "an unknown option is a usage error (exit 2)"
else
  fail "unknown option should exit 2: rc=$RC out=$OUT"
fi

run linux-gnu --help
if ((RC == 0)) && grep -q 'usage:' <<<"$OUT"; then
  pass "--help prints usage and exits 0"
else
  fail "--help should exit 0 with usage: rc=$RC out=$OUT"
fi

# --- 2. POSIX host: pass through unchanged, exit 0 --------------------------
run linux-gnu /srv/build/out.zip
if ((RC == 0)) && [[ "$OUT" == "/srv/build/out.zip" ]]; then
  pass "a POSIX host passes the path through unchanged (exit 0)"
else
  fail "POSIX pass-through failed: rc=$RC out=$OUT"
fi

run darwin24 /a/one /b/two
if ((RC == 0)) && [[ "$OUT" == $'/a/one\n/b/two' ]]; then
  pass "a POSIX host passes every argument through, one per line"
else
  fail "POSIX multi-arg pass-through failed: rc=$RC out=$OUT"
fi

# A path that merely LOOKS like an option, after `--`, is a path.
run linux-gnu -- -w
if ((RC == 0)) && [[ "$OUT" == "-w" ]]; then
  pass "-- ends option parsing so an option-shaped path is treated as a path"
else
  fail "-- terminator not honored: rc=$RC out=$OUT"
fi

# --- 3. Windows host without cygpath: FAIL LOUD, never a silent pass-through -
# The whole point of the helper: an emit path must not degrade to the
# unconverted literal, because the unconverted literal is what writes to the
# wrong place. Reachable on any host by emptying PATH for the child.
BASH_ABS="$(command -v bash)"
OUT="$(OSTYPE=msys PATH="$SCRIPT_DIR/__no_such_dir__" "$BASH_ABS" "$SUT" /d/x 2>&1)"
RC=$?
if ((RC == 2)) && grep -q 'cygpath not found' <<<"$OUT"; then
  pass "a Windows host without cygpath exits 2 rather than emitting the input"
else
  fail "missing cygpath should fail loud: rc=$RC out=$OUT"
fi
if ! grep -qx '/d/x' <<<"$OUT"; then
  pass "the unconverted path is never printed on stdout when conversion fails"
else
  fail "unconverted path leaked to output: $OUT"
fi

# --- 4. Real conversion, on a real Windows host -----------------------------
if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* || "${OSTYPE:-}" == win32 ]] &&
  command -v cygpath >/dev/null 2>&1; then
  probe="$(cygpath -m -- / 2>/dev/null)"
  drive="${probe:0:1}"
  if [[ -z "$drive" ]]; then
    fail "cygpath -m / returned nothing; cannot derive this host's drive letter"
  else
    run "$OSTYPE" "/${drive,}/emit-fixture/out.zip"
    expect_m="${drive}:/emit-fixture/out.zip"
    if ((RC == 0)) && [[ "$OUT" == "$expect_m" ]]; then
      pass "an MSYS absolute path converts to mixed form by default (${OUT})"
    else
      fail "mixed-form conversion wrong: rc=$RC out=$OUT want=$expect_m"
    fi

    run "$OSTYPE" -w "/${drive,}/emit-fixture/out.zip"
    expect_w="${drive}:\\emit-fixture\\out.zip"
    if ((RC == 0)) && [[ "$OUT" == "$expect_w" ]]; then
      pass "-w converts to backslash form (${OUT})"
    else
      fail "backslash conversion wrong: rc=$RC out=$OUT want=$expect_w"
    fi

    # The defect this helper prevents, stated as an assertion: the emitted form
    # must NOT be the leading-slash literal a native consumer would re-anchor to
    # the current drive's root.
    if [[ "$OUT" != /* ]]; then
      pass "the emitted path no longer starts with the MSYS root slash"
    else
      fail "emitted path still starts with '/': $OUT"
    fi

    run "$OSTYPE" "/${drive,}/one" "/${drive,}/two"
    if ((RC == 0)) && [[ "$OUT" == "${drive}:/one"$'\n'"${drive}:/two" ]]; then
      pass "every argument is converted, one per line"
    else
      fail "multi-arg conversion wrong: rc=$RC out=$OUT"
    fi

    # A relative path stays relative — the convention's preferred shape must
    # survive the helper rather than being silently absolutized.
    run "$OSTYPE" "sub/dir/out.zip"
    if ((RC == 0)) && [[ "$OUT" == "sub/dir/out.zip" ]]; then
      pass "a relative path survives conversion as a relative path"
    else
      fail "relative path was altered: rc=$RC out=$OUT"
    fi
  fi
else
  note "cygpath conversion cases: this host is not Windows/Git Bash (OSTYPE=${OSTYPE:-unset})"
fi

if ((fails > 0)); then
  printf '\n%d assertion(s) failed.\n' "$fails" >&2
  exit 1
fi
printf '\nAll assertions passed.\n'
