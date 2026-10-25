#!/usr/bin/env bash
# resolve-config.sh — resolve the docs-naming consumer configuration surface.
#
# WHY A SCRIPT AND NOT A SOURCED LIBRARY. Five callers in four skills need the
# same merged document, and each one runs in its own process against its own
# --root. A script invoked once per run returns one JSON document every caller
# reads the same way, so no two callers can disagree about what the consumer
# configured.
#
# LAYERS, per the config-cascade convention: user-global
# (~/.claude/docs-naming.json), team (<home>/docs-naming.yaml), and a gitignored
# personal overlay (<home>/docs-naming.local.yaml), applied in that order over the
# bundled defaults. <home> is the repository's convention home (docs/conventions
# unless AGENTS.md or CLAUDE.md binds another), and the YAML's keys are the
# `file_names` keys, validated by schemas/docs-naming.schema.json. When --root is
# the home directory (or an ancestor of it) or is not inside a git working tree,
# there is no team or overlay layer, and `paths` reports both as not-applicable;
# a team or overlay JSON path that is the user-global file is likewise reported
# and read once.
#
# PRE-YAML LOCATION. For one release a team or overlay layer whose YAML is absent
# is read from the JSON file it used to live in (<root>/.claude/docs-naming.json,
# <root>/.claude/docs-naming.local.json); `paths` reports the state `deprecated`,
# which `/docs-naming:setup check` turns into a WARN row. `resolve` stays quiet
# about it, because skill scripts read its stderr as their own. The YAML wins
# whenever it exists, and the two are never merged.
#
# RETIRED NAME. A layer with neither file under `docs-naming` but present under
# the retired `docs-hygiene` name (`.claude/docs-hygiene.json`, `.local.json`, and
# the user-global file) is read from there; `resolve` warns on stderr and `paths`
# reports the state `legacy`. The new name wins whenever it exists.
#
# MERGE IS PER KEY OF `file_names`, and three classes decide how:
#
#   nearest-wins  rule, regex, redirect_map. The latest layer that declares the
#                 key supplies it whole.
#   additive      roots, exempt_basenames, exempt_paths, exempt_extensions,
#                 tiers, sweep_exclude, sweep_exclude_sites. The TEAM layer
#                 replaces the bundled default whole; a PERSONAL layer only
#                 appends entries the resolved value does not carry.
#   team-only     generated. A personal layer that declares it is reported inert
#                 and ignored.
#
# The additive and team-only classes are the POLICY FLOOR. Every key in them
# decides what the realign skill will do to a tree: which files are frozen, which
# references are edited in which form, and which shell command runs after a move.
# A personal overlay that could REPLACE one could quietly widen a frozen tier or
# swap the command that regenerates a record, which is a team decision weakened
# from one machine. Appending is still allowed, because a contributor adding an
# exemption or a scope root of their own weakens nothing. The team layer is the
# authority rather than a peer, so it replaces: a repository whose defaults do
# not fit has to be able to say so, not only add to them.
#
# LAYERS ARE APPLIED team, user-global, overlay, so a personal addition is made
# to what the team decided rather than to a bundled default the team replaced.
#
# CRLF. On native Windows, jq writes \r\n (its own release notes add --binary to
# opt out, and this repository already records the class as a standing Windows
# failure). Every jq read here goes through `tr -d '\r'`, so a resolved regex
# cannot end in a carriage return and silently match nothing.
#
# Usage:
#   resolve-config.sh resolve [--root <dir>] [--home <dir>]
#   resolve-config.sh layers  [--root <dir>] [--home <dir>]
#   resolve-config.sh paths   [--root <dir>] [--home <dir>]
#   resolve-config.sh --help
#
#   resolve  print the merged document (schema + file_names) on stdout
#   layers   print `key<TAB>layers` lines, one per key, naming every layer that
#            contributed, plus `!inert:<key>` lines for ignored declarations
#   paths    print `layer<TAB>path<TAB>state` for the three layers; the state is
#            present, absent, deprecated, legacy, or a not-applicable reason
#
#   --root   the repository root to resolve the team and overlay layers against.
#            Default: `git rev-parse --show-toplevel` from the current directory,
#            never the directory this script happens to live in, so a worktree or
#            a fixture is addressed explicitly.
#   --home   the directory holding the user-global layer. Default: $HOME.
#
# Exit: 0 resolved, 2 usage error or an unreadable, unparsable, or
#       unknown-schema layer (the file is named on stderr).
# Every single-quoted `${...}` below is a jq program argument, substituted by jq
# from --arg/--argjson, never by the shell. Expanding any of them would break
# the merge, so SC2016 is disabled file-wide on purpose.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../skills/setup/templates/docs-naming.json"
# shellcheck source=../lib/layer-yaml.sh
. "$SCRIPT_DIR/../lib/layer-yaml.sh"

