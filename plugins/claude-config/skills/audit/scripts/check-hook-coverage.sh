#!/usr/bin/env bash
# Hook inventory for the audit skill (Categories B and D).
#
# WHY THIS EXISTS. Category D writes rules for hooks that use
# ${CLAUDE_PLUGIN_ROOT} / ${CLAUDE_PLUGIN_DATA}, and those placeholders only
# ever appear in a PLUGIN-provided hook. Category B's third baseline narrowing
# demotes a missing deny pattern to `info` when a LIVE PreToolUse hook already
# blocks the family. Both need to know what hooks are installed — and until this
# script, the skill read settings-declared hooks only and three of its own
# surfaces said so in prose. This is the enumeration path those surfaces were
# describing the absence of.
#
# WHAT IT ENUMERATES.
#   1. Settings-declared hooks: project settings.json, project
#      settings.local.json, and the user-scope settings.json.
#   2. Plugin-declared hooks: for every plugin enabled in any of those scopes,
#      the plugin's own hook config, resolved through the installed-plugin
#      registry so no version-directory guessing is involved.
#   3. The suppression levers that can switch hooks off wholesale, because a
#      hook that cannot run is not coverage.
#
# WHERE A PLUGIN'S HOOKS LIVE. plugins-reference (fetched 2026-08-12) says
# "Location: `hooks/hooks.json` in plugin root, or inline in plugin.json", and
# the manifest's `hooks` key is `string|array|object` — a path, several paths,
# or an inline config. All four shapes are read here; a plugin whose shape this
# script cannot parse is reported UNREADABLE, never silently as "no hooks".
#
# WHAT IT DOES NOT DO. It does not decide whether a hook covers a permission
# family. That judgment is the audit's, and required-permissions.md "Narrowing
# the baseline" carries the three preconditions it has to apply. This script
# answers only "what is installed", which is the question that previously had no
# answer at all.
#
# Read-only: opens JSON and prints. Never executes a hook command.
#
# Exit codes:
#   0  inventory COMPLETE — every enabled plugin resolved to a real directory
#   1  inventory PARTIAL  — at least one enabled plugin could not be resolved or
#      read. The audit keeps the conditional-finding posture for the families
#      those plugins might cover. Not an error; a stated limit.
#   2  fatal — jq missing, or no settings scope readable at all
#
# Env overrides (the test seam):
#   HOOK_COVERAGE_FIXTURE_DIR    project root to scan instead of the git toplevel
#   HOOK_COVERAGE_INSTALLED_JSON path to installed_plugins.json
#   HOOK_COVERAGE_USER_DIR       user config dir (else CLAUDE_CONFIG_DIR, else $HOME/.claude)

set -uo pipefail

# Every `jq` result that re-enters the shell goes through this. On Git for
# Windows, jq writes stdout in TEXT mode and appends a CR to every line — a
# property of jq's own output stream, NOT of the input file's line endings, so
# it happens even when every fixture is pure LF. Verified here by deleting the
# `tr` and re-running the suite: 17 of 34 checks failed, including cases whose
# fixtures contain no CR at all. Untreated, a plugin key read out of jq is
# `name@marketplace\r`, every registry lookup misses, and the plugin is reported
# as not installed on a machine where it is installed — a silent false negative
# on exactly the axis this script exists to make trustworthy.
jqs() { jq "$@" 2>/dev/null | tr -d '\r'; }

usage() {
  cat <<'EOF'
check-hook-coverage.sh — enumerate the hooks actually installed for this project.

Reads settings-declared hooks (project, local, user scope) and plugin-declared
hooks (via the installed-plugin registry), plus the levers that suppress hooks
wholesale. Read-only; never runs a hook.

Usage:
  check-hook-coverage.sh [--json] [--help]

  --json   emit the inventory as JSON on stdout instead of a table

Exit: 0 inventory complete; 1 inventory partial (some plugin unresolved);
      2 fatal (jq missing, or no settings scope readable).
EOF
}

EMIT_JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --json)
    EMIT_JSON=1
    shift
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required (install with: winget install jqlang.jq | apt install jq | brew install jq)" >&2
  exit 2
fi

# --- Roots -------------------------------------------------------------------

if [[ -n "${HOOK_COVERAGE_FIXTURE_DIR:-}" ]]; then
  PROJECT_ROOT="$HOOK_COVERAGE_FIXTURE_DIR"
