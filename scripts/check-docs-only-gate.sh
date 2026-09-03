#!/usr/bin/env bash
# Gate: the docs-only scope contract is resolved in ONE place and consumed in
# ONE documented form.
#
#   scripts/check-docs-only-gate.sh --check [<workflow>]
#
# Default workflow: .github/workflows/ci.yml.
#
# WHY. The heavy lanes short-circuit on a diff confined to the docs-only
# allowlist. That short-circuit is a fail-open shape by construction: getting it
# wrong makes a lane report success without running, which is exactly the
# false-green docs/conventions/liveness-assertion/ names. Consumers spell the
# gate as `steps.scope.outputs.docs_only != 'true'`, an INVERSE-polarity test
# of a string flag. A consumer that wrote `== 'false'` instead of `!= 'true'`
# would skip its lane whenever the detector emitted anything unexpected: the
# value is the string `true`, the safe direction is to RUN, and the negation
# must be spelled that exact way. That asymmetry is why this gate exists: the
# properties below are checked against the workflow itself.
#
# WHAT IS CHECKED:
#   1. SINGLE RESOLUTION  — the detector is invoked from exactly one job, that
#                           job is the resolver, and no `steps.<id>.outputs
#                           .docs_only` read survives outside the resolver's own
#                           output expression. A second resolution is a second
#                           answer that can disagree with the first.
#   2. FAIL-CLOSED DEFAULT — the published output is derived by the exact
#                           expression whose value for an UNSET detector output
#                           is "run the full suite". This is the property that
#                           makes a detector that never ran, or a push event
#                           where it is not meant to run, resolve toward running
#                           rather than toward skipping.
#   3. FAILURE IS ABSORBED — the step that invokes the detector carries
#                           `continue-on-error: true` and is the step the output
#                           expression reads, so a detector that fails OUTRIGHT
#                           leaves the output unset and falls into property 2
#                           instead of failing the resolving job and skipping
#                           every consumer.
#   4. SELF-TEST INTACT   — the resolving job runs the detector's own suite, and
#                           that step is NOT `continue-on-error`. A detector
#                           nobody verified must turn something red rather than
#                           resolve a scope silently.
#   5. ONE CONSUMER FORM  — every consumer reference is a STEP-level condition
#                           spelled exactly `== 'true'` (do the work) or
#                           `== 'false'` (report it not applicable), or an entry
#                           of the aggregator feed in its exact template. The
#                           check is a whitelist of whole shapes, not a search
#                           for a substring: a negation, a truthiness test, an
#                           index-syntax spelling, or a JOB-level condition all
#                           fail. A job-level condition is singled out because it
#                           SKIPS the job, and a skipped required lane leaves its
#                           check Pending rather than red — see
#                           scripts/check-docs-only.sh's header.
#   6. FEED MIRRORS A GATE — every step whose outcome the aggregator feed
#                           overrides to `success` on a docs-only diff is a step
#                           that actually carries the work gate. Forgetting an
#                           override is fail-closed (the raw `skipped` reds the
#                           aggregate); adding one for an UNGATED step is
#                           fail-open, because it replaces that step's real
#                           outcome with `success` on every docs-only diff.
#   7. NO JOB-LEVEL IF    — a consumer carries no job-level condition at all. It
#                           reaches the output through `needs`, so it runs only
#                           when the resolver succeeded — which is what makes the
#                           output's domain exactly {'true','false'} and the two
#                           sanctioned forms exact complements. `if: always()` or
#                           `if: ${{ !cancelled() }}` breaks that: the job runs
#                           with an EMPTY output, both forms are false, and every
#                           gated step and its not-applicable reporter skip
#                           together — the lane reports success having run
#                           nothing. The condition need not mention the output to
#                           do this, so this check does not read what it says.
#   8. EDGE DECLARED      — a job that reads the output declares the resolving
#                           job in its `needs`. Without the edge the expression
#                           yields an empty string, with the same consequence.
#   9. CONTRACT IS LIVE   — at least one consumer job actually reads the output.
#                           A resolver nobody consumes is a dead contract, and a
#                           gate that reports "all references are well formed"
#                           over zero references is the nominal closure this file
#                           exists to deny.
#
# FAIL CLOSED ON SHAPE. Like scripts/check-lane-coverage.sh, this reads the
# workflow structurally rather than through a YAML library (the repo ships no
# root YAML dependency). Any shape it does not recognize exits 2 (inconclusive),
# never 0. Reporting "contract satisfied" from a file this gate did not parse
# would be the same false-green it exists to deny. Comments are prose ABOUT the
# contract and never satisfy any property: a commented-out expression must not
# stand in for the expression. Block scalars (`run: |`) are skipped wholesale so
# a script body can never be read as workflow structure.
#
# KNOWN SCOPE LIMIT. A job that delegates to a reusable workflow (`uses:` at the
# job level) has no steps of its own, so its polarity decision would live in a
# file this gate never opens. Such a job is REJECTED if it reads the output,
# rather than passed silently.
#
# Exit: 0 satisfied; 1 a contract defect; 2 usage, missing file, or unrecognized
# workflow shape.
set -uo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "check-docs-only-gate: not inside a git work tree" >&2
  exit 2
fi
cd "$(git rev-parse --show-toplevel)" || exit 2

usage() {
  echo "usage: $(basename "$0") --check [<workflow>]" >&2
  exit 2
}

