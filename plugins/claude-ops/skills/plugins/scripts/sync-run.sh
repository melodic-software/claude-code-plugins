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
#               [--install-new all|none|ask] [--allow-downgrade]
#   sync-run.sh [--marketplace <name> | --all] --audit
#               [--install-new all|none|ask] [--allow-downgrade]
#   sync-run.sh --only-install <ids> --run-dir <dir> [--marketplace <name> | --all]
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
# reuses the cache-content report the first invocation already wrote, and re-emits
# the full digest. The cache checker therefore runs exactly ONCE per marketplace
# across both invocations.
#
# Output (stdout): one compact JSON object, also written to `<run_dir>/digest.json`.
#   {run_dir, mode, allow_downgrade, install_new, install_new_invalid,
#    marketplaces:[…], errors:[…]}
#   Each marketplace block: {name, catalog_last_updated, refresh:{rc,output,predicted},
#    project_root, in_repo:{updated,failed,would_update},
#    user_sweep:{updated,failed,would_update,withheld_downgrades},
#    downgraded, install_gap, installed, install_enable_deferred,
#    stopped_before_install, enable_gap, enabled, project_enable_rows, normalize,
#    cache_content, catalog_regression, divergences, self_updated, errors}
#   `updated` carries forward moves and unreadable-direction moves (flagged
#   `direction: "unknown"`); a pair whose new version is LOWER lands in `downgraded`
#   instead, which is what keeps a backward move off the report's `Updated:` line
#   even for an id the guard could not prove in advance.
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

# `set -e` is deliberately absent: it would abort a `{ …; } | tee` pipeline whose
# CLI element failed before `${PIPESTATUS[0]}` is read, and that status is what
# every mutating step here branches on.
set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required (install with: winget install jqlang.jq | apt install jq | brew install jq)" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_STATE="${SYNC_RUN_FLEET_STATE:-$SCRIPT_DIR/fleet-state.sh}"
CACHE_CHECK="${SYNC_RUN_CACHE_CHECK:-$SCRIPT_DIR/cache-content-check.sh}"
NORMALIZE="${SYNC_RUN_NORMALIZE:-$SCRIPT_DIR/normalize-enabled-plugins.sh}"
CLAUDE_BIN="${SYNC_RUN_CLAUDE_BIN:-claude}"

# fleet-state.sh resolves the DEFAULT marketplace by joining CLAUDE_PLUGIN_ROOT
# against the install records, so a headless run that never had it set still gets a
# target instead of an error. This script's own location is inside the plugin root
# by construction (<root>/skills/plugins/scripts), so it is the honest default.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

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

