#!/usr/bin/env bash
# Deterministic executor for `sync`/`audit` Steps 1 through 5b, one JSON digest out.
#
# `context/sync.md` is the normative algorithm and states why each step exists.
# This script is that algorithm's executable form: it runs the whole per-marketplace
# loop in ONE process and prints a single digest the model reads, rather than the
# model retyping each step's bash into its own turn. Every invariant sync.md fixes
# holds here — per-step `fleet-state.sh` re-reads, the run journal, the
# `rc=${PIPESTATUS[0]}` capture after every `tee`-journaled mutating call, the
# downgrade guard, the projection exit-status check, the per-marketplace failure
# rule, and Step 4/5 gating on the fresh pre-install read.
#
# The one decision it cannot make is the `install_new` policy: `${user_config.*}`
# substitutes only when Claude Code renders SKILL.md, so the caller passes the
# rendered value with `--install-new`. On `ask` with a non-empty install gap the
# script reports the gap and STOPS before Step 4; the caller prompts and re-enters
# with `--only-install`.
#
# Usage:
#   sync-run.sh [--marketplace <name> | --all] --journal-root <dir>
#               [--install-new all|none|ask] [--allow-downgrade] [--render]
#               [--source-pull ask|never] [--pull-source <names>]
#               [--quiet-auto-update <names>]
#   sync-run.sh [--marketplace <name> | --all] --audit
#               [--install-new all|none|ask] [--allow-downgrade] [--render]
#               [--source-pull ask|never] [--quiet-auto-update <names>]
#   sync-run.sh --only-install <ids> --run-dir <dir> [--marketplace <name> | --all]
#               [--render]
#
# `--source-pull` is the rendered `directory_source_pull` option (ask, the
# default, or never; any other value is treated as ask and named in the digest).
# `--pull-source <names>` names the marketplaces whose `directory` checkout the
# user agreed to fast-forward: before that marketplace's Step 1 refresh the script
# runs `git -C <path> pull --ff-only`, but only when the policy is ask, no
# CLAUDE_CODE_REMOTE is set, and the checkout is clean, on a branch with an
# upstream, not ahead, and behind; otherwise it refuses with the reason and
# touches nothing. `--quiet-auto-update <names>` drops the enable-it suggestion
# from those marketplaces' `autoUpdate: off` slot. Both lists are comma- or
# space-separated marketplace names.
#
# Step 6 is rendered here too: `render-report.jq` turns the digest into the
# fixed-section report SKILL.md's Report section fixes, written to
# `<run_dir>/report.txt` on every run and, under `--render`, printed to stdout
# after the digest line. Every row, annotation and `Action needed` bullet is a
# function of digest fields, so the caller appends the reload guidance and
# nothing else.
#
# With neither `--marketplace` nor `--all`, the target is the default marketplace
# `fleet-state.sh` resolves dynamically from `CLAUDE_PLUGIN_ROOT`; no marketplace
# name is hardcoded anywhere in this script. `--all` runs Steps 2-5b once per
# marketplace from `fleet-state.sh --marketplaces`, and a marketplace whose
# iteration fails is recorded in that block's `errors[]` without aborting the rest.
#
# `--journal-root <dir>` is REQUIRED in sync mode and is the run journal's parent.
# SKILL.md passes the substituted `${CLAUDE_PLUGIN_DATA}` path because that token
# resolves in skill content and not in a `context/*.md` spoke. `--audit` ignores it
# and uses a scratch directory under `${TMPDIR:-${TEMP:-.}}`, removed on exit, so an
# audit leaves nothing behind.
#
# `--only-install <ids>` is the narrow re-entry after an `ask` prompt: a comma- or
# space-separated list of fully-qualified `<name>@<marketplace>` ids to install
# (empty is legal and means install nothing), against the run directory the first
# invocation reported. It runs Step 4, the normalizer, Step 5, and the post re-read,
# and re-emits the full digest. When the first pass stopped before install it
# skipped Step 5b, and this re-entry runs that check after the installs land.
# When the first pass already ran Step 5b, the re-entry reuses that report. The
# cache checker therefore runs exactly ONCE per marketplace across both
# invocations, on the pass that follows the installs. The re-entry also keeps the
# run's `allow_downgrade`, `install_new` and `install_new_invalid` from
# `flags.json`, and adds the first pass's run timings from `first-pass-run.json`.
#
# Output (stdout): one compact JSON object, also written to `<run_dir>/digest.json`,
# followed under `--render` by a blank line and the rendered report.
#   {run_dir, cwd, mode, allow_downgrade, install_new, install_new_invalid,
#    source_pull, source_pull_invalid, quiet_auto_update,
#    timings:{total,outside_marketplaces,resolution[,passes]}, marketplaces:[…], errors:[…]}
#   `source_pull` is the policy the run applied: `never` when the option says so
#   or CLAUDE_CODE_REMOTE is set. `quiet_auto_update` is the names array.
#   On a re-entry, `timings.passes` is `[{pass: "first", …}, {pass: "only_install", …}]`,
#   each `{total, outside_marketplaces, resolution}`, and the top-level `total` and
#   `outside_marketplaces` sum the two; the wait between the passes is in neither.
#   Each marketplace block: {name, timings, catalog_last_updated, catalog_source,
#    source_checkout, source_pull, auto_update, refresh:{rc,output,predicted}, project_root,
#    in_repo:{updated,failed,would_update,live_read},
#    user_sweep:{updated,failed,would_update,withheld_downgrades},
#    downgraded, moved_during_run, noop_unverified, install_gap, installed, installed_with_unset_user_config,
#    install_enable_deferred, stopped_before_install, enable_gap, enabled,
#    pending_enable, project_enable_rows, normalize, cache_content, catalog_regression,
#    divergences, divergences_here, in_repo_records, in_repo_ids,
#    stale_project_records, user_scope_orphans, installed_disabled, delisted,
#    delisted_project, delisted_settings_only, other_paths, self_updated, self_update,
#    updated_with_monitors, errors}
#   `other_paths` is `{updated, failed, not_moved, would_update}` for the
#   project/local records of every OTHER present path (a user home and a linked
#   worktree included) whose version is below a readable catalog version: sync
#   runs `update -s <scope>` from that path and reads each record back.
#   `updated[]` is `{id, scope, path, old, new}`, `would_update[]` (audit) is
#   `{id, scope, path, old, catalog}`, `not_moved[]` is `{id, scope, path,
#   version, catalog, label}` for a linked-worktree or user-home record the call
#   left behind, and `failed[]` is `{id, scope, path, reason, stopped}` for any
#   other record left behind, a failed call, and, with `stopped` true, the call
#   after which the path's `.claude/` settings changed and every record in that
#   path not tried after it.
#   `installed_with_unset_user_config[]` is `{id, options_unset, required}` for
#   each install this run performed whose CLI output named userConfig options
#   the user has not set. `installed_disabled[]` is the ids whose install exited
#   0 and whose output said the plugin is disabled by default, classified before
#   the 400-character truncation, less any this run then enabled at user scope
#   (an `--only-install` pick is). `delisted[]` is the user-scope installs the
#   catalog's names no longer carry, `delisted_project[]` the `{id, scope}` of
#   each install in the repo the run stands in that those names no longer carry,
#   and `delisted_settings_only[]` the effective `true` enabledPlugins keys at
#   this marketplace with no install record that the names no longer carry; a
#   catalog with an empty plugins array produces none of the three.
#   `self_update` is `{id, scope, old, new}` for the first record of this plugin
#   the run moved (the row `self_updated` is true for), else null.
#   `updated_with_monitors[]` is `{id, scope, monitors}` for each plugin this
#   run moved whose installed manifest declares a monitor.
#   `catalog_last_updated` is the marketplace's lastUpdated as Step 2's read saw
#   it, after Step 1's refresh; a background refresh can move it later in the run.
#   `timings` holds one key per step plus `unattributed`, the rest of the block's
#   `total`, so the steps and the remainder sum to it.
#   `in_repo_records` counts the project/local records belonging to the repo the
#   run stands in, whether or not any of them moved; `stale_project_records` is
#   `{total, paths, project, by_parent:[{parent,count,paths}], more_parents, list_file}`,
#   `project` counting the project-scope records among `total`,
#   with the full `[{path,count}]` in `list_file` (null under --audit);
#   `user_home_records` is `{total, paths}` for the project/local records whose
#   projectPath is a user home (`projectPathIsHome`) and that are still below
#   the catalog version, or have none to compare (under --audit, less the
#   present ones sync would update), which `divergences` and `divergences_here`
#   never count;
#   `cache_content.scope` is `user`, the only
#   records Step 5b compares, and `cache_content.stale[]` is
#   `{id, version, files_differ, unreleased_changes}` per stale install, the last
#   true when the clone holds `.changes/<plugin>/`; `cache_content.not_checked`
#   counts the installs recorded at a commit other than the clone's HEAD, which
#   the checker does not compare. `in_repo.live_read[]` is
#   `{id, scope, installed, path}`, filled under --audit only, for each in-repo
#   record of a marketplace whose `directory` source is the run's own project
#   root (or a folder under it): the CLI reads that folder live and will not
#   update the record, so it is not in `would_update`. `source_checkout` is null
#   unless the source is `directory`; then it is `{path, state, branch, upstream,
#   ahead, behind, dirty}` with `state` one of tracking, no_upstream, detached,
#   not_a_repo, and the counts as of the checkout's last fetch (never fetched here
#   except by a requested fast-forward). `source_pull` is null unless the checkout
#   is behind or a fast-forward was requested; then it is `{status, reason}` with
#   status `offered` (eligible, policy ask, sync mode: the caller may ask),
#   `skipped` (not requested, and not eligible, policy never, an autonomous
#   session, or audit), `refused` (requested, and the guard said no), `pulled`
#   (plus `from` and `to` commits) or `failed` (plus `rc`, `from` and `to`).
#   `marketplace_update` timing includes a requested pull.
#   `enable_gap` is the gap the step FOUND; `enabled` is what it filled at user and
#   local scope, and `project_enable_rows` is what it reports rather than writes.
#   `pending_enable[]` is `{id, outcome}` (`enabled` or `enable_failed`) for each
#   id an earlier interrupted `ask` run left in pending-enable.txt that this run
#   found installed at user scope and effectively `false`, and tried to enable.
#   `updated` carries forward moves and unreadable-direction moves (flagged
#   `direction: "unknown"`); a pair whose new version is LOWER lands in `downgraded`
#   instead, which is what keeps a backward move off the report's `Updated:` line
#   even for an id the guard could not prove in advance.
#   `divergences` is `{pre, mid, post, new_total, new_by_interval, pre_existing,
#   actionable_here, actionable_elsewhere, in_worktrees, blocked, records, by_path}`:
#   `post` counts the actionable (`versionsMatch: false`) rows, and
#   `actionable_here` through `blocked` split it by what an operator can do about
#   each row (see `divergence_block`). A digest written before the split carries
#   none of the four. `records[]` is `{id, scope, version, projectPath}` for every
#   record that makes a counted row skewed (projectPath null at user scope), and
#   `by_path[]` is `{path, class, count, ids, more}` per projectPath among them,
#   `class` the path's pin class (`actionable`, `worktree` or `blocked`), the
#   actionable paths first and then most records first, `ids` the first
#   DIVERGENCE_PATH_IDS distinct ids and `more` the rest. A digest written before
#   them carries neither, and one written before `class` carries no `class`.
#   `moved_during_run[]` is `{id, scope, kind, old, new, direction}` for each id whose
#   update call the CLI answered "already at the latest version" while the post
#   snapshot's version differs from the pre-mutation one: it moved during the run
#   under something other than this run's update calls. A backward one is also in
#   `downgraded`, flagged `concurrent: true`. `noop_unverified` counts the already-
#   current answers the snapshots could not confirm (a version unread, or the
#   snapshot and the CLI's printed version disagreeing); those ids stay no-ops.
#   Ids and counts only: the digest is read by a model in one turn, so per-file
#   cache-check detail stays in `<run_dir>/cache-content.<mp>.json`.
#
# Exit codes:
#   0  the run completed; per-marketplace and per-id failures are reported in the
#      digest body, because a failed id is a finding, not a run failure
#   2  usage error, a missing prerequisite, or a run-level failure that left no
#      digest to emit
#
# Env overrides (testing only; production uses the bundled siblings):
#   SYNC_RUN_FLEET_STATE     path to fleet-state.sh
#   SYNC_RUN_CACHE_CHECK     path to cache-content-check.sh
#   SYNC_RUN_NORMALIZE       path to normalize-enabled-plugins.sh
#   SYNC_RUN_CLAUDE_BIN      the `claude` CLI to invoke (default: `claude` on PATH)
#   SYNC_RUN_VERSION_DIRECTION  testing only: "old<TAB>new" prints version_direction
#                            and exits before any fleet read

# `set -e` is deliberately absent: it would abort a `{ …; } | tee` pipeline whose
# CLI element failed before `${PIPESTATUS[0]}` is read, and that status is what
# every mutating step here branches on.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_STATE="${SYNC_RUN_FLEET_STATE:-$SCRIPT_DIR/fleet-state.sh}"
CACHE_CHECK="${SYNC_RUN_CACHE_CHECK:-$SCRIPT_DIR/cache-content-check.sh}"
NORMALIZE="${SYNC_RUN_NORMALIZE:-$SCRIPT_DIR/normalize-enabled-plugins.sh}"
CLAUDE_BIN="${SYNC_RUN_CLAUDE_BIN:-claude}"
# The stale-project-records section prints at most this many parent directories.
STALE_PARENT_ROWS=10
# Each Divergences sub-line names at most this many ids of its project path.
DIVERGENCE_PATH_IDS=3

# jq-capture.sh is this script's own fixed sibling, carrying the `jq_to` capture
# every jq call here goes through, shared with fleet-state.sh and
# cache-content-check.sh. Resolved from this script's own location, never from a
# SYNC_RUN_* override, so nothing a caller sets can redirect `source` at an
# arbitrary file.
JQ_CAPTURE="$SCRIPT_DIR/jq-capture.sh"
if [[ -f "$JQ_CAPTURE" ]]; then
  # shellcheck source=jq-capture.sh
  source "$JQ_CAPTURE"
else
  echo "ERROR: jq-capture.sh not found at $JQ_CAPTURE" >&2
  exit 2
fi

# fleet-state.sh resolves the DEFAULT marketplace by joining CLAUDE_PLUGIN_ROOT
# against the install records, so a headless run that never had it set still gets a
# target instead of an error. This script's own location is inside the plugin root
# by construction (<root>/skills/plugins/scripts), so it is the honest default.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

# --- clock ---------------------------------------------------------------------
# Every step is stamped so the digest reports where a run spent its time. The
# stamp source is a ladder, resolved once and named in the digest as `resolution`:
#   microseconds  bash's EPOCHREALTIME (bash 5.0 and later; the manual documents
#                 it as seconds since the Epoch with micro-second granularity)
#   nanoseconds   `date +%s.%N`, accepted only when the output is digits, one dot,
#                 digits: %N is a GNU extension and an older `date` prints a
#                 literal `N` instead of a fraction
#   seconds       `date +%s`, the one form every `date` documents (macOS system
#                 bash is 3.2 and has no EPOCHREALTIME, so this rung is real there)
# The timings are a diagnostic measurement with no gate, so a coarse rung is
# acceptable and labeled rather than an error. Stamps are kept as strings and
# subtracted in jq at emit time, because bash has no float arithmetic; a `,`
# radix (the manual leaves EPOCHREALTIME's locale behavior unstated) is
# rewritten to `.` first so every field is a JSON number.
# SYNC_RUN_NO_EPOCHREALTIME=1 is the test seam that forces the `date` rungs on a
# bash that has the variable: a child shell recreates it at startup, so a caller
# cannot unset it from outside.
CLOCK_RESOLUTION=""
resolve_clock() {
  local probe
  [[ "${SYNC_RUN_NO_EPOCHREALTIME:-0}" != "1" ]] || unset EPOCHREALTIME
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    CLOCK_RESOLUTION="microseconds"
    return 0
  fi
  probe=$(LC_ALL=C date +%s.%N 2>/dev/null)
  if [[ "$probe" =~ ^[0-9]+\.[0-9]+$ ]]; then
    CLOCK_RESOLUTION="nanoseconds"
  else
    CLOCK_RESOLUTION="seconds"
  fi
}
# clock_into VAR: the current stamp, `.` radix, into VAR without a subshell on
# the EPOCHREALTIME rung.
clock_into() {
  local __var="$1"
  local t
  case "$CLOCK_RESOLUTION" in
  microseconds) t="${EPOCHREALTIME:-}" ;;
  nanoseconds) t=$(LC_ALL=C date +%s.%N) ;;
  *) t=$(date +%s) ;;
  esac
  printf -v "$__var" '%s' "${t//,/.}"
}
resolve_clock
T_RUN_S=""
clock_into T_RUN_S
# The default-marketplace read main takes before the loop is Step 1's pre-refresh
# read for that marketplace, so its stamps are handed to the loop body.
MAIN_READ_MP="" MAIN_READ_S="" MAIN_READ_E=""

MODE="sync"
TARGET_MP=""
ALL=0
ALLOW_DOWNGRADE=0
INSTALL_NEW="ask"
INSTALL_NEW_INVALID=""
JOURNAL_ROOT=""
RUN_DIR=""
ONLY_INSTALL=""
ONLY_INSTALL_MODE=0
RENDER=0
SOURCE_PULL="ask"
SOURCE_PULL_INVALID=""
# Why the run will not pull: empty, `policy never`, or the autonomous session.
SOURCE_PULL_OFF=""
PULL_SOURCES=""
PULL_SOURCES_SET=0
QUIET_AUTO_UPDATE=""

