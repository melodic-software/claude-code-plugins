#!/usr/bin/env bash
# Black-box contract test for install-python-deps.sh (the animation SessionStart hook).
#
# Proves the install flow end to end against a local wheel (pip's PIP_NO_INDEX and PIP_FIND_LINKS,
# so nothing reaches a package index): the first session installs the hash-locked set into
# CLAUDE_PLUGIN_DATA silently, the second session is a no-op, and a failed install is a notice
# on both channels carrying the repair line. The hook runs from a copy of the plugin's hooks and
# scripts directories with a fixture lock, so the real numpy and opencv lock is never installed.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="${HOOK_DIR%/*}"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

py=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 12))' 2>/dev/null &&
    "$candidate" -m pip --version >/dev/null 2>&1; then
    py="$candidate"
    break
  fi
done
if [[ -z "$py" ]]; then
  echo "SKIP: Python 3.12 or later with pip not found -- install-python-deps hook tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
cleanup() { rm -rf "${WORK:?}"; }
trap cleanup EXIT

native() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

WHEELS="$WORK/wheels"
EMPTY="$WORK/empty"
mkdir -p "$WHEELS" "$EMPTY"
digest="$("$py" "$PLUGIN_DIR/scripts/test_pydeps.py" --make-wheel "$(native "$WHEELS")")" || {
  echo "FAIL: could not build the fixture wheel" >&2
  exit 1
}

# new_plugin <name> <digest> -> a plugin root holding the hook, its libs, pydeps.py and a lock for the fixture wheel.
new_plugin() {
  local root="$WORK/$1"
  mkdir -p "$root/hooks" "$root/scripts"
  cp "$HOOK_DIR/install-python-deps.sh" "$HOOK_DIR/hook-utils.sh" "$root/hooks/"
  cp "$PLUGIN_DIR/scripts/pydeps.py" "$root/scripts/"
  printf 'fakedeps==1.0 \\\n    --hash=sha256:%s\n' "$2" >"$root/requirements.txt"
  printf '%s' "$root"
}

# run_hook <plugin root> <find-links dir> [NAME=VALUE ...] -> sets $OUT to the hook's stdout and $RC to its exit code.
run_hook() {
  local root="$1" links="$2"
  shift 2
  OUT="$(env PIP_NO_INDEX=1 PIP_FIND_LINKS="$(native "$links")" "$@" bash "$root/hooks/install-python-deps.sh" <<<'{"hook_event_name":"SessionStart"}')"
  RC=$?
}

installs() { find "$1/python" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d '[:space:]'; }

# First session: installs, says nothing.
root="$(new_plugin first "$digest")"
data="$WORK/data-first"
run_hook "$root" "$WHEELS" CLAUDE_PLUGIN_DATA="$(native "$data")"
out="$OUT"
if [[ "$RC" -eq 0 && -z "$out" && "$(installs "$data")" == 1 ]]; then
  ok "first session installs the locked set into CLAUDE_PLUGIN_DATA silently"
else
  fail "first session: rc=$RC installs=$(installs "$data") output=[$out]"
fi

# Second session: no-op. An empty find-links folder would make any pip run fail, so a notice means it ran.
run_hook "$root" "$EMPTY" CLAUDE_PLUGIN_DATA="$(native "$data")"
out="$OUT"
if [[ "$RC" -eq 0 && -z "$out" && "$(installs "$data")" == 1 ]]; then
  ok "second session is a silent no-op"
else
  fail "second session: rc=$RC installs=$(installs "$data") output=[$out]"
fi

# A failed install (wrong hash): a notice on both channels with the reason and the repair line, exit 0, nothing left.
root="$(new_plugin bad "$(printf '0%.0s' {1..64})")"
data="$WORK/data-bad"
run_hook "$root" "$WHEELS" CLAUDE_PLUGIN_DATA="$(native "$data")"
out="$OUT"
if [[ "$RC" -eq 0 && "$out" == *'"systemMessage"'* && "$out" == *'"additionalContext"'* &&
  "$out" == *'could not be installed'* && "$out" == *'pip install --require-hashes failed'* &&
  "$out" == *'Repair with:'* && "$(installs "$data")" == 0 ]]; then
  ok "a failed install surfaces a notice on both channels with the repair line and installs nothing"
