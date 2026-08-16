#!/usr/bin/env bash
# Self-test for scripts/check-lane-coverage.sh
#
# Fixtures are plain files under mktemp, addressed by ABSOLUTE path: the script
# cds to the git toplevel, so an absolute fixture path resolves from anywhere and
# no scratch git repo is needed. That is deliberate — a fixture repo would need
# `git -C <dir> config user.*`, and the un-scoped form of that command writes the
# test identity into the CALLER's repo config (claude-code-plugins#2839). No git
# state means the class cannot recur here.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-lane-coverage.sh"
failures=0

ok() { printf 'ok - %s\n' "$1"; }
fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# Runs the gate and asserts exit code plus (optionally) a substring of output.
expect() {
  local label="$1" want_rc="$2" want_text="$3"
  shift 3
  local out rc
  out="$(bash "$SCRIPT" "$@" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
    return
  fi
  if [[ -n "$want_text" && "$out" != *"$want_text"* ]]; then
    fail "$label: expected output to contain '$want_text', got '$out'"
    return
  fi
  ok "$label"
}

# --- fixture builders -------------------------------------------------------

# A minimal but structurally faithful workflow: two lanes, an aggregate, and a
# body shaped like the real file (comments, block scalars, nested `if:` keys).
write_workflow() {
  local path="$1" extra_job_block="$2" needs_block="$3"
  cat >"$path" <<YAML
name: ci

on:
  pull_request:

permissions:
  contents: read

jobs:
  # A leading comment block, the way the real file carries them.
  alpha:
    runs-on: ubuntu-24.04
    steps:
      - name: Do a thing
        run: |
          echo "  not-a-job: this line lives inside a block scalar"
          echo done

  beta:
    runs-on: ubuntu-24.04
    if: github.event_name == 'pull_request'
    steps:
      - name: Do another thing
        run: echo ok
${extra_job_block}
  ci-status:
${needs_block}
    if: \${{ !cancelled() }}
    runs-on: ubuntu-24.04
    steps:
      - name: Aggregate lane results
        run: echo aggregated
YAML
}

needs_of() {
  printf '    needs:\n'
  local n
  for n in "$@"; do printf '      - %s\n' "$n"; done
}

# --- usage / input errors ---------------------------------------------------

expect "bare invocation exits 2 with usage" 2 "usage:"
expect "unknown mode exits 2 with usage" 2 "usage:" --verify
expect "missing workflow exits 2" 2 "workflow not found" --check "$scratch/nope.yml"
expect "excess arguments exit 2" 2 "usage:" --check "$scratch/nope.yml" ci-status extra

printf 'name: ci\non:\n  pull_request:\n' >"$scratch/nojobs.yml"
expect "workflow with no jobs mapping exits 2" 2 "no jobs: mapping found" --check "$scratch/nojobs.yml"

# --- the defect this gate exists to catch -----------------------------------

write_workflow "$scratch/ungated.yml" "" "$(needs_of alpha)"
expect "job absent from needs fails and names the job" 1 "UNGATED LANE: job 'beta'" \
  --check "$scratch/ungated.yml"

write_workflow "$scratch/covered.yml" "" "$(needs_of alpha beta)"
expect "every job in needs passes" 0 "all 2 lane(s) reachable" --check "$scratch/covered.yml"

# --- the opt-out path -------------------------------------------------------

write_workflow "$scratch/optout.yml" "" "$(needs_of alpha)"
# Annotate `beta` via the contiguous comment block immediately above its key.
annotate_above() {
  local file="$1" job="$2" comment="$3"
  awk -v job="  ${job}:" -v c="$comment" '
    $0 == job { print c } { print }
  ' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
}
annotate_above "$scratch/optout.yml" beta "  # lane-coverage-ok: advisory lane, findings routed to code scanning"
expect "annotated opt-out passes" 0 "all 1 lane(s) reachable" --check "$scratch/optout.yml"

write_workflow "$scratch/bare-optout.yml" "" "$(needs_of alpha)"
annotate_above "$scratch/bare-optout.yml" beta "  # lane-coverage-ok:"
expect "opt-out with no reason fails" 1 "BARE OPT-OUT: job 'beta'" --check "$scratch/bare-optout.yml"

write_workflow "$scratch/trailing-optout.yml" "" "$(needs_of alpha)"
awk '{ sub(/^  beta:$/, "  beta:  # lane-coverage-ok: deliberately advisory"); print }' \
  "$scratch/trailing-optout.yml" >"$scratch/trailing-optout.yml.tmp" &&
  mv "$scratch/trailing-optout.yml.tmp" "$scratch/trailing-optout.yml"
expect "trailing-comment opt-out passes" 0 "all 1 lane(s) reachable" --check "$scratch/trailing-optout.yml"

write_workflow "$scratch/stale-optout.yml" "" "$(needs_of alpha beta)"
annotate_above "$scratch/stale-optout.yml" beta "  # lane-coverage-ok: no longer true"
expect "opt-out on a job that IS in needs fails as stale" 1 "STALE OPT-OUT: job 'beta'" \
  --check "$scratch/stale-optout.yml"

# An annotation separated from its job key by a blank line must NOT carry over.
write_workflow "$scratch/detached-optout.yml" "" "$(needs_of alpha)"
awk '
  $0 == "  beta:" { print "  # lane-coverage-ok: this comment is not contiguous"; print "" }
  { print }
' "$scratch/detached-optout.yml" >"$scratch/detached-optout.yml.tmp" &&
  mv "$scratch/detached-optout.yml.tmp" "$scratch/detached-optout.yml"
expect "non-contiguous annotation does not exempt the job" 1 "UNGATED LANE: job 'beta'" \
  --check "$scratch/detached-optout.yml"

# --- dangling needs ---------------------------------------------------------

write_workflow "$scratch/dangling.yml" "" "$(needs_of alpha beta gamma)"
expect "needs entry with no defined job fails" 1 "DANGLING NEED" --check "$scratch/dangling.yml"

# --- unrecognized shapes must be inconclusive, never green ------------------

write_workflow "$scratch/flow-needs.yml" "" "    needs: [alpha, beta]"
expect "flow-sequence needs exits 2, not 0" 2 "not a block sequence" --check "$scratch/flow-needs.yml"

write_workflow "$scratch/scalar-needs.yml" "" "    needs: alpha"
expect "scalar needs exits 2, not 0" 2 "not a block sequence" --check "$scratch/scalar-needs.yml"

write_workflow "$scratch/no-needs.yml" "" "    permissions:
      contents: read"
expect "aggregate with no needs block exits 2" 2 "declares no needs: block" --check "$scratch/no-needs.yml"

write_workflow "$scratch/empty-needs.yml" "" "    needs:
"
expect "aggregate with an empty needs block exits 2" 2 "empty needs: block" --check "$scratch/empty-needs.yml"

write_workflow "$scratch/odd-key.yml" "  &anchor-not-a-job:
    runs-on: ubuntu-24.04
" "$(needs_of alpha beta)"
expect "unmodelled 2-space key exits 2" 2 "unrecognized key under jobs" --check "$scratch/odd-key.yml"

write_workflow "$scratch/missing-agg.yml" "" "$(needs_of alpha beta)"
expect "unknown aggregate job exits 2" 2 "is not defined" --check "$scratch/missing-agg.yml" no-such-job

# --- the real workflow ------------------------------------------------------

expect "the repository's own ci.yml is fully covered" 0 "reachable from ci-status.needs" --check

if [[ $failures -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
fi
echo "$failures failure(s)" >&2
exit 1