usage() {
  cat <<'EOF'
sync-run.sh — run `sync`/`audit` Steps 1-5b and print one JSON digest.

Usage:
  sync-run.sh [--marketplace <name> | --all] --journal-root <dir>
              [--install-new all|none|ask] [--allow-downgrade] [--render]
              [--source-pull ask|never] [--pull-source <names>]
              [--quiet-auto-update <names>]
  sync-run.sh [--marketplace <name> | --all] --audit
              [--install-new all|none|ask] [--allow-downgrade] [--render]
              [--source-pull ask|never] [--quiet-auto-update <names>]
  sync-run.sh --only-install <ids> --run-dir <dir> [--marketplace <name> | --all]
              [--render]

--render prints the Step 6 report (render-report.jq over the digest) after the
digest line; the report is written to <run_dir>/report.txt either way.
--audit is the dry run: it reads the fleet, predicts every claude call without
issuing it, and leaves nothing behind.
--pull-source fast-forwards each named marketplace's directory checkout before
its refresh, only when the checkout is clean, tracking, not ahead and behind.

Exit: 0 the run completed (per-marketplace and per-id failures are in the digest);
2 usage error, jq missing, or a run-level failure that left no digest.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --marketplace)
    [[ $# -ge 2 ]] || {
      echo "ERROR: --marketplace requires a name" >&2
      exit 2
    }
    TARGET_MP="$2"
    shift 2
    ;;
  --all)
    ALL=1
    shift
    ;;
  --audit)
    MODE="audit"
    shift
    ;;
  --allow-downgrade)
    ALLOW_DOWNGRADE=1
    shift
    ;;
  --render)
    RENDER=1
    shift
    ;;
  --install-new)
    [[ $# -ge 2 ]] || {
      echo "ERROR: --install-new requires a value" >&2
      exit 2
    }
    INSTALL_NEW="$2"
    shift 2
    ;;
  --journal-root)
    [[ $# -ge 2 ]] || {
      echo "ERROR: --journal-root requires a directory" >&2
      exit 2
    }
    JOURNAL_ROOT="$2"
    shift 2
    ;;
  --run-dir)
    [[ $# -ge 2 ]] || {
      echo "ERROR: --run-dir requires a directory" >&2
      exit 2
    }
    RUN_DIR="$2"
    shift 2
    ;;
  --only-install)
    [[ $# -ge 2 ]] || {
      echo "ERROR: --only-install requires an id list (an empty string is legal)" >&2
      exit 2
    }
    ONLY_INSTALL="$2"
    ONLY_INSTALL_MODE=1
    shift 2
    ;;
  --source-pull)
    [[ $# -ge 2 ]] || {
      echo "ERROR: --source-pull requires a value" >&2
      exit 2
    }
    SOURCE_PULL="$2"
    shift 2
    ;;
  --pull-source)
    [[ $# -ge 2 ]] || {
      echo "ERROR: --pull-source requires marketplace names" >&2
      exit 2
    }
    PULL_SOURCES="$2"
    PULL_SOURCES_SET=1
    shift 2
    ;;
  --quiet-auto-update)
    [[ $# -ge 2 ]] || {
      echo "ERROR: --quiet-auto-update requires marketplace names" >&2
      exit 2
    }
    QUIET_AUTO_UPDATE="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if ((ALL == 1)) && [[ -n "$TARGET_MP" ]]; then
  echo "ERROR: --all cannot be combined with --marketplace" >&2
  exit 2
fi

# An unsupported value becomes the default and is NAMED in the digest, the rule
# SKILL.md states for the rendered option: a policy the caller thought it set must
# never disappear silently.
case "$INSTALL_NEW" in
all | none | ask) ;;
*)
  INSTALL_NEW_INVALID="$INSTALL_NEW"
  INSTALL_NEW="ask"
  ;;
esac
# The same rule for the pull policy. `ask` is the safe default here too: the
# script pulls only a checkout the caller names after a yes.
case "$SOURCE_PULL" in
ask | never) ;;
*)
  SOURCE_PULL_INVALID="$SOURCE_PULL"
  SOURCE_PULL="ask"
  ;;
esac
# No human can answer the offer in an autonomous session, so the run neither
# offers nor pulls there: the same test converge applies before touching anything.
# Applied again after an --only-install re-entry restores the run's saved policy.
apply_pull_policy() {
  if [[ -n "${CLAUDE_CODE_REMOTE:-}" ]]; then
    SOURCE_PULL="never"
    SOURCE_PULL_OFF="autonomous session (CLAUDE_CODE_REMOTE set)"
  elif [[ "$SOURCE_PULL" == "never" ]]; then
    SOURCE_PULL_OFF="policy never"
  else
    SOURCE_PULL_OFF=""
  fi
}
apply_pull_policy

if ((PULL_SOURCES_SET == 1)); then
  if [[ "$MODE" == "audit" ]]; then
    echo "ERROR: --pull-source is a sync-mode request; audit changes nothing" >&2
    exit 2
  fi
  if ((ONLY_INSTALL_MODE == 1)); then
    echo "ERROR: --pull-source runs before Step 1; an --only-install re-entry starts at Step 4" >&2
    exit 2
  fi
fi

if ((ONLY_INSTALL_MODE == 1)); then
  if [[ -z "$RUN_DIR" ]]; then
    echo "ERROR: --only-install requires --run-dir <dir> (the run it re-enters)" >&2
    exit 2
  fi
  if [[ ! -d "$RUN_DIR" ]]; then
    echo "ERROR: --run-dir is not a directory: $RUN_DIR" >&2
    exit 2
  fi
  if [[ "$MODE" == "audit" ]]; then
    echo "ERROR: --only-install is a sync-mode re-entry; audit installs nothing" >&2
    exit 2
  fi
elif [[ "$MODE" == "sync" && -z "$JOURNAL_ROOT" ]]; then
  echo "ERROR: --journal-root <dir> is required in sync mode" >&2
  echo "  SKILL.md passes the substituted \${CLAUDE_PLUGIN_DATA} journal path;" >&2
  echo "  a context/*.md spoke is read raw and cannot substitute it." >&2
  exit 2
fi

# Checked after argument parsing so --help and usage errors work without jq.
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required (install with: winget install jqlang.jq | apt install jq | brew install jq)" >&2
  exit 2
fi

# JSON array of the non-empty lines of a file, CR-stripped. Used for every id list
# in the digest, so a `\r` can never ride into a report row or a later CLI call.
json_lines() {
  local __var="$1"
  local __file="$2"
  if [[ ! -f "$__file" ]]; then
    printf -v "$__var" '%s' '[]'
    return 0
  fi
  jq_to "$__var" -R -s -c 'gsub("\r"; "") | split("\n") | map(select(length > 0))' <"$__file"
}

