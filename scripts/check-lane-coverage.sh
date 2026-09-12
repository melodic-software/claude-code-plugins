#!/usr/bin/env bash
# Gate: every lane defined in the CI workflow must be able to turn the required
# aggregate red, at BOTH levels the lanes live at, or carry a written reason
# for staying out of it.
#
#   scripts/check-lane-coverage.sh --check [<workflow> [<aggregate-job-id> [<step-opt-out-list>]]]
#
# Defaults: .github/workflows/ci.yml, the `ci-status` aggregate, and
# scripts/lane-coverage-step-opt-outs.txt.
#
# WHY. `ci-status` is the single check the org ci-gate ruleset keys on, and its
# own comment calls its `needs` list "the single source of truth for the lane
# list". Nothing enforced the other direction: a job DEFINED in ci.yml but
# ABSENT from that list runs, reports, and turns red in the run list while
# `ci-status` reports success — so it cannot gate a merge. `hook-utils-windows`
# already states the doctrine in prose ("a lane missing from that list is
# informational no matter how loudly a comment here calls it a gate"), and prose
# is not a gate: `managed-scope-sync` and `state-key-sync` shipped outside the
# aggregate for their whole lifetime (claude-code-plugins#2856), each advertised
# as a dedicated check in scripts/cross-plugin-source-registry.txt. That is the
# false-green shape docs/conventions/liveness-assertion/ names — green surface,
# dead enforcement — with the added twist that the surface is the merge gate
# itself.
#
# The same shape exists one level down. Most lanes are no longer jobs: they are
# STEPS of one job, each carrying `continue-on-error: true` so that one failure
# does not hide the others, and an `id` so that an aggregator feed at the foot of
# the job can read `steps.<id>.outcome` and turn the job red on any non-success.
# `continue-on-error` absorbs the failure by design, so a gate step whose id the
# feed does not read fails silently: the job stays green, `ci-status` stays
# green, and the lane is decoration. The job-level check cannot see that, because
# the job IS in `needs`. So this gate proves set equality at step level too.
#
# WHAT IS CHECKED AT JOB LEVEL (all four directions, so the two sets are
# provably equal):
#   1. UNGATED LANE   — a job defined in the workflow, not in the aggregate's
#                       `needs`, and not annotated. The class #2856 filed.
#   2. DANGLING NEED  — a `needs` entry naming no defined job. GitHub rejects
#                       this at workflow-parse time, but a parse error surfaces
#                       as a failed run, not as a named defect.
#   3. STALE OPT-OUT  — a job annotated as deliberately ungated that IS in
#                       `needs`. Same stale-guard idiom as the baseline lists in
#                       scripts/: an exemption must not outlive what it excuses.
#   4. BARE OPT-OUT   — the annotation present with no reason after the colon.
#                       An undocumented opt-out is exactly the silent off switch
#                       this gate exists to deny, so it fails rather than passing
#                       as "annotated".
#
# WHAT IS CHECKED AT STEP LEVEL. A GATE STEP is a step carrying a literal
# `continue-on-error: true`; the AGGREGATOR FEED of a job is every row of the
# form `<name>=${{ ... steps.<id>.outcome }}` inside a block scalar of that job
# (the `CHECK_RESULTS` env block of the aggregate step, in this repo). Within
# each job the set of gate steps, minus the declared opt-outs, must EQUAL the
# set of ids the feed reads:
#   5. UNFED GATE       — a gate step with an id that no feed row in its job
#                         reads, and no opt-out. Its failure is absorbed and
#                         nothing turns red. The class this level exists for.
#   6. UNREADABLE GATE  — a gate step with no `id` at all. It cannot be fed, so
#                         it is the same defect with nothing to point at.
#   7. DANGLING FEED    — a feed row reading `steps.<id>.outcome` for an id no
#                         step in that job carries with `continue-on-error:
#                         true`. An undefined id evaluates to an empty string;
#                         an id on a step without the flag is a row the feed
#                         does not need and that would mask the flag's absence
#                         if one were added later.
#   8. STALE STEP OPT-OUT — a listed step that is not a gate step, or that the
#                         feed reads anyway. An exemption must not outlive what
#                         it excuses.
#   9. BARE STEP OPT-OUT  — a listed step with no reason written beside it.
# Steps of a job that is itself annotated `# lane-coverage-ok:` are exempt from
# 5 and 6: an informational lane cannot gate a merge whatever its steps do.
# Check 7 applies everywhere, because a feed row that reads nothing is wrong in
# any job.
#
# A `steps.<id>.outcome` read OUTSIDE a block scalar — a step-level `if:`, say —
# is not a feed row. This gate models ONE aggregation shape, the one this
# workflow uses, and a gate step reachable only some other way reports UNFED
# rather than passing on a shape nobody checked. That is the fail-closed
# direction: a false alarm names a step and a fix, a missed one is the silent
# lane this gate exists to deny.
#
# THE JOB OPT-OUT. A job that legitimately does not belong in the required
# aggregate — advisory by design, or driven by an event the merge gate never
# sees — records that decision inline:
#
#   # lane-coverage-ok: <reason>
#   some-job:
#
# or as a trailing comment on the job key itself. Same annotated-exemption shape
# `# silent-skip-ok:` uses for scripts/check-silent-skips.sh: the reason lives
# next to the thing it excuses, in the file a reviewer is already reading, and
# there is no separate list to drift. The annotation must sit in the contiguous
# 2-space comment block immediately above the job key (a blank line or any other
# line breaks contiguity), so it can never be mistaken for an annotation
# belonging to some earlier job. As of #2856 the repo carries ZERO opt-outs; the
# path exists so that a future advisory lane is a decision on the record instead
# of an omission nobody notices.
#
# THE STEP OPT-OUT. A step that carries `continue-on-error: true` for a reason
# other than aggregation (the docs-only resolver's own steps, whose failure must
# fall through to a fail-open default instead of failing their job) is listed in
# scripts/lane-coverage-step-opt-outs.txt, one entry per line:
#
#   <job-id>/<step-id>  <reason>
#
# The reason rides on the entry line, so it cannot drift away from what it
# excuses, and the list is checked in both directions (8 and 9 above), so it
# cannot rot into a silent allowlist. It is a list rather than the inline
# annotation the job level uses because a job key is a 2-space line with one
# possible meaning, while a step is a sequence item whose comment could sit above
# `- name:`, `uses:` or `with:` — attributing it would be exactly the
# shape-guessing this gate refuses to do. The list is parsed by the shared reader
# every scripts/*.txt list uses (scripts/lib/read-list.sh, `leading` mode), not
# by a private parser.
#
# The aggregate job itself is exempt from the job-level check by construction —
# it cannot depend on itself — via AGGREGATE below, not via a silent filter.
#
# FAIL CLOSED ON SHAPE. This reads the workflow structurally with awk rather
# than through a YAML library (the repo ships no root YAML dependency, and the
# only workflow parser in the tree, .github/standards/runner-policy, is an
# org-owned standards materialization this repo does not edit). Every YAML shape
# it does not recognize — a flow-sequence `needs: [a, b]`, a scalar `needs: x`,
# an aggregate with no `needs:` at all, a 2-space key under `jobs:` that is not a
# plain job id, an expression-valued `continue-on-error`, a `steps.<id>.outcome`
# read inside a block scalar that is not a single-step feed row — exits 2
# (inconclusive), never 0. Returning an empty lane set on an unparsed file would
# be this gate committing the very defect it detects. Block-scalar bodies are
# read as data, never as structure, so a script line can never be mistaken for
# a step key.
#
# Exit: 0 covered; 1 a coverage defect; 2 usage, missing file, or unrecognized
# workflow shape.
set -uo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "check-lane-coverage: not inside a git work tree" >&2
  exit 2
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$(git rev-parse --show-toplevel)" || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

