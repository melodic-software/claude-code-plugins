#!/usr/bin/env bash
# resolve-config.sh — resolve the testing plugin's .claude/testing.yaml cascade.
#
# LAYERS, per the config-cascade convention, in order: user-global
# (~/.claude/testing.yaml), team (<root>/.claude/testing.yaml)
# and a gitignored personal overlay (<root>/.claude/testing.local.yaml). Lists
# concatenate with the first occurrence kept; a scalar in a later layer
# overrides. The format is the adapters' YAML subset, parsed by
# skills/audit/scripts/adapter-load.awk -v MODE=config (its header lists the
# keys), so no jq, yq or Python is needed.
#
# OUTPUT, one record per line, `<key> <tab> <value>`:
#   layer               a layer file that is present, in cascade order
#   adapters.enable     adapter id; when any is listed, only listed adapters run
#   adapters.disable    adapter id; wins over enable
#   paths.include       glob relative to <root>, normalized
#   paths.exclude       glob relative to <root>, normalized; wins over include
#   adapter_dirs        absolute directory of consumer adapters (a leading ~/
#                       is $HOME)
#   extend.<id>.<field> one item appended to that adapter's list field
#   rules.<slug>        off | warn | error (test-weaken-block: the test-weaken
#                       hook denies an added skip or a removed test at error)
#   hook.uncovered      a consumer basename glob (extend.*.files, a consumer
#                       adapter's files:) no shipped hook row matches. Never a
#                       paths.include glob: it adds no basename an adapter
#                       does not already claim, and the hook rows match
#                       basenames in any directory.
# No layer present prints nothing. Adapter ids and extend fields are checked
# against the shipped adapters plus adapter_dirs.
#
# GLOBS: one matcher. Paths and globs are normalized first (backslashes to /,
# C:\ to /c/, a leading ./ dropped). ** matches across /, and **/ also matches
# no directory; * and ? never match /. Other characters are literal, [ included.
#
# CRLF and BOM: the parser strips a trailing \r and a leading UTF-8 byte-order
# mark, so a layer saved on Windows loads.
#
# Usage:
#   resolve-config.sh [--root <dir>] [--home <dir>] [--quick]
#   resolve-config.sh match <glob> <path>     exit 0 on a match, 1 otherwise
#   resolve-config.sh --help
#   source resolve-config.sh                  defines tcfg_norm, tcfg_glob_re
#
#   --root  the repository root the team and overlay layers and relative paths
#           resolve against. Default: the current directory's git toplevel,
#           else $CLAUDE_PROJECT_DIR.
#   --home  the directory holding the user-global layer. Default: $HOME.
#   --quick skip the adapter load and hook.uncovered: the test-scan hook path,
#           where the scanner's own adapter load still refuses a bad extend.
#           Adapter ids are still checked, against the adapter files' id: lines.
#
# Exit: 0 resolved, 2 usage error, a team or overlay layer that is a symlink
# or under a symlinked <root>/.claude, or an unreadable, unparsable or invalid
# layer (the file and line are named on stderr).

# tcfg_norm <path or glob>: set TCFG_NORM to it normalized.
tcfg_norm() {
  local p="${1//\\//}"
  if [[ "$p" =~ ^([A-Za-z]):/(.*)$ ]]; then
    p="/${BASH_REMATCH[1],,}/${BASH_REMATCH[2]}"
  fi
  while [[ "$p" == ./* ]]; do p="${p#./}"; done
  TCFG_NORM="$p"
}

# tcfg_glob_re <normalized glob>: set TCFG_RE to the anchored ERE it means.
tcfg_glob_re() {
  local g="$1" re="" c i
  for ((i = 0; i < ${#g}; i++)); do
    c="${g:i:1}"
    if [[ "$c" == '*' && "${g:i+1:1}" == '*' ]]; then
      if [[ "${g:i+2:1}" == / ]]; then
        re+='(.*/)?'
        i=$((i + 2))
      else
        re+='.*'
        i=$((i + 1))
      fi
    else
      case "$c" in
      '*') re+='[^/]*' ;;
      '?') re+='[^/]' ;;
      '^') re+='\^' ;;
      '.' | '[' | ']' | '$' | '(' | ')' | '+' | '{' | '}' | '|') re+="[$c]" ;;
      *) re+="$c" ;;
      esac
    fi
  done
  TCFG_RE="^$re\$"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0
set -uo pipefail

die() {
  printf 'resolve-config: %s\n' "$1" >&2
  exit 2
}

