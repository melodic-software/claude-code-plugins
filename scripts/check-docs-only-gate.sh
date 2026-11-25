#!/usr/bin/env bash
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
WORKFLOW="${2:-.github/workflows/pr-require-checks.yml}"
[[ $# -le 2 ]] || usage

if [[ ! -f "$WORKFLOW" ]]; then
  echo "check-docs-only-gate: workflow not found: $WORKFLOW" >&2
  exit 2
fi

TAB="$(printf '\t')"
RESOLVER_JOB="select-tests"
DETECT_STEP_ID="detect"
OUTPUT_NAME="run_full"
OUTPUT_TABLE="\
run_full${TAB}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' }}
run_tests${TAB}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' && github.event.pull_request.draft != true }}
run_bash${TAB}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' && github.event.pull_request.draft != true && steps.plan.outputs.bash != 'false' }}
run_python${TAB}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' && github.event.pull_request.draft != true && steps.plan.outputs.python != 'false' }}
run_node${TAB}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' && github.event.pull_request.draft != true && steps.plan.outputs.node != 'false' }}
run_shell${TAB}\${{ github.event.pull_request.draft != true && fromJSON(steps.match.outputs.results || '{}')['lint_shell'] != 'false' }}
run_check_tests${TAB}\${{ steps.base.outputs.ref == '' }}
run_selection${TAB}\${{ steps.base.outputs.ref != '' && github.event.pull_request.draft != true && steps.suites.outputs.any != 'false' }}
run_workflows${TAB}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' && fromJSON(steps.match.outputs.results || '{}')['workflows'] != 'false' }}
run_skill_checker${TAB}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' && github.event.pull_request.draft != true && fromJSON(steps.match.outputs.results || '{}')['skill_checker'] != 'false' }}
run_manifests${TAB}\${{ steps.${DETECT_STEP_ID}.outputs.docs_only != 'true' && fromJSON(steps.match.outputs.results || '{}')['manifests'] != 'false' }}"
DATA_TABLE="\
lane_base${TAB}\${{ steps.base.outputs.ref }}
standards_sha${TAB}\${{ steps.standards.outputs.sha }}
bash_legs${TAB}\${{ steps.plan.outputs.bash_legs }}
bash_plan${TAB}\${{ steps.plan.outputs.bash_plan }}
bash_needs${TAB}\${{ steps.plan.outputs.bash_needs }}
python_legs${TAB}\${{ steps.plan.outputs.python_legs }}
python_plan${TAB}\${{ steps.plan.outputs.python_plan }}
python_needs${TAB}\${{ steps.plan.outputs.python_needs }}
node_legs${TAB}\${{ steps.plan.outputs.node_legs }}
node_plan${TAB}\${{ steps.plan.outputs.node_plan }}
selection_suites${TAB}\${{ steps.suites.outputs.list }}
playwright_cache_key${TAB}\${{ steps.playwright_key.outputs.key }}"
MATRIX_READS="\
leg: \${{ fromJSON(needs.${RESOLVER_JOB}.outputs.bash_legs || '[0]') }}
leg: \${{ fromJSON(needs.${RESOLVER_JOB}.outputs.python_legs || '[0]') }}
leg: \${{ fromJSON(needs.${RESOLVER_JOB}.outputs.node_legs || '[0]') }}"
AGGREGATE_JOB="ci-status"
LANE_OPT_OUT="lane-coverage-ok:"
CONTRACT_ONLY_PREDICATE="github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('[\"labeled\",\"unlabeled\"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base))"
JOB_GATE="\${{ !(${CONTRACT_ONLY_PREDICATE}) }}"
JOB_GATE_DRAFT="\${{ !(${CONTRACT_ONLY_PREDICATE}) && github.event.pull_request.draft != true }}"
job_gate_skip() { printf '%s' "\${{ !(${CONTRACT_ONLY_PREDICATE}) && github.event.pull_request.draft != true && needs.${RESOLVER_JOB}.outputs.run_$1 == 'true' }}"; }
SKIP_CHECK_STEP_ID="lanes"
SKIP_CHECKED_RESULTS="\${{ steps.${SKIP_CHECK_STEP_ID}.outputs.results }}"
REFERENCE_PREFIX="needs.${RESOLVER_JOB}.outputs."
REFERENCE="${REFERENCE_PREFIX}${OUTPUT_NAME}"

row_names() {
  local tn out=""
  while IFS="$TAB" read -r tn _; do
    [[ -n "$tn" ]] || continue
    out+="${out:+$2}$tn"
  done <<<"$1"
  printf '%s' "$out"
}
table_names() { row_names "$OUTPUT_TABLE" "$1"; }
data_names() { row_names "$DATA_TABLE" "$1"; }

errors=0
report() {
  echo "$1" >&2
  errors=$((errors + 1))
}

parsed="$(
  awk -v resolver="$RESOLVER_JOB" -v output_names="$(table_names ' ') $(data_names ' ')" -v lane_opt_out="$LANE_OPT_OUT" '
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
    function mentions_output(line,   l, i) {
      l = tolower(line)
      for (i = 1; i <= n_outnames; i++) {
        if (index(l, outnames[i]) > 0) { return 1 }
      }
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
      # Every table name, so a BARE mention of any output — in an env value, an
      # echo, a run script — reaches the exact-shape check rather than being
      # invisible to it. Matching only the root output would have delivered the
      # over-matching this header promises for one row out of seven.
      n_outnames = split(tolower(output_names), outnames, " ")
      if (resolver_lc == "" || n_outnames == 0) {
        print "ERR\tinternal: resolver job or output names were not supplied to the parser"
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

      if ($0 ~ /^[[:blank:]]+treat-skipped-as:/) {
        sk = $0
        sub(/^[[:blank:]]+treat-skipped-as:[[:blank:]]*/, "", sk)
        print "SKIPAS\t" job "\t" uncommented(sk)
      }
      if ($0 ~ /^[[:blank:]]+results:/) {
        rv = $0
        sub(/^[[:blank:]]+results:[[:blank:]]*/, "", rv)
        print "RESULTSIN\t" job "\t" uncommented(rv)
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

REC_ERR=""
REC_JOB=""
REC_USES=""
REC_NEEDSFLOW=""
REC_NEEDSITEM=""
REC_OUTPUT=""
REC_INVOKE=""
REC_SELFTEST=""
REC_COE=""
REC_STEPID=""
REC_REF=""
REC_STEPOUT=""
REC_JOBIF=""
REC_LANEOK=""
REC_SKIPAS=""
REC_RESULTSIN=""
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
  "SKIPAS$TAB"*) REC_SKIPAS+="${line#*"$TAB"}"$'\n' ;;
  "RESULTSIN$TAB"*) REC_RESULTSIN+="${line#*"$TAB"}"$'\n' ;;
  *)
    echo "check-docs-only-gate: unrecognized internal record: $line" >&2
    exit 2
    ;;
  esac
done <<<"$parsed"

has_line() { case $'\n'"$1" in *$'\n'"$2"$'\n'*) return 0 ;; *) return 1 ;; esac }

