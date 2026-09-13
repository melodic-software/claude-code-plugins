#!/usr/bin/env bash
# Automation landscape counts for the audit-automation-gaps skill.
#
# The skill injects this script's stdout as pre-computed context, so the output is
# a COUNT TABLE and never a row dump. An all-scope enumerator that emitted one
# line per hook would spend more of the window than the audit it feeds.
#
# WHAT CHANGED AND WHY. The previous revision read only
# .claude/hooks, .claude/skills and .claude/agents, so on a repository carrying
# 77 plugins, 271 SKILL.md files and 137 hook files it reported 3 hook scripts, 0
# skills, 0 agents and 1 plugin. Every number was a zero produced by not looking,
# and a zero produced by not looking reads exactly like a real absence. The skill
# body's own Phase 1.1 already instructs the model to read user, project and local
# settings, managed policy, every enabled plugin's hooks/hooks.json, and skill and
# subagent frontmatter; the script was behind its own skill's spec.
#
# THE SAME ZERO, THROUGH FIVE OTHER DOORS. A review of that rewrite found it
# reproducing the defect it existed to remove, so every walk and every count in
# this file now goes through one of four helpers, and none of them can answer 0
# for a scope it did not actually read:
#   find0        the only tree walk. Passes -H so a SYMLINKED .claude/skills,
#                .claude/agents or .claude/hooks is descended instead of silently
#                yielding nothing; prunes .git and node_modules so .git/hooks/*
#                sample scripts cannot be counted as a plugin's hook scripts; and
#                emits NUL-delimited paths so a newline inside a path cannot split
#                one file into two.
#   dir_status   classifies a directory scope before it is walked. A path that
#                exists but cannot be traversed, a dangling symlink included, is
#                unreadable, never absent and never 0. All four directory scopes
#                go through it, .claude/skills, .claude/agents, .claude/hooks and
#                managed-settings.d, and each carries the status word the whole
#                way out through count_dir or scope_count. Wiring one scope and
#                not its siblings is how this class survived the first pass.
#   jq_num       FAILS instead of printing 0 when jq fails. A hooks or
#                enabledPlugins key holding a string, a number or an array is
#                reported invalid-json, because the wrong type is not "no hooks".
#   count0       counts a NUL stream rather than lines.
# An unusable project root is likewise fatal: printing another directory's counts
# under the requested root's name was the worst shape of all, since the header
# named a directory the numbers did not come from.
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

It takes no other argument. An unrecognised argument is a usage error rather
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
  INVENTORY_PROJECT_DIR    project root, instead of the git toplevel
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
  printf 'inventory.sh: unrecognised argument: %s\n' "$1" >&2
  usage >&2
  exit 2
}

case "$#" in
0) ;;
1)
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  *) usage_error "$1" ;;
  esac
  ;;
*)
  case "$1" in
  -h | --help) usage_error "$2" ;;
  *) usage_error "$1" ;;
  esac
  ;;
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

# A cd that fails is FATAL. The header prints the requested root, so a run that
# stayed in the invoking directory would attribute that directory's plugins,
# skills and handlers to a root they have nothing to do with. The `--` lets a
# relative root beginning with a dash be entered rather than parsed as an option.
if [[ ! -d "$project_root" ]] || ! cd -- "$project_root" 2>/dev/null; then
  printf 'inventory.sh: project root %s is not a directory this run could enter; no counts were produced.\n' \
    "$project_root" >&2
  exit 2
fi
project_root="$PWD"

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

# Classify one directory scope before anything walks it. A symlink to a
# directory IS a directory here and is walked; a dangling symlink, a plain file
# in a directory's place, or a directory this uid cannot open is unreadable, so
# the count next to it is a status word instead of the 0 that would read as a
# real absence.
dir_status() {
  local d="$1"
  [[ -n "$d" ]] || {
    printf 'not-probed'
    return
  }
  if [[ -d "$d" ]]; then
    if [[ -r "$d" && -x "$d" ]]; then
      printf 'present'
    else
      printf 'unreadable'
    fi
    return
  fi
  if [[ -e "$d" || -L "$d" ]]; then
    printf 'unreadable'
    return
  fi
  printf 'absent'
}

# The only tree walk in this script. Start points come first, then a literal --,
# then the find expression.
#
#   -H            follows a symlinked START POINT, so a .claude/skills that is a
#                 symlink to the real tree is descended. Without it find refuses
#                 to descend the start point and reports nothing, which is the
#                 "0 produced by not looking" this file exists to prevent. Only
#                 the start point is followed, so a symlink loop inside the tree
#                 still cannot trap the walk.
#   prune         .git carries a hooks/ directory whose *.sample files are not
#                 anybody's hook scripts, and a vendored node_modules tree can
#                 carry any layout at all. Both are pruned from every walk.
#   -print0       a path may contain a newline. Line-delimited output would turn
#                 one such file into two records and lose the real one.
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

