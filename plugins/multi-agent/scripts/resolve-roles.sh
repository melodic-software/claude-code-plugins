#!/usr/bin/env bash
# resolve-roles.sh: resolve the multi-agent role map through the config cascade.
#
# LAYERS, bottom to top, each overriding per key:
#   bundled      reference/defaults.yaml
#   user-global  <home>/.claude/multi-agent.yaml
#   team         the ```yaml config block of <root>/docs/conventions/multi-agent.md,
#                else <root>/.claude/multi-agent.yaml (the docs block wins when
#                both exist, with a note naming both)
#   overlay      <root>/.claude/multi-agent.local.yaml
# Team and overlay apply only when lib/config-root.sh classifies <root> as
# `repo`; a team or overlay path that is the user-global file is read once.
# A layer that does not parse, or declares a schema other than 1, is skipped
# and named in `notes`. A key with a value outside its allowed set is rejected
# and named; the layer below keeps the key. Keys and values: reference/config.md.
#
# Every role resolves to two variants:
#   single  a stage that runs one agent: the role's own model and effort.
#   fanout  a stage that runs more than one agent. With fanout.frontier_guard
#           on, a model that is `inherit` under a frontier or unknown session,
#           or a frontier alias, becomes fanout.model.
#
# Usage:
#   resolve-roles.sh [options] <role|all>    JSON on stdout
#   resolve-roles.sh pointers [--defaults F] TSV owner, key, value of every
#                                            pointer*, as_of and recheck default
# Options:
#   --workload code|research|mechanical   apply roles.<r>.workloads.<w> keys
#   --session-model <alias>               the session model's alias (opus,
#                                         sonnet, haiku, fable, best); omitted
#                                         means unknown, which the guard treats
#                                         as frontier
#   --root <dir>      repository root (default: CLAUDE_PROJECT_DIR, else the
#                     git toplevel)
#   --home <dir>      directory holding .claude/multi-agent.yaml (default $HOME)
#   --defaults <f>    bundled layer (tests)
#
# JSON shape: {"session_model", "session_frontier", "workload", "roles": {<role>:
# {"role", "single": V, "fanout": V, "source": {"model", "effort"}}}, "layers":
# [{"layer", "path", "state"}], "notes": [...]}, where V is {"model",
# "omit_model", "effort", "guarded"}. `omit_model` is true when model is
# `inherit`: the caller passes no model option and the agent runs on the
# session model. `guarded` is true when the fan-out guard replaced the model.
#
# Exit: 0 resolved; 2 usage error, unknown role (valid roles on stderr), or an
# unreadable bundled layer.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/yaml-subset.awk"
DEFAULTS="$SCRIPT_DIR/../reference/defaults.yaml"

ALIASES=" opus sonnet haiku fable best "
EFFORTS=" low medium high xhigh max "
WORKLOADS=" code research mechanical "

die() {
  printf 'resolve-roles: %s\n' "$1" >&2
  exit 2
}

json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//[$'\x01'-$'\x1f'$'\x7f']/?}"
  printf '"%s"' "$s"
}

parse() { # parse <file> [block]
  if [[ "${2:-}" == block ]]; then
    awk -v BLOCK=1 -f "$PARSER" "$1"
  else
    awk -f "$PARSER" "$1"
  fi
}

MODE=resolve
TARGET=""
WORKLOAD=""
SESSION_MODEL=""
ROOT=""
USER_HOME_DIR="${HOME:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
  pointers) MODE=pointers ;;
  --workload | --session-model | --root | --home | --defaults)
    [[ $# -gt 1 ]] || die "$1 needs a value"
    case "$1" in
    --workload) WORKLOAD="$2" ;;
    --session-model) SESSION_MODEL="$2" ;;
    --root) ROOT="$2" ;;
    --home) USER_HOME_DIR="$2" ;;
    *) DEFAULTS="$2" ;;
    esac
    shift
    ;;
  -h | --help)
    sed -n '2,/^# Exit:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  -*) die "unknown option '$1'" ;;
  *)
    [[ -z "$TARGET" ]] || die "one role or 'all', not '$TARGET' and '$1'"
    TARGET="$1"
    ;;
  esac
  shift
