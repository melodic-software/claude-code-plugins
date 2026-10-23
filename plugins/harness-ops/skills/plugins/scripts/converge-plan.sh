#!/usr/bin/env bash
# Read-only planning pass for `converge`: turns a fleet-state.sh report into one
# row per lagging (projectPath, id) pin, grouped by path, each carrying the
# strategy, the exact command, and a class that says whether converge can act.
# It NEVER runs a `claude plugin` command and never writes a settings file; the
# model presents the plan and runs only what the user confirms, one batch per
# path (context/converge.md Step 3).
#
# Usage:
#   converge-plan.sh [--marketplace <name>]
#   converge-plan.sh --from <report.json> [--marketplace <name>]
#
# Without --from, runs the sibling fleet-state.sh (default marketplace, or the
# named one). With --from, reads a single-marketplace report it already emitted.
#
# Output (stdout): one JSON object.
#   {marketplace, counts, groups}
#   counts   {rows, paths, actionable, worktree, "blocked-absent", "blocked-home",
#             "blocked-catalog"}
#   groups   [{projectPath, rows: [...]}] sorted by path; projectPath null holds
#            the user-scope rows (no path, no `cd`)
#   rows     [{id, scope, version, highest, class, strategy, command, default,
#              warning, alternative, why}]
#   alternative  {strategy, command, warning} or null: the non-default strategy an
#            actionable row also offers. A committed-enable `update` row offers
#            uninstall with the committed-entry warning; an `uninstall` row offers
#            update unless the catalog reads below the highest version.
#
# Only a record BEHIND the highest version its id holds gets a row (divergences
# with versionsMatch false; a record whose version does not parse as
# major.minor.patch is left out, the same fail-open the sibling scripts use).
# One row per (projectPath, id, scope): an id holding both a project and a local
# record in one path gets two rows, since each takes its own `-s` flag.
#
# Class, first match wins:
#   blocked-home     projectPathIsHome is true: its .claude/settings.json is USER
#                    settings, so a project-scope command would change user scope.
#                    No command.
#   blocked-absent   projectPathPresent is not true (or no projectPath): the `cd`
#                    cannot run. No command. Never "dead": it may be an unmounted
#                    volume.
#   worktree         the path is a linked worktree (linkedWorktree true). `update`
#                    is not offered there; uninstall is offered only when user
#                    scope holds the highest version, otherwise strategy is `none`.
#   blocked-catalog  the update strategy is chosen and the catalog reads below the
#                    highest installed version, so update would roll back. No
#                    command; uninstall is not offered as a way around it.
#   actionable       everything else; `command` is runnable.
#
# Strategy follows context/converge.md Step 2: user scope holds the highest
# version -> `uninstall -s <scope> --keep-data`, except a `project` row whose
# tracked .claude/settings.json holds an enabledPlugins entry for the id (any
# value), which takes `update`; otherwise `update` for the row's scope. A
# committed-enable check that cannot be read counts as a committed enable. A
# worktree row with a committed enable keeps uninstall as `default: false` with a
# `warning`, since neither strategy is the default there.
#
# Committed-enable read: for each distinct present path that needs it, one
# `git ls-files --error-unmatch` and, when tracked, one jq read of that file's
# enabledPlugins keys. This script is that sanctioned read; nothing is written.
#
# Exit codes:
#   0  plan emitted (an empty plan is success)
#   1  a marketplace run could not be resolved (fleet-state.sh exit 1, or an error
#      block in the report)
#   2  usage error, jq missing, or an unusable report

set -uo pipefail

unset GIT_DIR GIT_WORK_TREE

