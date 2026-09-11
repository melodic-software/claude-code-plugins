#!/usr/bin/env bash
# Hook inventory for the audit skill (Categories B and D).
#
# WHY THIS EXISTS. Category D writes rules for hooks that use
# ${CLAUDE_PLUGIN_ROOT} / ${CLAUDE_PLUGIN_DATA}, and those placeholders only
# ever appear in a PLUGIN-provided hook. Category B's third baseline narrowing
# demotes a missing deny pattern to `info` when a LIVE PreToolUse hook already
# blocks the family. Both need to know what hooks are installed.
#
# WHAT IT ENUMERATES.
#   1. Settings-declared hooks: project settings.json, project
#      settings.local.json, and the user-scope settings.json.
#   2. Plugin-declared hooks: for every plugin enabled in any of those scopes,
#      the plugin's own hook config, read from the directory the session
#      actually loads. A plugin that comes from a `directory` marketplace is
#      read from that marketplace's checkout; any other plugin is resolved
#      through the installed-plugin registry, so no version-directory guessing
#      is involved either way.
#   3. The suppression levers that can switch hooks off wholesale, because a
#      hook that cannot run is not coverage.
#   4. Cache-versus-loaded divergence: when a plugin resolves through both a
#      marketplace directory and a registry installPath and the two differ, the
#      pair is reported as an info note. It never changes the exit code.
#
# WHERE A PLUGIN'S HOOKS LIVE. Two steps: which directory, then which file.
#
# Which directory. A marketplace registered as
# `{"source": {"source": "directory", "path": "<dir>"}}` (in a settings scope's
# `extraKnownMarketplaces`, or in the user dir's plugins/known_marketplaces.json
# as `installLocation`) is loaded from <dir> itself: each plugin runs from
# `<dir>/<marketplace.json entry .source>`, not from the registry's versioned
# cache snapshot. That snapshot is taken at install time and can lag the
# checkout, so the marketplace directory is tried first and the registry's
# installPath is the fallback for everything else. A relative marketplace path
# resolves against the project root for the project and local scopes and
# against the directory that contains the user config dir for the user scope,
# mirroring where each settings file sits.
#
# Which file. plugins-reference says "Location: `hooks/hooks.json` in plugin
# root, or inline in plugin.json", and the manifest's `hooks` key is
# `string|array|object`: a path, several paths, or an inline config. All four
# shapes are read here; a plugin whose shape this script cannot parse is
# reported UNREADABLE, never silently as "no hooks".
#
# WHAT IT DOES NOT DO. It does not decide whether a hook covers a permission
# family. That judgment is the audit's, and required-permissions.md "Narrowing
# the baseline" carries the three preconditions it has to apply. This script
# answers only "what is installed".
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
hooks (from the marketplace directory a directory-source marketplace loads,
else via the installed-plugin registry), plus the levers that suppress hooks
wholesale. When a plugin resolves both ways to different directories, the pair
is reported as an info note. Read-only; never runs a hook.

Usage:
  check-hook-coverage.sh [--json] [--help]

  --json   emit the inventory as JSON on stdout instead of a table
           (project_root, hooks, plugins, divergence, levers, unreadable)

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
    # A scope that exists but does not parse may carry a suppression lever, so
    # the lever set is unknown rather than empty. An ABSENT scope carries no
    # lever and leaves the state complete.
    LEVER_STATE=unknown
    return 0
  fi
  SCOPES+=("$1")
  SCOPE_LABELS+=("$2")
}

PARTIAL=0
UNREADABLE=()
LEVER_STATE=complete
declare -A BAD_CATALOG=()

add_scope "$PROJECT_ROOT/.claude/settings.json" "project"
add_scope "$PROJECT_ROOT/.claude/settings.local.json" "local"
[[ -n "$USER_DIR" ]] && add_scope "$USER_DIR/settings.json" "user"

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MANAGED_SCOPE_LIB="$PLUGIN_ROOT/lib/managed-scope.sh"
MANAGED_NOTE=""
if [[ -r "$MANAGED_SCOPE_LIB" ]]; then
  # shellcheck source=../../../lib/managed-scope.sh
  # shellcheck disable=SC1091
  source "$MANAGED_SCOPE_LIB"
  MANAGED_FILE="$(mscope::base_file "${HOOK_COVERAGE_MANAGED_JSON:-}")"
  if [[ -f "$MANAGED_FILE" ]]; then
    add_scope "$MANAGED_FILE" "managed"
  else
    MANAGED_NOTE="Managed-settings JSON not present at ${MANAGED_FILE}; registry/plist managed policy is not read."
  fi
