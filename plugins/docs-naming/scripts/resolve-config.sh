#!/usr/bin/env bash
# Every single-quoted `${...}` below is a jq program argument, never a shell expansion.
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
  cat <<'EOF'
resolve-config.sh — resolve the docs-naming consumer configuration.

Layers, per the config-cascade convention, applied in this order over the
bundled defaults: userConfig (the plugin's `file_names` option, a JSON object of
`file_names` keys), team (<home>/docs-naming.yaml), and a gitignored personal
override (<home>/docs-naming.local.yaml). <home> is the repository's convention
home (docs/conventions unless AGENTS.md or CLAUDE.md binds another), and the
YAML's keys are the `file_names` keys, validated by
schemas/docs-naming.schema.json. When --root is the home directory (or an
ancestor of it) or is not inside a git working tree, there is no team layer or
personal override, and `paths` reports both as not-applicable.
An option value holding a whole old file ({"schema": 1, "file_names": {...}}) is
read as its `file_names` object.

Usage:
  resolve-config.sh resolve [--root <dir>] [--home <dir>] [--user-config <json>]
  resolve-config.sh layers  [--root <dir>] [--home <dir>] [--user-config <json>]
  resolve-config.sh paths   [--root <dir>] [--home <dir>] [--user-config <json>]
  resolve-config.sh --help

  resolve  print the merged document (schema + file_names) on stdout
  layers   print `key<TAB>layers` lines, one per key, naming every layer that
           contributed, plus `!inert:<key>` lines for ignored declarations
  paths    print `layer<TAB>path<TAB>state` lines. The userConfig row's path is
           `file_names` and its state present, absent or invalid; then team and
           personal-override, each present, absent or a not-applicable reason

  --root         the repository root to resolve the team layer and personal
                 override against. Default: `git rev-parse --show-toplevel` from
                 the current directory, never the directory this script lives
                 in, so a worktree or a fixture is addressed explicitly.
  --home         the home directory used to classify whether --root is a home
                 root. Default: $HOME.
  --user-config  the `file_names` option's value. Default:
                 $CLAUDE_PLUGIN_OPTION_FILE_NAMES. Empty, or a literal
                 ${user_config.file_names} placeholder, is unset. A value that is
                 not one JSON object is named on stderr and ignored.

Exit: 0 resolved, 2 usage error or an unreadable or unparsable file layer
      (the file is named on stderr).
EOF
}

jqr() {
  jq "$@" | tr -d '\r'
}

ACTION=""
ROOT=""
USER_HOME_DIR="${HOME:-}"
USER_CONFIG="${CLAUDE_PLUGIN_OPTION_FILE_NAMES:-}"

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
  --user-config)
    shift
    [[ $# -gt 0 ]] || die "--user-config needs a value"
    USER_CONFIG="$1"
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
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
  [[ -n "$ROOT" ]] || die "not inside a git repository and no --root given"
fi
[[ -d "$ROOT" ]] || die "--root '$ROOT' is not a directory"

case "$USER_CONFIG" in
'${user_config.'*) USER_CONFIG="" ;;
*) [[ -n "${USER_CONFIG//[[:space:]]/}" ]] || USER_CONFIG="" ;;
esac
USER_STATE=absent
USER_JSON=""
if [[ -n "$USER_CONFIG" ]]; then
  if USER_JSON="$(printf '%s' "$USER_CONFIG" | jqr -c -s -e 'if length == 1 and (.[0] | type) == "object" then {file_names: (.[0] | if (.file_names | type) == "object" then .file_names else . end)} else error("not one object") end' 2>/dev/null)"; then
    USER_STATE=present
  else
    USER_STATE=invalid
    USER_JSON=""
  fi
fi

# shellcheck source=../lib/config-root.sh
. "$SCRIPT_DIR/../lib/config-root.sh"
ROOT_CLASS="$(HOME="$USER_HOME_DIR" config_root_classify "$ROOT")"
TEAM_YAML=""
PERSONAL_YAML=""
LAYER_SKIP=""
if [[ "$ROOT_CLASS" != repo ]]; then
  LAYER_SKIP="not-applicable: $ROOT_CLASS root"
else
  CONVENTION_HOME="$(layer_yaml_home "$ROOT" 2>&1)" || die "$CONVENTION_HOME"
  TEAM_YAML="$ROOT/$CONVENTION_HOME/docs-naming.yaml"
  PERSONAL_YAML="$ROOT/$CONVENTION_HOME/docs-naming.local.yaml"
fi

if [[ "$ACTION" = paths ]]; then
  printf 'userConfig\tfile_names\t%s\n' "$USER_STATE"
  for name in team personal-override; do
    path="$TEAM_YAML"
    [[ "$name" = team ]] || path="$PERSONAL_YAML"
    if [[ -n "$LAYER_SKIP" ]]; then
      printf '%s\t-\t%s\n' "$name" "$LAYER_SKIP"
    elif [[ -f "$path" ]]; then
      printf '%s\t%s\tpresent\n' "$name" "$path"
    else
      printf '%s\t%s\tabsent\n' "$name" "$path"
    fi
  done
  exit 0
fi

read_layer() {
  layer_name="$1"
  layer_path="$2"
  [[ -n "$layer_path" ]] || return 0
  [[ -f "$layer_path" ]] || return 0
  [[ -r "$layer_path" ]] || die "$layer_name layer is not readable: $layer_path"
  if ! layer_json="$(layer_yaml_to_json "$layer_path" 2>&1)"; then
    die "$layer_name layer is not valid YAML ($layer_json): $layer_path"
  fi
  printf '%s' "$layer_json"
}

BUNDLED_JSON="$(jqr -e . "$TEMPLATE" 2>/dev/null)" || die "bundled defaults are not valid JSON: $TEMPLATE"
TEAM_JSON="$(read_layer team "$TEAM_YAML")" || exit $?
PERSONAL_JSON="$(read_layer personal-override "$PERSONAL_YAML")" || exit $?

if [[ "$ACTION" = resolve && "$USER_STATE" == invalid ]]; then
  printf "resolve-config: WARN: the docs-naming plugin's file_names userConfig option is not one JSON object and is ignored: %s\n" "$USER_CONFIG" >&2
fi

layer_has() {
  [[ -n "$2" ]] || return 1
  printf '%s' "$2" | jqr -e --arg k "$1" '.file_names | has($k)' >/dev/null 2>&1
}

layer_value() {
  printf '%s' "$2" | jqr -c --arg k "$1" '.file_names[$k]'
}

append_new() {
  jqr -n -c --argjson a "$1" --argjson b "$2" '
    ($a + $b)
    | reduce .[] as $x ([]; if (map(tojson) | index($x | tojson)) then . else . + [$x] end)
  '
}

stamp_layer() {
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
  [[ "$key" = tiers ]] && value="$(stamp_layer "$value" bundled)"
  contributors='bundled'

  case "$NEAREST_WINS" in
  *" $key "*) layer_order='userConfig team personal-override' ;;
  *) layer_order='team userConfig personal-override' ;;
  esac

  for layer in $layer_order; do
    case "$layer" in
    userConfig) layer_json="$USER_JSON" ;;
    team) layer_json="$TEAM_JSON" ;;
    personal-override) layer_json="$PERSONAL_JSON" ;;
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