script_src="${BASH_SOURCE[0]}"
case "$script_src" in
*/*) script_src_dir="${script_src%/*}" ;;
*) script_src_dir="." ;;
esac

JQ_CAPTURE="$script_src_dir/jq-capture.sh"
if [[ -f "$JQ_CAPTURE" ]]; then
  # shellcheck source=jq-capture.sh
  builtin source "$JQ_CAPTURE"
else
  echo "ERROR: jq-capture.sh not found at $JQ_CAPTURE" >&2
  exit 2
fi

usage() {
  local text
  IFS= read -r -d '' text <<'EOF' || true
converge-plan.sh: read-only converge plan, one row per lagging (projectPath, id), as JSON.

Usage:
  converge-plan.sh [--marketplace <name>]
  converge-plan.sh --from <report.json> [--marketplace <name>]

Runs fleet-state.sh unless --from names a saved single-marketplace report.
Classes: actionable, worktree, blocked-absent, blocked-home, blocked-catalog.

Exit: 0 plan emitted; 1 marketplace could not be resolved; 2 usage error, jq
missing, or an unusable report.

The output shape and the rules are in the header comment of this script.
EOF
  printf '%s\n' "$text"
}

TARGET=""
FROM_REPORT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --marketplace)
    TARGET="${2:-}"
    if [[ -z "$TARGET" ]]; then
      echo "ERROR: --marketplace requires a name" >&2
      exit 2
    fi
    shift 2
    ;;
  --from)
    FROM_REPORT="${2:-}"
    if [[ -z "$FROM_REPORT" ]]; then
      echo "ERROR: --from requires a report path" >&2
      exit 2
    fi
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown argument: $1 (see --help)" >&2
    exit 2
    ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required (install with: winget install jqlang.jq | apt install jq | brew install jq)" >&2
  exit 2
fi

report=""
if [[ -n "$FROM_REPORT" ]]; then
  if [[ ! -f "$FROM_REPORT" ]]; then
    echo "ERROR: --from report not found: $FROM_REPORT" >&2
    exit 2
  fi
  report=$(<"$FROM_REPORT")
else
  fs_args=()
  [[ -n "$TARGET" ]] && fs_args+=(--marketplace "$TARGET")
  fs_rc=0
  report=$("$script_src_dir/fleet-state.sh" ${fs_args[@]+"${fs_args[@]}"}) || fs_rc=$?
  if ((fs_rc != 0)); then
    echo "ERROR: fleet-state.sh failed (exit $fs_rc)" >&2
    exit $((fs_rc == 1 ? 1 : 2))
  fi
fi

# Shape check: a single-marketplace report with a divergences array. An --all
# envelope or an arbitrary object is refused by name rather than planned as empty.
shape=""
# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
if ! jq_to shape -r '
      if type != "object" then "err:not a JSON object"
      elif has("marketplaces") then "err:this is an --all envelope, not a single-marketplace report"
      elif (.marketplace | type) != "object" then "err:missing field .marketplace"
      elif (.marketplace.error // null) != null then "fail:" + (.marketplace.error | tostring)
      elif (.marketplace.name | type) != "string" then "err:missing or wrong-typed field .marketplace.name"
      elif (.divergences | type) != "array" then "err:missing or wrong-typed field .divergences (expected an array)"
      elif (.catalog_versions | type) != "object" then "err:missing or wrong-typed field .catalog_versions (expected an object)"
      else "ok:" + .marketplace.name end' <<<"$report" 2>/dev/null; then
  shape="err:not valid JSON"
fi
case "$shape" in
ok:*) ;;
fail:*)
  echo "ERROR: marketplace could not be resolved: ${shape#fail:}" >&2
  exit 1
  ;;
*)
  echo "ERROR: not a usable fleet-state report: ${shape#err:}" >&2
  exit 2
  ;;
esac
if [[ -n "$TARGET" && "$TARGET" != "${shape#ok:}" ]]; then
  echo "ERROR: report is for marketplace '${shape#ok:}', not '$TARGET'" >&2
  exit 2
fi

# The row program, shared by the path-listing pass and the plan pass so the two
# cannot disagree about which rows need the committed-enable read. `$committed`
# maps a path to {all: <bool>, ids: [...]}; `all` is true when the check could
# not be read, which counts as a committed enable.
# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
ROWS_PROGRAM='
  def triple:
    if type == "string" then
      ((capture("^v?(?<maj>[0-9]+)[.](?<min>[0-9]+)[.](?<pat>[0-9]+)") // null)
       | if . == null then null else [.maj, .min, .pat] | map(tonumber) end)
    else null end;
  def shq: ([39] | implode) as $q | $q + gsub($q; $q + "\\" + $q + $q) + $q;
  def lagging:
    .catalog_versions as $cv
    | .divergences[]? | select(.versionsMatch == false) | . as $d
    | ([$d.scopes[] | .version | triple | select(. != null)] | max) as $hi
    | select($hi != null)
    | ([$d.scopes[] | select((.version | triple) == $hi)][0].version) as $hiv
    | ([$d.scopes[] | select(.scope == "user" and (.version | triple) == $hi)] | length > 0) as $user_holds
    | ($cv[$d.id] | triple) as $cat
    | $d.scopes[]
    | select((.version | triple) as $t | $t != null and $t < $hi)
    | {id: $d.id, scope, version, highest: $hiv,
       projectPath: (.projectPath // null),
       present: (.projectPathPresent == true),
       isHome: (.projectPathIsHome == true),
       worktree: (.linkedWorktree == true),
       userHolds: $user_holds,
       catalogLower: ($cat != null and $cat < $hi)}
    | . + {needsCheck: (.scope == "project" and .userHolds and .present and (.isHome | not))};
'

# Pass 1: the distinct paths whose tracked settings must be read.
paths_needed=""
# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
if ! jq_to paths_needed -r "$ROWS_PROGRAM"'
  [lagging | select(.needsCheck) | .projectPath] | unique | .[]' <<<"$report"; then
  echo "ERROR: could not plan the report" >&2
  exit 2
fi

# Committed-enable state per path, fail closed: `all` true means "treat every id
# as a committed enable". Exit 1 from ls-files is "not tracked" (untracked or
# missing file); any other failure decides nothing, so it stays closed.
committed_lines=""
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  state='{"all":true,"ids":[]}'
  pfs="${p//\\//}"
  ls_rc=0
  git -C "$pfs" ls-files --error-unmatch .claude/settings.json >/dev/null 2>&1 || ls_rc=$?
  if ((ls_rc == 1)); then
    state='{"all":false,"ids":[]}'
  elif ((ls_rc == 0)); then
    keys=""
    # shellcheck disable=SC2016  # a jq program
    if jq_to keys -c '(.enabledPlugins // {}) | if type == "object" then keys else error("shape") end' \
      "$pfs/.claude/settings.json" 2>/dev/null; then
      state="{\"all\":false,\"ids\":$keys}"
    fi
  fi
  line=""
  # shellcheck disable=SC2016  # a jq program
  jq_to line -cn --arg k "$p" --argjson v "$state" '{key: $k, value: $v}'
  committed_lines+="$line"$'\n'
done <<<"$paths_needed"

committed="{}"
jq_to committed -s 'from_entries' <<<"$committed_lines" || committed="{}"
[[ -n "$committed" ]] || committed="{}"

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
PLAN_PROGRAM="$ROWS_PROGRAM"'
  def classify:
    . as $r
    | (if $r.scope == "project" and $r.needsCheck
       then (($committed[$r.projectPath] // {all: true, ids: []}) as $c
             | $c.all or (($c.ids | index($r.id)) != null))
       else false end) as $committed_enable
    | (if $r.worktree then (if $r.userHolds then "uninstall" else "none" end)
       elif $r.scope == "user" then "update"
       elif $r.userHolds and ($r.scope == "local" or ($committed_enable | not)) then "uninstall"
       else "update" end) as $strategy
    | (if $r.isHome then "blocked-home"
       elif ($r.projectPath == null and $r.scope != "user") or ($r.scope != "user" and ($r.present | not)) then "blocked-absent"
       elif $r.worktree then "worktree"
       elif $strategy == "update" and $r.catalogLower then "blocked-catalog"
       else "actionable" end) as $class
    | (if $r.scope == "user" or ($r.projectPath | type) != "string" then "" else "(cd " + ($r.projectPath | shq) + " && " end) as $pre
    | (if $r.scope == "user" or ($r.projectPath | type) != "string" then "" else ")" end) as $post
    | def cmd($s):
        if $s == "uninstall" then $pre + "claude plugin uninstall " + $r.id + " -s " + $r.scope + " --keep-data" + $post
        elif $s == "update" then $pre + "claude plugin update " + $r.id + " -s " + $r.scope + $post
        else null end;
      cmd($strategy) as $cmd
    | (if $class != "actionable" then null
       elif $strategy == "update" and $committed_enable
       then {strategy: "uninstall", command: cmd("uninstall"), warning: "removes a committed enabledPlugins entry"}
       elif $strategy == "uninstall" and ($r.catalogLower | not)
       then {strategy: "update", command: cmd("update"), warning: null}
       else null end) as $alt
    | {id: $r.id, scope: $r.scope, version: $r.version, highest: $r.highest,
       class: $class, strategy: $strategy,
       command: (if $class == "actionable" or ($class == "worktree" and $strategy == "uninstall") then $cmd else null end),
       default: ($class == "actionable" or ($class == "worktree" and ($committed_enable | not) and $strategy == "uninstall")),
       warning: (if $strategy == "uninstall" and $committed_enable and $r.scope == "project"
                 then "removes a committed enabledPlugins entry" else null end),
       alternative: $alt,
       why: (if $class == "blocked-home" then "projectPath is a user home directory; its .claude/settings.json is user settings"
             elif $class == "blocked-absent" then "projectPath is not present on this machine; the cd cannot run"
             elif $class == "worktree" and $strategy == "none" then "linked worktree: update is not offered, and no uninstall would bring it current"
             elif $class == "worktree" then "linked worktree: update is not offered; uninstall clears the record"
             elif $class == "blocked-catalog" then "the catalog reads below the highest installed version; update would roll back"
             elif $strategy == "uninstall" then "user scope holds the highest version and the id is not enabled in tracked project settings"
             elif $r.scope == "user" or ($r.userHolds | not) then "a project or local scope holds the highest version"
             else "the tracked project settings enable the id, and uninstall would remove it" end),
       projectPath: $r.projectPath};
  [lagging | classify] as $rows
  | {marketplace: .marketplace.name,
     counts: ({rows: ($rows | length),
               paths: ([$rows[] | select(.projectPath != null) | .projectPath] | unique | length)}
              + ([$rows[] | .class] | group_by(.) | map({key: .[0], value: length}) | from_entries
                 | {actionable: (.actionable // 0), worktree: (.worktree // 0),
                    "blocked-absent": (.["blocked-absent"] // 0),
                    "blocked-home": (.["blocked-home"] // 0),
                    "blocked-catalog": (.["blocked-catalog"] // 0)})),
     groups: ($rows | sort_by([.projectPath // "", .id, .scope]) | group_by(.projectPath)
              | map({projectPath: .[0].projectPath, rows: map(del(.projectPath))}))}'

plan=""
if ! jq_to plan -c --argjson committed "$committed" "$PLAN_PROGRAM" <<<"$report"; then
  echo "ERROR: could not plan the report" >&2
  exit 2
fi
printf '%s\n' "$plan"
