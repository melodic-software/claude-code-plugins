#!/usr/bin/env bash
# Binding discovery + validation for the work-item tracker seam (CONTRACT.md "Setup
# (binding file)"). Sourced — callers map failures to exit 3.

[[ -n "${_WIT_BINDING_LOADED:-}" ]] && return 0
readonly _WIT_BINDING_LOADED=1

_WIT_BINDING_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=labels.sh
source "$_WIT_BINDING_LIB_DIR/labels.sh"

# The repository's one YAML parser and its convention-home resolver, as the plugin's
# generated copies (scripts/shared-copies.txt). A vendored seam without them reads
# only the legacy JSON binding.
WIT_YAML_PARSER="$_WIT_BINDING_LIB_DIR/../../../skills/triage/scripts/yaml-subset.awk"
WIT_HOME_RESOLVER="$_WIT_BINDING_LIB_DIR/../../../lib/resolve-convention-home.sh"
readonly WIT_DEFAULT_CONVENTION_HOME="docs/conventions"
readonly WIT_LEGACY_BINDING=".work-item-tracker.json"
# What an empty flow sequence reads as while the parser reads a binding, which turns
# back into []. It opens with a control character no YAML scalar can hold (raw, it is
# outside YAML's character set; escaped, the subset rejects it), so it never matches
# a value a file sets.
readonly WIT_YAML_EMPTY_SEQ=$'\002[]'

# wit_project_root: the one repo-root anchor every seam resolution uses (CONTRACT.md
# "Setup (binding file)"). Fails outside a git repo with no CLAUDE_PROJECT_DIR.
wit_project_root() {
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return 0
  fi
  git rev-parse --show-toplevel 2>/dev/null
}

# wit_convention_home <root>: the repo-relative convention home the pointer region
# binds, or the default home when the repository binds none. Fails when it declined
# a home, when no home applies (exit 5: the root is $HOME, an ancestor of it, or not
# in a git work tree, so only the legacy JSON can bind it), or when the pointer is
# broken (that message passes through to stderr).
wit_convention_home() {
  local home rc
  [[ -f "$WIT_HOME_RESOLVER" && -f "$WIT_YAML_PARSER" ]] || return 1
  home="$(bash "$WIT_HOME_RESOLVER" --root "$1" 2>/dev/null)"
  rc=$?
  case "$rc" in
  0) printf '%s\n' "$home" ;;
  1) printf '%s\n' "$WIT_DEFAULT_CONVENTION_HOME" ;;
  3)
    bash "$WIT_HOME_RESOLVER" --root "$1" >/dev/null
    return 1
    ;;
  *) return 1 ;;
  esac
}