usage() {
  cat <<'EOF'
sync-run.sh — run `sync`/`audit` Steps 1-5b and print one JSON digest.

Usage:
  sync-run.sh [--marketplace <name> | --all] --journal-root <dir>
              [--install-new all|none|ask] [--allow-downgrade]
  sync-run.sh [--marketplace <name> | --all] --audit
              [--install-new all|none|ask] [--allow-downgrade]
  sync-run.sh --only-install <ids> --run-dir <dir> [--marketplace <name> | --all]
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

# --- jq capture ---------------------------------------------------------------
# Some native-Windows jq builds CRLF-terminate every line, including single-line
# compact output. `$(...)` strips only the trailing LF, so a stray CR survives at
# the end of a captured value and corrupts it once re-parsed as JSON, and every id
# but the last in a line-oriented output arrives as `<name>@<marketplace>\r`. Every
# jq call goes through this helper, which strips ALL carriage returns in the shell
# and stores the result in the named variable.
jq_to() {
  local __jq_var="$1"
  shift
  local __jq_out __jq_rc=0
  __jq_out=$(command jq "$@") || __jq_rc=$?
  printf -v "$__jq_var" '%s' "${__jq_out//$'\r'/}"
  return "$__jq_rc"
}

# JSON array of the non-empty lines of a file, CR-stripped. Used for every id list
# in the digest, so a `\r` can never ride into a report row or a later CLI call.
json_lines() {
  local __var="$1" __file="$2"
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

RUN_ERRORS=()
MP_ERRORS=()

run_error() { RUN_ERRORS+=("$1"); }
mp_error() { MP_ERRORS+=("$1"); }

# --- version direction ---------------------------------------------------------
# The same major.minor.patch triple compare the downgrade guard uses. Anything that
# does not parse on both sides is "unknown", never silently ranked: an unrankable
# pair is reported as such rather than assumed forward.
version_direction() {
  local old="$1" new="$2"
  local ore ore_ok=0 nre_ok=0
  local o1 o2 o3 n1 n2 n3
  if [[ "$old" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    o1=${BASH_REMATCH[1]}
    o2=${BASH_REMATCH[2]}
    o3=${BASH_REMATCH[3]}
    ore_ok=1
  fi
  if [[ "$new" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    n1=${BASH_REMATCH[1]}
    n2=${BASH_REMATCH[2]}
    n3=${BASH_REMATCH[3]}
    nre_ok=1
  fi
  ore="$ore_ok$nre_ok"
  if [[ "$ore" != "11" ]]; then
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

# That id's version in a saved fleet-state report, at that scope. Empty when the
# report does not carry the record.
version_at() {
  local __var="$1" report="$2" id="$3" scope="$4"
  jq_to "$__var" -r --arg id "$id" --arg sc "$scope" \
    'first(.installed[]? | select(.id == $id and .scope == $sc) | .version) // ""' "$report"
}

# --- journaled mutation --------------------------------------------------------
# The canonical shape from sync.md's "Run journal": the call and its output are
# appended to journal.log through `tee`, and `${PIPESTATUS[0]}` is read as the very
# next statement. A pipeline's own `$?` is `tee`'s status, and `tee` succeeds
# whenever it can write the log, so without this capture a failed CLI call journals
# its own error text and is then read as a success.
CLI_OUT=""
CLI_RC=0
run_cli() {
  local label="$1"
  shift
  local sink="$RUN_DIR/.last-cli-out"
  { echo "\$ $label"; "$CLAUDE_BIN" "$@" 2>&1; } | tee -a "$JOURNAL_LOG" >"$sink"
  CLI_RC=${PIPESTATUS[0]}
  CLI_OUT=$(<"$sink")
  CLI_OUT="${CLI_OUT//$'\r'/}"
}

# audit's stand-in for run_cli: journals the prediction, issues nothing.
predict_cli() {
  local label="$1"
  echo "would run: $label" >>"$JOURNAL_LOG"
  CLI_RC=0
  CLI_OUT="would run: $label"
}

# `<new>` from the CLI's own line, which is the only source that reflects an update
# immediately (sync.md's source 2). Empty when the line names no version.
cli_reported_version() {
  local __var="$1" text="$2"
  if [[ "$text" =~ updated\ from\ ([^[:space:]]+)\ to\ ([^[:space:]]+) ]]; then
    printf -v "$__var" '%s' "${BASH_REMATCH[2]}"
  else
    printf -v "$__var" '%s' ""
  fi
}

# --- projection ----------------------------------------------------------------
# Redirect the selector to a file and hand back the exit status. An empty
# projection is ambiguous: every `--from` rejection exits 2 with EMPTY stdout so a
# failure can never reach the CLI as an id, which makes the status the only thing
# that tells "nothing to do" from "the projection failed".
project_ids() {
  local selector="$1" from="$2" out="$3"
  "$FLEET_STATE" --ids "$selector" --from "$from" >"$out" 2>"$RUN_DIR/.proj-err"
  return $?
}

proj_err() {
  local text=""
  [[ -f "$RUN_DIR/.proj-err" ]] && text=$(<"$RUN_DIR/.proj-err")
  printf '%s' "${text//$'\r'/}"
}

# The digest is read by a model in one turn, so no single field may run away with
# the window. Output is kept, bounded.
trunc() {
  local __var="$1" text="$2" max="${3:-400}"
  if ((${#text} > max)); then
    printf -v "$__var" '%s' "${text:0:max}…"
  else
    printf -v "$__var" '%s' "$text"
  fi
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
# Step 3 sweeps every user-scope id, which necessarily includes the plugin
# providing this skill. Read the name from the manifest rather than hardcoding it,
# for the same reason no marketplace name is hardcoded.
own_plugin_name() {
  local manifest="$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" name=""
  [[ -f "$manifest" ]] && jq_to name -r '.name // ""' "$manifest" 2>/dev/null
  printf '%s' "$name"
}

# --- catalog regression --------------------------------------------------------
# Diff `catalog_versions` across consecutive saved snapshots and report the FIRST
# interval in which any id moved backward. That interval is what names the cause:
# in `sync` a regression across pre-refresh→pre is this run's refresh pulling a
# source that moved backward, while one appearing later is the checkout changing
# under the run. REPORT-ONLY — its output never becomes an id list handed to a CLI.
catalog_regression_rows() {
  local __interval_var="$1" __rows_var="$2" mp="$3"
  local snaps=(pre-refresh pre mid post)
  local i a b rows=""
  printf -v "$__interval_var" '%s' ""
  printf -v "$__rows_var" '%s' "[]"
  for ((i = 0; i + 1 < ${#snaps[@]}; i++)); do
    a="$RUN_DIR/${snaps[i]}.$mp.json"
    b="$RUN_DIR/${snaps[i + 1]}.$mp.json"
    [[ -f "$a" && -f "$b" ]] || continue
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
      printf -v "$__interval_var" '%s' "${snaps[i]}→${snaps[i + 1]}"
      printf -v "$__rows_var" '%s' "$rows"
      return 0
    fi
  done
  return 0
}

# --- divergence attribution ----------------------------------------------------
# Three snapshots, not two: Steps 2 and 3 both mutate versions, so a single
# pre/post bracket cannot tell which step created a new actionable divergence, and
# labelling the whole delta "the user-scope sweep" is wrong whenever Step 2 caused
# it. Only `versionsMatch: false` rows are actionable; a same-version multi-scope
# install is benign and is never counted.
divergence_block() {
  local __var="$1" mp="$2"
  local pre="$RUN_DIR/pre.$mp.json" mid="$RUN_DIR/mid.$mp.json" post="$RUN_DIR/post.$mp.json"
  if [[ ! -f "$pre" || ! -f "$mid" || ! -f "$post" ]]; then
    jq_to "$__var" -c -n '{pre: null, mid: null, post: null, new_total: null,
      new_by_interval: {in_repo: null, user_sweep: null}, pre_existing: null,
      note: "a snapshot was missing; the split could not be computed"}'
    return 0
  fi
  jq_to "$__var" -c -n \
    --slurpfile p "$pre" --slurpfile m "$mid" --slurpfile q "$post" '
    def act: [.divergences[]? | select(.versionsMatch == false) | .id];
    ($p[0] | act) as $pre | ($m[0] | act) as $mid | ($q[0] | act) as $post
    | ($post - $pre) as $new
    | {pre: ($pre | length), mid: ($mid | length), post: ($post | length),
       new_total: ($new | length),
       new_by_interval: {in_repo: ([$new[] | select(. as $i | $mid | index($i))] | length),
                         user_sweep: ([$new[] | select(. as $i | $mid | index($i) | not)] | length)},
       pre_existing: (($post | length) - ($new | length))}'
}

# --- per-marketplace accumulators ----------------------------------------------
# Script-scope rather than `local`, because the step helpers below append to them
# and a `local` array is invisible to a function the step calls.
IR_UPDATED=() IR_FAILED=() IR_WOULD=()
US_UPDATED=() US_FAILED=() US_WOULD=()
WITHHELD=() DOWNGRADED=() INSTALLED_ROWS=() ENABLED_ROWS=() PROJECT_ROWS=()
INSTALL_GAP="[]" ENABLE_GAP="[]" NORMALIZE_JSON="null" CACHE_JSON="null"
SELF_UPDATED="false" INSTALL_DEFERRED="false" STOPPED_BEFORE_INSTALL="false"
REFRESH_RC="null" REFRESH_OUT="" REFRESH_PREDICTED="false" REFRESH_FAILED=0
CATALOG_LAST_UPDATED="" PROJECT_ROOT_JSON="null"

reset_marketplace_state() {
  MP_ERRORS=()
  IR_UPDATED=() IR_FAILED=() IR_WOULD=()
  US_UPDATED=() US_FAILED=() US_WOULD=()
  WITHHELD=() DOWNGRADED=() INSTALLED_ROWS=() ENABLED_ROWS=() PROJECT_ROWS=()
  INSTALL_GAP="[]" ENABLE_GAP="[]" NORMALIZE_JSON="null" CACHE_JSON="null"
  SELF_UPDATED="false" INSTALL_DEFERRED="false" STOPPED_BEFORE_INSTALL="false"
  REFRESH_RC="null" REFRESH_OUT="" REFRESH_PREDICTED="false" REFRESH_FAILED=0
  CATALOG_LAST_UPDATED="" PROJECT_ROOT_JSON="null"
}

# --- the per-marketplace loop body (Steps 2-5b, plus Step 1's own refresh) -------
run_marketplace() {
  local mp="$1"
  reset_marketplace_state
  : >"$RUN_DIR/moves.$mp.tsv"

  local rc dg_rc id scope old new row text out

  local pre_refresh="$RUN_DIR/pre-refresh.$mp.json"

  # ---- Step 1 — marketplace refresh -------------------------------------------
  # The snapshot is a READ and both actions take it: it is the earliest link in the
  # catalog regression check's chain, and an action that skips it starts that check
  # at `pre` and loses the interval that isolates the refresh point.
  if ((ONLY_INSTALL_MODE == 0)); then
    if [[ ! -f "$pre_refresh" ]]; then
      "$FLEET_STATE" --marketplace "$mp" >"$pre_refresh" 2>"$RUN_DIR/.fs-err"
      rc=$?
      if ((rc != 0)); then
        text=$(<"$RUN_DIR/.fs-err")
        mp_error "pre-refresh fleet-state read failed (exit $rc): ${text//$'\r'/}"
        emit_marketplace_block "$mp"
        return 0
      fi
    fi
    jq_to CATALOG_LAST_UPDATED -r '.marketplace.lastUpdated // ""' "$pre_refresh"

    if [[ "$MODE" == "audit" ]]; then
      predict_cli "claude plugin marketplace update $mp"
      REFRESH_PREDICTED="true"
      REFRESH_RC="null"
      trunc REFRESH_OUT "$CLI_OUT"
    else
      run_cli "claude plugin marketplace update $mp" plugin marketplace update "$mp"
      REFRESH_RC="$CLI_RC"
      trunc REFRESH_OUT "$CLI_OUT"
      if ((CLI_RC != 0)); then
        REFRESH_FAILED=1
        mp_error "marketplace refresh failed (exit $CLI_RC); catalog may be stale, install/enable maintenance deferred"
      fi
    fi
  else
    [[ -f "$pre_refresh" ]] && jq_to CATALOG_LAST_UPDATED -r '.marketplace.lastUpdated // ""' "$pre_refresh"
  fi

  # ---- Step 2 — in-repo update (the primary value path) ------------------------
  if ((ONLY_INSTALL_MODE == 0)); then
    "$FLEET_STATE" --marketplace "$mp" >"$RUN_DIR/pre.$mp.json" 2>"$RUN_DIR/.fs-err"
    rc=$?
    if ((rc != 0)); then
      text=$(<"$RUN_DIR/.fs-err")
      mp_error "pre fleet-state read failed (exit $rc): ${text//$'\r'/}"
      emit_marketplace_block "$mp"
      return 0
    fi
    jq_to PROJECT_ROOT_JSON -c '.project_root' "$RUN_DIR/pre.$mp.json"
    [[ -n "$PROJECT_ROOT_JSON" ]] || PROJECT_ROOT_JSON="null"

    project_ids update-candidates-project "$RUN_DIR/pre.$mp.json" "$RUN_DIR/ids.pre.$mp.txt"
    rc=$?
    if ((rc != 0)); then
      # exit 2 with empty output is a FAILED projection, never "nothing in-repo".
      mp_error "in-repo projection failed (exit $rc), step not run: $(proj_err)"
    else
      while IFS=$'\t' read -r id scope; do
        id="${id//$'\r'/}"
        scope="${scope//$'\r'/}"
        [[ -n "$id" ]] || continue
        version_at old "$RUN_DIR/pre.$mp.json" "$id" "$scope"
        if [[ "$MODE" == "audit" ]]; then
          predict_cli "claude plugin update $id -s $scope"
          IR_WOULD+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg old "$old" \
            '{id: $id, scope: $sc, installed: $old}')")
          continue
        fi
        run_cli "claude plugin update $id -s $scope" plugin update "$id" -s "$scope"
        if ((CLI_RC != 0)); then
          trunc out "$CLI_OUT"
          IR_FAILED+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --argjson rc "$CLI_RC" \
            --arg out "$out" '{id: $id, scope: $sc, rc: $rc, output: $out}')")
          continue
        fi
        cli_reported_version new "$CLI_OUT"
        printf 'in_repo\t%s\t%s\t%s\t%s\n' "$id" "$scope" "$old" "$new" >>"$RUN_DIR/moves.$mp.tsv"
      done <"$RUN_DIR/ids.pre.$mp.txt"
    fi
  fi

  # ---- Step 3 — user-scope update sweep ----------------------------------------
  if ((ONLY_INSTALL_MODE == 0)); then
    "$FLEET_STATE" --marketplace "$mp" >"$RUN_DIR/mid.$mp.json" 2>"$RUN_DIR/.fs-err"
    rc=$?
    if ((rc != 0)); then
      text=$(<"$RUN_DIR/.fs-err")
      mp_error "mid fleet-state read failed (exit $rc): ${text//$'\r'/}"
      emit_marketplace_block "$mp"
      return 0
    fi

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
        run_cli "claude plugin update $id -s user" plugin update "$id" -s user
        if ((CLI_RC != 0)); then
          trunc out "$CLI_OUT"
          US_FAILED+=("$(jq -c -n --arg id "$id" --argjson rc "$CLI_RC" --arg out "$out" \
            '{id: $id, rc: $rc, output: $out}')")
          continue
        fi
        cli_reported_version new "$CLI_OUT"
        printf 'user_sweep\t%s\t%s\t%s\t%s\n' "$id" user "$old" "$new" >>"$RUN_DIR/moves.$mp.tsv"
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
        run_cli "claude plugin update $id -s $scope   # downgrade $old -> $new" \
          plugin update "$id" -s "$scope"
        if ((CLI_RC != 0)); then
          trunc out "$CLI_OUT"
          US_FAILED+=("$(jq -c -n --arg id "$id" --argjson rc "$CLI_RC" --arg out "$out" \
            '{id: $id, rc: $rc, output: $out}')")
          continue
        fi
        DOWNGRADED+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg o "$old" --arg n "$new" \
          '{id: $id, scope: $sc, old: $o, new: $n}')")
      else
        WITHHELD+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --arg o "$old" --arg n "$new" \
          '{id: $id, scope: $sc, installed: $o, catalog: $n}')")
      fi
    done <"$RUN_DIR/downgrades.$mp.txt"
  fi

  # ---- Steps 4 and 5 — install and enable, gated on the FRESH pre-install read ---
  "$FLEET_STATE" --marketplace "$mp" >"$RUN_DIR/pre-install.$mp.json" 2>"$RUN_DIR/.fs-err"
  rc=$?
  if ((rc != 0)); then
    text=$(<"$RUN_DIR/.fs-err")
    mp_error "pre-install fleet-state read failed (exit $rc): ${text//$'\r'/}"
  else
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

  local gap_count enable_gap_count
  jq_to gap_count -r 'length' <<<"$INSTALL_GAP"
  jq_to enable_gap_count -r 'length' <<<"$ENABLE_GAP"

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
    run_install_step "$mp" "$gap_count"
    run_enable_step "$mp"
  fi

  # ---- Step 5b — cache content check, exactly once per marketplace ---------------
  cache_content_block "$mp"

  # ---- post re-read, then the report inputs Step 6 reads back --------------------
  "$FLEET_STATE" --marketplace "$mp" >"$RUN_DIR/post.$mp.json" 2>"$RUN_DIR/.fs-err"
  rc=$?
  if ((rc != 0)); then
    text=$(<"$RUN_DIR/.fs-err")
    mp_error "post fleet-state read failed (exit $rc): ${text//$'\r'/}"
  fi

  finalize_moves "$mp"

  local own
  own=$(own_plugin_name)
  if [[ -n "$own" ]]; then
    for row in ${US_UPDATED[@]+"${US_UPDATED[@]}"} ${DOWNGRADED[@]+"${DOWNGRADED[@]}"}; do
      case "$row" in
      *"\"id\":\"$own@"*) SELF_UPDATED="true" ;;
      esac
    done
  fi

  emit_marketplace_block "$mp"
}

# --- Step 4 — install new catalog plugins, per the caller's rendered policy -------
run_install_step() {
  local mp="$1" gap_count="$2"
  local id out installed_any=0 wanted=""

  if ((ONLY_INSTALL_MODE == 1)); then
    # The narrow re-entry installs exactly the ids the caller's prompt returned,
    # scoped to this marketplace by the id's own `@<marketplace>` suffix.
    wanted=$(printf '%s' "${ONLY_INSTALL//,/ }")
    for id in $wanted; do
      [[ "$id" == *"@$mp" ]] || continue
      run_cli "claude plugin install $id -s user" plugin install "$id" -s user
      trunc out "$CLI_OUT"
      INSTALLED_ROWS+=("$(jq -c -n --arg id "$id" --argjson rc "$CLI_RC" --arg out "$out" \
        '{id: $id, rc: $rc, output: $out}')")
      ((CLI_RC == 0)) && installed_any=1
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
      run_cli "claude plugin install $id -s user" plugin install "$id" -s user
      trunc out "$CLI_OUT"
      INSTALLED_ROWS+=("$(jq -c -n --arg id "$id" --argjson rc "$CLI_RC" --arg out "$out" \
        '{id: $id, rc: $rc, output: $out}')")
      ((CLI_RC == 0)) && installed_any=1
    done <"$RUN_DIR/ids.pre-install.$mp.txt"
  fi

  # The reorder heals the unsorted tail an install just created, so it runs only
  # when this step installed something. `audit` predicts it with `--check`, which
  # writes nothing.
  ((installed_any == 1)) || return 0
  local nrc=0 nout=""
  if [[ "$MODE" == "audit" ]]; then
    nout=$("$NORMALIZE" --check 2>&1) || nrc=$?
  else
    nout=$("$NORMALIZE" 2>&1) || nrc=$?
  fi
  trunc nout "${nout//$'\r'/}" 200
  jq_to NORMALIZE_JSON -c -n --argjson rc "$nrc" --arg out "$nout" --arg mode "$MODE" \
    '{rc: $rc, output: $out, checked_only: ($mode == "audit")}'
}

# --- Step 5 — enabledPlugins completeness ----------------------------------------
# Its own live re-read: Step 4 mutated in between (it installs, and it normalizes the
# user-scope map), so the pre-install report no longer describes the state this step
# acts on.
run_enable_step() {
  local mp="$1" rc id row has_user has_local has_project ppath

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
  local id="$1" scope="$2" out
  if [[ "$MODE" == "audit" ]]; then
    predict_cli "claude plugin enable $id -s $scope"
    ENABLED_ROWS+=("$(jq -c -n --arg id "$id" --arg sc "$scope" \
      '{id: $id, scope: $sc, rc: null, predicted: true}')")
    return 0
  fi
  run_cli "claude plugin enable $id -s $scope" plugin enable "$id" -s "$scope"
  trunc out "$CLI_OUT"
  ENABLED_ROWS+=("$(jq -c -n --arg id "$id" --arg sc "$scope" --argjson rc "$CLI_RC" --arg out "$out" \
    '{id: $id, scope: $sc, rc: $rc, output: $out, predicted: false}')")
}

# --- Step 5b — cache content check ------------------------------------------------
# ONE call per marketplace. The stale ids come from the JSON this call already
# wrote, extracted CR-safe; the `--ids` form is reached only when the JSON could not
# be produced, never in addition to it.
cache_content_block() {
  local mp="$1"
  local report="$RUN_DIR/cache-content.$mp.json" rc=0 ids

  if [[ ! -f "$report" ]]; then
    "$CACHE_CHECK" --marketplace "$mp" >"$report" 2>"$RUN_DIR/.cc-err"
    rc=$?
  fi

  if ((rc == 0)) && jq -e 'has("checked")' "$report" >/dev/null 2>&1; then
    jq_to CACHE_JSON -c '{checked, match, stale_content, unverifiable,
      skipped_absent_project_paths,
      stale_ids: [.installs[]? | select(.verdict == "stale-content") | .id],
      source: "json"}' "$report"
    return 0
  fi

  # The JSON is unusable, so the id list is projected with the checker's own `--ids`
  # form rather than left unknown.
  "$CACHE_CHECK" --marketplace "$mp" --ids >"$RUN_DIR/cache-stale-ids.$mp.txt" 2>>"$RUN_DIR/.cc-err"
  rc=$?
  json_lines ids "$RUN_DIR/cache-stale-ids.$mp.txt"
  mp_error "cache-content JSON unusable; stale ids taken from the checker's --ids form (exit $rc)"
  jq_to CACHE_JSON -c -n --argjson ids "$ids" \
    '{checked: null, match: null, stale_content: ($ids | length), unverifiable: null,
      skipped_absent_project_paths: null, stale_ids: $ids, source: "ids-fallback"}'
}

# --- version capture --------------------------------------------------------------
# `<old>` is the pre-mutation snapshot's version by construction; `<new>` is the
# CLI's own line when it named one (source 2), else the post-sweep read (source 3).
# When the CLI reported an update and the post version is unchanged, the pair keeps
# `unknown` rather than rendering `<old> → <old>`, which would claim nothing changed
# for a plugin that did.
finalize_moves() {
  local mp="$1"
  local kind id scope old new dir row post="$RUN_DIR/post.$mp.json"
  [[ -f "$RUN_DIR/moves.$mp.tsv" ]] || return 0
  while IFS=$'\t' read -r kind id scope old new; do
    [[ -n "$id" ]] || continue
    if [[ -z "$new" && -f "$post" ]]; then
      version_at new "$post" "$id" "$scope"
      [[ "$new" == "$old" ]] && new=""
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

# --- one marketplace block --------------------------------------------------------
emit_marketplace_block() {
  local mp="$1"
  local ir_u ir_f ir_w us_u us_f us_w wh dg inst en pr errs
  local reg_interval reg_rows div block

  json_array_of ir_u ${IR_UPDATED[@]+"${IR_UPDATED[@]}"}
  json_array_of ir_f ${IR_FAILED[@]+"${IR_FAILED[@]}"}
  json_array_of ir_w ${IR_WOULD[@]+"${IR_WOULD[@]}"}
  json_array_of us_u ${US_UPDATED[@]+"${US_UPDATED[@]}"}
  json_array_of us_f ${US_FAILED[@]+"${US_FAILED[@]}"}
  json_array_of us_w ${US_WOULD[@]+"${US_WOULD[@]}"}
  json_array_of wh ${WITHHELD[@]+"${WITHHELD[@]}"}
  json_array_of dg ${DOWNGRADED[@]+"${DOWNGRADED[@]}"}
  json_array_of inst ${INSTALLED_ROWS[@]+"${INSTALLED_ROWS[@]}"}
  json_array_of en ${ENABLED_ROWS[@]+"${ENABLED_ROWS[@]}"}
  json_array_of pr ${PROJECT_ROWS[@]+"${PROJECT_ROWS[@]}"}

  if ((${#MP_ERRORS[@]} == 0)); then
    errs='[]'
  else
    jq_to errs -c -R -s 'split("\n") | map(select(length > 0))' <<<"$(printf '%s\n' "${MP_ERRORS[@]}")"
  fi

  catalog_regression_rows reg_interval reg_rows "$mp"
  divergence_block div "$mp"

  jq_to block -c -n \
    --arg name "$mp" \
    --arg lastUpdated "$CATALOG_LAST_UPDATED" \
    --argjson refresh_rc "${REFRESH_RC:-null}" \
    --arg refresh_out "$REFRESH_OUT" \
    --argjson refresh_predicted "$REFRESH_PREDICTED" \
    --argjson project_root "$PROJECT_ROOT_JSON" \
    --argjson ir_u "$ir_u" --argjson ir_f "$ir_f" --argjson ir_w "$ir_w" \
    --argjson us_u "$us_u" --argjson us_f "$us_f" --argjson us_w "$us_w" \
    --argjson wh "$wh" --argjson dg "$dg" \
    --argjson install_gap "$INSTALL_GAP" --argjson inst "$inst" \
    --argjson enable_gap "$ENABLE_GAP" --argjson en "$en" --argjson pr "$pr" \
    --argjson deferred "$INSTALL_DEFERRED" --argjson stopped "$STOPPED_BEFORE_INSTALL" \
    --argjson normalize "$NORMALIZE_JSON" --argjson cache "$CACHE_JSON" \
    --arg reg_interval "$reg_interval" --argjson reg_rows "$reg_rows" \
    --argjson div "$div" --argjson self_updated "$SELF_UPDATED" \
    --argjson errors "$errs" '
    {name: $name,
     catalog_last_updated: (if $lastUpdated == "" then null else $lastUpdated end),
     refresh: {rc: $refresh_rc, output: $refresh_out, predicted: $refresh_predicted},
     project_root: $project_root,
     in_repo: {updated: $ir_u, failed: $ir_f, would_update: $ir_w},
     user_sweep: {updated: $us_u, failed: $us_f, would_update: $us_w,
                  withheld_downgrades: $wh},
     downgraded: $dg,
     install_gap: $install_gap,
     installed: $inst,
     install_enable_deferred: $deferred,
     stopped_before_install: $stopped,
     enable_gap: $enable_gap,
     enabled: $en,
     project_enable_rows: $pr,
     normalize: $normalize,
     cache_content: $cache,
     catalog_regression: (if $reg_interval == "" then null
                          else {interval: $reg_interval, rows: $reg_rows} end),
     divergences: $div,
     self_updated: $self_updated,
     errors: $errors}'
  printf '%s\n' "$block" >>"$RUN_DIR/.blocks.jsonl"
}

# --- main --------------------------------------------------------------------------
setup_run_dir
: >"$RUN_DIR/.blocks.jsonl"
[[ -f "$JOURNAL_LOG" ]] || : >"$JOURNAL_LOG"

MPS=()
if ((ALL == 1)); then
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
  # pre-refresh snapshot, so it is saved under the resolved name rather than repeated.
  if ! "$FLEET_STATE" >"$RUN_DIR/.default.json" 2>"$RUN_DIR/.fs-err"; then
    echo "ERROR: could not resolve the default marketplace" >&2
    cat "$RUN_DIR/.fs-err" >&2
    exit 2
  fi
  jq_to DEFAULT_MP -r '.marketplace.name // ""' "$RUN_DIR/.default.json"
  if [[ -z "$DEFAULT_MP" ]]; then
    echo "ERROR: the default marketplace report carries no marketplace name" >&2
    exit 2
  fi
  MPS=("$DEFAULT_MP")
  [[ -f "$RUN_DIR/pre-refresh.$DEFAULT_MP.json" ]] ||
    mv "$RUN_DIR/.default.json" "$RUN_DIR/pre-refresh.$DEFAULT_MP.json"
fi

if ((${#MPS[@]} == 0)); then
  run_error "no marketplace resolved for this run"
fi

for mp in ${MPS[@]+"${MPS[@]}"}; do
  run_marketplace "$mp"
done

BLOCKS='[]'
[[ -s "$RUN_DIR/.blocks.jsonl" ]] && jq_to BLOCKS -c -s '.' "$RUN_DIR/.blocks.jsonl"

if ((${#RUN_ERRORS[@]} == 0)); then
  RUN_ERRS='[]'
else
  jq_to RUN_ERRS -c -R -s 'split("\n") | map(select(length > 0))' <<<"$(printf '%s\n' "${RUN_ERRORS[@]}")"
fi

DIGEST=""
ALLOW_DOWNGRADE_JSON="false"
((ALLOW_DOWNGRADE == 1)) && ALLOW_DOWNGRADE_JSON="true"

jq_to DIGEST -c -n \
  --arg run_dir "$RUN_DIR" \
  --arg mode "$MODE" \
  --argjson allow_downgrade "$ALLOW_DOWNGRADE_JSON" \
  --arg install_new "$INSTALL_NEW" \
  --arg install_new_invalid "$INSTALL_NEW_INVALID" \
  --argjson marketplaces "$BLOCKS" \
  --argjson errors "$RUN_ERRS" '
  {run_dir: $run_dir, mode: $mode, allow_downgrade: $allow_downgrade,
   install_new: $install_new,
   install_new_invalid: (if $install_new_invalid == "" then null else $install_new_invalid end),
   marketplaces: $marketplaces, errors: $errors}'

printf '%s\n' "$DIGEST" >"$RUN_DIR/digest.json"
printf '%s\n' "$DIGEST"
exit 0
