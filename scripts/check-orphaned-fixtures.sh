#!/usr/bin/env bash
# Detect eval fixtures that no grader consumes: a file under a skill's
# evals/fixtures/ that no eval case references and no test asserts on. An
# ungraded fixture is dead weight that reads as tested — the "looks-tested"
# trap a merged-PR audit caught (autonomy shipped a large security-binding
# fixture corpus with no eval or test consuming any of it).
#
#   scripts/check-orphaned-fixtures.sh          discover: list every fixture
#                                                under **/evals/fixtures/ and
#                                                whether a grader consumes it
#   scripts/check-orphaned-fixtures.sh --check  fail if an un-grandfathered
#                                                fixture is orphaned, or a
#                                                baseline entry is now stale
#
# A fixture at <skill>/evals/fixtures/<sub> is CONSUMED when any of:
#   * its skill-relative path (evals/fixtures/<sub>) appears in the sibling
#     grader <skill>/evals/evals.json — an eval `files[]` entry, the issue's
#     primary consumption path;
#   * its basename appears as a whole token in that evals.json (a files[] form
#     that spells the path differently still names the file);
#   * its basename appears as a whole token in any *.test.* file in the plugin
#     — a test that asserts on the fixture is a grader too.
# Consumption matching is deliberately generous (path OR basename, across the
# grader and every test): a false "consumed" only under-reports one orphan,
# whereas a false "orphaned" red-lines a legitimate fixture. The baseline
# absorbs the remaining known-orphan debt.
#
# Scope is **/evals/fixtures/ specifically — eval-grader fixtures, the gate's
# target. Unit-test fixture dirs (…/tests/fixtures, …/scripts/fixtures) are out
# of scope: those are often generated or loaded by directory, not named, and a
# name-matcher cannot honestly grade them.
#
# Existing orphan debt owned by another issue is grandfathered in
# scripts/orphaned-fixtures-baseline.txt (exact fixture paths, one file per
# line — matched by full-string equality, NOT prefix, so a baselined
# `<name>.json` never shadows a new `<name>.json.bak` or `<name>.jsonl`
# sibling). An entry there is a promise the owning issue burns it down; --check
# fails on a stale entry (one that no longer shadows any orphan) so the baseline
# cannot outlive its debt.
#
# Fail-closed: a fixture with no resolvable grader is an orphan unless
# explicitly grandfathered. FIXTURES_BASELINE overrides the baseline path (test
# injection).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

BASELINE="${FIXTURES_BASELINE:-scripts/orphaned-fixtures-baseline.txt}"

mode="${1:-discover}"
case "$mode" in
discover | --check) ;;
*)
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
  ;;
esac

# Active baseline entries. `inline`: each entry is one exact fixture path, never
# a regex, so a `#` anywhere on the line is a comment (scripts/lib/read-list.sh
# owns the two comment families and why they must stay distinct). Matched by
# full-string equality below.
entries=()
if [[ -f "$BASELINE" ]]; then
  read_list::into entries "$BASELINE" --comments inline || exit 2
fi

# matched_baseline <fixture-path> -> print the baseline entry that grandfathers
# it and return 0, or return 1 when none does. Callers that only need the
# yes/no answer discard stdout.
matched_baseline() {
  local path="$1" entry
  for entry in "${entries[@]}"; do
    if [[ "$path" == "$entry" ]]; then
      printf '%s' "$entry"
      return 0
    fi
  done
  return 1
}

# plugin root that owns a path under plugins/<name>/… -> plugins/<name>
plugin_root_of_to() {
  # plugins / <name> / rest…  -> keep the first two segments
  local rest="${2#plugins/}"
  printf -v "$1" 'plugins/%s' "${rest%%/*}"
}