done

[[ -r "$DEFAULTS" ]] || die "bundled defaults unreadable: $DEFAULTS"
bundled="$(parse "$DEFAULTS")" || die "bundled defaults do not parse: $DEFAULTS: $bundled"

if [[ "$MODE" == pointers ]]; then
  awk -F '\t' '
    $1 ~ /^roles\.[^.]+\.(pointer[^.]*|as_of|recheck)$/ { split($1, k, "."); print k[2] "\t" k[3] "\t" $2 }
    $1 ~ /^fanout\.(pointer[^.]*|as_of|recheck)$/ { split($1, k, "."); print "fanout\t" k[2] "\t" $2 }' <<<"$bundled"
  exit 0
fi

[[ -n "$TARGET" ]] || die "name a role or 'all'"
[[ -z "$WORKLOAD" || "$WORKLOADS" == *" $WORKLOAD "* ]] ||
  die "unknown workload '$WORKLOAD' (valid:$WORKLOADS)"
[[ -z "$SESSION_MODEL" || "$ALIASES" == *" $SESSION_MODEL "* ]] ||
  die "unknown session model '$SESSION_MODEL' (valid:$ALIASES; omit when unknown)"

# Bash 3.2 (stock macOS) has no associative arrays, so each dotted key maps to
# a VAL_<key> and SRC_<key> variable. Keys hold only [A-Za-z0-9_.-].
kv_name() {
  local n="${1//-/_H_}"
  printf '%s' "${n//./_D_}"
}
set_kv() { # set_kv <key> <value> <source layer>
  local n
  n="$(kv_name "$1")"
  printf -v "VAL_$n" '%s' "$2"
  printf -v "SRC_$n" '%s' "$3"
}
val() {
  local n
  n="VAL_$(kv_name "$1")"
  printf '%s' "${!n:-}"
}
src() {
  local n
  n="SRC_$(kv_name "$1")"
  printf '%s' "${!n:-}"
}

ROLES=()
NOTES=()
LAYERS_JSON=()

while IFS=$'\t' read -r key value; do
  [[ -n "$key" ]] || continue
  set_kv "$key" "$value" bundled
  if [[ "$key" =~ ^roles\.([^.]+)\.model$ ]]; then ROLES+=("${BASH_REMATCH[1]}"); fi
done <<<"$bundled"

if [[ "$TARGET" != all && " ${ROLES[*]} " != *" $TARGET "* ]]; then
  printf 'resolve-roles: unknown role %s; valid roles: %s, or all\n' "$TARGET" "${ROLES[*]}" >&2
  exit 2
fi

