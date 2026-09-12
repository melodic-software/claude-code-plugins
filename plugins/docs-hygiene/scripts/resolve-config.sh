#!/usr/bin/env bash
# resolve-config.sh — resolve the docs-hygiene consumer configuration surface.
#
# WHY A SCRIPT AND NOT A SOURCED LIBRARY. Four callers in three skills need the
# same merged document, and each one runs in its own process against its own
# --root. A script invoked once per run returns one JSON document every caller
# reads the same way, so no two callers can disagree about what the consumer
# configured.
#
# LAYERS, per the config-cascade convention: user-global
# (~/.claude/docs-hygiene.json), team (<root>/.claude/docs-hygiene.json), and a
# gitignored personal overlay (<root>/.claude/docs-hygiene.local.json), applied
# in that order over the bundled defaults.
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
#   paths    print the three layer paths and whether each is present
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
TEMPLATE="$SCRIPT_DIR/../skills/setup/templates/docs-hygiene.json"

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
[[ -n "$USER_HOME_DIR" ]] && USER_LAYER="$USER_HOME_DIR/.claude/docs-hygiene.json"
TEAM_LAYER="$ROOT/.claude/docs-hygiene.json"
OVERLAY_LAYER="$ROOT/.claude/docs-hygiene.local.json"

if [[ "$ACTION" = paths ]]; then
  for pair in "user-global:$USER_LAYER" "team:$TEAM_LAYER" "overlay:$OVERLAY_LAYER"; do
    name="${pair%%:*}"
    path="${pair#*:}"
    if [[ -z "$path" ]]; then
      printf '%s\t-\tno-home\n' "$name"
    elif [[ -f "$path" ]]; then
      printf '%s\t%s\tpresent\n' "$name" "$path"
    else
      printf '%s\t%s\tabsent\n' "$name" "$path"
    fi
  done
  exit 0
fi

# Read one layer. Prints its JSON, or nothing when the file is absent.
# A present file that does not parse, or whose schema is not this contract's, is
# fatal: a silently skipped layer is a configuration the operator believes is in
# effect and is not.
read_layer() {
  layer_name="$1"
  layer_path="$2"
  [[ -n "$layer_path" ]] || return 0
  [[ -f "$layer_path" ]] || return 0
  [[ -r "$layer_path" ]] || die "$layer_name layer is not readable: $layer_path"
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
USER_JSON="$(read_layer user-global "$USER_LAYER")" || exit $?
TEAM_JSON="$(read_layer team "$TEAM_LAYER")" || exit $?
OVERLAY_JSON="$(read_layer overlay "$OVERLAY_LAYER")" || exit $?

# `<key>` present in a layer's file_names object?
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

# THE POLICY FLOOR NEEDS PER-ENTRY PROVENANCE, AND ONLY `tiers` DOES.
#
# Every other additive key is a list of things to EXEMPT or EXCLUDE, so an
# appended entry can only ever narrow what a rename touches. A tier is the one
# additive key whose entries carry a verdict, and appending is not monotonic for
# a verdict: a personal tier naming a deeper path with a looser form would
# re-classify a file the team froze, which is a removal wearing an addition's
# clothes.
#
# Stamping each entry with the layer that contributed it lets the consumer hold
# the floor exactly where it belongs, per file: a personal tier may classify a
# file no team tier claims, and may never re-classify one a team tier did.
stamp_layer() {
  # A value that is absent, empty, or not an array is handed back untouched.
  # Stamping is a refinement of a list that already resolved; it must never be
  # the step that turns a readable document into a failed one.
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

  # THE TWO MERGE CLASSES NEED OPPOSITE LAYER ORDERS, so each gets its own.
  #
  # A nearest-wins key follows the documented cascade: user-global, then team,
  # then the overlay, so the NEARER layer lands last and wins. Running team
  # first here would let a machine-wide `rule` or `regex` overwrite the
  # repository's, and an audit or an emitted gate would silently enforce
  # somebody's personal convention.
  #
  # An additive key is the other way round: the team layer is the authority and
  # REPLACES, and a personal layer only appends to what the team decided. That
  # needs team first, or the team's replacement would discard the personal
  # additions the floor exists to allow.
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
