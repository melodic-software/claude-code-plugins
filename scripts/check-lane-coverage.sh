#!/usr/bin/env bash
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
  echo "usage: $(basename "$0") --check [<workflow> [<aggregate-job-id> [<step-opt-out-list> [<peer-workflow-dir>]]]]" >&2
  exit 2
}

[[ "${1:-}" == "--check" ]] || usage
WORKFLOW="${2:-.github/workflows/pr-require-checks.yml}"
AGGREGATE="${3:-ci-status}"
STEP_OPT_OUTS="${4:-scripts/lane-coverage-step-opt-outs.txt}"
PEER_DIR="${5:-}"
[[ -n "$PEER_DIR" || "$WORKFLOW" != ".github/workflows/pr-require-checks.yml" ]] || PEER_DIR=".github/workflows"
[[ $# -le 5 ]] || usage

if [[ ! -f "$WORKFLOW" ]]; then
  echo "check-lane-coverage: workflow not found: $WORKFLOW" >&2
  exit 2
fi
if [[ ! -f "$STEP_OPT_OUTS" ]]; then
  echo "check-lane-coverage: step opt-out list not found: $STEP_OPT_OUTS" >&2
  exit 2
fi
if [[ -n "$PEER_DIR" && ! -d "$PEER_DIR" ]]; then
  echo "check-lane-coverage: peer workflow directory not found: $PEER_DIR" >&2
  exit 2
fi

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

records() { grep "^$1 " <<<"$parsed" || true; }

shape_errors="$(records ERR)"
if [[ -n "$shape_errors" ]]; then
  echo "check-lane-coverage: unrecognized workflow shape in $WORKFLOW" >&2
  printf '%s\n' "$shape_errors" | sed 's/^ERR /  /' >&2
  echo "  Refusing to report coverage from a file this gate did not fully parse." >&2
  exit 2
fi

jobs_all="$(records JOB | cut -d' ' -f2)"
needs_all="$(records NEED | cut -d' ' -f2)"

if [[ -z "$jobs_all" ]]; then
  echo "check-lane-coverage: no jobs parsed from $WORKFLOW" >&2
  exit 2
fi
if ! grep -Fxq "$AGGREGATE" <<<"$jobs_all"; then
  echo "check-lane-coverage: aggregate job '$AGGREGATE' is not defined in $WORKFLOW" >&2
  exit 2
fi
if ! grep -Fxq 'NEEDSBLOCK' <<<"$parsed"; then
  echo "check-lane-coverage: aggregate job '$AGGREGATE' declares no needs: block in $WORKFLOW" >&2
  exit 2
fi
if [[ -z "$needs_all" ]]; then
  echo "check-lane-coverage: aggregate job '$AGGREGATE' has an empty needs: block in $WORKFLOW" >&2
  exit 2
fi

optout_entries=()
read_list::into optout_entries "$STEP_OPT_OUTS" --comments leading || exit 2

step_optouts=""
step_optout_reasons=""
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

has_line() { case $'\n'"$1" in *$'\n'"$2"$'\n'*) return 0 ;; *) return 1 ;; esac }

errors=0
report() {
  echo "$1" >&2
  errors=$((errors + 1))
}

annotated_jobs=""
while read -r _ job flag reason; do
  [[ -n "$job" ]] || continue
  [[ "$flag" == "A" ]] && annotated_jobs+="$job"$'\n'
  [[ "$job" != "$AGGREGATE" ]] || continue

  in_needs=1
  grep -Fxq "$job" <<<"$needs_all" || in_needs=0

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
done <<<"$(records JOB)"

while IFS= read -r need; do
  [[ -n "$need" ]] || continue
  grep -Fxq "$need" <<<"$jobs_all" ||
    report "DANGLING NEED: ${AGGREGATE}.needs names '$need', which is not a job defined in $WORKFLOW."
done <<<"$needs_all"

rec_stepid="$(records STEPID)"
rec_coe="$(records COE)"
rec_feed="$(records FEED)"
rec_stepname="$(records STEPNAME)"

step_field_of() {
  local _ j o value
  while read -r _ j o value; do
    [[ "$j" == "$2" && "$o" == "$3" ]] || continue
    printf '%s' "$value"
    return
  done <<<"$1"
}

