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
#   capture discipline as --ids. Empty output for an empty object is success
#   (exit 0). Standalone: combining it with --marketplace, --all, or --ids is a
#   usage error (exit 2). Exists so `sync`'s `all` mode can iterate
#   `--marketplace <name> --ids <selector>` per name without hand-writing its
#   own `jq -r 'keys[]' | while read`, which is the same Windows-CRLF
#   corruption the --ids contract exists to prevent.
#   A per-marketplace failure block goes to STDERR in this mode (never stdout),
#   so stdout carries records or nothing — a `< <(… --ids …)` consumer cannot
#   see the process's exit status and would otherwise read the error JSON as an
#   id. This mode exists so a caller never hand-writes `jq -r ... | while read`
#   — on Windows that reintroduces a CR and corrupts every id but the last. See
#   the jq_to comment and context/gotchas.md.
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
# Process budget. Every external command this script runs is a process
#   creation, and on Windows Git Bash each one costs fork() emulation plus a
#   CreateProcess (roughly 120 ms on a quiet host, seconds on a contended one).
#   The report is therefore computed in THREE jq passes and at most two
#   `realpath` calls, never one process per catalog entry:
#     1. one jq over installed_plugins.json, known_marketplaces.json and the
#        three settings scopes: validation, the merged enabledPlugins context,
#        every marketplace's fields, every recorded projectPath, and (default
#        mode only) the marketplace this plugin was installed from;
#     2. one jq per marketplace over its marketplace.json, the entry list
#        whose manifests the shell then locates with builtins;
#     3. one jq per marketplace that composes the whole block (or the --ids
#        projection) from the validated files plus a single stdin payload the
#        shell assembled with builtins (context, projectPath presence, and
#        every manifest's raw text).
#   Manifest containment resolves all paths with one batched `realpath`
#   (hook::_physical_prime) and reads each manifest with `read -d ''`, so the
#   per-entry work is pure shell. A `git rev-parse` runs only when
#   CLAUDE_PROJECT_DIR is unset. The regression guard for this budget lives in
#   fleet-state.test.sh.
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
# `builtin pushd`/`builtin popd` prefixes bypass an inherited exported
# `cd`/`pwd`/`pushd` function. The directory is read back from $PWD inside the
# main shell rather than through `$(builtin cd … && builtin pwd)`, which would
# fork a subshell for each of the two resolutions. This is defense against the
# common cd/pwd/dirname channels, not a guarantee against a fully
# attacker-controlled environment: an exported `BASH_FUNC_builtin%%` shadows
# `builtin` itself, and `BASH_ENV` runs before this script's first line — both
# sit at the same environment-trust boundary as the PATH-resolved jq/git/realpath
# used later, out of scope for an in-script fix.
script_src="${BASH_SOURCE[0]}"
case "$script_src" in
*/*) script_src_dir="${script_src%/*}" ;;
*) script_src_dir="." ;;
esac
PLUGIN_ROOT_DEFAULT=""
if builtin pushd "$script_src_dir/../../.." >/dev/null 2>&1; then
  PLUGIN_ROOT_DEFAULT="$PWD"
  builtin popd >/dev/null 2>&1 || true
fi

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

# --- jq capture ---------------------------------------------------------------
# Some native-Windows jq builds CRLF-terminate every line, including
# single-line compact output. `$(...)` strips only the trailing LF, so a
# stray CR survives at the end of a captured value and corrupts it once
# re-parsed as JSON, and every id but the last in a line-oriented output
# arrives as `<name>@<marketplace>\r`. Every jq call goes through this helper,
# which strips ALL carriage returns in the shell (no `tr` process) and stores
# the result in the named variable. Callers never pipe jq to anything: the
# pipeline would fork a second process for the consumer, and a `while read`
# over a here-string of the captured value costs nothing.
jq_to() {
  local __jq_var="$1"
  shift
  local __jq_out __jq_rc=0
  __jq_out=$(command jq "$@") || __jq_rc=$?
  printf -v "$__jq_var" '%s' "${__jq_out//$'\r'/}"
  return "$__jq_rc"
}

# --- JSON string literal, built with builtins ----------------------------------
# The --all envelope and the per-marketplace error blocks are assembled in the
# shell around jq's own compact output, so the two strings the shell itself
# has to encode (a marketplace name, a lastUpdated stamp) get the same
# escaping jq's encoder applies: `\"`, `\\`, the five short control escapes,
# `\u00XX` for every other C0 byte, everything else (including non-ASCII and
# DEL) verbatim.
json_string_to() {
  local __js_s="$2" __js_i __js_c __js_hex __js_out=""
  __js_s="${__js_s//\\/\\\\}"
  __js_s="${__js_s//\"/\\\"}"
  __js_s="${__js_s//$'\n'/\\n}"
  __js_s="${__js_s//$'\r'/\\r}"
  __js_s="${__js_s//$'\t'/\\t}"
  __js_s="${__js_s//$'\b'/\\b}"
  __js_s="${__js_s//$'\f'/\\f}"
  if [[ "$__js_s" == *[$'\x01'-$'\x1f']* ]]; then
    for ((__js_i = 0; __js_i < ${#__js_s}; __js_i++)); do
      __js_c="${__js_s:__js_i:1}"
      if [[ "$__js_c" == [$'\x01'-$'\x1f'] ]]; then
        printf -v __js_hex '\\u%04x' "'$__js_c"
        __js_out+="$__js_hex"
      else
        __js_out+="$__js_c"
      fi
    done
    __js_s="$__js_out"
  fi
  printf -v "$1" '"%s"' "$__js_s"
}

INSTALLED_JSON="${FLEET_STATE_INSTALLED_JSON:-$HOME/.claude/plugins/installed_plugins.json}"
MARKETPLACES_JSON="${FLEET_STATE_MARKETPLACES_JSON:-$HOME/.claude/plugins/known_marketplaces.json}"
USER_SETTINGS="${FLEET_STATE_USER_SETTINGS:-$HOME/.claude/settings.json}"

# Case-fold path comparisons ONLY on case-insensitive filesystems (mirrors
# hook::normalize_path's own $OSTYPE check exactly). Applying ascii_downcase
# unconditionally makes two genuinely different sibling repos on a
# case-sensitive POSIX host (e.g.
# /work/repo and /work/Repo) compare equal, which can point a project-scope
# mutation at the wrong repo.
case_insensitive_os="false"
case "${OSTYPE:-}" in
msys* | cygwin* | win32) case_insensitive_os="true" ;;
*) ;;
esac

# Native (drive-letter) spelling of an MSYS path, with no process when the
# path is a plain `/<drive>/…` mount, the form `pwd -W` would print for it.
# Any other spelling (a mount alias like /tmp, a POSIX host) falls back to the
# subshell `pwd -W` this used to run unconditionally.
native_cwd_to() {
  local __nc_dir="$2" __nc_v=""
  if [[ "$case_insensitive_os" == "true" && "$__nc_dir" =~ ^/([a-zA-Z])(/.*)?$ ]]; then
    __nc_v="${BASH_REMATCH[1]^}:${BASH_REMATCH[2]:-/}"
  else
    __nc_v=$(builtin cd "$__nc_dir" 2>/dev/null && { builtin pwd -W 2>/dev/null || builtin pwd; }) || __nc_v=""
  fi
  [[ -n "$__nc_v" ]] || __nc_v="$__nc_dir"
  printf -v "$1" '%s' "$__nc_v"
}

# --- Arg parsing ---------------------------------------------------------------
# Parsed before any file is read so a usage error costs no process and reports
# as exit 2 rather than as whatever the resolution attempt would have hit first.

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
  MODE="list"
fi

# --ids projects ONE marketplace block; --all's {marketplaces: {...}} envelope
# has no single block to project. Refused rather than invented, so a caller
# never gets a silently-empty list from a combination this does not implement.
if [[ -n "$IDS_SELECTOR" && "$MODE" == "all" ]]; then
  echo "ERROR: --ids cannot be combined with --all" >&2
  echo "  Run --ids once per marketplace with --marketplace <name>." >&2
  exit 2
fi

# Single source of truth for the accepted --ids selectors, so the parse-time
# rejection below and the projection inside the block jq can never drift. The
# projection itself is a branch on $selector in that jq program.
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
ids_selector_valid() {
  case "$1" in
  installed-user | update-candidates-user | current-project | missing-user-install | missing-enabled | user-scope-orphans)
    return 0
    ;;
  *)
    echo "ERROR: unknown --ids selector: $1" >&2
    echo "  expected one of: installed-user, update-candidates-user," >&2
    echo "                   current-project, missing-user-install," >&2
    echo "                   missing-enabled, user-scope-orphans" >&2
    return 1
    ;;
  esac
}

# Validate the selector before any marketplace resolution: a typo is a usage
# error (exit 2) and must report as one, not be masked by whatever the
# resolution attempt would have returned first.
if [[ -n "$IDS_SELECTOR" ]]; then
  ids_selector_valid "$IDS_SELECTOR" || exit 2
fi

# --- Fail-loud presence checks for internal (undocumented) CC state -----------
# These files are CC-internal, not a published contract. A shape drift means
# our assumptions are stale — better to fail loud here than silently emit an
# empty or wrong report. Presence is a builtin test; validity and shape are
# decided by the first jq pass below, which names the offending file.

if [[ ! -f "$INSTALLED_JSON" ]]; then
  echo "ERROR: installed_plugins.json not found: $INSTALLED_JSON" >&2
  exit 2
fi
if [[ ! -f "$MARKETPLACES_JSON" ]]; then
  echo "ERROR: known_marketplaces.json not found: $MARKETPLACES_JSON" >&2
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
#
# The list mode never needs a project root, so it skips the `git rev-parse`.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$PROJECT_ROOT" && "$MODE" != "list" ]]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT=""
  PROJECT_ROOT="${PROJECT_ROOT//$'\r'/}"
fi

# Every path whose physical form this run needs is resolved by ONE batched
# `realpath` (hook::_physical_prime), then read back from hook-utils' cache
# with no further process. The plugin root is only needed for default-mode
# marketplace self-resolution; the cwd/$HOME pair only for the corroborated
# non-git fallback.
cwd_native=""
home_native=""
phys_tmp=""
cwd_norm=""
home_norm=""
norm_root=""
key_json=""
plugin_root="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT_DEFAULT}"
prime_paths=()
if [[ -z "$PROJECT_ROOT" && "$MODE" != "list" && -d "$PWD/.claude" ]]; then
  # `pwd -W` (Git Bash) yields the native drive-letter spelling — the form
  # CC-written projectPath records carry. A raw MSYS mount alias like /tmp
  # resolves to a different string than the record even after normalization,
  # so the native spelling is taken where the shell can produce it.
  native_cwd_to cwd_native "$PWD"
  # Both sides of the $HOME comparison are spelled the same way. Normalizing
  # `$HOME` as given compares a native path against whatever spelling the
  # environment happens to carry, and an MSYS MOUNT ALIAS has no drive letter
  # for the normalizer to reconcile: `$HOME=/tmp/x` never equals the `C:/…`
  # `pwd -W` reports for that same directory, so the exclusion silently failed
  # and $HOME became project context — the one outcome this block exists to
  # prevent. Spelling both sides through the same derivation is what makes them
  # comparable; normalizing harder cannot, since the two inputs disagree before
  # the normalizer sees them. The fallback subshell uses `builtin cd`, matching
  # this script's shadow discipline: an exported `cd` function that returns
  # success WITHOUT changing directory would otherwise make home_native the
  # cwd, so every corroborated non-git project would compare equal to $HOME and
  # lose its project settings entirely.
  if [[ -n "${HOME:-}" && -d "$HOME" ]]; then
    native_cwd_to home_native "$HOME"
  fi
  prime_paths+=("$cwd_native")
  [[ -n "$home_native" ]] && prime_paths+=("$home_native")
fi
[[ -n "$PROJECT_ROOT" ]] && prime_paths+=("$PROJECT_ROOT")
[[ "$MODE" == "default" ]] && prime_paths+=("$plugin_root")
if ((${#prime_paths[@]} > 0)); then
  hook::_physical_prime "${prime_paths[@]}"
fi

if [[ -n "$cwd_native" ]]; then
  if [[ -n "$home_native" ]]; then
    hook::_physical_cached_to phys_tmp "$home_native" || true
    hook::normalize_path_to home_norm "$phys_tmp"
  fi
  hook::_physical_cached_to phys_tmp "$cwd_native" || true
  hook::normalize_path_to cwd_norm "$phys_tmp"
  [[ "$cwd_norm" != "$home_norm" ]] && PROJECT_ROOT="$cwd_native"
fi

# --- Normalized current-project root, for the `currentProject` install flag
current_project_norm=""
if [[ -n "$PROJECT_ROOT" ]]; then
  hook::_physical_cached_to phys_tmp "$PROJECT_ROOT" || true
  hook::normalize_path_to current_project_norm "$phys_tmp"
  current_project_norm="${current_project_norm%/}"
fi

# --- Normalized plugin root, for default-marketplace self-resolution ---------
# The match itself runs inside pass 1's jq, exactly as before, with the root
# handed over as a `--arg`. That placement is load-bearing on Windows: jq is a
# native binary, so MSYS rewrites a mount-alias argument such as `/tmp/...`
# into the drive-letter spelling installed_plugins.json records carry, which
# a comparison done in the shell would never see. Keep it in jq.
norm_root=""
norm_root_parent=""
if [[ "$MODE" == "default" ]]; then
  hook::_physical_cached_to phys_tmp "$plugin_root" || true
  hook::normalize_path_to norm_root "$phys_tmp"
  norm_root="${norm_root%/}"
  norm_root_parent="${norm_root%/*}"
  [[ -n "$norm_root_parent" && "$norm_root_parent" != "$norm_root" ]] || norm_root_parent=""
fi

# --- Pass 1: validate, merge scopes, enumerate marketplaces -------------------
# One jq over every top-level input. It emits one record per line, fields
# separated by U+001F (unit separator: never whitespace, so `read` cannot
# collapse an empty field, and never a byte that appears in compact JSON):
#   ERR<US><message>                       fail loud: the message names the file
#   CTX<US><json>                          {known_ids, effective, false_ids}
#   NAME<US><marketplace>                  every key, in sorted order
#   MP<US><name><US><installLocation><US><autoUpdate><US><lastUpdated>
#                                          every key whose entry is truthy
#   PP<US><projectPath>                    every distinct project/local path
#   TARGET<US><marketplace>                the default marketplace (default
#                                          mode only; empty when unresolved)
# The settings files are read as raw text so a malformed one surfaces as its
# own error instead of an empty capture that only fails several steps later.
#
# Default-marketplace resolution is the one this plugin was installed from: a
# two-stage match against installed_plugins.json's version-pinned installPath.
#   1. exact: installPath == this plugin's normalized root (the precise case).
#   2. version-agnostic fallback: installPath and the running root differ ONLY
#      by their trailing `/<version>` segment. This is common, not an edge case:
#      marketplace autoUpdate bumps the install shortly after session start while
#      the session keeps rendering the old version's skill, and `sync`'s own
#      Step 3 updates claude-ops itself, so every subsequent same-session call of
#      the bare (no --marketplace) default path would otherwise fail. The fallback
#      matches the version-stripped `…/cache/<marketplace>/<plugin>` prefix, which
#      still carries the marketplace (so two marketplaces shipping the same plugin
#      stay distinguishable).
settings_args=()
[[ -f "$USER_SETTINGS" ]] && settings_args+=(--rawfile us "$USER_SETTINGS")
if [[ -n "$PROJECT_ROOT" ]]; then
  [[ -f "$PROJECT_ROOT/.claude/settings.json" ]] &&
    settings_args+=(--rawfile ps "$PROJECT_ROOT/.claude/settings.json")
  [[ -f "$PROJECT_ROOT/.claude/settings.local.json" ]] &&
    settings_args+=(--rawfile ls "$PROJECT_ROOT/.claude/settings.local.json")
fi

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
PASS1_PROGRAM='
  def parsed($raw): ($raw | try (fromjson | {ok: .}) catch {err: true});
  def map_of($raw; $label):
    if $raw == null then {}
    else (parsed($raw) | if .err then error("ERR\u001f" + $label + " is not valid JSON")
          else (.ok | .enabledPlugins // {}) end)
    end;
  (parsed($inst_raw) | if .err then {err: ("installed_plugins.json is not valid JSON: " + $inst_path)}
     elif (.ok | type == "object" and has("plugins") and (.plugins | type == "object")
           and (.plugins | to_entries | all(.value | type == "array"))) | not
     then {err: ("installed_plugins.json does not match the expected {plugins: {<id>: [...]}} shape: " + $inst_path)}
     else . end) as $ip
  | (parsed($mk_raw) | if .err then {err: ("known_marketplaces.json is not valid JSON: " + $mk_path)}
     elif (.ok | type) != "object" then {err: ("known_marketplaces.json is not a JSON object: " + $mk_path)}
     else . end) as $mp
  | if $ip.err then "ERR\u001f" + $ip.err
    elif $mp.err then "ERR\u001f" + $mp.err
    else
      $ip.ok as $inst | $mp.ok as $mk
      | map_of($ARGS.named.us; "user settings") as $u
      | map_of($ARGS.named.ps; "project settings") as $p
      | map_of($ARGS.named.ls; "local settings") as $l
      | ("CTX\u001f" + ({
            known_ids: (($u + $p + $l) | keys),
            effective: ($u + $p + $l),
            false_ids: ([($u, $p, $l) | to_entries[] | select(.value == false) | .key] | unique)
          } | tojson)),
        ($mk | keys[] as $k
          | ("NAME\u001f" + $k),
            (if $mk[$k] then ($mk[$k]
              | "MP\u001f\($k)\u001f\(.installLocation // "")\u001f\((.autoUpdate // false) | tostring)\u001f\(.lastUpdated // "")")
             else empty end)),
        ([$inst.plugins | to_entries[] | .value[] | select(.scope == "project" or .scope == "local") | .projectPath // empty]
          | unique | .[] | "PP\u001f\(.)"),
        (if $mode == "default" then
           ($ci == "true") as $cib
           | ([$inst.plugins | to_entries[]
               | select(.value[] | (.installPath // "" | gsub("\\\\"; "/")) as $p |
                        if $cib then ($p | ascii_downcase) == ($root | ascii_downcase) else $p == $root end)
               | .key] | .[0] // "") as $exact
           | (if $exact != "" then $exact
              elif $parent == "" then ""
              else ([$inst.plugins | to_entries[]
                     | select(.value[] | (.installPath // "" | gsub("\\\\"; "/") | rtrimstr("/") | sub("/[^/]*$"; "")) as $pp |
                              if $cib then ($pp | ascii_downcase) == ($parent | ascii_downcase) else $pp == $parent end)
                     | .key] | .[0] // "")
              end) as $hit
           | "TARGET" + ([31] | implode) + ($hit | sub(".*@"; ""))
         else empty end)
    end'

pass1=""
if ! jq_to pass1 -rn \
  --rawfile inst_raw "$INSTALLED_JSON" --arg inst_path "$INSTALLED_JSON" \
  --rawfile mk_raw "$MARKETPLACES_JSON" --arg mk_path "$MARKETPLACES_JSON" \
  --arg mode "$MODE" --arg root "$norm_root" --arg parent "$norm_root_parent" --arg ci "$case_insensitive_os" \
  ${settings_args[@]+"${settings_args[@]}"} \
  "$PASS1_PROGRAM"; then
  # A settings scope that failed to parse: jq's own `error()` already named the
  # scope on stderr. Refuse to compose a report over a map that could not be
  # read: a silently empty scope would misreport every id in it.
  echo "ERROR: could not read the enabledPlugins scopes (see the jq error above)" >&2
  exit 2
fi

ctx_json=""
mp_names=()
mp_keys=()
mp_loc=()
mp_au=()
mp_lu=()
pp_lines=()
resolved_target=""
while IFS=$'\x1f' read -r tag f1 f2 f3 f4; do
  case "$tag" in
  ERR)
    echo "ERROR: $f1" >&2
    exit 2
    ;;
  CTX) ctx_json="$f1" ;;
  NAME) mp_names+=("$f1") ;;
  MP)
    mp_keys+=("$f1")
    mp_loc+=("$f2")
    mp_au+=("$f3")
    mp_lu+=("$f4")
    ;;
  PP) pp_lines+=("$f1") ;;
  TARGET) resolved_target="$f1" ;;
  *) ;;
  esac
done <<<"$pass1"

if [[ "$MODE" == "list" ]]; then
  # Through the same CR-free capture as every other line-oriented output, so a
  # `while read` consumer gets CR-free names by construction. An empty object
  # yields empty output and exit 0: nothing to enumerate is an answer, not an
  # error.
  for n in ${mp_names[@]+"${mp_names[@]}"}; do
    printf '%s\n' "$n"
  done
  exit 0
fi

# --- projectPath liveness (advisory only — NEVER a filter) -------------------
# Answers "is this record's projectPath a directory on this machine right
# now", nothing more. A false is equally consistent with a worktree that was
# removed and with a volume that is merely not mounted, a network share that
# is offline, or removable media that is unplugged — so this field annotates
# a row, and must never suppress one. Suppressing on it would hide real drift
# for anyone whose repos live on an external or network volume.
# Computed per DISTINCT path across every marketplace's records (a machine can
# hold a hundred records naming a dozen directories), so the stat count tracks
# directories, not records, and the answer is taken once for the whole run.
presence_tsv=""
for pp in ${pp_lines[@]+"${pp_lines[@]}"}; do
  [[ -n "$pp" ]] || continue
  pp_fs="${pp//\\//}"
  if [[ -d "$pp_fs" ]]; then
    presence_tsv+="$pp"$'\t'"true"$'\n'
  else
    presence_tsv+="$pp"$'\t'"false"$'\n'
  fi
done

# --- Emit one marketplace's state object ------------------------------------
# Args: marketplace name. Leaves the JSON object (or, under --ids, the
# projected id lines) in FS_BLOCK; on a resolvable per-marketplace failure
# leaves {marketplace:{name,error}} there and returns 1 (caller decides whether
# that is fatal for this invocation). A global rather than stdout so the caller
# never forks a subshell to capture it.
FS_BLOCK=""

error_block_to() {
  # $1 var, $2 name, $3 error, [$4 autoUpdate "true"/"false", $5 lastUpdated]
  local __eb_name __eb_err __eb_lu
  json_string_to __eb_name "$2"
  json_string_to __eb_err "$3"
  if [[ $# -ge 5 ]]; then
    json_string_to __eb_lu "$5"
    printf -v "$1" '{"marketplace":{"name":%s,"autoUpdate":%s,"lastUpdated":%s,"error":%s}}' \
      "$__eb_name" "$4" "$__eb_lu" "$__eb_err"
  else
    printf -v "$1" '{"marketplace":{"name":%s,"error":%s}}' "$__eb_name" "$__eb_err"
  fi
}

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
PASS2_PROGRAM='
  ($c | try (fromjson | {ok: .}) catch {err: true})
  | if .err then "INVALID"
    else "OK", (.ok | .plugins[]? | select((.source | type) == "string") | "E\u001f\(.name)\u001f\(.source)")
    end'

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
PASS3_PROGRAM='
  (. | split("\u001d")) as $parts
  | ($parts[0] | fromjson) as $ctx
  | ($parts[1] | split("\n")
      | map(select(length > 0) | split("\t") | select(length >= 2 and (.[0] | length) > 0)
            | {key: .[0], value: (.[1] == "true")})
      | from_entries) as $pres
  # Entries whose source is not a string never reached the payload, so they
  # are absent from this map entirely — a lookup returns null, the same
  # fail-open answer as an entry whose manifest could not be read. A manifest
  # that does not parse, carries no version, or carries false yields null too;
  # every value this collapses lands on the FAIL-OPEN side, so the collapse
  # cannot cause a wrong withhold. A numeric 0 is preserved.
  | ($parts[2] | split("\u001f")
      | map(select(length > 0) | split("\u001e") | select(length >= 2 and (.[0] | length) > 0)
            | {key: (.[0] + "@" + $name),
               value: (.[1]
                 | if . == "" then null else (try (fromjson | .version) catch null) end
                 | if . == null or . == false then null elif type == "string" then . else tojson end)})
      | from_entries) as $cv
  | ($ci == "true") as $cib
  # Every install record for ids in this marketplace, flattened, with the
  # currentProject flag Windows-normalized on both sides.
  | ($inst[0].plugins | to_entries
      | map(select(.key | endswith("@" + $name))
            | .key as $id
            | .value[]
            | {
                id: $id,
                scope: .scope,
                version: .version,
                projectPath: (.projectPath // null),
                currentProject: (
                  if (.scope == "project" or .scope == "local") and (.projectPath // "" | length) > 0 and ($cur | length) > 0 then
                    (.projectPath | gsub("\\\\"; "/")) as $p |
                    if $cib then ($p | ascii_downcase) == ($cur | ascii_downcase) else $p == $cur end
                  else null end
                ),
                projectPathPresent: (
                  if (.scope == "project" or .scope == "local") and (.projectPath // "" | length) > 0 then
                    # `has` rather than `$pres[$pp] // null`: jq treats FALSE as
                    # empty for `//`, so the alternative operator would silently
                    # rewrite a genuine "not present" into "not checked".
                    .projectPath as $pp
                    | (if ($pres | has($pp)) then $pres[$pp] else null end)
                  else null end
                )
              })) as $installed
  | ([$catalog[0].plugins[]?.name // empty] | unique) as $catalog_names
  | ($catalog_names | map(. + "@" + $name)) as $catalog_ids
  | ([$installed[].id] | unique) as $installed_ids
  # catalog minus installed minus any id explicitly opted out (false) in any
  # scope, even one never installed at all.
  | (($catalog_ids - $installed_ids) - $ctx.false_ids) as $missing_from_install
  # User-scope completeness, distinct from all-scope missing_from_install: a
  # plugin installed only at project/local scope is present all-scope but not
  # usable from other directories, so `sync` Step 4 (which installs at user
  # scope for the "usable from any directory" guarantee) must key off this.
  | ([$installed[] | select(.scope == "user") | .id] | unique) as $user_installed_ids
  | (($catalog_ids - $user_installed_ids) - $ctx.false_ids) as $missing_from_user_install
  # Ids with a project/local record and NO user-scope record. Deliberately NOT
  # filtered to catalog membership: an installed id the catalog no longer
  # carries is exactly the kind of record a reader wants named. An opt-out is
  # an answer, not a gap, so those are subtracted like the two arrays above.
  | (((([$installed[] | select(.scope == "project" or .scope == "local") | .id] | unique)
       - ([$installed[] | select(.scope == "user") | .id] | unique))
      - $ctx.false_ids)) as $user_scope_orphans
  | ($ctx.known_ids | map(select(endswith("@" + $name)))) as $known_at_mp
  # missing_from_enabled can only be computed for ids whose enabledPlugins
  # this invocation can actually read: user scope (global) and the current
  # PROJECT_ROOT'"'"'s project/local scope. A project/local install belonging to a
  # DIFFERENT repo is excluded rather than asserted missing.
  | ([$installed[] | select(.scope == "user" or .currentProject == true) | .id] | unique) as $verifiable_ids
  # Ids the marketplace entry ships with defaultEnabled:false — a publisher'"'"'s
  # deliberate opt-in-required default. No enabledPlugins entry anywhere for
  # one of these is the INTENDED state, not a completeness gap.
  | ([$catalog[0].plugins[]? | select(.defaultEnabled == false) | .name + "@" + $name]) as $default_disabled
  | (($verifiable_ids - $known_at_mp) - $default_disabled) as $missing_from_enabled
  | (reduce $known_at_mp[] as $id ({}; . + {($id): $ctx.effective[$id]})) as $enabled_at_mp
  # `versionsMatch` separates a benign multi-scope install (project and user
  # scope both pinned to the same version — normal, not actionable) from a
  # real version skew (some scope is behind another — the "run converge"
  # signal). A record count alone conflates the two.
  | ($installed | group_by(.id)
      | map(select(length > 1))
      | map({
          id: .[0].id,
          scopes: map({scope, version, projectPath, projectPathPresent}),
          versionsMatch: ((map(.version) | unique | length) == 1)
        })) as $divergences
  | {
      marketplace: {name: $name, autoUpdate: ($au == "true"), lastUpdated: $lastUpdated},
      project_root: (if ($cur | length) > 0 then $cur else null end),
      catalog: $catalog_names,
      catalog_versions: $cv,
      installed: $installed,
      enabled: $enabled_at_mp,
      missing_from_install: $missing_from_install,
      missing_from_user_install: $missing_from_user_install,
      missing_from_enabled: $missing_from_enabled,
      user_scope_orphans: $user_scope_orphans,
      divergences: $divergences
    } as $block
  | if $selector == "" then $block
    elif $selector == "installed-user" then ($block.installed[]? | select(.scope == "user") | .id)
    elif $selector == "update-candidates-user" then
      ($block.catalog_versions as $cvs | $block.installed[]? | select(.scope == "user")
       | select(($cvs[.id]) == null or ($cvs[.id]) != .version) | .id)
    elif $selector == "current-project" then ($block.installed[]? | select(.currentProject == true) | "\(.id)\t\(.scope)")
    elif $selector == "missing-user-install" then $block.missing_from_user_install[]?
    elif $selector == "missing-enabled" then $block.missing_from_enabled[]?
    elif $selector == "user-scope-orphans" then $block.user_scope_orphans[]?
    else error("unknown selector: " + $selector) end'

emit_marketplace() {
  local name="$1"
  local i idx=-1 auto_update_json=false last_updated install_location catalog_json

  for ((i = 0; i < ${#mp_keys[@]}; i++)); do
    if [[ "${mp_keys[i]}" == "$name" ]]; then
      idx=$i
      break
    fi
  done
  if ((idx < 0)); then
    error_block_to FS_BLOCK "$name" "not found in known_marketplaces.json"
    return 1
  fi
  # `auto_update` is jq's own `true`/`false` text; normalized to a JSON literal
  # once here for every block below.
  [[ "${mp_au[idx]}" == "true" ]] && auto_update_json=true
  last_updated="${mp_lu[idx]}"
  install_location="${mp_loc[idx]}"

  if [[ -n "${FLEET_STATE_CATALOG_DIR:-}" ]]; then
    local fixture="$FLEET_STATE_CATALOG_DIR/$name.json"
    if [[ ! -f "$fixture" ]]; then
      error_block_to FS_BLOCK "$name" "no catalog fixture" "$auto_update_json" "$last_updated"
      return 1
    fi
    catalog_json="$fixture"
  else
    catalog_json="$install_location/.claude-plugin/marketplace.json"
    if [[ ! -f "$catalog_json" ]]; then
      error_block_to FS_BLOCK "$name" "marketplace.json not found at installLocation" "$auto_update_json" "$last_updated"
      return 1
    fi
  fi

  # --- Pass 2: the catalog's own entry list ------------------------------------
  # A single marketplace's catalog being malformed is a per-marketplace failure
  # like the branches above — report it inline and return 1 so one corrupt
  # clone doesn't abort an --all sweep of every other marketplace. This is
  # also the only pass that needs the entries as shell data: the manifest each
  # `source` points at is located with builtins below.
  local pass2=""
  jq_to pass2 -rn --rawfile c "$catalog_json" "$PASS2_PROGRAM" || pass2="INVALID"
  if [[ "$pass2" == "INVALID"* ]]; then
    error_block_to FS_BLOCK "$name" "marketplace.json is not valid JSON" "$auto_update_json" "$last_updated"
    return 1
  fi

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
  # Every manifest that passes the -f test is resolved by ONE batched realpath
  # together with the checkout root, so the subprocess count is constant, not
  # proportional to the catalog. Either gate failing yields null → fail open →
  # the id stays a candidate.
  local -a cv_names=() cv_manifests=() prime=("$manifest_base")
  local cv_tag cv_name cv_src cv_rel cv_manifest
  while IFS=$'\x1f' read -r cv_tag cv_name cv_src; do
    [[ "$cv_tag" == "E" ]] || continue
    cv_rel="${cv_src#./}"
    cv_rel="${cv_rel//\\//}"
    case "/$cv_rel/" in
    */../*)
      cv_rel=""
      ;;
    *) ;;
    esac
    cv_manifest=""
    if [[ -n "$cv_rel" && -f "$manifest_base/$cv_rel/.claude-plugin/plugin.json" ]]; then
      cv_manifest="$manifest_base/$cv_rel/.claude-plugin/plugin.json"
      prime+=("$cv_manifest")
    fi
    cv_names+=("$cv_name")
    cv_manifests+=("$cv_manifest")
  done <<<"$pass2"
  hook::_physical_prime "${prime[@]}"

  # Containment root for the check below, resolved ONCE per marketplace.
  # hook::normalize_path folds separators, and on Windows also folds drive-letter
  # case, so two normalized physical paths compare directly with `==` on either
  # platform, so no ad-hoc downcasing here. On failure hook::_physical_cached_to
  # leaves the input in place and returns non-zero; the root itself keeps the
  # old lenient reading (an unresolvable root makes every containment test
  # below fail, which is the fail-open direction).
  local manifest_base_phys resolved contained bundle="" content
  hook::_physical_cached_to manifest_base_phys "$manifest_base" || true
  hook::normalize_path_to manifest_base_phys "$manifest_base_phys"
  manifest_base_phys="${manifest_base_phys%/}"

  for ((i = 0; i < ${#cv_names[@]}; i++)); do
    content=""
    cv_manifest="${cv_manifests[i]}"
    if [[ -n "$cv_manifest" && -n "$manifest_base_phys" ]]; then
      # Fails CLOSED for the containment question, which makes the version
      # fail OPEN: an unresolvable path yields no content, so the id stays an
      # update candidate. Gate on the RETURN STATUS: on failure the helper
      # echoes its input, which still begins with the checkout root, so a
      # naive prefix compare would call it contained without anything having
      # been resolved. Strict prefix: the root itself is not a plugin manifest,
      # and the trailing slash stops "/checkout-evil/..." from matching root
      # "/checkout".
      contained=0
      if hook::_physical_cached_to resolved "$cv_manifest"; then
        hook::normalize_path_to resolved "$resolved"
        [[ "$resolved" == "$manifest_base_phys"/* ]] && contained=1
      fi
      if ((contained)); then
        IFS= read -r -d '' content <"$cv_manifest" || true
      fi
    fi
    bundle+="${cv_names[i]}"$'\x1e'"$content"$'\x1f'
  done

  # --- Pass 3: compose the block -----------------------------------------------
  # The two validated files travel as --slurpfile; everything the shell
  # assembled (context, presence, manifests) travels on stdin as one payload,
  # never on argv, because a large catalog would otherwise exceed the platform
  # argv-length ceiling (#1336). The three sections are separated by U+001D
  # (group separator), which never appears in compact JSON or in a path.
  jq_to FS_BLOCK -Rsrc \
    --slurpfile inst "$INSTALLED_JSON" \
    --slurpfile catalog "$catalog_json" \
    --arg name "$name" \
    --arg au "$auto_update_json" \
    --arg lastUpdated "$last_updated" \
    --arg cur "$current_project_norm" \
    --arg ci "$case_insensitive_os" \
    --arg selector "$IDS_SELECTOR" \
    "$PASS3_PROGRAM" <<<"$ctx_json"$'\x1d'"$presence_tsv"$'\x1d'"$bundle"
}

# Emit one marketplace: the JSON block by default, or its projected id list when
# --ids is in play. Keeps the two single-marketplace call sites (default and
# --marketplace) identical instead of branching on IDS_SELECTOR at each.
emit_one() {
  local rc=0
  emit_marketplace "$1" || rc=$?
  # A per-marketplace failure block ({marketplace: {name, error}}) goes to
  # STDOUT in report mode (documented output contract) but to STDERR under
  # --ids. The documented consumer is `while read … done < <(… --ids …)`, and a
  # process substitution does NOT propagate its command's exit status, so a JSON
  # object left on stdout would be read as an id and handed to `claude plugin
  # update` verbatim. Under --ids stdout carries records or nothing at all.
  if [[ "$rc" -ne 0 ]]; then
    if [[ -n "$FS_BLOCK" ]]; then
      if [[ -n "$IDS_SELECTOR" ]]; then
        printf '%s\n' "$FS_BLOCK" >&2
      else
        printf '%s\n' "$FS_BLOCK"
      fi
    fi
    return "$rc"
  fi
  # Zero --ids matches is success with EMPTY output, never a blank line.
  [[ -n "$FS_BLOCK" ]] && printf '%s\n' "$FS_BLOCK"
  return 0
}

case "$MODE" in
default)
  TARGET="$resolved_target"
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
  # The envelope is composed in the shell around each block's compact JSON,
  # the same bytes `jq -c` would print for the same object, with the keys in
  # the sorted order pass 1 enumerated them.
  result='{"marketplaces":{'
  sep=""
  for n in ${mp_names[@]+"${mp_names[@]}"}; do
    [[ -n "$n" ]] || continue
    emit_marketplace "$n" || true
    json_string_to key_json "$n"
    result+="$sep$key_json:$FS_BLOCK"
    sep=","
  done
  result+='}}'
  printf '%s\n' "$result"
  ;;
*)
  echo "ERROR: unreachable mode: $MODE" >&2
  exit 2
  ;;
esac
