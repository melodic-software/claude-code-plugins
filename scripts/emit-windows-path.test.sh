#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/emit-windows-path.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"

note() { printf 'NOT EXERCISED - %s\n' "$1"; }

run() {
  local ostype="$1"
  shift
  OUT="$(OSTYPE="$ostype" bash "$SUT" "$@" 2>&1)"
  RC=$?
}

run msys
if ((RC == 2)) && grep -q 'at least one path' <<<"$OUT"; then
  ok "no arguments is a usage error (exit 2)"
else
  fail "missing path should exit 2: rc=$RC out=$OUT"
fi

run msys --nope /tmp/x
if ((RC == 2)) && grep -q 'unknown option' <<<"$OUT"; then
  ok "an unknown option is a usage error (exit 2)"
else
  fail "unknown option should exit 2: rc=$RC out=$OUT"
fi

run linux-gnu --help
if ((RC == 0)) && grep -q 'usage:' <<<"$OUT"; then
  ok "--help prints usage and exits 0"
else
  fail "--help should exit 0 with usage: rc=$RC out=$OUT"
fi
for opt in -m --mixed -w --backslash; do
  if grep -q -- "$opt" <<<"$OUT"; then
    ok "the usage banner documents $opt"
  else
    fail "usage banner omits an accepted option ($opt): $OUT"
  fi
done
for opt in -m --mixed; do
  run linux-gnu "$opt" /srv/build/out.zip
  if ((RC == 0)) && [[ "$OUT" == "/srv/build/out.zip" ]]; then
    ok "$opt is accepted as the mixed-form selector"
  else
    fail "$opt rejected or mishandled: rc=$RC out=$OUT"
  fi
done

run linux-gnu /srv/build/out.zip
if ((RC == 0)) && [[ "$OUT" == "/srv/build/out.zip" ]]; then
  ok "a POSIX host passes the path through unchanged (exit 0)"
else
  fail "POSIX pass-through failed: rc=$RC out=$OUT"
fi

run darwin24 /a/one /b/two
if ((RC == 0)) && [[ "$OUT" == $'/a/one\n/b/two' ]]; then
  ok "a POSIX host passes every argument through, one per line"
else
  fail "POSIX multi-arg pass-through failed: rc=$RC out=$OUT"
fi

run linux-gnu -- -w
if ((RC == 0)) && [[ "$OUT" == "-w" ]]; then
  ok "-- ends option parsing so an option-shaped path is treated as a path"
else
  fail "-- terminator not honored: rc=$RC out=$OUT"
fi

BASH_ABS="$(command -v bash)"
OUT="$(OSTYPE=msys PATH="$SCRIPT_DIR/__no_such_dir__" "$BASH_ABS" "$SUT" /d/x 2>&1)"
RC=$?
if ((RC == 2)) && grep -q 'cygpath not found' <<<"$OUT"; then
  ok "a Windows host without cygpath exits 2 rather than emitting the input"
else
  fail "missing cygpath should fail loud: rc=$RC out=$OUT"
fi
if ! grep -qx '/d/x' <<<"$OUT"; then
  ok "the unconverted path is never printed on stdout when conversion fails"
else
  fail "unconverted path leaked to output: $OUT"
fi

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
      ok "an MSYS absolute path converts to mixed form by default (${OUT})"
    else
      fail "mixed-form conversion wrong: rc=$RC out=$OUT want=$expect_m"
    fi

    run "$OSTYPE" -w "/${drive,}/emit-fixture/out.zip"
    expect_w="${drive}:\\emit-fixture\\out.zip"
    if ((RC == 0)) && [[ "$OUT" == "$expect_w" ]]; then
      ok "-w converts to backslash form (${OUT})"
    else
      fail "backslash conversion wrong: rc=$RC out=$OUT want=$expect_w"
    fi

    if [[ "$OUT" != /* ]]; then
      ok "the emitted path no longer starts with the MSYS root slash"
    else
      fail "emitted path still starts with '/': $OUT"
    fi

    run "$OSTYPE" "/${drive,}/one" "/${drive,}/two"
    if ((RC == 0)) && [[ "$OUT" == "${drive}:/one"$'\n'"${drive}:/two" ]]; then
      ok "every argument is converted, one per line"
    else
      fail "multi-arg conversion wrong: rc=$RC out=$OUT"
    fi

    run "$OSTYPE" "sub/dir/out.zip"
    if ((RC == 0)) && [[ "$OUT" == "sub/dir/out.zip" ]]; then
      ok "a relative path survives conversion as a relative path"
    else
      fail "relative path was altered: rc=$RC out=$OUT"
    fi
  fi
else
  note "cygpath conversion cases: this host is not Windows/Git Bash (OSTYPE=${OSTYPE:-unset})"
fi

test_harness::report
