#!/usr/bin/env bash
# Tests for build_capture_script.py against live processes this test starts: the built script
# reads the start time after the last ')' of /proc/<pid>/stat (a comm holding spaces and ')'),
# runs the recorder only when every recheck holds, drops the capture when the process changes
# while the recorder runs, and the builder refuses a record that fails its format or live check.
# Usage: build_capture_script.test.sh [builder]   (default: the sibling build_capture_script.py)
# shellcheck disable=SC2016 # recorder scripts and expected script text are single-quoted on purpose
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${1:-$SCRIPT_DIR/build_capture_script.py}"
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}

if [[ "$(uname -s)" != Linux || ! -r /proc/self/stat ]]; then
  printf 'SKIP: pid binding reads the Linux process table; this host is %s\n' "$(uname -s)"
  exit 0
fi

T="$(mktemp -d)"
PIDS=()
cleanup() {
  for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; done
  rm -rf "$T"
}
trap cleanup EXIT

UID_NOW="$(id -u)"
# start_of <pid>: field 22 of /proc/<pid>/stat, counted from after the last ')'.
start_of() {
  local stat rest
  stat="$(</proc/"$1"/stat)"
  rest="${stat##*)}"
  read -ra f <<<"$rest"
  printf '%s' "${f[19]}"
}
sum_of() {
  local s
  s="$(sha256sum <"/proc/$1/cmdline")"
  printf '%s' "${s%% *}"
}
# spawn <comm>: a long-lived bash whose comm is <comm>; its pid in $P.
spawn() {
  bash -c 'printf %s "$1" >/proc/self/comm; while :; do sleep 1; done' spawned "$1" &
  P=$!
  PIDS+=("$P")
  for _ in $(seq 50); do
    [[ "$(cat "/proc/$P/comm" 2>/dev/null)" == "$1" ]] && return 0
    sleep 0.1
  done
  return 1
}

N=0
# build <args...>: runs the builder writing $T/case-N/capture.sh; rc in $rc, stdout in $out,
# stderr in $err, the script path in $S and the capture path in $C.
build() {
  N=$((N + 1))
  mkdir -p "$T/case-$N"
  S="$T/case-$N/capture.sh"
  C="$T/case-$N/threads.txt"
  rc=0
  python3 -I "$BUILD" --write "$S" --capture "$C" "$@" >"$T/out" 2>"$T/err" || rc=$?
  out="$(cat "$T/out")"
  err="$(cat "$T/err")"
}
# run_script: runs $S; rc in $src, stderr in $serr.
run_script() {
  src=0
  sh "$S" 2>"$T/serr" || src=$?
  serr="$(cat "$T/serr")"
}
launch_args() {
  printf '%s\n' --pid "$1" --uid "$UID_NOW" --start-time "$(start_of "$1")" --sha256 "$(sum_of "$1")"
}

# --- a comm with spaces and ')' --------------------------------------------------
COMM='x) R 1 ) y'
if ! spawn "$COMM"; then
  fail "a process with comm '$COMM' starts" "comm never became '$COMM'"
