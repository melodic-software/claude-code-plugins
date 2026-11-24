#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/yaml-subset.awk"
DEFAULTS="$SCRIPT_DIR/../reference/defaults.yaml"

usage() {
  cat <<'EOF'
resolve-roles.sh: resolve the multi-agent role map through the config cascade.

LAYERS, bottom to top, each overriding per key:
  bundled      reference/defaults.yaml
  user-config  the file the role_map_file userConfig option names (--user-file)
  team         <root>/<home>/multi-agent.yaml (<home> is the convention home
               the repository binds, else docs/conventions)
  personal-override <root>/<home>/multi-agent.local.yaml
Dual-read window: while no file above supplies the user-config or the
personal-override layer, its old file still does: ~/.claude/multi-agent.yaml
(the layer is then named user-global) or <root>/.claude/multi-agent.local.yaml.
Each old file found adds one note naming it, its new location and
/multi-agent:setup apply --migrate, whether it was read or not.
Team and personal-override apply only when lib/config-root.sh classifies <root> as
`repo`; a team or personal-override path that is the user layer's file is read once.
A layer that does not parse, or declares a schema other than 1, is skipped
and named in `notes`. A key with a value outside its allowed set is rejected
and named; the layer below keeps the key. Keys and values: reference/config.md.

Every role resolves to two variants:
  single  a stage that runs one agent: the role's own model and effort.
  fanout  a stage that runs more than one agent. With fanout.frontier_guard
          on, a model that is `inherit` under a frontier or unknown session,
          or a frontier alias, becomes fanout.model.

Usage:
  resolve-roles.sh [options] <role|all>    JSON on stdout
  resolve-roles.sh pointers [--defaults F] TSV owner, key, value of every
                                           pointer*, as_of and recheck default
Options:
  --workload <w>                        apply roles.<r>.workloads.<w> keys; <w>
                                        is a workload some layer declares
                                        (workloads.<w>: true); the bundled
                                        layer declares code, research and
                                        mechanical
  --session-model <alias>               the session model's alias (opus,
                                        sonnet, haiku, fable); omitted
                                        means unknown, which the guard treats
                                        as frontier
  --root <dir>      repository root (default: CLAUDE_PROJECT_DIR, else the
                    git toplevel)
  --home <dir>      the user's home, holding the old .claude/multi-agent.yaml
                    (default $HOME)
  --user-file <f>   the file the role_map_file option names; empty or an
                    unsubstituted ${user_config.role_map_file} means unset
  --defaults <f>    bundled layer (tests)

JSON shape: {"session_model", "session_frontier", "workload", "roles": {<role>:
{"role", "single": V, "fanout": V, "source": {"model", "effort"}, "basis":
{"model", "fanout_model", "effort"}}}, "vendors": {"routing", "trials",
"auto_delegation", "tiebreak", "trials_prove", "trials_fail", "promotion_audits",
"promotion_days", "claude", "codex", "antigravity", "sources", "source"}, "layers": [{"layer", "path", "state"}],
"notes": [...]}, where V is {"model", "omit_model", "effort", "guarded"}. A
basis is `upstream` or `judgment` as the bundled layer records it
(basis_<field> in reference/defaults.yaml), `config` when a consumer layer
supplied the value, or `unrecorded` when the bundled entry names none.
`fanout_model` is the fanout variant's model basis: the role's own unless the
guard replaced it, then fanout.model's. `omit_model` is true when model is
`inherit`: the caller passes no model option and the agent runs on the
session model. `guarded` is true when the fan-out guard replaced the model.
A role whose single or fanout model is haiku, named or inherited from a haiku
session, gains one `notes` entry pointing at reference/routing-rubric.md; the
role still resolves.

Exit: 0 resolved; 2 usage error, unknown role (valid roles on stderr),
undeclared workload (declared ones on stderr), or an unreadable bundled layer.
EOF
}

# Validation constants: a chosen subset of the aliases at
# https://code.claude.com/docs/en/model-config#model-aliases and the levels at
# https://code.claude.com/docs/en/model-config#choose-an-effort-level (as of
# 2026-10-11; recheck when either section adds, renames or drops an alias or a
# level). `default`, `opusplan` and the `[1m]` variants are left out on purpose.
ALIASES=" opus sonnet haiku fable "
EFFORTS=" low medium high xhigh max "
TIEBREAK_STEPS=" vendor-order fewest-tokens most-usage-left "
SOURCE_ID_RE='^[a-z0-9][a-z0-9-]*$'

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

