#!/usr/bin/env bash
# Automation landscape counts for the audit-automation-gaps skill.
#
# The skill injects this script's stdout as pre-computed context, so the output is
# a COUNT TABLE and never a row dump. An all-scope enumerator that emitted one
# line per hook would spend more of the window than the audit it feeds.
#
# WHAT CHANGED AND WHY (issue #4146). The previous revision read only
# .claude/hooks, .claude/skills and .claude/agents, so on a repository carrying
# 77 plugins, 271 SKILL.md files and 137 hook files it reported 3 hook scripts, 0
# skills, 0 agents and 1 plugin. Every number was a zero produced by not looking,
# and a zero produced by not looking reads exactly like a real absence. The skill
# body's own Phase 1.1 already instructs the model to read user, project and local
# settings, managed policy, every enabled plugin's hooks/hooks.json, and skill and
# subagent frontmatter; the script was behind its own skill's spec.
#
# TWO MECHANICS THIS OUTPUT KEEPS APART. Hook entries MERGE across settings
# levels: user, project, local and managed each contribute, and none replaces
# another, so a per-scope additive count table is the honest shape for them.
# enabledPlugins is a PRECEDENCE key, not a merged one, and this script therefore
# reports the maps as read and computes no effective set. That is the same posture
# claude-ops:inventory and claude-ops:audit-native-overlap already take, and the
# Enablement section names where the verdict lives.
#
# STATUS, NEVER A SILENT ZERO. A location that could not be read reports
# unreadable, invalid-json, skipped or not-probed. A count is printed only for a
# location that was actually read.
#
# VOCABULARY is claude-ops:inventory's, not a second dialect for the same ideas:
#   present / absent / unreadable / invalid-json / skipped / not-probed
#   standing     registered for the whole session, part of the always-on set
#   conditional  registered only when a skill is invoked, or only while a
#                subagent runs, so it is not part of the standing set
#   A hook script on disk is not a wired hook. Script counts live in Components,
#   apart from the wired handler counts, and are never added to them.
#
# Claim: hooks are configured in exactly seven locations, user settings, project
#   settings, project local settings, managed policy, a plugin's
#   hooks/hooks.json, skill frontmatter and subagent frontmatter; hook entries
#   merge across settings levels rather than replacing each other; skill hooks
#   last for the rest of the session once the skill is invoked and subagent hooks
#   only while that subagent runs.
# Basis: https://code.claude.com/docs/en/hooks, the "Hook locations" table.
# As of: 2026-09-13.
# Recheck trigger: that table gains, drops or renames a row, or the sentence
#   stating that hook entries merge across settings levels changes.
#
# Claim: managed policy has a documented per-OS location, so this script probes it
#   instead of reporting it not-probed.
# Basis: the paths are owned by ../../../lib/managed-scope.sh, which carries its
#   own stamp against https://code.claude.com/docs/en/managed-settings; that page
#   was re-read for this script and still lists
#   /Library/Application Support/ClaudeCode/, /etc/claude-code/ and
#   C:\Program Files\ClaudeCode\ plus an optional managed-settings.d directory.
# As of: 2026-09-13.
# Recheck trigger: managed-scope.sh's own recheck trigger fires, or this script
#   starts reporting managed policy not-probed on a machine that has a policy.
set -u

usage() {
  cat <<'EOF'
inventory.sh - per-scope automation counts for the audit-automation-gaps skill.

Usage:
  inventory.sh [--help]

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
or not-probed. It never reports that location as 0.

Test seams, unset in normal use:
  INVENTORY_PROJECT_DIR    project root, instead of the git toplevel
  INVENTORY_USER_SETTINGS  user settings file, instead of the documented path
  INVENTORY_MANAGED_PATH   managed-settings.json, instead of the per-OS path
  INVENTORY_JQ             the jq command name, so a test can take jq away

Exit: always 0. The output is a skill's pre-computed context, so a nonzero exit
would cost the audit its inventory rather than tell it anything.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
*) ;;
esac

jq_bin="${INVENTORY_JQ:-jq}"
have_jq=0
command -v "$jq_bin" >/dev/null 2>&1 && have_jq=1

# Plugin root resolution mirrors permission-state.sh: parameter expansion plus
# builtins, so a missing external tool cannot silently turn managed policy into
# an absence. A reader that reports no policy because it could not load its own
# library is the exact failure this rewrite exists to remove.
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)}"
managed_lib="$plugin_root/lib/managed-scope.sh"
have_managed_lib=0
if [[ -r "$managed_lib" ]]; then
  # shellcheck source=../../../lib/managed-scope.sh
  source "$managed_lib" && have_managed_lib=1
