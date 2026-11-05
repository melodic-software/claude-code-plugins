#!/usr/bin/env bash
# Contract test for block-root-delete-target-resolve.sh: rdt_bounded_to gives
# what `$(command)` gives and bounds the command's whole life, and the guard
# refuses when a resolver outlives the time left.
#
# The too-slow cases set SECONDS in the guard's environment. Bash imports it, and
# RDT_DEADLINE_ABS bounds the hook by absolute SECONDS, so a start at 44 leaves
# 6 s and the test needs no switch in the guard.
# shellcheck disable=SC2016

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# shellcheck source=block-root-delete-target-resolve.sh
source "$HOOK_DIR/block-root-delete-target-resolve.sh"

pass=0
fail=0
ok() {
  pass=$((pass + 1))
  echo "ok - $1"
}
no() {
  fail=$((fail + 1))
  echo "FAIL - $1: $2"
}

# shim <name> <body>: an executable named <name> in the test's shim directory.
SHIMS="$TEST_TMPDIR/shims"
mkdir -p "$SHIMS"
shim() {
  printf '#!/bin/bash\n%s\n' "$2" >"$SHIMS/$1"
  chmod +x "$SHIMS/$1"
}

# same_as_subst <label> <body>: the helper's value and status equal `$(...)`'s.
same_as_subst() {
  local want want_rc=0 got got_rc=0
  shim emit "$2"
  want=$("$SHIMS/emit" 2>/dev/null) || want_rc=$?
  rdt_bounded_to got 10 "$SHIMS/emit" || got_rc=$?
  if [[ "$got" == "$want" && "$got_rc" == "$want_rc" ]]; then
    ok "$1"
  else
    no "$1" "want rc=$want_rc [$want], got rc=$got_rc [$got]"
  fi
}

same_as_subst 'one line' 'printf "a\n"'
same_as_subst 'no trailing newline' 'printf "a"'
same_as_subst 'several lines' 'printf "a\nb c\n\nd\n"'
same_as_subst 'trailing newlines stripped' 'printf "a\n\n\n"'
same_as_subst 'leading and trailing blanks kept' 'printf "  a  \n"'
same_as_subst 'a backslash kept' 'printf "a\\\\b\n"' # portability-ok: a literal backslash in printf data, not a grep word boundary
same_as_subst 'empty output' ':'
same_as_subst 'a nonzero exit keeps its status' 'printf "a\n"; exit 3'
same_as_subst 'stderr is dropped' 'echo err >&2; echo out'
same_as_subst 'a NUL is dropped' 'printf "a\0b\n"'

# `$(...)` keeps a CR on Linux and strips it on Git Bash; the helper always strips.
shim crlf 'printf "a\r\nb\r\n"'
rdt_bounded_to got 10 "$SHIMS/crlf"
if [[ "$got" == $'a\nb' ]]; then ok 'carriage returns removed'; else no 'carriage returns removed' "[$got]"; fi

got=keep
rc=0
rdt_bounded_to got 10 "$SHIMS/no-such-command" || rc=$?
if ((rc == 127)); then ok 'a missing command answers 127'; else no 'a missing command answers 127' "rc=$rc"; fi

# Expiry: 124, and the process is gone.
shim slow 'echo $$ >"$1"; exec sleep 60'
rc=0
start=$SECONDS
rdt_bounded_to got 1 "$SHIMS/slow" "$TEST_TMPDIR/slow.pid" || rc=$?
took=$((SECONDS - start))
if ((rc == 124)); then ok 'expiry answers 124'; else no 'expiry answers 124' "rc=$rc"; fi
if ((took <= 3)); then ok 'expiry returns on time'; else no 'expiry returns on time' "${took}s"; fi
if kill -0 "$(<"$TEST_TMPDIR/slow.pid")" 2>/dev/null; then
  no 'expiry kills the command' "pid $(<"$TEST_TMPDIR/slow.pid") alive"
else
  ok 'expiry kills the command'
fi

# A command that closes stdout and keeps running is still bounded.
shim closes 'echo hi; exec >&-; echo $$ >"$1"; exec sleep 60'
rc=0
start=$SECONDS
rdt_bounded_to got 1 "$SHIMS/closes" "$TEST_TMPDIR/closes.pid" || rc=$?
took=$((SECONDS - start))
if ((rc == 124 && took <= 3)); then
  ok 'a closed stdout does not end the bound'
