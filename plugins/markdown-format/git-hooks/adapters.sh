#!/bin/sh
# shellcheck shell=bash
# shellcheck disable=SC2154 # the MD_* gate results come from markdown-gates.sh, sourced first
# markdown-format's side of lib/git-hooks/resolve-tool.sh: the ecosystem id whose
# record setup reports (hooks never run it), the files it acts on, and its
# markdownlint-cli2 adapter. Sourced by the batch hook and both git-hook
# entries, after markdown-gates.sh.
#
# The adapter governs a file only when a markdownlint config governs it
# (md_config_state) and, for a config that can run repository code, only once
# the user approved that config state (md_trust); a file held back by the trust
# gate is noted in MF_HELD for the lint entry's notice. markdownlint-cli2 comes
# from PATH, else the repository's own node_modules/.bin (md_local_bin).
# Format is `--fix`, which applies only the fixes markdownlint's rules carry;
# lint reports and fixes nothing. Each file reaches the tool with a ":" prefix,
# markdownlint-cli2's literal-path form, so no name is read as a glob or a
# negation.

# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_PLUGIN=markdown-format
# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_IDS=markdown
# shellcheck disable=SC2034 # read by the entries: the config names whose drift refuses a commit
RT_DRIFT_CONFIGS=".markdownlint-cli2.jsonc .markdownlint-cli2.yaml .markdownlint-cli2.cjs .markdownlint-cli2.mjs .markdownlint.jsonc .markdownlint.json .markdownlint.yaml .markdownlint.yml .markdownlint.cjs .markdownlint.mjs"
MF_INSTALL='npm i -D markdownlint-cli2, or another method at https://github.com/DavidAnson/markdownlint-cli2'
# Each held config set once: "<configs>\t<verdict>\t<approval dir>".
MF_HELD=()

rt_wants() {
  case "$1" in
  .githooks/* | */.githooks/*) return 1 ;;
  *.md | *.mdc) return 0 ;;
  *) return 1 ;;
  esac
}

# mf__bin <dir> <root>: sets RT_BIN to markdownlint-cli2 on PATH, else the
# repository's own shim walking up from <dir>, absolute; else the bare name, so
# the missing-tool rule reports it.
mf__bin() {
  if [[ -z "${MF_ON_PATH:-}" ]]; then
    MF_ON_PATH=no
    command -v markdownlint-cli2 >/dev/null 2>&1 && MF_ON_PATH=yes
  fi
  RT_BIN=markdownlint-cli2
  [[ "$MF_ON_PATH" == yes ]] && return 0
  local bin
  bin="$(md_local_bin "$1" "$2")" || return 0
  [[ "$bin" == /* || "$bin" == [A-Za-z]:[\\/]* ]] || bin="$2/${bin#./}"
  RT_BIN="$bin"
}

# mf__rel <path> <root>: sets MF_REL to <path> relative to <root>.
mf__rel() {
  MF_REL="${1#./}"
  MF_REL="${MF_REL#"$2"/}"
}

# mf__detail <config> <config root> <root>: RT_DETAIL names the config and the
# binary, each relative to the repository root.
mf__detail() {
  local bin
  mf__rel "$1" "$2"
  bin="${RT_BIN#"$2"/}"
  bin="${bin#"$3"/}"
  [[ "$bin" == markdownlint-cli2 ]] && bin="markdownlint-cli2 on PATH"
  RT_DETAIL="config $MF_REL; binary $bin"
}

# mf__hold <root>: note the code configs the trust gate holds back, once.
mf__hold() {
  local c configs="" entry
  for c in "${MD_CODE_CONFIGS[@]}"; do
    mf__rel "$c" "$1"
    configs+="${configs:+, }$MF_REL"
  done
  case "$MD_TRUST" in
  gate) RT_DETAIL="config $configs can run repository code and is not approved" ;;
  unverifiable) RT_DETAIL="config $configs cannot be verified free of repository code" ;;
  unpinnable) RT_DETAIL="config $configs names code through an expression no approval can pin" ;;
  *) RT_DETAIL="config $configs can run repository code and there is no approval store" ;;
  esac
  entry="$configs"$'\t'"$MD_TRUST"$'\t'"$MD_TRUST_DIR"
  for c in ${MF_HELD[@]+"${MF_HELD[@]}"}; do
    [[ "$c" == "$entry" ]] && return 0
  done
  MF_HELD+=("$entry")
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh and the entries
rt_adapter() { # <concern> <file> <root>
  local f="$2" root="$3" dir name croot
  if [[ "$f" != /* && "$f" != [A-Za-z]:[\\/]* && "$root" == "$PWD" ]]; then
    # A repository-relative path from the repository root: walk it as is.
    croot=.
    md_config_state "$f" .
    dir="${f%/*}"
    [[ "$dir" == "$f" ]] && dir=.
  else
    # Both sides physical, so a symlinked directory or checkout compares equal.
    [[ "$f" == /* || "$f" == [A-Za-z]:[\\/]* ]] || f="$root/$f"
    name="${f##*/}"
    dir="$(cd -P -- "${f%/*}" 2>/dev/null && pwd -P)" || return 1
    if [[ "${MF_PROOT_FOR:-}" != "$root" ]]; then
      MF_PROOT="$(cd -P -- "$root" 2>/dev/null && pwd -P)" || return 1
      MF_PROOT_FOR="$root"
    fi
    croot="$MF_PROOT"
    md_config_state "$dir/$name" "$croot"
  fi
  case "$MD_STATE" in
  none)
    RT_DETAIL="no markdownlint config"
    return 1
    ;;
  code)
    md_trust "$croot"
    if [[ "$MD_TRUST" != approved ]]; then
      mf__hold "$croot"
      return 1
    fi
    ;;
  *) ;;
  esac
  mf__bin "$dir" "$root"
  mf__detail "$MD_NEAREST" "$croot" "$root"
  RT_ADAPTER=markdownlint-cli2 RT_TOOL=markdownlint-cli2 RT_DIR="$root" RT_INSTALL="$MF_INSTALL"
  RT_CONFIGS="$RT_DRIFT_CONFIGS"
  # shellcheck disable=SC2016 # the command text sh -c expands, with RT_BIN and the files
  case "$1" in
  format) RT_SCRIPT='for f do set -- "$@" ":$f"; shift; done; exec "$RT_BIN" --fix "$@"' ;;
  *) RT_SCRIPT='for f do set -- "$@" ":$f"; shift; done; exec "$RT_BIN" "$@"' ;;
  esac
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh
rt_adapter_in_repo() { # <concern> <root>
  local c found=""
  for c in $RT_DRIFT_CONFIGS; do
    [[ -f "$2/$c" ]] && found="$c" && break
  done
  if [[ -z "$found" ]]; then
    local specs=()
    for c in $RT_DRIFT_CONFIGS; do
      specs+=(":(glob)**/$c")
    done
    found="$(git -C "$2" ls-files -- "${specs[@]}" 2>/dev/null | grep -v -e '^node_modules/' -e '/node_modules/' | head -n 1)"
  fi
  if [[ -z "$found" ]]; then
    RT_DETAIL="no markdownlint config"
    return 1
  fi
  mf__bin "$2" "$2"
  RT_ADAPTER=markdownlint-cli2 RT_TOOL=markdownlint-cli2
  mf__detail "$found" "$2" "$2"
}