parse() { # parse <file>
  awk -f "$PARSER" "$1"
}

MODE=resolve
TARGET=""
WORKLOAD=""
SESSION_MODEL=""
ROOT=""
USER_HOME_DIR="${HOME:-}"
USER_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  pointers) MODE=pointers ;;
  --workload | --session-model | --root | --home | --user-file | --defaults)
    [[ $# -gt 1 ]] || die "$1 needs a value"
    case "$1" in
    --workload) WORKLOAD="$2" ;;
    --session-model) SESSION_MODEL="$2" ;;
    --root) ROOT="$2" ;;
    --home) USER_HOME_DIR="$2" ;;
    --user-file) USER_FILE="$2" ;;
    *) DEFAULTS="$2" ;;
    esac
    shift
    ;;
  -h | --help)
    usage
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
    $1 ~ /^roles\.[^.]+\.(pointer[^.]*|basis_[^.]*|claim_[^.]*|reason_[^.]*|as_of|recheck)$/ { split($1, k, "."); print k[2] "\t" k[3] "\t" $2 }
    $1 ~ /^fanout\.(pointer[^.]*|basis_[^.]*|claim_[^.]*|reason_[^.]*|as_of|recheck)$/ { split($1, k, "."); print "fanout\t" k[2] "\t" $2 }' <<<"$bundled"
  exit 0
fi

[[ -n "$TARGET" ]] || die "name a role or 'all'"
[[ -z "$SESSION_MODEL" || "$ALIASES" == *" $SESSION_MODEL "* ]] ||
  die "unknown session model '$SESSION_MODEL' (valid:$ALIASES; omit when unknown)"

# Bash 3.2 (stock macOS) has no associative arrays, so each dotted key maps to
# a VAL_<key> and SRC_<key> variable. Keys hold only [A-Za-z0-9_.-]; `_` is
# escaped first, so `a-b` and `a_H_b` get distinct names.
kv_name() {
  local n="${1//_/_U_}"
  n="${n//-/_H_}"
  printf '%s' "${n//./_D_}"
}
set_kv() { # set_kv <key> <value> <source layer>
  local n
  n="$(kv_name "$1")"
  printf -v "VAL_$n" '%s' "$2"
  printf -v "SRC_$n" '%s' "$3"
}
kv_get() { # kv_get VAL|SRC <key>
  local n
  n="$1_$(kv_name "$2")"
  printf '%s' "${!n:-}"
}
val() { kv_get VAL "$1"; }
src() { kv_get SRC "$1"; }

ROLES=()
NOTES=()
LAYERS_JSON=()
# Workload names any layer declares, and every role workload key applied as
# "<layer>\t<key>\t<workload>": a key's workload must be declared once all
# layers are read, whichever layer declares it.
WL_NAMES=()
WL_KEYS=()
WL_NAME_RE='^[A-Za-z0-9_][A-Za-z0-9_-]*$'
V_TIEBREAK=()
V_TIEBREAK_SRC=""
V_SOURCE_IDS=()

