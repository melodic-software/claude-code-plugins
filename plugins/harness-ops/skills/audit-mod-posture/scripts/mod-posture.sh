#!/usr/bin/env bash
# Read-only inventory of the mods this Claude Code can run: one TSV row per mod.
#
# Installed tier: `claude plugin list --json`, one row per distinct installPath whose
# hooks/hooks.json (or plugin.json's inline hooks object) declares `modules`; its hooks and
# calls come from `claude plugin validate --json <installPath>`, which reads the code without
# loading it and writes nothing to the directory (mod-posture.test.sh holds that). Built-in
# tier: an inventory report (`--builtin-json`, the JSON /harness-ops:inventory writes), plus
# the "How to turn it off" column of the mods overview "Built-in mods" table for can_disable.
#
# Prints names only: plugin ids, hook event names and mods API method names, each filtered
# through a strict grammar, plus fixed words. Never prints a settings or env value, a path,
# or any `claude auth status` field but the derived guard state.
#
# Usage: mod-posture.sh [--date YYYY-MM-DD] [--project <dir>] [--builtin-json <file>]
#                       [--overview <file> | --no-fetch] [--managed-file <file>]
#                       [--surface terminal|desktop]
# Env (test seam): MOD_POSTURE_CLAUDE  claude executable (default: claude on PATH)
# Exit: 0 inventory printed (rows may be partial; read the footers); 2 usage or jq missing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../../lib/managed-scope.sh
source "$PLUGIN_ROOT/lib/managed-scope.sh"

CLAUDE="${MOD_POSTURE_CLAUDE:-claude}"
DATE=""
PROJECT="$PWD"
BUILTIN_JSON=""
OVERVIEW=""
NO_FETCH=0
MANAGED_FILE=""
SURFACE=""

usage() {
  sed -n '15,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}
need() { [[ $# -ge 2 && -n "$2" ]] || {
  echo "mod-posture.sh: $1 needs a value" >&2
  exit 2
}; }
while [[ $# -gt 0 ]]; do
  case "$1" in
  --date) need "$@" && DATE="$2" && shift 2 ;;
  --project) need "$@" && PROJECT="$2" && shift 2 ;;
  --builtin-json) need "$@" && BUILTIN_JSON="$2" && shift 2 ;;
  --overview) need "$@" && OVERVIEW="$2" && shift 2 ;;
  --no-fetch) NO_FETCH=1 && shift ;;
  --managed-file) need "$@" && MANAGED_FILE="$2" && shift 2 ;;
  --surface) need "$@" && SURFACE="$2" && shift 2 ;;
  -h | --help) usage && exit 0 ;;
  *) echo "mod-posture.sh: unknown argument (see --help)" >&2 && exit 2 ;;
  esac
done
[[ -z "$DATE" ]] && DATE="$(date +%Y-%m-%d)"
[[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
  echo "mod-posture.sh: --date must be YYYY-MM-DD" >&2
  exit 2
}
case "$SURFACE" in "" | terminal | desktop) ;; *)
  echo "mod-posture.sh: --surface is terminal or desktop" >&2
  exit 2
  ;;
esac
command -v jq >/dev/null 2>&1 || {
  echo "mod-posture.sh: jq is required" >&2
  exit 2
}

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf -- "${TMP:?}"' EXIT
NOT_READ=()

# The grammars every printed name must fully match; anything else prints as a fixed word.
ID_RE='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}@[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
HOOK_RE='^[a-z][A-Za-z]*(\.[A-Za-z*][A-Za-z]*)*(\{[a-z][A-Za-z]*=[A-Za-z0-9._:-]{1,40}\})?$'
CALL_RE='^\$\.[a-z][A-Za-z]*\.[a-z][A-Za-z]*$'

safe_id() { [[ "$1" =~ $ID_RE ]] && printf '%s' "$1" || printf 'redacted-id'; }
# filter_list <regex>: comma-separated names on stdin -> the ones that match, deduplicated in
# order, joined by commas; `-` when none match.
filter_list() {
  local re="$1" out="" item seen=","
  local IFS=','
  read -r -a items || true
  for item in "${items[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    item="${item%% (via *}"
    [[ "$item" =~ $re ]] || continue
    [[ "$seen" == *",$item,"* ]] && continue
    seen+="$item,"
    out+="${out:+,}$item"
  done
  printf '%s' "${out:--}"
}

ROWS=()
row() { ROWS+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$@")"); }

# --- Installed tier --------------------------------------------------------------------
project_real="$(cd "$PROJECT" 2>/dev/null && pwd -P)" || project_real=""
if ! "$CLAUDE" plugin list --json >"$TMP/list.json" 2>/dev/null || ! jq -e 'type == "array"' "$TMP/list.json" >/dev/null 2>&1; then
  NOT_READ+=("installed tier: claude plugin list --json did not return a list")