usage() {
  echo "usage: $(basename "$0") --check [<workflow> [<aggregate-job-id> [<step-opt-out-list>]]]" >&2
  exit 2
}

[[ "${1:-}" == "--check" ]] || usage
WORKFLOW="${2:-.github/workflows/ci.yml}"
AGGREGATE="${3:-ci-status}"
STEP_OPT_OUTS="${4:-scripts/lane-coverage-step-opt-outs.txt}"
[[ $# -le 4 ]] || usage

if [[ ! -f "$WORKFLOW" ]]; then
  echo "check-lane-coverage: workflow not found: $WORKFLOW" >&2
  exit 2
fi
if [[ ! -f "$STEP_OPT_OUTS" ]]; then
  echo "check-lane-coverage: step opt-out list not found: $STEP_OPT_OUTS" >&2
  exit 2
fi

# One structural pass. Emits these record kinds on stdout:
#   JOB <id> <A|N> <reason...>       A = annotated opt-out (reason may be empty)
#   NEED <id>
#   STEPNAME <job> <ordinal> <name>  the step's display name, for messages
#   STEPID <job> <ordinal> <id>
#   COE <job> <ordinal>              step carries a literal continue-on-error: true
#   FEED <job> <id>                  a feed row reads steps.<id>.outcome
#   ERR <message>
parsed="$(
  awk -v agg="$AGGREGATE" '
    function reset_ann() { ann = 0; reason = "" }
    function trim(s) { sub(/^[[:blank:]]+/, "", s); sub(/[[:blank:]]+$/, "", s); return s }
    function indent_of(s,   t) { t = s; sub(/[^[:blank:]].*$/, "", t); return length(t) }
    # The column the KEY of a line sits at: past the "- " of a sequence item.
    function key_indent(s,   i) { i = indent_of(s); if (substr(s, i + 1, 2) == "- ") { return i + 2 } return i }
    function uncommented(s,   l) {
      l = trim(s)
      if (substr(l, 1, 1) == "#") { return "" }
      sub(/[[:blank:]]+#.*$/, "", l)
      return l
    }

    # A block scalar body is data. The only fact read from it is the aggregator
    # feed: a row `<name>=${{ ... steps.<id>.outcome }}` names exactly one
    # step. Any other read of a step outcome inside a scalar is a shape this
    # gate does not model, so it is refused rather than guessed at.
    function scan_scalar(   l, id, rest) {
      l = trim($0)
      if (l !~ /steps\.[A-Za-z_][A-Za-z0-9_-]*\.outcome/) { return }
      if (l ~ /^[A-Za-z0-9_-]+=[$][{][{] .*steps\.[A-Za-z_][A-Za-z0-9_-]*\.outcome [}][}]$/) {
        match(l, /steps\.[A-Za-z_][A-Za-z0-9_-]*\.outcome [}][}]$/)
        id = substr(l, RSTART + 6, RLENGTH - 6 - 11)
        rest = substr(l, 1, RSTART - 1)
        if (rest ~ /steps\./) {
          print "ERR feed row in job " job " reads more than one step: " l
          return
        }
        print "FEED " job " " id
        return
      }
      print "ERR step outcome read in job " job " in a shape this gate does not model: " l
    }

    BEGIN {
      injobs = 0; seen_jobs = 0; job = ""; needs_state = 0; reset_ann()
      step = 0; scalar_key = -1; scalar_body = -1
    }

    # --- block scalars: their content is data, never structure -------------
    # The body is every following line indented deeper than the key that
    # opened it, at or beyond the indent its first line established. A line
    # shallower than that closes it and is real structure again.
    scalar_key >= 0 {
      if ($0 ~ /^[[:blank:]]*$/) { next }
      if (indent_of($0) > scalar_key && (scalar_body < 0 || indent_of($0) >= scalar_body)) {
        if (scalar_body < 0) { scalar_body = indent_of($0) }
        scan_scalar()
        next
      }
      scalar_key = -1; scalar_body = -1
    }

    # The jobs: mapping opens at column 0 and closes at the next column-0 key.
    !injobs && /^jobs:[[:blank:]]*$/ { injobs = 1; seen_jobs = 1; next }
    !injobs { next }
    /^[^[:blank:]#]/ { injobs = 0; needs_state = 0; next }

    # --- inside the aggregate: the needs block sequence ---
    needs_state == 1 {
      if ($0 ~ /^[[:blank:]]*$/ || $0 ~ /^      #/) { next }
      if ($0 ~ /^      - [A-Za-z_][A-Za-z0-9_-]*[[:blank:]]*$/) {
        item = $0
        sub(/^      - /, "", item)
        sub(/[[:blank:]]+$/, "", item)
        print "NEED " item
        next
      }
      # Indent >= 6 that is not a plain list item is a shape we do not model.
      if ($0 ~ /^      /) {
        print "ERR unsupported needs entry under " agg ": " $0
        next
      }
      needs_state = 0
      # Fall through: this line may itself be a job key or a 4-space key.
    }

    # --- 2-space keys and comments under jobs: ---
    /^  [^[:blank:]]/ {
      if ($0 ~ /^  #/) {
        line = $0
        sub(/^  #[[:blank:]]*/, "", line)
        if (line ~ /^lane-coverage-ok:/) {
          ann = 1
          reason = line
          sub(/^lane-coverage-ok:[[:blank:]]*/, "", reason)
          sub(/[[:blank:]]+$/, "", reason)
        }
        next
      }
      if ($0 ~ /^  [A-Za-z_][A-Za-z0-9_-]*:[[:blank:]]*(#.*)?$/) {
        job = $0
        sub(/:.*$/, "", job)
        sub(/^  /, "", job)
        step = 0
        trail = $0
        if (trail ~ /#[[:blank:]]*lane-coverage-ok:/) {
          sub(/^.*#[[:blank:]]*lane-coverage-ok:[[:blank:]]*/, "", trail)
          sub(/[[:blank:]]+$/, "", trail)
          ann = 1
          reason = trail
        }
        print "JOB " job " " (ann ? "A" : "N") " " reason
        reset_ann()
        next
      }
      print "ERR unrecognized key under jobs: " $0
      reset_ann()
      next
    }

    # --- 4-space keys inside a job ---
    /^    [^[:blank:]]/ {
      reset_ann()
      if (job == agg && $0 ~ /^    needs:/) {
        if ($0 ~ /^    needs:[[:blank:]]*$/) { needs_state = 1; print "NEEDSBLOCK"; next }
        print "ERR " agg " needs: is not a block sequence: " $0
        next
      }
      if (uncommented($0) ~ /:[[:blank:]]*[|>][-+0-9]*$/) { scalar_key = key_indent($0) }
      next
    }

    # --- steps: boundaries, ids, and the absorb flag ---
    {
      reset_ann()
      if ($0 ~ /^      - /) { step = step + 1 }
      if ($0 ~ /^      - name:/) {
        nm = $0
        sub(/^      - name:[[:blank:]]*/, "", nm)
        print "STEPNAME " job " " step " " uncommented(nm)
      }
      if ($0 ~ /^        id:/) {
        sid = $0
        sub(/^        id:[[:blank:]]*/, "", sid)
        print "STEPID " job " " step " " uncommented(sid)
      }
      # `continue-on-error` decides whether a failure is absorbed, so an
      # expression-valued one cannot be judged without evaluating it. Refuse
      # rather than guess: a wrong guess is a silent gate either way.
      if ($0 ~ /^        continue-on-error:/) {
        coe = $0
        sub(/^        continue-on-error:[[:blank:]]*/, "", coe)
        coe = uncommented(coe)
        if (coe == "true") { print "COE " job " " step }
        else if (coe != "false") {
          print "ERR continue-on-error in job " job " step " step " is not a literal true/false: " coe
        }
      }
      if (uncommented($0) ~ /:[[:blank:]]*[|>][-+0-9]*$/) { scalar_key = key_indent($0) }
    }

    END { if (!seen_jobs) print "ERR no jobs: mapping found" }
  ' "$WORKFLOW"
)" || {
  echo "check-lane-coverage: failed to read $WORKFLOW" >&2
  exit 2
}

shape_errors="$(printf '%s\n' "$parsed" | grep '^ERR ' || true)"
if [[ -n "$shape_errors" ]]; then
  echo "check-lane-coverage: unrecognized workflow shape in $WORKFLOW" >&2
  printf '%s\n' "$shape_errors" | sed 's/^ERR /  /' >&2
  echo "  Refusing to report coverage from a file this gate did not fully parse." >&2
  exit 2
fi

jobs_all="$(printf '%s\n' "$parsed" | grep '^JOB ' | cut -d' ' -f2 || true)"
needs_all="$(printf '%s\n' "$parsed" | grep '^NEED ' | cut -d' ' -f2 || true)"

if [[ -z "$jobs_all" ]]; then
  echo "check-lane-coverage: no jobs parsed from $WORKFLOW" >&2
  exit 2
fi
if ! printf '%s\n' "$jobs_all" | grep -Fxq "$AGGREGATE"; then
  echo "check-lane-coverage: aggregate job '$AGGREGATE' is not defined in $WORKFLOW" >&2
  exit 2
fi
if ! printf '%s\n' "$parsed" | grep -Fxq 'NEEDSBLOCK'; then
  echo "check-lane-coverage: aggregate job '$AGGREGATE' declares no needs: block in $WORKFLOW" >&2
  exit 2
fi
if [[ -z "$needs_all" ]]; then
  echo "check-lane-coverage: aggregate job '$AGGREGATE' has an empty needs: block in $WORKFLOW" >&2
  exit 2
fi

# --- the step opt-out list --------------------------------------------------
#
# One `<job-id>/<step-id>  <reason>` per line, read through the shared reader
# scripts/lib/read-list.sh in `leading` mode: a whole-line `#` is a comment, and
# everything after the id on an ENTRY line is that entry's reason. Carrying the
# reason on the entry line rather than in a comment block above it is what keeps
# the two from drifting apart — there is no adjacency rule to get wrong, and the
# check below can hold each entry to having one. Read before any verdict, so a
# malformed list is inconclusive rather than a pass over an empty set.
optout_entries=()
read_list::into optout_entries "$STEP_OPT_OUTS" --comments leading || exit 2

step_optouts=""        # "<job>/<id>" per line
step_optout_reasons="" # "<job>/<id><TAB><reason>" per line
TAB=$'\t'
for optout_line in ${optout_entries[@]+"${optout_entries[@]}"}; do
  entry="${optout_line%%[[:blank:]]*}"
  if [[ ! "$entry" =~ ^[A-Za-z_][A-Za-z0-9_-]*/[A-Za-z_][A-Za-z0-9_-]*$ ]]; then
    echo "check-lane-coverage: malformed entry in $STEP_OPT_OUTS: '$optout_line' (expected '<job-id>/<step-id>  <reason>')" >&2
    exit 2
  fi
  entry_reason="${optout_line#"$entry"}"
  entry_reason="${entry_reason#"${entry_reason%%[![:blank:]]*}"}"
  step_optouts+="$entry"$'\n'
  step_optout_reasons+="${entry}${TAB}${entry_reason}"$'\n'
done

# Newline-delimited membership test without forking.
has_line() { case $'\n'"$1" in *$'\n'"$2"$'\n'*) return 0 ;; *) return 1 ;; esac }

errors=0
report() {
  echo "$1" >&2
  errors=$((errors + 1))
}

# --- job level --------------------------------------------------------------

annotated_jobs=""
while read -r _ job flag reason; do
  [[ -n "$job" ]] || continue
  [[ "$flag" == "A" ]] && annotated_jobs+="$job"$'\n'
  [[ "$job" != "$AGGREGATE" ]] || continue

  in_needs=1
  printf '%s\n' "$needs_all" | grep -Fxq "$job" || in_needs=0

  if [[ "$flag" == "A" ]]; then
    if [[ -z "$reason" ]]; then
      report "BARE OPT-OUT: job '$job' carries '# lane-coverage-ok:' with no reason. An opt-out without a written reason is not a documented opt-out."
    elif [[ "$in_needs" -eq 1 ]]; then
      report "STALE OPT-OUT: job '$job' is annotated '# lane-coverage-ok: $reason' but IS in ${AGGREGATE}.needs. Drop the annotation."
    fi
    continue
  fi

  if [[ "$in_needs" -eq 0 ]]; then
    report "UNGATED LANE: job '$job' is defined in $WORKFLOW but absent from ${AGGREGATE}.needs, so it cannot gate a merge. Add it to needs, or annotate the job with '# lane-coverage-ok: <reason>'."
  fi
done <<<"$(printf '%s\n' "$parsed" | grep '^JOB ')"

while IFS= read -r need; do
  [[ -n "$need" ]] || continue
  printf '%s\n' "$jobs_all" | grep -Fxq "$need" ||
    report "DANGLING NEED: ${AGGREGATE}.needs names '$need', which is not a job defined in $WORKFLOW."
done <<<"$needs_all"

# --- step level -------------------------------------------------------------

rec_stepid="$(printf '%s\n' "$parsed" | grep '^STEPID ' || true)"
rec_coe="$(printf '%s\n' "$parsed" | grep '^COE ' || true)"
rec_feed="$(printf '%s\n' "$parsed" | grep '^FEED ' || true)"
rec_stepname="$(printf '%s\n' "$parsed" | grep '^STEPNAME ' || true)"

# step_id_of <job> <ordinal>: the id a step declares, or empty.
step_id_of() {
  local _ j o id
  while read -r _ j o id; do
    [[ "$j" == "$1" && "$o" == "$2" ]] || continue
    printf '%s' "$id"
    return
  done <<<"$rec_stepid"
}

# step_name_of <job> <ordinal>: the display name, for a step with no id.
step_name_of() {
  local _ j o name
  while read -r _ j o name; do
    [[ "$j" == "$1" && "$o" == "$2" ]] || continue
    printf '%s' "$name"
    return
  done <<<"$rec_stepname"
}

# Every gate step as "<job>/<id>"; every feed read the same way; every id
# declared anywhere, so a dangling feed row can say WHICH half is missing.
gate_steps=""
all_step_ids=""
while read -r _ j o id; do
  [[ -n "$j" ]] || continue
  all_step_ids+="$j/$id"$'\n'
done <<<"$rec_stepid"

while read -r _ j o; do
  [[ -n "$j" ]] || continue
  id="$(step_id_of "$j" "$o")"
  if [[ -z "$id" ]]; then
    has_line "$annotated_jobs" "$j" && continue
    report "UNREADABLE GATE: job '$j' step #$o ('$(step_name_of "$j" "$o")') carries 'continue-on-error: true' but no 'id', so its outcome cannot be read and its failure turns nothing red. Give it an id and feed it to the aggregator, or drop continue-on-error so it fails the job directly."
    continue
  fi
  gate_steps+="$j/$id"$'\n'
done <<<"$rec_coe"

feed_reads=""
while read -r _ j id; do
  [[ -n "$j" ]] || continue
  feed_reads+="$j/$id"$'\n'
done <<<"$rec_feed"

# 5. UNFED GATE, and the fed half of 8.
while IFS= read -r gs; do
  [[ -n "$gs" ]] || continue
  job="${gs%%/*}"
  if has_line "$step_optouts" "$gs"; then
    if has_line "$feed_reads" "$gs"; then
      report "STALE STEP OPT-OUT: $STEP_OPT_OUTS lists '$gs' as not an aggregator gate, but a feed row in job '$job' reads steps.${gs#*/}.outcome. Drop the entry."
    fi
    continue
  fi
  has_line "$feed_reads" "$gs" && continue
  has_line "$annotated_jobs" "$job" && continue
  report "UNFED GATE: step '${gs#*/}' in job '$job' carries 'continue-on-error: true' but no aggregator feed row in that job reads steps.${gs#*/}.outcome, so its failure is absorbed and turns nothing red. Add a row '<name>=\${{ steps.${gs#*/}.outcome }}' to the feed, or list '$gs' in $STEP_OPT_OUTS with a reason."
done <<<"$gate_steps"

# 7. DANGLING FEED.
while IFS= read -r fr; do
  [[ -n "$fr" ]] || continue
  has_line "$gate_steps" "$fr" && continue
  job="${fr%%/*}"
  if has_line "$all_step_ids" "$fr"; then
    report "DANGLING FEED: a feed row in job '$job' reads steps.${fr#*/}.outcome, but step '${fr#*/}' does not carry 'continue-on-error: true'. A step without it fails the job on its own; the row is not mirroring a gate. Add the flag, or drop the row."
  else
    report "DANGLING FEED: a feed row in job '$job' reads steps.${fr#*/}.outcome, but no step in that job declares 'id: ${fr#*/}'. The read evaluates to an empty string. Fix the id, or drop the row."
  fi
done <<<"$feed_reads"

# 8 (unlisted half) and 9.
while IFS="$TAB" read -r entry oreason; do
  [[ -n "$entry" ]] || continue
  if [[ -z "$oreason" ]]; then
    report "BARE STEP OPT-OUT: $STEP_OPT_OUTS lists '$entry' with nothing after it. Write the reason on the entry line: '$entry  <reason>'. An opt-out without a written reason is not a documented opt-out."
  fi
  if ! has_line "$gate_steps" "$entry"; then
    report "STALE STEP OPT-OUT: $STEP_OPT_OUTS lists '$entry', but no step with that id in that job carries 'continue-on-error: true' in $WORKFLOW. Drop the entry."
  fi
done <<<"$step_optout_reasons"

if [[ "$errors" -ne 0 ]]; then
  echo "check-lane-coverage: $errors coverage defect(s) in $WORKFLOW" >&2
  exit 1
fi

covered="$(printf '%s\n' "$needs_all" | grep -c . || true)"
fed="$(printf '%s' "$feed_reads" | grep -c . || true)"
opted="$(printf '%s' "$step_optouts" | grep -c . || true)"
echo "check-lane-coverage: $WORKFLOW — all $covered lane(s) reachable from ${AGGREGATE}.needs; all $fed gate step(s) fed to the aggregator, $opted opted out"
exit 0
