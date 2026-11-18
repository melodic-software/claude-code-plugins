#!/bin/sh
# shellcheck shell=bash

# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_PLUGIN=bash-format
# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_IDS=bash
BF_SHFMT_INSTALL='see https://github.com/mvdan/sh#shfmt'
BF_SC_INSTALL='see https://github.com/koalaman/shellcheck#installing'
BF_SC_ARGS=(-x -f gcc -S warning)
BF_SC_LARGE_LINES=2000

# bf_sc_script [<flag>...]: sets RT_SCRIPT to the ShellCheck command, with BF_SC_ARGS and each <flag>.
# shellcheck disable=SC2016 # the command text sh -c expands, with RT_BIN and the files
bf_sc_script() {
  local a
  RT_SCRIPT='"$RT_BIN"'
  for a in "${BF_SC_ARGS[@]}" "$@"; do RT_SCRIPT+=" $a"; done
  RT_SCRIPT+=' -- "$@"'
}

bf_lines() {
  local n
  n="$(wc -l)" || n=0
  printf '%s\n' "$((n))"
}

bf_large() {
  (($1 > BF_SC_LARGE_LINES)) || return 1
  if [[ -z "${bf_dfa_flag:-}" ]]; then
    bf_dfa_flag=no
    [[ "$("$RT_BIN" --version 2>/dev/null)" =~ version:\ ([0-9]+)\.([0-9]+) ]] &&
      ((BASH_REMATCH[1] > 0 || BASH_REMATCH[2] >= 10)) && bf_dfa_flag=yes
  fi
  [[ "$bf_dfa_flag" == yes ]]
}

bf_lanes() {
  local n
  n="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null)"
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || n=2
  ((n > 8)) && n=8
  ((n > $1)) && n=$1
  BF_LANES=$n
}