else
  A="$P"
  mapfile -t LA < <(launch_args "$A")
  build "${LA[@]}" -- sh -c 'echo "threads of $1"' recorder '<pid>'
  if [[ "$rc" == 0 && -x "$S" && "$out" == *"process $A: uid $UID_NOW, start time $(start_of "$A"), sha256 $(sum_of "$A"), command line: "* ]]; then
    pass "the builder accepts a live record and prints the process line"
  else
    fail "the builder accepts a live record and prints the process line" "rc=$rc out=$out err=$err"
  fi
  if [[ "$out" == *"script $S:"* && "$out" == *"check $A $UID_NOW $(start_of "$A") $(sum_of "$A")"* ]]; then
    pass "stdout shows the full script with the checked literals"
  else
    fail "stdout shows the full script with the checked literals" "$out"
  fi
  if [[ -n "$(find "$S" -perm 0700)" ]]; then
    pass "the script is written with mode 0700"
  else
    fail "the script is written with mode 0700" "$(ls -l "$S")"
  fi
  run_script
  if [[ "$src" == 0 && "$(cat "$C" 2>/dev/null)" == "threads of $A" ]]; then
    pass "the built script reads starttime after the last ')' and runs the recorder"
  else
    fail "the built script reads starttime after the last ')' and runs the recorder" "rc=$src: $serr"
  fi

  build "${LA[@]}" -- sh -c 'echo dump; exit 3' recorder '<pid>'
  run_script
  if [[ "$src" == 4 && -s "$C" ]]; then
    pass "a recorder exit of 3 becomes 4 and the capture stays"
  else
    fail "a recorder exit of 3 becomes 4 and the capture stays" "rc=$src: $serr"
  fi

  build --pid "$A" --uid "$UID_NOW" --start-time "$(($(start_of "$A") + 1))" --sha256 "$(sum_of "$A")" -- rec '<pid>'
  if [[ "$rc" == 3 && "$err" == *"start time"* && ! -e "$S" ]]; then
    pass "the builder refuses a start time that differs"
  else
    fail "the builder refuses a start time that differs" "rc=$rc: $err"
  fi

  build --pid "$A" --uid "$UID_NOW" --start-time "$(start_of "$A")" --sha256 "$(printf '%064d' 0)" -- rec '<pid>'
  if [[ "$rc" == 3 && "$err" == *"command line sha256"* ]]; then
    pass "the builder refuses a hash that differs"
  else
    fail "the builder refuses a hash that differs" "rc=$rc: $err"
  fi

  build --pid "$A" --uid "$((UID_NOW + 1))" --start-time "$(start_of "$A")" --sha256 "$(sum_of "$A")" -- rec '<pid>'
  if [[ "$rc" == 3 && "$err" == *"is not this user's uid"* ]]; then
    pass "the builder refuses a recorded uid other than the caller's"
  else
    fail "the builder refuses a recorded uid other than the caller's" "rc=$rc: $err"
  fi

  for bad in "0$A" "${A}x" "-$A" ""; do
    build --pid "$bad" --uid "$UID_NOW" --start-time "$(start_of "$A")" --sha256 "$(sum_of "$A")" -- rec '<pid>'
    if [[ "$rc" == 3 && "$err" == *"fails its format check"* ]]; then
      pass "the builder refuses pid '$bad' by its format"
    else
      fail "the builder refuses pid '$bad' by its format" "rc=$rc: $err"
    fi
  done

  # --- recheck after the recorder ----------------------------------------------
  build "${LA[@]}" -- sh -c 'echo "threads of $1"; kill "$1"; sleep 0.5' recorder '<pid>'
  run_script
  if [[ "$src" == 3 && ! -e "$C" && "$serr" == *"capture dropped: $C"* ]]; then
    pass "a process that changes while the recorder runs drops the capture"
  else
    fail "a process that changes while the recorder runs drops the capture" "rc=$src: $serr"
  fi
fi

# --- the recheck before the recorder ----------------------------------------------
if spawn plain; then
  B="$P"
  mapfile -t LB < <(launch_args "$B")
  build "${LB[@]}" -- sh -c 'echo ran >"$2"' recorder '<pid>' "$T/ran"
  kill "$B"
  wait "$B" 2>/dev/null
  run_script
  if [[ "$src" == 3 && ! -e "$T/ran" && "$serr" == *"process no longer matches"* ]]; then
    pass "a process gone before the script runs exits 3 before the recorder"
  else
    fail "a process gone before the script runs exits 3 before the recorder" "rc=$src: $serr"
  fi
else
  fail "a plain process starts" "comm never became plain"
fi

# --- a wrapper resolves to its one child ------------------------------------------
bash -c 'sleep 120 & printf %s "$!" >"$1"; wait' wrapper "$T/child" &
W=$!
PIDS+=("$W")
for _ in $(seq 50); do
  [[ -s "$T/child" ]] && break
  sleep 0.1
done
K="$(cat "$T/child" 2>/dev/null)"
PIDS+=("$K")
# The child's command line is bash's until it execs sleep.
for _ in $(seq 50); do
  [[ "$(cat "/proc/$K/comm" 2>/dev/null)" == sleep ]] && break
  sleep 0.1
done
mapfile -t LW < <(launch_args "$W")
build "${LW[@]}" --child -- sh -c 'echo "threads of $1"' recorder '<pid>'
if [[ "$rc" == 0 && "$out" == *"child $K of $W: uid $UID_NOW"* && "$out" == *"check $K $UID_NOW $(start_of "$K") $(sum_of "$K") $W"* ]]; then
  pass "--child resolves the wrapper's one child and checks its parent pid"
else
  fail "--child resolves the wrapper's one child and checks its parent pid" "rc=$rc out=$out err=$err"
fi
run_script
if [[ "$src" == 0 && "$(cat "$C" 2>/dev/null)" == "threads of $K" ]]; then
  pass "the recorder targets the child's pid"
