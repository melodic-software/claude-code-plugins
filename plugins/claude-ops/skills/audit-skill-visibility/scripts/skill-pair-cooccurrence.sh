#!/usr/bin/env bash
# skill-pair-cooccurrence.sh — does skill B get invoked where skill A ran?
#
# Reads a `skill-usage.jsonl` store (SkillUse events, written by claude-ops'
# skill-usage-audit.sh and the UserPromptExpansion row of audit-event-emitter.sh)
# and reports, for an
# ordered pair CALLER,CALLEE: across the groups where CALLER fired, in what
# fraction did CALLEE also fire, and in which order.
#
# WHY THIS IS A PROXY, NOT A MEASUREMENT — stated here and re-stated in every
# report this script prints, because the number is misleading without it:
#
#   The SkillUse record carries no caller attribution. A PostToolUse hook on the
#   Skill tool receives `tool_name`, `tool_input`, and `tool_response`; nothing
#   in that payload names the skill whose instructions caused the call. So this
#   script cannot observe "CALLEE was invoked BY CALLER". It observes only that
#   both fired in the same (project_id, branch) group, and orders them by
#   timestamp. Co-occurrence is consistent with causation and does not
#   demonstrate it — a CALLEE the user invoked by hand counts identically to one
#   CALLER's instructions produced.
#
#   The group key is a proxy for "session" too. The record has no session id;
#   (project_id, branch) is the nearest available partition, so two sessions on
#   one branch collapse into one group and one session spanning a branch switch
#   splits into two.
#
# Inflating this proxy into a measurement is the specific failure mode this
# script is written to prevent, which is why a thin store produces WITHHELD
# rather than a small number: a store younger than the exposure floor cannot
# distinguish "CALLEE never fired" from "nothing was observed yet".
#
# WHERE THE STORE IS — the hooks decide, this script asks them:
#
#   The writers select the store through claude_ops::resolve_skill_usage_dir
#   in ../../../hooks/claude-ops-paths.sh (skill_usage_scope: repo, user or
#   data-dir; skill_usage_dir under the scope root). Without --store this script
#   sources that same resolver and feeds it the same options, so the file it
#   opens is the file the hooks wrote for every scope. A restated default here
#   would be one branch of that policy, correct only until the policy moved.
#   The hooks read their options from CLAUDE_PLUGIN_OPTION_* in the hook
#   environment; a skill subprocess inherits none of those, so the skill body
#   passes the rendered ${user_config.*} values through --scope / --dir. The
#   data-dir root arrives the same way, through --data-root: a skill
#   subprocess was observed carrying an UNRELATED plugin's CLAUDE_PLUGIN_DATA
#   (docs/conventions/plugin-data-report-keying/README.md rule 2), so this
#   script never reads that variable and the sibling pruner
#   (skills/observability/scripts/clean.sh) refuses to either.
#
# Exit:
#   0  a reading was produced — a VERDICT or an honest WITHHELD — or, with
#      --print-store, the resolved store path was printed
#   2  the store is missing, unreadable, or its destination cannot be resolved
#   3  invoked with bad arguments
set -uo pipefail

EX_OK=0
EX_NO_STORE=2
EX_USAGE=3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The plugin is cache-isolated and the hooks ship inside it, so the resolver is
# reachable by a path relative to this script: skills/<skill>/scripts -> hooks.
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

DEFAULT_SCOPE="repo"
DEFAULT_REL_DIR=".claude/observability"
STORE_FILE="skill-usage.jsonl"

# shellcheck disable=SC2016  # the ${...} tokens are literal help text, never expansions
USAGE='usage: skill-pair-cooccurrence.sh [--store PATH | --scope SCOPE --dir REL --data-root PATH]
                                  [--pair CALLER,CALLEE] [--floor-days N]
                                  [--floor-groups N] [--json] [--print-store]

  --store PATH        skill-usage.jsonl to read; an explicit override that skips the
                      scope resolution below
  --scope SCOPE       skill_usage_scope the hooks write under: repo (default), user,
                      or data-dir. Resolved by the resolver the hooks themselves
                      call, so the store read is the store written. Empty or an
                      unrendered ${user_config.*} placeholder reads as the default,
                      as it does in the hooks
  --dir REL           skill_usage_dir: the contained relative directory under the
                      scope root (default .claude/observability; ignored by data-dir)
  --data-root PATH    the plugin data root the hooks write under. REQUIRED by the
                      data-dir scope and ignored by the others; never read from
                      CLAUDE_PLUGIN_DATA, which a skill subprocess was observed
                      carrying for an unrelated plugin
  --print-store       print the resolved store path and exit 0. Hand it to
                      audit_skill_visibility.py --skill-usage so both read ONE store
  --pair A,B          ordered pair. Default: implementation:implement,tdd:principles
  --floor-days N      minimum observed span before any rate is reportable (default 30,
                      matching audit_skill_visibility.py exposure_floor_days)
  --floor-groups N    minimum CALLER-bearing groups (the denominator) before any rate
                      is reportable (default 5)
  --json              emit the report as one JSON object instead of prose'