SCHEMA=1
NEAREST_WINS=" rule regex redirect_map "
TEAM_ONLY=" generated "
KEY_ORDER="roots rule regex exempt_basenames exempt_paths exempt_extensions tiers sweep_exclude sweep_exclude_sites generated redirect_map"

die() {
  printf 'resolve-config: %s\n' "$1" >&2
  exit "${2:-2}"
}

usage() {
  sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'
}

# jq with the Windows carriage return stripped from every line it emits.
jqr() {
  jq "$@" | tr -d '\r'
}

ACTION=""
ROOT=""
USER_HOME_DIR="${HOME:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
  resolve | layers | paths)
    [[ -z "$ACTION" ]] || die "one action per run, got '$ACTION' and '$1'"
    ACTION="$1"
    ;;
  --root)
    shift
    [[ $# -gt 0 ]] || die "--root needs a directory"
    ROOT="$1"
    ;;
  --home)
    shift
    [[ $# -gt 0 ]] || die "--home needs a directory"
    USER_HOME_DIR="$1"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown argument '$1' (actions: resolve, layers, paths)"
    ;;
  esac
  shift
done

[[ -n "$ACTION" ]] || die "no action given (actions: resolve, layers, paths)"
command -v jq >/dev/null 2>&1 || die "jq is required and is not on PATH"
[[ -f "$TEMPLATE" ]] || die "bundled defaults missing at $TEMPLATE"

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" ||
    die "not inside a git repository and no --root given"
  [[ -n "$ROOT" ]] || die "not inside a git repository and no --root given"
fi
[[ -d "$ROOT" ]] || die "--root '$ROOT' is not a directory"

USER_LAYER=""
[[ -n "$USER_HOME_DIR" ]] && USER_LAYER="$USER_HOME_DIR/.claude/docs-naming.json"

# Config-cascade step 2: a root that is the home directory or an ancestor of it,
# or that is not inside a git working tree, has no team or overlay layer, and a
# team or overlay path that is the user-global file is not read a second time.
# The home is --home, not the inherited $HOME, so a fixture is classified against
# the directory it names.
# shellcheck source=../lib/config-root.sh
. "$SCRIPT_DIR/../lib/config-root.sh"
ROOT_CLASS="$(HOME="$USER_HOME_DIR" config_root_classify "$ROOT")"
# The JSON paths are where the team and overlay layers lived before the YAML
# (read for one release); the YAML paths are where they live now, under the
# convention home. A non-repo or home root has neither.
TEAM_LAYER="$ROOT/.claude/docs-naming.json"
OVERLAY_LAYER="$ROOT/.claude/docs-naming.local.json"
TEAM_YAML=""
OVERLAY_YAML=""
TEAM_SKIP=""
OVERLAY_SKIP=""
TEAM_JSON_SKIP=""
OVERLAY_JSON_SKIP=""
if [[ "$ROOT_CLASS" != repo ]]; then
  TEAM_SKIP="not-applicable: $ROOT_CLASS root"
  OVERLAY_SKIP="$TEAM_SKIP"
else
  CONVENTION_HOME="$(layer_yaml_home "$ROOT")"
  TEAM_YAML="$ROOT/$CONVENTION_HOME/docs-naming.yaml"
  OVERLAY_YAML="$ROOT/$CONVENTION_HOME/docs-naming.local.yaml"
  config_root_paths_same "$TEAM_LAYER" "$USER_LAYER" && TEAM_JSON_SKIP="same file as the user-global layer"
  config_root_paths_same "$OVERLAY_LAYER" "$USER_LAYER" && OVERLAY_JSON_SKIP="same file as the user-global layer"
fi
[[ -n "$TEAM_SKIP$TEAM_JSON_SKIP" ]] && TEAM_LAYER=""
[[ -n "$OVERLAY_SKIP$OVERLAY_JSON_SKIP" ]] && OVERLAY_LAYER=""

# Prints the retired-name file for layer path $1 (new basename $2, old basename
# $3) when only that one exists.
retired_layer() {
  old="${1%"$2"}$3"
  [[ -n "$1" && ! -f "$1" && -f "$old" ]] && printf '%s' "$old"
  return 0
}
USER_OLD="$(retired_layer "$USER_LAYER" docs-naming.json docs-hygiene.json)"
TEAM_OLD="$(retired_layer "$TEAM_LAYER" docs-naming.json docs-hygiene.json)"
OVERLAY_OLD="$(retired_layer "$OVERLAY_LAYER" docs-naming.local.json docs-hygiene.local.json)"

# Pick the file a layer is read from, YAML first: sets <PREFIX>_PATH, <PREFIX>_KIND
# (yaml, json or empty) and <PREFIX>_STATE (present, deprecated, legacy, absent).
# $2 yaml path, $3 pre-YAML JSON path, $4 retired-name path.
choose_layer() {
  if [[ -n "$2" && -f "$2" ]]; then
    printf -v "${1}_PATH" '%s' "$2"
    printf -v "${1}_KIND" '%s' yaml
    printf -v "${1}_STATE" '%s' present
  elif [[ -n "$3" && -f "$3" ]]; then
    printf -v "${1}_PATH" '%s' "$3"
    printf -v "${1}_KIND" '%s' json
    printf -v "${1}_STATE" '%s' deprecated
  elif [[ -n "$4" ]]; then
    printf -v "${1}_PATH" '%s' "$4"
    printf -v "${1}_KIND" '%s' json
    printf -v "${1}_STATE" '%s' legacy
  else
    printf -v "${1}_PATH" '%s' "${2:-$3}"
    printf -v "${1}_KIND" '%s' ''
    printf -v "${1}_STATE" '%s' absent
  fi
}
TEAM_PATH="" TEAM_KIND="" TEAM_STATE=""
OVERLAY_PATH="" OVERLAY_KIND="" OVERLAY_STATE=""
choose_layer TEAM "$TEAM_YAML" "$TEAM_LAYER" "$TEAM_OLD"
choose_layer OVERLAY "$OVERLAY_YAML" "$OVERLAY_LAYER" "$OVERLAY_OLD"

if [[ "$ACTION" = paths ]]; then
  if [[ -n "$USER_OLD" ]]; then
    printf 'user-global\t%s\tlegacy\n' "$USER_OLD"
  elif [[ -z "$USER_LAYER" ]]; then
    printf 'user-global\t-\tno-home\n'
  elif [[ -f "$USER_LAYER" ]]; then
    printf 'user-global\t%s\tpresent\n' "$USER_LAYER"
  else
    printf 'user-global\t%s\tabsent\n' "$USER_LAYER"
  fi
  for name in team overlay; do
    if [[ "$name" = team ]]; then
      path="$TEAM_PATH" state="$TEAM_STATE" skip="$TEAM_SKIP" jskip="$TEAM_JSON_SKIP"
    else
      path="$OVERLAY_PATH" state="$OVERLAY_STATE" skip="$OVERLAY_SKIP" jskip="$OVERLAY_JSON_SKIP"
    fi
    if [[ -n "$skip" ]]; then
      printf '%s\t-\t%s\n' "$name" "$skip"
    elif [[ "$state" = absent && -n "$jskip" ]]; then
      printf '%s\t-\t%s\n' "$name" "$jskip"
    else
      printf '%s\t%s\t%s\n' "$name" "$path" "$state"
    fi
  done
  exit 0
fi

# Read one layer. Prints its JSON, or nothing when the file is absent.
# A present file that does not parse, or whose JSON schema is not this contract's,
# is fatal: a silently skipped layer is a configuration the operator believes is
# in effect and is not. A YAML layer carries no schema number; it is the
# current contract by its location.
read_layer() {
  layer_name="$1"
  layer_path="$2"
  layer_kind="${3:-json}"
  [[ -n "$layer_path" ]] || return 0
  [[ -f "$layer_path" ]] || return 0
  [[ -r "$layer_path" ]] || die "$layer_name layer is not readable: $layer_path"
  if [[ "$layer_kind" = yaml ]]; then
    # On success the converter writes only the JSON; on failure only its message.
    if ! layer_json="$(layer_yaml_to_json "$layer_path" 2>&1)"; then
      die "$layer_name layer is not valid YAML ($layer_json): $layer_path"
    fi
    printf '%s' "$layer_json"
    return 0
  fi
  if ! layer_json="$(jqr -e . "$layer_path" 2>/dev/null)"; then
    die "$layer_name layer is not valid JSON: $layer_path"
  fi
  layer_schema="$(printf '%s' "$layer_json" | jqr -r '.schema // "missing"')"
  if [[ "$layer_schema" != "$SCHEMA" ]]; then
    die "$layer_name layer declares schema '$layer_schema', this contract is schema $SCHEMA: $layer_path"
  fi
  printf '%s' "$layer_json"
}

BUNDLED_JSON="$(jqr -e . "$TEMPLATE" 2>/dev/null)" || die "bundled defaults are not valid JSON: $TEMPLATE"
USER_JSON="$(read_layer user-global "${USER_OLD:-$USER_LAYER}")" || exit $?
TEAM_JSON="$(read_layer team "$TEAM_PATH" "$TEAM_KIND")" || exit $?
OVERLAY_JSON="$(read_layer overlay "$OVERLAY_PATH" "$OVERLAY_KIND")" || exit $?

if [[ "$ACTION" = resolve ]]; then
  for old in "$USER_OLD" "$TEAM_OLD" "$OVERLAY_OLD"; do
    [[ -n "$old" ]] || continue
    printf 'resolve-config: WARN: reading %s, the retired name; rename it to %s\n' \
      "$old" "${old%docs-hygiene*}docs-naming${old##*docs-hygiene}" >&2
  done
fi

layer_has() {
  [[ -n "$2" ]] || return 1
  printf '%s' "$2" | jqr -e --arg k "$1" '.file_names | has($k)' >/dev/null 2>&1
}

layer_value() {
  printf '%s' "$2" | jqr -c --arg k "$1" '.file_names[$k]'
}

# Append entries the accumulated value does not already carry, order preserved.
# Compared by their JSON encoding, so an object entry counts as a duplicate only
# when every field matches.
append_new() {
  jqr -n -c --argjson a "$1" --argjson b "$2" '
    ($a + $b)
    | reduce .[] as $x ([]; if (map(tojson) | index($x | tojson)) then . else . + [$x] end)
  '
}

# Only `tiers` entries carry a verdict, so each is stamped with its layer: a personal
# tier may classify a file no team tier claims, never one a team tier claimed.
stamp_layer() {
  # A non-array value is handed back untouched: stamping must never turn a
  # readable document into a failed one.
  case "$1" in
  '' | null) printf '%s' "$1" ;;
  \[*) jqr -n -c --argjson a "$1" --arg l "$2" '$a | map(if type == "object" then . + {_layer: $l} else . end)' ;;
  *) printf '%s' "$1" ;;
  esac
}

merged='{}'
prov_lines=''
inert_lines=''

for key in $KEY_ORDER; do
  value="$(layer_value "$key" "$BUNDLED_JSON")"
  [[ "$value" = "null" ]] && [[ "$key" != "redirect_map" ]] && value='null'
  [[ "$key" = tiers && "$value" != "null" ]] && value="$(stamp_layer "$value" bundled)"
  contributors='bundled'

  # Nearest-wins keys apply the nearer layer last so it wins; additive keys apply
  # team first so its replacement cannot discard personal additions.
  case "$NEAREST_WINS" in
  *" $key "*) layer_order='user-global team overlay' ;;
  *) layer_order='team user-global overlay' ;;
  esac

  for layer in $layer_order; do
    case "$layer" in
    user-global) layer_json="$USER_JSON" ;;
    team) layer_json="$TEAM_JSON" ;;
    overlay) layer_json="$OVERLAY_JSON" ;;
    *) layer_json='' ;;
    esac
    layer_has "$key" "$layer_json" || continue
    incoming="$(layer_value "$key" "$layer_json")"

    case "$TEAM_ONLY" in
    *" $key "*)
      if [[ "$layer" = team ]]; then
        value="$incoming"
        contributors="$contributors,$layer"
      else
        inert_lines="$inert_lines!inert:$key	$layer	team-layer-only
