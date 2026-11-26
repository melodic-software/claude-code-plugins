#!/usr/bin/env bash
set -u

usage() {
  cat <<'EOF'
inventory.sh - per-scope automation counts for the audit-automation-gaps skill.

Usage:
  inventory.sh [--help]

It takes no other argument. An unrecognized argument is a usage error rather
than a silently ignored one, because a run that ignored its arguments would
report a full audit under a scope nobody asked for.

Sections, in a stable order:
  Hook locations  one row per documented hook location, each with a status, a
                  standing-versus-conditional kind, and three counts: PROBED,
                  the files or paths this run examined; DECLARING, how many of
                  them register at least one hook; HANDLERS, how many hook
                  commands those registrations add. A frontmatter row carries no
                  HANDLERS figure because the YAML inside its hooks block is not
                  parsed here.
  Components      repository-tree counts for plugins, skills, agents, MCP
                  servers, and hook scripts present on disk
  Enablement      the enabledPlugins maps as read, per scope, with no verdict
  Notes           what a reader must know to not over-read the numbers

A location this script could not read reports unreadable, invalid-json, skipped
or not-probed. It never reports that location as 0. A directory reached through
a symlink is walked, not skipped; a JSON file whose hooks or enabledPlugins key
holds the wrong type is invalid-json, not zero hooks; and .git and node_modules
are pruned from every walk so a sample hook or a vendored tree cannot inflate a
component count.

Test seams, unset in normal use:
  INVENTORY_PROJECT_DIR    project root, instead of the git toplevel; both
                           project settings files are then read from it
  INVENTORY_USER_SETTINGS  user settings file, instead of the documented path
  INVENTORY_MANAGED_PATH   managed-settings.json, instead of the per-OS path
  INVENTORY_JQ             the jq command name, so a test can take jq away

Exit: 0 once a table is printed; 2 for a usage error or a project root that
could not be entered. The output is a skill's pre-computed context, so a
partial read still exits 0 and says per row what it could not reach; only a run
that can produce no honest table at all exits nonzero.
EOF
}

usage_error() {
  printf 'inventory.sh: unrecognized argument: %s\n' "$1" >&2
  usage >&2
  exit 2
}

if [[ "$#" -gt 0 ]]; then
  case "$1" in
  -h | --help)
    [[ "$#" -eq 1 ]] || usage_error "$2"
    usage
    exit 0
    ;;
  *) usage_error "$1" ;;
  esac
fi

jq_bin="${INVENTORY_JQ:-jq}"
have_jq=0
command -v "$jq_bin" >/dev/null 2>&1 && have_jq=1

plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)}"
managed_lib="$plugin_root/lib/managed-scope.sh"
have_managed_lib=0
if [[ -r "$managed_lib" ]]; then
  # shellcheck source=../../../lib/managed-scope.sh
  source "$managed_lib" && have_managed_lib=1
fi

start_dir="$(pwd -P)"
git_root=""
main_root=""
if [[ -n "${INVENTORY_PROJECT_DIR:-}" ]]; then
  project_root="$INVENTORY_PROJECT_DIR"