else
  fail "the recorder targets the child's pid" "rc=$src: $serr"
fi

mapfile -t LK < <(launch_args "$K")
build "${LK[@]}" --child -- rec '<pid>'
if [[ "$rc" == 3 && "$err" == *"0 child processes, not one"* ]]; then
  pass "--child on a process with no child is refused"
else
  fail "--child on a process with no child is refused" "rc=$rc: $err"
fi

# --- elevated attach ------------------------------------------------------------
build --attach-pid "$K" -- sh -c 'echo "threads of $1"' recorder '<pid>'
if [[ "$rc" == 0 && "$out" == *"attached process $K: uid $UID_NOW, start time $(start_of "$K")"* && "$out" == *"check $K $UID_NOW $(start_of "$K") $(sum_of "$K")"* ]]; then
  pass "--attach-pid records the pid's uid, start time and hash in the script"
else
  fail "--attach-pid records the pid's uid, start time and hash in the script" "rc=$rc out=$out err=$err"
fi
run_script
if [[ "$src" == 0 && "$(cat "$C" 2>/dev/null)" == "threads of $K" ]]; then
  pass "the attach script rechecks and runs the recorder"
else
  fail "the attach script rechecks and runs the recorder" "rc=$src: $serr"
fi

build --attach-pid "$K" --elevate sudo -- rec --pid '<pid>' --out '<file>'
if [[ "$rc" == 0 && "$out" == *"sudo rec --pid $K --out $C"* && "$out" == *'sudo chown -h "$(id -u):$(id -g)" "$capture"'* ]]; then
  pass "--elevate prefixes the recorder and hands a <file> capture back"
else
  fail "--elevate prefixes the recorder and hands a <file> capture back" "rc=$rc out=$out err=$err"
fi

# A placeholder name inside the capture path or a recorder argument stays literal text.
N=$((N + 1))
mkdir -p "$T/case-$N/@RUN@"
S="$T/case-$N/capture.sh"
C="$T/case-$N/@RUN@/threads.txt"
rc=0
python3 -I "$BUILD" --write "$S" --capture "$C" --attach-pid "$K" -- sh -c 'echo "$2 $1"' recorder '<pid>' '@HANDBACK@' >/dev/null 2>"$T/err" || rc=$?
run_script
if [[ "$rc" == 0 && "$src" == 0 && "$(cat "$C" 2>/dev/null)" == "@HANDBACK@ $K" ]]; then
  pass "placeholder names in the capture path and recorder are not filled again"
else
  fail "placeholder names in the capture path and recorder are not filled again" "rc=$rc src=$src: $(cat "$T/err") $serr"
fi

# --- usage ----------------------------------------------------------------------
build --attach-pid "$K" -- sudo rec '<pid>'
if [[ "$rc" == 2 && "$err" == *"pass --elevate"* ]]; then
  pass "a recorder with an elevation prefix is refused"
else
  fail "a recorder with an elevation prefix is refused" "rc=$rc: $err"
fi

build --attach-pid "$K" -- rec --all
if [[ "$rc" == 2 && "$err" == *"names no <pid>"* ]]; then
  pass "a recorder that names no <pid> is refused"
else
  fail "a recorder that names no <pid> is refused" "rc=$rc: $err"
fi

build --attach-pid "$K" --pid "$K" -- rec '<pid>'
if [[ "$rc" == 2 ]]; then
  pass "--attach-pid with launch record values is refused"
else
  fail "--attach-pid with launch record values is refused" "rc=$rc: $err"
fi

build --attach-pid "$K" -- rec '<pid>'
rc_first="$rc"
rc=0
python3 -I "$BUILD" --write "$S" --capture "$C" --attach-pid "$K" -- rec '<pid>' >/dev/null 2>"$T/err" || rc=$?
if [[ "$rc_first" == 0 && "$rc" == 2 ]]; then
  pass "an existing script path is never overwritten"
else
  fail "an existing script path is never overwritten" "first=$rc_first second=$rc: $(cat "$T/err")"
fi

rc=0
python3 -I "$BUILD" --write "$T/rel.sh" --capture relative.txt --attach-pid "$K" -- rec '<pid>' >/dev/null 2>"$T/err" || rc=$?
if [[ "$rc" == 2 ]]; then
  pass "a relative capture path is refused"
else
  fail "a relative capture path is refused" "rc=$rc: $(cat "$T/err")"
fi

if ((FAILED)); then
  printf '%d failed\n' "$FAILED" >&2
  exit 1
fi
printf 'all passed\n'