table_has() { [[ $'\n'"$OUTPUT_TABLE" == *$'\n'"$1$TAB"* ]]; }
data_has() { [[ $'\n'"$DATA_TABLE" == *$'\n'"$1$TAB"* ]]; }

is_data_read() {
  local t="$1" key rest name
  # shellcheck disable=SC2016 # `${{ }}` is a literal workflow delimiter here.
  [[ "$t" == *': ${{ '"$REFERENCE_PREFIX"*' }}' ]] || return 1
  key="${t%%: *}"
  [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || return 1
  rest="${t#"$key: \${{ $REFERENCE_PREFIX"}"
  name="${rest%' }}'}"
  [[ "$t" == "$key: \${{ ${REFERENCE_PREFIX}${name} }}" ]] || return 1
  data_has "$name"
}

CF_NAME=""
CF_VALUE=""
parse_consumer_form() {
  local t="$1" rest
  CF_NAME=""
  CF_VALUE=""
  [[ "$t" == "${REFERENCE_PREFIX}"* ]] || return 1
  rest="${t#"$REFERENCE_PREFIX"}"
  CF_NAME="${rest%% *}"
  [[ -n "$CF_NAME" && "$CF_NAME" != *[^A-Za-z0-9_-]* ]] || {
    CF_NAME=""
    return 1
  }
  rest="${rest#"$CF_NAME"}"
  case "$rest" in
  " == 'true'") CF_VALUE="true" ;;
  " == 'false'") CF_VALUE="false" ;;
  *)
    CF_NAME=""
    return 1
    ;;
  esac
  return 0
}

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