# ere_escape_to <var> <string>
# Write the ERE-escaped form into <var> in THIS shell. The previous
# `esc=$(printf '%s' "$base" | sed -E 's/[][\\.|$(){}?+*^]/\\&/g')` paid a
# printf+sed pipeline per fixture (380 on this tree). GNU Bash runs command
# substitution in a subshell even for builtins (Command Substitution, Bash
# Reference Manual; https://mywiki.wooledge.org/CommandSubstitution). Same
# metacharacter class as that sed.
ere_escape_to() {
  local __s="$2" __out="" __c
  local -i __i
  for ((__i = 0; __i < ${#__s}; __i++)); do
    __c="${__s:__i:1}"
    case "$__c" in
    # Unquoted `\\` is one backslash. A quoted `'\\'` arm is two backslash
    # characters, so a basename containing a single `\` would not be escaped
    # and `grep -E` would treat `\b` as a word boundary.
    \\ | '.' | '|' | '$' | '(' | ')' | '[' | ']' | '{' | '}' | '?' | '+' | '*' | '^')
      __out+="\\$__c"
      ;;
    *)
      __out+="$__c"
      ;;
    esac
  done
  printf -v "$1" '%s' "$__out"
}

# jq files[] extract, once per evals.json. autonomy/setup alone has 238
# fixtures sharing one grader; a per-fixture jq was 378 execs for 26 files.
declare -A EVAL_FILES_VALUES
eval_files_values_to() {
  local __dest="$1" __path="$2"
  if [[ "${EVAL_FILES_VALUES[$__path]+x}" == x ]]; then
    printf -v "$__dest" '%s' "${EVAL_FILES_VALUES[$__path]}"
    return
  fi
  local __v=""
  __v="$(jq -r '.. | objects | .files? // empty | .[]? | select(type == "string")' "$__path" 2>/dev/null)" || __v=""
  EVAL_FILES_VALUES[$__path]="$__v"
  printf -v "$__dest" '%s' "$__v"
}

# consumed <fixture-path> -> 0 if some grader consumes it
consumed() {
  local fixture="$1"
  local fixtures_dir evals_dir skill_dir evals_json rel base plugin plugin_rel files_values
  local esc_base base_re test_file line
  local -a skill_tests plugin_other_tests

  fixtures_dir="${fixture%/*}"
  # walk up to the nearest 'fixtures' segment (fixtures may nest a subdir)
  while [[ "$fixtures_dir" == */* && "${fixtures_dir##*/}" != "fixtures" ]]; do
    fixtures_dir="${fixtures_dir%/*}"
  done
  evals_dir="${fixtures_dir%/fixtures}" # …/evals
  skill_dir="${evals_dir%/evals}"       # dir that owns evals/
  evals_json="$evals_dir/evals.json"
  rel="${fixture#"$skill_dir"/}" # evals/fixtures/<sub>
  base="${fixture##*/}"

  # Basename matches are bounded by NON-FILENAME characters on both sides:
  # grep -w treats "." as a word boundary, so a referenced valid.json would
  # wrongly consume a new unconsumed valid.json.bak sibling. Escape ERE
  # metacharacters in the basename, then require the neighbors (if any) to be
  # outside [A-Za-z0-9._-] so a longer filename never satisfies the match.
  ere_escape_to esc_base "$base"
  base_re="(^|[^A-Za-z0-9._-])${esc_base}([^A-Za-z0-9._-]|$)"

  if [[ -f "$evals_json" ]]; then
    # Consumption via evals.json is limited to files[] VALUES: a fixture named
    # only in a prompt or unrelated metadata string is NOT consumed. Extract every
    # files[] string (at any nesting), then match $rel by whole-value equality, or
    # the basename bounded within a value (a files[] form that spells the path
    # differently still names the file). A shorter $rel is not a substring of a
    # longer value under -x. jq failure (missing/invalid json) -> empty -> falls
    # through to the test-file check below.
    eval_files_values_to files_values "$evals_json"
    if [[ -n "$files_values" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == "$rel" ]] && return 0
      done <<<"$files_values"
      if printf '%s\n' "$files_values" | grep -qE -- "$base_re"; then
        return 0
      fi
    fi
  fi

  # Test-file consumption is scoped: a bounded-basename match counts only inside
  # the OWNING skill, so same-named fixtures in sibling skills are never
  # conflated. A test elsewhere in the plugin must name the fixture by its
  # plugin-relative path (fixed string), which is unambiguous across skills.
  # ALL_TEST_FILES is indexed once below — not `find` per fixture (#3488 class).
  plugin_root_of_to plugin "$fixture"
  plugin_rel="${fixture#"$plugin"/}"
  skill_tests=()
  plugin_other_tests=()
  for test_file in "${ALL_TEST_FILES[@]}"; do
    [[ -n "$test_file" ]] || continue
    case "$test_file" in
    "$skill_dir"/*) skill_tests+=("$test_file") ;;
    "$plugin"/*) plugin_other_tests+=("$test_file") ;;
    *) ;;
    esac
  done
  if ((${#skill_tests[@]} > 0)) && grep -qE -- "$base_re" "${skill_tests[@]}"; then
    return 0
  fi
  if ((${#plugin_other_tests[@]} > 0)) && grep -qF -- "$plugin_rel" "${plugin_other_tests[@]}"; then
    return 0
  fi

  return 1
}

# Collect every fixture under a **/evals/fixtures/ directory, sorted. One find
# of every plugin `*.test.*` indexes the test-file graders: consumed() used to
# `find` the owning skill and then the plugin for each of ~380 fixtures
# (253 find execs on this tree). Same leftover-process class #3488 removed
# from the shell-portability scan (979s → 34s) — GNU find is a process;
# Cygwin's fork is a non-copy-on-write Win32 CreateProcess (Cygwin User's
# Guide, Process Creation).
mapfile -t -d '' fixtures < <(find plugins -type f -path '*/evals/fixtures/*' -print0 2>/dev/null | sort -z)
mapfile -t -d '' ALL_TEST_FILES < <(find plugins -type f -name '*.test.*' -print0 2>/dev/null)

# Track which baseline entries actually shadow an orphan, to flag stale ones.
declare -A entry_used

orphans=0
if [[ "$mode" == "discover" ]]; then
  for f in "${fixtures[@]}"; do
    if consumed "$f"; then
      printf '%-14s %s\n' "CONSUMED" "$f"
    elif matched_baseline "$f" >/dev/null; then
      printf '%-14s %s\n' "GRANDFATHERED" "$f"
    else
      printf '%-14s %s\n' "ORPHAN" "$f"
    fi
  done
  exit 0
fi

# --check mode
for f in "${fixtures[@]}"; do
  if consumed "$f"; then
    continue
  fi
  if p="$(matched_baseline "$f")"; then
    entry_used["$p"]=1
    continue
  fi
  echo "ORPHANED FIXTURE: $f is under evals/fixtures/ but no eval case references it and no test asserts on it." >&2
  echo "  Reference it from a grader (an eval files[] entry or a test), delete it, or grandfather it in $BASELINE with the owning issue." >&2
  orphans=$((orphans + 1))
done

stale=0
for entry in "${entries[@]}"; do
  if [[ -z "${entry_used[$entry]:-}" ]]; then
    echo "STALE BASELINE: '$entry' in $BASELINE no longer shadows any orphaned fixture — remove it." >&2
    stale=$((stale + 1))
  fi
done

if ((orphans > 0 || stale > 0)); then
  exit 1
fi
echo "No orphaned eval fixtures (every file under **/evals/fixtures/ is consumed by a grader or grandfathered)."