else
  no 'a closed stdout does not end the bound' "rc=$rc after ${took}s"
fi
if kill -0 "$(<"$TEST_TMPDIR/closes.pid")" 2>/dev/null; then
  no 'a closed stdout command is killed' "pid alive"
else
  ok 'a closed stdout command is killed'
fi

# A child the command starts without exec is killed too, and does not hold the
# bound open past its time.
shim wraps 'sleep 60 & echo $! >"$1"; wait'
rc=0
start=$SECONDS
rdt_bounded_to got 1 "$SHIMS/wraps" "$TEST_TMPDIR/wraps.pid" || rc=$?
took=$((SECONDS - start))
if ((rc == 124 && took <= 3)); then
  ok 'a child started without exec does not outlast the bound'
else
  no 'a child started without exec does not outlast the bound' "rc=$rc after ${took}s"
fi
if kill -0 "$(<"$TEST_TMPDIR/wraps.pid")" 2>/dev/null; then
  no 'a child started without exec is killed' "pid alive"
else
  ok 'a child started without exec is killed'
fi

# RDT_BOUND_UNSET reaches the command and not the caller.
shim showenv 'printf "%s" "${RDT_T_VAR-unset}"'
export RDT_T_VAR=set
RDT_BOUND_UNSET=(RDT_T_VAR)
rdt_bounded_to got 10 "$SHIMS/showenv"
unset RDT_BOUND_UNSET
if [[ "$got" == unset && "$RDT_T_VAR" == set ]]; then
  ok 'RDT_BOUND_UNSET drops the variable for the command only'
else
  no 'RDT_BOUND_UNSET drops the variable for the command only' "got [$got], caller [$RDT_T_VAR]"
fi
unset RDT_T_VAR

# Many calls leak no descriptor.
fds_before=$(compgen -G "/proc/$$/fd/*" | wc -l)
for ((i = 0; i < 20; i++)); do rdt_bounded_to got 10 "$SHIMS/showenv"; done
fds_after=$(compgen -G "/proc/$$/fd/*" | wc -l)
if ((fds_after <= fds_before)); then ok 'no descriptor leaks'; else no 'no descriptor leaks' "$fds_before -> $fds_after"; fi

# --- The guard refuses when a resolver outlives the time left --------------
unset CLAUDE_CODE_SESSION_ATTENDED GUARDRAILS_SESSION_UNWATCHED GIT_DIR GIT_WORK_TREE GIT_CONFIG
GUARD="$HOOK_DIR/block-root-delete-target.sh"
REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
REPO_TOP=$(git -C "$REPO" rev-parse --show-toplevel)
REPO_TOP="${REPO_TOP//$'\r'/}"
# The `~` keeps the operand off the in-shell resolver on Windows, so realpath
# runs on every host.
PAYLOAD=$(MSYS_NO_PATHCONV=1 jq -n --arg d "$REPO_TOP" '{tool_name:"Bash",tool_input:{command:"rm -rf ./x~1/build"},cwd:$d}')

# judge <path prefix>: the guard's status and output for PAYLOAD, in rc and out,
# starting 40 s into the hook's 50 s, so 10 s are left.
judge() {
  rc=0
  start=$SECONDS
  out=$(env PATH="$1$PATH" SECONDS=40 bash "$GUARD" <<<"$PAYLOAD" 2>&1) || rc=$?
  took=$((SECONDS - start))
}

judge ""
if ((rc == 0)); then ok 'control: the same delete is allowed with no slow process'; else no 'control: the same delete is allowed with no slow process' "rc=$rc: $out"; fi

