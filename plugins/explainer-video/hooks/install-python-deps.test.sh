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
# Nothing reaches the model: pydeps.py run prints the repair line when the skill runs.
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
if [[ "$RC" -eq 0 && "$out" == *'"systemMessage"'* && "$out" != *'"additionalContext"'* &&
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
if [[ "$rc" -eq 0 && "$out" == *'"systemMessage"'* && "$out" != *'"additionalContext"'* && "$out" == *'Python 3.12 or 3.13 was not found'* ]]; then
  ok "no Python on PATH surfaces a notice naming the supported versions"
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

# Under Git Bash, Windows Python writes the stamp with backslashes, its own letter case and .EXE suffixes, while the
# hook sees POSIX paths without them. A stamp in that shape holds under OSTYPE=msys and, paired, not elsewhere.
# windows_form <path> -> the path with backslashes; upper-cased with .EXE appended when a second argument is given.
windows_form() {
  local p="${1//\//\\}"
  [[ -n "${2:-}" && -n "$p" ]] && p="${p^^}.EXE"
  printf '%s' "$p"
}
target="$(find "$data/python" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
py_at="$(PATH="$logged:$PATH" command -v py 2>/dev/null || true)"
{
  printf 'pydeps-hook-ready 1\n%s\n%s\n' "$(windows_form "${root^^}")" "$(windows_form "$target")"
  for name in python3.13 python3.12 python3 python; do
    printf '%s=%s\n' "$name" "$(windows_form "$logged/$name" upper)"
  done
  printf 'py=%s\n' "$(windows_form "$py_at" upper)"
} >"$WORK/good-stamp"
starts_under=""
for ostype in msys linux-gnu; do
  restore_stamp
  touch "$stamp" # newer than a real py this PATH may hold
  rm -f "$WORK/starts.log"
  run_hook "$root" "$WHEELS" OSTYPE="$ostype" CLAUDE_PLUGIN_DATA="$data" PATH="$logged:$PATH"
  STARTS=0
  [[ -f "$WORK/starts.log" ]] && STARTS="$(wc -l <"$WORK/starts.log" | tr -d '[:space:]')"
  starts_under+="$ostype=$STARTS "
done
if [[ "$starts_under" == "msys=0 linux-gnu="[1-9]* ]]; then
  ok "a stamp in Windows path form holds under Git Bash and nowhere else"
else
  fail "Windows-form stamp: starts under $starts_under"
fi

# Git Bash on Windows can report OSTYPE=cygwin while it mounts drives at /c/, not /cygdrive/c/. Inside a user and
# mount namespace whose root holds a /c directory (this suite's WORK bound there), a stamp in Windows drive-letter
# form holds under OSTYPE=cygwin and under OSTYPE=msys, and starts no Python. Skipped where unprivileged user
# namespaces are not allowed.
drive_case() {
  local nr="$WORK/newroot" d
  mkdir -p "$nr"
  mount -t tmpfs drives "$nr" || return 1
  for d in /*; do
    [[ "$d" == /proc || "$d" == /sys || "$d" == /dev ]] && continue
    if [[ -L "$d" ]]; then
      cp -P "$d" "$nr$d"
    elif [[ -d "$d" ]]; then
      mkdir "$nr$d" && mount --rbind "$d" "$nr$d"
    fi
  done
  mkdir "$nr/proc" "$nr/dev" "$nr/c"
  mount --rbind /dev "$nr/dev"
  mount --rbind "$WORK/drive" "$nr/c"
  chroot "$nr" /bin/bash -c "$1"
}
mkdir -p "$WORK/drive/plugin" "$WORK/drive/data/python/0123456789ab-cpython-399" "$WORK/drive/bin"
cp -R "$root/hooks" "$root/scripts" "$root/requirements.txt" "$WORK/drive/plugin/"
for name in python3.13 python3.12 python3 python; do
  printf '#!/bin/sh\necho "%s $*" >>/c/starts.log\nexec "%s" "$@"\n' "$name" "$real_py" >"$WORK/drive/bin/$name"
done
chmod +x "$WORK/drive/bin/"*
{
  printf 'pydeps-hook-ready 1\nC:\\PLUGIN\nC:\\data\\python\\0123456789ab-cpython-399\n'
  for name in python3.13 python3.12 python3 python; do
    printf '%s=C:\\BIN\\%s.EXE\n' "$name" "${name^^}"
  done
  printf 'py=\n'
} >"$WORK/drive/data/python/.hook-ready"
touch -t 202001010000 "$WORK/drive/plugin/requirements.txt" "$WORK/drive/plugin/scripts/"* "$WORK/drive/bin/"*
drive_starts=""
for ostype in cygwin msys; do
  rm -f "$WORK/drive/starts.log"
  # shellcheck disable=SC2016  # expands inside the namespace
  if ! unshare -rm bash -c "$(declare -f drive_case); WORK='$WORK'; drive_case 'OSTYPE=$ostype CLAUDE_PLUGIN_DATA=/c/data PATH=/c/bin:/usr/bin:/bin bash /c/plugin/hooks/install-python-deps.sh </dev/null >/dev/null 2>&1'" 2>/dev/null; then
    drive_starts="unavailable"
    break
  fi
  n=0
  [[ -f "$WORK/drive/starts.log" ]] && n="$(wc -l <"$WORK/drive/starts.log" | tr -d '[:space:]')"
  drive_starts+="$ostype=$n "
done
if [[ "$drive_starts" == unavailable ]]; then
  echo "SKIP: no unprivileged user and mount namespace here -- the /c/ drive-mount case is skipped"
elif [[ "$drive_starts" == "cygwin=0 msys=0 " ]]; then
  ok "a drive-letter stamp holds where drives mount at /c/, whether the shell reports cygwin or msys"
else
  fail "drive-letter stamp under a /c/ mount: starts $drive_starts"
fi

echo "---"
echo "passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
