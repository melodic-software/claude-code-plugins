#!/usr/bin/env bash
# Gate: every plugin hooks.json carries a top-level `description`.
#
#   scripts/check-hooks-description.sh    fail on any plugins/*/hooks/hooks.json
#                                         whose top-level `description` is
#                                         absent, not a string, blank, or
#                                         multi-line
#
# Why: the plugins reference states "Define plugin hooks in `hooks/hooks.json`
# with an optional top-level `description` field" (raw `plugins-reference.md`,
# fetched 2026-09-05), and the field is the one place a plugin can label its
# hooks as a set, distinct from the per-handler `statusMessage` shown while a
# hook runs. The 2026-09-04 hooks-reference audit found the field absent in 20
# of 20 plugins (#3752); #3727 and #3750 added it to every file. Nothing else
# reads the field, so nothing else would notice a new plugin shipping without
# it, or a rewrite dropping it: this gate is what keeps 20 of 20 from drifting
# back to 19.
#
# The rule: `plugins/*/hooks/hooks.json` is scanned; a plugin with no such file
# has no hooks to label and is skipped. The file must parse as JSON and its
# top-level `description` must be a string with at least one non-blank
# character and no line break. Wording is not judged here; the field is a one
# sentence label, and a reviewer reads it in the diff.
#
# Basis: https://code.claude.com/docs/en/plugins-reference (the hooks component,
# "with an optional top-level `description` field"). Recheck trigger: the
# reference renames, removes, or makes the field required; either way this
# comment and the rule are re-derived from the page, not patched from memory.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "check-hooks-description: jq is required but not installed" >&2
  exit 1
fi

errors=0
scanned=0

flag() {
  local file="$1" reason="$2"
  echo "HOOKS DESCRIPTION: ${file}: ${reason}" >&2
  errors=$((errors + 1))
}

# Classify one file's top-level description. jq prints one word per JSON
# document it reads:
#   missing | notstring | blank | multiline | ok
# CRLF line endings in a Git Bash checkout sit between tokens, where jq
# treats them as whitespace; a line break INSIDE the value can only be an
# escaped one the author wrote.
#
# jq's exit status is checked SEPARATELY from its output: a file whose first
# document is well-formed but which carries trailing garbage makes jq print a
# verdict for the document and then exit non-zero on the garbage, so output
# alone would clear a file Claude Code cannot load. Only a zero exit with
# exactly one verdict word counts as parsed.
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
