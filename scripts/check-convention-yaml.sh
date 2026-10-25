#!/usr/bin/env bash
# Validate every tracked <home>/<concern>.yaml against its JSON Schema
# (ADR 0064 Decisions 6 and 7). <home> is the convention home the repository
# binds in the pointer region of AGENTS.md or CLAUDE.md, read with
# lib/resolve-convention-home.sh (ADR 0075 fix 3) both at the merge base with
# the base branch and in the working tree; docs/conventions when the
# repository binds none or declined a home.
#
#   scripts/check-convention-yaml.sh          validate; list every finding
#   scripts/check-convention-yaml.sh --check  same, explicit form matching the
#                                             sibling gates
#
# The schema for <concern>.yaml is found by ADR 0064 Decision 6, first match
# wins:
#
#   1. plugins/<concern>/schemas/<concern>.schema.json  a plugin concern
#   2. <home>/<concern>/<concern>.schema.json           a cross-plugin convention
#   3. plugins/*/schemas/<concern>.schema.json          a plugin's further concern
#
# A YAML file with neither is a finding: config nobody can validate is config
# nobody can trust. Only files directly under <home>/ are read; YAML
# in a convention folder (examples, fixtures) is not a team layer.
#
# Before the schema check each file goes through lib/yaml-subset.awk, the
# shared YAML-subset parser most plugins read these files with at runtime.
# check-jsonschema accepts full YAML (anchors, tags, block scalars); that parser
# rejects them and the plugin falls back to defaults, so a parse failure is a
# finding. A plugin with its own reader (code-metrics reads its file with
# yaml_subset.py, which is stricter) is not covered by this check.
#
# The validator is check-jsonschema, the tool the repository's other schema
# steps run. CHECK_JSONSCHEMA_BIN overrides the command (a path or a name on
# PATH).
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): one finding per file on stderr, with the validator's own report
# under it, and the clean-run statement on stdout. Exit: 0 clean, 1 any finding,
# 2 environment or usage (git, awk, the parser or the validator missing, bad
# argument).
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
parser=lib/yaml-subset.awk
if ! command -v awk >/dev/null 2>&1 || [[ ! -f "$parser" ]]; then
  printf 'check-convention-yaml: awk and %s are required to parse the YAML as the runtime does\n' "$parser" >&2
  exit 2
fi
validator="${CHECK_JSONSCHEMA_BIN:-check-jsonschema}"
if ! command -v "$validator" >/dev/null 2>&1; then
  printf 'check-convention-yaml: validator not found: %s (install check-jsonschema or set CHECK_JSONSCHEMA_BIN)\n' "$validator" >&2
  exit 2
fi

# The convention home is the one the repository binds in its pointer region
# (lib/resolve-convention-home.sh, ADR 0075 fix 3). With no region, a declined
# home, or a root that binds none, it is docs/conventions.
resolver=lib/resolve-convention-home.sh
if [[ ! -f "$resolver" ]]; then
  printf 'check-convention-yaml: %s is required to find the convention home\n' "$resolver" >&2
  exit 2
fi
# Two pointers are read, and the YAML under both homes is checked: the one
# committed at the merge base with the base branch, so a pull request that
# edits the region cannot move the gate off the home it is checked against, and
# the working tree's, so the home the change itself binds is checked too. The
# base branch is origin/$GITHUB_BASE_REF on a pull request, else origin's
# default branch (origin/HEAD, then origin/main). Where none resolves (a clone
# with no origin, a fixture repository) only the working tree's pointer is
# read; in CI (GITHUB_ACTIONS=true or a GITHUB_BASE_REF) that is exit 2.
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2
base_branch="origin/${GITHUB_BASE_REF:-}"
if [[ -z "${GITHUB_BASE_REF:-}" ]]; then
  base_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || base_branch=origin/main
fi
merge_base=""
# shellcheck disable=SC2310  # the non-zero return IS the handled case
if changed_files::verify_base "$base_branch"; then
  merge_base="$(git merge-base HEAD "$base_branch" 2>/dev/null)" || merge_base=""
fi
if [[ -z "$merge_base" && ("${GITHUB_ACTIONS:-}" == true || -n "${GITHUB_BASE_REF:-}") ]]; then
  printf 'check-convention-yaml: no merge base with %s to read the convention-home pointer at\n' "$base_branch" >&2
  exit 2
fi