valid_value() { # valid_value <field> <value>
  case "$1" in
  model) [[ "$2" == inherit || "$ALIASES" == *" $2 "* ]] ;;
  fanout_model) [[ "$ALIASES" == *" $2 "* ]] ;;
  effort) [[ "$EFFORTS" == *" $2 "* ]] ;;
  frontier_guard) [[ "$2" == true || "$2" == false ]] ;;
  frontier)
    local a parts=()
    IFS=',' read -ra parts <<<"$2"
    ((${#parts[@]})) || return 1
    for a in "${parts[@]}"; do [[ "$ALIASES" == *" $a "* ]] || return 1; done
    ;;
  *) return 1 ;;
  esac
}

layer_state() { # layer_state <label> <path> <state>
  LAYERS_JSON+=("{\"layer\":$(json_str "$1"),\"path\":$(json_str "$2"),\"state\":$(json_str "$3")}")
}

# apply_layer <label> <path> <records>
apply_layer() {
  local label="$1" path="$2" records="$3" key value field role w
  if [[ "$(awk -F '\t' '$1=="schema"{print $2}' <<<"$records")" != 1 ]]; then
    NOTES+=("$label layer skipped: $path does not declare schema: 1")
    layer_state "$label" "$path" skipped
    return
  fi
  layer_state "$label" "$path" read
  while IFS=$'\t' read -r key value; do
    [[ -n "$key" && "$key" != schema && "$key" != block ]] || continue
    role=""
    case "$key" in
    frontier) field=frontier ;;
    fanout.frontier_guard) field=frontier_guard ;;
    fanout.model) field=fanout_model ;;
    *)
      if [[ "$key" =~ ^roles\.([^.]+)\.(model|effort)$ ]]; then
        role="${BASH_REMATCH[1]}" field="${BASH_REMATCH[2]}"
      elif [[ "$key" =~ ^roles\.([^.]+)\.workloads\.([^.]+)\.(model|effort)$ ]]; then
        role="${BASH_REMATCH[1]}" w="${BASH_REMATCH[2]}" field="${BASH_REMATCH[3]}"
        if [[ "$WORKLOADS" != *" $w "* ]]; then
          NOTES+=("$label: $key ignored: unknown workload '$w' (valid:$WORKLOADS)")
          continue
        fi
      elif [[ "$key" =~ ^(roles\.[^.]+|fanout)\.(pointer[^.]*|as_of|recheck)$ ]]; then
        NOTES+=("$label: $key ignored: provenance keys are read from the bundled layer only")
        continue
      else
        NOTES+=("$label: $key ignored: unknown key")
        continue
      fi
      ;;
    esac
    if [[ -n "$role" && " ${ROLES[*]} " != *" $role "* ]]; then
      NOTES+=("$label: $key ignored: unknown role '$role' (valid: ${ROLES[*]})")
      continue
    fi
    if ! valid_value "$field" "$value"; then
      value="${value//[^[:print:]]/?}"
      NOTES+=("$label: $key rejected: '${value:0:40}' is not an allowed value; the layer below supplies it")
      continue
    fi
    set_kv "$key" "$value" "$label"
  done <<<"$records"
}

# read_layer <label> <path> [block]
read_layer() {
  local label="$1" path="$2" records where msg
  if ! records="$(parse "$path" "${3:-}")"; then
    where="$(awk -F '\t' '$1=="error"{print $2}' <<<"$records")"
    msg="$(awk -F '\t' '$1=="error"{print $3}' <<<"$records")"
    NOTES+=("$label layer skipped: $path:$where: $msg")
    layer_state "$label" "$path" skipped
    return
  fi
  apply_layer "$label" "$path" "$records"
}

# shellcheck source=../lib/config-root.sh
. "$SCRIPT_DIR/../lib/config-root.sh"
[[ -n "$ROOT" ]] || ROOT="$(config_root_resolve)"
ROOT_CLASS="$(HOME="$USER_HOME_DIR" config_root_classify "$ROOT")"

USER_LAYER=""
[[ -n "$USER_HOME_DIR" ]] && USER_LAYER="$USER_HOME_DIR/.claude/multi-agent.yaml"
if [[ -n "$USER_LAYER" && -f "$USER_LAYER" ]]; then
  read_layer user-global "$USER_LAYER"
else
  layer_state user-global "$USER_LAYER" absent
fi

TEAM_DOCS="$ROOT/docs/conventions/multi-agent.md"
TEAM_YAML="$ROOT/.claude/multi-agent.yaml"
OVERLAY="$ROOT/.claude/multi-agent.local.yaml"
if [[ "$ROOT_CLASS" != repo ]]; then
  layer_state team "$TEAM_DOCS" "not-applicable ($ROOT_CLASS root)"
  layer_state overlay "$OVERLAY" "not-applicable ($ROOT_CLASS root)"
