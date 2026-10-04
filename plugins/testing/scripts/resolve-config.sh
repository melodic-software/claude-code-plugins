#!/usr/bin/env bash
# resolve-config.sh — resolve the testing plugin's config cascade.
#
# LAYERS, per the config-cascade convention, in order: user-global
# (~/.claude/testing.yaml), team and a gitignored personal overlay
# (<root>/.claude/testing.local.yaml). The team layer is
# <root>/docs/conventions/testing.yaml when it exists (schema:
# schemas/testing.schema.json). Without it, the team layer is the ```yaml config
# block of <root>/docs/conventions/testing.md when that file holds one, else
# <root>/.claude/testing.yaml; the docs block is read for one more release. The
# first of the three present wins, and a warning naming it and each other one
# present goes to stderr. Lists concatenate with the first
# occurrence kept; a scalar in a later layer overrides. The format is the
# adapters' YAML subset, parsed by skills/audit/scripts/adapter-load.awk
# -v MODE=config (its header lists the keys and the block form), so no jq, yq
# or Python is needed. An error in the block names the .md file and its own
# line.
#
# OUTPUT, one record per line, `<key> <tab> <value>`:
#   layer               a layer file that is read, in cascade order (the .md
#                       file when the docs block is the team layer)
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
# E2E: `resolve-config.sh e2e` resolves /testing:run-e2e's keys instead, each
# top-level in the same files: e2e_driver (auto | harness | run | playwright |
# chrome) and reuse_running_instance (auto | true | false), both default auto.
# It prints `<key> <tab> <value> <tab> <source>` per key, the source being the
# layer file, userConfig, or default. Highest first: the overlay,
# docs/conventions/testing.yaml, the user-global file, then the --user value
# (the rendered userConfig option; an unrendered ${user_config.<key>} or an
# empty value is unset). The first that sets the key decides; an unknown,
# nested or unparsable value there is named on stderr and the key takes its
# default, never a lower layer's value. The docs block and .claude/testing.yaml are not read for
# these keys: a release older than this mode refuses them there, which stops
# its scan. Each value goes through parse-concern-value.sh, so the scan keys'
# grammar never applies, and a scan config that does not resolve, a missing
# repository or a symlinked layer (skipped with a warning) never stops it.
#
# Usage:
#   resolve-config.sh [--root <dir>] [--home <dir>] [--quick]
#   resolve-config.sh e2e [--root <dir>] [--home <dir>] [--user <key>=<value>]...
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
# or under a symlinked directory inside <root>, or an unreadable, unparsable or invalid
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
MODE=scan
users=()
if [[ "${1:-}" == e2e ]]; then
  MODE=e2e
  shift
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
  --root)
    [[ $# -gt 1 ]] || die "--root needs a directory"
    ROOT="$2"
    shift
    ;;
  --user)
    [[ "$MODE" == e2e ]] || die "--user is an e2e option"
    [[ $# -gt 1 && "$2" == *=* ]] || die "--user takes <key>=<value>"
    case "${2%%=*}" in
    e2e_driver | reuse_running_instance) users+=("$2") ;;
    *) die "--user names a run-e2e key: e2e_driver or reuse_running_instance" ;;
    esac
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
  [[ -n "$ROOT" || "$MODE" == e2e ]] || die "not inside a git repository, no CLAUDE_PROJECT_DIR and no --root given"
fi
[[ -z "$ROOT" || -d "$ROOT" ]] || die "--root '$ROOT' is not a directory"

PLUGIN="${BASH_SOURCE[0]%/*}"
[[ "$PLUGIN" == "${BASH_SOURCE[0]}" ]] && PLUGIN=.
LOADER="$PLUGIN/../skills/audit/scripts/adapter-load.awk"
PCV="$PLUGIN/parse-concern-value.sh"
PLUGIN="$PLUGIN/.."

warn() { printf 'resolve-config: warning: %s\n' "$1" >&2; }

# under_link <file>: true when <file>, or a directory above it inside <root>,
# is a symlink. A repository could point such a layer at any file.
under_link() {
  local d="$1"
  [[ -n "$ROOT" ]] || return 1
  while [[ "$d" == "$ROOT"/* ]]; do
    [[ ! -L "$d" ]] || return 0
    d="${d%/*}"
  done
  return 1
}

# in_list <value> <allowed>...: true when <value> is one of <allowed>.
in_list() {
  local v="$1" a
  shift
  for a in "$@"; do [[ "$v" == "$a" ]] && return 0; done
  return 1
}

# e2e: print each run-e2e key's value and source (header, E2E). Exit 0.
e2e() {
  local key val src def f u raw lines allowed files=() user_driver="" user_reuse=""
  for u in ${users[@]+"${users[@]}"}; do
    val="${u#*=}"
    # shellcheck disable=SC2016 # the literal an unrendered option leaves
    [[ "$val" != '${user_config.'* ]] || val=""
    case "${u%%=*}" in
    e2e_driver) user_driver="$val" ;;
    *) user_reuse="$val" ;;
    esac
  done
  for f in ${ROOT:+"$ROOT/.claude/testing.local.yaml" "$ROOT/docs/conventions/testing.yaml"} \
    ${USER_HOME_DIR:+"$USER_HOME_DIR/.claude/testing.yaml"}; do
    [[ -f "$f" ]] || continue
    if under_link "$f"; then
      warn "skipping a layer that is a symlink or under a symlinked directory: $f"
    elif [[ ! -r "$f" ]]; then
      warn "skipping a layer that is not readable: $f"
    else
      files+=("$f")
    fi
  done
  for key in e2e_driver reuse_running_instance; do
    if [[ "$key" == e2e_driver ]]; then
      allowed="auto harness run playwright chrome" u="$user_driver"
    else
      allowed="auto true false" u="$user_reuse"
    fi
    def="${allowed%% *}" val="" src="" raw=""
    for f in ${files[@]+"${files[@]}"}; do
      # The first layer with the key's top-level line sets it; only that line
      # reaches the parser, so a nested, non-scalar or unparsable value reads
      # as empty and is reported below.
      lines="$(LC_ALL=C sed -e $'1s/^\xef\xbb\xbf//' -e 's/\r$//' "$f" | grep -E "^${key}[[:space:]]*:")" || continue
      src="$f"
      val="$(bash "$PCV" - "$key" 2>/dev/null <<<"$lines")"
      raw="${lines%%$'\n'*}" raw="${raw#*:}"
      raw="${raw#"${raw%%[![:space:]]*}"}" raw="${raw%"${raw##*[![:space:]]}"}"
      break
    done
    [[ -n "$src" || -z "$u" ]] || val="$u" src=userConfig
    # shellcheck disable=SC2086 # allowed is a fixed word list
    if [[ -n "$src" ]] && ! in_list "$val" $allowed; then
      if [[ -n "$val$raw" ]]; then
        warn "$src: $key: unknown value '${val:-$raw}'; using the default, $def"
      else
        warn "$src: $key: no scalar value; using the default, $def"
      fi
      src=""
    fi
    [[ "$src" != userConfig || "$val" != "$def" ]] || src=""
    [[ -n "$src" ]] || val="$def" src=default
    printf '%s\t%s\t%s\n' "$key" "$val" "$src"
  done
}
if [[ "$MODE" == e2e ]]; then
  e2e
  exit 0
fi

TEAM_NEW="$ROOT/docs/conventions/testing.yaml"
TEAM_DOCS="$ROOT/docs/conventions/testing.md"
TEAM_YAML="$ROOT/.claude/testing.yaml"

# gather <team file>: set layers to the user-global layer, that team layer and
# the overlay, as present.
layers=()
declare -A layer_seen=()
gather() {
  local f
  layers=()
  layer_seen=()
  for f in ${USER_HOME_DIR:+"$USER_HOME_DIR/.claude/testing.yaml"} \
    "$1" "$ROOT/.claude/testing.local.yaml"; do
    [[ -f "$f" && -z "${layer_seen[$f]:-}" ]] || continue
    ! under_link "$f" || die "layer is a symlink or under a symlinked directory, refusing to read it: $f"
    [[ -r "$f" ]] || die "layer is not readable: $f"
    layer_seen[$f]=1
    layers+=("$f")
  done
}

# The docs file is the team layer when it holds a config block; else the
# loader's `block` record is absent and .claude/testing.yaml is read instead.
load() {
  ((${#layers[@]})) || return 0
  awk -v MODE=config -f "$LOADER" "${layers[@]}"
}
if [[ -f "$TEAM_NEW" ]]; then
  gather "$TEAM_NEW"
  records="$(load)" || exit 2
  if [[ -f "$TEAM_DOCS" && ! -L "$TEAM_DOCS" ]] && grep -q '^```yaml config[[:space:]]*$' "$TEAM_DOCS"; then
    warn "$TEAM_NEW and $TEAM_DOCS both exist; using $TEAM_NEW, ignoring the docs block"
  fi
  [[ ! -f "$TEAM_YAML" ]] || warn "$TEAM_NEW and $TEAM_YAML both exist; using $TEAM_NEW, ignoring the .claude file"
elif [[ -f "$TEAM_DOCS" ]]; then
  gather "$TEAM_DOCS"
  records="$(load)" || exit 2
  if [[ "$records" != block$'\t'* ]]; then
    gather "$TEAM_YAML"
    records="$(load)" || exit 2
  elif [[ -f "$TEAM_YAML" ]]; then
    warn "$TEAM_DOCS and $TEAM_YAML both exist; using the docs block, ignoring the .claude file"
  fi
else
  gather "$TEAM_YAML"
  records="$(load)" || exit 2
fi
[[ ${#layers[@]} -gt 0 ]] || exit 0

out=()
dirs=()
ids=()
consumer_globs=()
ext=""
blk_from=1 blk_to=0
for f in "${layers[@]}"; do out+=("layer"$'\t'"$f"); done
while IFS=$'\t' read -r key val; do
  [[ -n "$key" ]] || continue
  case "$key" in
  block)
    IFS=$'\t' read -r _ blk_from blk_to <<<"$val"
    continue
    ;;
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
    # In the docs file only the config block's lines count.
    from=1 to='$'
    [[ "$f" == "$TEAM_DOCS" ]] && from="$blk_from" to="$blk_to"
    if n="$(sed -n "${from},${to}p" "$f" | grep -nwF -m1 -- "$id")"; then
      loc="$f:$((from + ${n%%:*} - 1))"
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