else
  MANAGED_NOTE="Managed-scope library missing; managed hook-suppression levers were not read."
fi

if [[ ${#SCOPES[@]} -eq 0 ]]; then
  echo "ERROR: no readable settings scope found (looked under $PROJECT_ROOT/.claude and ${USER_DIR:-<no user dir>})" >&2
  for u in ${UNREADABLE+"${UNREADABLE[@]}"}; do echo "  unreadable: $u" >&2; done
  exit 2
fi

# --- Hook extraction ---------------------------------------------------------

# One jq program, used for every hook source. Input is the object that holds a
# `hooks` map (a settings file, or a plugin hook config). Output is one
# tab-separated row per command: event, matcher, command, and a JSON object of
# the entry's remaining fields (timeout, type, if, shell, args). The first three
# are never empty and the fourth is compact JSON, so no field is blank and none
# carries a tab, which keeps a tab-split `read` from collapsing columns. Tabs and
# line breaks inside a value become spaces; backslashes pass through verbatim.
# shellcheck disable=SC2016  # a jq program: $h/$event/$matcher are jq variables and must reach jq unexpanded
HOOK_ROWS_JQ='
  def flat: tostring | gsub("[\t\r\n]"; " ");
  (.hooks // {}) as $h
  | [ $h | to_entries[]
      | .key as $event
      | (.value // [])
      | if type == "array" then . else [] end
      | .[]
      | ((.matcher // "*") | if . == "" then "*" else . end) as $matcher
      | ((.hooks // []) | if type == "array" then . else [] end)[]
      | [ ($event | flat),
          ($matcher | flat),
          ((.command // .url // "<no command>") | if . == "" then "<no command>" else . end | flat),
          ({ timeout: (if (.timeout | type) == "number" then .timeout else null end),
             type: ((.type // "command") | tostring),
             if: ((.if // "") | tostring),
             shell: ((.shell // "") | tostring),
             args: (.args // [])
           } | tojson)
        ]
    ]
  | .[] | join("\t")
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
  done <<<"$out"
}

for i in "${!SCOPES[@]}"; do
  emit_rows "settings:${SCOPE_LABELS[$i]}" "${SCOPES[$i]}"
done

# --- Suppression levers ------------------------------------------------------
#
# A hook that is installed but switched off is not coverage. These are the three
# levers the audit's own narrowing rules name; the two managed-only ones are
# reported wherever they are visible, because a run that cannot see managed
# settings must not read their absence as "not set".

LEVERS=()
for i in "${!SCOPES[@]}"; do
  for key in disableAllHooks allowManagedHooksOnly strictPluginOnlyCustomization; do
    # shellcheck disable=SC2016  # $k is a jq --arg binding, not a shell variable
    val="$(jqs -r --arg k "$key" 'if has($k) then (.[$k] | tostring) else empty end' "${SCOPES[$i]}")"
    [[ -n "$val" ]] && LEVERS+=("${SCOPE_LABELS[$i]}	$key	$val")
  done
done

# --- Enabled plugins (local > project > user) --------------------------------

declare -A ENABLED_STATE=()
merge_enabled_plugins() {
  local label="$1" i
  for i in "${!SCOPE_LABELS[@]}"; do
    if [[ "${SCOPE_LABELS[$i]}" == "$label" ]]; then
      while IFS=$'\t' read -r pk pv; do
        [[ -z "$pk" ]] && continue
        ENABLED_STATE[$pk]="$pv"
      done < <(jqs -r '(.enabledPlugins // {}) | to_entries[] | [.key, (.value | tostring)] | @tsv' "${SCOPES[$i]}")
      return 0
    fi
  done
}
for label in user project local; do
  merge_enabled_plugins "$label"
done
ENABLED=()
for pk in "${!ENABLED_STATE[@]}"; do
  [[ "${ENABLED_STATE[$pk]}" == "true" ]] && ENABLED+=("$pk")
done

PLUGIN_STATUS=()

resolve_install_path() {
  # resolve_install_path <plugin-key> — echo the install directory, or nothing.
  # installed_plugins.json maps "<plugin>@<marketplace>" to install records each
  # carrying a version-pinned installPath and a scope; when several records exist,
  # pick the one for this project with local > project > user precedence.
  [[ -f "$INSTALLED_JSON" ]] || return 1
  local project_norm="${PROJECT_ROOT//\\//}"
  project_norm="${project_norm%/}"
  # shellcheck disable=SC2016  # $k/$project are jq --arg bindings, not shell variables
  jqs -r --arg k "$1" --arg project "$project_norm" '
    def rank($s): if $s == "local" then 3 elif $s == "project" then 2 elif $s == "user" then 1 else 0 end;
    (.plugins // {})[$k] // []
    | if type == "array" then . else [] end
    | map(select(.installPath != null))
    | map(. + {scope: (.scope // "user"), projectPath: ((.projectPath // "") | gsub("\\\\"; "/") | rtrimstr("/"))})
    | map(select(
        .projectPath == "" or .projectPath == $project
        or ($project | startswith(.projectPath + "/"))
      ))
    | sort_by(-(rank(.scope)))
    | .[0].installPath // empty
  ' "$INSTALLED_JSON"
}

norm_path() {
  # norm_path <path>: forward slashes only, no trailing slash. Git Bash reports
  # Windows paths with backslashes; the existence tests below need POSIX form.
  local p="${1//\\//}"
  while [[ "$p" == */ && ${#p} -gt 1 ]]; do p="${p%/}"; done
  printf '%s\n' "$p"
}

join_path() {
  # join_path <base> <path>: <path> as is when absolute, else under <base>.
  # A leading ./ is dropped; an empty or "." path is <base> itself.
  local base p
  base="$(norm_path "$1")"
  p="$(norm_path "$2")"
  while [[ "$p" == ./* ]]; do p="${p#./}"; done
  if [[ "$p" == /* || "$p" =~ ^[A-Za-z]:(/|$) ]]; then
    printf '%s\n' "$p"
  elif [[ -z "$p" || "$p" == "." ]]; then
    printf '%s\n' "$base"
  else
    printf '%s\n' "$base/$p"
  fi
}

canon_dir() {
  # canon_dir <dir>: the physical path when the directory exists, else as given,
  # so two spellings of one directory compare equal and a symlinked checkout is
  # not reported as diverging from itself.
  (cd -- "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"
}

resolve_marketplace_dir() {
  # resolve_marketplace_dir <marketplace-name>: echo the directory a
  # directory-source marketplace is loaded from, or nothing. Looked up in the
  # extraKnownMarketplaces block of each settings scope read (project, then
  # local, then user), then in the user dir's plugins/known_marketplaces.json.
  # A relative path in a settings scope resolves against that file's base: the
  # project root for project and local, the directory that contains the user
  # config dir for user. known_marketplaces.json carries installLocation.
  local name="$1" label i base rel known
  for label in project local user; do
    for i in "${!SCOPE_LABELS[@]}"; do
      [[ "${SCOPE_LABELS[$i]}" == "$label" ]] || continue
      # shellcheck disable=SC2016  # $n is a jq --arg binding, not a shell variable
      rel="$(jqs -r --arg n "$name" '
        ((.extraKnownMarketplaces // {})[$n] // {})
        | (.source // {})
        | select(type == "object" and .source == "directory")
        | .path // empty | tostring
      ' "${SCOPES[$i]}")"
      [[ -n "$rel" ]] || continue
      if [[ "$label" == "user" ]]; then base="$(dirname "$USER_DIR")"; else base="$PROJECT_ROOT"; fi
      join_path "$base" "$rel"
      return 0
    done
  done
  [[ -n "$USER_DIR" ]] || return 1
  known="$USER_DIR/plugins/known_marketplaces.json"
  [[ -f "$known" ]] || return 1
  # shellcheck disable=SC2016  # $n is a jq --arg binding, not a shell variable
  rel="$(jqs -r --arg n "$name" '
    (.[$n] // {})
    | select(type == "object" and ((.source // {}) | type) == "object" and (.source // {}).source == "directory")
    | .installLocation // empty | tostring
  ' "$known")"
  [[ -n "$rel" ]] || return 1
  norm_path "$rel"
}

resolve_marketplace_plugin_path() {
  # resolve_marketplace_plugin_path <plugin-key>: echo the directory a
  # directory-source marketplace loads this plugin from, or nothing. The
  # marketplace's .claude-plugin/marketplace.json names each plugin and its
  # `source`, a path relative to the marketplace directory; only a string
  # source is a local path, so an object source (github, url) is left to the
  # registry route.
  local key="$1" plugin mkt mdir catalog src dir
  [[ "$key" == *@* ]] || return 1
  plugin="${key%@*}"
  mkt="${key##*@}"
  mdir="$(resolve_marketplace_dir "$mkt")" || return 1
  [[ -n "$mdir" ]] || return 1
  catalog="$mdir/.claude-plugin/marketplace.json"
  [[ -f "$catalog" ]] || return 1
  # A catalog that does not parse is exit 2, distinct from "plugin absent"
  # (exit 1): the caller records it, since this function runs in a command
  # substitution where a global assignment would be lost.
  if ! tr -d '\r' <"$catalog" | jq empty 2>/dev/null; then
    return 2
  fi
  # shellcheck disable=SC2016  # $n is a jq --arg binding, not a shell variable
  src="$(jqs -r --arg n "$plugin" '
    (.plugins // []) | if type == "array" then . else [] end
    | map(select(type == "object" and .name == $n))
    | .[0].source // empty
    | if type == "string" then . else empty end
  ' "$catalog")"
  [[ -n "$src" ]] || return 1
  dir="$(join_path "$mdir" "$src")"
  [[ -d "$dir" ]] || return 1
  printf '%s\n' "$dir"
}

# Divergence rows: <plugin-key> <marketplace-dir-path> <registry-path>, one per
# plugin that resolves both ways to different directories. Info only.
DIVERGENCE=()
# Enabled plugins that did not resolve through a marketplace directory and so
# needed the registry. Only these make a missing registry a reportable gap.
REGISTRY_FALLBACKS=0

for key in ${ENABLED+"${ENABLED[@]}"}; do
  mpath="$(resolve_marketplace_plugin_path "$key")"
  mrc=$?
  if [[ $mrc -eq 2 ]]; then
    # What the session loads from an unparsable catalog is unknown, so the
    # inventory is partial even though the registry route still resolves the
    # plugin. Reported once per marketplace.
    bad_mkt="${key##*@}"
    if [[ -z "${BAD_CATALOG[$bad_mkt]:-}" ]]; then
      BAD_CATALOG[$bad_mkt]=1
      UNREADABLE+=("marketplace:$bad_mkt: its .claude-plugin/marketplace.json is not valid JSON; plugins it lists resolve through the registry cache instead")
      PARTIAL=1
    fi
  fi
  rpath="$(norm_path "$(resolve_install_path "$key")")"
  loaded_note=""
  if [[ -n "$mpath" ]]; then
    path="$mpath"
    loaded_note=" (loaded from marketplace directory)"
    if [[ -n "$rpath" && "$(canon_dir "$mpath")" != "$(canon_dir "$rpath")" ]]; then
      DIVERGENCE+=("$key	$mpath	$rpath")
    fi
  else
    REGISTRY_FALLBACKS=$((REGISTRY_FALLBACKS + 1))
    path="$rpath"
    if [[ -z "$path" ]]; then
      PLUGIN_STATUS+=("$key	UNRESOLVED	no installPath in the installed-plugin registry	")
      PARTIAL=1
      continue
    fi
    if [[ ! -d "$path" ]]; then
      PLUGIN_STATUS+=("$key	UNRESOLVED	registry names $path, which is not a directory	")
      PARTIAL=1
      continue
    fi
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
    PLUGIN_STATUS+=("$key	NO-HOOKS	no hooks/hooks.json and no hooks key in plugin.json$loaded_note	$path")
  else
    PLUGIN_STATUS+=("$key	OK	$added hook command(s)$loaded_note	$path")
  fi
done

if [[ $REGISTRY_FALLBACKS -gt 0 && ! -f "$INSTALLED_JSON" ]]; then
  UNREADABLE+=("installed_plugins.json not found at ${INSTALLED_JSON:-<unset>}; $REGISTRY_FALLBACKS enabled plugin(s) outside a marketplace directory could not be enumerated")
  PARTIAL=1
fi

# --- Output ------------------------------------------------------------------

if [[ $EMIT_JSON -eq 1 ]]; then
  {
    printf '{\n'
    printf '  "inventory": "%s",\n' "$([[ $PARTIAL -eq 0 ]] && echo complete || echo partial)"
    printf '  "lever_state": "%s",\n' "$LEVER_STATE"
    printf '  "project_root": %s,\n' "$(jq -cn --arg r "$PROJECT_ROOT" '$r')"
    printf '  "hooks": ['
    sep=""
    for r in ${ROWS+"${ROWS[@]}"}; do
      IFS=$'\t' read -r src event matcher cmd extra <<<"$r"
      printf '%s\n    ' "$sep"
      # shellcheck disable=SC2016  # $x is a jq --argjson binding, not a shell variable
      jq -cn --arg s "$src" --arg e "$event" --arg m "$matcher" --arg c "$cmd" --argjson x "${extra:-{\}}" \
        '{source:$s,event:$e,matcher:$m,command:$c} + $x'
      sep=","
    done
    printf '\n  ],\n'
    printf '  "plugins": ['
    sep=""
    for p in ${PLUGIN_STATUS+"${PLUGIN_STATUS[@]}"}; do
      IFS=$'\t' read -r pk st note ppath <<<"$p"
      printf '%s\n    ' "$sep"
      jq -cn --arg k "$pk" --arg s "$st" --arg n "$note" --arg p "${ppath:-}" '{plugin:$k,status:$s,note:$n,path:$p}'
      sep=","
    done
    printf '\n  ],\n'
    printf '  "divergence": ['
    sep=""
    for d in ${DIVERGENCE+"${DIVERGENCE[@]}"}; do
      IFS=$'\t' read -r dk dl dc <<<"$d"
      printf '%s\n    ' "$sep"
      jq -cn --arg p "$dk" --arg l "$dl" --arg c "$dc" '{plugin:$p,loaded:$l,cached:$c}'
      sep=","
    done
    printf '\n  ],\n'
    printf '  "levers": ['
    sep=""
    for l in ${LEVERS+"${LEVERS[@]}"}; do
      IFS=$'\t' read -r sc lk lv <<<"$l"
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
      IFS=$'\t' read -r src event matcher cmd _extra <<<"$r"
      printf '  %-28s %-22s %-12s %s\n' "$src" "$event" "$matcher" "$cmd"
    done
  fi
  echo
  if [[ ${#PLUGIN_STATUS[@]} -gt 0 ]]; then
    echo "Enabled plugins (${#PLUGIN_STATUS[@]}):"
    for p in "${PLUGIN_STATUS[@]}"; do
      IFS=$'\t' read -r pk st note _ppath <<<"$p"
      printf '  %-8s %-40s %s\n' "$st" "$pk" "$note"
    done
    echo
  fi
  if [[ ${#DIVERGENCE[@]} -gt 0 ]]; then
    echo "Cache-versus-loaded divergence (${#DIVERGENCE[@]}):"
    for d in "${DIVERGENCE[@]}"; do
      IFS=$'\t' read -r dk dl dc <<<"$d"
      printf '  %s: loads %s; registry cache at %s\n' "$dk" "$dl" "$dc"
    done
    echo "  Info: the session loads the marketplace directory; the cache is what a tool resolving through the registry would read."
    echo
  fi
  if [[ "$LEVER_STATE" != "complete" ]]; then
    echo "Hook-suppression lever state: UNKNOWN — a settings scope did not parse, so a lever that switches hooks off may be set and unread."
    echo
  fi
  if [[ ${#LEVERS[@]} -gt 0 ]]; then
    echo "Hook-suppression levers set:"
    for l in "${LEVERS[@]}"; do
      IFS=$'\t' read -r sc lk lv <<<"$l"
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
    echo "INVENTORY: complete — every enabled plugin resolved and every hook source parsed in the scopes read (${SCOPE_LABELS[*]})."
    [[ -n "$MANAGED_NOTE" ]] && echo "  Managed caveat: $MANAGED_NOTE"
  else
    echo "INVENTORY: partial — see 'Not enumerated' above. Narrowing 3 stays conditional for anything those sources could cover."
  fi
fi

exit $PARTIAL
