#!/usr/bin/env bash
# skill-pair-cooccurrence.sh — does skill B get invoked where skill A ran?
#
# Reads a `skill-usage.jsonl` store (SkillUse events, written by claude-ops'
# skill-usage-audit.sh / skill-usage-expansion-audit.sh) and reports, for an
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
# Exit:
#   0  a reading was produced — a VERDICT or an honest WITHHELD
#   2  the store is missing or unreadable
#   3  invoked with bad arguments
set -uo pipefail

EX_OK=0
EX_NO_STORE=2
EX_USAGE=3

USAGE='usage: skill-pair-cooccurrence.sh [--store PATH] [--pair CALLER,CALLEE]
                                  [--floor-days N] [--floor-groups N] [--json]

  --store PATH        skill-usage.jsonl to read. Default: the repo-scope store,
                      <git toplevel>/.claude/observability/skill-usage.jsonl
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

STORE=""
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

if [[ -z "$STORE" ]]; then
  TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || printf '.')"
  STORE="$TOPLEVEL/.claude/observability/skill-usage.jsonl"
fi

if [[ ! -r "$STORE" ]]; then
  # Absent store is not a crash: it is the commonest state on a fresh install,
  # and the honest answer is "nothing observed", said out loud.
  printf 'skill-pair-cooccurrence.sh: no readable skill-usage store at %s\n' "$STORE" >&2
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
