#!/usr/bin/env bash
# Black-box contract test for install-python-deps.sh (the explainer-video SessionStart hook).
#
# Proves the install flow end to end against a local wheel (pip's PIP_NO_INDEX and PIP_FIND_LINKS,
# so nothing reaches a package index): the first session installs the hash-locked set into
# CLAUDE_PLUGIN_DATA silently, the second session is a no-op, and a failed install is a notice
# on both channels carrying the repair line. The hook runs from a copy of the plugin's hooks and
# scripts directories with a fixture lock, so the real ManimCE lock is never installed.

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

# The hook's pydeps.py hands over to the first Python 3.12 or 3.13 on PATH, so the install path needs one.
py=""
for candidate in python3.13 python3.12 python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; raise SystemExit(sys.version_info[:2] not in ((3, 12), (3, 13)))' 2>/dev/null &&
    "$candidate" -m pip --version >/dev/null 2>&1; then
    py="$candidate"
    break
  fi
done
if [[ -z "$py" ]]; then
  echo "SKIP: Python 3.12 or 3.13 with pip not found -- install-python-deps hook tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
cleanup() { rm -rf "${WORK:?}"; }
trap cleanup EXIT

native() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

WHEELS="$WORK/wheels"
EMPTY="$WORK/empty"
mkdir -p "$WHEELS" "$EMPTY"
digest="$("$py" "$PLUGIN_DIR/scripts/test_explainer_video_pydeps.py" --make-wheel "$(native "$WHEELS")")" || {
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

# A handed-over child that dies at startup: the traceback's last line and a repair line, not the dump.
root="$(new_plugin crash "$digest")"
cat >"$root/scripts/pydeps.py" <<'EOF'
import sys
sys.stderr.write('Traceback (most recent call last):\n  File "pydeps.py", line 24, in <module>\n    import subprocess\n'
                 "AttributeError: 'sys.flags' object has no attribute 'context_aware_warnings'\n")
sys.exit(1)
EOF
data="$WORK/data-crash"
run_hook "$root" "$WHEELS" CLAUDE_PLUGIN_DATA="$(native "$data")"
out="$OUT"
if [[ "$RC" -eq 0 && "$out" == *'"systemMessage"'* && "$out" == *'"additionalContext"'* &&
  "$out" == *"the Python handover failed: AttributeError: 'sys.flags' object has no attribute 'context_aware_warnings'; repair with: "*"pydeps.py"*"install"*"--data-dir"* &&
  "$out" != *Traceback* ]]; then
  ok "a crashed handover surfaces the traceback's last line and a repair line, not the traceback"
else
  fail "crashed handover: rc=$RC output=[$out]"
fi

# The repair line is shell-quoted: a data directory with a space and a single quote re-parses to the same arguments.
# The Git Bash and Cygwin branch prints a PowerShell line instead, which no POSIX shell re-parses.
case "${OSTYPE:-}" in
msys* | cygwin*) ;;
*)
  data="$WORK/data o'brien/x y"
  run_hook "$root" "$WHEELS" CLAUDE_PLUGIN_DATA="$data"
  out="$OUT"
  repair="$("$py" -c 'import json, sys; print(json.loads(sys.stdin.read())["systemMessage"].split("repair with: ", 1)[1], end="")' <<<"$out")"
  got="$(eval "set -- $repair" && printf '%s|%s|%s|%s|%s|%s' "$#" "$([[ -x "$1" ]] && echo exec)" "$2" "$3" "$4" "$5")"
  if [[ "$got" == "5|exec|$root/scripts/pydeps.py|install|--data-dir|$data" ]]; then
    ok "the repair line re-parses to the interpreter and a data directory holding a space and a single quote"
  else
    fail "repair line round-trip: repair=[$repair] got=[$got]"
  fi
  ;;
esac

# No data directory (a host that sets none): nothing to install into, no output.
root="$(new_plugin nodata "$digest")"
run_hook "$root" "$WHEELS" CLAUDE_PLUGIN_DATA=
out="$OUT"
if [[ "$RC" -eq 0 && -z "$out" ]]; then
  ok "no CLAUDE_PLUGIN_DATA is a silent no-op"
else
  fail "no data dir: rc=$RC output=[$out]"
fi

# No Python on PATH: a notice naming the supported versions, not a silent skip.
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
if [[ "$rc" -eq 0 && "$out" == *'"systemMessage"'* && "$out" == *'Python 3.12 or 3.13 was not found'* ]]; then
  ok "no Python on PATH surfaces a notice naming the supported versions"
else
  fail "no python: rc=$rc output=[$out]"