# resolve_home <label> [resolver args...]: print the home, docs/conventions when
# the root binds none or declined one; return the resolver's exit 3 or other
# failure code with its message on stderr.
resolve_home() {
  local label="$1" out rc=0
  shift
  out="$(bash "$resolver" --root . "$@" 2>/dev/null)" || rc=$?
  case "$rc" in
  0) printf '%s\n' "$out" ;;
  1 | 4 | 5) printf 'docs/conventions\n' ;;
  3)
    # The resolver's own message says which region is broken.
    bash "$resolver" --root . "$@" 2>&1 >/dev/null | sed "s/^/check-convention-yaml: $label: /" >&2 || true
    return 3
    ;;
  *)
    printf 'check-convention-yaml: %s: %s failed with exit %s\n' "$label" "$resolver" "$rc" >&2
    return 2
    ;;
  esac
}

rc=0
# shellcheck disable=SC2310  # resolve_home returns its codes itself; set -e has nothing to catch
head_home="$(resolve_home 'working tree')" || rc=$?
((rc == 3)) && exit 1
((rc == 0)) || exit 2
homes=("$head_home")
if [[ -n "$merge_base" ]]; then
  rc=0
  # shellcheck disable=SC2310  # resolve_home returns its codes itself; set -e has nothing to catch
  base_home="$(resolve_home "merge base $merge_base" --ref "$merge_base")" || rc=$?
  # A broken pointer at the base is a warning: failing on it would fail every
  # later change, the one that repairs it included.
  ((rc == 0 || rc == 3)) || exit 2
  [[ $rc -eq 0 && "$base_home" != "$head_home" ]] && homes+=("$base_home")
fi

files=()
for home in "${homes[@]}"; do
  while IFS= read -r -d '' path; do
    files+=("$path")
  done < <(git ls-files -z -- ":(glob)$home/*.yaml")
done

findings=0
checked=0
for path in ${files+"${files[@]}"}; do
  checked=$((checked + 1))
  # The unattended merge policy (babysit_merge_policy.py `_SEPARATOR`) refuses
  # a pr-pipeline.yaml value holding a C0 or C1 control or U+2028/U+2029, and
  # with it every plain --merge. It reads no other file here, so only that one
  # is held to it. Read byte-wise as the policy's reader runs (LC_ALL=C); only
  # LF and a line-ending CR, which the reader strips, are allowed.
  if [[ "${path##*/}" == pr-pipeline.yaml ]] &&
    separator="$(LC_ALL=C awk '/[\001-\011\013\014\016-\037\177]|\015./ || /\302[\200-\237]|\342\200[\250\251]/ { print NR; exit }' "$path")" &&
    [[ -n "$separator" ]]; then
    printf '%s: line %s carries a control or line-separator character the unattended merge policy refuses\n' "$path" "$separator" >&2
    findings=$((findings + 1))
    continue
  fi
  if ! parsed="$(LC_ALL=C awk -f "$parser" <"$path" 2>&1)"; then
    printf '%s: the runtime YAML parser (%s) rejects it\n%s\n' "$path" "$parser" "$parsed" >&2
    findings=$((findings + 1))
    continue
  fi
  stem="${path##*/}"
  stem="${stem%.yaml}"
  plugin_schema="plugins/$stem/schemas/$stem.schema.json"
  convention_schema="${path%/*}/$stem/$stem.schema.json"
  # A plugin's second concern (review-digest.yaml, owned by the review plugin):
  # the schema ships in the plugin that reads it. Names compare literally, so a
  # stem holding a glob character matches nothing.
  owned_schema=""
  for candidate in plugins/*/schemas/*.schema.json; do
    if [[ "${candidate##*/}" == "$stem.schema.json" && -f "$candidate" ]]; then
      owned_schema="$candidate"
      break
    fi
  done
  if [[ -f "$plugin_schema" ]]; then
    schema="$plugin_schema"
  elif [[ -f "$convention_schema" ]]; then
    schema="$convention_schema"
  elif [[ -n "$owned_schema" ]]; then
    schema="$owned_schema"
  else
    printf '%s: no schema at %s, %s or plugins/*/schemas/%s.schema.json\n' "$path" "$plugin_schema" "$convention_schema" "$stem" >&2
    findings=$((findings + 1))
    continue
  fi
  if ! report="$("$validator" --schemafile "$schema" -- "$path" 2>&1)"; then
    printf '%s: does not validate against %s\n%s\n' "$path" "$schema" "$report" >&2
    findings=$((findings + 1))
  fi
done

if ((findings > 0)); then
  printf 'check-convention-yaml: %d finding(s) across %d file(s) checked\n' "$findings" "$checked" >&2
  exit 1
fi
homes_text="${homes[*]}"
printf 'check-convention-yaml: %d %s YAML file(s) parse and validate against their schemas\n' "$checked" "${homes_text// / and }"