else
  git_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  project_root="${git_root:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  common_dir=""
  [[ -z "$git_root" ]] || common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
  [[ "${common_dir##*/}" != .git ]] || main_root="$(cd -- "${common_dir%/*}" 2>/dev/null && pwd -P)"
fi

if [[ ! -d "$project_root" ]] || ! cd -- "$project_root" 2>/dev/null; then
  printf 'inventory.sh: project root %s is not a directory this run could enter; no counts were produced.\n' \
    "$project_root" >&2
  exit 2
fi
project_root="$PWD"

user_settings="${INVENTORY_USER_SETTINGS:-${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/settings.json}"
project_settings=".claude/settings.json"
local_settings=".claude/settings.local.json"
if [[ -n "$git_root" ]]; then
  root_real="$(pwd -P)"
  [[ "$start_dir" == "$root_real" ]] || project_settings="$start_dir/.claude/settings.json"
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32*)
    local_settings="${project_settings%settings.json}settings.local.json"
    ;;
  *)
    [[ -z "$main_root" || "$main_root" == "$root_real" ]] || local_settings="$main_root/.claude/settings.local.json"
    ;;
  esac
fi

managed_file=""
managed_dropin=""
if [[ "$have_managed_lib" -eq 1 ]]; then
  managed_file="$(mscope::base_file "${INVENTORY_MANAGED_PATH:-}")"
  managed_dropin="$(mscope::dropin_dir "${INVENTORY_MANAGED_PATH:-}")"
fi

notes=()
note() { notes+=("$1"); }

json_status() {
  local f="$1"
  if [[ -z "$f" ]]; then
    printf 'not-probed'
  elif [[ ! -e "$f" ]]; then
    printf 'absent'
  elif [[ ! -f "$f" || ! -r "$f" ]]; then
    printf 'unreadable'
  elif [[ "$have_jq" -eq 0 ]]; then
    printf 'skipped'
  elif ! "$jq_bin" -e 'type == "object"' "$f" >/dev/null 2>&1; then
    printf 'invalid-json'
  else
    printf 'present'
  fi
}

dir_status() {
  local d="$1"
  if [[ -z "$d" ]]; then
    printf 'not-probed'
  elif [[ -d "$d" && -r "$d" && -x "$d" ]]; then
    printf 'present'
  elif [[ -e "$d" || -L "$d" ]]; then
    printf 'unreadable'
  else
    printf 'absent'
  fi
}

find0() {
  local dirs=()
  while [[ "$#" -gt 0 && "$1" != "--" ]]; do
    dirs+=("$1")
    shift
  done
  [[ "$#" -gt 0 ]] && shift
  [[ "${#dirs[@]}" -gt 0 && "$#" -gt 0 ]] || return 0
  find -H "${dirs[@]}" \( -name .git -o -name node_modules \) -prune -o \( "$@" \) -print0 2>/dev/null
}

count0() { tr -cd '\000' | wc -c | tr -d ' '; }

SETTINGS_EVENTS_JQ='[(.hooks // {}) | to_entries[] | select((.value | type) == "array" and (.value | length) > 0) | .key] | length'
SETTINGS_HANDLERS_JQ='[(.hooks // {}) | to_entries[] | .value[]? | (.hooks // []) | length] | add // 0'
PLUGIN_EVENTS_JQ='def hk: if has("hooks") then .hooks else . end; [hk | to_entries[] | select((.value | type) == "array" and (.value | length) > 0) | .key] | length'
PLUGIN_HANDLERS_JQ='def hk: if has("hooks") then .hooks else . end; [hk | to_entries[] | .value[]? | (.hooks // []) | length] | add // 0'

jq_num() {
  local program="$1" file="$2" out
  out="$("$jq_bin" -r "$program" "$file" 2>/dev/null)" || return 1
  case "$out" in
  '' | *[!0-9]*) return 1 ;;
  *) printf '%s' "$out" ;;
  esac
}

jq_type() { "$jq_bin" -r "$1 | type" "$2" 2>/dev/null; }

plugin_roots=()
while IFS= read -r -d '' manifest; do
  [[ -n "$manifest" ]] || continue
  plugin_roots+=("${manifest%/.claude-plugin/plugin.json}")
done < <(find -H . -maxdepth 4 \( -name .git -o -name node_modules \) -prune -o \
  -type f -path '*/.claude-plugin/plugin.json' -print0 2>/dev/null)

find0_plugin_roots() {
  [[ "${#plugin_roots[@]}" -gt 0 ]] || return 0
  find0 "${plugin_roots[@]}" -- "$@"
}

count_in_plugin_roots() { find0_plugin_roots "$@" | count0; }

count_dir() {
  local status="$1" dir="$2"
  shift 2
  case "$status" in
  present) find0 "$dir" -- "$@" | count0 ;;
  absent) printf '0' ;;
  *) printf '%s' "$status" ;;
  esac
}

add_counts() {
  case "$1$2" in
  *[!0-9]*) printf '%s+%s' "$1" "$2" ;;
  *) printf '%s' "$(($1 + $2))" ;;
  esac
}

scope_count() {
  case "$1" in
  present | absent) printf '%s' "$2" ;;
  *) printf '%s' "$1" ;;
  esac
}

count_frontmatter_hooks() {
  local list="$1" f
  local files=()
  while IFS= read -r -d '' f; do
    [[ -n "$f" ]] || continue
    files+=("$f")
  done <"$list"
  [[ "${#files[@]}" -gt 0 ]] || {
    printf '0'
    return
  }
  awk '
    FNR == 1 { in_fm = 0; opened = 0; seen = 0 }
    FNR == 1 && $0 ~ /^---[[:space:]]*$/ { in_fm = 1; opened = 1; next }
    opened && in_fm && $0 ~ /^---[[:space:]]*$/ { in_fm = 0; next }
    opened && in_fm && seen == 0 && $0 ~ /^hooks:[[:space:]]*$/ { n += 1; seen = 1 }
    END { printf "%d", n + 0 }
  ' "${files[@]}" 2>/dev/null
}