[[ "${1:-}" == "--check" ]] || usage
WORKFLOW="${2:-.github/workflows/ci.yml}"
[[ $# -le 2 ]] || usage

if [[ ! -f "$WORKFLOW" ]]; then
  echo "check-docs-only-gate: workflow not found: $WORKFLOW" >&2
  exit 2
fi

# The contract's literals, kept together so the whole of it reads as one block
# rather than as constants scattered through the assertions.
TAB_LIT="$(printf '\t')"
RESOLVER_JOB="changes"
DETECT_STEP_ID="detect"
# The resolver publishes a TABLE of boolean-string outputs, not one. Every
# polarity decision in the workflow lives in this table, and consumers only
# ever compare a table entry against 'true' or 'false'. Each row is pinned by
# its exact expression: an output the table does not name is a defect, because
# it is a polarity decision made somewhere this gate cannot see.
#
# `run_full` is the root: it is the only row derived from the detector, and
# every other row narrows it. The narrowing rows read `steps.match.outputs`
# (the change-detection action) through fromJSON with a `|| '{}'` default and
# compare `!= 'false'`, never `== 'true'`, so an unset group runs the lane.
OUTPUT_NAME="run_full"
OUTPUT_TABLE="\
run_full${TAB_LIT}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' }}
run_tests${TAB_LIT}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' && github.event.pull_request.draft != true }}
run_shell${TAB_LIT}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' && github.event.pull_request.draft != true && fromJSON(steps.match.outputs.results || '{}')['shell'] != 'false' }}
run_node${TAB_LIT}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' && github.event.pull_request.draft != true && fromJSON(steps.match.outputs.results || '{}')['node'] != 'false' }}
run_python${TAB_LIT}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' && github.event.pull_request.draft != true && fromJSON(steps.match.outputs.results || '{}')['python'] != 'false' }}
run_windows${TAB_LIT}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' && github.event.pull_request.draft != true && (fromJSON(steps.match.outputs.results || '{}')['shell'] != 'false' || fromJSON(steps.match.outputs.results || '{}')['python'] != 'false') }}
run_workflows${TAB_LIT}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' && fromJSON(steps.match.outputs.results || '{}')['workflows'] != 'false' }}"
# The single required context. Everything reachable from its `needs` is a
# REQUIRED lane, and that closure is what decides whether a job-level condition
# is a defect (check 5c) and whether a lane may opt out of coverage (check 8).
AGGREGATE_JOB="ci-status"
LANE_OPT_OUT="lane-coverage-ok:"
REFERENCE_PREFIX="needs.${RESOLVER_JOB}.outputs."
REFERENCE="${REFERENCE_PREFIX}${OUTPUT_NAME}"

errors=0
report() {
  echo "$1" >&2
  errors=$((errors + 1))
}

# --- structural pass --------------------------------------------------------
#
# One walk over the file, emitting tab-separated records that carry the job (and
# where it matters the step ordinal) each fact belongs to. Attribution happens
# here rather than by re-slicing the text later, so no assertion can be
# satisfied by a line belonging to some other job or step.
#
#   JOB      <job>
#   USES     <job>                        job delegates to a reusable workflow
#   NEEDSFLOW <job> <text>                inline `needs:` value
#   NEEDSITEM <job> <id>                  one entry of a block-sequence `needs:`
#   OUTPUT   <job> <name> <expr>
#   INVOKE   <job> <step>                 invokes the detector
#   SELFTEST <job> <step>                 invokes the detector's own suite
#   COE      <job> <step>                 step carries continue-on-error: true
#   STEPID   <job> <step> <id>
#   REF      <job> <step> <kind> <text>   kind: stepif | jobif | other
#   STEPOUT  <job>                        reads a step-level docs_only output
#   ERR      <message>
parsed="$(
  awk -v resolver="$RESOLVER_JOB" -v output_name="$OUTPUT_NAME" -v lane_opt_out="$LANE_OPT_OUT" '
    function trim(s) { sub(/^[[:blank:]]+/, "", s); sub(/[[:blank:]]+$/, "", s); return s }
    function indent_of(s,   t) { t = s; sub(/[^[:blank:]].*$/, "", t); return length(t) }

    # Everything a line asserts once its comment is removed. A comment is prose
    # ABOUT the contract and satisfies no part of it: a commented-out detector
    # call is not an invocation, and a sentence naming the detector is not a
    # second resolution.
    function uncommented(line,   l) {
      l = trim(line)
      if (substr(l, 1, 1) == "#") { return "" }
      sub(/[[:blank:]]+#.*$/, "", l)
      return l
    }

    # A line MENTIONS the resolved output if it names the output, or reaches the
    # resolver`s outputs at all, in any spelling and any case. Actions context
    # accessors are case-insensitive and may be written with dots or brackets,
    # so this deliberately over-matches: the point is that every mention lands in
    # front of the exact-shape check below rather than being invisible to it. A
    # spelling this file does not model must read as UNSANCTIONED, never as
    # absent — a whitelist that only fires on what it recognizes silently ignores
    # everything else, which is the opposite of rejecting it.
    function mentions_output(line,   l) {
      l = tolower(line)
      if (index(l, outname) > 0) { return 1 }
      if (index(l, "needs") > 0 && index(l, resolver_lc) > 0 && index(l, "outputs") > 0) { return 1 }
      return 0
    }

    # Facts readable from a line WITHOUT interpreting it as workflow structure.
    # Block-scalar bodies get exactly these: a `run:` script that re-resolves the
    # scope is still a second resolution, and the aggregator feed lives inside an
    # env block scalar, so both must still be seen — but neither may be read as a
    # job key or a step boundary.
    function scan_content(   live) {
      live = uncommented($0)
      if (live == "") { return }
      if (live ~ /check-docs-only\.test\.sh/) { print "SELFTEST\t" job "\t" step }
      else if (live ~ /check-docs-only\.sh/) { print "INVOKE\t" job "\t" step }
      if (live ~ /steps\.[A-Za-z_][A-Za-z0-9_-]*\.outputs\.docs_only/) { print "STEPOUT\t" job }
      if (mentions_output(live)) { print "REF\t" job "\t" step "\tother\t" live }
    }

    BEGIN {
      injobs = 0; seen_jobs = 0; job = ""; step = 0
      needs_state = 0; outputs_state = 0; scalar = -1
      pending_laneok = 0; carried_laneok = 0
      # A reason after the colon is mandatory, exactly as check-lane-coverage.sh
      # requires: a bare marker names no lane and excuses nothing.
      laneok_re = "#[[:blank:]]*" lane_opt_out "[[:blank:]]*[^[:blank:]]"
      resolver_lc = tolower(resolver)
      outname = tolower(output_name)
      if (resolver_lc == "" || outname == "") {
        print "ERR\tinternal: resolver job or output name was not supplied to the parser"
        exit 1
      }
    }

    # --- block scalars: their content is data, never structure --------------
    scalar >= 0 {
      if ($0 ~ /^[[:blank:]]*$/) { next }
      if (indent_of($0) > scalar) { scan_content(); next }
      scalar = -1
      # fall through: this line is real structure again
    }

    !injobs && /^jobs:[[:blank:]]*$/ { injobs = 1; seen_jobs = 1; next }
    !injobs { next }

    # A column-0 key closes the jobs: mapping.
    /^[^[:blank:]#]/ { injobs = 0; needs_state = 0; outputs_state = 0; next }

    # A blank line breaks the contiguous comment block above a job key, which
    # is what carries a lane-coverage opt-out. Matches how
    # scripts/check-lane-coverage.sh reads the same marker, so the two gates
    # cannot disagree about which job an opt-out belongs to.
    /^[[:blank:]]*$/ { pending_laneok = 0 }

    # --- comments are prose about the contract, never part of it ------------
    # They are skipped for every purpose EXCEPT that they must not terminate a
    # job body (a comment sits happily between two steps) and that a
    # lane-coverage opt-out in the block directly above a job key attaches to
    # that job. The marker is READ here and judged in check 8; a comment still
    # satisfies no part of the contract itself.
    { probe = trim($0) }
    probe ~ /^#/ {
      if (probe ~ laneok_re) { pending_laneok = 1 }
      next
    }

    # Any non-comment line consumes whatever the comment block above it
    # carried, so the marker reaches the job key it precedes and nothing else.
    { carried_laneok = pending_laneok; pending_laneok = 0 }

    # --- block-sequence needs: ----------------------------------------------
    needs_state == 1 {
      # A sequence item may sit at the key`s own indent or deeper — both are
      # valid YAML, and the shallower form is the one a hand edit reaches for.
      if ($0 ~ /^[[:blank:]]+- [A-Za-z_][A-Za-z0-9_-]*[[:blank:]]*(#.*)?$/ && indent_of($0) >= 4) {
        item = $0
        sub(/^[[:blank:]]*- /, "", item)
        sub(/[[:blank:]]*#.*$/, "", item)
        print "NEEDSITEM\t" job "\t" trim(item)
        next
      }
      # A 4-space key or a shallower line closes the block; anything else at
      # this depth is a sequence shape this gate does not model.
      if ($0 !~ /^    [A-Za-z_][A-Za-z0-9_-]*:/ && indent_of($0) >= 4) {
        print "ERR\tunsupported needs entry in job " job ": " $0
        next
      }
      needs_state = 0
      # fall through
    }

    # --- outputs: mapping ---------------------------------------------------
    outputs_state == 1 {
      if ($0 ~ /^      [A-Za-z_][A-Za-z0-9_-]*:/) {
        name = $0
        sub(/^      /, "", name)
        sub(/:.*$/, "", name)
        expr = $0
        sub(/^      [A-Za-z_][A-Za-z0-9_-]*:[[:blank:]]*/, "", expr)
        print "OUTPUT\t" job "\t" name "\t" trim(expr)
        next
      }
      if ($0 ~ /^      /) {
        print "ERR\tunsupported outputs entry in job " job ": " $0
        next
      }
      outputs_state = 0
      # fall through
    }

    # --- 2-space keys: job boundaries ---------------------------------------
    /^  [^[:blank:]]/ {
      if ($0 ~ /^  [A-Za-z_][A-Za-z0-9_-]*:[[:blank:]]*(#.*)?$/) {
        job = $0
        sub(/:.*$/, "", job)
        sub(/^  /, "", job)
        step = 0
        needs_state = 0
        outputs_state = 0
        print "JOB\t" job
        # Both spellings check-lane-coverage.sh accepts: the marker in the
        # contiguous comment block above the key, and a trailing comment on
        # the key itself.
        if (carried_laneok || $0 ~ laneok_re) { print "LANEOK\t" job }
        next
      }
      print "ERR\tunrecognized key under jobs: " $0
      next
    }

    # --- 4-space keys: job-level ---------------------------------------------
    /^    [^[:blank:]]/ {
      needs_state = 0
      outputs_state = 0
      if ($0 ~ /^    needs:[[:blank:]]*$/) { needs_state = 1; next }
      if ($0 ~ /^    needs:/) {
        rest = $0
        sub(/^    needs:[[:blank:]]*/, "", rest)
        print "NEEDSFLOW\t" job "\t" trim(rest)
        next
      }
      if ($0 ~ /^    outputs:[[:blank:]]*$/) { outputs_state = 1; next }
      if ($0 ~ /^    uses:/) { print "USES\t" job; next }
      if ($0 ~ /^    if:/) {
        rest = $0
        sub(/^    if:[[:blank:]]*/, "", rest)
        rest = uncommented(rest)
        # Recorded whether or not it names the output: ANY job-level condition
        # on a consumer can let that job run while the resolver did not succeed,
        # which is the one state where the published output is empty.
        print "JOBIF\t" job "\t" rest
        if (mentions_output(rest)) { print "REF\t" job "\t-\tjobif\t" rest }
        next
      }
      # A block scalar opening at this level.
      if ($0 ~ /:[[:blank:]]*[|>][-+0-9]*[[:blank:]]*$/) { scalar = 4 }
      next
    }

    # --- step boundaries and step bodies ------------------------------------
    /^      - / { step = step + 1 }

    {
      # `continue-on-error` decides whether a failure is absorbed, so an
      # expression-valued one cannot be judged without evaluating it. Refuse
      # rather than guess: a wrong guess here silently flips property 3 or 4.
      if ($0 ~ /^        continue-on-error:/) {
        coe = $0
        sub(/^        continue-on-error:[[:blank:]]*/, "", coe)
        coe = uncommented(coe)
        if (coe == "true") { print "COE\t" job "\t" step }
        else if (coe != "false") {
          print "ERR\tcontinue-on-error in job " job " step " step " is not a literal true/false: " coe
        }
      }

      if ($0 ~ /^        id:/) {
        sid = $0
        sub(/^        id:[[:blank:]]*/, "", sid)
        print "STEPID\t" job "\t" step "\t" trim(sid)
      }

      if ($0 ~ /^        if:/ && mentions_output(uncommented($0))) {
        rest = $0
        sub(/^        if:[[:blank:]]*/, "", rest)
        print "REF\t" job "\t" step "\tstepif\t" uncommented(rest)
      } else {
        scan_content()
      }

      # A block scalar opening inside a step: its body is content, not structure.
      if ($0 ~ /:[[:blank:]]*[|>][-+0-9]*[[:blank:]]*$/) { scalar = indent_of($0) }
    }

    END { if (!seen_jobs) print "ERR\tno jobs: mapping found" }
  ' "$WORKFLOW"
)" || {
  echo "check-docs-only-gate: failed to read $WORKFLOW" >&2
  exit 2
}

TAB="$(printf '\t')"

# Partition the record stream once. Re-grepping it per assertion would fork a
# process per lookup, which is measurable on a large workflow.
REC_ERR=""; REC_JOB=""; REC_USES=""; REC_NEEDSFLOW=""; REC_NEEDSITEM=""
REC_OUTPUT=""; REC_INVOKE=""; REC_SELFTEST=""; REC_COE=""; REC_STEPID=""
REC_REF=""; REC_STEPOUT=""; REC_JOBIF=""; REC_LANEOK=""
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  case "$line" in
  "ERR$TAB"*) REC_ERR+="${line#*"$TAB"}"$'\n' ;;
  "JOB$TAB"*) REC_JOB+="${line#*"$TAB"}"$'\n' ;;
  "USES$TAB"*) REC_USES+="${line#*"$TAB"}"$'\n' ;;
  "NEEDSFLOW$TAB"*) REC_NEEDSFLOW+="${line#*"$TAB"}"$'\n' ;;
  "NEEDSITEM$TAB"*) REC_NEEDSITEM+="${line#*"$TAB"}"$'\n' ;;
  "OUTPUT$TAB"*) REC_OUTPUT+="${line#*"$TAB"}"$'\n' ;;
  "INVOKE$TAB"*) REC_INVOKE+="${line#*"$TAB"}"$'\n' ;;
  "SELFTEST$TAB"*) REC_SELFTEST+="${line#*"$TAB"}"$'\n' ;;
  "COE$TAB"*) REC_COE+="${line#*"$TAB"}"$'\n' ;;
  "STEPID$TAB"*) REC_STEPID+="${line#*"$TAB"}"$'\n' ;;
  "REF$TAB"*) REC_REF+="${line#*"$TAB"}"$'\n' ;;
  "STEPOUT$TAB"*) REC_STEPOUT+="${line#*"$TAB"}"$'\n' ;;
  "JOBIF$TAB"*) REC_JOBIF+="${line#*"$TAB"}"$'\n' ;;
  "LANEOK$TAB"*) REC_LANEOK+="${line#*"$TAB"}"$'\n' ;;
  # The awk pass emits no other record kind; a line that reaches here means the
  # two halves have drifted, which is not something to guess past.
  *)
    echo "check-docs-only-gate: unrecognized internal record: $line" >&2
    exit 2
    ;;
  esac
