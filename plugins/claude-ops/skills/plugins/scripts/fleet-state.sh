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
#   fleet-state.sh [--marketplace <name>] --ids <selector>
#   fleet-state.sh --marketplaces
#
# With neither flag, resolves the default marketplace dynamically: the one
# this plugin (CLAUDE_PLUGIN_ROOT) was itself installed from. `--all` sweeps
# every marketplace in known_marketplaces.json; a per-marketplace failure is
# reported inline and does not abort the sweep.
#
# Output (stdout): one JSON object.
#   Single marketplace: {marketplace, project_root, catalog, installed,
#     enabled, missing_from_install, missing_from_user_install,
#     missing_from_enabled, divergences}
#     — or {marketplace: {name, error}} on a resolvable per-marketplace failure.
#   project_root is the resolved PROJECT_ROOT as a string, or null when no
#   project context resolved at all. It disambiguates the tri-state that
#   `--ids current-project` alone collapses: that selector matches
#   currentProject == true, so "no project context" (every flag null) and
#   "project context but zero in-repo installs" (flags false) both project to
#   zero ids — a consumer needs project_root to tell "the primary value path
#   did not run" apart from "it ran and found nothing".
#   Each installed[] record carries {id, scope, version, projectPath,
#   currentProject, projectPathExists}. projectPathExists is true/false from a
#   directory-existence test on the recorded projectPath, or null when
#   projectPath is null (user-scope records).
#   missing_from_install is all-scope (catalog minus installed anywhere);
#   missing_from_user_install is user-scope only (catalog minus user-scope
#   installed), the signal `sync` Step 4 uses to keep every plugin usable from
#   any directory. Both exclude ids explicitly opted out (false) in any scope.
#   --all: {marketplaces: {"<name>": <single-marketplace shape>, ...}}
#
# Output (stdout) with --ids <selector>: NOT JSON — one record per line, in the
#   order the block carries them, and nothing else. Fields are TAB-separated and
#   the first field is always the fully-qualified `<name>@<marketplace>` id, so
#   `while IFS=$'\t' read -r id …` reads every selector. Selectors, each naming
#   the `sync` step that consumes it:
#     installed-user        installed[] at user scope           (Step 3 update)
#                             fields: id
#     current-project       installed[] with currentProject     (Step 2 update)
#                             fields: id, scope — scope is carried because one
#                             plugin can hold both a project- and a local-scope
#                             record for the same repo, so the id alone would
#                             appear twice and pick the wrong `-s` flag
#     missing-user-install  missing_from_user_install[]         (Step 4 install)
#                             fields: id
#     missing-enabled       missing_from_enabled[]              (Step 5 enable)
#                             fields: id
#     stale-user            installed[] at user scope NOT       (Step 3 update)
#                             confirmed current with the local marketplace
#                             checkout's catalog version
#                             fields: id — see emit_stale_user_ids for the
#                             fail-open resolution rules
#   Zero matches is success with empty output (exit 0), not an error. Reject:
#   `--ids` with `--all` (no single block to project), or an unknown selector.
#   A per-marketplace failure block goes to STDERR in this mode (never stdout),
#   so stdout carries records or nothing — a `< <(… --ids …)` consumer cannot
#   see the process's exit status and would otherwise read the error JSON as an
#   id. This mode exists so a caller never hand-writes `jq -r ... | while read`
#   — on Windows that reintroduces a CR and corrupts every id but the last. See
#   the emit_ids comment and context/gotchas.md.
#
# Output (stdout) with --marketplaces: NOT JSON — every marketplace name from
#   known_marketplaces.json, one per line, nothing else, CR-free by the same
#   mechanism as --ids. Empty output for an empty object is success (exit 0).
#   A standalone mode: combining it with --marketplace, --all, or --ids is a
#   usage error (exit 2). Exists so `sync`'s all-marketplace mode can iterate
#   `--marketplace <name> --ids <selector>` per name without hand-writing its
#   own `jq -r 'keys[]' | while read` over the JSON — the exact Windows-CRLF
#   corruption the --ids contract above exists to prevent.
#
# Exit codes:
#   0  ran to completion (individual marketplace failures are reported in the
#      JSON body, not the exit code, so an --all sweep with partial failures
#      still exits 0)
#   1  a single-marketplace run's marketplace could not be resolved/read
#   2  fatal: jq missing, an internal CC state file is present but does not
#      match its expected shape (fail loud on schema drift — never guess), a
#      bad/absent --ids selector, or --ids combined with --all
#
# Env overrides (testing only; production uses the real paths):
#   FLEET_STATE_INSTALLED_JSON     — path to installed_plugins.json
#   FLEET_STATE_MARKETPLACES_JSON  — path to known_marketplaces.json
#   FLEET_STATE_USER_SETTINGS      — path to the user-scope settings.json
#   FLEET_STATE_CATALOG_DIR        — dir of <marketplace>.json catalog
#                                     fixtures, read instead of each
#                                     marketplace's installLocation clone.
#                                     Replaces the marketplace.json CATALOG
#                                     file only: the per-plugin manifests
#                                     stale-user reads still resolve under the
#                                     real installLocation recorded in
#                                     known_marketplaces.json, so a fixture
#                                     that exercises stale-user must point
#                                     installLocation at a real directory
#                                     carrying <source-path>/.claude-plugin/
#                                     plugin.json files
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

