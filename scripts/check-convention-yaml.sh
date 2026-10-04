#!/usr/bin/env bash
# Validate every tracked docs/conventions/<concern>.yaml against its JSON Schema
# (ADR 0054 Decisions 6 and 7).
#
#   scripts/check-convention-yaml.sh          validate; list every finding
#   scripts/check-convention-yaml.sh --check  same, explicit form matching the
#                                             sibling gates
#
# The schema for <concern>.yaml is found by ADR 0054 Decision 6, first match
# wins:
#
#   1. plugins/<concern>/schemas/<concern>.schema.json   a plugin concern
#   2. docs/conventions/<concern>/<concern>.schema.json  a cross-plugin convention
#
# A YAML file with neither is a finding: config nobody can validate is config
# nobody can trust. Only files directly under docs/conventions/ are read; YAML
# in a convention folder (examples, fixtures) is not a team layer.
#
# The validator is check-jsonschema, the tool the repository's other schema
# steps run. CHECK_JSONSCHEMA_BIN overrides the command (a path or a name on
# PATH).
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): one finding per file on stderr, with the validator's own report
# under it, and the clean-run statement on stdout. Exit: 0 clean, 1 any finding,
# 2 environment or usage (git or the validator missing, bad argument).
set -euo pipefail

SCRIPT_SRC="${BASH_SOURCE[0]}"
[[ "$SCRIPT_SRC" == */* ]] || SCRIPT_SRC="./$SCRIPT_SRC"
SCRIPT_DIR="$(cd "${SCRIPT_SRC%/*}" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

if ! command -v git >/dev/null 2>&1; then
  printf 'check-convention-yaml: git is required to list the tracked YAML files\n' >&2
  exit 2
fi
validator="${CHECK_JSONSCHEMA_BIN:-check-jsonschema}"
if ! command -v "$validator" >/dev/null 2>&1; then
  printf 'check-convention-yaml: validator not found: %s (install check-jsonschema or set CHECK_JSONSCHEMA_BIN)\n' "$validator" >&2
  exit 2
fi

files=()
while IFS= read -r -d '' path; do
  files+=("$path")
done < <(git ls-files -z -- ':(glob)docs/conventions/*.yaml')

findings=0
checked=0
for path in ${files+"${files[@]}"}; do
  stem="${path##*/}"
  stem="${stem%.yaml}"
  plugin_schema="plugins/$stem/schemas/$stem.schema.json"
  convention_schema="docs/conventions/$stem/$stem.schema.json"
  if [[ -f "$plugin_schema" ]]; then
    schema="$plugin_schema"
  elif [[ -f "$convention_schema" ]]; then
    schema="$convention_schema"
  else
    printf '%s: no schema at %s or %s\n' "$path" "$plugin_schema" "$convention_schema" >&2
    findings=$((findings + 1))
    continue
  fi
  checked=$((checked + 1))
  if ! report="$("$validator" --schemafile "$schema" -- "$path" 2>&1)"; then
    printf '%s: does not validate against %s\n%s\n' "$path" "$schema" "$report" >&2
    findings=$((findings + 1))
  fi
done

if ((findings > 0)); then
  printf 'check-convention-yaml: %d finding(s) in %d file(s)\n' "$findings" "${#files[@]}" >&2
  exit 1
fi
printf 'check-convention-yaml: %d docs/conventions YAML file(s) validate against their schemas\n' "$checked"
