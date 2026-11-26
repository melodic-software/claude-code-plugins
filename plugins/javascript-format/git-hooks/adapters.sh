#!/bin/sh
# shellcheck shell=bash

# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_PLUGIN=javascript-format
# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_IDS="typescript javascript json"
# shellcheck disable=SC2034 # read by the entries: the config names whose drift refuses a commit
RT_DRIFT_CONFIGS="biome.json biome.jsonc"
JF_INSTALL='npm i -D @biomejs/biome, or another method at https://biomejs.dev/guides/getting-started/'
JF_CONCISE='s/^[^ ][^ ]* \([^:]*:[0-9][0-9]*:[0-9][0-9]*: \)/\1/
t
s/^/biome: /'
JF_LINT_FLAGS='lint --reporter=concise --error-on-warnings --max-diagnostics=none --no-errors-on-unmatched'

rt_wants() {
  case "$1" in
  .githooks/*) return 1 ;;
  *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.mts | *.cts | *.json | *.jsonc) return 0 ;;
  *) return 1 ;;
  esac
}

jf__config_here() {
  [[ -f "$1/biome.json" || -f "$1/biome.jsonc" ]]
}

jf__topmost() {
  local dir="$1"
  JF_CONFIG_DIR=""
  while :; do
    jf__config_here "$dir" && JF_CONFIG_DIR="$dir"
    [[ "$dir" == "$2" || "$dir" != */* ]] && break
    dir="${dir%/*}"
    [[ -n "$dir" ]] || break
  done
  [[ -n "$JF_CONFIG_DIR" ]]
}

jf__local_bin_here() {
  [[ -x "$1/node_modules/.bin/biome" && -z "$(rt_git -C "$1" ls-files -- ':(literal)node_modules' 2>/dev/null)" ]]
}

jf__dir() {
  JF_DIR="$1"
  [[ "$JF_DIR" == /* || "$JF_DIR" == [A-Za-z]:[\\/]* ]] || JF_DIR="$2/$JF_DIR"
  [[ "$JF_DIR" == */* ]] && JF_DIR="${JF_DIR%/*}"
  return 0
}

jf__biome() {
  if [[ "${JF_BIN_FROM:-}" != "$1|$2" ]]; then
    local dir="$1"
    JF_BIN=biome
    while :; do
      if jf__local_bin_here "$dir"; then
        JF_BIN="$dir/node_modules/.bin/biome"
        break
      fi
      [[ "$dir" == "$2" || "$dir" != */* ]] && break
      dir="${dir%/*}"
      [[ -n "$dir" ]] || break
    done
    JF_BIN_FROM="$1|$2"
  fi
  RT_BIN="$JF_BIN"
}

jf__detail() {
  local name rel="${1#"$2"}"
  rel="${rel#/}"
  name=biome.json
  [[ -f "$1/$name" ]] || name=biome.jsonc
  local bin="${RT_BIN#"$2"/}"
  [[ "$bin" == biome ]] && bin="biome on PATH"
  RT_DETAIL="config ${rel:+$rel/}$name; binary $bin"
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh and the entries
rt_adapter() {
  jf__dir "$2" "$3"
  jf__topmost "$JF_DIR" "$3" || return 1
  jf__biome "$JF_DIR" "$3"
  jf__detail "$JF_CONFIG_DIR" "$3"
  RT_ADAPTER=biome RT_TOOL=biome RT_DIR="$JF_CONFIG_DIR" RT_INSTALL="$JF_INSTALL"
  RT_CONFIGS="biome.json biome.jsonc"
  # shellcheck disable=SC2016 # the command text sh -c expands, with RT_BIN and the files
  case "$1" in
  format)
    RT_SCRIPT='unset BIOME_CONFIG_PATH; exec "$RT_BIN" check --write --linter-enabled=false --no-errors-on-unmatched -- "$@"'
    ;;
  *)
    RT_SCRIPT='unset BIOME_CONFIG_PATH; o="$("$RT_BIN" '"$JF_LINT_FLAGS"' -- "$@" 2>&1)"; s=$?; printf "%s\n" "$o" | sed -e '"'$JF_CONCISE'"'; exit "$s"'
    ;;
  esac
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh
rt_adapter_in_repo() {
  local f config_dir="$2"
  if ! jf__config_here "$2"; then
    f="$(rt_git -C "$2" ls-files -- ':(glob)**/biome.json' ':(glob)**/biome.jsonc' 2>/dev/null | head -n 1)"
    if [[ -z "$f" ]]; then
      RT_DETAIL="no Biome config"
      [[ -f "$2/.biome.json" || -f "$2/.biome.jsonc" ]] && RT_DETAIL="no Biome config: a hidden .biome.json does not opt in"
      return 1
    fi
    [[ "$f" == */* ]] && config_dir="$2/${f%/*}"
  fi
  jf__biome "$config_dir" "$2"
  RT_ADAPTER=biome RT_TOOL=biome
  jf__detail "$config_dir" "$2"
}

rt_config_counts() { return 0; }

rt_lint_index() {
  local base="${CHECKS_TMP:?}/staged" rel=. rest="$1" name sub
  mkdir -p "$base"
  while :; do
    for name in biome.json biome.jsonc .gitignore .ignore; do
      [[ -f "$rel/$name" ]] && cp "$rel/$name" "$base/$rel/$name"
    done
    [[ "$rest" == */* ]] || break
    rel="$rel/${rest%%/*}"
    rest="${rest#*/}"
    mkdir -p "$base/$rel"
  done
  rt_git show ":$1" >"$base/$1" 2>/dev/null
  sub="${RT_DIR#"$RT_ROOT"}"
  sub="${sub#/}"
  local o s
  # shellcheck disable=SC2086 # the flags split on spaces
  o="$(cd "$base${sub:+/$sub}" && unset BIOME_CONFIG_PATH && "$RT_BIN" $JF_LINT_FLAGS -- "${1#"${sub:+$sub/}"}" 2>&1)"
  s=$?
  printf '%s\n' "$o" | sed -e "$JF_CONCISE"
  return "$s"
}