row() {
  printf '  %-20s %-12s %-11s %7s %9s %8s  %s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}


shc_status=""
shc_events=0
shc_handlers=0
settings_hook_counts() {
  local file="$1" hooks_type
  shc_events=0
  shc_handlers=0
  shc_status="$(json_status "$file")"
  [[ "$shc_status" == "present" ]] || return 0
  hooks_type="$(jq_type '(.hooks // {})' "$file")"
  if [[ "$hooks_type" != "object" ]]; then
    note "$file is valid JSON, but its hooks key holds ${hooks_type:-a value jq could not type} rather than an object, so no hook entry could be read from it. A malformed hooks block is not an absence of hooks."
    shc_status=invalid-json
    return 0
  fi
  if ! shc_events="$(jq_num "$SETTINGS_EVENTS_JQ" "$file")" ||
    ! shc_handlers="$(jq_num "$SETTINGS_HANDLERS_JQ" "$file")"; then
    note "$file parses as JSON, but the hook query over it failed, so its hook entries are counted nowhere in this table."
    shc_status=unreadable
    shc_events=0
    shc_handlers=0
  fi
  return 0
}

settings_row() {
  local label="$1" file="$2" declaring=0
  settings_hook_counts "$file"
  if [[ "$shc_status" != "present" ]]; then
    row "$label" "$shc_status" standing 1 - - "$file"
    return
  fi
  [[ "$shc_events" -gt 0 ]] && declaring=1
  row "$label" "$shc_status" standing 1 "$declaring" "$shc_handlers" "$file"
}

managed_policy_row() {
  local base="$1" dropin_dir="$2" dropin_status="$3"
  local drops=() f base_status floor="" probed_floor=""
  local probed=1 declaring=0 handlers=0 read_any=0
  local probed_out declaring_out handlers_out source_label

  settings_hook_counts "$base"
  base_status="$shc_status"
  case "$base_status" in
  present)
    read_any=1
    [[ "$shc_events" -gt 0 ]] && declaring=$((declaring + 1))
    handlers=$((handlers + shc_handlers))
    ;;
  absent) ;;
  *) floor="$base_status" ;;
  esac

  case "$dropin_status" in
  present)
    while IFS= read -r -d '' f; do
      [[ -n "$f" ]] || continue
      drops+=("$f")
    done < <(find0 "$dropin_dir" -- -maxdepth 1 -type f -name '*.json')
    ;;
  absent | not-probed) ;;
  *)
    probed_floor="$dropin_status"
    [[ -n "$floor" ]] || floor="$dropin_status"
    note "managed-settings.d exists at $dropin_dir but could not be traversed ($dropin_status), so how many drop-in files it holds is unknown to this run. They merge on top of managed-settings.json, so the managed policy in force may carry hooks nothing above accounts for, and the managed-policy row is a floor rather than a total."
    ;;
  esac

  for f in ${drops[@]+"${drops[@]}"}; do
    probed=$((probed + 1))
    settings_hook_counts "$f"
    if [[ "$shc_status" != "present" ]]; then
      [[ -n "$floor" ]] || floor="$shc_status"
      note "managed drop-in $f is $shc_status, so whatever it registers is missing from the managed-policy row, which is therefore a floor rather than a total."
      continue
    fi
    read_any=1
    [[ "$shc_events" -gt 0 ]] && declaring=$((declaring + 1))
    handlers=$((handlers + shc_handlers))
  done

  if [[ "${#drops[@]}" -gt 0 ]]; then
    note "managed-settings.d exists at $dropin_dir with ${#drops[@]} drop-in file(s); they merge on top of managed-settings.json and are counted in the managed-policy row above. That row counts registrations read, so a handler written identically in two of these files is one entry in force and two there."
  fi

  if [[ "$read_any" -eq 0 ]]; then
    row managed-policy "$base_status" standing "$probed" - - "$base"
    return
  fi

  probed_out="$probed"
  [[ -n "$probed_floor" ]] && probed_out="$(add_counts "$probed" "$probed_floor")"
  declaring_out="$declaring"
  handlers_out="$handlers"
  if [[ -n "$floor" ]]; then
    declaring_out="$(add_counts "$declaring" "$floor")"
    handlers_out="$(add_counts "$handlers" "$floor")"
  fi
  source_label="$base"
  [[ "${#drops[@]}" -gt 0 ]] && source_label="$base + ${#drops[@]} drop-in(s)"
  row managed-policy present standing "$probed_out" "$declaring_out" "$handlers_out" "$source_label"
}