usage() {
  sed -n '2,/^# layer (the file/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

if [[ "${1:-}" == match ]]; then
  [[ $# -eq 3 ]] || die "match needs <glob> <path>"
  tcfg_norm "$2"
  tcfg_glob_re "$TCFG_NORM"
  tcfg_norm "$3"
  [[ "$TCFG_NORM" =~ $TCFG_RE ]]
  exit
fi

ROOT=""
USER_HOME_DIR="${HOME:-}"
QUICK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  --root)
    [[ $# -gt 1 ]] || die "--root needs a directory"
    ROOT="$2"
    shift
    ;;
  --quick) QUICK=1 ;;
  --home)
    [[ $# -gt 1 ]] || die "--home needs a directory"
    USER_HOME_DIR="$2"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument '$1'" ;;
  esac
  shift
done

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  ROOT="${ROOT:-${CLAUDE_PROJECT_DIR:-}}"
  [[ -n "$ROOT" ]] || die "not inside a git repository, no CLAUDE_PROJECT_DIR and no --root given"
fi
[[ -d "$ROOT" ]] || die "--root '$ROOT' is not a directory"

PLUGIN="${BASH_SOURCE[0]%/*}"
[[ "$PLUGIN" == "${BASH_SOURCE[0]}" ]] && PLUGIN=.
PLUGIN="$PLUGIN/.."
LOADER="$PLUGIN/skills/audit/scripts/adapter-load.awk"

layers=()
declare -A layer_seen=()
for f in ${USER_HOME_DIR:+"$USER_HOME_DIR/.claude/testing.yaml"} \
  "$ROOT/.claude/testing.yaml" "$ROOT/.claude/testing.local.yaml"; do
  [[ -f "$f" && -z "${layer_seen[$f]:-}" ]] || continue
  # A repository could point a symlinked layer at any file and have it parsed.
  if [[ "$f" == "$ROOT"/* ]] && [[ -L "$f" || -L "$ROOT/.claude" ]]; then
    die "layer is a symlink or under a symlinked .claude, refusing to read it: $f"
  fi
  [[ -r "$f" ]] || die "layer is not readable: $f"
  layer_seen[$f]=1
  layers+=("$f")
done
[[ ${#layers[@]} -gt 0 ]] || exit 0

records="$(awk -v MODE=config -f "$LOADER" "${layers[@]}")" || exit 2

out=()
dirs=()
ids=()
consumer_globs=()
ext=""
for f in "${layers[@]}"; do out+=("layer"$'\t'"$f"); done
while IFS=$'\t' read -r key val; do
  [[ -n "$key" ]] || continue
  case "$key" in
  paths.include | paths.exclude)
    tcfg_norm "$val"
    val="$TCFG_NORM"
    ;;
  adapter_dirs)
    tcfg_norm "$val"
    val="$TCFG_NORM"
    [[ "$val" == \~/* ]] && val="${HOME:-}/${val#\~/}"
    [[ "$val" == /* ]] || val="$ROOT/$val"
    [[ -d "$val" ]] || die "adapter_dirs entry is not a directory: $val"
    val="$(cd "$val" && pwd)"
    dirs+=("$val")
    ;;
  adapters.enable | adapters.disable) ids+=("$val") ;;
  extend.*)
    rest="${key#extend.}"
    ext+="${rest%%.*}"$'\t'"${rest#*.}"$'\t'"$val"$'\n'
    [[ "${rest#*.}" == files ]] && consumer_globs+=("$val")
    ;;
  *) ;;
  esac
  out+=("$key"$'\t'"$val")
done <<<"$records"

# Adapter ids come from the id: lines, so --quick checks them without a load.
extra=()
for d in ${dirs[@]+"${dirs[@]}"}; do
  for f in "$d"/*.yaml; do [[ -f "$f" ]] && extra+=("$f"); done
done
id_lines() { sed -n "s/^id:[[:space:]]*['\"]\{0,1\}\([A-Za-z0-9_.-]*\).*/\1/p" "$@"; }
declare -A known=() shipped=()
while read -r id; do shipped[$id]=1; done < <(id_lines "$PLUGIN"/skills/audit/adapters/*.yaml)
while read -r id; do known[$id]=1; done < <(id_lines "$PLUGIN"/skills/audit/adapters/*.yaml ${extra[@]+"${extra[@]}"})
for id in ${ids[@]+"${ids[@]}"}; do
  [[ -z "${known[$id]:-}" ]] || continue
  loc="${layers[*]}"
  for f in "${layers[@]}"; do
    if n="$(grep -nwF -m1 -- "$id" "$f")"; then
      loc="$f:${n%%:*}"
      break
    fi
  done
  die "$loc: unknown adapter: $id (in adapters.enable or adapters.disable)"
done
if ((QUICK)); then
  printf '%s\n' "${out[@]}"
  exit 0
fi

# Load every adapter once with the extensions applied, so a bad extension
# fails here, where the layer is named, not mid-scan.
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
printf '%s' "$ext" >"$W/extend"
table="$(awk -v EXTEND="${W}/extend" -f "$LOADER" "$PLUGIN"/skills/audit/adapters/*.yaml ${extra[@]+"${extra[@]}"})" ||
  die "adapter load failed with this config (layers: ${layers[*]})"
while IFS=$'\t' read -r id key val; do
  [[ "$key" == files && -z "${shipped[$id]:-}" ]] && consumer_globs+=("$val")
done <<<"$table"

# A consumer glob is covered when a shipped hook row names it, or when it is a
# literal name a shipped row's glob matches.
mapfile -t hook_globs < <(sed -n 's/^ *"if": "Write(\(.*\))",*$/\1/p' "$PLUGIN/hooks/hooks.json")
declare -A reported=()
for g in ${consumer_globs[@]+"${consumer_globs[@]}"}; do
  [[ -z "${reported[$g]:-}" ]] || continue
  covered=0
  for h in "${hook_globs[@]}"; do
    # shellcheck disable=SC2053 # the shipped glob is a pattern on purpose
    if [[ "$g" == "$h" ]] || [[ "$g" != *[*?[]* && "$g" == $h ]]; then
      covered=1
      break
    fi
  done
  reported[$g]=1
  ((covered)) || out+=("hook.uncovered"$'\t'"$g")
done
printf '%s\n' "${out[@]}"