gate_steps=""
all_step_ids=""
while read -r _ j o id; do
  [[ -n "$j" ]] || continue
  all_step_ids+="$j/$id"$'\n'
done <<<"$rec_stepid"

while read -r _ j o; do
  [[ -n "$j" ]] || continue
  id="$(step_field_of "$rec_stepid" "$j" "$o")"
  if [[ -z "$id" ]]; then
    has_line "$annotated_jobs" "$j" && continue
    report "UNREADABLE GATE: job '$j' step #$o ('$(step_field_of "$rec_stepname" "$j" "$o")') carries 'continue-on-error: true' but no 'id', so its outcome cannot be read and its failure turns nothing red. Give it an id and feed it to the aggregator, or drop continue-on-error so it fails the job directly."
    continue
  fi
  gate_steps+="$j/$id"$'\n'
done <<<"$rec_coe"

feed_reads=""
while read -r _ j id; do
  [[ -n "$j" ]] || continue
  feed_reads+="$j/$id"$'\n'
done <<<"$rec_feed"

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

while IFS="$TAB" read -r entry oreason; do
  [[ -n "$entry" ]] || continue
  if [[ -z "$oreason" ]]; then
    report "BARE STEP OPT-OUT: $STEP_OPT_OUTS lists '$entry' with nothing after it. Write the reason on the entry line: '$entry  <reason>'. An opt-out without a written reason is not a documented opt-out."
  fi
  if ! has_line "$gate_steps" "$entry"; then
    report "STALE STEP OPT-OUT: $STEP_OPT_OUTS lists '$entry', but no step with that id in that job carries 'continue-on-error: true' in $WORKFLOW. Drop the entry."
  fi
done <<<"$step_optout_reasons"

check_names() {
  awk -v q="'" '
    function flush() {
      if (job != "" && !uses) { print (name != "" ? name : job) }
      job = ""; name = ""; uses = 0
    }
    /^jobs:[[:blank:]]*$/ { injobs = 1; next }
    !injobs { next }
    /^[^[:blank:]#]/ { flush(); injobs = 0; next }
    /^  [A-Za-z_][A-Za-z0-9_-]*:[[:blank:]]*(#.*)?$/ {
      flush(); job = $0; sub(/:.*$/, "", job); sub(/^  /, "", job); next
    }
    /^    uses:/ { uses = 1; next }
    /^    name:/ {
      name = $0; sub(/^    name:[[:blank:]]*/, "", name); sub(/[[:blank:]]+#.*$/, "", name)
      gsub("^[\"" q "]|[\"" q "]$", "", name)
      if (name ~ /\$\{\{/) { uses = 1 }
      next
    }
    END { flush() }
  ' "$1"
}

peer_count=0
if [[ -n "$PEER_DIR" ]]; then
  own_names="$(check_names "$WORKFLOW")"$'\n'
  for peer in "$PEER_DIR"/*.yml "$PEER_DIR"/*.yaml; do
    [[ -f "$peer" ]] || continue
    [[ "$peer" -ef "$WORKFLOW" ]] && continue
    peer_count=$((peer_count + 1))
    while IFS= read -r pname; do
      [[ -n "$pname" ]] || continue
      has_line "$own_names" "$pname" &&
        report "SHARED CHECK NAME: job '$pname' in $WORKFLOW has the same check name as a job in $peer. A required check matches by name alone, so the two results are ambiguous; rename one."
    done <<<"$(check_names "$peer")"
  done
fi

if [[ "$errors" -ne 0 ]]; then
  echo "check-lane-coverage: $errors coverage defect(s) in $WORKFLOW" >&2
  exit 1
fi

covered="$(printf '%s\n' "$needs_all" | grep -c . || true)"
fed="$(printf '%s' "$feed_reads" | grep -c . || true)"
opted="$(printf '%s' "$step_optouts" | grep -c . || true)"
echo "check-lane-coverage: $WORKFLOW — all $covered lane(s) reachable from ${AGGREGATE}.needs; all $fed gate step(s) fed to the aggregator, $opted opted out; no check name shared with $peer_count peer workflow(s)"
exit 0