done <<<"$parsed"

# Newline-delimited membership test without forking.
has_line() { case $'\n'"$1" in *$'\n'"$2"$'\n'*) return 0 ;; *) return 1 ;; esac; }

# --- the output table, read three ways --------------------------------------

# table_has <name>: is <name> a sanctioned output?
table_has() {
  local tn
  while IFS="$TAB" read -r tn _; do
    [[ "$tn" == "$1" ]] && return 0
  done <<<"$OUTPUT_TABLE"
  return 1
}

# table_names_list: the row names, for a message.
table_names_list() {
  local tn out=""
  while IFS="$TAB" read -r tn _; do
    [[ -n "$tn" ]] || continue
    out+="${out:+, }$tn"
  done <<<"$OUTPUT_TABLE"
  printf '%s' "$out"
}

# parse_consumer_form <bare-expression>: recognises exactly
# `needs.<resolver>.outputs.<name> == '<true|false>'`, setting CF_NAME and
# CF_VALUE. Deliberately whole-string: a prefix match would accept a longer
# expression whose extra clauses this gate never reads.
CF_NAME=""; CF_VALUE=""
parse_consumer_form() {
  local t="$1" rest
  CF_NAME=""; CF_VALUE=""
  [[ "$t" == "${REFERENCE_PREFIX}"* ]] || return 1
  rest="${t#"$REFERENCE_PREFIX"}"
  CF_NAME="${rest%% *}"
  [[ -n "$CF_NAME" && "$CF_NAME" != *[^A-Za-z0-9_-]* ]] || { CF_NAME=""; return 1; }
  rest="${rest#"$CF_NAME"}"
  case "$rest" in
  " == 'true'") CF_VALUE="true" ;;
  " == 'false'") CF_VALUE="false" ;;
  *) CF_NAME=""; return 1 ;;
  esac
  return 0
}