die_usage() {
  printf 'skill-pair-cooccurrence.sh: %s\n\n%s\n' "$1" "$USAGE" >&2
  exit "$EX_USAGE"
}

# An option the skill body passed through unrendered (`${user_config.x}`) or
# empty is an unset option, and reads as its default.
# shellcheck disable=SC2016  # the literal placeholder text is the thing matched
unset_value() { [[ -z "$1" || "$1" == '${user_config.'* ]]; }

STORE=""
SCOPE=""
REL_DIR=""
DATA_ROOT=""
PRINT_STORE=0
PAIR="implementation:implement,tdd:principles"
FLOOR_DAYS=30
FLOOR_GROUPS=5
AS_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    printf '%s\n' "$USAGE"
    exit "$EX_OK"
    ;;
  --store)
    [[ $# -ge 2 ]] || die_usage "--store needs a value"
    STORE="$2"
    shift 2
    ;;
  --scope)
    [[ $# -ge 2 ]] || die_usage "--scope needs a value"
    SCOPE="$2"
    shift 2
    ;;
  --dir)
    [[ $# -ge 2 ]] || die_usage "--dir needs a value"
    REL_DIR="$2"
    shift 2
    ;;
  --data-root)
    [[ $# -ge 2 ]] || die_usage "--data-root needs a value"
    DATA_ROOT="$2"
    shift 2
    ;;
  --print-store)
    PRINT_STORE=1
    shift
    ;;
  --pair)
    [[ $# -ge 2 ]] || die_usage "--pair needs a value"
    PAIR="$2"
    shift 2
    ;;
  --floor-days)
    [[ $# -ge 2 ]] || die_usage "--floor-days needs a value"
    FLOOR_DAYS="$2"
    shift 2
    ;;
  --floor-groups)
    [[ $# -ge 2 ]] || die_usage "--floor-groups needs a value"
    FLOOR_GROUPS="$2"
    shift 2
    ;;
  --json)
    AS_JSON=1
    shift
    ;;
  *) die_usage "unexpected argument: $1" ;;
  esac
done

[[ "$FLOOR_DAYS" =~ ^[0-9]+$ ]] || die_usage "--floor-days must be a non-negative integer: $FLOOR_DAYS"
[[ "$FLOOR_GROUPS" =~ ^[0-9]+$ ]] || die_usage "--floor-groups must be a non-negative integer: $FLOOR_GROUPS"

# The pair is split on the FIRST comma only. Skill names are `plugin:skill` and
# contain no comma, so a second one means the caller passed something else.
[[ "$PAIR" == *,* ]] || die_usage "--pair must be CALLER,CALLEE: $PAIR"
CALLER="${PAIR%%,*}"
CALLEE="${PAIR#*,}"
[[ -n "$CALLER" && -n "$CALLEE" ]] || die_usage "--pair needs a non-empty name on both sides: $PAIR"
[[ "$CALLEE" != *,* ]] || die_usage "--pair takes exactly two names: $PAIR"

command -v jq >/dev/null 2>&1 || {
  printf 'skill-pair-cooccurrence.sh: jq is required to read the JSONL store\n' >&2
  exit "$EX_NO_STORE"
}

# Resolve the store the way the writers do. Sets STORE and STORE_ORIGIN (the
# phrase the missing-store message names, so a wrong-scope run says which scope
# it looked in). Exits 2 when the destination itself cannot be resolved: that
# is a configuration answer, not "nothing observed".
resolve_store_from_scope() {
  local project_dir store_dir rc
  # shellcheck source=../../../hooks/hook-utils.sh
  . "$PLUGIN_ROOT/hooks/hook-utils.sh"
  # shellcheck source=../../../hooks/claude-ops-paths.sh
  . "$PLUGIN_ROOT/hooks/claude-ops-paths.sh"

  unset_value "$SCOPE" && SCOPE="$DEFAULT_SCOPE"
  unset_value "$REL_DIR" && REL_DIR="$DEFAULT_REL_DIR"
  # DATA_ROOT has no environment fallback on purpose: an inherited
  # CLAUDE_PLUGIN_DATA in a skill subprocess can name another plugin's data
  # directory, so an unpassed --data-root is an unanswerable data-dir scope
  # rather than a guess at one.
  unset_value "$DATA_ROOT" && DATA_ROOT=""
  case "$SCOPE" in
  repo | user | data-dir) ;;
  *)
    # The same fallback the writers apply to an unknown scope, so the reader
    # still lands on the file they wrote.
    printf 'skill-pair-cooccurrence.sh: unknown skill_usage_scope "%s" (valid: repo, user, data-dir); reading the default %s scope, as the hooks write to it\n' \
      "$SCOPE" "$DEFAULT_SCOPE" >&2
    SCOPE="$DEFAULT_SCOPE"
    ;;
  esac

  # Same project root the writers key on: CLAUDE_PROJECT_DIR in a hook or
  # skill subprocess, the working directory otherwise. An unresolved root
  # (not a git checkout) falls back to the hint, as it does for the writers.
  project_dir=$(hook::repo_root "${CLAUDE_PROJECT_DIR:-.}") || true
  store_dir=$(CLAUDE_PLUGIN_DATA="$DATA_ROOT" claude_ops::resolve_skill_usage_dir "$SCOPE" "$project_dir" "$REL_DIR")
  rc=$?
  case "$rc" in
  0) ;;
  1)
    printf 'skill-pair-cooccurrence.sh: the skill-usage destination is invalid for scope "%s": skill_usage_dir "%s" must be a contained relative path (no absolute, drive, UNC, traversal, or escaping symlink path), so the hooks write nothing there either\n' \
      "$SCOPE" "$REL_DIR" >&2
    exit "$EX_NO_STORE"
    ;;
  *)
    if [[ "$SCOPE" == "data-dir" ]]; then
      printf 'skill-pair-cooccurrence.sh: scope "data-dir" needs the plugin data root: pass --data-root <the claude-ops plugin data directory>. It is not taken from CLAUDE_PLUGIN_DATA, which a skill subprocess can carry for an unrelated plugin\n' >&2
    else
      printf 'skill-pair-cooccurrence.sh: scope "%s" needs HOME to name an existing directory\n' "$SCOPE" >&2
    fi
    exit "$EX_NO_STORE"
    ;;
  esac
  STORE="${store_dir}/${STORE_FILE}"
  STORE_ORIGIN="scope ${SCOPE}"
}

