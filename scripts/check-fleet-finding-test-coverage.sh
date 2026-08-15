#!/usr/bin/env bash
# Gate: every finding kind audit-fleet.sh emits must have a collector-output
# assertion in audit-fleet.test.sh (the literal `Finding: <kind>` needle).
#
#   scripts/check-fleet-finding-test-coverage.sh          discover: list emitted
#                                                          kinds and whether the
#                                                          suite asserts them
#   scripts/check-fleet-finding-test-coverage.sh --check  fail if an un-grandfathered
#                                                          emitted kind has no
#                                                          Finding: assertion, or a
#                                                          baseline entry is stale
#
# Why this lives outside audit-fleet.test.sh: #2633/#2640 rewrote the test file
# alongside the collector, so the suite stayed self-consistent while dropping
# coverage. A check that only runs inside the deleted file cannot defend it
# (claude-code-plugins#2656).
#
# Substring / setup-only mentions (comments, F_KIND injection arrays) do not
# count — those previously false-greened locked-worktree. Existing coverage
# debt is grandfathered in scripts/fleet-finding-test-coverage-baseline.txt
# (exact finding-kind tokens, one per line). --check fails on a stale entry so
# the baseline cannot outlive its debt. FLEET_FINDING_COVERAGE_BASELINE /
# FLEET_FINDING_SCRIPT / FLEET_FINDING_TEST override paths (test injection and
# historical proofs).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

BASELINE="${FLEET_FINDING_COVERAGE_BASELINE:-scripts/fleet-finding-test-coverage-baseline.txt}"
SCRIPT="${FLEET_FINDING_SCRIPT:-plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh}"
TEST="${FLEET_FINDING_TEST:-plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh}"

mode="${1:-discover}"
case "$mode" in
discover | --check) ;;
*)
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
  ;;
esac

if [[ ! -f "$SCRIPT" ]]; then
  echo "check-fleet-finding-test-coverage: collector not found: $SCRIPT" >&2
  exit 2
fi
if [[ ! -f "$TEST" ]]; then
  echo "check-fleet-finding-test-coverage: test suite not found: $TEST" >&2
  exit 2
fi

emitted_tmp="$(mktemp)"
missing_tmp="$(mktemp)"
baseline_tmp="$(mktemp)"
trap 'rm -f "$emitted_tmp" "$missing_tmp" "$baseline_tmp"' EXIT

# Skip comment lines: prose in the collector names kinds while explaining them.
grep -vE "^[[:space:]]*#" "$SCRIPT" | grep -oE "emit_finding [A-Z]+ [a-z-]+" |
  awk '{print $3}' | sort -u >"$emitted_tmp"

emitted_count="$(grep -c . "$emitted_tmp" || true)"
if [[ "$emitted_count" -lt 20 ]]; then
  echo "check-fleet-finding-test-coverage: finding-kind extraction returned too few kinds ($emitted_count); the extraction, not the suite, is broken" >&2
  exit 2
fi

kind_asserted() {
  # True only when the suite asserts collector output for this kind.
  local kind="$1"
  grep -Fq -- "Finding: $kind" "$TEST"
}

: >"$missing_tmp"
while IFS= read -r kind; do
  [[ -n "$kind" ]] || continue
  if ! kind_asserted "$kind"; then
    printf '%s\n' "$kind" >>"$missing_tmp"
  fi
done <"$emitted_tmp"

declare -A baselined=()
if [[ -f "$BASELINE" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    baselined["$line"]=1
    printf '%s\n' "$line" >>"$baseline_tmp"
  done <"$BASELINE"
fi

if [[ "$mode" == "discover" ]]; then
  echo "Emitted finding kinds in $SCRIPT: $emitted_count"
  while IFS= read -r kind; do
    if kind_asserted "$kind"; then
      printf '  COVERED  %s\n' "$kind"
    elif [[ -n "${baselined[$kind]+x}" ]]; then
      printf '  BASELINE %s\n' "$kind"
    else
      printf '  MISSING  %s\n' "$kind"
    fi
  done <"$emitted_tmp"
  exit 0
fi

errors=0

while IFS= read -r kind; do
  [[ -n "$kind" ]] || continue
  if [[ -z "${baselined[$kind]+x}" ]]; then
    echo "UNCOVERED FINDING KIND: $kind (emitted by $SCRIPT, no Finding: assertion in $TEST)" >&2
    errors=$((errors + 1))
  fi
done <"$missing_tmp"

# Stale baseline: entry no longer shadows a missing kind (either covered now, or
# no longer emitted).
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  if ! grep -Fxq -- "$entry" "$emitted_tmp"; then
    echo "STALE BASELINE ENTRY: $entry (no longer emitted by $SCRIPT)" >&2
    errors=$((errors + 1))
    continue
  fi
  if kind_asserted "$entry"; then
    echo "STALE BASELINE ENTRY: $entry (now Finding:-asserted by $TEST; remove from baseline)" >&2
    errors=$((errors + 1))
  fi
done <"$baseline_tmp"

if [[ "$errors" -gt 0 ]]; then
  echo "check-fleet-finding-test-coverage: FAILED — $errors gap(s)" >&2
  exit 1
fi

echo "check-fleet-finding-test-coverage: passed — every emitted finding kind has a Finding: assertion or is grandfathered ($emitted_count kinds)"
exit 0