"
      fi
      continue
      ;;
    *) ;;
    esac

    case "$NEAREST_WINS" in
    *" $key "*)
      value="$incoming"
      contributors="$contributors,$layer"
      ;;
    *)
      # Additive: the team layer is the authority and replaces; a personal layer
      # only adds to what the team, or the bundled default, already decided.
      [[ "$key" = tiers ]] && incoming="$(stamp_layer "$incoming" "$layer")"
      if [[ "$layer" = team || "$value" = "null" ]]; then
        value="$incoming"
      else
        value="$(append_new "$value" "$incoming")" || die "cannot merge key '$key' from the $layer layer"
      fi
      contributors="$contributors,$layer"
      ;;
    esac
  done

  merged="$(jqr -n -c --argjson m "$merged" --arg k "$key" --argjson v "$value" '$m + {($k): $v}')" ||
    die "cannot assemble key '$key'"
  prov_lines="$prov_lines$key	$contributors
"
done

case "$ACTION" in
resolve)
  jqr -n --argjson s "$SCHEMA" --argjson m "$merged" '{schema: $s, file_names: $m}'
  ;;
layers)
  printf '%s' "$prov_lines"
  printf '%s' "$inert_lines"
  ;;
*)
  die "unreachable action '$ACTION'"
  ;;
esac