while IFS=$'\t' read -r key value; do
  [[ -n "$key" ]] || continue
  set_kv "$key" "$value" bundled
  if [[ "$key" =~ ^roles\.([^.]+)\.model$ ]]; then ROLES+=("${BASH_REMATCH[1]}"); fi
  if [[ "$key" =~ ^workloads\.([^.]+)$ ]]; then WL_NAMES+=("${BASH_REMATCH[1]}"); fi
  if [[ "$key" =~ ^roles\.[^.]+\.workloads\.([^.]+)\.(model|effort)$ ]]; then
    WL_KEYS+=("bundled"$'\t'"$key"$'\t'"${BASH_REMATCH[1]}")
  fi
  if [[ "$key" =~ ^vendors\.tiebreak\.[0-9]+$ ]]; then
    V_TIEBREAK+=("$value")
    V_TIEBREAK_SRC=bundled
  fi
  if [[ "$key" =~ ^vendors\.sources\.([^.]+)\.enabled$ ]]; then
    sid="${BASH_REMATCH[1]}"
    if [[ " ${V_SOURCE_IDS[*]+"${V_SOURCE_IDS[*]}"} " != *" $sid "* ]]; then
      V_SOURCE_IDS+=("$sid")
    fi
  fi
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
  frontier_guard | declared | bool) [[ "$2" == true || "$2" == false ]] ;;
  trials_prove | positive_int) [[ "$2" =~ ^[1-9][0-9]*$ ]] ;;
  trials_fail) [[ "$2" =~ ^[1-9][0-9]*$ ]] && ((10#$2 >= 2)) ;;
  vendor_rank) [[ "$2" =~ ^-?(0|[1-9][0-9]*)$ ]] ;;
  frontier)
    local a parts=()
    # read drops one trailing empty field, so a trailing comma is refused here,
    # as the schema's pattern refuses it.
    [[ "$2" != *, ]] || return 1
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
  local label="$1" path="$2" records="$3" key value field role w sid=""
  local layer_tb=() layer_tb_seen=0 layer_tb_bad=0
  if [[ "$(awk -F '\t' '$1=="schema"{print $2}' <<<"$records")" != 1 ]]; then
    NOTES+=("$label layer skipped: $path does not declare schema: 1")
    layer_state "$label" "$path" skipped
    return
  fi
  layer_state "$label" "$path" read
  while IFS=$'\t' read -r key value; do
    [[ -n "$key" && "$key" != schema ]] || continue
    role=""
    sid=""
    case "$key" in
    frontier) field=frontier ;;
    # Not a role-map key: lib/read-verification.sh reads it from the team file at the default branch.
    verification | verification_skills.*) continue ;;
    fanout.frontier_guard) field=frontier_guard ;;
    fanout.model) field=fanout_model ;;
    vendors.auto_delegation)
      if [[ "$label" != user-config && "$label" != user-global ]]; then
        NOTES+=("$label: vendors.auto_delegation ignored: only the user layer (role_map_file) sets it, never a file inside a repository")
        continue
      fi
      field=bool
      ;;
    vendors.routing | vendors.trials) field=bool ;;
    vendors.trials_prove) field=trials_prove ;;
    vendors.trials_fail) field=trials_fail ;;
    vendors.promotion_audits | vendors.promotion_days) field=positive_int ;;
    vendors.tiebreak)
      value="${value//[^[:print:]]/?}"
      NOTES+=("$label: vendors.tiebreak rejected: '${value:0:40}' is not a list of allowed tiebreak steps; the layer below supplies it")
      layer_tb_bad=1
      continue
      ;;
    *)
      if [[ "$key" =~ ^workloads\.([^.]+)$ ]]; then
        w="${BASH_REMATCH[1]}" field=declared
        if [[ ! "$w" =~ $WL_NAME_RE ]]; then
          NOTES+=("$label: ${key//[^[:print:]]/?} ignored: a workload name holds only letters, digits, _ and -, and does not start with -")
          continue
        fi
      elif [[ "$key" =~ ^roles\.([^.]+)\.(model|effort)$ ]]; then
        role="${BASH_REMATCH[1]}" field="${BASH_REMATCH[2]}"
      elif [[ "$key" =~ ^roles\.([^.]+)\.workloads\.([^.]+)\.(model|effort)$ ]]; then
        role="${BASH_REMATCH[1]}" w="${BASH_REMATCH[2]}" field="${BASH_REMATCH[3]}"
        if [[ ! "$w" =~ $WL_NAME_RE ]]; then
          NOTES+=("$label: ${key//[^[:print:]]/?} ignored: a workload name holds only letters, digits, _ and -, and does not start with -")
          continue
        fi
      elif [[ "$key" =~ ^vendors\.tiebreak\.[0-9]+$ ]]; then
        layer_tb_seen=1
        if [[ "$TIEBREAK_STEPS" != *" $value "* ]]; then
          value="${value//[^[:print:]]/?}"
          NOTES+=("$label: vendors.tiebreak rejected: '${value:0:40}' is not an allowed value; the layer below supplies it")
          layer_tb_bad=1
        elif [[ " ${layer_tb[*]+"${layer_tb[*]}"} " == *" $value "* ]]; then
          NOTES+=("$label: vendors.tiebreak rejected: duplicate step '$value'; the layer below supplies it")
          layer_tb_bad=1
        else
          layer_tb+=("$value")
        fi
        continue
      elif [[ "$key" =~ ^vendors\.(claude|codex|antigravity)\.(in_use|rank)$ ]]; then
        if [[ "${BASH_REMATCH[2]}" == in_use ]]; then
          field=bool
        else
          field=vendor_rank
        fi
      elif [[ "$key" =~ ^vendors\.sources\.([^.]+)\.enabled$ ]]; then
        sid="${BASH_REMATCH[1]}"
        if [[ ! "$sid" =~ $SOURCE_ID_RE ]]; then
          NOTES+=("$label: ${key//[^[:print:]]/?} ignored: a source id holds only lowercase letters, digits and -, and does not start with -")
          continue
        fi
        field=bool
      elif [[ "$key" =~ ^(roles\.[^.]+|fanout)\.(pointer[^.]*|basis_[^.]*|claim_[^.]*|reason_[^.]*|as_of|recheck)$ ]]; then
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
    if [[ "$field" == declared ]]; then
      WL_NAMES+=("$w")
    elif [[ "$key" == *.workloads.* ]]; then
      WL_KEYS+=("$label"$'\t'"$key"$'\t'"$w")
    elif [[ -n "$sid" ]]; then
      if [[ " ${V_SOURCE_IDS[*]+"${V_SOURCE_IDS[*]}"} " != *" $sid "* ]]; then
        V_SOURCE_IDS+=("$sid")
      fi
    fi
  done <<<"$records"
  if ((layer_tb_seen && !layer_tb_bad)); then
    V_TIEBREAK=("${layer_tb[@]+"${layer_tb[@]}"}")
    V_TIEBREAK_SRC="$label"
  fi
}