# Resolve this script's own directory with parameter expansion and no external
# process, because the result feeds the `source` below. Deriving the directory
# with `${BASH_SOURCE[0]%/*}` instead of `dirname` keeps resolution
# PATH-independent (no attacker-planted `dirname` binary in the loop), and the
# `builtin cd`/`builtin pwd` prefixes bypass an inherited exported `cd`/`pwd`
# function. This is defense against the common cd/pwd/dirname channels, not a
# guarantee against a fully attacker-controlled environment: an exported
# `BASH_FUNC_builtin%%` shadows `builtin` itself, and `BASH_ENV` runs before
# this script's first line — both sit at the same environment-trust boundary as
# the PATH-resolved jq/git/tr used later, out of scope for an in-script fix.
script_src="${BASH_SOURCE[0]}"
case "$script_src" in
*/*) script_src_dir="${script_src%/*}" ;;
*) script_src_dir="." ;;
esac
SCRIPT_DIR="$(builtin cd "$script_src_dir" && builtin pwd)"
PLUGIN_ROOT_DEFAULT="$(builtin cd "$SCRIPT_DIR/../../.." && builtin pwd)"

# hook-utils.sh is a fixed sibling shipped with this plugin. Resolve it from
# this script's own location, never from a caller-supplied env var, so a stray
# FLEET_STATE_* override cannot redirect `source` at an arbitrary file.
# CLAUDE_PLUGIN_ROOT is deliberately not consulted here (it equals the
# script-relative root in production, and is set to a fake value by tests
# exercising marketplace self-resolution).
HOOK_UTILS="$PLUGIN_ROOT_DEFAULT/hooks/hook-utils.sh"
if [[ -f "$HOOK_UTILS" ]]; then
  # `builtin source` bypasses an inherited exported `source` function
  # (BASH_FUNC_source%%). Like the resolution above this covers the common
  # single-function shadow, not a shadowed `builtin` or BASH_ENV — see the
  # environment-trust boundary noted there.
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

# --- Large-JSON routing: temp file instead of argv (#1336) ------------------
# `jq --argjson name "$value"` embeds $value as a literal command-line
# argument. Several call sites below carry a full marketplace catalog or the
# composed per-marketplace report; for a large enough marketplace (confirmed
# against a 273-plugin catalog) the serialized JSON exceeds this
# platform/shell's argv-length ceiling and jq fails with "Argument list too
# long" (confirmed on Windows Git Bash/MSYS jq) — a real OS ARG_MAX ceiling
# everywhere, just reached sooner here. jq_slurp_tmpfile writes a JSON value
# to a fresh temp file and prints its path so a call site can pass
# `--slurpfile name "$(jq_slurp_tmpfile "$value")"` instead of
# `--argjson name "$value"`; payload then travels through the filesystem,
# never argv, so its size never determines whether jq can be invoked.
# --slurpfile always yields a one-element array bound to $name, so a
# converted jq program reads `$name[0]` where it used to read `$name`.
# Process substitution (`<(...)`) was considered instead of a real temp file,
# but a native-Windows jq binary does not reliably read the /dev/fd-style
# paths Git Bash's process substitution produces, so a real file backed by
# `mktemp` is the portable choice. Every call site invokes jq_slurp_tmpfile
# inside a `$(...)` command substitution (to capture the printed path), which
# runs the function in a SUBSHELL — an array append inside it would mutate
# only the subshell's copy and vanish on return (the same pitfall
# fleet-state.test.sh's own new_case_dir doc comment calls out for CASE_NUM),
# so temp files are NOT individually tracked in an array. Instead every one
# of them is created inside a single per-run temp directory, and the EXIT
# trap removes that whole directory — a subshell-safe cleanup that needs no
# shared mutable state, on every exit path (normal completion, `exit`, or an
# unhandled error under `set -u`).
_FLEET_STATE_TMPDIR="$(mktemp -d)" || {
  echo "ERROR: could not create a temp directory for large-JSON routing" >&2
  exit 2
}
trap 'rm -rf "$_FLEET_STATE_TMPDIR"' EXIT

jq_slurp_tmpfile() {
  local f
  f=$(mktemp "$_FLEET_STATE_TMPDIR/payload.XXXXXX") || return 1
  if [[ -z "$1" ]]; then
    # An empty value only happens when an earlier `jq` read of a source file
    # (e.g. user/project/local settings.json) already failed — malformed
    # JSON captures no stdout. `--argjson name ""` used to fail this loud
    # immediately ("invalid JSON text passed to --argjson"); `--slurpfile`
    # tolerates a genuinely EMPTY file as "zero JSON values" instead of
    # erroring, which would silently degrade the report (a null/empty field
    # instead of the script failing) rather than reproducing the prior
    # fail-loud behavior. Write a deliberately-invalid token so the
    # consuming jq call's own parser still errors at this call site.
    printf '%s' 'FLEET_STATE_INVALID_EMPTY_PAYLOAD' >"$f"
  else
    printf '%s' "$1" >"$f"
  fi
  printf '%s' "$f"
}

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
# inside a project directory) — fall back to the cwd's git toplevel.
#
# A third, corroborated source covers the non-Git project: Claude Code does
# not require a repo, so a headless session anchored in a plain directory has
# neither the env var nor a git toplevel, yet its `.claude/settings*.json` and
# install records are real project state that Step 2/Step 5 must not skip. The
# corroboration is a `.claude` directory at cwd — evidence Claude was anchored
# HERE, not a bare-$PWD guess that would manufacture project context for any
# directory. $HOME is excluded even when it carries `.claude`: that directory
# is USER scope, and reading $HOME/.claude/settings.json as the "project" map
# would duplicate the user map. A cwd with no `.claude` stays an empty root —
# the honest answer, and every consumer below already guards for it.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
fi
if [[ -z "$PROJECT_ROOT" && -d "$PWD/.claude" ]]; then
  # `pwd -W` (Git Bash) yields the native drive-letter spelling — the form
  # CC-written projectPath records carry. A raw MSYS mount alias like /tmp
  # resolves to a different string than the record even after normalization,
  # so the native spelling is taken where the shell can produce it.
  cwd_native=$(builtin pwd -W 2>/dev/null) || cwd_native="$PWD"
  [[ -n "$cwd_native" ]] || cwd_native="$PWD"
  # Both sides of the $HOME comparison are spelled by `pwd -W`. Normalizing
  # `$HOME` as given compares a native path against whatever spelling the
  # environment happens to carry, and an MSYS MOUNT ALIAS has no drive letter
  # for the normalizer to reconcile: `$HOME=/tmp/x` never equals the `C:/…`
  # `pwd -W` reports for that same directory, so the exclusion silently failed
  # and $HOME became project context — the one outcome this block exists to
  # prevent. Spelling both sides through the same command is what makes them
  # comparable; normalizing harder cannot, since the two inputs disagree before
  # the normalizer sees them.
  home_norm=""
  # `builtin` on both, matching this script's existing shadow discipline: an
  # exported `cd` function that returns success WITHOUT changing directory would
  # otherwise make home_native the cwd, so every corroborated non-git project
  # would compare equal to $HOME and lose its project settings entirely.
  if [[ -n "${HOME:-}" && -d "$HOME" ]]; then
    home_native=$(builtin cd "$HOME" 2>/dev/null && { builtin pwd -W 2>/dev/null || builtin pwd; })
    [[ -n "$home_native" ]] || home_native="$HOME"
    home_norm=$(hook::normalize_path "$(hook::physical_path "$home_native")")
  fi
  [[ "$(hook::normalize_path "$(hook::physical_path "$cwd_native")")" != "$home_norm" ]] &&
    PROJECT_ROOT="$cwd_native"
fi

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

# The three scope maps feed three jq programs below. Route each one through the
# filesystem ONCE and reuse the path: jq_slurp_tmpfile is a mktemp + write per
# call, and re-deriving the same three payloads for every program paid that nine
# times for three distinct values.
user_map_f="$(jq_slurp_tmpfile "$user_map")"
project_map_f="$(jq_slurp_tmpfile "$project_map")"
local_map_f="$(jq_slurp_tmpfile "$local_map")"

# Union of every id ever mentioned in any scope (raw, unmerged) — used to
# distinguish "never mentioned anywhere" (missing_from_enabled) from
# "explicitly false somewhere" (deliberate opt-out, never flipped by sync).
known_ids=$(jq -cn \
  --slurpfile u "$user_map_f" \
  --slurpfile p "$project_map_f" \
  --slurpfile l "$local_map_f" \
  '($u[0] + $p[0] + $l[0]) | keys')

# Effective value per id: local > project > user.
effective_map=$(jq -cn \
  --slurpfile u "$user_map_f" \
  --slurpfile p "$project_map_f" \
  --slurpfile l "$local_map_f" \
  '$u[0] + $p[0] + $l[0]')

# ids explicitly set to false in ANY scope — a deliberate opt-out, even for a
# plugin never installed at all (e.g. a team pre-declares "we're not using
# this" in project settings before anyone runs install). "Missing" (needing
# an install prompt) excludes these; sync never installs over an opt-out.
explicit_false_ids=$(jq -cn \
  --slurpfile u "$user_map_f" \
  --slurpfile p "$project_map_f" \
  --slurpfile l "$local_map_f" \
  '[($u[0], $p[0], $l[0]) | to_entries[] | select(.value == false) | .key] | unique')

# Marketplace-invariant, so it is routed once here rather than twice per
# marketplace inside emit_marketplace (which an --all sweep runs per entry).
explicit_false_ids_f="$(jq_slurp_tmpfile "$explicit_false_ids")"

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
# Two-stage match against installed_plugins.json's version-pinned installPath:
#   1. exact — installPath == this plugin's normalized root (the precise case).
#   2. version-agnostic fallback — installPath and the running root differ ONLY
#      by their trailing `/<version>` segment. This is common, not an edge case:
#      marketplace autoUpdate bumps the install shortly after session start while
#      the session keeps rendering the old version's skill, and `sync`'s own
#      Step 3 updates claude-ops itself — so every subsequent same-session call of
#      the bare (no --marketplace) default path would otherwise fail. The fallback
#      matches the version-stripped `…/cache/<marketplace>/<plugin>` prefix, which
#      still carries the marketplace (so two marketplaces shipping the same plugin
#      stay distinguishable). Takes the caller's already-normalized root as $1 so
#      the caller can reuse it in the error message (a var set here would be lost
#      across the `$(...)` the caller wraps this in).
resolve_default_marketplace() {
  local norm_root="$1" norm_root_parent result
  # Stage 1: exact installPath match.
  result=$(jq -r --arg root "$norm_root" --argjson ci "$case_insensitive_os" '
    .plugins
    | to_entries[]
    | select(.value[] | (.installPath // "" | gsub("\\\\";"/")) as $p |
             if $ci then ($p | ascii_downcase) == ($root | ascii_downcase) else $p == $root end)
    | .key
  ' "$INSTALLED_JSON" | head -1 | sed 's/.*@//')
  if [[ -n "$result" ]]; then
    printf '%s' "$result"
    return 0
  fi
  # Stage 2: version-agnostic parent-prefix match (survives mid-session skew).
  norm_root_parent="${norm_root%/*}"
  [[ -n "$norm_root_parent" && "$norm_root_parent" != "$norm_root" ]] || return 0
  jq -r --arg parent "$norm_root_parent" --argjson ci "$case_insensitive_os" '
    .plugins
    | to_entries[]
    | select(.value[] | (.installPath // "" | gsub("\\\\";"/") | rtrimstr("/") | sub("/[^/]*$";"")) as $pp |
             if $ci then ($pp | ascii_downcase) == ($parent | ascii_downcase) else $pp == $parent end)
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
  # `auto_update` is jq's own `true`/`false` text; normalize it to a JSON literal
  # once here rather than re-running the same `$([[ … ]] && echo …)` subshell at
  # each of the four --argjson call sites below.
  local auto_update_json=false
  [[ "$auto_update" == "true" ]] && auto_update_json=true

  if [[ -n "${FLEET_STATE_CATALOG_DIR:-}" ]]; then
    local fixture="$FLEET_STATE_CATALOG_DIR/$name.json"
    if [[ ! -f "$fixture" ]]; then
      jq -cn --arg n "$name" --argjson au "$auto_update_json" --arg lu "$last_updated" \
        '{marketplace: {name: $n, autoUpdate: $au, lastUpdated: $lu, error: "no catalog fixture"}}'
      return 1
    fi
    catalog_json="$fixture"
  else
    catalog_json="$install_location/.claude-plugin/marketplace.json"
    if [[ ! -f "$catalog_json" ]]; then
      jq -cn --arg n "$name" --argjson au "$auto_update_json" --arg lu "$last_updated" \
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
    jq -cn --arg n "$name" --argjson au "$auto_update_json" --arg lu "$last_updated" \
      '{marketplace: {name: $n, autoUpdate: $au, lastUpdated: $lu, error: "marketplace.json is not valid JSON"}}'
    return 1
  fi
  local catalog
  catalog=$(jq -c '[.plugins[]?.name // empty] | unique' "$catalog_json")

  local catalog_ids catalog_ids_f
  catalog_ids=$(jq -c --arg mp "$name" '[.[] | . + "@" + $mp]' <<<"$catalog")
  # Routed once: both the all-scope and the user-scope completeness programs
  # below read the same catalog id list.
  catalog_ids_f="$(jq_slurp_tmpfile "$catalog_ids")"

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

  # projectPathExists: true/false from a directory test on the recorded
  # projectPath, null for the user-scope records that carry none. Exists so
  # converge/sync never emit `(cd "<projectPath>" && claude plugin …)` against
  # a directory that no longer exists — those commands can only fail, and no
  # CLI verb reaps such records (observed on the audited CC 2.1.240 run), so
  # they are report-only. jq cannot stat, so existence is computed here in
  # bash over the UNIQUE recorded paths (one probe per directory, not per
  # record) and fed back in as a path→bool map. The probe takes each path
  # verbatim: CC wrote it for this same machine, so whatever spelling the
  # record carries is the spelling `-d` must judge.
  local path_exists_map='{}' rec_path rec_exists
  while IFS= read -r rec_path; do
    [[ -n "$rec_path" ]] || continue
    rec_exists=false
    [[ -d "$rec_path" ]] && rec_exists=true
    path_exists_map=$(jq -c --arg p "$rec_path" --arg e "$rec_exists" \
      '. + {($p): ($e == "true")}' <<<"$path_exists_map")
  done <<<"$(jq -r '[.[].projectPath // empty] | unique | .[]' <<<"$installed")"
  installed=$(jq -c --slurpfile pe "$(jq_slurp_tmpfile "$path_exists_map")" \
    'map(. + {projectPathExists: (if .projectPath == null then null else $pe[0][.projectPath] end)})' \
    <<<"$installed")

  local installed_ids
  installed_ids=$(jq -c '[.[].id] | unique' <<<"$installed")

  # catalog minus installed minus any id explicitly opted out (false) in any
  # scope, even one never installed at all.
  local missing_from_install
  missing_from_install=$(jq -cn \
    --slurpfile catalog "$catalog_ids_f" \
    --slurpfile installed "$(jq_slurp_tmpfile "$installed_ids")" \
    --slurpfile falseIds "$explicit_false_ids_f" \
    '($catalog[0] - $installed[0]) - $falseIds[0]')

  # User-scope completeness, distinct from all-scope missing_from_install: a
  # plugin installed only at project/local scope is present all-scope but not
  # usable from other directories, so `sync` Step 4 (which installs at user
  # scope for the "usable from any directory" guarantee) must key off this, not
  # missing_from_install. Same opt-out exclusion as above.
  local user_installed_ids
  user_installed_ids=$(jq -c '[.[] | select(.scope == "user") | .id] | unique' <<<"$installed")

  local missing_from_user_install
  missing_from_user_install=$(jq -cn \
    --slurpfile catalog "$catalog_ids_f" \
    --slurpfile userInstalled "$(jq_slurp_tmpfile "$user_installed_ids")" \
    --slurpfile falseIds "$explicit_false_ids_f" \
    '($catalog[0] - $userInstalled[0]) - $falseIds[0]')

  local known_at_mp known_at_mp_f
  known_at_mp=$(jq -c --arg suffix "@$name" '[.[] | select(endswith($suffix))]' <<<"$known_ids")
  # Routed once: both the missing_from_enabled and enabled_at_mp programs read it.
  known_at_mp_f="$(jq_slurp_tmpfile "$known_at_mp")"

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
  missing_from_enabled=$(jq -cn \
    --slurpfile verifiable_ids "$(jq_slurp_tmpfile "$verifiable_ids")" \
    --slurpfile known "$known_at_mp_f" \
    --slurpfile defaultDisabled "$(jq_slurp_tmpfile "$default_disabled_ids")" \
    '($verifiable_ids[0] - $known[0]) - $defaultDisabled[0]')

  local enabled_at_mp
  enabled_at_mp=$(jq -cn \
    --slurpfile known "$known_at_mp_f" \
    --slurpfile eff "$(jq_slurp_tmpfile "$effective_map")" \
    'reduce $known[0][] as $id ({}; . + {($id): $eff[0][$id]})')

  # `versionsMatch` separates a benign multi-scope install (project and user
  # scope both pinned to the same version — normal, not actionable) from a
  # real version skew (some scope is behind another — the "run converge"
  # signal). A record count alone conflates the two. Each scope entry carries
  # projectPathExists so a converge command targeting a dead projectPath can
  # be withheld per-scope without a second lookup into installed[].
  local divergences
  divergences=$(jq -c '
    group_by(.id)
    | map(select(length > 1))
    | map({
        id: .[0].id,
        scopes: map({scope, version, projectPath, projectPathExists}),
        versionsMatch: ((map(.version) | unique | length) == 1)
      })
  ' <<<"$installed")

  # project_root is marketplace-invariant but emitted per block: an --all
  # consumer reads blocks independently, and the tri-state it disambiguates
  # (see the header contract) must travel with every block that carries the
  # currentProject flags it explains. Empty-string PROJECT_ROOT means no
  # project context resolved — surfaced as null, never "".
  jq -cn \
    --arg name "$name" \
    --argjson autoUpdate "$auto_update_json" \
    --arg lastUpdated "$last_updated" \
    --arg projectRoot "$PROJECT_ROOT" \
    --slurpfile catalog "$(jq_slurp_tmpfile "$catalog")" \
    --slurpfile installed "$(jq_slurp_tmpfile "$installed")" \
    --slurpfile enabled "$(jq_slurp_tmpfile "$enabled_at_mp")" \
    --slurpfile missingInstall "$(jq_slurp_tmpfile "$missing_from_install")" \
    --slurpfile missingUserInstall "$(jq_slurp_tmpfile "$missing_from_user_install")" \
    --slurpfile missingEnabled "$(jq_slurp_tmpfile "$missing_from_enabled")" \
    --slurpfile divergences "$(jq_slurp_tmpfile "$divergences")" \
    '{
      marketplace: {name: $name, autoUpdate: $autoUpdate, lastUpdated: $lastUpdated},
      project_root: (if $projectRoot == "" then null else $projectRoot end),
      catalog: $catalog[0],
      installed: $installed[0],
      enabled: $enabled[0],
      missing_from_install: $missingInstall[0],
      missing_from_user_install: $missingUserInstall[0],
      missing_from_enabled: $missingEnabled[0],
      divergences: $divergences[0]
    }'
}

# --- Id projection (--ids) ---------------------------------------------------

# Map an --ids selector to its jq filter, or fail. Single source of truth for
# BOTH the parse-time validation and the projection itself, so the accepted set
# can never drift between "what --ids rejects" and "what --ids can emit".
#
# `current-project` carries a SECOND tab-separated field, the record's scope,
# because Step 2 picks `-s project` vs `-s local` per record. It cannot be
# derived from the id afterwards: one plugin can hold BOTH a project- and a
# local-scope record for the same repo (the multi-scope case divergences[]
# exists to track), so an id-only projection would emit that id twice with
# nothing to tell the two lines apart.
ids_selector_filter() {
  case "$1" in
  installed-user) printf '%s' '.installed[]? | select(.scope == "user") | .id' ;;
  current-project) printf '%s' '.installed[]? | select(.currentProject == true) | "\(.id)\t\(.scope)"' ;;
  missing-user-install) printf '%s' '.missing_from_user_install[]?' ;;
  missing-enabled) printf '%s' '.missing_from_enabled[]?' ;;
  # stale-user's base projection carries the installed version alongside the
  # id because the projection alone cannot answer the selector: the catalog
  # side of the comparison lives in per-plugin manifest files on disk, which
  # jq cannot read from inside a filter. emit_ids routes these pairs through
  # emit_stale_user_ids, which does the manifest reads and emits ids only.
  # A null version interpolates as the literal string "null", which can never
  # equal a real catalog version — so a version-less record fails open into
  # the emitted set, per the selector's bias (see emit_stale_user_ids).
  stale-user) printf '%s' '.installed[]? | select(.scope == "user") | "\(.id)\t\(.version)"' ;;
  *)
    echo "ERROR: unknown --ids selector: $1" >&2
    echo "  expected one of: installed-user, current-project," >&2
    echo "                   missing-user-install, missing-enabled, stale-user" >&2
    return 1
    ;;
  esac
}

# Project the stale-user selector: the subset of user-scope installed ids (the
# installed-user population) NOT confirmed current with the local marketplace
# checkout's catalog version. Exists so `sync` Step 3 can skip `claude plugin
# update` for already-current plugins instead of sweeping every installed id
# with no-op calls. The catalog version for <name>@<mp> is read from the
# marketplace clone at <installLocation>/<source-path>/.claude-plugin/
# plugin.json — <source-path> from the catalog entry's `source` field when
# that is a relative-path string (the "./plugins/<name>" spelling), else the
# plugins/<name> layout default. Observed on the audited CC 2.1.240 run: this
# installed-vs-catalog comparison predicted exactly the 48 of 61 plugins that
# updated (0 false positives, 0 false negatives), with all 70 catalog
# manifests resolving locally, zero network.
#
# FAIL OPEN, every edge: an id is emitted whenever its catalog version cannot
# be resolved — missing installLocation, missing/unreadable/invalid manifest,
# non-string version, an object `source` whose local path cannot be derived.
# Only an id whose catalog version was read successfully AND equals the
# installed version is omitted. The asymmetry is deliberate: a wrongly-emitted
# id costs one no-op CLI call (safe); a wrongly-omitted id skips a real
# update (unsafe).
#
# Note FLEET_STATE_CATALOG_DIR replaces the catalog FILE only (see the env
# header): the per-plugin manifests here always resolve under the real
# installLocation from known_marketplaces.json.
emit_stale_user_ids() {
  local block="$1" filter="$2"
  local mp_name install_location catalog_json source_map='{}'
  mp_name=$(jq -r '.marketplace.name' <<<"$block")
  install_location=$(jq -r --arg n "$mp_name" '.[$n].installLocation // ""' "$MARKETPLACES_JSON")
  # Same catalog-file resolution as emit_marketplace, minus its error blocks:
  # here an unresolvable catalog is not a failure, it is "every id fails open".
  if [[ -n "${FLEET_STATE_CATALOG_DIR:-}" ]]; then
    catalog_json="$FLEET_STATE_CATALOG_DIR/$mp_name.json"
  else
    catalog_json="$install_location/.claude-plugin/marketplace.json"
  fi
  # name→source-path map from the catalog. Only string sources map; an object
  # source (git/github forms) maps to null and falls through to the layout
  # default below — if that path carries no manifest either, the id fails open.
  if [[ -f "$catalog_json" ]] && jq empty "$catalog_json" 2>/dev/null; then
    source_map=$(jq -c '
      [.plugins[]?
       | select((.name | type) == "string")
       | {key: .name, value: (if (.source | type) == "string" then .source else null end)}]
      | from_entries' "$catalog_json")
  fi
  local pairs id installed_version pname rel manifest catalog_version
  pairs=$(jq -r "$filter" <<<"$block")
  [[ -n "$pairs" ]] || return 0
  while IFS=$'\t' read -r id installed_version; do
    [[ -n "$id" ]] || continue
    if [[ -z "$install_location" ]]; then
      printf '%s\n' "$id"
      continue
    fi
    pname="${id%@*}"
    rel=$(jq -r --arg n "$pname" '.[$n] // empty' <<<"$source_map")
    [[ -n "$rel" ]] || rel="plugins/$pname"
    rel="${rel#./}"
    manifest="$install_location/$rel/.claude-plugin/plugin.json"
    # Empty string is the single "unresolved" sentinel: an invalid-JSON
    # manifest fails the jq read (capturing nothing), a non-string .version is
    # mapped to "" by the filter itself, and a manifest whose version IS the
    # empty string can never equal a real installed version — all three land
    # in the emitted set, as fail-open requires.
    catalog_version=""
    [[ -f "$manifest" ]] &&
      catalog_version=$(jq -r 'if (.version | type) == "string" then .version else "" end' "$manifest" 2>/dev/null)
    if [[ -z "$catalog_version" || "$catalog_version" != "$installed_version" ]]; then
      printf '%s\n' "$id"
    fi
  done <<<"$pairs"
  return 0
}

# Project one marketplace block down to the plain id list a `sync` step loops.
# Exists so no CALLER has to write its own `jq -r ... | while read`: on Windows
# a hand-written jq reintroduces the CR this script's own wrapper strips (the
# native binary writes stdout in text mode), and because `$(...)` strips only
# the TRAILING CRLF, every id but the last arrives as `<name>@<marketplace>\r`.
# Passed to `claude plugin update` that id fails with `Plugin "<name>" not
# found` — the marketplace suffix is silently corrupted, and the error is
# byte-identical to the bare-name failure, so it misdirects diagnosis. Output
# here goes through the same wrapper as every other call, so it is CR-free by
# construction; see context/gotchas.md.
# Reject a bad selector at PARSE time (ids_selector_filter below), not here:
# emit_ids only runs after a marketplace resolves, so a late check would do the
# whole resolution first and then report exit 1 (marketplace unresolvable) for
# what is really exit 2 (bad selector) — the wrong code and the wrong cause.
emit_ids() {
  local block="$1" selector="$2" filter
  filter=$(ids_selector_filter "$selector") || return 2
  # stale-user is the one selector that is not a pure block projection: its
  # base id/version pairs are post-filtered against on-disk catalog manifests.
  if [[ "$selector" == "stale-user" ]]; then
    emit_stale_user_ids "$block" "$filter"
    return $?
  fi
  # `[]?` rather than `[]`: a block legitimately missing a key (an empty
  # `installed`, say) yields no ids instead of erroring.
  jq -r "$filter" <<<"$block"
}

# Emit one marketplace: the JSON block by default, or its projected id list when
# --ids is in play. Keeps the two single-marketplace call sites (default and
# --marketplace) identical instead of branching on IDS_SELECTOR at each.
emit_one() {
  local block rc
  block=$(emit_marketplace "$1")
  rc=$?
  # A per-marketplace failure block ({marketplace: {name, error}}) goes to
  # STDOUT in report mode (documented output contract) but to STDERR under
  # --ids. The documented consumer is `while read … done < <(… --ids …)`, and a
  # process substitution does NOT propagate its command's exit status, so a JSON
  # object left on stdout would be read as an id and handed to `claude plugin
  # update` verbatim. Under --ids stdout carries records or nothing at all.
  #
  # Empty-guarded because a failure can come from a branch that returned before
  # printing; on the success path emit_marketplace always ends in the composed
  # object, so there is no empty case to guard there.
  if [[ "$rc" -ne 0 ]]; then
    if [[ -n "$block" ]]; then
      if [[ -n "$IDS_SELECTOR" ]]; then
        printf '%s\n' "$block" >&2
      else
        printf '%s\n' "$block"
      fi
    fi
    return "$rc"
  fi
  if [[ -n "$IDS_SELECTOR" ]]; then
    emit_ids "$block" "$IDS_SELECTOR" || return $?
  else
    printf '%s\n' "$block"
  fi
}

# --- Arg parsing -------------------------------------------------------------

MODE="default"
TARGET=""
IDS_SELECTOR=""
LIST_MARKETPLACES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --marketplaces)
    LIST_MARKETPLACES="yes"
    shift
    ;;
  --ids)
    IDS_SELECTOR="${2:-}"
    # Same guard-before-`shift 2` reasoning as --marketplace below: with no
    # following arg, `shift 2` fails (no set -e) and the loop spins forever.
    if [[ -z "$IDS_SELECTOR" ]]; then
      echo "ERROR: --ids requires a selector" >&2
      exit 2
    fi
    shift 2
    ;;
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

# --marketplaces is a standalone enumeration mode: it answers "which names can
# I hand to --marketplace" and nothing else, so any flag that shapes a
# per-marketplace report alongside it is a contradiction, refused loudly like
# the --ids/--all combination below rather than silently ignored. Checked
# after the arg loop (not in the branch) so rejection is order-independent —
# `--marketplaces --all` and `--all --marketplaces` fail identically.
if [[ -n "$LIST_MARKETPLACES" ]]; then
  if [[ "$MODE" != "default" || -n "$IDS_SELECTOR" ]]; then
    echo "ERROR: --marketplaces cannot be combined with --marketplace, --all, or --ids" >&2
    exit 2
  fi
  # Through the CR-stripping jq wrapper like every other line-oriented output,
  # so a `while read` consumer gets CR-free names by construction (the reason
  # this mode exists — see the header contract). An empty object yields empty
  # output and exit 0: nothing to enumerate is an answer, not an error.
  jq -r 'keys[]' "$MARKETPLACES_JSON" || exit 2
  exit 0
fi

# --ids projects ONE marketplace block; --all's {marketplaces: {...}} envelope
# has no single block to project. Refused rather than invented, so a caller
# never gets a silently-empty list from a combination this does not implement.
if [[ -n "$IDS_SELECTOR" && "$MODE" == "all" ]]; then
  echo "ERROR: --ids cannot be combined with --all" >&2
  echo "  Run --ids once per marketplace with --marketplace <name>." >&2
  exit 2
fi

# Validate the selector before any marketplace resolution: a typo is a usage
# error (exit 2) and must report as one, not be masked by whatever the
# resolution attempt would have returned first.
if [[ -n "$IDS_SELECTOR" ]]; then
  ids_selector_filter "$IDS_SELECTOR" >/dev/null || exit 2
fi

case "$MODE" in
default)
  plugin_root="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT_DEFAULT}"
  norm_root=$(hook::normalize_path "$(hook::physical_path "$plugin_root")")
  norm_root="${norm_root%/}"
  TARGET=$(resolve_default_marketplace "$norm_root")
  if [[ -z "$TARGET" ]]; then
    echo "ERROR: could not resolve the default marketplace. This plugin's install dir" >&2
    echo "  ${norm_root:-<unresolved>}" >&2
    echo "matched no installed_plugins.json entry — searched by exact installPath and by" >&2
    echo "version-agnostic .../cache/<marketplace>/<plugin> prefix. This usually means the" >&2
    echo "session's loaded version differs from the installed one AND the cache layout is" >&2
    echo "not the expected .../cache/<marketplace>/<plugin>/<version> shape. Pass" >&2
    echo "--marketplace <name> explicitly." >&2
    exit 1
  fi
  emit_one "$TARGET" || exit $?
  ;;
single)
  emit_one "$TARGET" || exit $?
  ;;
all)
  names=$(jq -r 'keys[]' "$MARKETPLACES_JSON")
  result='{}'
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    block=$(emit_marketplace "$n" || true)
    result=$(jq -c --arg n "$n" --slurpfile b "$(jq_slurp_tmpfile "$block")" '. + {($n): $b[0]}' <<<"$result")
  done <<<"$names"
  jq -cn --slurpfile m "$(jq_slurp_tmpfile "$result")" '{marketplaces: $m[0]}'
  ;;
*)
  echo "ERROR: unreachable mode: $MODE" >&2
  exit 2
  ;;
esac
