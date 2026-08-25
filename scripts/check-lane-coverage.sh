#!/usr/bin/env bash
# Gate: every job defined in the CI workflow must be reachable from the required
# aggregate's `needs` graph, or carry a written reason for staying out of it.
#
#   scripts/check-lane-coverage.sh --check [<workflow> [<aggregate-job-id>]]
#
# Defaults: .github/workflows/ci.yml and the `ci-status` aggregate.
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
# WHAT IS CHECKED (all four directions, so the two sets are provably equal):
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
# THE OPT-OUT. A job that legitimately does not belong in the required aggregate
# — advisory by design, or driven by an event the merge gate never sees —
# records that decision inline:
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
# The aggregate job itself is exempt by construction — it cannot depend on
# itself — via AGGREGATE below, not via a silent filter.
#
# FAIL CLOSED ON SHAPE. This reads the workflow structurally with awk rather
# than through a YAML library (the repo ships no root YAML dependency, and the
# only workflow parser in the tree, .github/standards/runner-policy, is an
# org-owned standards materialization this repo does not edit). Every YAML shape
# it does not recognize — a flow-sequence `needs: [a, b]`, a scalar `needs: x`,
# an aggregate with no `needs:` at all, a 2-space key under `jobs:` that is not a
# plain job id — exits 2 (inconclusive), never 0. Returning an empty lane set on
# an unparsed file would be this gate committing the very defect it detects.
#
# Exit: 0 covered; 1 a coverage defect; 2 usage, missing file, or unrecognized
# workflow shape.
set -uo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "check-lane-coverage: not inside a git work tree" >&2
  exit 2
fi
cd "$(git rev-parse --show-toplevel)" || exit 2

usage() {
  echo "usage: $(basename "$0") --check [<workflow> [<aggregate-job-id>]]" >&2
  exit 2
}

[[ "${1:-}" == "--check" ]] || usage
WORKFLOW="${2:-.github/workflows/ci.yml}"
AGGREGATE="${3:-ci-status}"
[[ $# -le 3 ]] || usage

if [[ ! -f "$WORKFLOW" ]]; then
  echo "check-lane-coverage: workflow not found: $WORKFLOW" >&2
  exit 2
fi

# One structural pass. Emits three record kinds on stdout:
#   JOB <id> <A|N> <reason...>   A = annotated opt-out (reason may be empty)
#   NEED <id>
#   ERR <message>
parsed="$(
  awk -v agg="$AGGREGATE" '
    function reset_ann() { ann = 0; reason = "" }
    BEGIN { injobs = 0; seen_jobs = 0; job = ""; needs_state = 0; reset_ann() }

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
      next
    }

    { reset_ann() }

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

errors=0
report() {
  echo "$1" >&2
  errors=$((errors + 1))
}

while read -r _ job flag reason; do
  [[ -n "$job" ]] || continue
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

if [[ "$errors" -ne 0 ]]; then
  echo "check-lane-coverage: $errors coverage defect(s) in $WORKFLOW" >&2
  exit 1
fi

covered="$(printf '%s\n' "$needs_all" | grep -c . || true)"
echo "check-lane-coverage: $WORKFLOW — all $covered lane(s) reachable from ${AGGREGATE}.needs"
exit 0