if [[ -n "$REC_ERR" ]]; then
  echo "check-docs-only-gate: unrecognized workflow shape in $WORKFLOW" >&2
  while IFS= read -r msg; do
    [[ -n "$msg" ]] || continue
    echo "  $msg" >&2
  done <<<"$REC_ERR"
  echo "  Refusing to report a satisfied contract from a file this gate did not fully parse." >&2
  exit 2
fi

if [[ -z "$REC_JOB" ]]; then
  echo "check-docs-only-gate: no jobs parsed from $WORKFLOW" >&2
  exit 2
fi
if ! has_line "$REC_JOB" "$RESOLVER_JOB"; then
  echo "check-docs-only-gate: resolving job '$RESOLVER_JOB' is not defined in $WORKFLOW" >&2
  exit 2
fi
if ! has_line "$REC_JOB" "$AGGREGATE_JOB"; then
  echo "check-docs-only-gate: aggregate job '$AGGREGATE_JOB' is not defined in $WORKFLOW, so the required-lane closure cannot be computed" >&2
  exit 2
fi

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

stray_stepouts=""
while IFS= read -r sjob; do
  [[ -n "$sjob" ]] || continue
  [[ "$sjob" == "$RESOLVER_JOB" ]] && continue
  stray_stepouts+="$sjob"$'\n'
done <<<"$REC_STEPOUT"
if [[ -n "$stray_stepouts" ]]; then
  report "SINGLE RESOLUTION: a step-level docs_only output is still read in job(s) [$(uniq_list "$stray_stepouts")]. Consumers must read $REFERENCE, never a per-job step output."
fi

find_published() {
  local ojob oname oexpr found=1
  published_expr=""
  while IFS="$TAB" read -r ojob oname oexpr; do
    [[ "$ojob" == "$RESOLVER_JOB" && "$oname" == "$1" ]] || continue
    found=0
    published_expr="$oexpr"
  done <<<"$REC_OUTPUT"
  return "$found"
}

while IFS="$TAB" read -r tname texpr; do
  [[ -n "$tname" ]] || continue
  if ! find_published "$tname"; then
    report "FAIL-CLOSED DEFAULT: job '$RESOLVER_JOB' publishes no '$tname' output. Consumers would read an empty string, which skips both the work step and its not-applicable reporter."
  elif [[ "$published_expr" != "$texpr" ]]; then
    report "FAIL-CLOSED DEFAULT: job '$RESOLVER_JOB' publishes '$tname: $published_expr', expected exactly '$tname: $texpr'. That expression is the contract: an UNSET detector output (the detector never ran, or failed) renders as 'true', so the full suite runs, and every narrowing clause compares != 'false' so an unset filter group runs its lane too. Any other derivation can resolve an unset input toward skipping."
  fi
done <<<"$OUTPUT_TABLE"

while IFS="$TAB" read -r tname texpr; do
  [[ -n "$tname" ]] || continue
  if ! find_published "$tname"; then
    report "DATA IS NOT A GATE: job '$RESOLVER_JOB' publishes no '$tname' data output; expected exactly '$tname: $texpr'."
  elif [[ "$published_expr" != "$texpr" ]]; then
    report "DATA IS NOT A GATE: job '$RESOLVER_JOB' publishes '$tname: $published_expr', expected exactly '$tname: $texpr'. A data output passes its step's value through unchanged; an expression around it is a decision this gate does not model."
  fi
done <<<"$DATA_TABLE"

while IFS="$TAB" read -r ojob oname oexpr; do
  [[ "$ojob" == "$RESOLVER_JOB" ]] || continue
  [[ -n "$oname" ]] || continue
  table_has "$oname" && continue
  data_has "$oname" && continue
  report "FAIL-CLOSED DEFAULT: job '$RESOLVER_JOB' publishes '$oname', which neither the output table nor the data table names. Every polarity decision belongs in the table [$(table_names ', ')] and every value in [$(data_names ', ')]; an extra output is a decision this gate cannot check, and consumers reading it are invisible to the consumer-form rule."
done <<<"$REC_OUTPUT"

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

feed_infix=" && 'success' || steps."
feed_suffix=".outcome }}"