plugin_hook_row() {
  local manifests=() m status total_events=0 total_handlers=0 declaring=0 scanned=0
  while IFS= read -r -d '' m; do
    [[ -n "$m" ]] || continue
    manifests+=("$m")
  done < <(find0_plugin_roots -type f -path '*/hooks/hooks.json')
  scanned="${#manifests[@]}"
  if [[ "${#plugin_roots[@]}" -eq 0 ]]; then
    row plugin-hooks-json absent standing 0 - - "no plugin root in this repository"
    return
  fi
  if [[ "$have_jq" -eq 0 ]]; then
    row plugin-hooks-json skipped standing "$scanned" - - "$scanned hooks.json, jq unavailable"
    return
  fi
  for m in "${manifests[@]}"; do
    status="$(json_status "$m")"
    if [[ "$status" != "present" ]]; then
      note "plugin hooks manifest $m is $status; its handlers are missing from the plugin-hooks-json row, which is therefore a floor rather than a total."
      continue
    fi
    local e h
    if ! e="$(jq_num "$PLUGIN_EVENTS_JQ" "$m")" || ! h="$(jq_num "$PLUGIN_HANDLERS_JQ" "$m")"; then
      note "plugin hooks manifest $m parses as JSON, but its hooks block is the wrong shape to read; its handlers are missing from the plugin-hooks-json row, which is therefore a floor rather than a total."
      continue
    fi
    total_events=$((total_events + e))
    total_handlers=$((total_handlers + h))
    [[ "$e" -gt 0 ]] && declaring=$((declaring + 1))
  done
  row plugin-hooks-json present standing "$scanned" "$declaring" "$total_handlers" \
    "${#plugin_roots[@]} plugin roots, $total_events event slots"
}

frontmatter_row() {
  local label="$1" listfile="$2" source_label="$3" scope_status="$4" scanned declaring
  scanned="$(count0 <"$listfile")"
  if [[ "$scanned" -eq 0 ]]; then
    case "$scope_status" in
    present | absent) row "$label" absent conditional 0 - - "$source_label" ;;
    *) row "$label" "$scope_status" conditional - - - "$source_label" ;;
    esac
    return
  fi
  declaring="$(count_frontmatter_hooks "$listfile")"
  row "$label" present conditional "$scanned" "$declaring" - "$source_label"
}

tmpdir="$(mktemp -d 2>/dev/null)"
if [[ -z "$tmpdir" || ! -d "$tmpdir" ]]; then
  echo "inventory.sh: could not create a work directory; no counts were produced." >&2
  exit 2
fi
trap 'rm -rf "$tmpdir"' EXIT

skills_dir_status="$(dir_status .claude/skills)"
agents_dir_status="$(dir_status .claude/agents)"
hooks_dir_status="$(dir_status .claude/hooks)"
for scope_pair in "skills:$skills_dir_status" "agents:$agents_dir_status" "hooks:$hooks_dir_status"; do
  case "${scope_pair#*:}" in
  present | absent) ;;
  *) note ".claude/${scope_pair%%:*} exists but could not be traversed (${scope_pair#*:}); whatever it holds is missing from the counts below, which are floors rather than totals for that scope." ;;
  esac
done

skill_list="$tmpdir/skills"
agent_list="$tmpdir/agents"
: >"$skill_list"
: >"$agent_list"
find0_plugin_roots -type f -name 'SKILL.md' >>"$skill_list"
find0_plugin_roots -type f -path '*/agents/*.md' >>"$agent_list"
plugin_skills="$(count0 <"$skill_list")"
plugin_agents="$(count0 <"$agent_list")"
[[ "$skills_dir_status" == "present" ]] &&
  find0 .claude/skills -- -type f -name 'SKILL.md' >>"$skill_list"
[[ "$agents_dir_status" == "present" ]] &&
  find0 .claude/agents -- -type f -name '*.md' >>"$agent_list"

skills_read="$(count0 <"$skill_list")"
agents_read="$(count0 <"$agent_list")"
skills_total="$(add_counts "$plugin_skills" \
  "$(scope_count "$skills_dir_status" "$((skills_read - plugin_skills))")")"