# too_slow <tool>: a <tool> that sleeps past the time left is refused and killed.
too_slow() {
  local bin=$SHIMS-$1 pidfile="$TEST_TMPDIR/$1.pid"
  mkdir -p "$bin"
  printf '#!/bin/bash\necho $$ >"%s"\nexec sleep 60\n' "$pidfile" >"$bin/$1"
  chmod +x "$bin/$1"
  judge "$bin:"
  if [[ -s "$pidfile" ]]; then ok "$1: the slow process started"; else no "$1: the slow process started" "rc=$rc: $out"; fi
  if ((rc == 2)) && [[ "$out" == *'ran out of time'* ]]; then
    ok "$1: the guard refuses as too slow"
  else
    no "$1: the guard refuses as too slow" "rc=$rc: $out"
  fi
  if ((took < 30)); then ok "$1: the refusal comes before the process would end"; else no "$1: the refusal comes before the process would end" "${took}s"; fi
  if [[ -s "$pidfile" ]] && kill -0 "$(<"$pidfile")" 2>/dev/null; then
    no "$1: the slow process is gone" "pid alive"
  else
    ok "$1: the slow process is gone"
  fi
}
too_slow git
too_slow realpath

# --- On Git Bash, the in-shell resolvers give the processes' answers ---------
# Each path goes through realpath -m and the guard's cygpath rule (nearest
# existing ancestor, a symlink leaf by its parent), and through rdt_phys_to and
# rdt_win_to. A helper may decline (status 1); an answer must match: the
# physical one exactly, the Windows one in the spelling the guard compares
# (rdt_canon_to: slashes squeezed, no trailing slash, lower case).
skips=0
case "${OSTYPE:-}" in
  msys* | cygwin*) on_windows=1 ;;
  *) on_windows=0 ;;
esac
if ((! on_windows)) || ! command -v cygpath >/dev/null 2>&1; then
  skips=$((skips + 1))
  echo "SKIP - resolver differential: needs Git Bash with cygpath (OSTYPE=${OSTYPE:-unset}); the Windows CI lane runs it"