# JSON array literal from the shell array named by $2, empty array included.
json_array_of() {
  local __var="$1"
  shift
  if (($# == 0)); then
    printf -v "$__var" '%s' '[]'
    return 0
  fi
  jq_to "$__var" -c -s '.' <<<"$(printf '%s\n' "$@")"
}

# JSON array of STRING literals from the shell array named by $2 onward: the
# message arrays, whose elements are prose rather than JSON.
json_strings_of() {
  local __var="$1"
  shift
  if (($# == 0)); then
    printf -v "$__var" '%s' '[]'
    return 0
  fi
  jq_to "$__var" -c -R -s 'split("\n") | map(select(length > 0))' <<<"$(printf '%s\n' "$@")"
}

# Writes the object {"<name>": <value>, ...} to the file $1 from name and value
# pairs, each name a plain identifier written unescaped and each value already
# JSON text, for a jq program to destructure with `. as {$name, ...}`. A value
# that grows with the fleet (the divergence records, the installed and enabled
# rows) can pass the kernel's cap on one exec argument, so it reaches jq through
# this file, never as --argjson; see context/gotchas.md.
# printf is a builtin, so writing the file is not an exec. An empty value leaves
# the file invalid JSON, and the jq that reads it fails rather than reading null.
json_object_file() {
  local __file="$1"
  local __sep=""
  shift
  {
    printf '{'
    while (($# >= 2)); do
      printf '%s"%s":%s' "$__sep" "$1" "$2"
      __sep=","
      shift 2
    done
    printf '}\n'
  } >"$__file"
}

RUN_ERRORS=()
MP_ERRORS=()

run_error() { RUN_ERRORS+=("$1"); }
mp_error() { MP_ERRORS+=("$1"); }

# --- version direction ---------------------------------------------------------
# The same major.minor.patch triple compare the downgrade guard uses. Anything that
# does not parse on both sides is "unknown", never silently ranked: an unrankable
# pair is reported as such rather than assumed forward.
version_direction() {
  local old="$1"
  local new="$2"
  local ore_ok=0
  local nre_ok=0
  local o1
  local o2
  local o3
  local n1
  local n2
  local n3
  # Base 10 on every capture. A bare ((08)) is an octal error that makes the
  # pair "unknown", and a longer leading-zero segment such as 010 is octal
  # with no error and the wrong rank. sync.md's triple compare is decimal.
  if [[ "$old" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    o1=$((10#${BASH_REMATCH[1]}))
    o2=$((10#${BASH_REMATCH[2]}))
    o3=$((10#${BASH_REMATCH[3]}))
    ore_ok=1
  fi
  if [[ "$new" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    n1=$((10#${BASH_REMATCH[1]}))
    n2=$((10#${BASH_REMATCH[2]}))
    n3=$((10#${BASH_REMATCH[3]}))
    nre_ok=1
  fi
  if [[ "$ore_ok$nre_ok" != "11" ]]; then
    echo "unknown"
    return 0
  fi
  if ((n1 > o1)) || { ((n1 == o1)) && ((n2 > o2)); } ||
    { ((n1 == o1)) && ((n2 == o2)) && ((n3 > o3)); }; then
    echo "forward"
  elif ((n1 < o1)) || { ((n1 == o1)) && ((n2 < o2)); } ||
    { ((n1 == o1)) && ((n2 == o2)) && ((n3 < o3)); }; then
    echo "backward"
  else
    # Triples tie while the strings differ (`1.2.3` vs `1.2.3-beta`): the compare
    # cannot rank a suffix, so the pair is unknown rather than forward.
    if [[ "$old" == "$new" ]]; then echo "same"; else echo "unknown"; fi
  fi
}

# Testing only. "old<TAB>new" prints version_direction and exits before any
# fleet read, so a leading-zero segment can be asserted without a catalog.
if [[ -n "${SYNC_RUN_VERSION_DIRECTION:-}" ]]; then
  version_direction "${SYNC_RUN_VERSION_DIRECTION%%$'\t'*}" "${SYNC_RUN_VERSION_DIRECTION#*$'\t'}"
  exit 0
fi

# That id's version in a saved fleet-state report, at that scope. Empty when the
# report does not carry the record. A project or local record counts only when it
# belongs to the project the run stands in (`currentProject`): several worktrees
# can each hold a record of one id, and the first in file order is not this one.
version_at() {
  local __var="$1"
  local report="$2"
  local id="$3"
  local scope="$4"
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to "$__var" -r --arg id "$id" --arg sc "$scope" \
    'first(.installed[]? | select(.id == $id and .scope == $sc
      and ($sc == "user" or .currentProject == true)) | .version) // ""' "$report"
}

# --- journaled mutation --------------------------------------------------------
# The canonical shape from sync.md's "Run journal": the call and its output are
# appended to journal.log through `tee`, and `${PIPESTATUS[0]}` is read as the very
# next statement. A pipeline's own `$?` is `tee`'s status, and `tee` succeeds
# whenever it can write the log, so without this capture a failed CLI call journals
# its own error text and is then read as a success.
CLI_OUT=""
CLI_RC=0
# The directory a project/local call runs from when it is not the run's own:
# `-s project` and `-s local` have no path flag and act on the cwd.
CLI_CWD=""
run_cli() {
  local label="$1"
  shift
  local sink="$RUN_DIR/.last-cli-out"
  {
    echo "\$ $label"
    # stdin closed: the CLI's confirmation for a marketplace-declared command
    # must fail, not wait on a prompt whose text is captured into the journal.
    if [[ -n "$CLI_CWD" ]]; then
      (cd "$CLI_CWD" && exec "$CLAUDE_BIN" "$@") 2>&1 </dev/null
    else
      "$CLAUDE_BIN" "$@" 2>&1 </dev/null
    fi
  } | tee -a "$JOURNAL_LOG" >"$sink"
  CLI_RC=${PIPESTATUS[0]}
  CLI_OUT=$(<"$sink")
  CLI_OUT="${CLI_OUT//$'\r'/}"
  # A CLI older than `--json` (before 2.1.268) rejects it as an unknown option:
  # run the call once more without it and read its text output.
  if ((CLI_RC != 0)) && [[ " $* " == *" --json "* && "$CLI_OUT" == *"unknown option"*"--json"* ]]; then
    local -a args=()
    local arg
    for arg in "$@"; do [[ "$arg" == --json ]] || args+=("$arg"); done
    run_cli "${label/ --json/}" "${args[@]}"
  fi
}

# audit's stand-in for run_cli: journals the prediction, issues nothing.
predict_cli() {
  local label="$1"
  echo "would run: $label" >>"$JOURNAL_LOG"
  CLI_RC=0
  CLI_OUT="would run: $label"
}

# The result line `claude plugin install|update --json` prints (Claude Code
# 2.1.268 or later): the last output line that is a JSON object with a `command`
# key, or empty when there is none, as from a CLI older than the flag. stderr is
# merged into the capture, so a `✘ Failed ...` line and a marketplace-declared
# command's review text can sit beside it.
#   Claim: update prints `updateOutcome` (`updated`, `up_to_date`), `oldVersion`
#     and `newVersion`; install and update print `outcome` (`ok`, `failed`),
#     `message` and, on failure, `failureCode`. No field names unset userConfig
#     options or a disabled-by-default install: both are sentences in `message`.
#   Basis: attended probe on Claude Code 2.1.310 (WSL2), captured in
#     sync-run.test.sh's stub shapes; plugins CLI reference, plugin JSON result.
#   As of: 2026-10-25.
#   Recheck: a Claude Code release that adds a field for either sentence, or
#     changes `updateOutcome`'s values.
cli_json() {
  local __var="$1"
  local __text="$2"
  local __line __found=""
  while IFS= read -r __line || [[ -n "$__line" ]]; do
    [[ "$__line" == '{'* ]] || continue
    jq -e 'type == "object" and has("command")' <<<"$__line" >/dev/null 2>&1 && __found="$__line"
  done <<<"$__text"
  printf -v "$__var" '%s' "$__found"
}

# The text the sentence classifiers below read: the result's `message` when the
# CLI printed a result line, the whole output otherwise.
cli_message() {
  local __var="$1"
  local __text="$2"
  local __json
  cli_json __json "$__text"
  if [[ -n "$__json" ]]; then
    jq_to "$__var" -r '.message // ""' <<<"$__json"
  else
    printf -v "$__var" '%s' "$__text"
  fi
}

# `<new>` from the CLI's own result, which is the only source that reflects an
# update immediately (sync.md's source 2): `newVersion` when `updateOutcome` is
# `updated` or `up_to_date`. Without a result line, the text's `updated from X to
# Y` or `already at the latest version (X)`. Empty when neither names a version.
# For an already-current result it is the install's version as the CLI read it,
# which finalize_moves checks against the snapshots.
cli_reported_version() {
  local __var="$1"
  local text="$2"
  local json
  cli_json json "$text"
  if [[ -n "$json" ]]; then
    jq_to "$__var" -r 'if .updateOutcome == "updated" or .updateOutcome == "up_to_date"
      then .newVersion // "" else "" end' <<<"$json"
  elif [[ "$text" =~ updated\ from\ ([^[:space:]]+)\ to\ ([^[:space:]]+) ]]; then
    printf -v "$__var" '%s' "${BASH_REMATCH[2]}"
  elif [[ "$text" =~ already\ at\ the\ latest\ version\ \(([^\)[:space:]]+)\) ]]; then
    printf -v "$__var" '%s' "${BASH_REMATCH[1]}"
  else
    printf -v "$__var" '%s' ""
  fi
}

# The install's sentence about userConfig options the user has not set, as a
# JSON object `{options_unset, required}` or `null`. The result line has no field
# for it (cli_json's claim), so this reads the sentence in `message`. Classified at
# capture time from the UNTRUNCATED output: the digest row keeps 400 characters.
#   Claim: the sentence is "<N> userConfig option(s) not yet set[ (<M> required)]
#     — run /plugin configure <id> in Claude Code, or pass --config KEY=VALUE."
#   Basis: attended probe on Claude Code 2.1.310, `plugin install --json`
#     `message` with two options and with three.
#   As of: 2026-10-25.
#   Recheck: as cli_json.
unset_user_config_of() {
  local __var="$1"
  local text
  cli_message text "$2"
  if [[ "$text" =~ ([0-9]+)\ userConfig\ options?\ not\ yet\ set(\ \(([0-9]+)\ required\))? ]]; then
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to "$__var" -c -n --arg n "${BASH_REMATCH[1]}" --arg r "${BASH_REMATCH[3]:-}" \
      '{options_unset: ($n | tonumber), required: (if $r == "" then null else ($r | tonumber) end)}'
  else
    printf -v "$__var" '%s' "null"
  fi
}

# What the CLI said it did, classified at capture time, because the outcome is not
# recoverable later: an id the CLI reported as ALREADY CURRENT and an id whose
# update the state write has not landed for both read as "no version change" from a
# post-sweep snapshot. Reporting the first as an update with an unknown version
# would put most of an already-current fleet under `Updated:`.
#   updated  `updateOutcome: updated`, or text naming a version pair
#   noop     `updateOutcome: up_to_date`, or "already at the latest version". That
#            is the CLI's word only: finalize_moves checks it against the
#            snapshots before it drops the id, because an id that something else
#            moved earlier in the run reads the same
#   other    neither; the post-sweep read decides
cli_move_result() {
  local __var="$1"
  local text="$2"
  local json outcome=""
  cli_json json "$text"
  if [[ -n "$json" ]]; then
    jq_to outcome -r '.updateOutcome // ""' <<<"$json"
    case "$outcome" in
    updated) printf -v "$__var" '%s' "updated" ;;
    up_to_date) printf -v "$__var" '%s' "noop" ;;
    *) printf -v "$__var" '%s' "other" ;;
    esac
    return 0
  fi
  case "$text" in
  *"updated from"*) printf -v "$__var" '%s' "updated" ;;
  *"already at the latest version"*) printf -v "$__var" '%s' "noop" ;;
  *) printf -v "$__var" '%s' "other" ;;
  esac
}

# The line the report should show for a CLI call, classified from the
# UNTRUNCATED output. The digest keeps 400 characters, and the first line that
# is not the journal's `$ <command>` echo is often a progress line, so the
# failure reason has to be picked before truncation. The last line is the wrong
# fallback: it can be a userConfig note or a truncated tail. The first line
# that starts with ✘ or contains Failed or Error wins; then the first line of a
# result line's `message`; otherwise the first non-`$` line.
cli_outcome_line() {
  local text="$1"
  local line json message
  local fallback=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    [[ "$line" == '$ '* ]] && continue
    [[ -z "$line" ]] && continue
    if [[ -z "$fallback" ]]; then
      fallback="$line"
    fi
    if [[ "$line" == ✘* || "$line" == *Failed* || "$line" == *Error* ]]; then
      [[ "$line" == '{'* ]] && continue
      printf '%s' "$line"
      return 0
    fi
  done <<<"$text"
  cli_json json "$text"
  if [[ -n "$json" ]]; then
    jq_to message -r '.message // "" | split("\n")[0]' <<<"$json"
    [[ -z "$message" ]] || {
      printf '%s' "$message"
      return 0
    }
  fi
  printf '%s' "$fallback"
}

# Whether the install says the plugin was left disabled, read from `message` (no
# field carries it; cli_json's claim). Classified from the untruncated output:
# install_one keeps 400 characters, and the notice can sit past that. The
# catalog's defaultEnabled field is not the signal, because the CLI's sentence and
# that field can disagree. The CLI writes an explicit enabledPlugins false for
# this case.
install_disabled_notice() {
  local text
  cli_message text "$1"
  case "$text" in
  *"disabled by default"* | *"Disabled by default"*) return 0 ;;
  *) return 1 ;;
  esac
}

# --- projection ----------------------------------------------------------------
# Redirect the selector to a file and hand back the exit status. An empty
# projection is ambiguous: every `--from` rejection exits 2 with EMPTY stdout so a
# failure can never reach the CLI as an id, which makes the status the only thing
# that tells "nothing to do" from "the projection failed".
project_ids() {
  local selector="$1"
  local from="$2"
  local out="$3"
  "$FLEET_STATE" --ids "$selector" --from "$from" >"$out" 2>"$RUN_DIR/.proj-err"
}

# The digest is read by a model in one turn, so no single field may run away with
# the window. Output is kept, bounded.
trunc() {
  local __var="$1"
  local text="$2"
  local max="${3:-400}"
  if ((${#text} > max)); then
    printf -v "$__var" '%s' "${text:0:max}…"
  else
    printf -v "$__var" '%s' "$text"
  fi
}

# The selector's stderr, bounded HERE rather than at each call site: every caller
# embeds it in a digest string, so the truncation belongs to the reader and not to
# any one message.
proj_err() {
  local text=""
  local bounded=""
  [[ -f "$RUN_DIR/.proj-err" ]] && text=$(<"$RUN_DIR/.proj-err")
  trunc bounded "${text//$'\r'/}"
  printf '%s' "$bounded"
}

# --- run directory -------------------------------------------------------------
# `mktemp -d`, never a bare `mkdir -p` on the timestamp: the stamp has one-second
# resolution, so two runs started in the same second compute the same path,
# `mkdir -p` succeeds for both, and their snapshots overwrite each other.
setup_run_dir() {
  if ((ONLY_INSTALL_MODE == 1)); then
    JOURNAL_LOG="$RUN_DIR/journal.log"
    return 0
  fi
  if [[ "$MODE" == "audit" ]]; then
    # `${TMPDIR:-${TEMP:-.}}` and never a hardcoded POSIX temp literal: on Windows
    # that literal is resolved by a native consumer against the current drive root.
    RUN_DIR=$(mktemp -d "${TMPDIR:-${TEMP:-.}}/plugins-audit.XXXXXX") || {
      echo "ERROR: could not create the audit scratch directory" >&2
      exit 2
    }
    AUDIT_SCRATCH="$RUN_DIR"
    trap 'rm -rf "$AUDIT_SCRATCH"' EXIT
  else
    mkdir -p "$JOURNAL_ROOT" 2>/dev/null
    RUN_DIR=$(mktemp -d "$JOURNAL_ROOT/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX") || {
      echo "ERROR: could not create a run directory under: $JOURNAL_ROOT" >&2
      exit 2
    }
  fi
  JOURNAL_LOG="$RUN_DIR/journal.log"
  : >"$JOURNAL_LOG"
}

# --- own plugin name -----------------------------------------------------------
# The run can move the plugin providing this skill (Step 3 sweeps every user-scope
# candidate), and so can a concurrent update; either lands in a moved row the
# self-update check matches by this name. Read the name from the manifest rather
# than hardcoding it, for the same reason no marketplace name is hardcoded.
own_plugin_name() {
  local manifest="$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
  local name=""
  [[ -f "$manifest" ]] && jq_to name -r '.name // ""' "$manifest" 2>/dev/null
  printf '%s' "$name"
}

# --- catalog regression --------------------------------------------------------
# Diff `catalog_versions` across consecutive saved snapshots and report the FIRST
# interval in which any id moved backward. That interval is what names the cause:
# in `sync` a regression across pre-refresh->pre is this run's refresh pulling a
# source that moved backward, while one appearing later is the checkout changing
# under the run. REPORT-ONLY — its output never becomes an id list handed to a CLI.
catalog_regression_rows() {
  local __interval_var="$1"
  local __rows_var="$2"
  local mp="$3"
  local snaps=(pre-refresh pre mid post)
  local i
  local a
  local b
  local rows=""
  printf -v "$__interval_var" '%s' ""
  printf -v "$__rows_var" '%s' "[]"
  for ((i = 0; i + 1 < ${#snaps[@]}; i++)); do
    a="$RUN_DIR/${snaps[i]}.$mp.json"
    b="$RUN_DIR/${snaps[i + 1]}.$mp.json"
    [[ -f "$a" && -f "$b" ]] || continue
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to rows -c --slurpfile a "$a" --slurpfile b "$b" -n '
      def triple:
        if type == "string" then
          ((capture("^v?(?<x>[0-9]+)[.](?<y>[0-9]+)[.](?<z>[0-9]+)") // null)
           | if . == null then null else [.x, .y, .z] | map(tonumber) end)
        else null end;
      ($a[0].catalog_versions // {}) as $before | ($b[0].catalog_versions // {}) as $after
      | [$before | to_entries[]
         | select((.value | triple) != null and ($after[.key] | triple) != null
                  and ($after[.key] | triple) < (.value | triple))
         | "\(.key) \(.value) \($after[.key])"]' || continue
    if [[ -n "$rows" && "$rows" != "[]" ]]; then
      printf -v "$__interval_var" '%s' "${snaps[i]}->${snaps[i + 1]}"
      printf -v "$__rows_var" '%s' "$rows"
      return 0
    fi
  done
  return 0
}

# --- divergence attribution ----------------------------------------------------
# Three snapshots, not two: Steps 2 and 3 both mutate versions, so a single
# pre/post bracket cannot tell which step created a new actionable divergence, and
# labeling the whole delta "the user-scope sweep" is wrong whenever Step 2 caused
# it. Only `versionsMatch: false` rows are actionable; a same-version multi-scope
# install is benign and is never counted.
#
# A scope whose projectPath is a user home (`projectPathIsHome`) is not a project
# at all, and converge blocks it, so it is dropped before the versions are
# compared: a divergence that exists only because of such a record is not
# actionable. A report with no such field keeps every scope.
# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
ACTIONABLE_DEF='def actionable: select(.versionsMatch == false)
    | select(([.scopes[]? | select(.projectPathIsHome != true) | .version] | unique | length) > 1);'
#
# The post count is then split by what an operator can do about each row, so the
# report points converge only at rows converge can act on. A divergence row is
# classed by its project/local pins: any pin that is present and not a linked
# worktree makes the row `actionable`; otherwise any pin in a linked worktree makes
# it `worktree`; otherwise every pin is in a path that is not present and the row is
# `blocked`. A row with no pin is `actionable`. The actionable rows split again into
# `actionable_here` (the id has a record for the repo the run stands in) and
# `actionable_elsewhere`. `divergences[]` itself is never filtered.
#
# A linked worktree is a present path whose `.git` is a FILE whose `gitdir:` line
# names a `<repo>.git/worktrees/<name>` entry of another repository. A repository's
# own `.git` is a directory, a submodule's `.git` file names `/modules/`, and a
# `--separate-git-dir` checkout names a git directory that is not under `worktrees/`
# of a `.git`, so none of them matches.
#
# A row's pins are judged only when they differ from the row's highest version
# (`row_class`), so a pin already at the highest version does not make a row
# actionable while its stale pin sits in a path that is not present.
linked_worktree_paths() {
  local __var="$1"
  local post="$2"
  local paths=""
  local p
  local fs
  local line
  local found=()
  jq_to paths -r "$ACTIONABLE_DEF"'[.divergences[]? | actionable | .scopes[]?
    | select(.projectPathIsHome != true and .projectPathPresent == true) | .projectPath]
    | unique | .[]' "$post" || paths=""
  while IFS= read -r p; do
    p="${p//$'\r'/}"
    [[ -n "$p" ]] || continue
    fs="${p//\\//}"
    [[ -f "$fs/.git" ]] || continue
    line=""
    IFS= read -r line <"$fs/.git" || true
    line="${line//$'\r'/}"
    case "$line" in
    "gitdir:"*".git/worktrees/"*) found+=("$p") ;;
    *) ;;
    esac
  done <<<"$paths"
  json_strings_of "$__var" ${found[@]+"${found[@]}"}
}

would_pins() {
  local __var="$1"
  local ir_w
  json_array_of ir_w ${IR_WOULD[@]+"${IR_WOULD[@]}"}
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to "$__var" -c -n --argjson ir "$ir_w" --argjson op "$OTHER_PATHS_JSON" \
    '[($ir[] | {id, scope, current: true}), ($op.would_update[]? | {id, scope, path})]' || printf -v "$__var" '%s' "[]"
  [[ -n "${!__var}" ]] || printf -v "$__var" '%s' "[]"
}

divergence_block() {
  local __var="$1"
  local mp="$2"
  local pre="$RUN_DIR/pre.$mp.json"
  local mid="$RUN_DIR/mid.$mp.json"
  local post="$RUN_DIR/post.$mp.json"
  local linked="[]"
  if [[ ! -f "$pre" || ! -f "$mid" || ! -f "$post" ]]; then
    jq_to "$__var" -c -n '{pre: null, mid: null, post: null, new_total: null,
      new_by_interval: {in_repo: null, user_sweep: null, concurrent: null}, pre_existing: null,
      note: "a snapshot was missing, so the split could not be computed"}'
    return 0
  fi
  linked_worktree_paths linked "$post"
  [[ -n "$linked" ]] || linked="[]"
  # The ids that moved during the run under a call this run did not make an update
  # (finalize_moves' MOVED_DURING): a new divergence on one of them is not the
  # step's doing, so it is split out of the interval it first appeared in.
  local moved_rows
  local would
  would_pins would
  json_array_of moved_rows ${MOVED_DURING[@]+"${MOVED_DURING[@]}"}
  json_object_file "$RUN_DIR/.divergence-args.$mp.json" moved "$moved_rows" wt "$linked" would "$would"
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to "$__var" -c \
    --slurpfile p "$pre" --slurpfile m "$mid" --slurpfile q "$post" \
    --argjson cap "$DIVERGENCE_PATH_IDS" "$ACTIONABLE_DEF$TRIPLE_DEF"'
    . as {$moved, $wt, $would}
    # Under --audit nothing moved, so a pin sync would forward-update (Step 2 or
    # Step 3a) is read at the catalog version: it is not work for converge. A
    # linked worktree keeps its own version, since update leaves it behind there.
    | ($q[0] | if ($would | length) == 0 then . else
        .catalog_versions as $cv
        | ([.installed[]? | select(.currentProject == true) | {id, scope, path: .projectPath}]) as $cur
        | ([$would[] | . as $w
            | if .current == true then ($cur[] | select(.id == $w.id and .scope == $w.scope))
              else {id, scope, path} end]) as $wp
        | .divergences |= map(.id as $id | .scopes |= map(
            . as $s
            | if $s.linkedWorktree != true and $s.projectPathIsHome != true
                 and ($s.projectPath as $pp | $wt | index($pp)) == null
                 and any($wp[]; .id == $id and .scope == $s.scope and .path == $s.projectPath)
                 and ($cv[$id] | triple) != null and ($s.version | triple) != null
                 and ($s.version | triple) < ($cv[$id] | triple)
              then .version = $cv[$id] else . end))
      end) as $qq
    # A pin at the project the run stands in is converge-actionable even when that
    # project is itself a linked worktree, so it is never classed `worktree`.
    | ([$qq.installed[]? | select(.currentProject == true) | .projectPath]) as $curp
    | def act: [.divergences[]? | actionable | .id];
    def pin_class:
      if .projectPathPresent == false then "blocked"
      elif .projectPathPresent == true and (.projectPath as $pp | $curp | index($pp)) == null
           and (.projectPath as $pp | $wt | index($pp)) != null then "worktree"
      else "actionable" end;
    def version_triple:
      if type == "string" then
        ((capture("^v?(?<a>[0-9]+)[.](?<b>[0-9]+)[.](?<c>[0-9]+)") // null)
         | if . == null then null else [.a, .b, .c] | map(tonumber) end)
      else null end;
    # Only a pin that differs from the row'"'"'s highest version is the skew converge or
    # a worktree removal would settle; a pin already at it is not what makes the
    # row actionable. An unparsable version stays in, the conservative direction.
    # A pin keyed to a user home (`projectPathIsHome`) is dropped like in `actionable`:
    # it never sets the highest version and never classes the row.
    def row_class:
      [.scopes[]? | select(.projectPathIsHome != true)] as $s
      | ([$s[] | .version | version_triple | select(. != null)] | max) as $top
      | [$s[] | select((.projectPath // "") != "")
         | select($top == null or (.version | version_triple) != $top)
         | pin_class] as $c
      | if ($c | length) == 0 or ($c | index("actionable")) != null then "actionable"
        elif ($c | index("worktree")) != null then "worktree"
        else "blocked" end;
    # The records that make a row skewed: the same pins row_class judges, plus a
    # user-scope record behind a project pin, so every diverging id is named. A row
    # whose versions differ only past the triple (`1.2.3` against `1.2.3-beta`) has
    # no such pin, so all of its scopes are kept rather than none. Each record also
    # carries its pin_class, which by_path keeps and records[] drops.
    def diverging_records:
      .id as $id
      | [.scopes[]? | select(.projectPathIsHome != true)] as $s
      | ([$s[] | .version | version_triple | select(. != null)] | max) as $top
      | [$s[] | select($top == null or (.version | version_triple) != $top)] as $d
      | (if ($d | length) > 0 then $d else $s end)
      | map({id: $id, scope, version, projectPath: (.projectPath // null),
             class: (if (.projectPath // "") != "" then pin_class else null end)});
    ($moved | map(.id)) as $conc
    | ($p[0] | act) as $pre | ($m[0] | act) as $mid | ($qq | act) as $post
    | ($post - $pre) as $new
    | [$new[] | select(. as $i | $conc | index($i))] as $by_conc
    | ($new - $by_conc) as $by_step
    | ([$qq.installed[]? | select(.currentProject == true) | .id]) as $here
    | ([$qq.divergences[]? | actionable | {id, c: row_class}]) as $rows
    | ([$rows[] | select(.c == "actionable")]) as $act_rows
    | ([$qq.divergences[]? | actionable | diverging_records[]]) as $records
    | {pre: ($pre | length), mid: ($mid | length), post: ($post | length),
       new_total: ($new | length),
       new_by_interval: {in_repo: ([$by_step[] | select(. as $i | $mid | index($i))] | length),
                         user_sweep: ([$by_step[] | select(. as $i | $mid | index($i) | not)] | length),
                         concurrent: ($by_conc | length)},
       pre_existing: (($post | length) - ($new | length)),
       actionable_here: ([$act_rows[] | select(.id as $i | $here | index($i))] | length),
       actionable_elsewhere: ([$act_rows[] | select(.id as $i | $here | index($i) | not)] | length),
       in_worktrees: ([$rows[] | select(.c == "worktree")] | length),
       blocked: ([$rows[] | select(.c == "blocked")] | length),
       records: [$records[] | del(.class)],
       # A path converge can act on sorts before a linked worktree, and a worktree
       # before a path that is not present, so the first sub-line under the
       # converge pointer is a place converge can run from.
       by_path: ([$records[] | select((.projectPath // "") != "")]
                 | group_by(.projectPath)
                 | map((map(.id) | unique) as $ids
                       | {path: .[0].projectPath, class: .[0].class, count: length, ids: $ids[:$cap],
                          more: ([($ids | length) - $cap, 0] | max)})
                 | sort_by(({actionable: 0, worktree: 1, blocked: 2}[.class // ""] // 0), -.count, .path))}' \
    "$RUN_DIR/.divergence-args.$mp.json"
}

# --- Step 3a — forward-update the records of every other present path --------------
# Step 2 updates the records of the repo the run stands in; this step takes the
# project/local records of every OTHER path that is present, a user home and a
# linked worktree included, and runs `claude plugin update <id> -s <scope>` from
# that path, since the two scopes have no path flag. Forward only: a record is
# called only when its version and the catalog's both parse and the record is
# below, so a deliberate pin above the catalog, a catalog that moved backward,
# and an id with no readable catalog version are never touched.
#
# `update` writes no settings file (context/scope-semantics.md), and this step
# checks that rather than trusting it: before the first call in a path and after
# each one it takes `git status --porcelain -- .claude/` where the path is in a
# git work tree, and a checksum of `.claude/settings.json` and
# `.claude/settings.local.json` in every path (git status cannot see a change to
# an ignored settings.local.json). A change stops that path: the call is a
# failure, and every record in that path after it is reported as not tried.
#
# Selected from the mid snapshot, so Step 2's own moves are already in it, and
# read back from the post snapshot by finalize_other_paths.
# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
TRIPLE_DEF='def triple:
    if type == "string" then
      ((capture("^v?(?<x>[0-9]+)[.](?<y>[0-9]+)[.](?<z>[0-9]+)") // null)
       | if . == null then null else [.x, .y, .z] | map(tonumber) end)
    else null end;'

settings_state() {
  local __var="$1"
  local dir="$2"
  local st=""
  local f
  local sum
  if git --no-optional-locks -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    st=$(git --no-optional-locks -C "$dir" status --porcelain -- .claude/ 2>&1)
  fi
  for f in settings.json settings.local.json; do
    sum="absent"
    [[ -f "$dir/.claude/$f" ]] && sum=$(cksum <"$dir/.claude/$f")
    st+=$'\n'"$f $sum"
  done
  printf -v "$__var" '%s' "$st"
}

path_row() {
  # path_row <result> <reason> <stopped>: one row for the current record.
  jq -c -n --arg id "$id" --arg sc "$scope" --arg path "$path" --arg old "$old" --arg cat "$cat" \
    --arg label "$label" --arg home "$home" --arg result "$1" --arg reason "$2" --argjson stopped "$3" \
    '{id: $id, scope: $sc, path: $path, old: $old, catalog: $cat, label: $label,
      home: ($home == "true"), result: $result, reason: $reason, stopped: $stopped}'
}

other_paths_step() {
  local mp="$1"
  local cands=""
  local path id scope old cat label home fs reason
  local before=""
  local after=""
  local cur=""
  local stopped=""
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  if ! jq_to cands -r "$TRIPLE_DEF"'
    .catalog_versions as $cv
    | [.installed[]? | select((.scope == "project" or .scope == "local") and .currentProject != true
         and .projectPathPresent == true and (.projectPath // "") != "")
       | select(($cv[.id] | triple) as $c | (.version | triple) as $v | $c != null and $v != null and $v < $c)
       | {projectPath, id, scope, version, cat: $cv[.id], label: (.label // ""),
          home: (.projectPathIsHome == true | tostring)}]
    | sort_by(.projectPath, .id, .scope)[]
    | [.projectPath, .id, .scope, .version, .cat, .label, .home] | join("\u001f")' "$RUN_DIR/mid.$mp.json"; then
    mp_error "other-paths selection failed, step not run"
    return 0
  fi
  while IFS=$'\x1f' read -r path id scope old cat label home; do
    path="${path//$'\r'/}" id="${id//$'\r'/}" scope="${scope//$'\r'/}" old="${old//$'\r'/}"
    cat="${cat//$'\r'/}" label="${label//$'\r'/}" home="${home//$'\r'/}"
    [[ -n "$id" ]] || continue
    if [[ "$MODE" == "audit" ]]; then
      predict_cli "(cd \"$path\" && claude plugin update $id -s $scope)"
      PATH_ROWS+=("$(path_row would "" false)")
      continue
    fi
    fs="${path//\\//}"
    if [[ "$path" != "$cur" ]]; then
      cur="$path"
      settings_state before "$fs"
    fi
    if [[ "$path" == "$stopped" ]]; then
      PATH_ROWS+=("$(path_row failed "not tried: the .claude/ settings in this path changed after an earlier call" true)")
      continue
    fi
    CLI_CWD="$fs"
    run_cli "(cd \"$path\" && claude plugin update $id -s $scope --json)" plugin update "$id" -s "$scope" --json
    CLI_CWD=""
    settings_state after "$fs"
    if [[ "$after" != "$before" ]]; then
      stopped="$path"
      PATH_ROWS+=("$(path_row failed "the .claude/ settings in this path changed after this call, so the path was stopped" true)")
      continue
    fi
    if ((CLI_RC != 0)); then
      reason=$(cli_outcome_line "$CLI_OUT")
      PATH_ROWS+=("$(path_row failed "exit $CLI_RC: $reason" false)")
      continue
    fi
    PATH_ROWS+=("$(path_row called "" false)")
  done <<<"$cands"
}

# Each called record read back from the post snapshot by (id, scope, path). A
# record that moved forward is updated. One left behind in a linked worktree or a
# user home is `not_moved`: the worktree keeps its divergence class and the home
# its own report row. Any other record left behind is a failure. A re-entry
# reuses the first pass's result, which no later step changes.
finalize_other_paths() {
  local mp="$1"
  local file="$RUN_DIR/other-paths.$mp.json"
  local rows_file="$RUN_DIR/.other-paths-rows.$mp.json"
  local post="$RUN_DIR/post.$mp.json"
  local rows
  local result=""
  if ((ONLY_INSTALL_MODE == 1)); then
    [[ -f "$file" ]] && OTHER_PATHS_JSON=$(<"$file")
    return 0
  fi
  json_array_of rows ${PATH_ROWS[@]+"${PATH_ROWS[@]}"}
  printf '%s\n' "$rows" >"$rows_file"
  [[ -f "$post" ]] || post="$rows_file"
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to result -c -n --slurpfile rows "$rows_file" --slurpfile post "$post" "$TRIPLE_DEF"'
    ($post[0] | if type == "object" then . else {} end) as $q
    | [$rows[0][] | select(.result == "called")
       | . as $r
       | . + {new: (first($q.installed[]? | select(.id == $r.id and .scope == $r.scope
                     and .projectPath == $r.path) | .version) // null)}
       | . + {moved: ((.new | triple) != null and (.old | triple) < (.new | triple))}] as $called
    | {updated: [$called[] | select(.moved) | {id, scope, path, old, new}],
       not_moved: [$called[] | select((.moved | not) and (.label != "" or .home))
                   | {id, scope, path, version: (.new // .old), catalog,
                      label: (if .label != "" then .label else "user home" end)}],
       failed: ([$rows[0][] | select(.result == "failed") | {id, scope, path, reason, stopped}]
                + [$called[] | select((.moved | not) and .label == "" and (.home | not))
                   | {id, scope, path, stopped: false,
                      reason: ("the record did not move: still at \(.new // "an unread version"), the catalog reads \(.catalog)")}]),
       would_update: [$rows[0][] | select(.result == "would") | {id, scope, path, old, catalog}]}' || result=""
  if [[ -n "$result" ]]; then
    OTHER_PATHS_JSON="$result"
  else
    mp_error "other-paths read-back failed"
  fi
  printf '%s\n' "$OTHER_PATHS_JSON" >"$file"
}

# --- per-marketplace accumulators ----------------------------------------------
# Script-scope rather than `local`, because the step helpers below append to them
# and a `local` array is invisible to a function the step calls. The initial
# values ARE the per-marketplace reset, so both come from this one function.
reset_marketplace_state() {
  MP_ERRORS=()
  IR_UPDATED=() IR_FAILED=() IR_WOULD=() IR_LIVE=()
  US_UPDATED=() US_FAILED=() US_WOULD=()
  MOVED_DURING=() NOOP_UNVERIFIED=0
  PATH_ROWS=() OTHER_PATHS_JSON='{"updated":[],"failed":[],"not_moved":[],"would_update":[]}'
  WITHHELD=() DOWNGRADED=() INSTALLED_ROWS=() ENABLED_ROWS=() PROJECT_ROWS=() RECOVERED_ROWS=()
  INSTALL_GAP="[]" ENABLE_GAP="[]" NORMALIZE_JSON="null" CACHE_JSON="null"
  SELF_UPDATED="false" SELF_UPDATE="null" INSTALL_DEFERRED="false" STOPPED_BEFORE_INSTALL="false"
  REFRESH_RC="null" REFRESH_OUT="" REFRESH_REASON="" REFRESH_PREDICTED="false" REFRESH_FAILED=0
  CATALOG_LAST_UPDATED="" PROJECT_ROOT_JSON="null" SOURCE_PULL_JSON="null"
  # Step stamps (start, end) for this marketplace; an empty pair is a step this
  # invocation did not run and reads `null` in the digest, never 0.
  T_PRR_S="" T_PRR_E="" T_MU_S="" T_MU_E="" T_IR_S="" T_IR_E="" T_US_S="" T_US_E=""
  T_PI_S="" T_PI_E="" T_IE_S="" T_IE_E="" T_CC_S="" T_CC_E="" T_PR_S="" T_PR_E=""
  T_FN_S="" T_MP_S="" T_MP_E=""
  CACHE_CHECK_RAN=0
}
reset_marketplace_state

# First-pass result rows that live only in these arrays. Successful moves ride
# `moves.<mp>.tsv` and withheld downgrades ride `downgrades.<mp>.txt`, so an
# `--only-install` re-entry can rebuild those; a failed update or a projection
# error has no other store. Without this sidecar the replacement digest drops
# them and a run that left a plugin stale can report as a successful sync.
persist_first_pass_rows() {
  local mp="$1"
  local ir_f
  local us_f
  local errs
  local persisted
  json_array_of ir_f ${IR_FAILED[@]+"${IR_FAILED[@]}"}
  json_array_of us_f ${US_FAILED[@]+"${US_FAILED[@]}"}
  json_strings_of errs ${MP_ERRORS[@]+"${MP_ERRORS[@]}"}
  json_object_file "$RUN_DIR/.first-pass-args.$mp.json" \
    errors "$errs" ir_failed "$ir_f" us_failed "$us_f" source_pull "$SOURCE_PULL_JSON"
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to persisted -c \
    --arg refresh_rc "$REFRESH_RC" \
    --arg refresh_out "$REFRESH_OUT" \
    --arg refresh_reason "$REFRESH_REASON" \
    --arg refresh_predicted "$REFRESH_PREDICTED" \
    '{errors, ir_failed, us_failed, source_pull,
      refresh: {rc: (if $refresh_rc == "null" or $refresh_rc == "" then null
                     else ($refresh_rc | tonumber? // $refresh_rc) end),
                output: $refresh_out,
                reason: $refresh_reason,
                predicted: ($refresh_predicted == "true")}}' "$RUN_DIR/.first-pass-args.$mp.json"
  printf '%s\n' "$persisted" >"$RUN_DIR/first-pass.$mp.json"
}

# The three array restores stay spelled out: appending to a caller-named array
# needs a `local -n` nameref (bash 4.3), and this script runs in Claude Code's
# Bash-tool shell on every platform, which on macOS is the stock bash 3.2.
restore_first_pass_rows() {
  local mp="$1"
  local sidecar="$RUN_DIR/first-pass.$mp.json"
  local lines
  local line
  [[ -f "$sidecar" ]] || return 0
  jq_to lines -r '.errors[]?' "$sidecar"
  while IFS= read -r line; do
    [[ -n "$line" ]] && MP_ERRORS+=("$line")
  done <<<"$lines"
  jq_to lines -c '.ir_failed[]?' "$sidecar"
  while IFS= read -r line; do
    [[ -n "$line" ]] && IR_FAILED+=("$line")
  done <<<"$lines"
  jq_to lines -c '.us_failed[]?' "$sidecar"
  while IFS= read -r line; do
    [[ -n "$line" ]] && US_FAILED+=("$line")
  done <<<"$lines"
  # Digest fields only. `REFRESH_FAILED` stays 0 so the re-entry can still run
  # Steps 4 and 5: that flag is the first-pass defer gate, and restoring it
  # would skip the install the caller just confirmed.
  jq_to REFRESH_OUT -r '.refresh.output // ""' "$sidecar"
  jq_to REFRESH_REASON -r '.refresh.reason // ""' "$sidecar"
  jq_to REFRESH_PREDICTED -r 'if .refresh.predicted == true then "true" else "false" end' "$sidecar"
  jq_to REFRESH_RC -r 'if .refresh.rc == null then "null" else (.refresh.rc | tostring) end' "$sidecar"
  jq_to SOURCE_PULL_JSON -c '.source_pull // null' "$sidecar"
  [[ -n "$SOURCE_PULL_JSON" ]] || SOURCE_PULL_JSON="null"
}

# 0 when $1 is one of the comma- or space-separated names in $2.
name_listed() {
  local name
  for name in ${2//,/ }; do
    [[ "$name" == "$1" ]] && return 0
  done
  return 1
}

# Why a `source_checkout` object may not be fast-forwarded, or "" when it may: a
# clean checkout on a branch with an upstream, not ahead of it and behind it.
# Anything else could lose or tangle the user's work, so the guard says no.
# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
FF_REFUSAL_DEF='def ff_refusal:
  if . == null then "not a directory source"
  elif .state == "not_a_repo" then "not a git work tree"
  elif .state == "detached" then "detached HEAD"
  elif .state == "no_upstream" then "no upstream branch"
  elif .dirty == true then "tracked files modified"
  elif (.ahead // 0) > 0 and (.behind // 0) > 0 then
    "diverged from \(.upstream): \(.ahead) ahead, \(.behind) behind"
  elif (.ahead // 0) > 0 then "\(.ahead) local commit(s) ahead of \(.upstream)"
  elif (.behind // 0) == 0 then "not behind \(.upstream)"
  else "" end;'

# --- the guarded fast-forward of a directory source's checkout ---------------------
# Runs before Step 1's refresh, only for a marketplace the caller named with
# --pull-source after the user said yes. The guard lives here as well as in the
# model's offer: the checkout is read again at this point and refused, with the
# reason, unless the policy is ask and ff_refusal finds nothing, so a stale offer
# or a mistyped name touches nothing. The pull is journaled like a CLI call, with
# stdin closed and git's prompts off, and SOURCE_PULL_JSON records the outcome.
source_fast_forward() {
  local mp="$1"
  local snapshot="$2"
  local src=""
  local checkout="null"
  local refusal=""
  local path=""
  local from=""
  local to=""
  local rc=0
  local out=""
  local reason=""
  local sink="$RUN_DIR/.last-git-out"
  if [[ -n "$SOURCE_PULL_OFF" ]]; then
    refusal="$SOURCE_PULL_OFF"
  else
    jq_to src -r '.marketplace.source // ""' "$snapshot"
    source_checkout checkout "$src"
    # An unreadable checkout fails closed: an empty path would point git at the
    # current directory.
    if ! jq_to path -r 'if type == "object" then .path // "" else "" end' <<<"${checkout:-null}" ||
      { [[ -z "$path" ]] && [[ "$src" == directory:* ]]; }; then
      refusal="source checkout unreadable"
    else
      jq_to refusal -r "$FF_REFUSAL_DEF"' ff_refusal' <<<"${checkout:-null}" || refusal="source checkout unreadable"
    fi
  fi
  if [[ -n "$refusal" ]]; then
    echo "fast-forward refused for $mp: $refusal" >>"$JOURNAL_LOG"
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to SOURCE_PULL_JSON -c -n --arg r "$refusal" '{status: "refused", reason: $r}'
    return 0
  fi
  from=$(git -C "$path" rev-parse HEAD 2>/dev/null)
  # No terminal prompt and no credential-manager dialog: a pull that needs one
  # fails and is reported rather than waiting on a person who may not be there.
  {
    echo "\$ git -C $path pull --ff-only"
    GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never git -C "$path" pull --ff-only 2>&1 </dev/null
  } | tee -a "$JOURNAL_LOG" >"$sink"
  rc=${PIPESTATUS[0]}
  out=$(<"$sink")
  to=$(git -C "$path" rev-parse HEAD 2>/dev/null)
  if ((rc == 0)); then
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to SOURCE_PULL_JSON -c -n --arg f "$from" --arg t "$to" \
      '{status: "pulled", reason: "", from: $f, to: $t}'
  else
    reason=$(cli_outcome_line "${out//$'\r'/}")
    trunc reason "$reason"
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to SOURCE_PULL_JSON -c -n --argjson rc "$rc" --arg r "$reason" --arg f "$from" --arg t "$to" \
      '{status: "failed", rc: $rc, reason: $r, from: $f, to: $t}'
  fi
}

# --- one snapshot read ----------------------------------------------------------
# `fleet-state.sh --marketplace <mp>` into $2, with its stderr captured and, on a
# non-zero exit, recorded as a per-marketplace error named for the step ($3).
# Returns the reader's own status, so a caller that must abandon the marketplace
# still branches on it.
fleet_read() {
  local mp="$1"
  local out="$2"
  local label="$3"
  local rc=0
  local text
  "$FLEET_STATE" --marketplace "$mp" >"$out" 2>"$RUN_DIR/.fs-err"
  rc=$?
  if ((rc != 0)); then
    text=$(<"$RUN_DIR/.fs-err")
    mp_error "$label fleet-state read failed (exit $rc): ${text//$'\r'/}"
  fi
  return "$rc"
}

# --- the per-marketplace loop body (Steps 2-5b, plus Step 1's own refresh) -------
run_marketplace() {
  local mp="$1"
  reset_marketplace_state
  clock_into T_MP_S
  # The `--only-install` re-entry APPENDS to the same move ledger. Truncating it
  # would drop the sweep's `<old> → <new>` pairs from the digest that supersedes
  # the first one, and the report would then show an empty `Updated:` for a run
  # that updated plugins.
  ((ONLY_INSTALL_MODE == 1)) || : >"$RUN_DIR/moves.$mp.tsv"

  local rc
  local dg_rc
  local id
  local scope
  local old
  local new
  local result
  local row
  local out
  local reason

  local pre_refresh="$RUN_DIR/pre-refresh.$mp.json"

  # ---- Step 1 — marketplace refresh -------------------------------------------
  # The snapshot is a READ and both actions take it: it is the earliest link in the
  # catalog regression check's chain, and an action that skips it starts that check
  # at `pre` and loses the interval that isolates the refresh point.
  if ((ONLY_INSTALL_MODE == 0)); then
    if [[ ! -f "$pre_refresh" ]]; then
      clock_into T_PRR_S
      fleet_read "$mp" "$pre_refresh" pre-refresh
      rc=$?
      clock_into T_PRR_E
      if ((rc != 0)); then
        emit_marketplace_block "$mp"
        return 0
      fi
    elif [[ "$mp" == "$MAIN_READ_MP" ]]; then
      # That read ran before this function, so the block's window opens where it did.
      T_PRR_S="$MAIN_READ_S"
      T_PRR_E="$MAIN_READ_E"
      T_MP_S="$MAIN_READ_S"
    fi

    if [[ "$MODE" == "audit" ]]; then
      # Predicted, not run: the step's timing stays null.
      predict_cli "claude plugin marketplace update $mp"
      REFRESH_PREDICTED="true"
      REFRESH_RC="null"
      trunc REFRESH_OUT "$CLI_OUT"
    else
      clock_into T_MU_S
      # A requested fast-forward goes first, so the refresh below reads the
      # updated checkout and the rest of this run sees the newer catalog.
      if ((PULL_SOURCES_SET == 1)) && name_listed "$mp" "$PULL_SOURCES"; then
        source_fast_forward "$mp" "$pre_refresh"
      fi
      run_cli "claude plugin marketplace update $mp" plugin marketplace update "$mp"
      clock_into T_MU_E
      REFRESH_RC="$CLI_RC"
      trunc REFRESH_OUT "$CLI_OUT"
      REFRESH_REASON=$(cli_outcome_line "$CLI_OUT")
      if ((CLI_RC != 0)); then
        REFRESH_FAILED=1
        mp_error "marketplace refresh failed (exit $CLI_RC): ${REFRESH_REASON}, so the catalog may be stale and install/enable maintenance is deferred"
      fi
    fi
  else
    # The re-entry reports the whole run, so the fields Steps 1-3 filled come back
    # off their saved snapshots rather than reading as absent.
    if [[ -f "$RUN_DIR/pre.$mp.json" ]]; then
      jq_to CATALOG_LAST_UPDATED -r '.marketplace.lastUpdated // ""' "$RUN_DIR/pre.$mp.json"
      jq_to PROJECT_ROOT_JSON -c '.project_root' "$RUN_DIR/pre.$mp.json"
      [[ -n "$PROJECT_ROOT_JSON" ]] || PROJECT_ROOT_JSON="null"
    fi
    if ((ALLOW_DOWNGRADE == 0)) && [[ -f "$RUN_DIR/downgrades.$mp.txt" ]]; then
      while IFS=$'\t' read -r id scope old new; do
        id="${id//$'\r'/}"
        [[ -n "$id" ]] || continue
        WITHHELD+=("$(jq -c -n --arg id "$id" --arg sc "${scope//$'\r'/}" \
          --arg o "${old//$'\r'/}" --arg n "${new//$'\r'/}" \
          '{id: $id, scope: $sc, installed: $o, catalog: $n}')")
      done <"$RUN_DIR/downgrades.$mp.txt"
    fi
    restore_first_pass_rows "$mp"
  fi

  # ---- Step 2 — in-repo update (the primary value path) ------------------------
  if ((ONLY_INSTALL_MODE == 0)); then
    clock_into T_IR_S
    fleet_read "$mp" "$RUN_DIR/pre.$mp.json" pre
    rc=$?
    if ((rc != 0)); then
      emit_marketplace_block "$mp"
      return 0
    fi
    # Step 1's refresh rewrites the stamp, so it is read after that refresh, never
    # off the pre-refresh snapshot.
    jq_to CATALOG_LAST_UPDATED -r '.marketplace.lastUpdated // ""' "$RUN_DIR/pre.$mp.json"
    jq_to PROJECT_ROOT_JSON -c '.project_root' "$RUN_DIR/pre.$mp.json"
    [[ -n "$PROJECT_ROOT_JSON" ]] || PROJECT_ROOT_JSON="null"

    project_ids update-candidates-project "$RUN_DIR/pre.$mp.json" "$RUN_DIR/ids.pre.$mp.txt"
    rc=$?
    if ((rc != 0)); then
      # exit 2 with empty output is a FAILED projection, never "nothing in-repo".
      mp_error "in-repo projection failed (exit $rc), step not run: $(proj_err)"
    else
      # A marketplace whose `directory` source is this very repository is read
      # live from that folder: `claude plugin update` answers "nothing to update"
      # and leaves the project record pinned, so an update predicted for it
      # would be one the CLI never makes.
      local live_path=""
      if [[ "$MODE" == "audit" ]]; then
        # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
        jq_to live_path -r '
          def fold: gsub("\\\\"; "/") | rtrimstr("/");
          (.marketplace.source // "") as $s | (.project_root // "" | fold) as $r
          # fleet-state folds the project root to lower case after the drive letter
          # on Windows, where the recorded source keeps its case: compare folded.
          | ($r | test("^[A-Za-z]:")) as $ci
          | def eqp($a; $b): if $ci then ($a | ascii_downcase) == ($b | ascii_downcase) else $a == $b end;
          if ($s | startswith("directory:")) and $r != "" then
              ($s | sub("^directory:"; "") | fold) as $p
              | if eqp($p; $r) or eqp(($p | .[0:($r | length) + 1]); $r + "/") then $p else "" end
            else "" end' "$RUN_DIR/pre.$mp.json"
      fi
      # The same .claude/ check as Step 3a, in the project root: taken before the
      # first call and after each one, and a change stops the step there.
      local ir_root=""
      local ir_before=""
      local ir_after=""
      local ir_stopped=0
      jq_to ir_root -r '.project_root // ""' "$RUN_DIR/pre.$mp.json"
      ir_root="${ir_root//\\//}"
      if [[ "$MODE" == "sync" && -n "$ir_root" ]]; then
        settings_state ir_before "$ir_root"
      fi
      while IFS=$'\t' read -r id scope; do
        id="${id//$'\r'/}"
        scope="${scope//$'\r'/}"
        [[ -n "$id" ]] || continue
        if ((ir_stopped == 1)); then
          IR_FAILED+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg path "$ir_root" \
            '{id: $id, scope: $sc, rc: 0, output: "", path: $path, stopped: true,
              reason: "not tried: the .claude/ settings in this path changed after an earlier call"}')")
          continue
        fi
        version_at old "$RUN_DIR/pre.$mp.json" "$id" "$scope"
        if [[ "$MODE" == "audit" && -n "$live_path" ]]; then
          IR_LIVE+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg old "$old" --arg path "$live_path" \
            '{id: $id, scope: $sc, installed: $old, path: $path}')")
          continue
        fi
        if [[ "$MODE" == "audit" ]]; then
          predict_cli "claude plugin update $id -s $scope"
          IR_WOULD+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg old "$old" \
            '{id: $id, scope: $sc, installed: $old}')")
          continue
        fi
        run_cli "claude plugin update $id -s $scope --json" plugin update "$id" -s "$scope" --json
        if [[ -n "$ir_root" ]]; then
          settings_state ir_after "$ir_root"
          if [[ "$ir_after" != "$ir_before" ]]; then
            ir_stopped=1
            IR_FAILED+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg path "$ir_root" \
              '{id: $id, scope: $sc, rc: 0, output: "", path: $path, stopped: true,
                reason: "the .claude/ settings in this path changed after this call, so the path was stopped"}')")
            continue
          fi
        fi
        if ((CLI_RC != 0)); then
          reason=$(cli_outcome_line "$CLI_OUT")
          trunc out "$CLI_OUT"
          IR_FAILED+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --argjson rc "$CLI_RC" \
            --arg out "$out" --arg reason "$reason" \
            '{id: $id, scope: $sc, rc: $rc, output: $out, reason: $reason}')")
          continue
        fi
        cli_reported_version new "$CLI_OUT"
        cli_move_result result "$CLI_OUT"
        printf 'in_repo\t%s\t%s\t%s\t%s\t%s\n' "$id" "$scope" "${old:--}" "${new:--}" "$result" \
          >>"$RUN_DIR/moves.$mp.tsv"
      done <"$RUN_DIR/ids.pre.$mp.txt"
    fi
    clock_into T_IR_E
  fi

  # ---- Step 3 — user-scope update sweep ----------------------------------------
  if ((ONLY_INSTALL_MODE == 0)); then
    clock_into T_US_S
    fleet_read "$mp" "$RUN_DIR/mid.$mp.json" mid
    rc=$?
    if ((rc != 0)); then
      emit_marketplace_block "$mp"
      return 0
    fi

    other_paths_step "$mp"

    project_ids downgrade-candidates "$RUN_DIR/mid.$mp.json" "$RUN_DIR/downgrades.$mp.txt"
    dg_rc=$?
    if ((dg_rc != 0)); then
      # An unchecked failed downgrade projection reads as "no downgrades", which is
      # the guard reporting an all-clear it never established.
      mp_error "downgrade projection failed (exit $dg_rc): $(proj_err)"
      : >"$RUN_DIR/downgrades.$mp.txt"
    fi

    project_ids update-candidates-user "$RUN_DIR/mid.$mp.json" "$RUN_DIR/ids.mid.$mp.txt"
    rc=$?
    if ((rc != 0)); then
      mp_error "user-scope projection failed (exit $rc), sweep not run: $(proj_err)"
    else
      while IFS= read -r id; do
        id="${id//$'\r'/}"
        [[ -n "$id" ]] || continue
        version_at old "$RUN_DIR/mid.$mp.json" "$id" user
        if [[ "$MODE" == "audit" ]]; then
          predict_cli "claude plugin update $id -s user"
          US_WOULD+=("$(jq -c -n --arg id "$id" --arg old "$old" '{id: $id, installed: $old}')")
          continue
        fi
        run_cli "claude plugin update $id -s user --json" plugin update "$id" -s user --json
        if ((CLI_RC != 0)); then
          reason=$(cli_outcome_line "$CLI_OUT")
          trunc out "$CLI_OUT"
          US_FAILED+=("$(jq -c -n --arg id "$id" --argjson rc "$CLI_RC" --arg out "$out" \
            --arg reason "$reason" '{id: $id, rc: $rc, output: $out, reason: $reason}')")
          continue
        fi
        cli_reported_version new "$CLI_OUT"
        cli_move_result result "$CLI_OUT"
        printf 'user_sweep\t%s\t%s\t%s\t%s\t%s\n' "$id" user "${old:--}" "${new:--}" "$result" \
          >>"$RUN_DIR/moves.$mp.tsv"
      done <"$RUN_DIR/ids.mid.$mp.txt"
    fi

    # The withheld set. `--allow-downgrade` is the operator's explicit opt-in; without
    # it a proven downgrade is reported and never issued.
    while IFS=$'\t' read -r id scope old new; do
      id="${id//$'\r'/}"
      [[ -n "$id" ]] || continue
      scope="${scope//$'\r'/}"
      old="${old//$'\r'/}"
      new="${new//$'\r'/}"
      if ((ALLOW_DOWNGRADE == 1)) && [[ "$MODE" == "sync" ]]; then
        run_cli "claude plugin update $id -s $scope --json   # downgrade $old -> $new" \
          plugin update "$id" -s "$scope" --json
        if ((CLI_RC != 0)); then
          reason=$(cli_outcome_line "$CLI_OUT")
          trunc out "$CLI_OUT"
          US_FAILED+=("$(jq -c -n --arg id "$id" --argjson rc "$CLI_RC" --arg out "$out" \
            --arg reason "$reason" '{id: $id, rc: $rc, output: $out, reason: $reason}')")
          continue
        fi
        # Through the move ledger like every other mutation, so the direction
        # compare is the one that decides where it renders and the row survives an
        # `--only-install` re-entry.
        local applied=""
        local applied_result=""
        cli_move_result applied_result "$CLI_OUT"
        # Only an update line names the version this call applied; an
        # already-current line's version is the installed one.
        [[ "$applied_result" == "updated" ]] && cli_reported_version applied "$CLI_OUT"
        [[ -n "$applied" ]] || applied="$new"
        printf 'user_sweep\t%s\t%s\t%s\t%s\t%s\n' "$id" "$scope" "${old:--}" "${applied:--}" updated \
          >>"$RUN_DIR/moves.$mp.tsv"
      else
        WITHHELD+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg o "$old" --arg n "$new" \
          '{id: $id, scope: $sc, installed: $o, catalog: $n}')")
      fi
    done <"$RUN_DIR/downgrades.$mp.txt"
    clock_into T_US_E
  fi

  # ---- Steps 4 and 5 — install and enable, gated on the FRESH pre-install read ---
  # Timed as its own step: it runs on every pass, while `install_enable` stays
  # null when the gate below finds nothing to do or the `ask` policy stops.
  clock_into T_PI_S
  fleet_read "$mp" "$RUN_DIR/pre-install.$mp.json" pre-install
  rc=$?
  if ((rc == 0)); then
    project_ids missing-user-install "$RUN_DIR/pre-install.$mp.json" "$RUN_DIR/ids.pre-install.$mp.txt"
    rc=$?
    if ((rc != 0)); then
      mp_error "install-gap projection failed (exit $rc), Step 4 not run: $(proj_err)"
    else
      json_lines INSTALL_GAP "$RUN_DIR/ids.pre-install.$mp.txt"
    fi
    project_ids missing-enabled "$RUN_DIR/pre-install.$mp.json" "$RUN_DIR/ids.gap-enable.$mp.txt"
    rc=$?
    if ((rc != 0)); then
      mp_error "enable-gap projection failed (exit $rc): $(proj_err)"
    else
      json_lines ENABLE_GAP "$RUN_DIR/ids.gap-enable.$mp.txt"
    fi
  fi

  local gap_count
  local enable_gap_count
  jq_to gap_count -r 'length' <<<"$INSTALL_GAP"
  jq_to enable_gap_count -r 'length' <<<"$ENABLE_GAP"
  clock_into T_PI_E

  recover_pending "$mp"

  if ((REFRESH_FAILED == 1)); then
    # Step 4 derives installations from the catalog and Step 5 consults catalog
    # metadata, so an unrefreshed checkout can install a since-removed plugin or
    # enable one the publisher has made opt-in-only. Defer both and report.
    INSTALL_DEFERRED="true"
  elif [[ "$MODE" == "sync" && "$INSTALL_NEW" == "ask" ]] && ((gap_count > 0)) && ((ONLY_INSTALL_MODE == 0)); then
    # The `ask` policy needs a human, and only the caller can prompt. Report the gap
    # and stop before Step 4; the caller re-enters with `--only-install`.
    STOPPED_BEFORE_INSTALL="true"
  elif ((gap_count > 0)) || ((enable_gap_count > 0)) || ((ONLY_INSTALL_MODE == 1)); then
    # Both arrays are empty on an already-current fleet, and then Steps 4 and 5 are
    # no-ops with nothing to read: the same gate that keeps the spoke unloaded.
    clock_into T_IE_S
    run_install_step "$mp" "$gap_count"
    run_enable_step "$mp"
    clock_into T_IE_E
  fi

  # ---- Step 5b — cache content check, once per marketplace, after the installs ----
  # An `ask` pass that stopped before Step 4 has not installed the picks yet, so
  # a check here would miss them and the re-entry would reuse that verdict. Skip
  # it; the re-entry runs this step once the installs have landed. A pass that
  # did not stop writes the report, and a later re-entry reuses that file.
  if [[ "$STOPPED_BEFORE_INSTALL" == "true" ]]; then
    :
  else
    clock_into T_CC_S
    cache_content_block "$mp"
    if ((CACHE_CHECK_RAN == 1)); then
      clock_into T_CC_E
    else
      # The re-entry reuses the first pass's finding; the checker did not run here.
      T_CC_S=""
    fi
  fi

  # ---- post re-read, then the report inputs Step 6 reads back --------------------
  clock_into T_PR_S
  fleet_read "$mp" "$RUN_DIR/post.$mp.json" post
  clock_into T_PR_E

  clock_into T_FN_S
  finalize_moves "$mp"
  finalize_other_paths "$mp"

  local own
  own=$(own_plugin_name)
  if [[ -n "$own" ]]; then
    # Every scope and every mover: a project/local `harness-ops` record Step 2
    # moved is the same self-update, and so is one that moved during the run under
    # a CLI call that reported it already current. The running algorithm is just
    # as stale for each.
    for row in ${IR_UPDATED[@]+"${IR_UPDATED[@]}"} ${US_UPDATED[@]+"${US_UPDATED[@]}"} \
      ${DOWNGRADED[@]+"${DOWNGRADED[@]}"} ${MOVED_DURING[@]+"${MOVED_DURING[@]}"}; do
      case "$row" in
      *"\"id\":\"$own@"*)
        SELF_UPDATED="true"
        # The digest names this plugin's own row, so the render never has to
        # pick it out of the moved rows. The first match wins.
        if [[ "$SELF_UPDATE" == "null" ]]; then
          jq_to SELF_UPDATE -c '{id, scope, old, new}' <<<"$row"
        fi
        ;;
      *) ;;
      esac
    done
  fi

  emit_marketplace_block "$mp"
}

# --- pending-enable record ---------------------------------------------------------
# An `ask` pick is installed and then enabled in two CLI calls, and a run
# interrupted between them leaves a user-scope `enabledPlugins: false` that reads
# as the user's own opt-out. So the pick is journaled in the record BEFORE the
# install and cleared once the enable lands (or once nothing is left to enable);
# the next run completes what the record names. The record lives beside the run
# directories, not in one, so pruning old runs never drops it. Only an id sync
# itself journaled is ever in it, which is why a `false` the user set is never
# touched.
PENDING_FILE=""
pending_path() {
  local root
  if [[ "$MODE" == "audit" ]]; then
    return 0
  elif ((ONLY_INSTALL_MODE == 1)); then
    root="${RUN_DIR%/}"
    root="${root%/*}"
  else
    root="${JOURNAL_ROOT%/}"
  fi
  PENDING_FILE="${root%/*}/pending-enable.txt"
}

pending_add() {
  [[ -n "$PENDING_FILE" ]] || return 0
  mkdir -p "${PENDING_FILE%/*}" 2>/dev/null
  grep -qxF -- "$1" "$PENDING_FILE" 2>/dev/null || printf '%s\n' "$1" >>"$PENDING_FILE"
}

pending_remove() {
  [[ -n "$PENDING_FILE" && -f "$PENDING_FILE" ]] || return 0
  grep -vxF -- "$1" "$PENDING_FILE" >"$PENDING_FILE.next" 2>/dev/null
  mv "$PENDING_FILE.next" "$PENDING_FILE"
}

# Finishes what an interrupted run left, from the fresh pre-install read. An id the
# record names that is installed at user scope and effectively `false` is the
# interrupted pick, so it is enabled; an id that is not installed never finished
# its install, and one already enabled needs nothing. Each clears its record
# entry, except a failed enable, which stays for the next run and is reported.
recover_pending() {
  local mp="$1"
  local id
  local state
  [[ -n "$PENDING_FILE" && -f "$PENDING_FILE" && "$MODE" == "sync" ]] || return 0
  [[ -f "$RUN_DIR/pre-install.$mp.json" ]] || return 0
  while IFS= read -r id; do
    id="${id//$'\r'/}"
    [[ -n "$id" && "$id" == *"@$mp" ]] || continue
    # This run's own picks are handled by the install loop.
    case ",${ONLY_INSTALL// /,}," in *",$id,"*) continue ;; *) ;; esac
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to state -r --arg id "$id" '
      (any(.installed[]?; .id == $id and .scope == "user")) as $in
      | .enabled[$id] as $en
      | if ($in | not) then "absent" elif $en == false then "off" else "on" end' \
      "$RUN_DIR/pre-install.$mp.json" || continue
    case "$state" in
    off)
      enable_one "$id" user
      if ((CLI_RC == 0)); then
        pending_remove "$id"
        RECOVERED_ROWS+=("$(jq -c -n --arg id "$id" '{id: $id, outcome: "enabled"}')")
      else
        RECOVERED_ROWS+=("$(jq -c -n --arg id "$id" '{id: $id, outcome: "enable_failed"}')")
      fi
      ;;
    *) pending_remove "$id" ;;
    esac
  done <"$PENDING_FILE"
}

# Installs one id at user scope and appends its digest row. `CLI_RC` is the
# caller's success test, so the row shape lives in one place across both entry
# paths below.
install_one() {
  local id="$1"
  local out
  local unset_cfg="null"
  local reason=""
  local disabled="false"
  run_cli "claude plugin install $id -s user --json" plugin install "$id" -s user --json
  # Classify before truncation: the digest row keeps 400 characters, and both
  # the failure reason and the disabled-by-default notice can sit past that.
  reason=$(cli_outcome_line "$CLI_OUT")
  if install_disabled_notice "$CLI_OUT"; then
    disabled="true"
  fi
  INSTALLED_DISABLED="$disabled"
  trunc out "$CLI_OUT"
  unset_user_config_of unset_cfg "$CLI_OUT"
  INSTALLED_ROWS+=("$(jq -c -n --arg id "$id" --argjson rc "$CLI_RC" --arg out "$out" \
    --argjson unset "$unset_cfg" --argjson disabled "$disabled" --arg reason "$reason" \
    '{id: $id, rc: $rc, output: $out, unset_user_config: $unset, disabled_by_default: $disabled, reason: $reason}')")
}

# --- Step 4 — install new catalog plugins, per the caller's rendered policy -------
run_install_step() {
  local mp="$1"
  local gap_count="$2"
  local id
  local installed_any=0
  local wanted=""

  if ((ONLY_INSTALL_MODE == 1)); then
    # The narrow re-entry installs exactly the ids the caller's prompt returned,
    # scoped to this marketplace by the id's own `@<marketplace>` suffix.
    wanted=$(printf '%s' "${ONLY_INSTALL//,/ }")
    # A pick is the user's choice, so a pick the CLI installed disabled by
    # default is enabled at user scope. Only those: `enable` on a plugin that
    # is already enabled exits 1, which would report a false failure.
    for id in $wanted; do
      [[ "$id" == *"@$mp" ]] || continue
      pending_add "$id"
      install_one "$id"
      if ((CLI_RC != 0)); then
        pending_remove "$id"
        continue
      fi
      installed_any=1
      if [[ "$INSTALLED_DISABLED" == "true" ]]; then
        enable_one "$id" user
        ((CLI_RC == 0)) && pending_remove "$id"
      else
        pending_remove "$id"
      fi
    done
  elif ((gap_count > 0)) && [[ "$INSTALL_NEW" == "all" ]]; then
    while IFS= read -r id; do
      id="${id//$'\r'/}"
      [[ -n "$id" ]] || continue
      if [[ "$MODE" == "audit" ]]; then
        predict_cli "claude plugin install $id -s user"
        installed_any=1
        continue
      fi
      install_one "$id"
      ((CLI_RC == 0)) && installed_any=1
    done <"$RUN_DIR/ids.pre-install.$mp.txt"
  fi

  # The reorder heals the unsorted tail an install just created, so it runs only
  # when this step installed something. `audit` predicts it with `--check`, which
  # writes nothing.
  ((installed_any == 1)) || return 0
  local nrc=0
  local nout=""
  if [[ "$MODE" == "audit" ]]; then
    nout=$("$NORMALIZE" --check 2>&1) || nrc=$?
  else
    nout=$("$NORMALIZE" 2>&1) || nrc=$?
  fi
  trunc nout "${nout//$'\r'/}" 200

  # The project-scope map is INSPECTED and never rewritten: `project-unsorted` is a
  # report row, and `converge` remains the only action that may touch that file.
  local prc=0
  local pout=""
  local proot=""
  jq_to proot -r '. // ""' <<<"$PROJECT_ROOT_JSON"
  if [[ -n "$proot" && -f "$proot/.claude/settings.json" ]]; then
    pout=$("$NORMALIZE" --report-project "$proot/.claude/settings.json" 2>&1) || prc=$?
    trunc pout "${pout//$'\r'/}" 200
  fi

  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to NORMALIZE_JSON -c -n --argjson rc "$nrc" --arg out "$nout" --arg mode "$MODE" \
    --argjson prc "$prc" --arg pout "$pout" \
    '{rc: $rc, output: $out, checked_only: ($mode == "audit"),
      project_report: (if $pout == "" then null else {rc: $prc, output: $pout} end)}'
}

# --- Step 5 — enabledPlugins completeness ----------------------------------------
# Its own live re-read: Step 4 mutated in between (it installs, and it normalizes the
# user-scope map), so the pre-install report no longer describes the state this step
# acts on.
run_enable_step() {
  local mp="$1"
  local rc
  local id
  local row
  local has_user
  local has_local
  local has_project
  local ppath

  "$FLEET_STATE" --marketplace "$mp" >"$RUN_DIR/pre-enable.$mp.json" 2>"$RUN_DIR/.fs-err"
  rc=$?
  if ((rc != 0)); then
    mp_error "pre-enable fleet-state read failed (exit $rc), Step 5 not run"
    return 0
  fi

  project_ids missing-enabled "$RUN_DIR/pre-enable.$mp.json" "$RUN_DIR/ids.pre-enable.$mp.txt"
  rc=$?
  if ((rc != 0)); then
    mp_error "enable projection failed (exit $rc), Step 5 not run: $(proj_err)"
    return 0
  fi
  json_lines ENABLE_GAP "$RUN_DIR/ids.pre-enable.$mp.txt"

  while IFS= read -r id; do
    id="${id//$'\r'/}"
    [[ -n "$id" ]] || continue
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to row -r --arg id "$id" '
      [.installed[]? | select(.id == $id)] as $r
      | [(any($r[]; .scope == "user") | tostring),
         (any($r[]; .scope == "local" and .currentProject == true) | tostring),
         (any($r[]; .scope == "project" and .currentProject == true) | tostring),
         (first($r[] | select(.scope == "project" and .currentProject == true) | .projectPath) // "")]
      | @tsv' "$RUN_DIR/pre-enable.$mp.json"
    IFS=$'\t' read -r has_user has_local has_project ppath <<<"$row"

    local enabled_here=0
    if [[ "$has_user" == "true" ]]; then
      enable_one "$id" user
      enabled_here=1
    fi
    if [[ "$has_local" == "true" ]]; then
      enable_one "$id" local
      enabled_here=1
    fi
    # `sync` never writes a committed settings file, so a project-scope gap is
    # reported with its runnable command instead of enabled. Suppressed for an id
    # this run already enabled at user or local scope: `enable -s project` gates on
    # the merged effective value, so the reported command would fail.
    if [[ "$has_project" == "true" ]] && ((enabled_here == 0)); then
      PROJECT_ROWS+=("$(jq -c -n --arg id "$id" --arg p "$ppath" '{id: $id, project_path: $p}')")
    fi
  done <"$RUN_DIR/ids.pre-enable.$mp.txt"
}

enable_one() {
  local id="$1"
  local scope="$2"
  local out
  local reason=""
  if [[ "$MODE" == "audit" ]]; then
    predict_cli "claude plugin enable $id -s $scope"
    ENABLED_ROWS+=("$(jq -c -n --arg id "$id" --arg sc "$scope" \
      '{id: $id, scope: $sc, rc: null, predicted: true}')")
    return 0
  fi
  run_cli "claude plugin enable $id -s $scope" plugin enable "$id" -s "$scope"
  reason=$(cli_outcome_line "$CLI_OUT")
  trunc out "$CLI_OUT"
  ENABLED_ROWS+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --argjson rc "$CLI_RC" --arg out "$out" \
    --arg reason "$reason" \
    '{id: $id, scope: $sc, rc: $rc, output: $out, reason: $reason, predicted: false}')")
}

# --- Step 5b — cache content check ------------------------------------------------
# ONE call per marketplace. The stale ids come from the JSON this call already
# wrote, extracted CR-safe; the `--ids` form is reached only when the JSON could not
# be produced, never in addition to it.
cache_content_block() {
  local mp="$1"
  local report="$RUN_DIR/cache-content.$mp.json"
  local rc=0
  local ids

  if [[ ! -f "$report" ]]; then
    CACHE_CHECK_RAN=1
    "$CACHE_CHECK" --marketplace "$mp" --scope user >"$report" 2>"$RUN_DIR/.cc-err"
    rc=$?
  fi

  # `stale[]` carries the per-id row the report renders: the version the record
  # names, and one file count. All three directions are summed, because the row
  # says the cache DISAGREES with the recorded sha and a file only in the tree or
  # only in the cache disagrees exactly as much as one whose bytes changed.
  # `unreleased_changes` marks a plugin whose clone holds changelog fragments:
  # its files changed with no version bump yet, which the next release fixes.
  # `stale_ids` stays alongside it for readers that only need the ids. `scope`
  # names which records the counts cover: project and local records are not
  # compared.
  if ((rc == 0)) && jq -e 'has("checked")' "$report" >/dev/null 2>&1; then
    jq_to CACHE_JSON -c '{scope: (.scope // "user"), checked, match, stale_content, unverifiable,
      not_checked: (.not_checked // 0),
      stale_ids: [.installs[]? | select(.verdict == "stale-content") | .id],
      stale: [.installs[]? | select(.verdict == "stale-content")
              | {id, version, files_differ: ((.differing // 0) + (.missing_from_cache // 0)
                                             + (.extra_in_cache // 0)),
                 unreleased_changes: (.unreleased_changes // false)}],
      source: "json"}' "$report"
    return 0
  fi

  # The JSON is unusable, so the id list is projected with the checker's own `--ids`
  # form rather than left unknown.
  CACHE_CHECK_RAN=1
  "$CACHE_CHECK" --marketplace "$mp" --scope user --ids >"$RUN_DIR/cache-stale-ids.$mp.txt" 2>>"$RUN_DIR/.cc-err"
  rc=$?
  json_lines ids "$RUN_DIR/cache-stale-ids.$mp.txt"
  mp_error "cache-content JSON unusable, so the stale ids come from the checker's --ids form (exit $rc)"
  # Same shape either way, with the per-id detail the `--ids` form cannot know
  # spelled `null` rather than omitted: a reader that finds no `stale` key cannot
  # tell an empty finding from a missing field.
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to CACHE_JSON -c \
    '. as $ids
    | {scope: "user", checked: null, match: null, stale_content: ($ids | length), unverifiable: null,
      not_checked: null, stale_ids: $ids,
      stale: ($ids | map({id: ., version: null, files_differ: null, unreleased_changes: null})),
      source: "ids-fallback"}' <<<"$ids"
}

# --- version capture --------------------------------------------------------------
# `<old>` is the pre-mutation snapshot's version by construction; `<new>` is the
# CLI's own line when it named one (source 2), else the post-sweep read (source 3).
# When the CLI reported an update and the post version is unchanged, the pair keeps
# `unknown` rather than rendering `<old> → <old>`, which would claim nothing changed
# for a plugin that did.
finalize_moves() {
  local mp="$1"
  local kind
  local id
  local scope
  local old
  local new
  local result
  local dir
  local row
  local post="$RUN_DIR/post.$mp.json"
  [[ -f "$RUN_DIR/moves.$mp.tsv" ]] || return 0
  while IFS=$'\t' read -r kind id scope old new result; do
    [[ -n "$id" ]] || continue
    # A version field is written as `-` when it is empty, and read back the same
    # way: tab is IFS WHITESPACE, so two adjacent tabs collapse into one delimiter
    # and an empty interior field would shift every later column left by one.
    [[ "$old" == "-" ]] && old=""
    [[ "$new" == "-" ]] && new=""
    # An id the CLI called already-current is a true noop only when the snapshots
    # agree and the run's own record took. First, when the run's own project/local
    # record is still below the catalog, the CLI judged some other record (a linked
    # worktree's update is a no-op, #6713) and the update did not take: a failure,
    # never a quiet success, or the next run would count the same divergence again.
    # Otherwise the post read decides; the version the CLI's line printed (`new`,
    # for a noop row) is the cross-check. A post version that differs from `old`
    # means the install moved after the pre-mutation read and this call changed
    # nothing: a concurrent move, reported as its own row. A version that cannot be
    # read, or the two sources disagreeing, stays a noop and is counted as unverified.
    if [[ "$result" == "noop" ]]; then
      if ((ONLY_INSTALL_MODE == 0)) && [[ "$kind" == "in_repo" && "$scope" != "user" && -f "$post" ]]; then
        local ncur
        local ncat
        local nlabel
        version_at ncur "$post" "$id" "$scope"
        # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
        jq_to ncat -r --arg id "$id" '.catalog_versions[$id] // ""' "$post"
        # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
        jq_to nlabel -r --arg id "$id" --arg sc "$scope" \
          'first(.installed[]? | select(.id == $id and .scope == $sc and .currentProject == true)
            | .label) // ""' "$post"
        if [[ -n "$ncur" && -n "$ncat" && "$(version_direction "$ncur" "$ncat")" == "forward" ]]; then
          IR_FAILED+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg cur "$ncur" --arg cat "$ncat" --arg label "$nlabel" \
            '{id: $id, scope: $sc, rc: 0, output: "",
              reason: ("the CLI said already at the latest version, but this project'"'"'s record is still at \($cur) and the catalog reads \($cat): the update did not take"
                + (if $label == "" then "" else " (" + $label + ")" end))}')")
          continue
        fi
      fi
      local post_v=""
      [[ -f "$post" ]] && version_at post_v "$post" "$id" "$scope"
      if [[ -z "$old" || -z "$post_v" ]]; then
        NOOP_UNVERIFIED=$((NOOP_UNVERIFIED + 1))
        continue
      fi
      if [[ "$post_v" == "$old" ]]; then
        [[ -z "$new" || "$new" == "$old" ]] || NOOP_UNVERIFIED=$((NOOP_UNVERIFIED + 1))
        continue
      fi
      new="$post_v"
      dir=$(version_direction "$old" "$new")
      [[ "$dir" == "same" ]] && continue
      row=$(jq -c -n --arg id "$id" --arg sc "$scope" --arg k "$kind" --arg o "$old" --arg n "$new" --arg d "$dir" \
        '{id: $id, scope: $sc, kind: $k, old: $o, new: $n, direction: $d}')
      MOVED_DURING+=("$row")
      if [[ "$dir" == "backward" ]]; then
        DOWNGRADED+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg o "$old" --arg n "$new" \
          '{id: $id, scope: $sc, old: $o, new: $n, concurrent: true}')")
      fi
      continue
    fi
    if [[ -z "$new" && -f "$post" ]]; then
      version_at new "$post" "$id" "$scope"
      [[ "$new" == "$old" ]] && new=""
    fi
    # The CLI says it updated a project/local record, yet the run's own record is
    # unchanged in the post read: it updated a sibling worktree's record of the id
    # instead. Never a success row.
    # A --only-install re-entry restores the first pass's failed rows, this one
    # included, so it does not append it again.
    if ((ONLY_INSTALL_MODE == 0)) && [[ "$kind" == "in_repo" && "$scope" != "user" &&
      "$result" == "updated" && -n "$new" && -n "$old" && -f "$post" ]]; then
      local cur
      local moved=""
      version_at cur "$post" "$id" "$scope"
      if [[ "$cur" == "$old" && "$new" != "$old" ]]; then
        # Name the record that did move: another project's record of the id whose
        # version differs between the pre and post reads.
        # Against the mid read when there is one: Step 3a moves other paths'
        # records after it, and those moves are not this call's.
        local after_step2="$post"
        [[ -f "$RUN_DIR/mid.$mp.json" ]] && after_step2="$RUN_DIR/mid.$mp.json"
        if [[ -f "$RUN_DIR/pre.$mp.json" ]]; then
          # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
          jq_to moved -r -n --arg id "$id" --arg sc "$scope" \
            --slurpfile pre "$RUN_DIR/pre.$mp.json" --slurpfile post "$after_step2" \
            '[$post[0].installed[]? | select(.id == $id and .scope == $sc and .currentProject != true)
              | . as $r | select(([$pre[0].installed[]? | select(.id == $id and .scope == $sc
                  and .projectPath == $r.projectPath) | .version] | first) != $r.version)
              | .projectPath] | map("\"\(.)\"") | join(", ")'
        fi
        IR_FAILED+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg old "$old" --arg new "$new" --arg moved "$moved" \
          '{id: $id, scope: $sc, rc: 0, output: "",
            reason: ("the CLI reported \($old) to \($new), but this project'"'"'s record is still at \($old): it updated "
              + (if $moved == "" then "another record of the id (a sibling worktree'"'"'s)" else $moved end) + " instead")}')")
        continue
      fi
    fi
    if [[ -z "$new" ]]; then
      new="unknown"
      dir="unknown"
    else
      dir=$(version_direction "$old" "$new")
    fi
    case "$dir" in
    same) continue ;;
    backward)
      DOWNGRADED+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg o "$old" --arg n "$new" \
        '{id: $id, scope: $sc, old: $o, new: $n}')")
      ;;
    *)
      row=$(jq -c -n --arg id "$id" --arg sc "$scope" --arg o "$old" --arg n "$new" --arg d "$dir" \
        '{id: $id, scope: $sc, old: $o, new: $n, direction: $d}')
      if [[ "$kind" == "in_repo" ]]; then IR_UPDATED+=("$row"); else US_UPDATED+=("$row"); fi
      ;;
    esac
  done <"$RUN_DIR/moves.$mp.tsv"
}

# --- report rows that live in the state, not in this run's actions ------------------
# SKILL.md's Report has rows whose only source is a fleet-state report: the
# marketplace's own autoUpdate, the stale project records, the user-scope orphans,
# and the share of actionable divergences that belong to the repo the run stands in.
# They ride the digest so the report costs no extra read.
#
# `auto_update` is read from the snapshot directly, never through `//`: jq's
# alternative operator treats `false` as absent, so `false // null` is `null`,
# and a marketplace with autoUpdate off would read as unreadable. fleet-state.sh
# already normalizes the field to a JSON boolean, so a snapshot that carries it
# yields `true` or `false`; `null` is reserved for no snapshot at all, or a
# snapshot whose marketplace block never resolved far enough to carry the field.
report_extras() {
  local __var="$1"
  local mp="$2"
  local src=""
  for src in "$RUN_DIR/post.$mp.json" "$RUN_DIR/pre-install.$mp.json" "$RUN_DIR/pre.$mp.json" \
    "$RUN_DIR/pre-refresh.$mp.json"; do
    [[ -f "$src" ]] && break
    src=""
  done
  if [[ -z "$src" ]]; then
    jq_to "$__var" -c -n '{auto_update: null, catalog_source: null, user_scope_orphans: [],
      user_home_records: {total: 0, paths: []},
      delisted: [], delisted_project: [], delisted_settings_only: [],
      stale_project_records: {total: null, paths: null, by_parent: [], more_parents: 0, list_file: null},
      in_repo_records: null, in_repo_ids: [], divergences_here: null}'
    return 0
  fi
  # The full per-path list goes to a run-directory file, not the digest: a
  # machine with thousands of absent paths would otherwise put every one of them
  # on the digest line and in the report. Audit's scratch directory is removed on
  # exit, so audit writes no file and names none.
  local list_file=""
  local stale_list=""
  if [[ "$MODE" != "audit" ]] &&
    jq_to stale_list -c '[.installed[]? | select(.projectPathPresent == false)] | group_by(.projectPath)
      | map({path: .[0].projectPath, count: length})' "$src" &&
    [[ "$stale_list" != "[]" ]] &&
    printf '%s\n' "$stale_list" >"$RUN_DIR/stale-project-records.$mp.json"; then
    list_file="$RUN_DIR/stale-project-records.$mp.json"
  fi
  # `in_repo_records` is the count of project/local records belonging to the repo
  # the run stands in, independent of whether any of them diverged. The report's
  # `In-repo:` row needs exactly that: `0` means this root has no project/local
  # installs, and the intersection with the divergences answers a different
  # question. `by_parent` groups the absent paths by parent directory, largest
  # record count first, capped at STALE_PARENT_ROWS rows; `more_parents` counts
  # the groups past the cap.
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to "$__var" -c --argjson cap "$STALE_PARENT_ROWS" --arg list_file "$list_file" \
    --argjson audit "$([[ "$MODE" == "audit" ]] && echo true || echo false)" \
    "$ACTIONABLE_DEF$TRIPLE_DEF"'
    def parent: capture("^(?<p>.*[/\\\\])[^/\\\\]+[/\\\\]*$").p // .;
    ([.divergences[]? | actionable | .id]) as $act
    | .catalog_versions as $cv
    | ([.installed[]? | select(.currentProject == true) | .id]) as $here
    | ([.installed[]? | select(.projectPathPresent == false)]) as $absent
    # A home record still below the catalog, or with no version to compare: the
    # ones Step 3a could not move. Under --audit, the present ones it would move
    # are left out.
    | ([.installed[]? | select(.projectPathIsHome == true)
        | select(($cv[.id] | triple) as $c | (.version | triple) as $v
                 | ($c == null or $v == null or $v < $c)
                   and (($audit and .projectPathPresent == true and $c != null and $v != null) | not))]) as $homes
    | {auto_update: .marketplace.autoUpdate,
       user_home_records: {total: ($homes | length),
                           paths: ($homes | map(.projectPath) | unique)},
       catalog_source: (.marketplace.source // null),
       user_scope_orphans: (.user_scope_orphans // []),
       delisted: (.delisted // []),
       delisted_project: (.delisted_project // []),
       delisted_settings_only: (.delisted_settings_only // []),
       stale_project_records: (($absent | group_by(.projectPath | parent)
                                | map({parent: (.[0].projectPath | parent), count: length,
                                       paths: (map(.projectPath) | unique | length)})
                                | sort_by(-.count, .parent)) as $groups
                               | {total: ($absent | length),
                                  paths: ($absent | map(.projectPath) | unique | length),
                                  project: ($absent | map(select(.scope == "project")) | length),
                                  "local": ($absent | map(select(.scope == "local")) | length),
                                  by_parent: $groups[:$cap],
                                  more_parents: ([0, ($groups | length) - $cap] | max),
                                  list_file: (if $list_file == "" then null else $list_file end)}),
       in_repo_records: ($here | length),
       in_repo_ids: $here,
       divergences_here: ($act | map(select(. as $i | $here | index($i))) | length)}' "$src"
}

# --- a directory source's checkout, read without changing it -----------------------
# `claude plugin marketplace update` on a `directory` source validates the
# directory as it is ("Validating local marketplace") and fetches nothing, so the
# catalog is only as fresh as that checkout. This reads the checkout's branch,
# upstream, ahead/behind counts against the upstream as of its last fetch, and
# whether tracked files are modified. It never fetches, pulls, or writes:
# `--no-optional-locks` keeps `status` from refreshing the index. `null` for any
# other source kind, whose installLocation clone Claude Code itself manages.
# `catalog_source` is `directory:<path>` with the path as recorded (native form
# on Windows), folded to forward slashes the way fleet-state.sh folds
# installLocation.
source_checkout() {
  local __var="$1"
  local src="$2"
  local path
  local state="tracking"
  local branch=""
  local upstream=""
  local counts="0 0"
  local dirty=""
  if [[ "$src" != directory:* ]]; then
    printf -v "$__var" '%s' null
    return 0
  fi
  path="${src#directory:}"
  path="${path//\\//}"
  local g=(git --no-optional-locks -C "$path")
  if [[ "$("${g[@]}" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
    state="not_a_repo"
  else
    dirty=$("${g[@]}" status --porcelain --untracked-files=no 2>/dev/null | head -n 1)
    if ! branch=$("${g[@]}" symbolic-ref -q --short HEAD 2>/dev/null); then
      state="detached"
    elif ! upstream=$("${g[@]}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) ||
      ! counts=$("${g[@]}" rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null); then
      state="no_upstream"
      counts="0 0"
    fi
  fi
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to "$__var" -c -n --arg path "$path" --arg state "$state" --arg branch "$branch" \
    --arg upstream "$upstream" --arg counts "$counts" --arg dirty "$dirty" '
    [$counts | splits("[ \t]+") | tonumber? // 0] as $c
    | {path: $path, state: $state,
       branch: (if $branch == "" then null else $branch end),
       upstream: (if $state == "tracking" then $upstream else null end),
       ahead: (if $state == "tracking" then $c[0] else null end),
       behind: (if $state == "tracking" then $c[1] else null end),
       dirty: (if $state == "not_a_repo" then null else $dirty != "" end)}'
}

# --- monitors in the plugins this run moved ---------------------------------------
# A plugin updated mid-session keeps running its previous version's monitors
# until the session restarts, so the report names every moved plugin whose
# installed build declares one. The manifest is read from the record's own
# cache directory in the post-sweep snapshot, which is the build the update
# left in place.
#   Claim: a plugin declares monitors under the nested experimental.monitors
#     value or, when that key is absent, a top-level monitors value, as an
#     inline array or a path. monitors/monitors.json counts only when neither
#     key is present, because a present key replaces that file. An updated
#     plugin's monitors need a session restart; /reload-plugins does not switch
#     them.
#   Basis: https://code.claude.com/docs/en/plugins/manifest-reference#monitors,
#     https://code.claude.com/docs/en/plugins/manifest-reference#how-each-key-combines-with-its-default-location
#     and https://code.claude.com/docs/en/plugins/loading#which-marketplaces-and-plugins-auto-update
#   As of: 2026-10-04.
#   Recheck: the reference renames either key, stops a declared key from
#     replacing monitors/monitors.json, or the loading page stops requiring a
#     restart for an updated plugin's monitors.
monitor_count_at() {
  # `__mc_*` names: the caller passes its own variable name in $1, and a local
  # of the same name here would shadow it, so nothing here is called `n`.
  local __mc_var="$1"
  local __mc_root="$2"
  local __mc_manifest="$2/.claude-plugin/plugin.json"
  local __mc_n="0"
  local __mc_spec=""
  local __mc_kind=""
  local __mc_path=""
  printf -v "$__mc_var" '%s' "0"
  [[ -d "$__mc_root" ]] || return 0
  if [[ -f "$__mc_manifest" ]]; then
    # Nested experimental.monitors wins over a top-level monitors key, the same
    # order as (.experimental.monitors // .monitors). Presence is has(), not
    # //: an empty array is a declared value and must not fall through to the
    # default file, and neither must an explicit null.
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    if ! jq_to __mc_spec -c '
      if (.experimental | type) == "object" and (.experimental | has("monitors")) then
        {present: true, value: .experimental.monitors}
      elif has("monitors") then
        {present: true, value: .monitors}
      else {present: false} end' "$__mc_manifest" 2>/dev/null; then
      __mc_kind="unreadable"
    else
      jq_to __mc_kind -r 'if .present == true then "true" else "false" end' <<<"$__mc_spec" 2>/dev/null || __mc_kind="unreadable"
    fi
    case "$__mc_kind" in
    true)
      # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
      jq_to __mc_n -r '
        .value
        | if type == "array" then "array:\(length)"
          elif type == "string" then "path:\(.)"
          else "other" end' <<<"$__mc_spec" 2>/dev/null || __mc_n="other"
      case "$__mc_n" in
      array:*) __mc_n="${__mc_n#array:}" ;;
      path:*)
        __mc_path="${__mc_n#path:}"
        __mc_path="${__mc_path#./}"
        __mc_n="0"
        [[ -f "$__mc_root/$__mc_path" ]] &&
          jq_to __mc_n -r 'if type == "array" then length else 0 end' "$__mc_root/$__mc_path" 2>/dev/null
        ;;
      *) __mc_n="0" ;;
      esac
      ;;
    false) ;;
    *)
      # Unreadable manifest: a key may be present and we cannot see it, so the
      # default file is not a safe fallback.
      __mc_kind="unreadable"
      ;;
    esac
  fi
  if [[ "$__mc_kind" != "true" && "$__mc_kind" != "unreadable" && -f "$__mc_root/monitors/monitors.json" ]]; then
    jq_to __mc_n -r 'if type == "array" then length else 0 end' "$__mc_root/monitors/monitors.json" 2>/dev/null || __mc_n="0"
  fi
  [[ "$__mc_n" =~ ^[0-9]+$ ]] || __mc_n="0"
  printf -v "$__mc_var" '%s' "$__mc_n"
}

monitor_rows() {
  local __var="$1"
  local mp="$2"
  local post="$RUN_DIR/post.$mp.json"
  local row
  local id
  local scope
  local path
  local n
  local rows=()
  printf -v "$__var" '%s' "[]"
  [[ -f "$post" ]] || return 0
  for row in ${IR_UPDATED[@]+"${IR_UPDATED[@]}"} ${US_UPDATED[@]+"${US_UPDATED[@]}"} \
    ${DOWNGRADED[@]+"${DOWNGRADED[@]}"} ${MOVED_DURING[@]+"${MOVED_DURING[@]}"}; do
    # A backward concurrent move sits in both arrays; the downgraded copy counts.
    [[ "$row" == *'"kind":'* && "$row" == *'"direction":"backward"'* ]] && continue
    jq_to id -r '.id' <<<"$row"
    jq_to scope -r '.scope' <<<"$row"
    # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
    jq_to path -r --arg id "$id" --arg sc "$scope" \
      'first(.installed[]? | select(.id == $id and .scope == $sc
        and ($sc == "user" or .currentProject == true)) | .installPath) // ""' "$post"
    [[ -n "$path" ]] || continue
    monitor_count_at n "${path//\\//}"
    ((n > 0)) || continue
    rows+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --argjson n "$n" '{id: $id, scope: $sc, monitors: $n}')")
  done
  json_array_of "$__var" ${rows[@]+"${rows[@]}"}
}

# The block's `source_pull`: what a requested fast-forward recorded, else what
# the run does with a behind checkout. It offers one only when the guard would
# let it through, the policy is ask and the mode is sync; otherwise it skips it
# and says why. Null when nothing is behind and nothing was requested.
source_pull_field() {
  local __var="$1"
  local checkout="$2"
  if [[ "$SOURCE_PULL_JSON" != "null" ]]; then
    printf -v "$__var" '%s' "$SOURCE_PULL_JSON"
    return 0
  fi
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to "$__var" -c --arg off "$SOURCE_PULL_OFF" --arg mode "$MODE" "$FF_REFUSAL_DEF"'
    if . == null or (.behind // 0) == 0 then null
    else ff_refusal as $r
      | if $r != "" then {status: "skipped", reason: $r}
        elif $off != "" then {status: "skipped", reason: $off}
        elif $mode == "audit" then {status: "skipped", reason: "audit changes nothing"}
        else {status: "offered", reason: ""} end
    end' <<<"$checkout"
}

# --- one marketplace block --------------------------------------------------------
emit_marketplace_block() {
  local mp="$1"
  local ir_u
  local ir_f
  local ir_w
  local ir_l
  local us_u
  local us_f
  local us_w
  local wh
  local dg
  local moved
  local inst
  local en
  local pr
  local rec
  local errs
  local unset_cfg
  local installed_disabled
  local monitors
  # A marketplace abandoned on a failed read reaches here without finalize_moves.
  [[ -n "$T_FN_S" ]] || clock_into T_FN_S
  # Written on the first pass only. The re-entry reads this sidecar; overwriting
  # it after restore would drop the first-pass failures from a later re-entry.
  if ((ONLY_INSTALL_MODE == 0)); then
    persist_first_pass_rows "$mp"
  fi
  local reg_interval
  local reg_rows
  local div
  local extras
  local block
  local checkout
  local pull

  json_array_of ir_u ${IR_UPDATED[@]+"${IR_UPDATED[@]}"}
  json_array_of ir_f ${IR_FAILED[@]+"${IR_FAILED[@]}"}
  json_array_of ir_w ${IR_WOULD[@]+"${IR_WOULD[@]}"}
  json_array_of ir_l ${IR_LIVE[@]+"${IR_LIVE[@]}"}
  json_array_of us_u ${US_UPDATED[@]+"${US_UPDATED[@]}"}
  json_array_of us_f ${US_FAILED[@]+"${US_FAILED[@]}"}
  json_array_of us_w ${US_WOULD[@]+"${US_WOULD[@]}"}
  json_array_of wh ${WITHHELD[@]+"${WITHHELD[@]}"}
  json_array_of dg ${DOWNGRADED[@]+"${DOWNGRADED[@]}"}
  json_array_of moved ${MOVED_DURING[@]+"${MOVED_DURING[@]}"}
  json_array_of inst ${INSTALLED_ROWS[@]+"${INSTALLED_ROWS[@]}"}
  json_array_of en ${ENABLED_ROWS[@]+"${ENABLED_ROWS[@]}"}
  json_array_of pr ${PROJECT_ROWS[@]+"${PROJECT_ROWS[@]}"}
  json_array_of rec ${RECOVERED_ROWS[@]+"${RECOVERED_ROWS[@]}"}
  json_strings_of errs ${MP_ERRORS[@]+"${MP_ERRORS[@]}"}

  catalog_regression_rows reg_interval reg_rows "$mp"
  divergence_block div "$mp"
  report_extras extras "$mp"
  jq_to checkout -r '.catalog_source // ""' <<<"$extras"
  source_checkout checkout "$checkout"
  source_pull_field pull "${checkout:-null}"
  monitor_rows monitors "$mp"
  # The two Action-needed sources.
  jq_to unset_cfg -c '[.[] | select(.unset_user_config != null)
    | {id, options_unset: .unset_user_config.options_unset, required: .unset_user_config.required}]' <<<"$inst"
  # An id this run went on to enable at user scope is no longer disabled.
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to installed_disabled -c -s '
    .[0] as $inst | .[1] as $en
    | [$en[] | select(.predicted == false and .rc == 0 and .scope == "user") | .id] as $on
    | [$inst[] | select(.rc == 0 and .disabled_by_default == true) | .id | select(IN($on[]) | not)]' \
    <<<"$inst"$'\n'"$en"
  # A field that could not be computed becomes an empty object, never an empty
  # string: an empty value would leave the args file invalid and drop the block.
  [[ -n "$div" ]] || div='{}'
  [[ -n "$extras" ]] || extras='{}'
  [[ -n "$reg_rows" ]] || reg_rows='[]'

  # The window closes here, after every read above, so the `finalize` step
  # carries their cost; only the jq below and the append fall outside it.
  clock_into T_MP_E
  local args_file="$RUN_DIR/.block-args.$mp.json"
  local err_file="$RUN_DIR/.block-err.$mp"
  local block_rc=0
  local jq_err=""
  json_object_file "$args_file" \
    refresh_rc "${REFRESH_RC:-null}" refresh_predicted "$REFRESH_PREDICTED" \
    project_root "$PROJECT_ROOT_JSON" \
    ir_u "$ir_u" ir_f "$ir_f" ir_w "$ir_w" ir_l "$ir_l" \
    us_u "$us_u" us_f "$us_f" us_w "$us_w" wh "$wh" dg "$dg" \
    moved "$moved" noop_unverified "$NOOP_UNVERIFIED" \
    install_gap "$INSTALL_GAP" inst "$inst" \
    enable_gap "$ENABLE_GAP" en "$en" pr "$pr" rec "$rec" \
    deferred "$INSTALL_DEFERRED" stopped "$STOPPED_BEFORE_INSTALL" \
    normalize "$NORMALIZE_JSON" cache "$CACHE_JSON" reg_rows "$reg_rows" \
    div "$div" self_updated "$SELF_UPDATED" self_update "$SELF_UPDATE" \
    extras "$extras" checkout "${checkout:-null}" pull "${pull:-null}" \
    unset_cfg "${unset_cfg:-[]}" installed_disabled "${installed_disabled:-[]}" \
    monitors "${monitors:-[]}" errors "$errs" other_paths "$OTHER_PATHS_JSON"
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to block -c \
    --arg name "$mp" \
    --arg lastUpdated "$CATALOG_LAST_UPDATED" \
    --arg refresh_out "$REFRESH_OUT" \
    --arg refresh_reason "$REFRESH_REASON" \
    --arg reg_interval "$reg_interval" \
    --arg t_prr_s "$T_PRR_S" --arg t_prr_e "$T_PRR_E" \
    --arg t_mu_s "$T_MU_S" --arg t_mu_e "$T_MU_E" \
    --arg t_ir_s "$T_IR_S" --arg t_ir_e "$T_IR_E" \
    --arg t_us_s "$T_US_S" --arg t_us_e "$T_US_E" \
    --arg t_pi_s "$T_PI_S" --arg t_pi_e "$T_PI_E" \
    --arg t_ie_s "$T_IE_S" --arg t_ie_e "$T_IE_E" \
    --arg t_cc_s "$T_CC_S" --arg t_cc_e "$T_CC_E" \
    --arg t_pr_s "$T_PR_S" --arg t_pr_e "$T_PR_E" \
    --arg t_fn_s "$T_FN_S" \
    --arg t_mp_s "$T_MP_S" --arg t_mp_e "$T_MP_E" \
    --arg resolution "$CLOCK_RESOLUTION" '
    # Seconds to three decimals; an empty stamp pair is a step that did not run.
    # Steps round DOWN and the total rounds UP, so the total is never below the
    # sum of its steps after rounding. Clamped at zero so a wall clock stepped
    # backwards mid-run cannot report a negative duration.
    def ms($s; $e): (($e | tonumber) - ($s | tonumber)) * 1000;
    def dur($s; $e):
      if $s == "" or $e == "" then null else ([0, ((ms($s; $e) | floor) / 1000)] | max) end;
    def dur_up($s; $e):
      if $s == "" or $e == "" then null else ([0, ((ms($s; $e) | ceil) / 1000)] | max) end;
    . as {$refresh_rc, $refresh_predicted, $project_root, $ir_u, $ir_f, $ir_w, $ir_l,
          $us_u, $us_f, $us_w, $wh, $dg, $moved, $noop_unverified, $install_gap, $inst,
          $enable_gap, $en, $pr, $rec, $deferred, $stopped, $normalize, $cache, $reg_rows,
          $div, $self_updated, $self_update, $extras, $checkout, $pull, $unset_cfg,
          $installed_disabled, $monitors, $errors, $other_paths}
    | {pre_refresh_read: dur($t_prr_s; $t_prr_e),
     marketplace_update: dur($t_mu_s; $t_mu_e),
     in_repo_update: dur($t_ir_s; $t_ir_e),
     user_sweep: dur($t_us_s; $t_us_e),
     pre_install_read: dur($t_pi_s; $t_pi_e),
     install_enable: dur($t_ie_s; $t_ie_e),
     cache_content_check: dur($t_cc_s; $t_cc_e),
     post_read: dur($t_pr_s; $t_pr_e),
     finalize: dur($t_fn_s; $t_mp_e)} as $steps
    | dur_up($t_mp_s; $t_mp_e) as $total
    # The time between and around the named steps, so the steps plus this
    # remainder account for the whole total.
    | (if $total == null then null
       else [0, ((($total * 1000) - ([$steps[] | select(. != null)] | add // 0) * 1000) | round) / 1000]
            | max end) as $unattributed
    | $extras + {name: $name,
     timings: ($steps + {unattributed: $unattributed, total: $total, resolution: $resolution}),
     catalog_last_updated: (if $lastUpdated == "" then null else $lastUpdated end),
     source_checkout: $checkout,
     source_pull: $pull,
     refresh: {rc: $refresh_rc, output: $refresh_out, reason: $refresh_reason, predicted: $refresh_predicted},
     project_root: $project_root,
     in_repo: {updated: $ir_u, failed: $ir_f, would_update: $ir_w, live_read: $ir_l},
     user_sweep: {updated: $us_u, failed: $us_f, would_update: $us_w,
                  withheld_downgrades: $wh},
     downgraded: $dg,
     moved_during_run: $moved,
     noop_unverified: $noop_unverified,
     install_gap: $install_gap,
     installed: $inst,
     installed_with_unset_user_config: $unset_cfg,
     installed_disabled: $installed_disabled,
     install_enable_deferred: $deferred,
     stopped_before_install: $stopped,
     enable_gap: $enable_gap,
     enabled: $en,
     project_enable_rows: $pr,
     other_paths: $other_paths,
     pending_enable: $rec,
     normalize: $normalize,
     cache_content: $cache,
     catalog_regression: (if $reg_interval == "" then null
                          else {interval: $reg_interval, rows: $reg_rows} end),
     divergences: $div,
     self_updated: $self_updated,
     self_update: $self_update,
     updated_with_monitors: $monitors,
     errors: $errors}' "$args_file" 2>"$err_file" || block_rc=$?
  if ((block_rc == 0)) && [[ -n "$block" ]]; then
    printf '%s\n' "$block" >>"$RUN_DIR/.blocks.jsonl"
    return 0
  fi
  # The steps above already ran and only the report block is missing, so the
  # run names the failure instead of reading as if no marketplace resolved.
  # render-report.jq matches this wording to tell the two apart: change both
  # together.
  [[ -f "$err_file" ]] && IFS= read -r jq_err <"$err_file"
  jq_err="${jq_err//$'\r'/}"
  run_error "marketplace $mp: its report block could not be assembled (jq exit $block_rc: ${jq_err:-no error output})"
}

# --- main --------------------------------------------------------------------------
setup_run_dir
pending_path

# `--allow-downgrade` belongs to the RUN, not to one invocation of it. A re-entry
# that omitted the flag would otherwise rebuild the withheld list from
# `downgrades.<mp>.txt` and report a downgrade the first pass already applied. The
# flag is written once by the pass that starts the run and read back by the
# re-entry, before anything branches on it; a run directory from an older version
# carries no file and keeps the previous behavior.
# The `install_new` policy and the invalid value it replaced belong to the run the
# same way. The re-entry takes no `--install-new`, so without the saved pair its
# digest, which supersedes the first one, would drop the invalid-value warning.
SAVED_ALLOW_DOWNGRADE=""
SAVED_INSTALL_NEW=""
SAVED_INSTALL_NEW_INVALID=""
if ((ONLY_INSTALL_MODE == 1)); then
  if [[ -f "$RUN_DIR/flags.json" ]]; then
    jq_to SAVED_ALLOW_DOWNGRADE -r '.allow_downgrade // false' "$RUN_DIR/flags.json" 2>/dev/null
    [[ "$SAVED_ALLOW_DOWNGRADE" != "true" ]] || ALLOW_DOWNGRADE=1
    jq_to SAVED_INSTALL_NEW -r '.install_new // ""' "$RUN_DIR/flags.json" 2>/dev/null
    jq_to SAVED_INSTALL_NEW_INVALID -r '.install_new_invalid // ""' "$RUN_DIR/flags.json" 2>/dev/null
    # The pair is restored together, so the digest never names a policy beside
    # an invalid value from a different invocation.
    case "$SAVED_INSTALL_NEW" in
    all | none | ask)
      INSTALL_NEW="$SAVED_INSTALL_NEW"
      INSTALL_NEW_INVALID="$SAVED_INSTALL_NEW_INVALID"
      ;;
    *) ;;
    esac
    # The pull policy and the quiet list belong to the run too, so the digest
    # that supersedes the first one renders the same Marketplace rows.
    SAVED_SOURCE_PULL=""
    jq_to SAVED_SOURCE_PULL -r '.source_pull // ""' "$RUN_DIR/flags.json" 2>/dev/null
    case "$SAVED_SOURCE_PULL" in
    ask | never)
      SOURCE_PULL="$SAVED_SOURCE_PULL"
      jq_to SOURCE_PULL_INVALID -r '.source_pull_invalid // ""' "$RUN_DIR/flags.json" 2>/dev/null
      jq_to SOURCE_PULL_OFF -r '.source_pull_off // ""' "$RUN_DIR/flags.json" 2>/dev/null
      jq_to QUIET_AUTO_UPDATE -r '.quiet_auto_update // [] | join(",")' "$RUN_DIR/flags.json" 2>/dev/null
      # The saved reason stands unless this session is the autonomous one.
      [[ -z "${CLAUDE_CODE_REMOTE:-}" ]] || apply_pull_policy
      ;;
    *) ;;
    esac
  fi
else
  FLAG_AD="false"
  ((ALLOW_DOWNGRADE == 0)) || FLAG_AD="true"
  FLAG_IN=""
  json_string_to FLAG_IN "$INSTALL_NEW"
  FLAG_INV="null"
  [[ -z "$INSTALL_NEW_INVALID" ]] || json_string_to FLAG_INV "$INSTALL_NEW_INVALID"
  FLAG_SP=""
  json_string_to FLAG_SP "$SOURCE_PULL"
  FLAG_SPI="null"
  [[ -z "$SOURCE_PULL_INVALID" ]] || json_string_to FLAG_SPI "$SOURCE_PULL_INVALID"
  FLAG_SPO="null"
  [[ -z "$SOURCE_PULL_OFF" ]] || json_string_to FLAG_SPO "$SOURCE_PULL_OFF"
  FLAG_QAU="[]"
  # shellcheck disable=SC2086  # word splitting on the comma-folded list is the point
  json_strings_of FLAG_QAU ${QUIET_AUTO_UPDATE//,/ }
  printf '{"allow_downgrade":%s,"install_new":%s,"install_new_invalid":%s,"source_pull":%s,"source_pull_invalid":%s,"source_pull_off":%s,"quiet_auto_update":%s}\n' \
    "$FLAG_AD" "$FLAG_IN" "$FLAG_INV" "$FLAG_SP" "$FLAG_SPI" "$FLAG_SPO" "$FLAG_QAU" >"$RUN_DIR/flags.json"
fi

# The first pass's run-level timings, written by that pass once its clock stops
# and read back by a re-entry, so the superseding digest times both passes. Only
# the first pass writes it: a second re-entry reports the first pass plus itself.
# A run directory from an older version carries no file, and the re-entry then
# times itself alone, as before.
FIRST_PASS_RUN="$RUN_DIR/first-pass-run.json"
FIRST_PASS_TIMINGS="null"
if ((ONLY_INSTALL_MODE == 1)) && [[ -f "$FIRST_PASS_RUN" ]]; then
  jq_to FIRST_PASS_TIMINGS -c '.timings | select((.total | type) == "number")
    | {total, resolution,
       outside_marketplaces: (if (.outside_marketplaces | type) == "number" then .outside_marketplaces else null end)}' \
    "$FIRST_PASS_RUN" 2>/dev/null || FIRST_PASS_TIMINGS="null"
  [[ -n "$FIRST_PASS_TIMINGS" ]] || FIRST_PASS_TIMINGS="null"
fi

: >"$RUN_DIR/.blocks.jsonl"
[[ -f "$JOURNAL_LOG" ]] || : >"$JOURNAL_LOG"

MPS=()
if ((ONLY_INSTALL_MODE == 1)); then
  # The re-entry's marketplaces are the ones the first pass actually swept, read off
  # its own snapshots. Resolving the default again would run Steps 4 and 5 against
  # one marketplace and emit a one-block digest for a run that covered several,
  # which is the silent partial sweep the marketplace-scoping rule exists to
  # prevent.
  for snapshot in "$RUN_DIR"/pre-refresh.*.json; do
    [[ -f "$snapshot" ]] || continue
    snapshot="${snapshot##*/pre-refresh.}"
    MPS+=("${snapshot%.json}")
  done
  if [[ -n "$TARGET_MP" ]]; then
    if [[ ! -f "$RUN_DIR/pre-refresh.$TARGET_MP.json" ]]; then
      echo "ERROR: that run directory carries no snapshot for marketplace: $TARGET_MP" >&2
      echo "  --only-install re-enters a run; it cannot start one for a new marketplace." >&2
      exit 2
    fi
    MPS=("$TARGET_MP")
  fi
  if ((${#MPS[@]} == 0)); then
    echo "ERROR: that run directory carries no marketplace snapshot: $RUN_DIR" >&2
    exit 2
  fi
elif ((ALL == 1)); then
  # Names come from the script, never a hand-written jq over known_marketplaces.json:
  # enumerating names carries the same trailing-`\r` hazard as enumerating ids.
  if ! "$FLEET_STATE" --marketplaces >"$RUN_DIR/.marketplaces.txt" 2>"$RUN_DIR/.fs-err"; then
    echo "ERROR: could not enumerate marketplaces" >&2
    cat "$RUN_DIR/.fs-err" >&2
    exit 2
  fi
  while IFS= read -r line; do
    line="${line//$'\r'/}"
    [[ -n "$line" ]] || continue
    MPS+=("$line")
  done <"$RUN_DIR/.marketplaces.txt"
elif [[ -n "$TARGET_MP" ]]; then
  MPS=("$TARGET_MP")
else
  # The default marketplace, resolved dynamically. The resolving read IS Step 1's
  # pre-refresh snapshot, so it is saved under the resolved name rather than repeated,
  # and its stamps are that marketplace's `pre_refresh_read` timing.
  clock_into MAIN_READ_S
  if ! "$FLEET_STATE" >"$RUN_DIR/.default.json" 2>"$RUN_DIR/.fs-err"; then
    echo "ERROR: could not resolve the default marketplace" >&2
    cat "$RUN_DIR/.fs-err" >&2
    exit 2
  fi
  clock_into MAIN_READ_E
  jq_to DEFAULT_MP -r '.marketplace.name // ""' "$RUN_DIR/.default.json"
  if [[ -z "$DEFAULT_MP" ]]; then
    echo "ERROR: the default marketplace report carries no marketplace name" >&2
    exit 2
  fi
  MPS=("$DEFAULT_MP")
  MAIN_READ_MP="$DEFAULT_MP"
  [[ -f "$RUN_DIR/pre-refresh.$DEFAULT_MP.json" ]] ||
    mv "$RUN_DIR/.default.json" "$RUN_DIR/pre-refresh.$DEFAULT_MP.json"
fi

if ((${#MPS[@]} == 0)); then
  run_error "no marketplace resolved for this run"
fi

for mp in ${MPS[@]+"${MPS[@]}"}; do
  run_marketplace "$mp"
done

# Each marketplace skips the ids that are not its own, so an id no marketplace in
# the run claims would vanish from the report. Name it once the whole run has been
# considered.
if ((ONLY_INSTALL_MODE == 1)); then
  for id in ${ONLY_INSTALL//,/ }; do
    claimed=0
    for mp in ${MPS[@]+"${MPS[@]}"}; do
      [[ "$id" == *"@$mp" ]] && claimed=1
    done
    ((claimed == 1)) || run_error "--only-install id matches no marketplace in this run: $id"
  done
fi
# A name no marketplace in the run carries would otherwise pull nothing and say
# nothing.
if ((PULL_SOURCES_SET == 1)); then
  for name in ${PULL_SOURCES//,/ }; do
    claimed=0
    for mp in ${MPS[@]+"${MPS[@]}"}; do
      [[ "$name" == "$mp" ]] && claimed=1
    done
    ((claimed == 1)) || run_error "--pull-source names no marketplace in this run: $name"
  done
fi

# Declared here as well as filled below, so the lint can see the assignment the
# write-into-variable helper makes.
RUN_ERRS='[]'
json_strings_of RUN_ERRS ${RUN_ERRORS[@]+"${RUN_ERRORS[@]}"}

DIGEST=""
ALLOW_DOWNGRADE_JSON="false"
((ALLOW_DOWNGRADE == 1)) && ALLOW_DOWNGRADE_JSON="true"
QUIET_JSON='[]'
# shellcheck disable=SC2086  # word splitting on the comma-folded list is the point
json_strings_of QUIET_JSON ${QUIET_AUTO_UPDATE//,/ }
T_RUN_E=""
clock_into T_RUN_E

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
jq_to DIGEST -c -n \
  --arg run_dir "$RUN_DIR" \
  --arg cwd "$PWD" \
  --arg mode "$MODE" \
  --argjson allow_downgrade "$ALLOW_DOWNGRADE_JSON" \
  --arg install_new "$INSTALL_NEW" \
  --arg install_new_invalid "$INSTALL_NEW_INVALID" \
  --arg source_pull "$SOURCE_PULL" \
  --arg source_pull_invalid "$SOURCE_PULL_INVALID" \
  --argjson quiet_auto_update "$QUIET_JSON" \
  --slurpfile marketplaces "$RUN_DIR/.blocks.jsonl" \
  --arg t_run_s "$T_RUN_S" --arg t_run_e "$T_RUN_E" \
  --arg resolution "$CLOCK_RESOLUTION" \
  --argjson first "$FIRST_PASS_TIMINGS" \
  --argjson errors "$RUN_ERRS" '
  def ms_sum($a; $b): ((($a * 1000) + ($b * 1000)) | round) / 1000;
  # The combined total is only as fine as the coarser clock that timed it. The
  # rungs run fine to coarse here, not in the ladder'"'"'s try order.
  def coarser($a; $b):
    ["nanoseconds", "microseconds", "seconds"] as $rungs
    | if ($rungs | index($a)) == null then $b
      elif ($rungs | index($b)) == null then $a
      elif ($rungs | index($a)) > ($rungs | index($b)) then $a
      else $b end;
  (([0, (((($t_run_e | tonumber) - ($t_run_s | tonumber)) * 1000 | ceil) / 1000)] | max) as $total
   | {total: $total,
      # Run setup and the per-block assembly: the part of the total no
      # block window covers. The clock stops before this jq runs, since a digest
      # cannot time its own assembly without a second jq process.
      outside_marketplaces: ([0, ((($total * 1000)
                                   - ([$marketplaces[].timings.total | numbers] | add // 0) * 1000)
                                  | round) / 1000] | max),
      resolution: $resolution}) as $this
  # A re-entry adds the first pass it continues. The blocks time only this pass,
  # so `outside_marketplaces` sums each pass'"'"'s own remainder, and the wait
  # between the passes (the caller'"'"'s prompt) is in neither.
  | (if $first == null then $this
     else {total: ms_sum($first.total; $this.total),
           outside_marketplaces: (if $first.outside_marketplaces == null then $this.outside_marketplaces
                                  else ms_sum($first.outside_marketplaces; $this.outside_marketplaces) end),
           resolution: coarser($first.resolution; $this.resolution),
           passes: [{pass: "first"} + $first, {pass: "only_install"} + $this]}
     end) as $timings
  | {run_dir: $run_dir, cwd: $cwd, mode: $mode, allow_downgrade: $allow_downgrade,
     install_new: $install_new,
     install_new_invalid: (if $install_new_invalid == "" then null else $install_new_invalid end),
     source_pull: $source_pull,
     source_pull_invalid: (if $source_pull_invalid == "" then null else $source_pull_invalid end),
     quiet_auto_update: $quiet_auto_update,
     timings: $timings,
     marketplaces: $marketplaces, errors: $errors}'

printf '%s\n' "$DIGEST" >"$RUN_DIR/digest.json"
if [[ "$MODE" == "sync" ]] && ((ONLY_INSTALL_MODE == 0)); then
  FIRST_PASS_OUT=""
  jq_to FIRST_PASS_OUT -c '{timings}' <<<"$DIGEST" && printf '%s\n' "$FIRST_PASS_OUT" >"$FIRST_PASS_RUN"
fi

# --- Step 6 — the report, rendered from the digest --------------------------------
# A render failure is a defect in the renderer, never in the run: the digest is
# complete and printed either way, and the failure is named on stderr rather
# than swallowed.
REPORT=""
if jq_to REPORT -r -f "$SCRIPT_DIR/render-report.jq" "$RUN_DIR/digest.json"; then
  printf '%s\n' "$REPORT" >"$RUN_DIR/report.txt"
else
  echo "ERROR: report render failed; the digest above is complete, report.txt was not written" >&2
  REPORT=""
fi

printf '%s\n' "$DIGEST"
if ((RENDER == 1)) && [[ -n "$REPORT" ]]; then
  printf '\n%s\n' "$REPORT"
fi
exit 0
