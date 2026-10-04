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
# Read-only: opens JSON and prints, writing only its own temp file. Never
# executes a hook command.
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

# Every value the --json emitter builds a node from goes through this. A jq
# --arg value is DATA, never a path for jq to open, but on Git for Windows the
# call crosses CreateProcess and MSYS rewrites any argument whose tail looks
# like a POSIX path: a plugin's shipped hook command
# "${CLAUDE_PLUGIN_ROOT}"/hooks/x.sh arrives as
# "${CLAUDE_PLUGIN_ROOT}"C:/Program Files/Git/hooks/x.sh, so the engine reports
# hook-path-missing for a file that exists. Suppressing the conversion is safe
# for every call routed here because not one passes a file for jq to OPEN; a
# site that does must keep the conversion, or jq could no longer find the file.
# Set inline per call, never exported.
#
# The CR strip is the same one jqs() above does, for the same reason: native jq
# writes stdout in TEXT mode here and ends every line CRLF. In a node fragment
# the stray CR lands between JSON tokens, where it is only whitespace, so it
# corrupts nothing today; stripping it keeps the two jq wrappers honest about the
# same platform quirk, so a value ever captured from this one cannot carry a CR
# into a comparison. jq escapes a control character inside a string as \r, so a
# literal CR byte in its output is only ever the line terminator.
jqn() { MSYS2_ARG_CONV_EXCL='*' jq -cn "$@" | tr -d '\r'; }

