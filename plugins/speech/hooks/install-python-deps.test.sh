#!/usr/bin/env bash
# Black-box contract test for install-python-deps.sh (the speech SessionStart hook).
#
# Proves the install flow end to end against a local wheel (pip's PIP_NO_INDEX and PIP_FIND_LINKS,
# so nothing reaches a package index): the first session installs the hash-locked set into
# CLAUDE_PLUGIN_DATA silently, the second session is a no-op, and a failed install is a notice
# on both channels carrying the repair line. The hook runs from a copy of the plugin's hooks and
# scripts directories with a fixture lock, so the real numpy and onnxruntime lock is never installed.

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
digest="$("$py" "$PLUGIN_DIR/scripts/test_speech_pydeps.py" --make-wheel "$(native "$WHEELS")")" || {
  echo "FAIL: could not build the fixture wheel" >&2
  exit 1
}

# new_plugin <name> <digest> -> a plugin root holding the hook, its libs, pydeps.py and a lock for the fixture wheel.
new_plugin() {
  local root="$WORK/$1"
  mkdir -p "$root/hooks" "$root/scripts"
  cp "$HOOK_DIR/install-python-deps.sh" "$HOOK_DIR/install-python-deps.conf" "$HOOK_DIR/hook-utils.sh" "$root/hooks/"
  cp "$PLUGIN_DIR/scripts/pydeps.py" "$PLUGIN_DIR/scripts/pydeps.json" "$root/scripts/"
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

# A failed install (wrong hash): a user notice with the reason and the repair line, exit 0, nothing left.
# Nothing reaches the model: pydeps.py run prints the repair line when a skill runs.
root="$(new_plugin bad "$(printf '0%.0s' {1..64})")"
data="$WORK/data-bad"
run_hook "$root" "$WHEELS" CLAUDE_PLUGIN_DATA="$(native "$data")"
out="$OUT"
if [[ "$RC" -eq 0 && "$out" == *'"systemMessage"'* && "$out" != *'"additionalContext"'* &&
  "$out" == *'not installed; '* && "$out" == *'pip install --require-hashes failed'* &&
  "$out" == *'Repair with:'* && "$(installs "$data")" == 0 ]]; then
  ok "a failed install surfaces a user notice with the repair line and installs nothing"
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
if [[ "$rc" -eq 0 && "$out" == *'"systemMessage"'* && "$out" != *'"additionalContext"'* && "$out" == *'Python 3.12 or later was not found'* ]]; then
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

# The ready stamp: pydeps.py install, started through a candidate found on PATH, writes <data>/python/.hook-ready,
# and while it holds a session start starts no Python. Every candidate name resolves to a wrapper that logs each start
# and execs the real interpreter. Each case restores the stamp that install wrote, shows that baseline starts nothing,
# changes one input and shows the full path runs.
logged="$WORK/logged"
other="$WORK/other"
mkdir -p "$logged" "$other"
real_py="$(command -v "$py")"
for name in python3.13 python3.12 python3 python; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/starts.log"\nexec "%s" "$@"\n' "$name" "$WORK" "$real_py" >"$logged/$name"
done
cp "$logged/python3.13" "$other/python3.13"
chmod +x "$logged/"* "$other/"*
root="$(new_plugin stamped "$digest")"
data="$WORK/data-stamped"
stamp="$data/python/.hook-ready"
# stamp_run <plugin root> <find-links dir> [PATH prefix] -> runs the hook with the wrappers first on PATH; sets OUT, RC
# and STARTS, the number of Python starts.
stamp_run() {
  rm -f "$WORK/starts.log"
  run_hook "$1" "$2" CLAUDE_PLUGIN_DATA="$(native "$data")" PATH="${3:-}$logged:$PATH"
  STARTS=0
  [[ -f "$WORK/starts.log" ]] && STARTS="$(wc -l <"$WORK/starts.log" | tr -d '[:space:]')"
}
stamp_run "$root" "$WHEELS"
if [[ "$RC" -eq 0 && -z "$OUT" && -f "$stamp" ]]; then
  ok "an install through a candidate on PATH writes the ready stamp"
else
  fail "ready stamp write: rc=$RC stamp=$([[ -f "$stamp" ]] && echo yes || echo no) output=[$OUT]"
fi
cp "$stamp" "$WORK/good-stamp" 2>/dev/null
# restore_stamp -> the stamp the install wrote, newer than every input it checks.
restore_stamp() {
  cp "$WORK/good-stamp" "$stamp"
  touch -t 202001010000 "$root/requirements.txt" "$root/scripts/pydeps.py" "$root/scripts/pydeps.json" "$logged/"* "$other/"*
  touch -t 202101010000 "$stamp"
}
# invalidated <what> <mutation command ...> -> the baseline starts no Python; after the mutation the hook starts one.
invalidated() {
  local what="$1" base
  shift
  restore_stamp
  stamp_run "$root" "$WHEELS"
  base="$STARTS/$RC/[$OUT]"
  "$@"
  if [[ "$base" == "0/0/[]" && "$STARTS" -gt 0 && "$RC" -eq 0 ]]; then
    ok "while the ready stamp holds no Python starts; $what runs the full path"
  else
    fail "$what: baseline starts/rc/output=$base, after: starts=$STARTS rc=$RC output=[$OUT]"
  fi
}
moved_root() {
  mv "$root" "$root-moved"
  stamp_run "$root-moved" "$WHEELS"
  mv "$root-moved" "$root"
}
other_candidate() { stamp_run "$root" "$WHEELS" "$other:"; }
newer() {
  touch "$1"
  stamp_run "$root" "$WHEELS"
}
target_missing() {
  find "$data/python" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +
  stamp_run "$root" "$WHEELS"
}
invalidated "another plugin root" moved_root
invalidated "a candidate resolving elsewhere" other_candidate
invalidated "a resolved candidate newer than the stamp" newer "$logged/python3"
invalidated "a newer requirements.txt" newer "$root/requirements.txt"
invalidated "a newer pydeps.py" newer "$root/scripts/pydeps.py"
invalidated "a newer pydeps.json" newer "$root/scripts/pydeps.json"
invalidated "a missing installed set" target_missing

echo "---"
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
