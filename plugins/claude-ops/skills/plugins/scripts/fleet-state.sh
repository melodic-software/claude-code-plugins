#!/usr/bin/env bash
# Read-only plugin-fleet state inspection for the `plugins` skill.
#
# Reads CC's own internal plugin-state files (installed_plugins.json,
# known_marketplaces.json, a marketplace's own marketplace.json,
# enabledPlugins across user/project/local settings scopes) and emits one
# JSON object describing catalog completeness, install completeness, and
# scope divergence for a marketplace. NEVER writes any of these files — every
# mutation this skill performs goes through the `claude plugin` CLI, never
# this script.
#
# Usage:
#   fleet-state.sh [--marketplace <name> | --all]
#
# With neither flag, resolves the default marketplace dynamically: the one
# this plugin (CLAUDE_PLUGIN_ROOT) was itself installed from. `--all` sweeps
# every marketplace in known_marketplaces.json; a per-marketplace failure is
# reported inline and does not abort the sweep.
#
# Output (stdout): one JSON object.
#   Single marketplace: {marketplace, catalog, installed, enabled,
#     missing_from_install, missing_from_user_install, missing_from_enabled,
#     divergences}
#     — or {marketplace: {name, error}} on a resolvable per-marketplace failure.
#   missing_from_install is all-scope (catalog minus installed anywhere);
#   missing_from_user_install is user-scope only (catalog minus user-scope
#   installed), the signal `sync` Step 4 uses to keep every plugin usable from
#   any directory. Both exclude ids explicitly opted out (false) in any scope.
#   --all: {marketplaces: {"<name>": <single-marketplace shape>, ...}}
#
# Exit codes:
#   0  ran to completion (individual marketplace failures are reported in the
#      JSON body, not the exit code, so an --all sweep with partial failures
#      still exits 0)
#   1  a single-marketplace run's marketplace could not be resolved/read
#   2  fatal: jq missing, or an internal CC state file is present but does not
#      match its expected shape (fail loud on schema drift — never guess)
#
# Env overrides (testing only; production uses the real paths):
#   FLEET_STATE_INSTALLED_JSON     — path to installed_plugins.json
#   FLEET_STATE_MARKETPLACES_JSON  — path to known_marketplaces.json
#   FLEET_STATE_USER_SETTINGS      — path to the user-scope settings.json
#   FLEET_STATE_CATALOG_DIR        — dir of <marketplace>.json catalog
#                                     fixtures, read instead of each
#                                     marketplace's installLocation clone
#
# Real env vars this script honors (set by Claude Code, not test-only):
#   CLAUDE_PLUGIN_ROOT   — this plugin's own install dir; used to self-resolve
#                          the default marketplace when neither flag is given
#   CLAUDE_PROJECT_DIR   — current project root; authoritative when set, for
#                          project/local scope settings and the
#                          `currentProject` install flag. Falls back to the
#                          cwd's git toplevel when unset (verified empirically
#                          not reliably exported in every invocation context).

set -uo pipefail