# read_layer <label> <path>
read_layer() {
  local label="$1" path="$2" records where msg
  if ! records="$(parse "$path")"; then
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

MIGRATE="/multi-agent:setup apply --migrate"
USER_LAYER=""

dual_read() {
  local label="$1" old_label="$2" new="$3" old="$4" where="$5" has_old=0
  READ_FILE=""
  [[ -n "$old" && -f "$old" ]] && ! config_root_paths_same "$old" "$USER_LAYER" && has_old=1
  if [[ -n "$new" && -f "$new" ]]; then
    if config_root_paths_same "$new" "$USER_LAYER"; then
      layer_state "$label" "$new" absent
    else
      read_layer "$label" "$new"
      READ_FILE="$new"
    fi
    if ((has_old)) && ! config_root_paths_same "$old" "$new"; then
      NOTES+=("$old_label: $old is an old path and not read, since $new supplies the layer; $MIGRATE merges its keys into $new and deletes it")
    fi
  elif ((has_old)); then
    read_layer "$old_label" "$old"
    READ_FILE="$old"
    NOTES+=("$old_label: $old is an old path, still read until it moves; $MIGRATE moves it to $where and deletes it")
  else
    layer_state "$label" "$new" absent
  fi
}

[[ "$USER_FILE" == "\${user_config."* ]] && USER_FILE=""
[[ -n "$USER_HOME_DIR" && "$USER_FILE" == \~/* ]] && USER_FILE="$USER_HOME_DIR/${USER_FILE#\~/}"
if [[ -n "$USER_FILE" && "$USER_FILE" != /* ]]; then
  NOTES+=("user-config layer skipped: the role_map_file option '${USER_FILE//[^[:print:]]/?}' is not an absolute path; set an absolute path in /config")
  USER_FILE=""
fi
OLD_USER=""
[[ -n "$USER_HOME_DIR" ]] && OLD_USER="$USER_HOME_DIR/.claude/multi-agent.yaml"
user_where="the file the role_map_file option names (set it in /config)"
[[ -n "$USER_FILE" ]] && user_where="$USER_FILE"
dual_read user-config user-global "$USER_FILE" "$OLD_USER" "$user_where"
USER_LAYER="$READ_FILE"

# The convention home is the one the repository binds in AGENTS.md or CLAUDE.md
# (lib/resolve-convention-home.sh); docs/conventions when it binds none.
CONVENTION_HOME="docs/conventions"
if [[ -f "$SCRIPT_DIR/../lib/resolve-convention-home.sh" ]]; then
  home_out="$(bash "$SCRIPT_DIR/../lib/resolve-convention-home.sh" --root "$ROOT" 2>/dev/null)" && CONVENTION_HOME="$home_out"
fi
TEAM_CONCERN="$ROOT/$CONVENTION_HOME/multi-agent.yaml"
PERSONAL_OVERRIDE="$ROOT/$CONVENTION_HOME/multi-agent.local.yaml"
if [[ "$ROOT_CLASS" != repo ]]; then
  layer_state team "$TEAM_CONCERN" "not-applicable ($ROOT_CLASS root)"
  layer_state personal-override "$PERSONAL_OVERRIDE" "not-applicable ($ROOT_CLASS root)"
else
  if [[ -f "$TEAM_CONCERN" ]] && ! config_root_paths_same "$TEAM_CONCERN" "$USER_LAYER"; then
    read_layer team "$TEAM_CONCERN"
  else
    layer_state team "$TEAM_CONCERN" absent
  fi
  dual_read personal-override personal-override "$PERSONAL_OVERRIDE" \
    "$ROOT/.claude/multi-agent.local.yaml" "$PERSONAL_OVERRIDE"
fi

# A workload is declared when its last workloads.<w> value is true.
DECLARED=" "
for w in "${WL_NAMES[@]+"${WL_NAMES[@]}"}"; do
  [[ "$(val "workloads.$w")" == true && "$DECLARED" != *" $w "* ]] && DECLARED+="$w "
done
for e in "${WL_KEYS[@]+"${WL_KEYS[@]}"}"; do
  IFS=$'\t' read -r label key w <<<"$e"
  [[ "$DECLARED" == *" $w "* ]] ||
    NOTES+=("$label: $key ignored: undeclared workload '$w' (declare it with workloads.$w: true)")
done
[[ -z "$WORKLOAD" || "$DECLARED" == *" $WORKLOAD "* ]] ||
  die "unknown workload '$WORKLOAD' (declared:${DECLARED% })"

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

# basis_of <role prefix> <field> <source layer> [<workload>]: the bundled
# basis_[<workload>_]<field> (upstream or judgment) when the bundled layer
# supplied the value, `config` when a consumer layer did, `unrecorded` when the
# bundled entry names none. Pass the workload only when its key set the value.
basis_of() {
  local b
  if [[ -z "$3" ]]; then
    printf 'unrecorded'
    return
  fi
  if [[ "$3" != bundled ]]; then
    printf 'config'
    return
  fi
  b="$(val "$1.basis_${4:+$4_}$2")"
  case "$b" in
  upstream | judgment) printf '%s' "$b" ;;
  *) printf 'unrecorded' ;;
  esac
}

role_json() {
  local r="$1" p="roles.$1" model effort ms es mw="" ew="" mb fb fan guarded=false w guard v
  model="$(val "$p.model")" ms="$(src "$p.model")"
  effort="$(val "$p.effort")" es="$(src "$p.effort")"
  if [[ -n "$WORKLOAD" ]]; then
    w="$p.workloads.$WORKLOAD"
    v="$(val "$w.model")"
    [[ -z "$v" ]] || model="$v" ms="$(src "$w.model")" mw="$WORKLOAD"
    v="$(val "$w.effort")"
    [[ -z "$v" ]] || effort="$v" es="$(src "$w.effort")" ew="$WORKLOAD"
  fi
  fan="$model"
  mb="$(basis_of "$p" model "$ms" "$mw")" fb="$mb"
  guard="$(val fanout.frontier_guard)"
  if [[ "${guard:-true}" == true ]]; then
    if [[ "$model" == inherit && "$SESSION_FRONTIER" == true ]] || is_frontier "$model"; then
      fan="$(val fanout.model)" guarded=true
      fan="${fan:-opus}"
      fb="$(basis_of fanout model "$(src fanout.model)")"
    fi
  fi
  printf -v ROLE_JSON '%s:{"role":%s,"single":%s,"fanout":%s,"source":{"model":%s,"effort":%s},"basis":{"model":%s,"fanout_model":%s,"effort":%s}}' \
    "$(json_str "$r")" "$(json_str "$r")" "$(variant "$model" "$effort" false)" \
    "$(variant "$fan" "$effort" "$guarded")" "$(json_str "$ms")" "$(json_str "$es")" \
    "$(json_str "$mb")" "$(json_str "$fb")" "$(json_str "$(basis_of "$p" effort "$es" "$ew")")"
  [[ "$model" == inherit ]] && model="$SESSION_MODEL"
  [[ "$fan" == inherit ]] && fan="$SESSION_MODEL"
  if [[ "$model" == haiku || "$fan" == haiku ]]; then
    NOTES+=("$r: resolves to haiku; no role routes to Haiku by owner decision, effort high and never xhigh or max: reference/routing-rubric.md")
  fi
}

join() {
  local IFS=,
  printf '%s' "$*"
}

json_or_null() {
  if [[ -n "$1" ]]; then json_str "$1"; else printf 'null'; fi
}

raw_or_null() {
  if [[ -n "$1" ]]; then printf '%s' "$1"; else printf 'null'; fi
}

vendors_json() {
  local r t ad tp tf pa pd tb_items=() step vn v_parts=() vs_parts=() s_parts=() ss_parts=() sorted_sids sid
  r="$(val vendors.routing)"
  [[ -n "$r" ]] || r=true
  t="$(val vendors.trials)"
  [[ -n "$t" ]] || t=false
  ad="$(val vendors.auto_delegation)"
  [[ -n "$ad" ]] || ad=false
  tp="$(raw_or_null "$(val vendors.trials_prove)")"
  tf="$(raw_or_null "$(val vendors.trials_fail)")"
  pa="$(raw_or_null "$(val vendors.promotion_audits)")"
  pd="$(raw_or_null "$(val vendors.promotion_days)")"

  for step in "${V_TIEBREAK[@]+"${V_TIEBREAK[@]}"}"; do
    tb_items+=("$(json_str "$step")")
  done

  for vn in claude codex antigravity; do
    v_parts+=("$(json_str "$vn"):{\"in_use\":$(raw_or_null "$(val "vendors.$vn.in_use")"),\"rank\":$(raw_or_null "$(val "vendors.$vn.rank")")}")
    vs_parts+=("$(json_str "$vn"):{\"in_use\":$(json_or_null "$(src "vendors.$vn.in_use")"),\"rank\":$(json_or_null "$(src "vendors.$vn.rank")")}")
  done

  if ((${#V_SOURCE_IDS[@]} > 0)); then
    sorted_sids="$(printf '%s\n' "${V_SOURCE_IDS[@]}" | LC_ALL=C sort)"
    while IFS= read -r sid; do
      [[ -n "$sid" ]] || continue
      s_parts+=("$(json_str "$sid"):{\"enabled\":$(raw_or_null "$(val "vendors.sources.$sid.enabled")")}")
      ss_parts+=("$(json_str "$sid"):{\"enabled\":$(json_or_null "$(src "vendors.sources.$sid.enabled")")}")
    done <<<"$sorted_sids"
  fi

  printf '{"routing":%s,"trials":%s,"auto_delegation":%s,"tiebreak":[%s],"trials_prove":%s,"trials_fail":%s,"promotion_audits":%s,"promotion_days":%s,%s,"sources":{%s},"source":{"routing":%s,"trials":%s,"auto_delegation":%s,"tiebreak":%s,"trials_prove":%s,"trials_fail":%s,"promotion_audits":%s,"promotion_days":%s,%s,"sources":{%s}}}' \
    "$r" "$t" "$ad" "$(join "${tb_items[@]+"${tb_items[@]}"}")" "$tp" "$tf" "$pa" "$pd" \
    "$(join "${v_parts[@]}")" "$(join "${s_parts[@]+"${s_parts[@]}"}")" \
    "$(json_or_null "$(src vendors.routing)")" \
    "$(json_or_null "$(src vendors.trials)")" \
    "$(json_or_null "$(src vendors.auto_delegation)")" \
    "$(json_or_null "$V_TIEBREAK_SRC")" \
    "$(json_or_null "$(src vendors.trials_prove)")" \
    "$(json_or_null "$(src vendors.trials_fail)")" \
    "$(json_or_null "$(src vendors.promotion_audits)")" \
    "$(json_or_null "$(src vendors.promotion_days)")" \
    "$(join "${vs_parts[@]}")" "$(join "${ss_parts[@]+"${ss_parts[@]}"}")"
}

out_roles=()
for r in "${ROLES[@]}"; do
  if [[ "$TARGET" == all || "$TARGET" == "$r" ]]; then
    role_json "$r"
    out_roles+=("$ROLE_JSON")
  fi
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
printf '{"session_model":%s,"session_frontier":%s,"workload":%s,"roles":{%s},"vendors":%s,"layers":[%s],"notes":[%s]}\n' \
  "$session" "$SESSION_FRONTIER" "$workload" "$(join "${out_roles[@]}")" "$(vendors_json)" "$(join "${LAYERS_JSON[@]+"${LAYERS_JSON[@]}"}")" \
  "$(join "${notes_json[@]+"${notes_json[@]}"}")"