fi

if [[ -n "${INVENTORY_PROJECT_DIR:-}" ]]; then
  project_root="$INVENTORY_PROJECT_DIR"
else
  project_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  [[ -n "$project_root" ]] || project_root="${CLAUDE_PROJECT_DIR:-$PWD}"
fi
cd "$project_root" 2>/dev/null || true

user_settings="${INVENTORY_USER_SETTINGS:-${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/settings.json}"
project_settings=".claude/settings.json"
local_settings=".claude/settings.local.json"

managed_file=""
managed_dropin=""
if [[ "$have_managed_lib" -eq 1 ]]; then
  managed_file="$(mscope::base_file "${INVENTORY_MANAGED_PATH:-}")"
  managed_dropin="$(mscope::dropin_dir "${INVENTORY_MANAGED_PATH:-}")"
fi

notes=()
note() { notes+=("$1"); }

# Classify one JSON surface. A path that exists but is not a regular file, or is
# not readable, is unreadable rather than absent: the caller must be able to tell
# "there is no policy here" from "I could not look".
json_status() {
  local f="$1"
  [[ -n "$f" ]] || {
    printf 'not-probed'
    return
  }
  [[ -e "$f" ]] || {
    printf 'absent'
    return
  }
  if [[ ! -f "$f" || ! -r "$f" ]]; then
    printf 'unreadable'
    return
  fi
  if [[ "$have_jq" -eq 0 ]]; then
    printf 'skipped'
    return
  fi
  if ! "$jq_bin" -e 'type == "object"' "$f" >/dev/null 2>&1; then
    printf 'invalid-json'
    return
  fi
  printf 'present'
}

# A settings file names its hook block under the `hooks` key; a plugin manifest
# may wrap the same block or carry the events at its top level, so the two get
# their own programs rather than one guessing filter over both.
SETTINGS_EVENTS_JQ='[(.hooks // {}) | to_entries[] | select((.value | type) == "array" and (.value | length) > 0) | .key] | length'
SETTINGS_HANDLERS_JQ='[(.hooks // {}) | to_entries[] | .value[]? | (.hooks // []) | length] | add // 0'
PLUGIN_EVENTS_JQ='def hk: if has("hooks") then .hooks else . end; [hk | to_entries[] | select((.value | type) == "array" and (.value | length) > 0) | .key] | length'
PLUGIN_HANDLERS_JQ='def hk: if has("hooks") then .hooks else . end; [hk | to_entries[] | .value[]? | (.hooks // []) | length] | add // 0'

jq_num() {
  local program="$1" file="$2" out
  out="$("$jq_bin" -r "$program" "$file" 2>/dev/null)"
  case "$out" in
  '' | *[!0-9]*) printf '0' ;;
  *) printf '%s' "$out" ;;
  esac
}

# Discovered plugin roots. `.claude-plugin/plugin.json` is the documented marker,
# and the depth bound keeps the walk off vendored trees.
plugin_roots=()
while IFS= read -r manifest; do
  [[ -n "$manifest" ]] || continue
  plugin_roots+=("${manifest%/.claude-plugin/plugin.json}")
done < <(find . -maxdepth 4 -type f -path '*/.claude-plugin/plugin.json' 2>/dev/null | sort)

# Counts files matching the trailing find expression under every discovered
# plugin root, or 0 when this repository ships no plugins.
count_in_plugin_roots() {
  [[ "${#plugin_roots[@]}" -gt 0 ]] || {
    printf '0'
    return
  }
  find "${plugin_roots[@]}" "$@" 2>/dev/null | wc -l | tr -d ' '
}

count_path() {
  local dir="$1"
  shift
  [[ -d "$dir" ]] || {
    printf '0'
    return
  }
  find "$dir" "$@" 2>/dev/null | wc -l | tr -d ' '
}

# Files whose YAML frontmatter opens a top-level `hooks:` block, one path per
# matching file. The walk is frontmatter-only: a `hooks:` line in a skill body is
# prose about hooks, not a hook registration.
frontmatter_hook_files() {
  [[ "$#" -gt 0 ]] || return 0
  awk '
    FNR == 1 { in_fm = 0; opened = 0; seen = 0 }
    FNR == 1 && $0 ~ /^---[[:space:]]*$/ { in_fm = 1; opened = 1; next }
    opened && in_fm && $0 ~ /^---[[:space:]]*$/ { in_fm = 0; next }
    opened && in_fm && seen == 0 && $0 ~ /^hooks:[[:space:]]*$/ { print FILENAME; seen = 1 }
  ' "$@" 2>/dev/null
}