else
  fail "failed install: rc=$RC installs=$(installs "$data") output=[$out]"
fi

# No data directory (a host that sets none): nothing to install into, no output.
root="$(new_plugin nodata "$digest")"
run_hook "$root" "$WHEELS" CLAUDE_PLUGIN_DATA=
out="$OUT"
if [[ "$RC" -eq 0 && -z "$out" ]]; then
  ok "no CLAUDE_PLUGIN_DATA is a silent no-op"
else
  fail "no data dir: rc=$RC output=[$out]"
fi

# No Python on PATH: a notice naming the floor, not a silent skip.
tools="$WORK/tools"
mkdir -p "$tools"
for t in bash cat dirname basename env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink date; do
  real="$(command -v "$t" 2>/dev/null)" || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real" >"$tools/$t"
  chmod +x "$tools/$t"
done
root="$(new_plugin nopython "$digest")"
out="$(env PATH="$tools" CLAUDE_PLUGIN_DATA="$(native "$WORK/data-nopython")" "$tools/bash" "$root/hooks/install-python-deps.sh" <<<'{}')"
rc=$?
if [[ "$rc" -eq 0 && "$out" == *'"systemMessage"'* && "$out" == *'Python 3.12 or later was not found'* ]]; then
  ok "no Python 3.12 on PATH surfaces a notice naming the floor"
else
  fail "no python: rc=$rc output=[$out]"
fi

# Native Windows Python under Git Bash or Cygwin: pydeps.py and a POSIX data directory reach it as drive-letter
# paths even with MSYS path conversion switched off, and a cygpath that fails is a notice, never the unconverted
# path. The stub python3 logs its arguments; the stub cygpath maps -m /dir to C:/dir, or fails.
# native_hook <ostype> <cygpath body> -> runs the hook with MSYS_NO_PATHCONV=1 and a POSIX data directory; sets OUT,
# RC and ARGV.
# shellcheck disable=SC2016  # the stub bodies expand when the stubs run, not here
native_hook() {
  local stubs="$WORK/stubs-$1"
  mkdir -p "$stubs"
  printf '#!/bin/sh\n[ "$1" = -c ] && exit 0\nprintf "%%s|" "$@" >"%s/argv.log"\n' "$WORK" >"$stubs/python3"
  printf '#!/bin/sh\n%s\n' "$2" >"$stubs/cygpath"
  chmod +x "$stubs/python3" "$stubs/cygpath"
  rm -f "$WORK/argv.log"
  OUT="$(env PATH="$stubs:$tools" OSTYPE="$1" MSYS_NO_PATHCONV=1 CLAUDE_PLUGIN_DATA="$WORK/data-native" "$tools/bash" "$root/hooks/install-python-deps.sh" <<<'{}')"
  RC=$?
  ARGV="$(cat "$WORK/argv.log" 2>/dev/null)"
}
# shellcheck disable=SC2016  # the stub body expands when the stub runs, not here
for ostype in msys cygwin; do
  native_hook "$ostype" '[ "$1" = -m ] && printf "C:%s\n" "$2"'
  if [[ "$RC" -eq 0 && -z "$OUT" && "$ARGV" == "C:$root/scripts/pydeps.py|install|--data-dir|C:$WORK/data-native|" ]]; then
    ok "OSTYPE=$ostype with path conversion off hands Python drive-letter pydeps.py and data directory paths"
  else
    fail "OSTYPE=$ostype conversion: rc=$RC argv=[$ARGV] output=[$OUT]"
  fi
done
native_hook msys 'exit 1'
if [[ "$RC" -eq 0 && -z "$ARGV" && "$OUT" == *'"systemMessage"'* && "$OUT" == *'cygpath could not convert'* ]]; then
  ok "a failing cygpath is a notice and Python never gets the unconverted path"
else
  fail "failing cygpath: rc=$RC argv=[$ARGV] output=[$OUT]"
fi
native_hook linux-gnu 'exit 1'
if [[ "$RC" -eq 0 && -z "$OUT" && "$ARGV" == "$root/scripts/pydeps.py|install|--data-dir|$WORK/data-native|" ]]; then
  ok "outside Git Bash and Cygwin the paths reach Python unchanged"
else
  fail "linux paths: rc=$RC argv=[$ARGV] output=[$OUT]"
fi

echo "---"
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