else
  # One line per installPath: path, id, tier, enabled. An entry counts toward `enabled` when it
  # applies to this project: user or managed scope, or a project or local entry for --project.
  # A path no such entry names is `elsewhere`: skipped, and counted in a footer.
  jq -r --arg proj "$project_real" '
    [.[] | select((.installPath | type) == "string")]
    | group_by(.installPath)[]
    | . as $g
    | [ $g[] | select(.scope == "user" or .scope == "managed" or (.projectPath // "") == $proj) ] as $here
    | [ $g[0].installPath,
        ($g[0].id // ""),
        (if any($g[]; .scope == "managed") then "managed" else "user" end),
        (if ($here | length) == 0 then "elsewhere"
         elif any($here[]; .enabled == true) then "on"
         elif all($here[]; .enabled == false) then "off"
         else "unknown" end) ]
    | @tsv' "$TMP/list.json" >"$TMP/paths.tsv" 2>/dev/null
  elsewhere=0
  while IFS=$'\t' read -r path id tier enabled; do
    [[ -d "$path" ]] || continue
    [[ "$enabled" == "elsewhere" ]] && elsewhere=$((elsewhere + 1)) && continue
    modules=0
    if [[ -f "$path/hooks/hooks.json" ]] && jq -e '(.modules | type) == "array" and (.modules | length) > 0' "$path/hooks/hooks.json" >/dev/null 2>&1; then
      modules=1
    elif [[ -f "$path/.claude-plugin/plugin.json" ]] && jq -e '(.hooks | type) == "object" and (.hooks.modules | type) == "array" and (.hooks.modules | length) > 0' "$path/.claude-plugin/plugin.json" >/dev/null 2>&1; then
      modules=1
    fi
    ((modules)) || continue
    if "$CLAUDE" plugin validate --json "$path" >"$TMP/validate.json" 2>/dev/null || jq -e '.contents' "$TMP/validate.json" >/dev/null 2>&1; then
      notes="$(jq -r '[.contents[]?.notes[]? | strings] | .[]' "$TMP/validate.json" 2>/dev/null)"
      hooks="$(printf '%s\n' "$notes" | sed -n 's/^[^ ]* hooks: //p' | paste -sd, - | filter_list "$HOOK_RE")"
      calls="$(printf '%s\n' "$notes" | sed -n 's/^[^ ]* calls: //p' | sed 's/ (via [^)]*)//g' | paste -sd, - | filter_list "$CALL_RE")"
      source="validate"
      jq -e '.success == true' "$TMP/validate.json" >/dev/null 2>&1 || source="validate-errors"
    else
      hooks="unknown" calls="unknown" source="validate-failed"
    fi
    row "$(safe_id "$id")" "$tier" "$enabled" "yes" "$hooks" "$calls" "$source"
  done <"$TMP/paths.tsv"
  ((elsewhere)) && NOT_READ+=("installed tier: $elsewhere install path(s) only other projects enable, skipped")
fi

# --- Built-in tier ---------------------------------------------------------------------
# can_disable per built-in name from the overview table's last column: "You can't..." is no.
overview_file=""
if [[ -n "$OVERVIEW" ]]; then
  [[ -f "$OVERVIEW" ]] && overview_file="$OVERVIEW" || NOT_READ+=("can_disable: --overview file not found")
elif ((NO_FETCH)); then
  NOT_READ+=("can_disable: --no-fetch, overview page not read")
elif FETCH_DOCS_CLAUDE_BIN='' bash "$PLUGIN_ROOT/scripts/fetch-docs.sh" --out "$TMP/docs" --cache plugins/mods/overview >/dev/null 2>&1 &&
  [[ "$(jq -r '.pages[0].state' "$TMP/docs/manifest.json" 2>/dev/null)" == "read" ]]; then
  overview_file="$TMP/docs/plugins/mods/overview.md"
else
  NOT_READ+=("can_disable: fetch of the mods overview page failed")
fi
declare -A CAN_DISABLE=()
if [[ -n "$overview_file" ]]; then
  while IFS=$'\t' read -r name how; do
    [[ "$name" =~ ^cc-plugin-[a-z0-9-]+$ ]] || continue
    case "$how" in "You can't"* | "You cannot"*) CAN_DISABLE[$name]=no ;; ?*) CAN_DISABLE[$name]=yes ;; *) ;; esac
  done < <(awk -F'|' '/^\| *`cc-plugin-/ {
      n = $2; gsub(/[ `]/, "", n); h = $(NF - 1); sub(/^ +/, "", h); sub(/ +$/, "", h)
      print n "\t" h }' "$overview_file")
  ((${#CAN_DISABLE[@]})) || NOT_READ+=("can_disable: no Built-in mods table rows found on the overview page")
fi

if [[ -z "$BUILTIN_JSON" ]]; then
  NOT_READ+=("built-in tier: built-in mods were not read (no --builtin-json inventory report)")
elif ! jq -e '(.builtin_plugins | type) == "object"' "$BUILTIN_JSON" >/dev/null 2>&1; then
  NOT_READ+=("built-in tier: --builtin-json has no builtin_plugins section")
else
  NOT_READ+=("built-in enabled: managed settings and --settings are not read, so on/off is partial")
  while IFS=$'\t' read -r name id enabled hooks; do
    [[ "$name" =~ ^cc-plugin-[a-z0-9-]+$ ]] || continue
    if [[ "$hooks" != "unknown" && "$hooks" != "-" ]]; then
      hooks="$(printf '%s' "$hooks" | filter_list "$HOOK_RE")"
    fi
    row "$(safe_id "${id:-$name@builtin}")" builtin "$enabled" "${CAN_DISABLE[$name]:-unknown}" "$hooks" unknown builtin-lane
  done < <(jq -r '(.builtin_plugin_state.plugins // {}) as $st
    | .builtin_plugins | to_entries[]
    | ($st[.key] // {}) as $s
    | [ .key, (.value.id // ""),
        ((if (.value.default_enabled | type) == "boolean" then .value.default_enabled
          else $s.default_enabled end) as $default
         | if ($s.enabled_setting | type) == "boolean" then (if $s.enabled_setting then "on" else "off" end)
           elif ($default | type) == "boolean" then (if $default then "on" else "off" end)
           else "unknown" end),
        (if (.value.hook_events | type) != "array" then "unknown"
         elif (.value.hook_events | length) == 0 then "-"
         else (.value.hook_events | join(",")) end) ]
    | @tsv' "$BUILTIN_JSON" 2>/dev/null)
fi

# --- Guard -----------------------------------------------------------------------------
# Seated when the machine has managed settings or the account is on a Team or Enterprise plan
# (mods admin page, "Know what happens by default").
managed="unknown"
base="$(mscope::base_file "$MANAGED_FILE")"
dropin="$(mscope::dropin_dir "$MANAGED_FILE")"
if [[ -f "$base" ]] || compgen -G "$dropin/*.json" >/dev/null 2>&1; then
  managed="present"
else
  managed="absent"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    if command -v reg.exe >/dev/null 2>&1 || command -v reg >/dev/null 2>&1; then
      if MSYS2_ARG_CONV_EXCL='*' reg query "$key" /v Settings >/dev/null 2>&1; then managed="present" && break; fi
    else
      managed="unknown"
    fi
  done < <([[ -z "$MANAGED_FILE" ]] && mscope::registry_keys)
  if [[ "$managed" == "absent" && -z "$MANAGED_FILE" && -n "$(mscope::plist_domain)" ]]; then
    managed="unknown"
    NOT_READ+=("guard: the macOS managed preferences domain is not probed")
  fi
fi
if [[ -z "$MANAGED_FILE" && -n "${WSL_DISTRO_NAME:-}" ]]; then
  NOT_READ+=("guard: the Windows policy chain WSL can inherit (wslInheritsWindowsSettings) is not read")
fi
[[ -f "$(mscope::remote_cache_file "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")" ]] &&
  NOT_READ+=("guard: a server-managed settings cache exists; it is not counted as managed settings")

plan=""
if "$CLAUDE" auth status --json >"$TMP/auth.json" 2>/dev/null; then
  plan="$(jq -r 'if (.subscriptionType | type) == "string" then .subscriptionType else "none" end' "$TMP/auth.json" 2>/dev/null)"
fi
rm -f -- "$TMP/auth.json"
case "$plan" in team | enterprise | max | pro | none) ;; "") plan="unread" ;; *) plan="other" ;; esac

if [[ "$managed" == "present" ]]; then
  guard="seated (managed settings present)"
elif [[ "$plan" == "team" || "$plan" == "enterprise" ]]; then
  guard="seated (plan $plan)"
elif [[ "$managed" == "absent" && "$plan" != "unread" && "$plan" != "other" ]]; then
  guard="not-seated (no managed settings; plan $plan)"
else
  guard="unknown (managed settings $managed; plan $plan)"
fi

# --- Surface ---------------------------------------------------------------------------
version="$("$CLAUDE" --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
if [[ -z "$SURFACE" ]]; then
  case "${CLAUDE_CODE_ENTRYPOINT:-}" in *desktop*) SURFACE=desktop ;; *) SURFACE=terminal ;; esac
fi

printf '# mod-posture inventory %s\n' "$DATE"
printf 'id\ttier\tenabled\tcan_disable\thooks\tcalls\tsource\n'
((${#ROWS[@]})) && printf '%s\n' "${ROWS[@]}"
printf '# guard: %s\n' "$guard"
if [[ "$SURFACE" == "terminal" ]]; then
  printf '# surface: terminal (%s); the Desktop app bundles its own copy, which may differ: check it by running this skill in a Desktop Code-tab session\n' "${version:-unknown}"
else
  printf '# surface: desktop (%s, the claude on PATH)\n' "${version:-unknown}"
fi
for reason in "${NOT_READ[@]}"; do printf '# not read: %s\n' "$reason"; done
exit 0