# Unique, space-joined rendering of a newline-delimited list, for messages.
uniq_list() {
  local seen="" item out=""
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    has_line "$seen" "$item" && continue
    seen+="$item"$'\n'
    out+="$item "
  done <<<"$1"
  printf '%s' "$out"
}

shape_errors="$REC_ERR"

if [[ -n "$shape_errors" ]]; then
  echo "check-docs-only-gate: unrecognized workflow shape in $WORKFLOW" >&2
  while IFS= read -r msg; do
    [[ -n "$msg" ]] || continue
    echo "  $msg" >&2
  done <<<"$shape_errors"
  echo "  Refusing to report a satisfied contract from a file this gate did not fully parse." >&2
  exit 2
fi

jobs_all="$REC_JOB"
if [[ -z "$jobs_all" ]]; then
  echo "check-docs-only-gate: no jobs parsed from $WORKFLOW" >&2
  exit 2
fi
if ! has_line "$jobs_all" "$RESOLVER_JOB"; then
  echo "check-docs-only-gate: resolving job '$RESOLVER_JOB' is not defined in $WORKFLOW" >&2
  exit 2
fi

# --- 1. SINGLE RESOLUTION ---------------------------------------------------

invoker_jobs=""
invoker_count=0
invoke_count=0
while IFS="$TAB" read -r ijob _; do
  [[ -n "$ijob" ]] || continue
  invoke_count=$((invoke_count + 1))
  has_line "$invoker_jobs" "$ijob" && continue
  invoker_jobs+="$ijob"$'\n'
  invoker_count=$((invoker_count + 1))