is_value_read() {
  [[ "$1" != stepif && "$1" != jobif ]] && { is_data_read "$2" || has_line "$MATRIX_READS"$'\n' "$2"; }
}

refjobs=""
gate_refjobs=""
ref_count=0
gated_ordinals=""
feed_targets=""
while IFS="$TAB" read -r refjob reford kind text; do
  [[ -n "$refjob" ]] || continue
  ref_count=$((ref_count + 1))
  if [[ "$refjob" != "$RESOLVER_JOB" ]] && ! has_line "$refjobs" "$refjob"; then
    refjobs+="$refjob"$'\n'
  fi
  if [[ "$refjob" != "$RESOLVER_JOB" ]] && ! is_value_read "$kind" "$text" && ! has_line "$gate_refjobs" "$refjob"; then
    gate_refjobs+="$refjob"$'\n'
  fi

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
      report "  Use \"${REFERENCE_PREFIX}<output> == 'true'\" to do the work, or \"== 'false'\" to report it not applicable, naming one of the table's outputs [$(table_names ', ')]. Both are plain equality against the only two values an output can hold; a negation, a truthiness test, or an index-syntax spelling is the polarity decision this contract removes."
    elif ! table_has "$CF_NAME"; then
      report "ONE CONSUMER FORM: job '$refjob' gates a step on '$CF_NAME', which the resolver's output table does not name: if: $text. Every polarity decision belongs in the table [$(table_names ', ')]; an output outside it is a decision made where this gate cannot check it."
    elif [[ "$CF_VALUE" == "true" ]]; then
      gated_ordinals+="${refjob}${TAB}${reford}${TAB}${CF_NAME}"$'\n'
    fi
    ;;
  jobif)
    for dn in $(data_names ' '); do
      if [[ "$bare" == *"${REFERENCE_PREFIX}${dn}"* ]]; then
        report "DATA IS NOT A GATE: job '$refjob' conditions the job on the data output '$dn': if: $text. Its value is not a polarity decision; read it in an env entry and let the script branch on it."
      fi
    done
    ;;
  *)
    if is_value_read "$kind" "$text"; then
      continue
    fi
    ok_feed=0
    name=""
    stepref=""
    feed_output=""
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
  if ! has_line "$gated_ids" "${fjob}${TAB}${fstep}${TAB}${fout}"; then
    report "THE FEED MIRRORS A REAL GATE: job '$fjob' maps '$fname' to success by reading step '$fstep' when '$fout' is false, but no step with that id is gated on \"${REFERENCE_PREFIX}${fout} == 'true'\". Mapping an ungated step's outcome to success hides a real failure instead of reporting a step that provably did not run, and pairing it with a DIFFERENT output would map a skip that never happened."
  fi
done <<<"$feed_targets"

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

skip_lanes=""
while IFS= read -r refjob; do
  [[ -n "$refjob" ]] || continue
  is_required "$refjob" || continue
  while IFS="$TAB" read -r cjob ctext; do
    [[ "$cjob" == "$refjob" ]] || continue
    [[ "$ctext" == "$JOB_GATE" || "$ctext" == "$JOB_GATE_DRAFT" ]] && continue
    lane="${refjob#test-}"
    [[ "$refjob" == lint-shell ]] && lane=shell
    [[ "$refjob" == check-tests ]] && lane=check_tests
    if [[ "$refjob" == test-* || "$refjob" == lint-shell || "$refjob" == check-tests ]] && table_has "run_$lane" &&
      [[ "$ctext" == "$(job_gate_skip "$lane")" ]]; then
      skip_lanes+="$refjob"$'\n'
      continue
    fi
    report "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER: job '$refjob' reads $OUTPUT_NAME, is reachable from ${AGGREGATE_JOB}.needs, and carries a job-level condition that is not the contract-only gate: if: $ctext. If that condition ever lets the job run when '$RESOLVER_JOB' did not succeed, $OUTPUT_NAME is the empty string, both sanctioned forms are false, and the lane reports success having run nothing. Gate the steps and let the needs edge decide whether the job runs at all. The only sanctioned job-level conditions here are exactly: $JOB_GATE, or $JOB_GATE_DRAFT, or on a job test-<x> (or lint-shell, row shell; check-tests, row check_tests) whose run_<x> row the table names: $(job_gate_skip '<x>')"
  done <<<"$REC_JOBIF"
