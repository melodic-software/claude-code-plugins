#!/usr/bin/env bash
# shellcheck shell=bash
# Team-layer reader for the commit and PR convention keys of the source-control
# plugin: subject_pattern, type_list, pr_title_pattern, trailer_policy,
# pr_body_attribution, pr_body_required_sections and branch_issue_pattern. The
# babysit-loop lane reads its babysit_loop_* keys through it too, when the
# checkout is its target.
#
# The team value lives in docs/conventions/source-control.yaml (ADR 0064),
# validated by schemas/source-control.schema.json; the retired
# .claude/source-control.md is not read. The YAML is parsed by yaml-subset.awk,
# the shared parser, and the value is printed as written: parse-concern-value.sh is not used because it strips a trailing
# slash, which belongs to a directory value and would change a regex.
#
# Sourced by scripts; run directly for the model-run skills:
#
#   bash convention-key.sh layer ROOT KEY   print the team layer that supplies KEY:
#                                           yaml | none
#   bash convention-key.sh value ROOT KEY   print KEY's scalar from the YAML
#   bash convention-key.sh list ROOT KEY    print KEY's list items from the YAML
#
# `layer` names the file in the form callers report: `yaml` is
# docs/conventions/source-control.yaml, `none` means it does not carry the key.
# ROOT is the repo root from config-root.sh; the caller has already classified it
# `repo`. `value` and `list` print nothing for a key the YAML lacks and exit 3
# for a YAML the parser rejects, so a caller can stop instead of reading a
# lower layer past a broken team file.

CONVENTION_KEY_YAML_REL="docs/conventions/source-control.yaml"
CONVENTION_KEY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# True when git tracks the repo-relative file REL under ROOT. An untracked or
# gitignored team file is not a config layer (skills/commit/SKILL.md).
convention_key_tracked() {
  git -C "$1" ls-files --error-unmatch -- "$2" >/dev/null 2>&1
}

# Print the parser's key<TAB>value records for the team YAML under ROOT, nothing
# when the file is absent. Returns 3 when the parser rejects the file; a key
# repeated in one mapping is a rejection too.
convention_key_records() {
  local file="$1/$CONVENTION_KEY_YAML_REL" text
  [[ -f "$file" ]] || return 0
  text="$(<"$file")"
  LC_ALL=C awk -v STRICT=1 -f "$CONVENTION_KEY_DIR/yaml-subset.awk" <<<"$text" 2>/dev/null || return 3
}

# Print the value of KEY from the team YAML under ROOT, or nothing.
convention_key_yaml_value() {
  local records
  records="$(convention_key_records "$1")" || return 3
  PCV_KEY="$2" LC_ALL=C awk -F '\t' '$1 == ENVIRON["PCV_KEY"] && !seen++ { print substr($0, length($1) + 2) }' <<<"$records"
}

# Print the scalar items of the sequence KEY in the team YAML, one per line.
convention_key_yaml_list() {
  local records
  records="$(convention_key_records "$1")" || return 3
  PCV_KEY="$2" LC_ALL=C awk -F '\t' 'index($1, ENVIRON["PCV_KEY"] ".") == 1 && substr($1, length(ENVIRON["PCV_KEY"]) + 2) ~ /^[0-9]+$/ { print substr($0, length($1) + 2) }' <<<"$records"
}

# True when the team YAML carries KEY, as a scalar or as a non-empty list.
convention_key_yaml_has() {
  local root="$1" key="$2" scalar items
  scalar="$(convention_key_yaml_value "$root" "$key")" || return 3
  [[ -z "$scalar" ]] || return 0
  items="$(convention_key_yaml_list "$root" "$key")" || return 3
  [[ -n "$items" ]]
}

# Print yaml | none. Returns 3 for an unparsable YAML.
convention_key_layer() {
  convention_key_yaml_has "$1" "$2"
  case $? in
    0) echo yaml ;;
    3) return 3 ;;
    *) echo none ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    layer) convention_key_layer "${2:?root}" "${3:?key}" ;;
    value) convention_key_yaml_value "${2:?root}" "${3:?key}" ;;
    list) convention_key_yaml_list "${2:?root}" "${3:?key}" ;;
    *)
      echo "usage: bash convention-key.sh layer|value|list ROOT KEY" >&2
      exit 2
      ;;
  esac
fi
