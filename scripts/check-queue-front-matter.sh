#!/usr/bin/env bash
# Consumer-side front-matter validator for file-based markdown handoff queues
# (one item per file with YAML front matter). Detects malformed items that make
# a `grep '^status:'` reconciliation report a false all-clear (#1647).
#
#   scripts/check-queue-front-matter.sh <queue-dir>
#
# Not a CI gate — the queue lives outside the repository. Invoke at claim time
# when an agent decides whether work is present.
#
# Exit 0 = every item file conforms; 1 = one or more violations; 2 = usage error.
set -euo pipefail

usage() {
  printf 'usage: check-queue-front-matter.sh <queue-dir>\n' >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
QUEUE_DIR="$1"

if [[ ! -d "$QUEUE_DIR" ]]; then
  printf 'Error: queue directory not found: %s\n' "$QUEUE_DIR" >&2
  exit 2
fi

VALID_STATUSES='unclaimed|claimed|in-progress|blocked|done'
VALID_PRIORITIES='low|medium|high|urgent'
REQUIRED_KEYS=(id title status created producer)

errors=0
file_count=0
parsed_count=0

report_violation() {
  printf 'VIOLATION: %s — %s\n' "$1" "$2"
  errors=$((errors + 1))
}

# extract_front_matter <file> — prints front matter body or nothing.
extract_front_matter() {
  awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm { print }
  ' "$1"
}

# fm_value <front_matter> <key>
fm_value() {
  awk -v key="$2" '
    $1 == key ":" {
      sub(/^[^:]*:[[:space:]]*/, "")
      print
      exit
    }
  ' <<<"$1"
}

for item in "$QUEUE_DIR"/*.md; do
  [[ -e "$item" ]] || continue
  base="$(basename "$item")"
  [[ "$base" == README.md ]] && continue
  file_count=$((file_count + 1))
  stem="${base%.md}"
  fm="$(extract_front_matter "$item")"
  if [[ -z "${fm//[[:space:]]/}" ]]; then
    report_violation "$item" 'missing or empty YAML front matter'
    continue
  fi
  parsed_count=$((parsed_count + 1))

  for key in "${REQUIRED_KEYS[@]}"; do
    val="$(fm_value "$fm" "$key")"
    if [[ -z "${val//[[:space:]]/}" ]]; then
      report_violation "$item" "missing required key: $key"
    fi
  done

  status="$(fm_value "$fm" status)"
  if [[ -n "$status" ]] && ! grep -qE "^(${VALID_STATUSES})$" <<<"$status"; then
    report_violation "$item" "status '$status' not in documented set (${VALID_STATUSES})"
  fi

  priority="$(fm_value "$fm" priority)"
  if [[ -n "${priority//[[:space:]]/}" ]] && ! grep -qE "^(${VALID_PRIORITIES})$" <<<"$priority"; then
    report_violation "$item" "priority '$priority' not in documented set (${VALID_PRIORITIES})"
  fi

  id="$(fm_value "$fm" id)"
  if [[ -n "$id" && "$id" != "$stem" ]]; then
    report_violation "$item" "id '$id' does not match filename stem '$stem'"
  fi
done

printf 'Reconciliation: %d item file(s), %d with parseable front matter\n' \
  "$file_count" "$parsed_count"

if ((file_count != parsed_count)); then
  report_violation "$QUEUE_DIR" \
    "count gap — $((file_count - parsed_count)) file(s) lack parseable front matter (never reconcile by status grep alone)"
fi

if ((errors > 0)); then
  printf '\n%d violation(s).\n' "$errors" >&2
  exit 1
fi

echo "Queue front matter OK."
exit 0
