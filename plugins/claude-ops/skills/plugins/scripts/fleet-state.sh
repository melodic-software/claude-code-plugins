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
#   Single marketplace: {marketplace, project_root, catalog, catalog_versions,
#     installed, enabled, missing_from_install, missing_from_user_install,
#     missing_from_enabled, user_scope_orphans, divergences}
#     — or {marketplace: {name, error}} on a resolvable per-marketplace failure.
#   missing_from_install is all-scope (catalog minus installed anywhere);
#   missing_from_user_install is user-scope only (catalog minus user-scope
#   installed), the signal `sync` Step 4 uses to keep every plugin usable from
#   any directory. Both exclude ids explicitly opted out (false) in any scope.
#   --all: {marketplaces: {"<name>": <single-marketplace shape>, ...}}
#
#   project_root          the normalized project root this run resolved, or null
#                        when none did. Consumers need the DISTINCTION, not just
#                        the per-record currentProject flag: currentProject is a
#                        tri-state (true / false / null) and null collapses
#                        "no project context resolved at all" together with
#                        "this is a user-scope record", so a run from $HOME and a
#                        run inside a repo with no in-repo installs are otherwise
#                        indistinguishable downstream. `sync` Step 2 branches on
#                        this to report a skipped in-repo step instead of
#                        silently no-opping.
#   catalog_versions     {"<id>": "<version>"|null} — each catalog entry's
#                        version read from its own manifest in the marketplace
#                        checkout. null means UNKNOWN, never "no update needed";
#                        see the fail-open contract at the computation below.
#   user_scope_orphans   ids holding at least one project/local install record
#                        and NO user-scope record. Structurally absent from
#                        divergences[] (which only groups ids with more than one
#                        record) and from missing_from_user_install (they ARE
#                        installed, just not at user scope), so without this
#                        field nothing in the output names them at all.
#                        Excludes ids explicitly opted out (false) in any scope,
#                        like the two missing_* arrays — a deliberate decline is
#                        not a gap to report as action needed.
#
#   Each project/local record in installed[] (and each divergences[].scopes[]
#   entry) additionally carries projectPathPresent: true|false|null — whether
#   that record's projectPath is a directory on this machine RIGHT NOW. It is
#   advisory and must never filter installed[] or divergences[]: a false is
#   equally consistent with a deleted worktree and with an unmounted volume,
#   a disconnected network share, or removable media that is simply not
#   attached. null means not applicable (a user-scope record, or no
#   projectPath).
#
# Output (stdout) with --ids <selector>: NOT JSON — one record per line, in the
#   order the block carries them, and nothing else. Fields are TAB-separated and
#   the first field is always the fully-qualified `<name>@<marketplace>` id, so
#   `while IFS=$'\t' read -r id …` reads every selector. Selectors, each naming
#   the `sync` step that consumes it:
#     installed-user        installed[] at user scope           (Step 3 update)
#                             fields: id
#     update-candidates-user  installed[] at user scope whose   (Step 3 update)
#                             catalog version is UNKNOWN or differs from the
#                             installed one — a SUPERSET of what actually needs
#                             updating, never an authoritative "these are stale"
#                             list. Prefer it over installed-user for the Step 3
#                             sweep; it degrades to exactly installed-user when
#                             no catalog version resolves.
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
#     user-scope-orphans    user_scope_orphans[]                (report only)
#                             fields: id
#   Zero matches is success with empty output (exit 0), not an error. Reject:
#   `--ids` with `--all` (no single block to project), or an unknown selector.
#
# Output (stdout) with --marketplaces: NOT JSON — every marketplace name from
#   known_marketplaces.json, one per line, nothing else, CR-free by the same
#   wrapper as --ids. Empty output for an empty object is success (exit 0).
#   Standalone: combining it with --marketplace, --all, or --ids is a usage
#   error (exit 2). Exists so `sync`'s `all` mode can iterate
#   `--marketplace <name> --ids <selector>` per name without hand-writing its
#   own `jq -r 'keys[]' | while read`, which is the same Windows-CRLF
#   corruption the --ids contract exists to prevent.
#   A per-marketplace failure block goes to STDERR in this mode (never stdout),
#   so stdout carries records or nothing — a `< <(… --ids …)` consumer cannot
#   see the process's exit status and would otherwise read the error JSON as an
#   id. This mode exists so a caller never hand-writes `jq -r ... | while read`
#   — on Windows that reintroduces a CR and corrupts every id but the last. See
#   the emit_ids comment and context/gotchas.md.
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
#                                     Per-plugin manifests (for catalog_versions)
#                                     are then resolved under a SUBDIRECTORY of
#                                     the same dir named for the marketplace:
#                                       $FLEET_STATE_CATALOG_DIR/<marketplace>.json
#                                       $FLEET_STATE_CATALOG_DIR/<marketplace>/<entry.source>/.claude-plugin/plugin.json
#                                     mirroring production's
#                                       <installLocation>/.claude-plugin/marketplace.json
#                                       <installLocation>/<entry.source>/.claude-plugin/plugin.json
#                                     A fixture that omits the subdirectory is
#                                     not broken — it exercises the fail-open
#                                     path, which is the common one in the wild.
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