fi

# Only the py launcher (a python.org install without "Add python.exe to PATH"): under Git Bash or Cygwin the
# hook asks it only to list (py -0p) and starts pydeps.py with a listed python.exe, never through py, which
# installs the latest Python on any launch command while none is installed; elsewhere `py` is not taken for Python.
# The stub py logs its arguments and prints $WORK/listing with CRLF line ends; the stub cygpath maps a listed
# Windows path to $WORK/stub/<file name>, ahead of a real one.
launcher="$WORK/launcher"
mkdir -p "$launcher" "$WORK/stub"
{
  printf '#!/bin/sh\nWORK="%s"\n' "$WORK"
  cat <<'EOF'
printf '%s\n' "$*" >>"$WORK/py.log"
awk '{ printf "%s\r\n", $0 }' "$WORK/listing"
EOF
} >"$launcher/py"
{
  printf '#!/bin/sh\nWORK="%s"\n' "$WORK"
  cat <<'EOF'
case "$1" in
-u) printf '%s\n' "$WORK/stub/${2##*\\}" ;;
*) printf '%s\n' "$2" ;;
esac
EOF
} >"$launcher/cygpath"
for exe in python.exe python3.13t.exe python3.14.exe; do
  printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >>"%s/started.log"\n' "$exe" "$WORK" >"$WORK/stub/$exe"
done
chmod +x "$launcher/py" "$launcher/cygpath" "$WORK/stub/"*
root="$(new_plugin launcher "$digest")"
# launcher_hook <<listing -> runs the hook under OSTYPE=msys with only the stub py listing stdin; sets OUT, RC, PYLOG
# and STARTED.
launcher_hook() {
  cat >"$WORK/listing"
  rm -f "$WORK/py.log" "$WORK/started.log"
  OUT="$(env PATH="$launcher:$tools" OSTYPE=msys CLAUDE_PLUGIN_DATA="$(native "$WORK/data-launcher")" "$tools/bash" "$root/hooks/install-python-deps.sh" <<<'{}')"
  RC=$?
  PYLOG="$(tr '\n' '|' <"$WORK/py.log" 2>/dev/null)"
  STARTED="$(cat "$WORK/started.log" 2>/dev/null)"
}
launcher_hook <<<'No installed Pythons found!'
if [[ "$RC" -eq 0 && "$PYLOG" == '-0p|' && -z "$STARTED" && "$OUT" == *'Python 3.12 or 3.13 was not found'* ]]; then
  ok "under Git Bash, a py launcher that lists no runtime only lists and the hook gives the missing-Python notice"
else
  fail "py launcher, no runtime: rc=$RC py=[$PYLOG] started=[$STARTED] output=[$OUT]"
fi
launcher_hook <<'EOF'
 -V:3.14 *        C:\Py\python3.14.exe
 -V:3.13t         C:\Py\python3.13t.exe
 -V:3.13          C:\Py\python.exe
EOF
if [[ "$RC" -eq 0 && -z "$OUT" && "$PYLOG" == '-0p|' &&
  "$STARTED" == "python.exe $root/scripts/pydeps.py install --data-dir "* ]]; then
  ok "under Git Bash, the hook starts pydeps.py install with the listed regular 3.13 python.exe, not through py"
else
  fail "py launcher, 3.13 listed: rc=$RC py=[$PYLOG] started=[$STARTED] output=[$OUT]"
fi
launcher_hook <<'EOF'
 -V:3.14 *        C:\Py\python3.14.exe
EOF
if [[ "$RC" -eq 0 && "$PYLOG" == '-0p|' && "$STARTED" == "python3.14.exe $root/scripts/pydeps.py install --data-dir "* ]]; then
  ok "under Git Bash, with no 3.12 or 3.13 listed the hook starts pydeps.py with the listed one, which says what is required"
else
  fail "py launcher, only 3.14 listed: rc=$RC py=[$PYLOG] started=[$STARTED] output=[$OUT]"
fi
rm -f "$WORK/py.log"
out="$(env PATH="$tools:$launcher" OSTYPE=linux-gnu CLAUDE_PLUGIN_DATA="$(native "$WORK/data-launcher")" "$tools/bash" "$root/hooks/install-python-deps.sh" <<<'{}')"
rc=$?
if [[ "$rc" -eq 0 && "$out" == *'Python 3.12 or 3.13 was not found'* && ! -e "$WORK/py.log" ]]; then
  ok "outside Git Bash and Cygwin a py on PATH is not used"
else
  fail "py outside Windows: rc=$rc output=[$out]"
fi

echo "---"
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