# wit_yaml_mark_empty_seqs [<marker>]: stdin to stdout, line for line, with each empty
# flow sequence in a value position (`key: []`, `- key: []`, `- []`) replaced by
# <marker> as a double-quoted scalar. The parser prints nothing for `[]` and a record
# for the scalar. The line count is kept, so a parse error still names the file's own
# line. With no marker, a plain copy.
wit_yaml_mark_empty_seqs() {
  if [[ -z "${1:-}" ]]; then
    cat
    return
  fi
  # The lead is the indent, then `- `, a plain or quoted key and its colon, or both,
  # exactly as the parser reads them; \047 is a single quote.
  LC_ALL=C awk -v marker="$1" '
    BEGIN {
      key = "([A-Za-z0-9_-]+|\"([^\"\\\\]|\\\\.)*\"|\047([^\047]|\047\047)*\047)"
      lead = "^ *((- +)?" key "[ \t]*:[ \t]+|- +)"
    }
    {
      sub(/\r$/, "")
      if (NR == 1) sub(/^\357\273\277/, "")
      if (match($0, lead) && substr($0, RLENGTH + 1) ~ /^\[[ \t]*\][ \t]*(#.*)?$/)
        $0 = substr($0, 1, RLENGTH) "\"" marker "\""
      print
    }'
}

# wit_yaml_records <file> [<marker>]: the parser's `dotted.key<TAB>value` records, each
# empty flow sequence printed as <marker> when one is given (wit_yaml_mark_empty_seqs).
# On a parse error, names the file and line on stderr and fails.
wit_yaml_records() {
  local records
  if ! records="$({ wit_yaml_mark_empty_seqs "${2:-}" | LC_ALL=C awk -f "$WIT_YAML_PARSER"; } <"$1")"; then
    printf 'work-item-tracker: %s: line %s\n' "$1" \
      "$(awk -F '\t' '$1 == "error" { print $2 ": " $3 }' <<<"$records" | tail -n 1)" >&2
    return 1
  fi
  printf '%s\n' "$records"
}

# wit_yaml_has_binding <file>: true when the file sets a `tracker` key, or does not
# parse (so the read names the error rather than falling back to the legacy file).
wit_yaml_has_binding() {
  local records
  records="$(wit_yaml_records "$1" 2>/dev/null)" || return 0
  grep -q $'^tracker[.\t]' <<<"$records"
}

# wit_yaml_binding_json <file>: the file's `tracker` mapping as one JSON object.
# Every scalar stays a string: the parser drops quotes, so a type guessed from the
# text would turn a quoted id such as "10000" into a number. Every reader takes
# numbers and booleans as text (jq -r, then a regex or string compare). An empty flow
# sequence stays [], as the legacy JSON file writes it: jira and linear tell a present
# empty list (a config error) from an absent key (the default) with has(). A key with
# no value reads as absent (CONTRACT.md "Setup (binding file)").
wit_yaml_binding_json() {
  local records json bad
  records="$(wit_yaml_records "$1" "$WIT_YAML_EMPTY_SEQ")" || return 1
  json="$(jq -R -n -c --arg emptyseq "$WIT_YAML_EMPTY_SEQ" '
    [inputs | select(startswith("tracker.") or startswith("tracker\t"))
      | split("\t") as $f
      | {path: ($f[0] | split(".")[1:] | map(if test("^(0|[1-9][0-9]*)$") then tonumber else . end)),
         value: ($f[1:] | join("\t") | if . == $emptyseq then [] else . end)}]
    | reduce .[] as $r ({}; setpath($r.path; $r.value))' <<<"$records")" || return 1
  bad="$(jq -r 'if type != "object" then "tracker"
    else keys_unsorted - ["schema_version", "provider", "config", "docs"] | map("tracker." + .) | join(", ") end' <<<"$json")"
  if [[ -n "$bad" ]]; then
    printf 'work-item-tracker: %s: %s is not a binding key (work-items.schema.json, tracker)\n' "$1" "$bad" >&2
    return 1
  fi
  printf '%s\n' "$json"
}

# wit_find_binding: echo the binding file path: the env override, else the `tracker`
# mapping of <home>/work-items.yaml, else the legacy root .work-item-tracker.json.
# Never a CWD-upward climb: a stray ancestor or home binding would silently capture
# every repo beneath it (#2941).
wit_find_binding() {
  if [[ -n "${WORK_ITEM_TRACKER_BINDING:-}" ]]; then
    [[ -f "$WORK_ITEM_TRACKER_BINDING" ]] || return 1
    printf '%s\n' "$WORK_ITEM_TRACKER_BINDING"
    return 0
  fi
  local root home yaml
  root="$(wit_project_root)" || return 1
  [[ -n "$root" ]] || return 1
  if home="$(wit_convention_home "$root")"; then
    yaml="$root/$home/work-items.yaml"
    if [[ -f "$yaml" ]] && wit_yaml_has_binding "$yaml"; then
      printf '%s\n' "$yaml"
      return 0
    fi
  fi
  [[ -f "$root/$WIT_LEGACY_BINDING" ]] || return 1
  printf '%s\n' "$root/$WIT_LEGACY_BINDING"
}

# The only keys the personal override may refine; any other key there is a config
# error, never a merge (CONTRACT.md "Setup (binding file)").
readonly WIT_OVERRIDE_ALLOWED_PATHS='[["config","lease_ttl_hours"],["config","lease_ttl_minutes"],["config","jira","auth_email"],["config","jira","auth_env"],["config","linear","auth_env"],["config","gitea","auth_env"],["docs"]]'

# wit_override_path <binding-path>: echo where the personal override sits beside that
# binding (work-items.local.yaml beside a YAML binding, else .work-item-tracker.local.json),
# whether or not it exists.
wit_override_path() {
  local dir name=".work-item-tracker.local.json"
  [[ "$1" == *.yaml ]] && name="work-items.local.yaml"
  dir="$(cd "$(dirname "$1")" && pwd)" || return 1
  printf '%s\n' "$dir/$name"
}

# wit_find_override <binding-path>: echo the personal override path beside whatever
# binding resolved, or fail when none exists.
wit_find_override() {
  local override
  override="$(wit_override_path "$1")" || return 1
  [[ -f "$override" ]] || return 1
  printf '%s\n' "$override"
}

# wit_binding_layer_json <path>: one layer as a JSON value: the `tracker` mapping of
# a YAML file, else the whole JSON file.
wit_binding_layer_json() {
  if [[ "$1" == *.yaml ]]; then
    wit_yaml_binding_json "$1"
  else
    jq -e -c . "$1" 2>/dev/null
  fi
}

# wit_effective_binding_json <binding-path>: the team file merged with allowlisted
# personal override keys. A bad personal override fails loudly: it must never silently
# reshape team state.
wit_effective_binding_json() {
  local path="$1" team override override_json bad
  team="$(wit_binding_layer_json "$path")" || return 1
  if ! override="$(wit_find_override "$path")"; then
    printf '%s\n' "$team"
    return 0
  fi
  if ! override_json="$(wit_binding_layer_json "$override")"; then
    printf 'work-item-tracker: personal override %s does not parse as a binding layer\n' "$override" >&2
    return 1
  fi
  # Each path must be an allowlisted SCALAR or an object prefix of one; a leaf-only check
  # lets {"provider":{}} through. Use any() equality: index() on an array is a subsequence search.
  bad="$(jq -c --argjson allowed "$WIT_OVERRIDE_ALLOWED_PATHS" '
    . as $o
    | [paths]
    | map(select(. as $p
        | ((($o | getpath($p)) | type) as $t
           | ((any($allowed[]; . == $p) and $t != "object" and $t != "array")
              or ($t == "object"
                  and any($allowed[]; (length > ($p | length)) and (.[:($p | length)] == $p)))))
        | not))' <<<"$override_json")"
  if [[ "$bad" != "[]" ]]; then
    printf 'work-item-tracker: personal override %s sets non-overridable key(s) %s — only lease TTL and per-provider auth identity (jira, linear, gitea) may be personal; see CONTRACT.md "Setup (binding file)"\n' \
      "$override" "$bad" >&2
    return 1
  fi
  # Merge by PRESENCE, not non-null value: an explicit null merges and faces normal
  # validation, never a silent fallback to the team value.
  jq -c -s --argjson allowed "$WIT_OVERRIDE_ALLOWED_PATHS" '
    .[0] as $team | .[1] as $o
    | [$o | paths(type != "object")] as $present
    | reduce ($allowed[] | . as $p | select(any($present[]; . == $p))) as $p
        ($team; setpath($p; $o | getpath($p)))' <<<"$team"$'\n'"$override_json"
}

# wit_role_label <binding-json> <role> <default>: the configured label, or <default>
# when absent OR empty (jq's `//` alone would let a configured empty string win).
wit_role_label() {
  local configured
  configured="$(jq -r --arg role "$2" '.config.role_labels[$role] // empty' <<<"$1")"
  printf '%s\n' "${configured:-$3}"
}

# wit_config_list <binding-json> <key> <default-json>: config.<key> as one JSON array,
# or <default-json> (an array) when it is absent or empty. Fails on a present value that
# is not a list of non-empty strings.
wit_config_list() {
  jq -c -e --arg k "$2" --argjson default "$3" '.config[$k]
    | if . == null or . == [] then $default
      elif type == "array" and all(.[]; type == "string" and length > 0) then .
      else false end' <<<"$1" 2>/dev/null
}

# wit_config_text <binding-json> <key> <default>: config.<key>, or <default> when it is
# absent or empty. Fails on a present value that is not a string.
wit_config_text() {
  local value
  value="$(jq -r -e --arg k "$2" '.config[$k]
    | if . == null then "" elif type == "string" then . else error("not a string") end' <<<"$1" 2>/dev/null)" ||
    return 1
  printf '%s\n' "${value:-$3}"
}

# wit_with_owner_decision <label> <default>...: the defaults as one JSON array, with the
# shipped owner-decision label replaced by <label>, so a role remap reaches the hold
# label defaults.
wit_with_owner_decision() {
  local label="$1"
  shift
  jq -n -c --arg from "$WIT_DEFAULT_OWNER_DECISION_LABEL" --arg to "$label" \
    '$ARGS.positional | map(if . == $from then $to else . end)' --args "$@"
}

# wit_invalid <path> <key> <value>: name the file (the personal override when it sets
# the key), key and value of a rejected binding value on stderr (ADR 0075 "The
# invalid-value rule"), and fail.
wit_invalid() {
  local file="$1" key="$2" override present
  if override="$(wit_find_override "$1")"; then
    present="$(wit_binding_layer_json "$override" 2>/dev/null |
      jq --arg k "$2" '($k | split(".")) as $p | any(paths; . == $p)' 2>/dev/null)"
    [[ "$present" == "true" ]] && file="$override"
  fi
  [[ "$file" == *.yaml ]] && key="tracker.$key"
  printf 'work-item-tracker: %s: invalid %s: %s\n' "$file" "$key" "${3:-(absent)}" >&2
  return 1
}

# wit_storage_root <path>: where a relative storage_dir roots: the project root for
# a YAML binding under it (the home is a subdirectory), else the binding's directory.
wit_storage_root() {
  local root
  root="$(wit_project_root 2>/dev/null)"
  if [[ "$1" == *.yaml && -n "$root" && "$1" == "$root"/* ]]; then
    printf '%s\n' "$root"
  else
    (cd "$(dirname "$1")" && pwd)
  fi
}

# wit_read_binding <path>: validate shape and export the WIT_* binding values.
# lease_ttl_hours is REQUIRED: defaults live in the binding, never in code.
wit_read_binding() {
  local path="$1" json version provider ttl storage human_gated autonomous_eligible recurring_maintenance container container_type minutes
  local owner_decision hold_labels hold_states hold_state_labels wayfind
  json="$(wit_effective_binding_json "$path")" || return 1
  if [[ "$path" == */"$WIT_LEGACY_BINDING" && "$path" != "${WORK_ITEM_TRACKER_BINDING:-}" ]]; then
    printf 'work-item-tracker: notice: read the legacy binding %s; move it under tracker: in <home>/work-items.yaml (CONTRACT.md "Setup (binding file)")\n' "$path" >&2
  fi
  version="$(jq -r '.schema_version // empty' <<<"$json")"
  [[ "$version" == 1.* ]] || { wit_invalid "$path" schema_version "$version"; return 1; }
  provider="$(jq -r '.provider // empty' <<<"$json")"
  # The provider name becomes an adapter directory path: a bare segment only, so a
  # binding value can never traverse outside adapters/<provider>.
  [[ "$provider" =~ ^[a-zA-Z0-9_-]+$ ]] || { wit_invalid "$path" provider "$provider"; return 1; }
  ttl="$(jq -r '.config.lease_ttl_hours // empty' <<<"$json")"
  [[ "$ttl" =~ ^[0-9]+$ ]] || { wit_invalid "$path" config.lease_ttl_hours "$ttl"; return 1; }
  minutes="$(jq -r '.config.lease_ttl_minutes // 0' <<<"$json")"
  [[ "$minutes" =~ ^[0-9]+$ && "$minutes" -le 59 ]] || { wit_invalid "$path" config.lease_ttl_minutes "$minutes"; return 1; }
  storage="$(jq -r '.config.storage_dir // empty' <<<"$json")"
  if [[ "$provider" == "local-markdown" && -z "$storage" ]]; then
    wit_invalid "$path" config.storage_dir "$storage"
    return 1
  fi
  # A relative storage_dir is rooted at the binding's directory (a YAML binding's
  # project root), never the caller's CWD, so a verb run from a subdirectory reads
  # the same store.
  if [[ -n "$storage" && "$storage" != /* ]]; then
    storage="$(wit_storage_root "$path")/$storage"
  fi
  human_gated="$(wit_role_label "$json" "human-gated" "$WIT_DEFAULT_HUMAN_GATED_LABEL")"
  autonomous_eligible="$(wit_role_label "$json" "autonomous-eligible" "$WIT_DEFAULT_AUTONOMOUS_ELIGIBLE_LABEL")"
  recurring_maintenance="$(wit_role_label "$json" "recurring-maintenance" "$WIT_DEFAULT_RECURRING_MAINTENANCE_LABEL")"
  # A present non-string container_label is a config error, not a fallback: jq -r would
  # stringify it into a label no item carries, letting containers onto the frontier.
  container_type="$(jq -r '.config.container_label | type' <<<"$json")"
  [[ "$container_type" == "null" || "$container_type" == "string" ]] ||
    { wit_invalid "$path" config.container_label "$(jq -c '.config.container_label' <<<"$json")"; return 1; }
  container="$(jq -r '.config.container_label // empty' <<<"$json")"
  container="${container:-$WIT_DEFAULT_CONTAINER_LABEL}"
  owner_decision="$(wit_role_label "$json" "owner-decision" "$WIT_DEFAULT_OWNER_DECISION_LABEL")"
  # The hold lists and the wayfind prefix: absent or empty keeps the lib/labels.sh
  # default; a present value of the wrong shape is a config error, never a fallback.
  hold_labels="$(wit_config_list "$json" hold_labels \
    "$(wit_with_owner_decision "$owner_decision" "${WIT_HUMAN_FLOOR_STATUS_LABELS[@]}")")" ||
    { wit_invalid "$path" config.hold_labels "$(jq -c '.config.hold_labels' <<<"$json")"; return 1; }
  hold_states="$(wit_config_list "$json" hold_states \
    "$(jq -n -c '$ARGS.positional' --args "${WIT_HUMAN_FLOOR_STATUS_STATES[@]}")")" ||
    { wit_invalid "$path" config.hold_states "$(jq -c '.config.hold_states' <<<"$json")"; return 1; }
  hold_state_labels="$(wit_config_list "$json" hold_state_labels \
    "$(wit_with_owner_decision "$owner_decision" "${WIT_HOLD_STATE_LABELS[@]}")")" ||
    { wit_invalid "$path" config.hold_state_labels "$(jq -c '.config.hold_state_labels' <<<"$json")"; return 1; }
  wayfind="$(wit_config_text "$json" wayfind_label_prefix "$WIT_WAYFIND_LABEL_PREFIX")" ||
    { wit_invalid "$path" config.wayfind_label_prefix "$(jq -c '.config.wayfind_label_prefix' <<<"$json")"; return 1; }
  WIT_PROVIDER="$provider"
  WIT_LEASE_TTL_HOURS="$ttl"
  WIT_LEASE_TTL_MINUTES="$minutes"
  WIT_STORAGE_DIR="$storage"
  WIT_HUMAN_GATED_LABEL="$human_gated"
  WIT_AUTONOMOUS_ELIGIBLE_LABEL="$autonomous_eligible"
  WIT_RECURRING_MAINTENANCE_LABEL="$recurring_maintenance"
  WIT_CONTAINER_LABEL="$container"
  WIT_OWNER_DECISION_LABEL="$owner_decision"
  WIT_HOLD_LABELS_JSON="$hold_labels"
  WIT_HOLD_STATES_JSON="$hold_states"
  WIT_HOLD_STATE_LABELS_JSON="$hold_state_labels"
  WIT_WAYFIND_PREFIX="$wayfind"
  export WIT_PROVIDER WIT_LEASE_TTL_HOURS WIT_LEASE_TTL_MINUTES WIT_STORAGE_DIR WIT_HUMAN_GATED_LABEL \
    WIT_AUTONOMOUS_ELIGIBLE_LABEL WIT_RECURRING_MAINTENANCE_LABEL WIT_CONTAINER_LABEL \
    WIT_OWNER_DECISION_LABEL WIT_HOLD_LABELS_JSON WIT_HOLD_STATES_JSON WIT_HOLD_STATE_LABELS_JSON \
    WIT_WAYFIND_PREFIX
}