done <<<"$REC_INVOKE"

if [[ "$invoker_count" -ne 1 ]]; then
  report "SINGLE RESOLUTION: the docs-only detector is invoked from $invoker_count job(s) [$(uniq_list "$invoker_jobs")]. It must be resolved exactly once, in '$RESOLVER_JOB', and read from there."
elif [[ "$invoke_count" -ne 1 ]]; then
  report "SINGLE RESOLUTION: the docs-only detector is invoked $invoke_count times in job [$(uniq_list "$invoker_jobs")]. Count invocation records; the sole invocation must belong to the resolver's detect step, not a second call that can overwrite docs_only."
elif ! has_line "$invoker_jobs" "$RESOLVER_JOB"; then
  report "SINGLE RESOLUTION: the docs-only detector is invoked from [$(uniq_list "$invoker_jobs")], not from the resolving job '$RESOLVER_JOB'."
fi

# The resolver reads its own detect step to publish the output — the single
# sanctioned step-level read. Anywhere else it is a second answer.
stray_stepouts=""
while IFS= read -r sjob; do
  [[ -n "$sjob" ]] || continue
  [[ "$sjob" == "$RESOLVER_JOB" ]] && continue
  stray_stepouts+="$sjob"$'\n'
done <<<"$REC_STEPOUT"
if [[ -n "$stray_stepouts" ]]; then
  report "SINGLE RESOLUTION: a step-level docs_only output is still read in job(s) [$(uniq_list "$stray_stepouts")]. Consumers must read $REFERENCE, never a per-job step output."
fi

# --- 2. FAIL-CLOSED DEFAULT -------------------------------------------------

# Every table row must be published, by exactly its expression; and the
# resolver must publish nothing the table does not name. The first half is what
# makes an unset detector output resolve toward RUNNING; the second is what
# keeps a new polarity decision from being introduced where nothing checks it.

while IFS="$TAB" read -r tname texpr; do
  [[ -n "$tname" ]] || continue
  published_expr=""
  published_found=0
  while IFS="$TAB" read -r ojob oname oexpr; do
    [[ "$ojob" == "$RESOLVER_JOB" && "$oname" == "$tname" ]] || continue
    published_found=1
    published_expr="$oexpr"
  done <<<"$REC_OUTPUT"

  if [[ "$published_found" -eq 0 ]]; then
    report "FAIL-CLOSED DEFAULT: job '$RESOLVER_JOB' publishes no '$tname' output. Consumers would read an empty string, which skips both the work step and its not-applicable reporter."
  elif [[ "$published_expr" != "$texpr" ]]; then
    report "FAIL-CLOSED DEFAULT: job '$RESOLVER_JOB' publishes '$tname: $published_expr', expected exactly '$tname: $texpr'. That expression is the contract: an UNSET detector output (the detector never ran, or failed) renders as 'true', so the full suite runs, and every narrowing clause compares != 'false' so an unset filter group runs its lane too. Any other derivation can resolve an unset input toward skipping."
  fi