if [[ -n "$STORE" ]]; then
  STORE_ORIGIN="explicit --store"
else
  resolve_store_from_scope
fi

if ((PRINT_STORE)); then
  printf '%s\n' "$STORE"
  exit "$EX_OK"
fi

if [[ ! -r "$STORE" ]]; then
  # Absent store is not a crash: it is the commonest state on a fresh install,
  # and the honest answer is "nothing observed", said out loud, with the scope
  # it was said about — a store written under another scope is the other
  # common reason for this branch.
  printf 'skill-pair-cooccurrence.sh: no readable skill-usage store at %s (%s)\n' "$STORE" "$STORE_ORIGIN" >&2
  printf 'Nothing has been observed. This is the normal state before the claude-ops skill-usage hooks have run in this repo; it is not evidence about %s or %s.\n' \
    "$CALLER" "$CALLEE" >&2
  exit "$EX_NO_STORE"
fi

# One jq program does the whole reduction, so the grouping rule lives in exactly
# one place. Malformed rows are dropped rather than fatal — this is an
# observability store and one bad line must not cost the report (the same
# posture parse_jsonl() takes in audit_skill_visibility.py).
REPORT="$(
  jq -Rnc \
    --arg caller "$CALLER" \
    --arg callee "$CALLEE" \
    --argjson floor_days "$FLOOR_DAYS" \
    --argjson floor_groups "$FLOOR_GROUPS" '
    # Raw input plus `fromjson?` is what makes a bad row cost only itself.
    # `jq -s` would fail the ENTIRE file on the first unparsable line, which is
    # the opposite of the stated posture.
    [ inputs
      | fromjson?
      | select(type == "object")
      | select((.event // "") == "SkillUse")
      | select((.skill // "") != "" and (.ts // "") != "")
      | { skill: .skill,
          ts: .ts,
          group: ((.project_id // "unknown") + " " + (.branch // "unknown")) }
    ] as $events
    | ($events | map(.ts) | sort) as $stamps
    | ($stamps | first) as $first
    | ($stamps | last) as $last
    | (if $first == null then 0
       else (($last | fromdateiso8601) - ($first | fromdateiso8601)) / 86400
       end) as $span_days
    | ($events | group_by(.group)) as $groups
    | [ $groups[] | select(any(.[]; .skill == $caller)) ] as $with_caller
    | [ $with_caller[]
        | (map(select(.skill == $caller)) | map(.ts) | sort | first) as $caller_first
        | (map(select(.skill == $callee)) | map(.ts) | sort | first) as $callee_first
        | { has_callee: ($callee_first != null),
            order: (if $callee_first == null then "absent"
                    elif $callee_first < $caller_first then "callee-first"
                    elif $callee_first > $caller_first then "caller-first"
                    else "same-timestamp" end) }
      ] as $rows
    | ($with_caller | length) as $denominator
    | ([ $rows[] | select(.has_callee) ] | length) as $numerator
    | { caller: $caller,
        callee: $callee,
        events_read: ($events | length),
        horizon_start: $first,
        horizon_end: $last,
        span_days: ($span_days | floor),
        groups_total: ($groups | length),
        denominator: $denominator,
        numerator: $numerator,
        order_callee_first: ([ $rows[] | select(.order == "callee-first") ] | length),
        order_caller_first: ([ $rows[] | select(.order == "caller-first") ] | length),
        order_same_timestamp: ([ $rows[] | select(.order == "same-timestamp") ] | length),
        floor_days: $floor_days,
        floor_groups: $floor_groups }
    | . + (
        if .events_read == 0 then
          { verdict: "WITHHELD",
            reason: "the store holds no SkillUse events." }
        elif .denominator == 0 then
          { verdict: "WITHHELD",
            reason: ($caller + " was never observed, so there is no denominator to take a fraction of. An empty denominator is not a rate of zero.") }
        elif (.span_days < $floor_days) then
          { verdict: "WITHHELD",
            reason: ("the observed span is " + (.span_days | tostring) + "d, below the " + ($floor_days | tostring) + "d exposure floor; a store this young cannot distinguish never-invoked from never-observed.") }
        elif (.denominator < $floor_groups) then
          { verdict: "WITHHELD",
            reason: ("only " + (.denominator | tostring) + " group(s) carry " + $caller + ", below the floor of " + ($floor_groups | tostring) + "; a rate over that denominator would be noise reported as a finding.") }
        else
          { verdict: "READING",
            reason: "",
            rate: ((.numerator * 100 / .denominator) | floor) }
        end)
  ' <"$STORE" 2>/dev/null
)" || true

if [[ -z "$REPORT" ]]; then
  printf 'skill-pair-cooccurrence.sh: %s could not be parsed as a JSONL store\n' "$STORE" >&2
  exit "$EX_NO_STORE"
fi

if ((AS_JSON)); then
  # The caveat rides in the JSON too. A consumer that machine-reads this must not
  # get a number stripped of the thing that qualifies it.
  jq -c '. + {proxy_limit: "Co-occurrence within a (project_id, branch) group, NOT caller attribution: the SkillUse record has no field naming the invoking skill, and no session id. Consistent with causation; does not demonstrate it."}' <<<"$REPORT"
  exit "$EX_OK"
fi

jq -r '
  "Skill-pair co-occurrence — " + .caller + " -> " + .callee,
  "",
  "Store read:        " + (.events_read | tostring) + " SkillUse event(s) across " + (.groups_total | tostring) + " (project_id, branch) group(s)",
  "Observed horizon:  " + ((.horizon_start // "none")) + " .. " + ((.horizon_end // "none")) + "  (" + (.span_days | tostring) + "d, floor " + (.floor_days | tostring) + "d)",
  "Denominator:       " + (.denominator | tostring) + " group(s) where " + .caller + " fired (floor " + (.floor_groups | tostring) + ")",
  "",
  (if .verdict == "READING" then
     "VERDICT: " + (.rate | tostring) + "% — " + (.numerator | tostring) + " of " + (.denominator | tostring) + " group(s) carrying " + .caller + " also carry " + .callee + ".",
     "  ordering: " + (.order_callee_first | tostring) + " with " + .callee + " first, "
       + (.order_caller_first | tostring) + " with " + .caller + " first, "
       + (.order_same_timestamp | tostring) + " at the same timestamp."
   else
     "WITHHELD: " + .reason
   end),
  "",
  "PROXY LIMIT — this reading is co-occurrence, not attribution.",
  "  The SkillUse record carries no field naming the skill that invoked another,",
  "  and no session id. Groups are keyed on (project_id, branch), so two sessions",
  "  on one branch collapse and one session across a branch switch splits. A " + .callee,
  "  the user invoked by hand is indistinguishable here from one " + .caller + " caused.",
  "  Read this as consistent with causation, never as demonstrating it."
' <<<"$REPORT"

exit "$EX_OK"