# json_nodes <width> <jq-program> <field>...: one compact JSON node per line,
# one for every <width> fields, from a single jq call, so a large inventory
# costs one process per array rather than one per node (each is tens to
# hundreds of milliseconds on Windows). The program sees each group as $f. The
# fields cross as one base64 text of NUL-terminated strings, which has no argv
# cap, needs no MSYS rewriting guard, and carries a CR in a value through jq's
# text-mode stdin on Windows.
json_nodes() {
  local w="$1" prog="$2"
  shift 2
  [[ $# -gt 0 ]] || return 0
  printf '%s\0' "$@" | base64 | tr -d '\r\n' |
    jq -R -c --argjson w "$w" "@base64d | split(\"\\u0000\")[:-1] | range(0; length; \$w) as \$i | .[\$i : \$i + \$w] as \$f | $prog" |
    tr -d '\r'
}

# print_nodes <node>...: the nodes of one --json array, laid out as the
# emitter always has.
print_nodes() {
  local sep="" n
  for n in "$@"; do
    printf '%s\n    %s\n' "$sep" "$n"
    sep=","
  done
}

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

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# The project-root, user-dir and registry ladders are shared vocabulary
# (lib/resolve-scopes.sh), not this script's to restate. Fail loudly rather than
# fall through: an unsourced library leaves every root empty and the inventory
# would report "no settings scope" on a machine that has them.
RESOLVE_SCOPES_LIB="$PLUGIN_ROOT/lib/resolve-scopes.sh"
if [[ ! -r "$RESOLVE_SCOPES_LIB" ]]; then
  echo "ERROR: cannot read $RESOLVE_SCOPES_LIB; the plugin's shared scope-resolution library is missing" >&2
  exit 2
fi
# shellcheck source=../../../lib/resolve-scopes.sh
# shellcheck disable=SC1091
source "$RESOLVE_SCOPES_LIB"

# Initialized here so ShellCheck SC2154 sees the assignment; the ladder fills it in.
PROJECT_ROOT=""
scopes::project_root_to PROJECT_ROOT "${HOOK_COVERAGE_FIXTURE_DIR:-}"
USER_DIR=""
scopes::user_dir_to USER_DIR "${HOOK_COVERAGE_USER_DIR:-}"
INSTALLED_JSON=""
scopes::installed_registry_to INSTALLED_JSON "${HOOK_COVERAGE_INSTALLED_JSON:-}" "$USER_DIR"

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

MANAGED_SCOPE_LIB="$PLUGIN_ROOT/lib/managed-scope.sh"
MANAGED_NOTE=""
MANAGED_PRESENT=false
if [[ -r "$MANAGED_SCOPE_LIB" ]]; then
  # shellcheck source=../../../lib/managed-scope.sh
  # shellcheck disable=SC1091
  source "$MANAGED_SCOPE_LIB"
  MANAGED_FILE="$(mscope::base_file "${HOOK_COVERAGE_MANAGED_JSON:-}")"
  if [[ -f "$MANAGED_FILE" ]]; then
    MANAGED_PRESENT=true
    add_scope "$MANAGED_FILE" "managed"
  else
    MANAGED_NOTE="Managed-settings JSON not present at ${MANAGED_FILE}; registry/plist managed policy is not read."
  fi
  compgen -G "$(mscope::dropin_dir "${HOOK_COVERAGE_MANAGED_JSON:-}")/*.json" >/dev/null && MANAGED_PRESENT=true
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
  add_rows "$src" $? "$out"
}

# add_rows <source-label> <jq-exit> <rows>: record the rows one hook source
# yielded, or the source as unreadable when its jq failed.
add_rows() {
  local src="$1" rc="$2" out="$3" line
  if [[ $rc -ne 0 ]]; then
    UNREADABLE+=("$src: hook config did not parse")
    PARTIAL=1
    return 0
  fi
  [[ -z "$out" ]] && return 0
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
    # Compact JSON, not tostring: true stays a boolean and an array stays an
    # array. strictPluginOnlyCustomization is true or a per-surface array
    # ("skills", "agents", "hooks", "mcp"). Stringifying the array made every
    # value look like a hook lock.
    # shellcheck disable=SC2016  # $k is a jq --arg binding, not a shell variable
    val="$(jqs -c --arg k "$key" 'if has($k) then .[$k] else empty end' "${SCOPES[$i]}")"
    [[ -n "$val" ]] && LEVERS+=("${SCOPE_LABELS[$i]}	$key	$val")
  done
done

# --- Mod-plane keys ----------------------------------------------------------
#
# Settings that govern mods (plugins of function hooks) rather than settings
# hooks: none switches a settings hook off, so they stay out of LEVERS and
# never feed the narrowing. The two guard options live under the built-in
# guard's pluginConfigs entry, the one spelling Claude Code reads them under.

MOD_PLANE=()
# shellcheck disable=SC2016  # a jq program; $k is a jq variable
MOD_PLANE_JQ='
  def obj: if type == "object" then . else {} end;
  (obj as $s | ["prependPlugins", "appendPlugins", "disableSideloadFlags"][] as $k
    | select($s | has($k)) | [$k, ($s[$k] | tojson)]),
  (obj | .pluginConfigs | obj | .["cc-plugin-sec-default@builtin"] | obj | .options | obj
    | to_entries[] | select(.key == "allowManagedModsOnly" or .key == "allowModsToOverrideDenyRules")
    | [.key, (.value | tojson)])
  | @tsv'
for i in "${!SCOPES[@]}"; do
  while IFS=$'\t' read -r mk mv; do
    [[ -n "$mk" ]] && MOD_PLANE+=("${SCOPE_LABELS[$i]}	$mk	$mv")
  done < <(jqs -r "$MOD_PLANE_JQ" "${SCOPES[$i]}")
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

# Every per-plugin step below runs in this shell and sets a variable rather
# than printing into a command substitution, and every lookup a marketplace or
# the registry answers for all plugins at once is made once: on Windows each
# process costs tens to hundreds of milliseconds, and this loop runs once per
# enabled plugin.

# nul_fields <base64>: decode a base64 text of NUL-terminated fields into the
# array NUL_FIELDS, one element per field, byte for byte. Returns 1, with
# NUL_FIELDS empty, when the text does not decode.
NUL_FIELDS=()
nul_fields() {
  local x
  NUL_FIELDS=()
  base64 -d <<<"$1" >"$FIELDS_FILE" 2>/dev/null || base64 -D <<<"$1" >"$FIELDS_FILE" 2>/dev/null || return 1
  while IFS= read -r -d '' x; do NUL_FIELDS+=("$x"); done <"$FIELDS_FILE"
}
FIELDS_FILE="$(mktemp 2>/dev/null)" || {
  echo "ERROR: could not create a temp file" >&2
  exit 2
}
trap 'rm -f "$FIELDS_FILE"' EXIT

# installPath per enabled plugin key, from one read of installed_plugins.json.
# The registry maps "<plugin>@<marketplace>" to install records each carrying a
# version-pinned installPath and a scope; when several records exist, the one
# for this project wins with local > project > user precedence.
declare -A INSTALL_PATH=()
if [[ -f "$INSTALLED_JSON" && ${#ENABLED[@]} -gt 0 ]]; then
  project_norm="${PROJECT_ROOT//\\//}"
  project_norm="${project_norm%/}"
  # shellcheck disable=SC2016  # $project is a jq --arg binding, not a shell variable
  if nul_fields "$(jqs -r --arg project "$project_norm" '
    def rank($s): if $s == "local" then 3 elif $s == "project" then 2 elif $s == "user" then 1 else 0 end;
    . as $reg
    | [$ARGS.positional[] as $k
      | ($reg.plugins // {})[$k] // []
      | if type == "array" then . else [] end
      | map(select(.installPath != null))
      | map(. + {scope: (.scope // "user"), projectPath: ((.projectPath // "") | gsub("\\\\"; "/") | rtrimstr("/"))})
      | map(select(
          .projectPath == "" or .projectPath == $project
          or (.projectPath as $pp | $project | startswith($pp + "/"))
        ))
      | sort_by(-(rank(.scope)))
      | (.[0].installPath // empty | tostring | gsub("\r"; "")) as $p
      | $k, $p]
    | map(gsub("\u0000"; "") + "\u0000") | add // "" | @base64
  ' "$INSTALLED_JSON" --args "${ENABLED[@]}")"; then
    for ((n = 0; n + 1 < ${#NUL_FIELDS[@]}; n += 2)); do
      INSTALL_PATH["${NUL_FIELDS[n]}"]="${NUL_FIELDS[n + 1]}"
    done
  fi
fi

norm_path_to() {
  # norm_path_to <var> <path>: forward slashes only, no trailing slash. Git
  # Bash reports Windows paths with backslashes; the existence tests below
  # need POSIX form.
  local _np="${2//\\//}"
  while [[ "$_np" == */ && ${#_np} -gt 1 ]]; do _np="${_np%/}"; done
  while [[ "$_np" == *$'\n' ]]; do _np="${_np%$'\n'}"; done
  printf -v "$1" '%s' "$_np"
}

join_path_to() {
  # join_path_to <var> <base> <path>: <path> as is when absolute, else under
  # <base>. A leading ./ is dropped; an empty or "." path is <base> itself.
  local _base _p
  norm_path_to _base "$2"
  norm_path_to _p "$3"
  while [[ "$_p" == ./* ]]; do _p="${_p#./}"; done
  if [[ "$_p" == /* || "$_p" =~ ^[A-Za-z]:(/|$) ]]; then
    printf -v "$1" '%s' "$_p"
  elif [[ -z "$_p" || "$_p" == "." ]]; then
    printf -v "$1" '%s' "$_base"
  else
    printf -v "$1" '%s' "$_base/$_p"
  fi
}

canon_dir_to() {
  # canon_dir_to <var> <dir>: the physical path when the directory exists, else
  # as given, so two spellings of one directory compare equal and a symlinked
  # checkout is not reported as diverging from itself.
  local _here="$PWD"
  if cd -P -- "$2" 2>/dev/null; then
    printf -v "$1" '%s' "$PWD"
    cd -- "$_here" || exit 2
  else
    printf -v "$1" '%s' "$2"
  fi
}

resolve_marketplace_dir_to() {
  # resolve_marketplace_dir_to <var> <marketplace-name>: the directory a
  # directory-source marketplace is loaded from; returns 1 when there is none.
  # Looked up in the extraKnownMarketplaces block of each settings scope read
  # (project, then local, then user), then in the user dir's
  # plugins/known_marketplaces.json. A relative path in a settings scope
  # resolves against that file's base: the project root for project and local,
  # the directory that contains the user config dir for user.
  # known_marketplaces.json carries installLocation.
  local _name="$2" label i base rel known
  for label in project local user; do
    for i in "${!SCOPE_LABELS[@]}"; do
      [[ "${SCOPE_LABELS[$i]}" == "$label" ]] || continue
      # shellcheck disable=SC2016  # $n is a jq --arg binding, not a shell variable
      rel="$(jqs -r --arg n "$_name" '
        ((.extraKnownMarketplaces // {})[$n] // {})
        | (.source // {})
        | select(type == "object" and .source == "directory")
        | .path // empty | tostring
      ' "${SCOPES[$i]}")"
      [[ -n "$rel" ]] || continue
      if [[ "$label" == "user" ]]; then base="$(dirname "$USER_DIR")"; else base="$PROJECT_ROOT"; fi
      join_path_to "$1" "$base" "$rel"
      return 0
    done
  done
  [[ -n "$USER_DIR" ]] || return 1
  known="$USER_DIR/plugins/known_marketplaces.json"
  [[ -f "$known" ]] || return 1
  # shellcheck disable=SC2016  # $n is a jq --arg binding, not a shell variable
  rel="$(jqs -r --arg n "$_name" '
    (.[$n] // {})
    | select(type == "object" and ((.source // {}) | type) == "object" and (.source // {}).source == "directory")
    | .installLocation // empty | tostring
  ' "$known")"
  [[ -n "$rel" ]] || return 1
  norm_path_to "$1" "$rel"
}

# Per marketplace, read once: MKT_STATE is none (no directory-source catalog),
# bad (its catalog does not parse) or ok; MKT_DIR its directory; MKT_SRC the
# string source of the first catalog entry of each plugin name, keyed
# "<marketplace><US><name>". The marketplace's .claude-plugin/marketplace.json
# names each plugin and its `source`, a path relative to the marketplace
# directory; only a string source is a local path, so an object source
# (github, url) is left to the registry route.
US=$'\x1f'
declare -A MKT_STATE=() MKT_DIR=() MKT_SRC=()
load_marketplace() {
  local mkt="$1" mdir="" catalog n
  MKT_STATE[$mkt]=none
  resolve_marketplace_dir_to mdir "$mkt" || return 0
  [[ -n "$mdir" ]] || return 0
  catalog="$mdir/.claude-plugin/marketplace.json"
  [[ -f "$catalog" ]] || return 0
  if ! tr -d '\r' <"$catalog" | jq empty 2>/dev/null; then
    MKT_STATE[$mkt]=bad
    return 0
  fi
  MKT_DIR[$mkt]="$mdir"
  MKT_STATE[$mkt]=ok
  # shellcheck disable=SC2016  # $e is a jq binding, not a shell variable
  nul_fields "$(jqs -r '
    (.plugins // []) | if type == "array" then . else [] end
    | reduce (.[] | select(type == "object" and (.name | type) == "string")) as $e
        ({}; if has($e.name) then . else .[$e.name] = $e.source end)
    | [to_entries[] | select(.value | type == "string") | .key, (.value | gsub("\r"; ""))]
    | map(gsub("\u0000"; "") + "\u0000") | add // "" | @base64
  ' "$catalog")" || return 0
  for ((n = 0; n + 1 < ${#NUL_FIELDS[@]}; n += 2)); do
    MKT_SRC["$mkt$US${NUL_FIELDS[n]}"]="${NUL_FIELDS[n + 1]}"
  done
}

marketplace_plugin_path_to() {
  # marketplace_plugin_path_to <var> <plugin-key>: the directory a
  # directory-source marketplace loads this plugin from. Returns 1 when there
  # is none, and 2 when the marketplace's catalog does not parse.
  local _key="$2" _plugin _mkt _dir
  printf -v "$1" '%s' ""
  [[ "$_key" == *@* ]] || return 1
  _plugin="${_key%@*}"
  _mkt="${_key##*@}"
  [[ -n "${MKT_STATE[$_mkt]+x}" ]] || load_marketplace "$_mkt"
  case "${MKT_STATE[$_mkt]}" in
  bad) return 2 ;;
  ok) ;;
  *) return 1 ;;
  esac
  [[ -n "${MKT_SRC["$_mkt$US$_plugin"]:-}" ]] || return 1
  join_path_to _dir "${MKT_DIR[$_mkt]}" "${MKT_SRC["$_mkt$US$_plugin"]}"
  [[ -d "$_dir" ]] || return 1
  printf -v "$1" '%s' "$_dir"
}

# Divergence rows: <plugin-key> <marketplace-dir-path> <registry-path>, one per
# plugin that resolves both ways to different directories. Info only.
DIVERGENCE=()
# Enabled plugins that did not resolve through a marketplace directory and so
# needed the registry. Only these make a missing registry a reportable gap.
REGISTRY_FALLBACKS=0

for key in ${ENABLED+"${ENABLED[@]}"}; do
  marketplace_plugin_path_to mpath "$key"
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
  norm_path_to rpath "${INSTALL_PATH[$key]:-}"
  loaded_note=""
  if [[ -n "$mpath" ]]; then
    path="$mpath"
    loaded_note=" (loaded from marketplace directory)"
    if [[ -n "$rpath" ]]; then
      mcanon="" rcanon=""
      canon_dir_to mcanon "$mpath"
      canon_dir_to rcanon "$rpath"
      [[ "$mcanon" != "$rcanon" ]] && DIVERGENCE+=("$key	$mpath	$rpath")
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
      # One jq normalizes and flattens the file; a value the normalization
      # cannot take yields no rows.
      out="$(jqs -r "(try ($PLUGIN_HOOK_NORMALIZE_JQ) catch empty) | $HOOK_ROWS_JQ" "$path/hooks/hooks.json")"
      add_rows "plugin:$key" $? "$out"
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

# Every single-quoted string in this block is a jq program and every $name in one
# is a jq binding, not a shell variable. shellcheck special-cases a literal `jq`
# command word and stays quiet; it cannot see through the jqn wrapper.
# shellcheck disable=SC2016
if [[ $EMIT_JSON -eq 1 ]]; then
  {
    printf '{\n'
    printf '  "inventory": "%s",\n' "$([[ $PARTIAL -eq 0 ]] && echo complete || echo partial)"
    printf '  "lever_state": "%s",\n' "$LEVER_STATE"
    printf '  "managed_scope": %s,\n' "$MANAGED_PRESENT"
    printf '  "project_root": %s,\n' "$(jqn --arg r "$PROJECT_ROOT" '$r')"
    # Each array's fields are split from their tab-joined records here, in the
    # shell, and every node of the array is built by one json_nodes call.
    fields=()
    for r in ${ROWS+"${ROWS[@]}"}; do
      IFS=$'\t' read -r src event matcher cmd extra <<<"$r"
      fields+=("$src" "$event" "$matcher" "$cmd" "${extra:-{\}}")
    done
    mapfile -t nodes < <(json_nodes 5 '{source: $f[0], event: $f[1], matcher: $f[2], command: $f[3]} + ($f[4] | fromjson)' ${fields+"${fields[@]}"})
    printf '  "hooks": ['
    print_nodes ${nodes+"${nodes[@]}"}
    printf '\n  ],\n'
    fields=()
    for p in ${PLUGIN_STATUS+"${PLUGIN_STATUS[@]}"}; do
      IFS=$'\t' read -r pk st note ppath <<<"$p"
      fields+=("$pk" "$st" "$note" "${ppath:-}")
    done
    mapfile -t nodes < <(json_nodes 4 '{plugin: $f[0], status: $f[1], note: $f[2], path: $f[3]}' ${fields+"${fields[@]}"})
    printf '  "plugins": ['
    print_nodes ${nodes+"${nodes[@]}"}
    printf '\n  ],\n'
    fields=()
    for d in ${DIVERGENCE+"${DIVERGENCE[@]}"}; do
      IFS=$'\t' read -r dk dl dc <<<"$d"
      fields+=("$dk" "$dl" "$dc")
    done
    mapfile -t nodes < <(json_nodes 3 '{plugin: $f[0], loaded: $f[1], cached: $f[2]}' ${fields+"${fields[@]}"})
    printf '  "divergence": ['
    print_nodes ${nodes+"${nodes[@]}"}
    printf '\n  ],\n'
    # A lever value that parses as JSON other than false or null is that JSON;
    # anything else is the text as read.
    fields=()
    for l in ${LEVERS+"${LEVERS[@]}"}; do
      IFS=$'\t' read -r sc lk lv <<<"$l"
      fields+=("$sc" "$lk" "$lv")
    done
    mapfile -t nodes < <(json_nodes 3 '($f[2] | try fromjson catch null) as $v
      | {scope: $f[0], key: $f[1], value: (if $v == null or $v == false then $f[2] else $v end)}' ${fields+"${fields[@]}"})
    printf '  "levers": ['
    print_nodes ${nodes+"${nodes[@]}"}
    printf '\n  ],\n'
    fields=()
    for l in ${MOD_PLANE+"${MOD_PLANE[@]}"}; do
      IFS=$'\t' read -r sc mk mv <<<"$l"
      fields+=("$sc" "$mk" "$mv")
    done
    mapfile -t nodes < <(json_nodes 3 '{scope: $f[0], key: $f[1], value: ($f[2] | fromjson)}' ${fields+"${fields[@]}"})
    printf '  "mod_plane": ['
    print_nodes ${nodes+"${nodes[@]}"}
    printf '\n  ],\n'
    mapfile -t nodes < <(json_nodes 1 '$f[0]' ${UNREADABLE+"${UNREADABLE[@]}"})
    printf '  "unreadable": ['
    print_nodes ${nodes+"${nodes[@]}"}
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
  if [[ ${#MOD_PLANE[@]} -gt 0 ]]; then
    echo "Mod-plane keys set:"
    for l in "${MOD_PLANE[@]}"; do
      IFS=$'\t' read -r sc mk mv <<<"$l"
      printf '  %-8s %-32s %s\n' "$sc" "$mk" "$mv"
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