agents_total="$(add_counts "$plugin_agents" \
  "$(scope_count "$agents_dir_status" "$((agents_read - plugin_agents))")")"

printf 'Claude Code automation inventory for %s\n' "$project_root"
printf '\nHook locations (7 documented; entries MERGE across settings levels)\n'
row LOCATION STATUS KIND PROBED DECLARING HANDLERS SOURCE
settings_row user-settings "$user_settings"
settings_row project-settings "$project_settings"
settings_row local-settings "$local_settings"
if [[ "$have_managed_lib" -eq 1 ]]; then
  managed_policy_row "$managed_file" "$managed_dropin" "$(dir_status "$managed_dropin")"
else
  row managed-policy not-probed standing - - - "managed-scope library unavailable"
  note "Managed policy was not probed: $managed_lib could not be read, so no per-OS path was available. This is not evidence that no policy is deployed."
fi
plugin_hook_row
frontmatter_row skill-frontmatter "$skill_list" "$skills_total SKILL.md" "$skills_dir_status"
frontmatter_row subagent-frontmatter "$agent_list" "$agents_total agent definitions" "$agents_dir_status"


hook_scripts="$(count_in_plugin_roots -type f -path '*/hooks/*' ! -name '*.json' ! -name '*.test.sh')"
project_hook_scripts="$(count_dir "$hooks_dir_status" .claude/hooks -type f ! -name '*.json' ! -name '*.test.sh')"
hook_tests="$(add_counts \
  "$(count_in_plugin_roots -type f -path '*/hooks/*' -name '*.test.sh')" \
  "$(count_dir "$hooks_dir_status" .claude/hooks -type f -name '*.test.sh')")"
mcp_candidates() {
  [[ -e .mcp.json || -L .mcp.json ]] && printf '%s\0' .mcp.json
  find0_plugin_roots -maxdepth 1 -type f -name '.mcp.json'
}

mcp_servers=0
mcp_files=0
mcp_floor=""
if [[ "$have_jq" -eq 1 ]]; then
  while IFS= read -r -d '' f; do
    [[ -n "$f" ]] || continue
    mcp_files=$((mcp_files + 1))
    f_status="$(json_status "$f")"
    if [[ "$f_status" != "present" ]]; then
      [[ -n "$mcp_floor" ]] || mcp_floor="$f_status"
      note "$f is $f_status, so the MCP servers it configures could not be counted; the mcp server figure is a floor."
      continue
    fi
    if [[ "$(jq_type '(.mcpServers // {})' "$f")" != "object" ]]; then
      [[ -n "$mcp_floor" ]] || mcp_floor=invalid-json
      note "$f is valid JSON, but its mcpServers key is not an object, so its servers could not be counted; the mcp server figure is a floor."
      continue
    fi
    if ! n="$(jq_num '(.mcpServers // {}) | length' "$f")"; then
      [[ -n "$mcp_floor" ]] || mcp_floor=unreadable
      note "$f parses as JSON, but its mcpServers count could not be read; the mcp server figure is a floor."
      continue
    fi
    mcp_servers=$((mcp_servers + n))
  done < <(mcp_candidates)
  [[ -n "$mcp_floor" ]] && mcp_servers="$(add_counts "$mcp_servers" "$mcp_floor")"
else
  mcp_files="$(mcp_candidates | count0)"
  mcp_servers=skipped
  note "MCP server counts were skipped: jq is not on PATH. The count below is not a measurement. The .mcp.json files beside it were found and tallied, but nothing was read from them."
fi

printf '\nComponents in this repository\n'
printf '  plugin roots         %s\n' "${#plugin_roots[@]}"
printf '  skills               %s SKILL.md\n' "$skills_total"
printf '  subagents            %s definitions\n' "$agents_total"
printf '  mcp servers          %s across %s .mcp.json file(s)\n' "$mcp_servers" "$mcp_files"
printf '  hook scripts on disk %s in plugin hooks/ dirs, %s in .claude/hooks (+%s test scripts)\n' \
  "$hook_scripts" "$project_hook_scripts" "$hook_tests"


ENABLED_ON_JQ='[(.enabledPlugins // {}) | to_entries[] | select(.value == true)] | length'
ENABLED_OFF_JQ='[(.enabledPlugins // {}) | to_entries[] | select(.value == false)] | length'