# Resolve this script's own directory using only shell builtins and parameter
# expansion — nothing external — because the result feeds the `source` below.
# An inherited environment can subvert an external resolver two ways: an
# exported shell function named cd/pwd (bash imports it before the script runs),
# or a PATH prefixed with an attacker's dirname binary. `builtin cd`/`builtin
# pwd` bypass the function-export channel; deriving the directory with
# `${BASH_SOURCE[0]%/*}` instead of `dirname` keeps resolution PATH-independent,
# so the plugin-shipped hook-utils.sh is always sourced from this script's real
# location regardless of a hostile environment.
script_src="${BASH_SOURCE[0]}"
case "$script_src" in
*/*) script_src_dir="${script_src%/*}" ;;
*) script_src_dir="." ;;
esac
SCRIPT_DIR="$(builtin cd "$script_src_dir" && builtin pwd)"
PLUGIN_ROOT_DEFAULT="$(builtin cd "$SCRIPT_DIR/../../.." && builtin pwd)"

# hook-utils.sh is a fixed sibling shipped with this plugin. Resolve it only
# from this script's own location — never from a caller-supplied env var — so
# no inherited or hostile environment can redirect `source` at an arbitrary
# file. CLAUDE_PLUGIN_ROOT is deliberately not consulted here (it equals the
# script-relative root in production, and is set to a fake value by tests
# exercising marketplace self-resolution).
HOOK_UTILS="$PLUGIN_ROOT_DEFAULT/hooks/hook-utils.sh"
if [[ -f "$HOOK_UTILS" ]]; then
  # `builtin source` so an inherited environment exporting a shell function
  # named `source` (BASH_FUNC_source%%) cannot shadow the builtin and ignore
  # the correctly resolved path — the resolution above would otherwise be moot.
  # shellcheck source=/dev/null
  builtin source "$HOOK_UTILS"
else
  echo "ERROR: hook-utils.sh not found at $HOOK_UTILS" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required (install with: winget install jqlang.jq | apt install jq | brew install jq)" >&2
  exit 2
fi

# Some native-Windows jq builds CRLF-terminate every line, including
# single-line compact output. `$(...)` strips only the trailing LF, so a
# stray CR survives at the end of a captured value and corrupts it once
# re-parsed as JSON via --argjson. Route every call through this wrapper
# instead of calling jq directly so no call site has to remember this.
jq() { command jq "$@" | tr -d '\r'; }

INSTALLED_JSON="${FLEET_STATE_INSTALLED_JSON:-$HOME/.claude/plugins/installed_plugins.json}"
MARKETPLACES_JSON="${FLEET_STATE_MARKETPLACES_JSON:-$HOME/.claude/plugins/known_marketplaces.json}"
USER_SETTINGS="${FLEET_STATE_USER_SETTINGS:-$HOME/.claude/settings.json}"

# --- Fail-loud shape validation for internal (undocumented) CC state -------
# These files are CC-internal, not a published contract. A shape drift means
# our assumptions are stale — better to fail loud here than silently emit an
# empty or wrong report.

require_json() {
  local path="$1" label="$2"
  [[ -f "$path" ]] || {
    echo "ERROR: $label not found: $path" >&2
    exit 2
  }
  jq empty "$path" 2>/dev/null || {
    echo "ERROR: $label is not valid JSON: $path" >&2
    exit 2
  }
}

require_json "$INSTALLED_JSON" "installed_plugins.json"
if [[ "$(jq -r 'has("plugins") and (.plugins | type == "object") and (.plugins | to_entries | all(.value | type == "array"))' "$INSTALLED_JSON")" != "true" ]]; then
  echo "ERROR: installed_plugins.json does not match the expected {plugins: {<id>: [...]}} shape: $INSTALLED_JSON" >&2
  exit 2
fi

require_json "$MARKETPLACES_JSON" "known_marketplaces.json"
if [[ "$(jq -r 'type == "object"' "$MARKETPLACES_JSON")" != "true" ]]; then
  echo "ERROR: known_marketplaces.json is not a JSON object: $MARKETPLACES_JSON" >&2
  exit 2
fi

# --- Resolve the current project root ---------------------------------------
# CLAUDE_PROJECT_DIR is authoritative when set — it's the project Claude Code
# itself is anchored to, which can legitimately differ from cwd's git
# toplevel (e.g. a Bash call from a subdirectory, or a repo nested inside
# another). But it is NOT reliably exported to every invocation context
# (verified empirically: absent in a real headless `-p` session run from
# inside a project directory) — fall back to the cwd's git toplevel, then
# bare $PWD, rather than silently losing project context.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
fi
[[ -n "$PROJECT_ROOT" ]] || PROJECT_ROOT="$PWD"

# --- Effective enabledPlugins (raw per-scope + merged local>project>user) --

user_map='{}'
[[ -f "$USER_SETTINGS" ]] && user_map=$(jq -c '.enabledPlugins // {}' "$USER_SETTINGS")

project_map='{}'
local_map='{}'
if [[ -n "$PROJECT_ROOT" ]]; then
  [[ -f "$PROJECT_ROOT/.claude/settings.json" ]] &&
    project_map=$(jq -c '.enabledPlugins // {}' "$PROJECT_ROOT/.claude/settings.json")
  [[ -f "$PROJECT_ROOT/.claude/settings.local.json" ]] &&
    local_map=$(jq -c '.enabledPlugins // {}' "$PROJECT_ROOT/.claude/settings.local.json")
fi

# Union of every id ever mentioned in any scope (raw, unmerged) — used to
# distinguish "never mentioned anywhere" (missing_from_enabled) from
# "explicitly false somewhere" (deliberate opt-out, never flipped by sync).
known_ids=$(jq -cn --argjson u "$user_map" --argjson p "$project_map" --argjson l "$local_map" \
  '($u + $p + $l) | keys')

# Effective value per id: local > project > user.
effective_map=$(jq -cn --argjson u "$user_map" --argjson p "$project_map" --argjson l "$local_map" \
  '$u + $p + $l')

# ids explicitly set to false in ANY scope — a deliberate opt-out, even for a
# plugin never installed at all (e.g. a team pre-declares "we're not using
# this" in project settings before anyone runs install). "Missing" (needing
# an install prompt) excludes these; sync never installs over an opt-out.
explicit_false_ids=$(jq -cn --argjson u "$user_map" --argjson p "$project_map" --argjson l "$local_map" \
  '[($u, $p, $l) | to_entries[] | select(.value == false) | .key] | unique')

# --- Normalized current-project root, for the `currentProject` install flag
current_project_norm=""
if [[ -n "$PROJECT_ROOT" ]]; then
  current_project_norm=$(hook::normalize_path "$(hook::physical_path "$PROJECT_ROOT")")
  current_project_norm="${current_project_norm%/}"
fi

# Case-fold path comparisons ONLY on case-insensitive filesystems (mirrors
# hook::normalize_path's own $OSTYPE check exactly). Applying ascii_downcase
# unconditionally — as an earlier version of this script did — makes two
# genuinely different sibling repos on a case-sensitive POSIX host (e.g.
# /work/repo and /work/Repo) compare equal, which can point a project-scope
# mutation at the wrong repo.
case_insensitive_os="false"
case "${OSTYPE:-}" in
msys* | cygwin* | win32) case_insensitive_os="true" ;;
*) ;;
esac

# --- Resolve default marketplace: the one this plugin was installed from ---
resolve_default_marketplace() {
  local plugin_root norm_root
  plugin_root="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT_DEFAULT}"
  norm_root=$(hook::normalize_path "$(hook::physical_path "$plugin_root")")
  norm_root="${norm_root%/}"
  jq -r --arg root "$norm_root" --argjson ci "$case_insensitive_os" '
    .plugins
    | to_entries[]
    | select(.value[] | (.installPath // "" | gsub("\\\\";"/")) as $p |
             if $ci then ($p | ascii_downcase) == ($root | ascii_downcase) else $p == $root end)
    | .key
  ' "$INSTALLED_JSON" | head -1 | sed 's/.*@//'
}

# --- Emit one marketplace's state object ------------------------------------
# Args: marketplace name. Prints a JSON object on stdout; on a resolvable
# per-marketplace failure prints {marketplace:{name,error}} and returns 1
# (caller decides whether that is fatal for this invocation).
emit_marketplace() {
  local name="$1"
  local mp_entry auto_update last_updated install_location catalog_json

  mp_entry=$(jq -c --arg n "$name" '.[$n] // empty' "$MARKETPLACES_JSON")
  if [[ -z "$mp_entry" ]]; then
    jq -cn --arg n "$name" '{marketplace: {name: $n, error: "not found in known_marketplaces.json"}}'
    return 1
  fi
  auto_update=$(jq -r '.autoUpdate // false' <<<"$mp_entry")
  last_updated=$(jq -r '.lastUpdated // ""' <<<"$mp_entry")
  install_location=$(jq -r '.installLocation // ""' <<<"$mp_entry")

  if [[ -n "${FLEET_STATE_CATALOG_DIR:-}" ]]; then
    local fixture="$FLEET_STATE_CATALOG_DIR/$name.json"
    if [[ ! -f "$fixture" ]]; then
      jq -cn --arg n "$name" --argjson au "$([[ "$auto_update" == "true" ]] && echo true || echo false)" --arg lu "$last_updated" \
        '{marketplace: {name: $n, autoUpdate: $au, lastUpdated: $lu, error: "no catalog fixture"}}'
      return 1
    fi
    catalog_json="$fixture"
  else
    catalog_json="$install_location/.claude-plugin/marketplace.json"
    if [[ ! -f "$catalog_json" ]]; then
      jq -cn --arg n "$name" --argjson au "$([[ "$auto_update" == "true" ]] && echo true || echo false)" --arg lu "$last_updated" \
        '{marketplace: {name: $n, autoUpdate: $au, lastUpdated: $lu, error: "marketplace.json not found at installLocation"}}'
      return 1
    fi
  fi

  # Not require_json: that helper exit-2's the whole process, appropriate for
  # the two prerequisite files this script cannot run without at all. A single
  # marketplace's catalog being malformed is a per-marketplace failure like
  # the branches above — report it inline and return 1 so one corrupt clone
  # doesn't abort an --all sweep of every other marketplace.
  if ! jq empty "$catalog_json" 2>/dev/null; then
    jq -cn --arg n "$name" --argjson au "$([[ "$auto_update" == "true" ]] && echo true || echo false)" --arg lu "$last_updated" \
      '{marketplace: {name: $n, autoUpdate: $au, lastUpdated: $lu, error: "marketplace.json is not valid JSON"}}'
    return 1
  fi
  local catalog
  catalog=$(jq -c '[.plugins[]?.name // empty] | unique' "$catalog_json")

  local catalog_ids
  catalog_ids=$(jq -c --arg mp "$name" '[.[] | . + "@" + $mp]' <<<"$catalog")

  # Ids the marketplace entry ships with defaultEnabled:false — a publisher's
  # deliberate opt-in-required default (takes precedence over the plugin's own
  # plugin.json field; see plugins-reference.md's "Default enablement"). No
  # enabledPlugins entry anywhere for one of these is the INTENDED state, not
  # a completeness gap — never auto-enable it.
  local default_disabled_ids
  default_disabled_ids=$(jq -c --arg mp "$name" \
    '[.plugins[]? | select(.defaultEnabled == false) | .name + "@" + $mp]' "$catalog_json")

  # Every install record for ids in this marketplace, flattened, with the
  # currentProject flag Windows-normalized on both sides.
  local installed
  installed=$(jq -c --arg suffix "@$name" --arg cur "$current_project_norm" --argjson ci "$case_insensitive_os" '
    .plugins
    | to_entries[]
    | select(.key | endswith($suffix))
    | .key as $id
    | .value[]
    | {
        id: $id,
        scope: .scope,
        version: .version,
        projectPath: (.projectPath // null),
        currentProject: (
          if (.scope == "project" or .scope == "local") and (.projectPath // "" | length) > 0 and ($cur | length) > 0 then
            (.projectPath | gsub("\\\\";"/")) as $p |
            if $ci then ($p | ascii_downcase) == ($cur | ascii_downcase) else $p == $cur end
          else null end
        )
      }
  ' "$INSTALLED_JSON" | jq -cs '.')

  local installed_ids
  installed_ids=$(jq -c '[.[].id] | unique' <<<"$installed")

  # catalog minus installed minus any id explicitly opted out (false) in any
  # scope, even one never installed at all.
  local missing_from_install
  missing_from_install=$(jq -cn \
    --argjson catalog "$catalog_ids" \
    --argjson installed "$installed_ids" \
    --argjson falseIds "$explicit_false_ids" \
    '($catalog - $installed) - $falseIds')

  # User-scope completeness, distinct from all-scope missing_from_install: a
  # plugin installed only at project/local scope is present all-scope but not
  # usable from other directories, so `sync` Step 4 (which installs at user
  # scope for the "usable from any directory" guarantee) must key off this, not
  # missing_from_install. Same opt-out exclusion as above.
  local user_installed_ids
  user_installed_ids=$(jq -c '[.[] | select(.scope == "user") | .id] | unique' <<<"$installed")

  local missing_from_user_install
  missing_from_user_install=$(jq -cn \
    --argjson catalog "$catalog_ids" \
    --argjson userInstalled "$user_installed_ids" \
    --argjson falseIds "$explicit_false_ids" \
    '($catalog - $userInstalled) - $falseIds')

  local known_at_mp
  known_at_mp=$(jq -c --arg suffix "@$name" '[.[] | select(endswith($suffix))]' <<<"$known_ids")

  # missing_from_enabled can only be computed for ids whose enabledPlugins
  # this invocation can actually read: user scope (global) and the current
  # PROJECT_ROOT's project/local scope. A project/local install belonging to
  # a DIFFERENT repo is excluded rather than asserted missing — its own
  # settings files live in that repo and are never read here, so treating an
  # unread file as "never mentioned" would false-positive on every already-
  # enabled install elsewhere on the machine (and could later steer a mutation
  # at the wrong repo).
  local verifiable_ids
  verifiable_ids=$(jq -c '[.[] | select(.scope == "user" or .currentProject == true) | .id] | unique' <<<"$installed")

  local missing_from_enabled
  missing_from_enabled=$(jq -cn --argjson verifiable_ids "$verifiable_ids" --argjson known "$known_at_mp" \
    --argjson defaultDisabled "$default_disabled_ids" \
    '($verifiable_ids - $known) - $defaultDisabled')

  local enabled_at_mp
  enabled_at_mp=$(jq -cn --argjson known "$known_at_mp" --argjson eff "$effective_map" \
    'reduce $known[] as $id ({}; . + {($id): $eff[$id]})')

  # `versionsMatch` separates a benign multi-scope install (project and user
  # scope both pinned to the same version — normal, not actionable) from a
  # real version skew (some scope is behind another — the "run converge"
  # signal). A record count alone conflates the two.
  local divergences
  divergences=$(jq -c '
    group_by(.id)
    | map(select(length > 1))
    | map({
        id: .[0].id,
        scopes: map({scope, version, projectPath}),
        versionsMatch: ((map(.version) | unique | length) == 1)
      })
  ' <<<"$installed")

  jq -cn \
    --arg name "$name" \
    --argjson autoUpdate "$([[ "$auto_update" == "true" ]] && echo true || echo false)" \
    --arg lastUpdated "$last_updated" \
    --argjson catalog "$catalog" \
    --argjson installed "$installed" \
    --argjson enabled "$enabled_at_mp" \
    --argjson missingInstall "$missing_from_install" \
    --argjson missingUserInstall "$missing_from_user_install" \
    --argjson missingEnabled "$missing_from_enabled" \
    --argjson divergences "$divergences" \
    '{
      marketplace: {name: $name, autoUpdate: $autoUpdate, lastUpdated: $lastUpdated},
      catalog: $catalog,
      installed: $installed,
      enabled: $enabled,
      missing_from_install: $missingInstall,
      missing_from_user_install: $missingUserInstall,
      missing_from_enabled: $missingEnabled,
      divergences: $divergences
    }'
}

# --- Arg parsing -------------------------------------------------------------

MODE="default"
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --marketplace)
    MODE="single"
    TARGET="${2:-}"
    # Guard here, before `shift 2`: with no following arg only one positional
    # param remains, `shift 2` fails (no set -e), $1 stays "--marketplace", and
    # the loop spins forever — the post-loop empty check is never reached.
    if [[ -z "$TARGET" ]]; then
      echo "ERROR: --marketplace requires a name" >&2
      exit 2
    fi
    shift 2
    ;;
  --all)
    MODE="all"
    shift
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

case "$MODE" in
default)
  TARGET=$(resolve_default_marketplace)
  if [[ -z "$TARGET" ]]; then
    echo "ERROR: could not resolve the default marketplace (this plugin's CLAUDE_PLUGIN_ROOT was not found in installed_plugins.json). Pass --marketplace <name> explicitly." >&2
    exit 1
  fi
  emit_marketplace "$TARGET" || exit 1
  ;;
single)
  emit_marketplace "$TARGET" || exit 1
  ;;
all)
  names=$(jq -r 'keys[]' "$MARKETPLACES_JSON")
  result='{}'
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    block=$(emit_marketplace "$n" || true)
    result=$(jq -c --arg n "$n" --argjson b "$block" '. + {($n): $b}' <<<"$result")
  done <<<"$names"
  jq -cn --argjson m "$result" '{marketplaces: $m}'
  ;;
*)
  echo "ERROR: unreachable mode: $MODE" >&2
  exit 2
  ;;
esac