# --- Physical containment test for a catalog plugin manifest -----------------
# True only when $1 resolves — with symlinks followed — to a path strictly
# under the already-resolved checkout root $2.
#
# Why physical rather than lexical: a symlink inside the checkout that points
# outside it is reached by an ordinary-looking relative source, so no amount of
# string inspection on the source can detect it. Resolving both sides and
# comparing is what actually enforces "inside the checkout".
#
# Fails CLOSED for the containment question (returns non-zero), which makes the
# CALLER fail OPEN on the version: an unresolvable path yields no version, so
# the id stays an update candidate. That is the safe direction — the only
# unsafe outcome for this pre-filter is withholding an update it did not earn.
manifest_is_contained() {
  local candidate="$1" root="$2" resolved
  [[ -n "$root" ]] || return 1
  # On failure hook::physical_path ECHOES ITS INPUT and returns non-zero. That
  # echoed input still begins with the checkout root, so a naive prefix compare
  # would call it contained without anything having been resolved — the unsafe
  # direction. Gate on the RETURN STATUS, which `resolved=$(...)` propagates.
  # Its HOOK_PHYSICAL_PATH_UNRESOLVED global cannot be used here: command
  # substitution runs the function in a subshell, so the flag it sets never
  # reaches this scope and would always read as "resolved".
  resolved=$(hook::physical_path "$candidate") || return 1
  resolved=$(hook::normalize_path "$resolved")
  # Strict prefix: the root itself is not a plugin manifest, and the trailing
  # slash stops "/checkout-evil/..." from matching root "/checkout".
  [[ "$resolved" == "$root"/* ]]
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

  # --- Per-plugin catalog versions, for the Step 3 update pre-filter ---------
  # A marketplace.json ENTRY carries no version — only name/source/category/
  # tags (and optionally defaultEnabled/displayName/relevance). That absence is
  # why `sync` Step 3 historically called `claude plugin update` for every
  # user-scope install and let the CLI decide: there was "no per-plugin catalog
  # version to compare against". There is one, just not in that file — each
  # plugin's own manifest sits in the marketplace checkout the entry's `source`
  # points at, and reading it costs no network call and no CLI invocation.
  #
  # FAIL OPEN is the contract here, not a defensive nicety. Measured across the
  # nine marketplaces registered on the authoring machine (Claude Code 2.1.240),
  # the version resolves for every entry of some marketplaces and for a small
  # MINORITY of others': an entry whose `source` is an object (a remote git
  # spec) has no repo-relative path at all, a checkout may not materialize every
  # entry's directory, and a manifest may carry no `version` key. So an
  # unresolvable version is the COMMON case, not the rare one. Every such id
  # gets null, and every consumer must read null as "update candidate" — the
  # pre-filter may only ever shrink the sweep for an id it positively proved is
  # already at the catalog version. Anything else risks silently skipping a
  # stale plugin, which is strictly worse than the redundant no-op call the
  # pre-filter exists to avoid.
  local manifest_base
  if [[ -n "${FLEET_STATE_CATALOG_DIR:-}" ]]; then
    manifest_base="$FLEET_STATE_CATALOG_DIR/$name"
  else
    # installLocation is recorded in native form on Windows (C:\Users\...);
    # fold to forward slashes so the composed path is one this shell can stat.
    manifest_base="${install_location//\\//}"
  fi

  # Containment root for the check below, resolved ONCE per marketplace.
  # hook::normalize_path folds separators, and on Windows also folds drive-letter
  # case, so two normalized physical paths compare directly with `==` on either
  # platform — no ad-hoc downcasing here.
  local manifest_base_phys
  manifest_base_phys=$(hook::normalize_path "$(hook::physical_path "$manifest_base")")
  manifest_base_phys="${manifest_base_phys%/}"

  local catalog_versions_lines="" cv_name cv_src cv_rel cv_ver cv_manifest
  while IFS=$'\t' read -r cv_name cv_src; do
    [[ -n "$cv_name" ]] || continue
    cv_ver=""
    # `source` is THIRD-PARTY content — it comes out of a marketplace's own
    # manifest. If it can name a manifest outside the checkout, that foreign
    # file gets to positively "prove" an id is already at the catalog version
    # and suppress its update. A wrongly-WITHHELD update is the only unsafe
    # direction this pre-filter has (a wrongly-emitted id is merely a redundant
    # no-op call), so reaching outside the checkout must be impossible.
    #
    # Two gates, because a lexical one alone is NOT sufficient:
    #  1. Lexical, below — refuse a `../` path SEGMENT. Cheap, spawns nothing,
    #     and rejects the common spelling before anything is stat'd. Backslash
    #     is folded first so `..\x` is caught as the same traversal.
    #  2. Physical containment, after the -f test — resolve the manifest with
    #     symlinks followed and require it to sit under the resolved checkout
    #     root. This is the gate that actually enforces the property: a SYMLINK
    #     inside the checkout pointing outside it is a perfectly ordinary
    #     `./name` source that no lexical check can see, and `git clone`
    #     materializes real symlinks wherever core.symlinks is on.
    # The physical gate runs only for entries whose manifest exists, so its
    # subprocess cost tracks resolvable plugins, not catalog size.
    # Either gate failing yields null → fail open → the id stays a candidate.
    cv_rel="${cv_src#./}"
    cv_rel="${cv_rel//\\//}"
    case "/$cv_rel/" in
    */../*)
      cv_rel=""
      ;;
    *) ;;
    esac
    cv_manifest="$manifest_base/$cv_rel/.claude-plugin/plugin.json"
    if [[ -n "$cv_rel" && -f "$cv_manifest" ]] && manifest_is_contained "$cv_manifest" "$manifest_base_phys"; then
      # Through the CR-stripping wrapper like every other call, and
      # `// empty` so a manifest with no version yields "" (→ null below)
      # rather than the string "null".
      # `//` is used deliberately here, unlike at projectPathPresent below
      # where it would destroy information: the only extra value it swallows
      # is a boolean `false` version, and swallowing that yields null → the id
      # stays an update candidate. Every value this operator collapses lands on
      # the FAIL-OPEN side, so the collapse cannot cause a wrong withhold. A
      # numeric `0` is preserved (jq treats only false/null as empty).
      cv_ver=$(jq -r '.version // empty' "$cv_manifest" 2>/dev/null)
    fi
    catalog_versions_lines+="$cv_name"$'\t'"$cv_ver"$'\n'
  done < <(jq -r '.plugins[]? | select((.source | type) == "string") | "\(.name)\t\(.source)"' "$catalog_json")

  # Entries whose source is not a string never enter the loop above, so they
  # are absent from this map entirely — a lookup returns null, the same
  # fail-open answer as an entry whose manifest could not be read.
  local catalog_versions
  catalog_versions=$(printf '%s' "$catalog_versions_lines" | jq -Rn --arg mp "$name" '
    [inputs
     | split("\t")
     | select(length >= 2 and (.[0] | length) > 0)
     | {key: (.[0] + "@" + $mp), value: (if .[1] == "" then null else .[1] end)}]
    | from_entries')

  # --- projectPath liveness (advisory only — NEVER a filter) -----------------
  # Answers "is this record's projectPath a directory on this machine right
  # now", nothing more. A false is equally consistent with a worktree that was
  # removed and with a volume that is merely not mounted, a network share that
  # is offline, or removable media that is unplugged — so this field annotates
  # a row, and must never suppress one. Suppressing on it would hide real drift
  # for anyone whose repos live on an external or network volume.
  # Computed per DISTINCT path (a machine can hold a hundred records naming a
  # dozen directories), so the stat count tracks directories, not records.
  local path_presence_lines="" pp pp_fs
  while IFS= read -r pp; do
    [[ -n "$pp" ]] || continue
    pp_fs="${pp//\\//}"
    if [[ -d "$pp_fs" ]]; then
      path_presence_lines+="$pp"$'\t'"true"$'\n'
    else
      path_presence_lines+="$pp"$'\t'"false"$'\n'
    fi
  done < <(jq -r --arg suffix "@$name" '
    [.plugins
     | to_entries[]
     | select(.key | endswith($suffix))
     | .value[]
     | select(.scope == "project" or .scope == "local")
     | .projectPath // empty]
    | unique | .[]' "$INSTALLED_JSON")

  local path_presence path_presence_f
  path_presence=$(printf '%s' "$path_presence_lines" | jq -Rn '
    [inputs
     | split("\t")
     | select(length >= 2 and (.[0] | length) > 0)
     | {key: .[0], value: (.[1] == "true")}]
    | from_entries')
  path_presence_f="$(jq_slurp_tmpfile "$path_presence")"

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
  installed=$(jq -c --arg suffix "@$name" --arg cur "$current_project_norm" --argjson ci "$case_insensitive_os" \
    --slurpfile pres "$path_presence_f" '
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
        ),
        projectPathPresent: (
          if (.scope == "project" or .scope == "local") and (.projectPath // "" | length) > 0 then
            # `has` rather than `$pres[0][$pp] // null`: jq treats FALSE as
            # empty for `//`, so the alternative operator would silently
            # rewrite a genuine "not present" into "not checked" — collapsing
            # the exact distinction this field exists to carry.
            .projectPath as $pp
            | (if ($pres[0] | has($pp)) then $pres[0][$pp] else null end)
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

  # Ids with a project/local record and NO user-scope record. Every other field
  # here is structurally blind to them: divergences[] starts by discarding any
  # id with fewer than two records, and missing_from_user_install lists ids that
  # are not installed AT ALL at user scope but IS catalog-derived and excludes
  # ids installed somewhere. So a single-scope project-only install appears in
  # neither, and without this array nothing in the output names it. Deliberately
  # NOT filtered to catalog membership: an installed id the catalog no longer
  # carries is exactly the kind of record a reader wants named.
  # Excludes ids explicitly opted out (false) in any scope, exactly as
  # missing_from_install and missing_from_user_install do. Without that
  # subtraction, a plugin that is deliberately disabled AND installed only at
  # project/local scope lands in this array, and SKILL.md's Report section puts
  # the array under "Action needed" — resurfacing a decision the user already
  # made as drift to act on. An opt-out is an answer, not a gap.
  local user_scope_orphans
  user_scope_orphans=$(jq -cn \
    --slurpfile installed "$(jq_slurp_tmpfile "$installed")" \
    --slurpfile falseIds "$explicit_false_ids_f" '
    (([$installed[0][] | select(.scope == "project" or .scope == "local") | .id] | unique)
     - ([$installed[0][] | select(.scope == "user") | .id] | unique))
    - $falseIds[0]
  ')

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
  # signal). A record count alone conflates the two.
  local divergences
  divergences=$(jq -c '
    group_by(.id)
    | map(select(length > 1))
    | map({
        id: .[0].id,
        scopes: map({scope, version, projectPath, projectPathPresent}),
        versionsMatch: ((map(.version) | unique | length) == 1)
      })
  ' <<<"$installed")

  jq -cn \
    --arg name "$name" \
    --argjson autoUpdate "$auto_update_json" \
    --arg lastUpdated "$last_updated" \
    --arg project_root "$current_project_norm" \
    --slurpfile catalog "$(jq_slurp_tmpfile "$catalog")" \
    --slurpfile catalogVersions "$(jq_slurp_tmpfile "$catalog_versions")" \
    --slurpfile installed "$(jq_slurp_tmpfile "$installed")" \
    --slurpfile enabled "$(jq_slurp_tmpfile "$enabled_at_mp")" \
    --slurpfile missingInstall "$(jq_slurp_tmpfile "$missing_from_install")" \
    --slurpfile missingUserInstall "$(jq_slurp_tmpfile "$missing_from_user_install")" \
    --slurpfile missingEnabled "$(jq_slurp_tmpfile "$missing_from_enabled")" \
    --slurpfile userScopeOrphans "$(jq_slurp_tmpfile "$user_scope_orphans")" \
    --slurpfile divergences "$(jq_slurp_tmpfile "$divergences")" \
    '{
      marketplace: {name: $name, autoUpdate: $autoUpdate, lastUpdated: $lastUpdated},
      project_root: (if ($project_root | length) > 0 then $project_root else null end),
      catalog: $catalog[0],
      catalog_versions: $catalogVersions[0],
      installed: $installed[0],
      enabled: $enabled[0],
      missing_from_install: $missingInstall[0],
      missing_from_user_install: $missingUserInstall[0],
      missing_from_enabled: $missingEnabled[0],
      user_scope_orphans: $userScopeOrphans[0],
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
#
# `update-candidates-user` is the pre-filtered form of `installed-user`, and its
# name says CANDIDATE on purpose: it emits a SUPERSET of the ids that actually
# need updating, never an authoritative stale list. An id is emitted when its
# catalog version is unknown OR differs from the installed one, so the only ids
# it withholds are those positively proved to already sit at the catalog
# version. `== null` rather than `// null`: jq's alternative operator also
# swallows `false`, and reaching for it here is how a lookup miss and a real
# value get conflated.
# Plain string inequality, deliberately not a semver ORDERING compare: an
# installed version merely DIFFERENT from the catalog's (a local dev build
# ahead of it, say) stays a candidate, exactly as it is today when Step 3 calls
# update for every id unconditionally. An ordering compare would start
# withholding ids on a judgement this script has no business making.
ids_selector_filter() {
  case "$1" in
  installed-user) printf '%s' '.installed[]? | select(.scope == "user") | .id' ;;
  update-candidates-user)
    # shellcheck disable=SC2016  # a jq program: $cv is a jq variable and must reach jq unexpanded
    printf '%s' '.catalog_versions as $cv | .installed[]? | select(.scope == "user") | select(($cv[.id]) == null or ($cv[.id]) != .version) | .id'
    ;;
  current-project) printf '%s' '.installed[]? | select(.currentProject == true) | "\(.id)\t\(.scope)"' ;;
  missing-user-install) printf '%s' '.missing_from_user_install[]?' ;;
  missing-enabled) printf '%s' '.missing_from_enabled[]?' ;;
  user-scope-orphans) printf '%s' '.user_scope_orphans[]?' ;;
  *)
    echo "ERROR: unknown --ids selector: $1" >&2
    echo "  expected one of: installed-user, update-candidates-user," >&2
    echo "                   current-project, missing-user-install," >&2
    echo "                   missing-enabled, user-scope-orphans" >&2
    return 1
    ;;
  esac
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

# --marketplaces is a standalone ENUMERATION mode: it answers "which names can
# I hand to --marketplace" and nothing else. `sync`'s `all` mode runs Steps 2-5
# once per marketplace, so it needs that list — and without this mode the only
# way to get it is a hand-written `jq -r 'keys[]' | while read` over
# known_marketplaces.json, which on Windows reintroduces the trailing CR that
# the whole --ids contract exists to prevent. Same hazard, same remedy.
#
# Any flag that shapes a per-marketplace report alongside it is a
# contradiction, so it is refused loudly rather than silently ignored. Checked
# after the arg loop rather than inside the branch so the rejection is
# order-independent: `--marketplaces --all` and `--all --marketplaces` fail
# identically.
if [[ -n "$LIST_MARKETPLACES" ]]; then
  if [[ "$MODE" != "default" || -n "$IDS_SELECTOR" ]]; then
    echo "ERROR: --marketplaces cannot be combined with --marketplace, --all, or --ids" >&2
    exit 2
  fi
  # Through the CR-stripping jq wrapper like every other line-oriented output,
  # so a `while read` consumer gets CR-free names by construction. An empty
  # object yields empty output and exit 0: nothing to enumerate is an answer,
  # not an error.
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