done <<<"$OUTPUT_TABLE"

while IFS="$TAB" read -r ojob oname oexpr; do
  [[ "$ojob" == "$RESOLVER_JOB" ]] || continue
  [[ -n "$oname" ]] || continue
  table_has "$oname" && continue
  report "FAIL-CLOSED DEFAULT: job '$RESOLVER_JOB' publishes '$oname', which the output table does not name. Every polarity decision belongs in the table [$(table_names_list)]; an extra output is a decision this gate cannot check, and consumers reading it are invisible to the consumer-form rule."
done <<<"$REC_OUTPUT"

# --- 3. FAILURE IS ABSORBED -------------------------------------------------
#
# The step carrying the detect id must be the step that actually invokes the
# detector, and must absorb its own failure. Checking those independently would
# pass a workflow whose detect step runs something else entirely.

detect_job=""
detect_ordinal=""
while IFS="$TAB" read -r sjob step_ord sid; do
  [[ "$sid" == "$DETECT_STEP_ID" ]] || continue
  [[ -n "$detect_job" ]] && continue
  detect_job="$sjob"
  detect_ordinal="$step_ord"
done <<<"$REC_STEPID"

if [[ -z "$detect_job" ]]; then
  report "FAILURE IS ABSORBED: no step declares 'id: $DETECT_STEP_ID', so the published output has nothing to read."
elif [[ "$detect_job" != "$RESOLVER_JOB" ]]; then
  report "FAILURE IS ABSORBED: the 'id: $DETECT_STEP_ID' step is in job '$detect_job', not in the resolving job '$RESOLVER_JOB'."
else
  if ! has_line "$REC_INVOKE" "${RESOLVER_JOB}${TAB}${detect_ordinal}"; then
    report "FAILURE IS ABSORBED: the 'id: $DETECT_STEP_ID' step in job '$RESOLVER_JOB' does not invoke the docs-only detector, so the published output does not describe what the detector found."
  fi
  if ! has_line "$REC_COE" "${RESOLVER_JOB}${TAB}${detect_ordinal}"; then
    report "FAILURE IS ABSORBED: the 'id: $DETECT_STEP_ID' step in job '$RESOLVER_JOB' is missing 'continue-on-error: true'. Without it a detector that fails outright fails the resolving job, and every consumer is skipped rather than falling back to running the full suite."
  fi
fi

# --- 4. SELF-TEST INTACT ----------------------------------------------------

selftest_ordinal=""
while IFS="$TAB" read -r sjob step_ord; do
  [[ "$sjob" == "$RESOLVER_JOB" ]] || continue
  [[ -n "$selftest_ordinal" ]] && continue
  selftest_ordinal="$step_ord"
done <<<"$REC_SELFTEST"

if [[ -z "$selftest_ordinal" ]]; then
  report "SELF-TEST INTACT: job '$RESOLVER_JOB' does not run the detector's own suite. A detector nobody verified must not be the thing that decides a lane can be short-circuited."
elif has_line "$REC_COE" "${RESOLVER_JOB}${TAB}${selftest_ordinal}"; then
  report "SELF-TEST INTACT: the detector self-test step in job '$RESOLVER_JOB' carries continue-on-error. A broken detector must turn this job red, not pass quietly."
fi

# --- 5. ONE CONSUMER FORM ---------------------------------------------------
#
# A whitelist of whole shapes. Anything that mentions the output and is not one
# of these is a defect — including spellings this gate does not model, which is
# the point: an unrecognized consumer form must never read as a sanctioned one.

# The aggregator feed maps an intentional step skip to `success`. Its pattern is
# assembled from the sanctioned skip form of whichever table output gates the
# step, so the feed and the gate cannot drift apart and cannot disagree about
# WHICH output they are talking about.
feed_infix=" && 'success' || steps."
feed_suffix=".outcome }}"