else
  # Consumer project root: the cwd's git toplevel, then Claude Code's exported
  # project dir, then cwd. Never the plugin's own install directory.
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  [[ -n "$PROJECT_ROOT" ]] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
fi

if [[ -n "${HOOK_COVERAGE_USER_DIR:-}" ]]; then
  USER_DIR="$HOOK_COVERAGE_USER_DIR"
elif [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  USER_DIR="$CLAUDE_CONFIG_DIR"
elif [[ -n "${HOME:-}" ]]; then
  USER_DIR="$HOME/.claude"
else
  USER_DIR=""
fi

INSTALLED_JSON="${HOOK_COVERAGE_INSTALLED_JSON:-}"
if [[ -z "$INSTALLED_JSON" && -n "$USER_DIR" ]]; then
  INSTALLED_JSON="$USER_DIR/plugins/installed_plugins.json"
fi

SCOPES=()
SCOPE_LABELS=()
add_scope() {
  # add_scope <path> <label> — register a settings file that exists and parses.
  [[ -f "$1" ]] || return 0
  if ! jq empty "$1" 2>/dev/null; then
    UNREADABLE+=("$2 ($1): not valid JSON")
    PARTIAL=1
    return 0
  fi
  SCOPES+=("$1")
  SCOPE_LABELS+=("$2")
}

PARTIAL=0
UNREADABLE=()

add_scope "$PROJECT_ROOT/.claude/settings.json" "project"
add_scope "$PROJECT_ROOT/.claude/settings.local.json" "local"
[[ -n "$USER_DIR" ]] && add_scope "$USER_DIR/settings.json" "user"

if [[ ${#SCOPES[@]} -eq 0 ]]; then
  echo "ERROR: no readable settings scope found (looked under $PROJECT_ROOT/.claude and ${USER_DIR:-<no user dir>})" >&2
  for u in ${UNREADABLE+"${UNREADABLE[@]}"}; do echo "  unreadable: $u" >&2; done
  exit 2
fi

# --- Hook extraction ---------------------------------------------------------

# One jq program, used for every hook source. Input is the object that holds a
# `hooks` map (a settings file, or a plugin hook config). Output is one TSV row
# per command: event, matcher, command.
# shellcheck disable=SC2016  # a jq program: $h/$event/$matcher are jq variables and must reach jq unexpanded
HOOK_ROWS_JQ='
  (.hooks // {}) as $h
  | [ $h | to_entries[]
      | .key as $event
      | (.value // [])
      | if type == "array" then . else [] end
      | .[]
      | (.matcher // "*") as $matcher
      | ((.hooks // []) | if type == "array" then . else [] end)[]
      | [$event, $matcher, ((.command // .url // "<no command>") | tostring)]
    ]
  | .[] | @tsv
'

# Plugin hook configs are documented as `{"hooks": {...}}`. A file that carries
# the event map at the top level with no `hooks` key is read that way instead,
# and the fallback is visible here rather than being a silent guess.
PLUGIN_HOOK_NORMALIZE_JQ='if has("hooks") then . else {hooks: .} end'

ROWS=()
emit_rows() {
  # emit_rows <source-label> <json-file-or-inline> [--inline]
  local src="$1" input="$2" mode="${3:-file}" out
  if [[ "$mode" == "--inline" ]]; then
    out="$(printf '%s' "$input" | jqs -r "$PLUGIN_HOOK_NORMALIZE_JQ | $HOOK_ROWS_JQ")"
  else
    out="$(jqs -r "$HOOK_ROWS_JQ" "$input")"
  fi
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    UNREADABLE+=("$src: hook config did not parse")
    PARTIAL=1
    return 0
  fi
  [[ -z "$out" ]] && return 0
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && ROWS+=("$src	$line")
  done <<EOF
$out
EOF
}

i=0
while [[ $i -lt ${#SCOPES[@]} ]]; do
  emit_rows "settings:${SCOPE_LABELS[$i]}" "${SCOPES[$i]}"
  i=$((i + 1))
done

# --- Suppression levers ------------------------------------------------------
#
# A hook that is installed but switched off is not coverage. These are the three
# levers the audit's own narrowing rules name; the two managed-only ones are
# reported wherever they are visible, because a run that cannot see managed
# settings must not read their absence as "not set".

LEVERS=()
i=0
while [[ $i -lt ${#SCOPES[@]} ]]; do
  for key in disableAllHooks allowManagedHooksOnly strictPluginOnlyCustomization; do
    # shellcheck disable=SC2016  # $k is a jq --arg binding, not a shell variable
    val="$(jqs -r --arg k "$key" 'if has($k) then (.[$k] | tostring) else empty end' "${SCOPES[$i]}")"
    [[ -n "$val" ]] && LEVERS+=("${SCOPE_LABELS[$i]}	$key	$val")
  done
  i=$((i + 1))
done

# --- Enabled plugins ---------------------------------------------------------

ENABLED=()
i=0
while [[ $i -lt ${#SCOPES[@]} ]]; do
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    case " ${ENABLED[*]-} " in
    *" $p "*) ;;
    *) ENABLED+=("$p") ;;
    esac
  done < <(jqs -r '(.enabledPlugins // {}) | to_entries[] | select(.value == true) | .key' "${SCOPES[$i]}")
  i=$((i + 1))
done

PLUGIN_STATUS=()

resolve_install_path() {
  # resolve_install_path <plugin-key> — echo the install directory, or nothing.
  # installed_plugins.json maps "<plugin>@<marketplace>" to an array of install
  # records each carrying an already-resolved, version-pinned `installPath`, so
  # no version-directory ordering is inferred here.
  [[ -f "$INSTALLED_JSON" ]] || return 1
  # shellcheck disable=SC2016  # $k is a jq --arg binding, not a shell variable
  jqs -r --arg k "$1" '
    (.plugins // {})[$k] // []
    | if type == "array" then . else [] end
    | map(select(.installPath != null))
    | last // {}
    | .installPath // empty
  ' "$INSTALLED_JSON"
}

if [[ ${#ENABLED[@]} -gt 0 && ! -f "$INSTALLED_JSON" ]]; then
  UNREADABLE+=("installed_plugins.json not found at ${INSTALLED_JSON:-<unset>} — no plugin hook could be enumerated")
  PARTIAL=1
fi

for key in ${ENABLED+"${ENABLED[@]}"}; do
  path="$(resolve_install_path "$key")"
  # Git Bash reports a Windows path here; normalize the separators so the
  # existence test and the reads below work from a POSIX shell.
  path="${path//\\//}"
  if [[ -z "$path" ]]; then
    PLUGIN_STATUS+=("$key	UNRESOLVED	no installPath in the installed-plugin registry")
    PARTIAL=1
    continue
  fi
  if [[ ! -d "$path" ]]; then
    PLUGIN_STATUS+=("$key	UNRESOLVED	registry names $path, which is not a directory")
    PARTIAL=1
    continue
  fi

  manifest="$path/.claude-plugin/plugin.json"
  declared=""
  if [[ -f "$manifest" ]]; then
    declared="$(jqs -r 'if has("hooks") then (.hooks | tostring) else empty end' "$manifest")"
  fi

  before=${#ROWS[@]}
  found=0

  if [[ -n "$declared" ]]; then
    htype="$(jqs -r '.hooks | type' "$manifest")"
    case "$htype" in
    string | array)
      while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        rel="${rel#./}"
        if [[ -f "$path/$rel" ]]; then
          emit_rows "plugin:$key" "$path/$rel"
          found=1
        else
          UNREADABLE+=("plugin:$key declares hooks at $rel, which does not exist")
          PARTIAL=1
        fi
      done < <(jqs -r 'if (.hooks | type) == "array" then .hooks[] else .hooks end' "$manifest")
      ;;
    object)
      emit_rows "plugin:$key" "$declared" --inline
      found=1
      ;;
    *)
      UNREADABLE+=("plugin:$key declares a hooks key of unsupported type $htype")
      PARTIAL=1
      ;;
    esac
  fi

  if [[ $found -eq 0 && -f "$path/hooks/hooks.json" ]]; then
    if jq empty "$path/hooks/hooks.json" 2>/dev/null; then
      raw="$(jqs -c "$PLUGIN_HOOK_NORMALIZE_JQ" "$path/hooks/hooks.json")"
      emit_rows "plugin:$key" "$raw" --inline
      found=1
    else
      UNREADABLE+=("plugin:$key: hooks/hooks.json is not valid JSON")
      PARTIAL=1
    fi
  fi

  added=$((${#ROWS[@]} - before))
  if [[ $found -eq 0 ]]; then
    PLUGIN_STATUS+=("$key	NO-HOOKS	no hooks/hooks.json and no hooks key in plugin.json")
  else
    PLUGIN_STATUS+=("$key	OK	$added hook command(s)")
  fi
done

# --- Output ------------------------------------------------------------------

if [[ $EMIT_JSON -eq 1 ]]; then
  {
    printf '{\n'
    printf '  "inventory": "%s",\n' "$([[ $PARTIAL -eq 0 ]] && echo complete || echo partial)"
    printf '  "hooks": ['
    sep=""
    for r in ${ROWS+"${ROWS[@]}"}; do
      IFS=$'\t' read -r src event matcher cmd <<EOF
$r
EOF
      printf '%s\n    ' "$sep"
      jq -cn --arg s "$src" --arg e "$event" --arg m "$matcher" --arg c "$cmd" \
        '{source:$s,event:$e,matcher:$m,command:$c}'
      sep=","
    done
    printf '\n  ],\n'
    printf '  "plugins": ['
    sep=""
    for p in ${PLUGIN_STATUS+"${PLUGIN_STATUS[@]}"}; do
      IFS=$'\t' read -r pk st note <<EOF
$p
EOF
      printf '%s\n    ' "$sep"
      jq -cn --arg k "$pk" --arg s "$st" --arg n "$note" '{plugin:$k,status:$s,note:$n}'
      sep=","
    done
    printf '\n  ],\n'
    printf '  "levers": ['
    sep=""
    for l in ${LEVERS+"${LEVERS[@]}"}; do
      IFS=$'\t' read -r sc lk lv <<EOF
$l
EOF
      printf '%s\n    ' "$sep"
      jq -cn --arg s "$sc" --arg k "$lk" --arg v "$lv" '{scope:$s,key:$k,value:$v}'
      sep=","
    done
    printf '\n  ],\n'
    printf '  "unreadable": ['
    sep=""
    for u in ${UNREADABLE+"${UNREADABLE[@]}"}; do
      printf '%s\n    ' "$sep"
      jq -cn --arg m "$u" '$m'
      sep=","
    done
    printf '\n  ]\n}\n'
  }
else
  echo "Hook inventory"
  echo "=============="
  echo "Project root: $PROJECT_ROOT"
  echo "Scopes read:  ${SCOPE_LABELS[*]}"
  echo "Registry:     ${INSTALLED_JSON:-<none>}"
  echo
  if [[ ${#ROWS[@]} -eq 0 ]]; then
    echo "Hooks: none found in any enumerated source."
  else
    echo "Hooks (${#ROWS[@]}):"
    printf '  %-28s %-22s %-12s %s\n' "SOURCE" "EVENT" "MATCHER" "COMMAND"
    for r in "${ROWS[@]}"; do
      IFS=$'\t' read -r src event matcher cmd <<EOF
$r
EOF
      printf '  %-28s %-22s %-12s %s\n' "$src" "$event" "$matcher" "$cmd"
    done
  fi
  echo
  if [[ ${#PLUGIN_STATUS[@]} -gt 0 ]]; then
    echo "Enabled plugins (${#PLUGIN_STATUS[@]}):"
    for p in "${PLUGIN_STATUS[@]}"; do
      IFS=$'\t' read -r pk st note <<EOF
$p
EOF
      printf '  %-8s %-40s %s\n' "$st" "$pk" "$note"
    done
    echo
  fi
  if [[ ${#LEVERS[@]} -gt 0 ]]; then
    echo "Hook-suppression levers set:"
    for l in "${LEVERS[@]}"; do
      IFS=$'\t' read -r sc lk lv <<EOF
$l
EOF
      printf '  %-8s %-32s %s\n' "$sc" "$lk" "$lv"
    done
    echo
  fi
  if [[ ${#UNREADABLE[@]} -gt 0 ]]; then
    echo "Not enumerated (${#UNREADABLE[@]}) — treat the families these might cover as unsettled:"
    for u in "${UNREADABLE[@]}"; do echo "  - $u"; done
    echo
  fi
  if [[ $PARTIAL -eq 0 ]]; then
    echo "INVENTORY: complete — every enabled plugin resolved and every hook source parsed."
  else
    echo "INVENTORY: partial — see 'Not enumerated' above. Narrowing 3 stays conditional for anything those sources could cover."
  fi
fi

exit $PARTIAL
