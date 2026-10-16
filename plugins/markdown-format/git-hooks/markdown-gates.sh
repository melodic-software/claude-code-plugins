#!/usr/bin/env bash
# Gates shared by the PostToolBatch rewrite (hooks/markdown-format.sh) and the
# pre-commit entry (git-hooks/markdown-check.sh), so both decide the same way
# which files markdownlint-cli2 may touch and which binary runs. Sourced, never
# run; the installer copies it beside the entry script.
#
#   md_config_state <file> <root>   set MD_STATE for the file: "none" when no
#                                   markdownlint config governs it, "plain" when
#                                   one does, "code" when a governing config can
#                                   run repository code
#   md_local_bin <dir> <root>       print a repo-local node_modules/.bin shim
#                                   whose physical target stays inside <root>
#
# A markdownlint config is the opt-in: markdownlint-cli2 ships a default rule
# set, so a run without one would impose a style the repository never chose.
# The candidates are the files markdownlint-cli2 discovers on its own (its README
# "Configuration" section); a package.json property is honored only under an
# explicit --config flag, so it is no opt-in.
#
# A config that can run code (.cjs or .mjs, or customRules, markdownItPlugins and
# outputFormatters keys) is never run: the check cannot show what it would
# execute. The key test is a plain-text over-approximation, so a double-quoted
# string holding a backslash, or a YAML escape or tag able to spell a key
# differently, counts as code too.

md_runs_code() {
  case "$1" in
  *.cjs | *.mjs) return 0 ;;
  *markdownlint-cli2.jsonc | *markdownlint-cli2.yaml) ;;
  *) return 1 ;;
  esac
  grep -Eq 'customRules|markdownItPlugins|outputFormatters' "$1" 2>/dev/null && return 0
  grep -Eq $'"[^"]*\\\\' "$1" 2>/dev/null && return 0
  case "$1" in
  *.yaml) grep -Eq '\\$|!![A-Za-z]' "$1" 2>/dev/null && return 0 ;;
  *) ;;
  esac
  return 1
}

# The first config of each family wins in a directory, as markdownlint-cli2
# resolves it, so a shadowed executable config does not count.
md_scan_dir() {
  local c
  for c in .markdownlint-cli2.jsonc .markdownlint-cli2.yaml .markdownlint-cli2.cjs .markdownlint-cli2.mjs; do
    if [[ -f "$1/$c" ]]; then
      md_note_config "$1/$c"
      break
    fi
  done
  for c in .markdownlint.jsonc .markdownlint.json .markdownlint.yaml .markdownlint.yml .markdownlint.cjs .markdownlint.mjs; do
    if [[ -f "$1/$c" ]]; then
      case "$c" in
      *.cjs | *.mjs) MD_STATE=code ;;
      *) [[ "$MD_STATE" == code ]] || MD_STATE=plain ;;
      esac
      break
    fi
  done
}

md_note_config() {
  if md_runs_code "$1"; then
    MD_STATE=code
  elif [[ "$MD_STATE" != code ]]; then
    MD_STATE=plain
  fi
}

# Walks from the file's directory up to <root> inclusive; <root> is "." for a
# repo-relative path or an absolute directory the file lies under. A directory
# above the root is never read: a walk past the repository would adopt someone
# else's config as this repository's opt-in.
md_config_state() {
  local dir="${1%/*}" root="$2"
  [[ "$dir" == "$1" ]] && dir=.
  MD_STATE=none
  if [[ "$root" != . ]]; then
    case "$dir/" in
    "${root%/}"/*) ;;
    *) return 0 ;;
    esac
  fi
  while :; do
    md_scan_dir "$dir"
    [[ "$dir" == "$root" || "$dir" == . || "$dir" == / ]] && break
    case "$dir" in
    */*)
      dir="${dir%/*}"
      [[ -n "$dir" ]] || dir=/
      ;;
    *) dir=. ;;
    esac
  done
}

# Walks from <dir> up to <root>, so a monorepo workspace install is found. A
# shim is accepted only after its symlinks are followed and the physical target
# lies in this repository's node_modules tree, which rejects a checked-in or
# replaced .bin symlink that points out of the repository.
md_local_bin() {
  local dir="$1" root cand target link tdir here parent depth
  root="$(cd -P -- "$2" 2>/dev/null && pwd -P)" || return 1
  while :; do
    cand="$dir/node_modules/.bin/markdownlint-cli2"
    if [[ -f "$cand" && -x "$cand" ]]; then
      target="$cand"
      depth=0
      while [[ -L "$target" ]]; do
        depth=$((depth + 1))
        ((depth <= 32)) || return 1
        link="$(readlink "$target" 2>/dev/null)" || return 1
        case "$link" in
        /*) target="$link" ;;
        *) target="${target%/*}/$link" ;;
        esac
      done
      if [[ -f "$target" && -x "$target" ]]; then
        tdir="$(cd -P -- "${target%/*}" 2>/dev/null && pwd -P)" || tdir=""
        case "$tdir/${target##*/}" in
        "$root"/node_modules/* | "$root"/*/node_modules/*)
          printf '%s' "$cand"
          return 0
          ;;
        *) ;;
        esac
      fi
    fi
    here="$(cd -P -- "$dir" 2>/dev/null && pwd -P)" || return 1
    [[ "$here" == "$root" || "$here" == / ]] && return 1
    case "$dir" in
    */*)
      parent="${dir%/*}"
      [[ -n "$parent" ]] || parent=/
      ;;
    *) parent=. ;;
    esac
    [[ "$parent" == "$dir" ]] && return 1
    dir="$parent"
  done
}
