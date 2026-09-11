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
# count. Existing coverage debt is grandfathered in
# scripts/fleet-finding-test-coverage-baseline.txt
# (exact finding-kind tokens, one per line). --check fails on a stale entry so
# the baseline cannot outlive its debt. FLEET_FINDING_COVERAGE_BASELINE /
# FLEET_FINDING_SCRIPT / FLEET_FINDING_TEST override paths (test injection and
# historical proofs).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

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
trap 'rm -f "$emitted_tmp"' EXIT

# The collector owns its finding-kind list and publishes it as data
# (--print-finding-registry, first tab-separated column). Ask it, rather than
# pattern-matching its source: a registry the emitters, the action predicates
# and the reference table already read is the same list this gate needs, and a
# regex over call sites goes quietly empty the moment the emitter's argument
# shape changes.
#
# A collector predating that mode answers nothing, so the gate falls back to
# scraping emit_finding call sites, which is the list such a tree encodes. The
# fallback announces itself: it is for the historical proofs, and a live tree
# whose registry mode broke must not be mistaken for an old one.
if bash "$SCRIPT" --print-finding-registry 2>/dev/null |
  awk -F'\t' 'NF > 0 && $1 != "" {print $1}' | sort -u >"$emitted_tmp" &&
  [[ -s "$emitted_tmp" ]]; then
  kind_source="--print-finding-registry"
else
  kind_source="emit_finding call sites (collector has no --print-finding-registry)"
  echo "check-fleet-finding-test-coverage: $SCRIPT does not answer --print-finding-registry; falling back to source scraping" >&2
  # Skip comment lines: prose in the collector names kinds while explaining them.
  grep -vE "^[[:space:]]*#" "$SCRIPT" | grep -oE "emit_finding [A-Z]+ [a-z-]+" |
    awk '{print $3}' | sort -u >"$emitted_tmp"
fi

emitted_count="$(grep -c . "$emitted_tmp" || true)"
if [[ "$emitted_count" -lt 20 ]]; then
  echo "check-fleet-finding-test-coverage: finding-kind extraction returned too few kinds ($emitted_count via $kind_source); the extraction, not the suite, is broken" >&2
  exit 2
fi

kind_asserted() {
  # True only when the suite asserts collector output for this exact kind.
  # Anchor the trailing boundary so Finding: worktree-root-conformance does not
  # false-cover via Finding: worktree-root-conformance-summary (#2656 review).
  local kind="$1"
  grep -Eq -- "Finding: ${kind}([^a-z-]|$)" "$TEST"
}

declare -A baselined=()
baseline_entries=()
if [[ -f "$BASELINE" ]]; then
  # `inline`: entries are finding-kind tokens, never regexes, so a `#` anywhere
  # on the line opens the reason comment (scripts/lib/read-list.sh owns the two
  # comment families and why they must stay distinct).
  read_list::into baseline_entries "$BASELINE" --comments inline || exit 2
  for line in ${baseline_entries[@]+"${baseline_entries[@]}"}; do
    baselined["$line"]=1
  done
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
  kind_asserted "$kind" && continue
  if [[ -z "${baselined[$kind]+x}" ]]; then
    echo "UNCOVERED FINDING KIND: $kind (emitted by $SCRIPT, no Finding: assertion in $TEST)" >&2
    errors=$((errors + 1))
  else
    # The entry is shadowing a real gap right now, so it has not outlived what
    # it excuses. scripts/lib/read-list.sh owns the consumed-set.
    read_list::mark_used "$kind"
  fi
done <"$emitted_tmp"

# Stale baseline: entry no longer shadows a missing kind (either covered now, or
# no longer emitted). The two reasons differ per entry, so the report goes
# through the library's diagnostic line rather than its uniform reporter.
stale_entries=()
read_list::stale_to stale_entries baseline_entries
for entry in ${stale_entries[@]+"${stale_entries[@]}"}; do
  if grep -Fxq -- "$entry" "$emitted_tmp"; then
    read_list::stale_line "$BASELINE" "$entry" "is now Finding:-asserted by $TEST; remove it"
  else
    read_list::stale_line "$BASELINE" "$entry" "is no longer emitted by $SCRIPT"
  fi
  errors=$((errors + 1))
done

if [[ "$errors" -gt 0 ]]; then
  echo "check-fleet-finding-test-coverage: FAILED — $errors gap(s)" >&2
  exit 1
fi

echo "check-fleet-finding-test-coverage: passed — every emitted finding kind has a Finding: assertion or is grandfathered ($emitted_count kinds)"
exit 0