count_frontmatter_hooks() {
  local list="$1" f
  local files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    files+=("$f")
  done <"$list"
  [[ "${#files[@]}" -gt 0 ]] || {
    printf '0'
    return
  }
  frontmatter_hook_files "${files[@]}" | wc -l | tr -d ' '
}

row() {
  printf '  %-20s %-12s %-11s %7s %9s %8s  %s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

# --- Hook locations -----------------------------------------------------------

settings_row() {
  local label="$1" file="$2" status events handlers declaring
  status="$(json_status "$file")"
  if [[ "$status" == "present" ]]; then
    events="$(jq_num "$SETTINGS_EVENTS_JQ" "$file")"
    handlers="$(jq_num "$SETTINGS_HANDLERS_JQ" "$file")"
    declaring=0
    [[ "$events" -gt 0 ]] && declaring=1
    row "$label" "$status" standing 1 "$declaring" "$handlers" "$file"
  else
    row "$label" "$status" standing 1 - - "$file"
  fi
}

plugin_hook_row() {
  local manifests=() m status total_events=0 total_handlers=0 declaring=0 scanned=0
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    manifests+=("$m")
  done < <(
    if [[ "${#plugin_roots[@]}" -gt 0 ]]; then
      find "${plugin_roots[@]}" -type f -path '*/hooks/hooks.json' 2>/dev/null | sort
    fi
  )
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
    e="$(jq_num "$PLUGIN_EVENTS_JQ" "$m")"
    h="$(jq_num "$PLUGIN_HANDLERS_JQ" "$m")"
    total_events=$((total_events + e))
    total_handlers=$((total_handlers + h))
    [[ "$e" -gt 0 ]] && declaring=$((declaring + 1))
  done
  row plugin-hooks-json present standing "$scanned" "$declaring" "$total_handlers" \
    "${#plugin_roots[@]} plugin roots, $total_events event slots"
}

frontmatter_row() {
  local label="$1" listfile="$2" source_label="$3" scanned declaring
  scanned="$(wc -l <"$listfile" | tr -d ' ')"
  if [[ "$scanned" -eq 0 ]]; then
    row "$label" absent conditional 0 - - "$source_label"
    return
  fi
  declaring="$(count_frontmatter_hooks "$listfile")"
  row "$label" present conditional "$scanned" "$declaring" - "$source_label"
}

tmpdir="$(mktemp -d 2>/dev/null)"
if [[ -z "$tmpdir" || ! -d "$tmpdir" ]]; then
  echo "inventory.sh: could not create a work directory; no counts were produced." >&2
  exit 0
fi
trap 'rm -rf "$tmpdir"' EXIT

skill_list="$tmpdir/skills"
agent_list="$tmpdir/agents"
: >"$skill_list"
: >"$agent_list"
if [[ "${#plugin_roots[@]}" -gt 0 ]]; then
  find "${plugin_roots[@]}" -type f -name 'SKILL.md' 2>/dev/null >>"$skill_list"
  find "${plugin_roots[@]}" -type f -path '*/agents/*.md' 2>/dev/null >>"$agent_list"
fi
[[ -d .claude/skills ]] && find .claude/skills -type f -name 'SKILL.md' 2>/dev/null >>"$skill_list"
[[ -d .claude/agents ]] && find .claude/agents -type f -name '*.md' 2>/dev/null >>"$agent_list"

skills_total="$(wc -l <"$skill_list" | tr -d ' ')"
agents_total="$(wc -l <"$agent_list" | tr -d ' ')"

printf 'Claude Code automation inventory for %s\n' "$project_root"
printf '\nHook locations (7 documented; entries MERGE across settings levels)\n'
row LOCATION STATUS KIND PROBED DECLARING HANDLERS SOURCE
settings_row user-settings "$user_settings"
settings_row project-settings "$project_settings"
settings_row local-settings "$local_settings"
if [[ "$have_managed_lib" -eq 1 ]]; then
  settings_row managed-policy "$managed_file"
  if [[ -d "$managed_dropin" ]]; then
    dropin_n="$(count_path "$managed_dropin" -maxdepth 1 -type f -name '*.json')"
    note "managed-settings.d exists at $managed_dropin with $dropin_n drop-in file(s); they merge on top of managed-settings.json and are not counted in the managed-policy row."
  fi
else
  row managed-policy not-probed standing - - - "managed-scope library unavailable"
  note "Managed policy was NOT probed: $managed_lib could not be read, so no per-OS path was available. This is not evidence that no policy is deployed."
fi
plugin_hook_row
frontmatter_row skill-frontmatter "$skill_list" "$skills_total SKILL.md"
frontmatter_row subagent-frontmatter "$agent_list" "$agents_total agent definitions"

# --- Components ---------------------------------------------------------------

hook_scripts="$(count_in_plugin_roots -type f -path '*/hooks/*' ! -name '*.json' ! -name '*.test.sh')"
project_hook_scripts="$(count_path .claude/hooks -type f ! -name '*.json' ! -name '*.test.sh')"
hook_tests=$(($(count_in_plugin_roots -type f -path '*/hooks/*' -name '*.test.sh') + $(count_path .claude/hooks -type f -name '*.test.sh')))
mcp_servers=0
mcp_files=0
if [[ "$have_jq" -eq 1 ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ "$(json_status "$f")" == "present" ]] || continue
    mcp_files=$((mcp_files + 1))
    mcp_servers=$((mcp_servers + $(jq_num '(.mcpServers // {}) | length' "$f")))
  done < <(
    [[ -f .mcp.json ]] && printf '%s\n' .mcp.json
    if [[ "${#plugin_roots[@]}" -gt 0 ]]; then
      find "${plugin_roots[@]}" -maxdepth 1 -type f -name '.mcp.json' 2>/dev/null | sort
    fi
  )
else
  note "MCP server counts were skipped: jq is not on PATH. The count below is not a measurement."
fi

printf '\nComponents in this repository\n'
printf '  plugin roots         %s\n' "${#plugin_roots[@]}"
printf '  skills               %s SKILL.md\n' "$skills_total"
printf '  subagents            %s definitions\n' "$agents_total"
printf '  mcp servers          %s across %s .mcp.json file(s)\n' "$mcp_servers" "$mcp_files"
printf '  hook scripts on disk %s in plugin hooks/ dirs, %s in .claude/hooks (+%s test scripts)\n' \
  "$hook_scripts" "$project_hook_scripts" "$hook_tests"

# --- Enablement inputs --------------------------------------------------------

enablement_row() {
  local label="$1" file="$2" status on off
  status="$(json_status "$file")"
  if [[ "$status" != "present" ]]; then
    printf '  %-10s %-12s %s\n' "$label" "$status" "$file"
    return
  fi
  on="$(jq_num '[(.enabledPlugins // {}) | to_entries[] | select(.value == true)] | length' "$file")"
  off="$(jq_num '[(.enabledPlugins // {}) | to_entries[] | select(.value == false)] | length' "$file")"
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
  cat_total="$(jq_num '(.plugins // []) | length' .claude-plugin/marketplace.json)"
  cat_off="$(jq_num '[(.plugins // [])[] | select(.defaultEnabled == false)] | length' .claude-plugin/marketplace.json)"
  printf '  %-10s %-12s %s entries, %s with defaultEnabled false\n' catalog present "$cat_total" "$cat_off"
fi
printf '  No effective enablement is computed here. Run /claude-ops:plugins audit for the verdict.\n'

# --- Notes --------------------------------------------------------------------

note "A hook script on disk is not a wired hook: the Components counts are files present, and only the HANDLERS column counts entries a settings file or manifest actually registers."
note "skill-frontmatter and subagent-frontmatter rows are conditional, so they are not part of the standing set: a skill's hooks register only once that skill is invoked, and a subagent's only while that subagent runs. Do not fold them into the always-on set."
note "The frontmatter rows count files that open a hooks: block; the YAML inside those blocks is not parsed, so they carry no HANDLERS figure."
note "plugin-hooks-json covers plugin roots inside this repository. Plugins installed on this machine from elsewhere also contribute hooks; run /claude-ops:inventory for the machine-scope picture."
if [[ "${CLAUDE_CODE_REMOTE:-}" == "true" ]]; then
  note "CLAUDE_CODE_REMOTE=true: this is a cloud session, which does not read your own machine's ~/.claude/settings.json or .claude/settings.local.json, and reaches only server-managed settings. The user-settings row above is this container's file, so the effective set here differs from a desktop session's."
else
  note "A cloud session reads a different scope set than this one: it does not read local user settings or .claude/settings.local.json, and only server-managed settings reach it. An effective set measured here is not the effective set there."
fi
note "Server-managed settings, delivered remotely at sign-in, have no local path and are invisible to any local reader, including this one."

printf '\nNotes\n'
for n in "${notes[@]}"; do
  printf '  - %s\n' "$n"
done

exit 0