# Counts a NUL-delimited stream on stdin. wc -l would count newlines, which are
# legal inside a path and would therefore over-count.
count0() { tr -cd '\000' | wc -c | tr -d ' '; }

# A settings file names its hook block under the `hooks` key; a plugin manifest
# may wrap the same block or carry the events at its top level, so the two get
# their own programs rather than one guessing filter over both.
SETTINGS_EVENTS_JQ='[(.hooks // {}) | to_entries[] | select((.value | type) == "array" and (.value | length) > 0) | .key] | length'
SETTINGS_HANDLERS_JQ='[(.hooks // {}) | to_entries[] | .value[]? | (.hooks // []) | length] | add // 0'
PLUGIN_EVENTS_JQ='def hk: if has("hooks") then .hooks else . end; [hk | to_entries[] | select((.value | type) == "array" and (.value | length) > 0) | .key] | length'
PLUGIN_HANDLERS_JQ='def hk: if has("hooks") then .hooks else . end; [hk | to_entries[] | .value[]? | (.hooks // []) | length] | add // 0'

# Runs one jq program over one file and prints its number. A jq that could not
# run, or a program whose result is not a plain non-negative integer, prints
# NOTHING and returns 1. Printing 0 there was the defect: a hooks key holding a
# string, a number, a boolean or an array made every query fail or return
# nothing, and the row then said "present, no hooks" about a file whose hook
# block is malformed.
jq_num() {
  local program="$1" file="$2" out
  out="$("$jq_bin" -r "$program" "$file" 2>/dev/null)" || return 1
  case "$out" in
  '' | *[!0-9]*) return 1 ;;
  *) printf '%s' "$out" ;;
  esac
}

# The jq type of one expression, or the empty string when jq could not run. An
# array answers most of the count programs without erroring, so the type has to
# be asked directly rather than inferred from a query that happened to succeed.
jq_type() { "$jq_bin" -r "$1 | type" "$2" 2>/dev/null; }

# Discovered plugin roots. `.claude-plugin/plugin.json` is the documented marker,
# and the depth bound keeps the walk off vendored trees.
plugin_roots=()
while IFS= read -r -d '' manifest; do
  [[ -n "$manifest" ]] || continue
  plugin_roots+=("${manifest%/.claude-plugin/plugin.json}")
done < <(find -H . -maxdepth 4 \( -name .git -o -name node_modules \) -prune -o \
  -type f -path '*/.claude-plugin/plugin.json' -print0 2>/dev/null)

# Walks every discovered plugin root, or emits nothing when this repository ships
# no plugins.
find0_plugin_roots() {
  [[ "${#plugin_roots[@]}" -gt 0 ]] || return 0
  find0 "${plugin_roots[@]}" -- "$@"
}

count_in_plugin_roots() {
  [[ "${#plugin_roots[@]}" -gt 0 ]] || {
    printf '0'
    return
  }
  find0_plugin_roots "$@" | count0
}

# Counts files under one directory scope whose status was classified first. Only
# a scope that was actually walked gets a number; anything else gets its status
# word, so a count in this output is always a measurement.
count_dir() {
  local status="$1" dir="$2"
  shift 2
  case "$status" in
  present) find0 "$dir" -- "$@" | count0 ;;
  absent) printf '0' ;;
  *) printf '%s' "$status" ;;
  esac
}

# Adds two figures either of which may be a status word rather than a number.
# A status word on either side makes the sum a floor, and it is printed as the
# two parts rather than collapsed into a number that was never measured.
add_counts() {
  case "$1$2" in
  *[!0-9]*) printf '%s+%s' "$1" "$2" ;;
  *) printf '%s' "$(($1 + $2))" ;;
  esac
}

# One scope's contribution to a total: the number of files read from it, or its
# status word when the scope exists and could not be walked. Every scope that
# feeds a Components figure goes through this, so no scope can reach a total as
# a 0 it did not earn. count_dir applies the same rule to a scope it walks
# itself; this one is for a scope whose files were already gathered into a list.
scope_count() {
  case "$1" in
  present | absent) printf '%s' "$2" ;;
  *) printf '%s' "$1" ;;
  esac
}

# Counts files whose YAML frontmatter opens a top-level `hooks:` block. The walk
# is frontmatter-only: a `hooks:` line in a skill body is prose about hooks, not
# a hook registration. awk prints only the tally and never a path, so a newline
# inside a path cannot be mistaken for a record separator on the way out either.
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

# --- Hook locations -----------------------------------------------------------

# Reads one settings-shaped file's hook block into three globals instead of
# printing them. note() appends to an array, and a command substitution would run
# it in a subshell whose appends die with it, so a file that could not be read
# would lose its explanation on the way back to the caller. shc_status is one
# vocabulary word; shc_events and shc_handlers are numbers only when it is
# present, and are zero otherwise so no caller can add a count nothing measured.
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
    return 0
  fi
  return 0
}