else
  docs_block=0
  if [[ -f "$TEAM_DOCS" ]]; then
    # A docs file whose only fence is an example inside an outer fence holds
    # no block; a parse error after the block opened still makes it the team layer.
    docs_records="$(parse "$TEAM_DOCS" block)"
    [[ "$docs_records" == block$'\t'* ]] && docs_block=1
  fi
  if ((docs_block)); then
    [[ -f "$TEAM_YAML" ]] && NOTES+=("team: $TEAM_DOCS and $TEAM_YAML both exist; using the docs block, ignoring the .claude file")
    read_layer team "$TEAM_DOCS" block
  elif [[ -f "$TEAM_YAML" ]] && ! config_root_paths_same "$TEAM_YAML" "$USER_LAYER"; then
    read_layer team "$TEAM_YAML"
  else
    layer_state team "$TEAM_YAML" absent
  fi
  if [[ -f "$OVERLAY" ]] && ! config_root_paths_same "$OVERLAY" "$USER_LAYER"; then
    read_layer overlay "$OVERLAY"
  else
    layer_state overlay "$OVERLAY" absent
  fi
fi

FRONTIER=",$(val frontier),"
is_frontier() { [[ "$FRONTIER" == *",$1,"* ]]; }
# An unknown session counts as frontier: the guard fails toward `opus`.
SESSION_FRONTIER=true
[[ -n "$SESSION_MODEL" ]] && ! is_frontier "$SESSION_MODEL" && SESSION_FRONTIER=false

variant() { # variant <model> <effort> <guarded>
  local omit=false
  [[ "$1" == inherit ]] && omit=true
  printf '{"model":%s,"omit_model":%s,"effort":%s,"guarded":%s}' \
    "$(json_str "$1")" "$omit" "$(json_str "$2")" "$3"
}

role_json() {
  local r="$1" p="roles.$1" model effort ms es fan guarded=false w guard
  model="$(val "$p.model")" ms="$(src "$p.model")"
  effort="$(val "$p.effort")" es="$(src "$p.effort")"
  if [[ -n "$WORKLOAD" ]]; then
    w="$p.workloads.$WORKLOAD"
    if [[ -n "$(val "$w.model")" ]]; then
      model="$(val "$w.model")" ms="$(src "$w.model")"
    fi
    if [[ -n "$(val "$w.effort")" ]]; then
      effort="$(val "$w.effort")" es="$(src "$w.effort")"
    fi
  fi
  fan="$model"
  guard="$(val fanout.frontier_guard)"
  if [[ "${guard:-true}" == true ]]; then
    if [[ "$model" == inherit && "$SESSION_FRONTIER" == true ]] || is_frontier "$model"; then
      fan="$(val fanout.model)" guarded=true
      fan="${fan:-opus}"
    fi
  fi
  printf '%s:{"role":%s,"single":%s,"fanout":%s,"source":{"model":%s,"effort":%s}}' \
    "$(json_str "$r")" "$(json_str "$r")" "$(variant "$model" "$effort" false)" \
    "$(variant "$fan" "$effort" "$guarded")" "$(json_str "$ms")" "$(json_str "$es")"
}

join() {
  local IFS=,
  printf '%s' "$*"
}

out_roles=()
for r in "${ROLES[@]}"; do
  [[ "$TARGET" == all || "$TARGET" == "$r" ]] && out_roles+=("$(role_json "$r")")
done
notes_json=()
for n in "${NOTES[@]+"${NOTES[@]}"}"; do
  notes_json+=("$(json_str "$n")")
  printf 'resolve-roles: %s\n' "$n" >&2
done

session='null'
[[ -n "$SESSION_MODEL" ]] && session="$(json_str "$SESSION_MODEL")"
workload='null'
[[ -n "$WORKLOAD" ]] && workload="$(json_str "$WORKLOAD")"
printf '{"session_model":%s,"session_frontier":%s,"workload":%s,"roles":{%s},"layers":[%s],"notes":[%s]}\n' \
  "$session" "$SESSION_FRONTIER" "$workload" "$(join "${out_roles[@]}")" "$(join "${LAYERS_JSON[@]+"${LAYERS_JSON[@]}"}")" \
  "$(join "${notes_json[@]+"${notes_json[@]}"}")"