else
  fold() {
    local p="${1//\\//}"
    while [[ "$p" == *//* ]]; do p="${p//\/\//\/}"; done
    [[ "$p" == ?*/ && ! "$p" =~ ^[A-Za-z]:/$ ]] && p="${p%/}"
    printf '%s' "${p,,}"
  }
  old_win() {
    local a="$1" rem="" m
    while [[ ! -e "$a" && "$a" == */* && "$a" != / && ! "$a" =~ ^[A-Za-z]:/$ ]]; do
      rem="/${a##*/}$rem"
      a="${a%/*}"
      [[ -z "$a" ]] && a=/
    done
    if [[ -z "$rem" && -L "$a" && "$a" == */?* ]]; then
      rem="/${a##*/}"
      a="${a%/*}"
    fi
    m=$(cygpath -l -m -- "$a") || return 1
    m="${m//$'\r'/}"
    if [[ -z "$rem" ]]; then printf '%s' "$m"; else printf '%s/%s' "${m%/}" "${rem#/}"; fi
  }
  W="$(cd "$TEST_TMPDIR" && pwd -P)/w"
  mkdir -p "$W/real/sub" "$W/real/-" "$W/real/-P" "$W/real/--" "$W/dot." "$W/sp " "$W/caf"$'\xc3\xa9'
  ln -s "$W/real" "$W/link"
  ln -s "$W/real/sub" "$W/leaflink"
  ln -s /usr "$W/out"
  cmd //c mklink //J "$(cygpath -w "$W/junc")" "$(cygpath -w "$W/real")" >/dev/null 2>&1
  W8=$(cygpath -s -m -- "$W/real" 2>/dev/null)
  W8="${W8//$'\r'/}"
  WM=$(cygpath -m -- "$W")
  WM="${WM//$'\r'/}"
  paths=(
    "$W" "$W/real" "$W/real/sub" "$W/real/missing/x" "$W/real/missing/../sub" "$W/missing/../out/x"
    "$W/link/sub" "$W/link/../real" "$W/real/sub/../../link/x" "$W/leaflink" "$W/out" "$W/out/x"
    "$W/junc/sub" "$W/junc/missing/z" "$W/real/-" "$W/real/-P" "$W/real/--" "$W/real/-/x"
    "$W/dot." "$W/dot./x" "$W/sp " "$W/caf"$'\xc3\xa9' "$W/real/./sub" "$W//real//sub/" "$W/REAL/SUB"
    "$WM/real/sub" "${WM,}/real" "$W8/sub" "$W\\real" /tmp /tmp/x /tmp/x/../y /var/tmp /usr/bin /bin/x
    / /c /c/ C:/ "$HOME" "$HOME/.claude" //server/share/x x/relative
  )
  here="$PWD"
  CDPATH="$W/real"
  for p in "${paths[@]}"; do
    want=$(realpath -m -- "$p" 2>/dev/null) && want="${want//$'\r'/}" || want="(error)"
    got="" rc=0
    out=$(
      rdt_phys_to got "$p" || exit 1
      printf '|%s|%s' "$got" "$PWD"
    ) || rc=$?
    if ((rc == 0)); then
      got="${out#|}"
      got="${got%|*}"
      if [[ "$got" == "$want" ]]; then ok "phys: $p"; else no "phys: $p" "realpath [$want], helper [$got]"; fi
    fi
    for q in "$p" "$want"; do
      [[ "$q" == "(error)" ]] && continue
      wwant=$(old_win "$q") || continue
      rc=0
      out=$(
        rdt_win_to got "$q" || exit 1
        printf '|%s|%s' "$got" "$PWD"
      ) || rc=$?
      ((rc == 0)) || continue
      [[ "$out" == '|'* ]] || no "win writes nothing to stdout: $q" "[$out]"
      got="${out#|}"
      [[ "${got##*|}" == "$here" ]] || no "win returns to the start directory: $q" "${got##*|}"
      got="${got%|*}"
      if [[ "$(fold "$got")" == "$(fold "$wwant")" ]]; then ok "win: $q"; else no "win: $q" "cygpath [$wwant], helper [$got]"; fi
    done
  done
  unset CDPATH
  # Declines this suite pins: each answer would differ from the processes', or
  # the path is on a drive that is not local. A host whose `ln -s` copies
  # instead of linking (Git Bash without native symlinks) has no link to decline.
  free=""
  for l in Q R S T U V W X Y Z; do [[ -e "$l:/" ]] || {
    free="$l"
    break
  }; done
  declines=("$W/missing/../out/x" "$W8/sub" "$W/dot./x" "$W/sp " "$W/caf"$'\xc3\xa9' //server/share/x x/relative)
  wdeclines=("$W8/sub" "$W/dot./x" /usr/bin C:/ /c)
  [[ -n "$free" ]] && declines+=("$free:/rdt-x" "/${free,,}/rdt-x") && wdeclines+=("$free:/rdt-x")
  if [[ -L "$W/link" && -L "$W/leaflink" ]]; then
    declines+=("$W/link/sub" "$W/leaflink")
    wdeclines+=("$W/leaflink" "$W/link/sub" "$W/real/sub/../../link/x")
  else
    skips=$((skips + 1))
    echo "SKIP - link declines: ln -s made copies here, not links (3 phys and 3 win cases)"
  fi
  [[ -L "$W/junc" ]] && wdeclines+=("$W/junc/sub")
  for p in "${declines[@]}"; do
    if rdt_phys_to got "$p"; then no "phys declines: $p" "answered [$got]"; else ok "phys declines: $p"; fi
  done
  for p in "${wdeclines[@]}"; do
    if rdt_win_to got "$p"; then no "win declines: $p" "answered [$got]"; else ok "win declines: $p"; fi
  done
  # The temp roots without their drive spellings resolve to the same set.
  # shellcheck source=hook-utils.sh
  source "$HOOK_DIR/hook-utils.sh"
  hook::_temp_root_candidates
  full=("${_HOOK_TEMP_CANDS[@]}")
  hook::_temp_root_candidates --no-drive
  bare=("${_HOOK_TEMP_CANDS[@]}")
  set_of() {
    local c r
    for c in "$@"; do
      r=$(realpath -m -- "$c") || continue
      r=$(old_win "${r//$'\r'/}") || continue
      fold "$r"
      echo
    done | sort -u
  }
  if [[ "$(set_of "${full[@]}")" == "$(set_of "${bare[@]}")" ]]; then
    ok "temp roots: --no-drive resolves to the same set (${#full[@]} -> ${#bare[@]} candidates)"
  else
    no "temp roots: --no-drive resolves to the same set" "full [$(set_of "${full[@]}")] bare [$(set_of "${bare[@]}")]"
  fi
  cmd //c rmdir "$(cygpath -w "$W/junc")" >/dev/null 2>&1
fi

echo "PASS=$pass FAIL=$fail SKIP=$skips"
((fail == 0))