settings_row() {
  local label="$1" file="$2" declaring
  settings_hook_counts "$file"
  if [[ "$shc_status" != "present" ]]; then
    row "$label" "$shc_status" standing 1 - - "$file"
    return
  fi
  declaring=0
  [[ "$shc_events" -gt 0 ]] && declaring=1
  row "$label" "$shc_status" standing 1 "$declaring" "$shc_handlers" "$file"
}

# The managed-policy row covers managed-settings.json TOGETHER WITH the readable
# managed-settings.d drop-ins, because those drop-ins merge on top of the base
# file rather than sitting beside it. Counting only the base file published an
# exact-looking handler figure for a policy whose standing hooks may live
# entirely in the drop-ins, which is the same confident wrong number this script
# exists to stop printing. A drop-in that could not be read contributes its
# status word instead of a count, so the figures render in the add_counts floor
# form rather than as a total nobody measured.
#
# Registrations, not the de-duplicated effective set: the merge concatenates and
# de-duplicates arrays, so a handler registered identically in the base file and
# in a drop-in is one entry in force and two here. The drop-in note says so.
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

  # Nothing was read, so there is nothing to count and the row carries the base
  # file's status word exactly as a single-file row would.
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

# scope_status is the project-scope directory that feeds this list alongside the
# plugin roots. An empty list is only an ABSENCE when that scope was actually
# walked; when the scope exists and could not be walked, the row carries its
# status word and no counts at all, because 0 there would be the same claim the
# whole file exists to stop making.
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

# Each list is filled in two passes, plugin roots first and the project scope
# second, so the two contributions stay separable. The project scope's share is
# then rendered through scope_count, which substitutes its status word when the
# scope could not be walked. A list is therefore always what was READ, and the
# total beside it always says when it is only a floor.
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
  note "Managed policy was NOT probed: $managed_lib could not be read, so no per-OS path was available. This is not evidence that no policy is deployed."
fi
plugin_hook_row
frontmatter_row skill-frontmatter "$skill_list" "$skills_total SKILL.md" "$skills_dir_status"
frontmatter_row subagent-frontmatter "$agent_list" "$agents_total agent definitions" "$agents_dir_status"

# --- Components ---------------------------------------------------------------

hook_scripts="$(count_in_plugin_roots -type f -path '*/hooks/*' ! -name '*.json' ! -name '*.test.sh')"
project_hook_scripts="$(count_dir "$hooks_dir_status" .claude/hooks -type f ! -name '*.json' ! -name '*.test.sh')"
hook_tests="$(add_counts \
  "$(count_in_plugin_roots -type f -path '*/hooks/*' -name '*.test.sh')" \
  "$(count_dir "$hooks_dir_status" .claude/hooks -type f -name '*.test.sh')")"
# Every .mcp.json this run will look at. The project-root file is emitted
# whenever anything is THERE, a directory or a dangling symlink included, so
# json_status gets to call it unreadable: the -f test that used to gate it
# dropped such a file before any status could be assigned, and the row then
# reported the absence of a configuration that exists.
mcp_candidates() {
  [[ -e .mcp.json || -L .mcp.json ]] && printf '%s\0' .mcp.json
  find0_plugin_roots -maxdepth 1 -type f -name '.mcp.json'
}

# mcp_files counts the .mcp.json files this run EXAMINED, readable or not, and
# mcp_floor carries the status word of the first one it could not measure. A
# file that exists and could not be parsed therefore leaves the server figure in
# the add_counts floor form rather than at a numeric 0: "0 across 0 .mcp.json
# file(s)" for a repository that ships an MCP configuration was the same
# confident wrong number the directory scopes already stopped printing.
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

# --- Enablement inputs --------------------------------------------------------

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
  # `length` answers on a string as well as on an array, so a plugins key of the
  # wrong type would otherwise publish a character count as an entry count.
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
printf '  No effective enablement is computed here. Run /claude-ops:plugins audit for the verdict.\n'

# --- Notes --------------------------------------------------------------------

note "A hook script on disk is not a wired hook: the Components counts are files present, and only the HANDLERS column counts entries a settings file or manifest actually registers."
note "skill-frontmatter and subagent-frontmatter rows are conditional, so they are not part of the standing set: a skill's hooks register only once that skill is invoked, and a subagent's only while that subagent runs. Do not fold them into the always-on set."
note "The frontmatter rows count files that open a hooks: block; the YAML inside those blocks is not parsed, so they carry no HANDLERS figure."
note "plugin-hooks-json covers plugin roots inside this repository. Plugins installed on this machine from elsewhere also contribute hooks; run /claude-ops:inventory for the machine-scope picture."
note "Every walk prunes .git and node_modules, so .git/hooks sample scripts and vendored trees are outside these counts."
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