bf_lint() {
  local out="$1" full="$2" i n l r kind status=0 plan="${CHECKS_TMP:?}/plan" pids=()
  shift 2
  local lint=("$@")
  : >"$plan.sizes"
  : >"$out.lanes"
  for i in "${!lint[@]}"; do
    n="$(bf_lines <"${lint[i]}")"
    kind=S
    ((full)) || ! bf_large "$n" || kind=L
    printf '%s\t%s\t%s\n' "$n" "$kind" "$i" >>"$plan.sizes"
  done
  bf_lanes "${#lint[@]}"
  LC_ALL=C sort -t $'\t' -k1,1nr "$plan.sizes" | awk -F '\t' -v n="$BF_LANES" '{
      b = 0; for (l = 1; l < n; l++) if (load[l] < load[b]) b = l
      load[b] += $1 + 1; print b "\t" $2 "\t" $3
    }' >"$plan" || return 3
  for ((l = 0; l < BF_LANES; l++)); do
    (
      small=() large=() worst=0
      while IFS=$'\t' read -r lane kind i; do
        ((lane == l)) || continue
        if [[ "$kind" == L ]]; then large+=("${lint[i]}"); else small+=("${lint[i]}"); fi
      done <"$plan"
      if ((${#small[@]})); then
        rt_run "${small[@]}"
        worst=$?
      fi
      if ((${#large[@]})); then
        bf_sc_script --extended-analysis=false
        rt_run "${large[@]}"
        r=$?
        ((r > worst)) && worst=$r
      fi
      exit "$worst"
    ) >"$CHECKS_TMP/lane.$l" 2>&1 &
    pids+=($!)
  done
  for i in "${!pids[@]}"; do
    wait "${pids[i]}"
    r=$?
    ((r > status)) && status=$r
    cat "$CHECKS_TMP/lane.$i" >>"$out.lanes" || status=3
  done
  LC_ALL=C sort -s -t : -k1,1 -k2,2n -k3,3n "$out.lanes" >>"$out" || status=3
  return "$status"
}

bf__rcdir() {
  local d="$1"
  rcdir=
  while [[ "$d" == */* ]]; do
    d="${d%/*}"
    [[ -e "$d/.shellcheckrc" || -e "$d/shellcheckrc" ]] && rcdir="$d" && return
  done
  [[ -e .shellcheckrc || -e shellcheckrc ]] && rcdir=.
  return 0
}
bf__sources() {
  local probe opts=()
  bf_large "$(bf_lines <"$1")" && opts=(--extended-analysis=false)
  probe="$(sed 's/#[[:space:]]*shellcheck/#_/g' -- "$1" |
    (unset SHELLCHECK_OPTS && "$RT_BIN" --norc ${opts[@]+"${opts[@]}"} -s bash -f gcc -S info -) 2>&1)"
  (($? <= 1)) || return 0
  grep -q -e '\[SC109[01]\]' -e ': error: ' <<<"$probe"
}
bf__dedupe() {
  local table="${CHECKS_TMP:?}/blobs" i=0 f h ext dir key rep path
  plain=()
  for f in ${files[@]+"${files[@]}"}; do
    [[ "$f" == *[$'\t\n']* ]] || plain+=("$f")
  done
  ((${#plain[@]} > 1)) || return 0
  printf '%s\n' "${plain[@]}" | rt_git hash-object --no-filters --stdin-paths >"$CHECKS_TMP/hashes" || return 1
  : >"$table"
  while IFS= read -r h; do
    f="${plain[i]}"
    ext="${f##*.}"
    bf__rcdir "$f"
    dir=.
    [[ "$f" == */* ]] && dir="${f%/*}"
    printf '%s %s %s\t%s\t%s\n' "$h" "$ext" "$rcdir" "$dir" "$f" >>"$table"
    i=$((i + 1))
  done <"$CHECKS_TMP/hashes"
  ((i == ${#plain[@]})) || return 1
  awk -F '\t' '{ if (!($1 in first)) first[$1] = $3; else if (dir[$1] != $2) spread[$1] = 1; dir[$1] = $2 }
    END { for (k in spread) print k "\t" first[k] }' "$table" >"$CHECKS_TMP/spread" || return 1
  : >"$CHECKS_TMP/split"
  while IFS=$'\t' read -r key rep; do
    bf__sources "$rep" && printf '%s\n' "$key" >>"$CHECKS_TMP/split"
  done <"$CHECKS_TMP/spread"
  awk -F '\t' -v probed="$CHECKS_TMP/split" '
    BEGIN { while ((got = (getline l < probed)) > 0) apart[l] = 1; if (got < 0) exit 2 }
    { k = ($1 in apart) ? $1 "\t" $2 : $1; if (!(k in rep)) rep[k] = $3; print rep[k] "\t" $3 }' "$table" >"$CHECKS_TMP/reps" || return 1
  lint=()
  while IFS=$'\t' read -r rep path; do
    if [[ "$rep" == "$path" ]]; then
      lint+=("$path")
    else
      printf '%s\t%s\n' "$rep" "$path" >>"$copies"
    fi
  done <"$CHECKS_TMP/reps"
  for f in ${files[@]+"${files[@]}"}; do
    [[ "$f" == *[$'\t\n']* ]] && lint+=("$f")
  done
  return 0
}
# bf_lint_once <out> <full> <file>...: bf_lint over the files, each identical
# script linted once. Identical scripts lint identically when ShellCheck reads
# nothing else that depends on the path: the extension (its dialect fallback),
# the .shellcheckrc nearest the script's directory, and, for a script that
# sources a file, the directory a SCRIPTDIR search path resolves it from. So each distinct (bytes,
# extension, nearest rc) is linted once, from its first path, into $lint; a
# group spread over directories stays whole only when a probe finds nothing it
# sources, else it splits by directory. $copies maps a linted path to each copy,
# which gets its findings under its own path, so its own added lines still decide
# what blocks. Any failure here lints every path. The path-dependent inputs are
# the ones https://github.com/koalaman/shellcheck/blob/master/shellcheck.1.md
# lists under RC FILES, source-path and --shell.
bf_lint_once() {
  local out="$1" full="$2" rc=0 copied copies="${CHECKS_TMP:?}/copies" plain=()
  shift 2
  local files=("$@") lint=("$@")
  : >"$copies"
  if ! bf__dedupe; then
    lint=("$@")
    : >"$copies"
  fi
  if ((${#lint[@]})); then
    bf_lint "$out" "$full" "${lint[@]}"
    rc=$?
  fi
  [[ -s "$copies" ]] || return "$rc"
  awk -v copies="$copies" '
    BEGIN {
      while ((got = (getline l < copies)) > 0) { t = index(l, "\t"); r = substr(l, 1, t - 1); c[r] = (r in c) ? c[r] "\t" substr(l, t + 1) : substr(l, t + 1) }
      if (got < 0) exit 2
    }
    { print }
    match($0, /:[0-9]+:[0-9]+: /) {
      p = substr($0, 1, RSTART - 1)
      sub(/^\.\//, "", p)
      if (p in c) {
        n = split(c[p], m, "\t")
        for (i = 1; i <= n; i++) print m[i] substr($0, RSTART)
      }
    }' "$out" >"$out.copies"
  copied=$?
  if ((copied == 0)); then
    mv "$out.copies" "$out"
  else
    checks_tool_failed awk "$copied" 'copying the shellcheck findings to identical scripts'
  fi
  return "$rc"
}

rt_wants() {
  case "$1" in
  .githooks/*) return 1 ;;
  *.sh | *.bash) return 0 ;;
  *) return 1 ;;
  esac
}

bf__shellcheckrc_here() {
  [[ -e "$1/.shellcheckrc" || -e "$1/shellcheckrc" ]]
}

bf__walk() {
  local dir="$1" rc
  while :; do
    BF_WALK_DIR="$dir"
    "$3" "$dir"
    rc=$?
    ((rc == 0)) && return 0
    ((rc == 2)) && return 1
    [[ "$dir" == "$2" || "$dir" != */* ]] && return 1
    dir="${dir%/*}"
    [[ -n "$dir" ]] || return 1
  done
}

bf__dir() {
  local f="$1"
  [[ "$f" == /* || "$f" == [A-Za-z]:[\\/]* ]] || f="$2/$f"
  [[ "$f" == */* ]] && f="${f%/*}"
  BF_DIR="$f"
}

# bf__set <concern> <config path, repo-relative> <root>: the adapter's RT_*.
# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh and the entries
bf__set() {
  RT_DIR="$3"
  case "$1" in
  format)
    RT_ADAPTER=shfmt RT_TOOL=shfmt RT_BIN=shfmt RT_INSTALL="$BF_SHFMT_INSTALL"
    RT_CONFIGS=.editorconfig RT_SCRIPT=""
    RT_DETAIL="config $2; binary shfmt on PATH"
    ;;
  *)
    RT_ADAPTER=shellcheck RT_TOOL=shellcheck RT_BIN=shellcheck RT_INSTALL="$BF_SC_INSTALL"
    RT_CONFIGS=".shellcheckrc shellcheckrc"
    bf_sc_script
    RT_DETAIL="config $2; binary shellcheck on PATH"
    ;;
  esac
}

bf__rel() {
  local rel="${1#"$2"}"
  rel="${rel#/}"
  BF_REL="${rel:+$rel/}$3"
}

rt_adapter() {
  bf__dir "$2" "$3"
  if [[ "$1" == format ]]; then
    bf__walk "$BF_DIR" "$3" editorconfig_shell_section_here || return 1
    bf__rel "$BF_WALK_DIR" "$3" .editorconfig
  elif bf__walk "$BF_DIR" "$3" bf__shellcheckrc_here; then
    bf__rel "$BF_WALK_DIR" "$3" .shellcheckrc
    [[ -e "$BF_WALK_DIR/.shellcheckrc" ]] || bf__rel "$BF_WALK_DIR" "$3" shellcheckrc
  else
    BF_REL="none (ShellCheck defaults)"
  fi
  bf__set "$1" "$BF_REL" "$3"
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh
rt_adapter_in_repo() {
  local f=""
  if [[ "$1" == format ]]; then
    if editorconfig_shell_section_here "$2"; then
      f=.editorconfig
    else
      while IFS= read -r f; do
        [[ "$f" == */* ]] && editorconfig_shell_section_here "$2/${f%/*}" && break
        f=""
      done < <(rt_git -C "$2" ls-files -- ':(glob)**/.editorconfig' 2>/dev/null)
    fi
    if [[ -z "$f" ]]; then
      RT_DETAIL="no .editorconfig section names shell files"
      return 1
    fi
  else
    if [[ -e "$2/.shellcheckrc" ]]; then
      f=.shellcheckrc
    elif [[ -e "$2/shellcheckrc" ]]; then
      f=shellcheckrc
    else
      f="$(rt_git -C "$2" ls-files -- ':(glob)**/.shellcheckrc' ':(glob)**/shellcheckrc' 2>/dev/null | head -n 1)"
    fi
    [[ -n "$f" ]] || f="none (ShellCheck defaults)"
  fi
  bf__set "$1" "$f" "$2"
}