done <<<"$gate_refjobs"

if [[ -n "$skip_lanes" ]]; then
  agg_results="$(awk -F '\t' -v j="$AGGREGATE_JOB" '$1 == j { print $2 }' <<<"$REC_RESULTSIN")"
  if [[ "$agg_results" != "$SKIP_CHECKED_RESULTS" ]]; then
    report "A SKIP IS CHECKED: lane(s) [$(uniq_list "$skip_lanes")] skip on their own row, but job '$AGGREGATE_JOB' aggregates results: ${agg_results:-<none>}. It must read exactly $SKIP_CHECKED_RESULTS, the step that passes a skip only where '$RESOLVER_JOB' said the lane had no work."
  fi
  if ! awk -F '\t' -v j="$AGGREGATE_JOB" -v id="$SKIP_CHECK_STEP_ID" '$1 == j && $3 == id { f = 1 } END { exit !f }' <<<"$REC_STEPID"; then
    report "A SKIP IS CHECKED: lane(s) [$(uniq_list "$skip_lanes")] skip on their own row, but job '$AGGREGATE_JOB' has no step 'id: $SKIP_CHECK_STEP_ID' to check those skips against '$RESOLVER_JOB'."
  fi
fi

SKIP_AS_DRAFT="\${{ github.event.pull_request.draft && 'pass' || 'fail' }}"
skipas_seen=0
while IFS="$TAB" read -r sjob svalue; do
  [[ -n "$sjob" ]] || continue
  [[ "$sjob" == "$AGGREGATE_JOB" ]] || continue
  skipas_seen=1
  [[ "$svalue" == "fail" || "$svalue" == "$SKIP_AS_DRAFT" ]] && continue
  report "A SKIPPED LANE NEVER PASSES: job '$AGGREGATE_JOB' sets treat-skipped-as: $svalue. Use 'fail' or exactly $SKIP_AS_DRAFT."
done <<<"$REC_SKIPAS"
if [[ "$skipas_seen" -eq 0 ]] &&
  awk -F '\t' -v j="$JOB_GATE_DRAFT" '$2 == j { f = 1 } END { exit !f }' <<<"$REC_JOBIF"; then
  report "A SKIPPED LANE NEVER PASSES: a lane carries the draft gate but job '$AGGREGATE_JOB' sets no treat-skipped-as, whose default passes a skip. Set it to 'fail' or exactly $SKIP_AS_DRAFT."
fi

while IFS= read -r okjob; do
  [[ -n "$okjob" ]] || continue
  is_required "$okjob" || continue
  report "LANE OPT-OUT ON A REQUIRED LANE: job '$okjob' carries a '# $LANE_OPT_OUT' marker but is reachable from ${AGGREGATE_JOB}.needs, so it does gate merges and the marker's claim is false. Remove the marker, or take the job out of the aggregate's needs closure if it really is informational."
done <<<"$REC_LANEOK"

consumer_count=0
while IFS= read -r refjob; do
  [[ -n "$refjob" ]] || continue
  consumer_count=$((consumer_count + 1))
  declared=0
  deps="$(needs_of "$refjob")"
  while IFS= read -r entry; do
    [[ "$entry" == "$RESOLVER_JOB" ]] && declared=1
  done <<<"$deps"
  if [[ "$declared" -eq 0 ]]; then
    report "EDGE DECLARED: job '$refjob' reads $REFERENCE but does not declare '$RESOLVER_JOB' in its needs. The expression would evaluate to an empty string, skipping both the work step and its not-applicable reporter."
  fi
done <<<"$refjobs"

if [[ "$consumer_count" -eq 0 ]]; then
  report "CONTRACT IS LIVE: job '$RESOLVER_JOB' resolves the docs-only scope but no job reads $REFERENCE. Either the consumers stopped gating (and every lane now runs unconditionally), or they read it by a spelling this gate does not recognize. Reporting a well-formed contract over zero references would be the nominal closure this gate exists to deny."
fi

if [[ "$errors" -ne 0 ]]; then
  echo "check-docs-only-gate: $errors contract defect(s) in $WORKFLOW" >&2
  exit 1
fi

echo "check-docs-only-gate: $WORKFLOW — scope resolved once in '$RESOLVER_JOB'; $ref_count reference(s) across $consumer_count consumer job(s), all in the sanctioned form"
exit 0
