#!/usr/bin/env bash
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

if bash "$SCRIPT" --print-finding-registry 2>/dev/null |
  awk -F'\t' 'NF > 0 && $1 != "" {print $1}' | sort -u >"$emitted_tmp" &&
  [[ -s "$emitted_tmp" ]]; then
  kind_source="--print-finding-registry"
else
  kind_source="emit_finding call sites (collector has no --print-finding-registry)"
  echo "check-fleet-finding-test-coverage: $SCRIPT does not answer --print-finding-registry; falling back to source scraping" >&2
  grep -vE "^[[:space:]]*#" "$SCRIPT" | grep -oE "emit_finding [A-Z]+ [a-z-]+" |
    awk '{print $3}' | sort -u >"$emitted_tmp"
fi

emitted_count="$(grep -c . "$emitted_tmp" || true)"
if [[ "$emitted_count" -lt 20 ]]; then
  echo "check-fleet-finding-test-coverage: finding-kind extraction returned too few kinds ($emitted_count via $kind_source); the extraction, not the suite, is broken" >&2
  exit 2
fi

kind_asserted() {
  local kind="$1"
  grep -Eq -- "Finding: ${kind}([^a-z-]|$)" "$TEST"
}

declare -A baselined=()
baseline_entries=()
if [[ -f "$BASELINE" ]]; then
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
  kind_asserted "$kind" && continue
  if [[ -z "${baselined[$kind]+x}" ]]; then
    echo "UNCOVERED FINDING KIND: $kind (emitted by $SCRIPT, no Finding: assertion in $TEST)" >&2
    errors=$((errors + 1))
  else
    read_list::mark_used "$kind"
  fi
done <"$emitted_tmp"

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
