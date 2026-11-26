#!/usr/bin/env bash
# Exit 0 clean, 1 findings, 2 environment or usage; findings on stderr.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

if ! command -v jq >/dev/null 2>&1; then
  echo "check-hooks-description: jq is required but not installed" >&2
  exit 2
fi

errors=0
scanned=0

flag() {
  local file="$1" reason="$2"
  echo "HOOKS DESCRIPTION: ${file}: ${reason}" >&2
  errors=$((errors + 1))
}

CLASSIFY_PROG='
  if has("description") | not then "missing"
  elif (.description | type) != "string" then "notstring"
  elif (.description | test("[\n\r]")) then "multiline"
  elif (.description | gsub("^[[:space:]]+|[[:space:]]+$"; "") | length) == 0 then "blank"
  else "ok" end'

for file in plugins/*/hooks/hooks.json; do
  [[ -f "$file" ]] || continue
  scanned=$((scanned + 1))
  rc=0
  verdict="$(jq -r "$CLASSIFY_PROG" "$file" 2>/dev/null)" || rc=$?
  if ((rc != 0)) || [[ -z "$verdict" || "$verdict" == *$'\n'* ]]; then
    flag "$file" "not parseable as JSON, so this gate cannot clear it"
    continue
  fi
  case "$verdict" in
  ok) ;;
  missing) flag "$file" "no top-level \"description\"; add a one-sentence label for what this plugin's hooks do and on which events" ;;
  notstring) flag "$file" "top-level \"description\" is not a string" ;;
  blank) flag "$file" "top-level \"description\" is blank" ;;
  multiline) flag "$file" "top-level \"description\" spans more than one line; keep it to one sentence" ;;
  *) flag "$file" "unexpected verdict \"$verdict\"" ;;
  esac
done

if ((errors > 0)); then
  echo "check-hooks-description: ${errors} problem(s) across ${scanned} hooks.json file(s)." >&2
  exit 1
fi
echo "Every plugin hooks.json (${scanned}) carries a one-line top-level description."