refjobs=""
ref_count=0
gated_ordinals=""
feed_targets=""
while IFS="$TAB" read -r refjob reford kind text; do
  [[ -n "$refjob" ]] || continue
  ref_count=$((ref_count + 1))
  if [[ "$refjob" != "$RESOLVER_JOB" ]] && ! has_line "$refjobs" "$refjob"; then
    refjobs+="$refjob"$'\n'
  fi

  # An expression may be written bare or wrapped in ${{ }}. The single quotes
  # are the point: these are literal workflow delimiters, not shell expansions.
  bare="$text"
  # shellcheck disable=SC2016
  if [[ "$bare" == '${{ '*' }}' ]]; then
    # shellcheck disable=SC2016
    bare="${bare#'${{ '}"
    bare="${bare%' }}'}"
  fi

  case "$kind" in
  stepif)
    if ! parse_consumer_form "$bare"; then
      report "ONE CONSUMER FORM: job '$refjob' gates a step on an unsanctioned condition: if: $text"
      report "  Use \"${REFERENCE_PREFIX}<output> == 'true'\" to do the work, or \"== 'false'\" to report it not applicable, naming one of the table's outputs [$(table_names_list)]. Both are plain equality against the only two values an output can hold; a negation, a truthiness test, or an index-syntax spelling is the polarity decision this contract removes."
    elif ! table_has "$CF_NAME"; then
      report "ONE CONSUMER FORM: job '$refjob' gates a step on '$CF_NAME', which the resolver's output table does not name: if: $text. Every polarity decision belongs in the table [$(table_names_list)]; an output outside it is a decision made where this gate cannot check it."
    elif [[ "$CF_VALUE" == "true" ]]; then
      gated_ordinals+="${refjob}${TAB}${reford}${TAB}${CF_NAME}"$'\n'
    fi
    ;;
  jobif)
    # Judged in check 5c, which knows the required-lane closure. A job-level
    # read is a defect on an aggregated lane and the intended shape on a lane
    # outside it, and that distinction is not available here.
    ;;
  *)
    # An aggregator feed entry, for some table output X:
    #   <name>=${{ needs.<resolver>.outputs.X == 'false' && 'success' || steps.<id>.outcome }}
    ok_feed=0
    name=""; stepref=""; feed_output=""
    if [[ "$text" == *"=\${{ "*"$feed_infix"*"$feed_suffix" ]]; then
      name="${text%%=*}"
      rest="${text#"${name}=\${{ "}"
      skip_part="${rest%%"$feed_infix"*}"
      stepref="${rest#*"$feed_infix"}"
      stepref="${stepref%"$feed_suffix"}"
      if parse_consumer_form "$skip_part" && [[ "$CF_VALUE" == "false" ]] && table_has "$CF_NAME" &&
        [[ -n "$name" && "$text" == "${name}=\${{ ${skip_part}${feed_infix}${stepref}${feed_suffix}" &&
        "$name" != *' '* && "$stepref" != *' '* && "$stepref" != *'{'* ]]; then
        ok_feed=1
        feed_output="$CF_NAME"
      fi
    fi
    if [[ "$ok_feed" -eq 0 ]]; then
      report "ONE CONSUMER FORM: job '$refjob' reads the resolver outside a step condition and outside the aggregator feed template: $text"
    else
      feed_targets+="${refjob}${TAB}${stepref}${TAB}${name}${TAB}${feed_output}"$'\n'
    fi
    ;;
  esac

  if has_line "$REC_USES" "$refjob"; then
    report "ONE CONSUMER FORM: job '$refjob' delegates to a reusable workflow and reads $OUTPUT_NAME. Such a job has no steps of its own, so its polarity decision would live in a file this gate never opens."
  fi
done <<<"$REC_REF"

# --- 5b. THE FEED MIRRORS A REAL GATE ---------------------------------------
#
# The aggregator feed maps a step's intentional docs-only skip to `success`.
# That is only honest for a step that PROVABLY did not run — one carrying the
# work gate. An override on an ungated step would mask a genuine failure as
# success on every docs-only diff, and it fails open: forgetting an override
# feeds a raw `skipped` and reds the aggregate, but adding an unpaired one goes
# quietly green. Pin the pairing rather than trusting the two lists to stay
# aligned by eye.

gated_ids=""
while IFS="$TAB" read -r gjob gate_ord gate_out; do
  [[ -n "$gjob" ]] || continue
  while IFS="$TAB" read -r sjob step_ord sid; do
    [[ "$sjob" == "$gjob" && "$step_ord" == "$gate_ord" ]] || continue
    gated_ids+="${gjob}${TAB}${sid}${TAB}${gate_out}"$'\n'
  done <<<"$REC_STEPID"
done <<<"$gated_ordinals"

while IFS="$TAB" read -r fjob fstep fname fout; do
  [[ -n "$fjob" ]] || continue
  # Keyed on the OUTPUT as well as the step: an override that maps a skip of
  # one output onto a step gated by another is not the honest mapping, because
  # the two outputs can disagree and the step can have really run.
  if ! has_line "$gated_ids" "${fjob}${TAB}${fstep}${TAB}${fout}"; then
    report "THE FEED MIRRORS A REAL GATE: job '$fjob' maps '$fname' to success by reading step '$fstep' when '$fout' is false, but no step with that id is gated on \"${REFERENCE_PREFIX}${fout} == 'true'\". Mapping an ungated step's outcome to success hides a real failure instead of reporting a step that provably did not run, and pairing it with a DIFFERENT output would map a skip that never happened."
  fi
done <<<"$feed_targets"

# --- the required-lane closure ----------------------------------------------
#
# Everything reachable from the aggregate's `needs`, transitively, plus the
# aggregate itself. That set is exactly the lanes whose result can turn the one
# required context red, and it is what the next two checks are about: the
# hazard a job-level condition creates is that a REQUIRED lane reports success
# having run nothing, and the claim a lane-coverage opt-out makes is that the
# lane is NOT required. Neither statement means anything for a job the
# aggregate cannot see, and neither is safe for one it can.
#
# Derived from the file rather than configured, so it cannot drift from the
# needs graph it describes.

needs_of() {
  local job="$1" njob ntext entry normalized
  while IFS="$TAB" read -r njob ntext; do
    [[ "$njob" == "$job" ]] || continue
    normalized="${ntext%%#*}"
    normalized="${normalized//[/ }"
    normalized="${normalized//]/ }"
    normalized="${normalized//\"/ }"
    normalized="${normalized//\'/ }"
    normalized="${normalized//,/ }"
    for entry in $normalized; do printf '%s\n' "$entry"; done
  done <<<"$REC_NEEDSFLOW"
  while IFS="$TAB" read -r njob entry; do
    [[ "$njob" == "$job" ]] || continue
    [[ -n "$entry" ]] && printf '%s\n' "$entry"
  done <<<"$REC_NEEDSITEM"
}

required_closure=$'\n'"$AGGREGATE_JOB"$'\n'
frontier="$AGGREGATE_JOB"
while [[ -n "$frontier" ]]; do
  next_frontier=""
  while IFS= read -r fjob; do
    [[ -n "$fjob" ]] || continue
    while IFS= read -r dep; do
      [[ -n "$dep" ]] || continue
      [[ "$required_closure" == *$'\n'"$dep"$'\n'* ]] && continue
      required_closure+="$dep"$'\n'
      next_frontier+="$dep"$'\n'
    done < <(needs_of "$fjob")
  done <<<"$frontier"
  frontier="$next_frontier"
done

is_required() { [[ "$required_closure" == *$'\n'"$1"$'\n'* ]]; }

# The aggregate has to exist, or the closure is empty and both checks below
# would pass every workflow by saying nothing.
if ! has_line "$REC_JOB" "$AGGREGATE_JOB"; then
  report "NO AGGREGATE: this workflow defines no job named '$AGGREGATE_JOB', so the required-lane closure cannot be computed and neither the job-level-condition rule nor the lane opt-out rule can be judged. Rename the aggregate here if it moved."
fi

# --- 5c. NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER ----------------------
#
# A consumer reaches the published output through `needs`, so it runs only when
# the resolver succeeded — which is what makes the output's domain exactly
# {'true','false'} and the two sanctioned forms exact complements. A job-level
# condition breaks that: `if: always()` or `if: ${{ !cancelled() }}` lets the job
# run when the resolver did NOT succeed, where the output is the empty string.
# Both sanctioned forms are then false, so the work steps AND their
# not-applicable reporter all skip, and the lane goes green having done nothing.
# The condition need not mention the output to cause this, so this check does not
# look at what it says.
#
# It applies to REQUIRED consumers. A lane outside the closure cannot report
# success to branch protection at all, so a job-level condition there costs a
# skipped informational lane rather than a false green, and skipping the whole
# job is the cheaper shape: it is why a non-required Windows lane may gate at
# job level while every aggregated lane gates its steps.

while IFS= read -r refjob; do
  [[ -n "$refjob" ]] || continue
  is_required "$refjob" || continue
  while IFS="$TAB" read -r cjob ctext; do
    [[ "$cjob" == "$refjob" ]] || continue
    report "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER: job '$refjob' reads $OUTPUT_NAME, is reachable from ${AGGREGATE_JOB}.needs, and carries a job-level condition: if: $ctext. If that condition ever lets the job run when '$RESOLVER_JOB' did not succeed, $OUTPUT_NAME is the empty string, both sanctioned forms are false, and the lane reports success having run nothing. Gate the steps and let the needs edge decide whether the job runs at all."
  done <<<"$REC_JOBIF"
done <<<"$refjobs"

# --- 8. NO LANE OPT-OUT INSIDE THE CLOSURE ----------------------------------
#
# `# lane-coverage-ok: <reason>` asserts that a lane is informational and does
# not gate a merge. On a job the aggregate depends on, that assertion is simply
# false, and the danger is not the comment: it is that check-lane-coverage.sh
# stops asking whether the lane is in `needs` once it sees a marker, so a
# genuinely required lane can be annotated out of the coverage question while
# still deciding merges. Annotating a required job fails here rather than
# exempting it.

while IFS= read -r okjob; do
  [[ -n "$okjob" ]] || continue
  is_required "$okjob" || continue
  report "LANE OPT-OUT ON A REQUIRED LANE: job '$okjob' carries a '# $LANE_OPT_OUT' marker but is reachable from ${AGGREGATE_JOB}.needs, so it does gate merges and the marker's claim is false. Remove the marker, or take the job out of the aggregate's needs closure if it really is informational."
done <<<"$REC_LANEOK"

# --- 6. EDGE DECLARED -------------------------------------------------------

consumer_count=0
while IFS= read -r refjob; do
  [[ -n "$refjob" ]] || continue
  consumer_count=$((consumer_count + 1))
  declared=0
  while IFS="$TAB" read -r njob ntext; do
    [[ "$njob" == "$refjob" ]] || continue
    # `needs: [a, b]`, `needs: ['a']`, `needs: a`, each possibly with a comment.
    normalized="${ntext%%#*}"
    normalized="${normalized//[/ }"
    normalized="${normalized//]/ }"
    normalized="${normalized//\"/ }"
    normalized="${normalized//\'/ }"
    normalized="${normalized//,/ }"
    for entry in $normalized; do
      [[ "$entry" == "$RESOLVER_JOB" ]] && declared=1
    done
  done <<<"$REC_NEEDSFLOW"
  has_line "$REC_NEEDSITEM" "${refjob}${TAB}${RESOLVER_JOB}" && declared=1
  if [[ "$declared" -eq 0 ]]; then
    report "EDGE DECLARED: job '$refjob' reads $REFERENCE but does not declare '$RESOLVER_JOB' in its needs. The expression would evaluate to an empty string, skipping both the work step and its not-applicable reporter."
  fi
done <<<"$refjobs"

# --- 7. CONTRACT IS LIVE ----------------------------------------------------

if [[ "$consumer_count" -eq 0 ]]; then
  report "CONTRACT IS LIVE: job '$RESOLVER_JOB' resolves the docs-only scope but no job reads $REFERENCE. Either the consumers stopped gating (and every lane now runs unconditionally), or they read it by a spelling this gate does not recognize. Reporting a well-formed contract over zero references would be the nominal closure this gate exists to deny."
fi

# --- verdict ----------------------------------------------------------------

if [[ "$errors" -ne 0 ]]; then
  echo "check-docs-only-gate: $errors contract defect(s) in $WORKFLOW" >&2
  exit 1
fi

echo "check-docs-only-gate: $WORKFLOW — scope resolved once in '$RESOLVER_JOB'; $ref_count reference(s) across $consumer_count consumer job(s), all in the sanctioned form"
exit 0