enablement_row() {
  local label="$1" file="$2" status on off ep_type
  status="$(json_status "$file")"
  if [[ "$status" != "present" ]]; then
    printf '  %-10s %-12s %s\n' "$label" "$status" "$file"
    return
  fi
  ep_type="$(jq_type '(.enabledPlugins // {})' "$file")"
  if [[ "$ep_type" != "object" ]]; then
    printf '  %-10s %-12s %s\n' "$label" invalid-json \
      "$file (enabledPlugins holds ${ep_type:-a value jq could not type}, not an object)"
    return
  fi
  if ! on="$(jq_num "$ENABLED_ON_JQ" "$file")" || ! off="$(jq_num "$ENABLED_OFF_JQ" "$file")"; then
    printf '  %-10s %-12s %s\n' "$label" unreadable "$file"
    return
  fi
  printf '  %-10s %-12s %s true, %s false\n' "$label" "$status" "$on" "$off"
}

printf '\nPlugin enablement inputs (enabledPlugins follows PRECEDENCE, not merge)\n'
enablement_row user "$user_settings"
enablement_row project "$project_settings"
enablement_row local "$local_settings"
if [[ "$have_managed_lib" -eq 1 ]]; then
  enablement_row managed "$managed_file"
else
  printf '  %-10s %-12s %s\n' managed not-probed "managed-scope library unavailable"
fi
if [[ -f .claude-plugin/marketplace.json && "$have_jq" -eq 1 ]]; then
  if [[ "$(jq_type '(.plugins // [])' .claude-plugin/marketplace.json)" != "array" ]]; then
    printf '  %-10s %-12s %s\n' catalog invalid-json \
      ".claude-plugin/marketplace.json (plugins is not an array)"
  elif cat_total="$(jq_num '(.plugins // []) | length' .claude-plugin/marketplace.json)" &&
    cat_off="$(jq_num '[(.plugins // [])[] | select(.defaultEnabled == false)] | length' .claude-plugin/marketplace.json)"; then
    printf '  %-10s %-12s %s entries, %s with defaultEnabled false\n' catalog present "$cat_total" "$cat_off"
  else
    printf '  %-10s %-12s %s\n' catalog invalid-json .claude-plugin/marketplace.json
  fi
fi
printf '  No effective enablement is computed here. Run /harness-ops:plugins-audit for the verdict.\n'


note "A hook script on disk is not a wired hook: the Components counts are files present, and only the HANDLERS column counts entries a settings file or manifest actually registers."
note "skill-frontmatter and subagent-frontmatter rows are conditional, so they are not part of the standing set: a skill's hooks register only once that skill is invoked, and a subagent's only while that subagent runs. Do not fold them into the always-on set."
note "The frontmatter rows count files that open a hooks: block; the YAML inside those blocks is not parsed, so they carry no HANDLERS figure."
note "plugin-hooks-json covers plugin roots inside this repository. Plugins installed on this machine from elsewhere also contribute hooks; run /harness-ops:inventory for the machine-scope picture."
note "Every walk prunes .git and node_modules, so .git/hooks sample scripts and vendored trees are outside these counts."
if [[ "${CLAUDE_CODE_REMOTE:-}" == "true" ]]; then
  note "CLAUDE_CODE_REMOTE=true: this is a cloud session, which does not read your own machine's ~/.claude/settings.json or .claude/settings.local.json, and reaches only server-managed settings. The user-settings row above is this container's file, so the effective set here differs from a desktop session's. Which scopes a cloud session reads: https://code.claude.com/docs/en/settings#settings-in-cloud-sessions"
else
  note "A cloud session reads a different scope set than this one: it does not read local user settings or .claude/settings.local.json, and only server-managed settings reach it. An effective set measured here is not the effective set there. Which scopes a cloud session reads: https://code.claude.com/docs/en/settings#settings-in-cloud-sessions"
fi
note "Server-managed settings have a local cache under the Claude config directory (\$CLAUDE_CONFIG_DIR, else ~/.claude). The cache is not the live policy; this inventory does not fold it in. Cache path: https://code.claude.com/docs/en/server-managed-settings#invalid-entries-in-delivered-settings; when it applies: https://code.claude.com/docs/en/server-managed-settings#fetch-and-caching-behavior; where a failed fetch shows: https://code.claude.com/docs/en/server-managed-settings#verify-settings-delivery"

printf '\nNotes\n'
for n in "${notes[@]}"; do
  printf '  - %s\n' "$n"
done

exit 0
