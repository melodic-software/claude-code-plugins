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

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

BASELINE="${FIXTURES_BASELINE:-scripts/orphaned-fixtures-baseline.txt}"

mode="${1:-discover}"
case "$mode" in
discover | --check) ;;
*)
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
  ;;
esac

# Active baseline entries: strip inline comments and surrounding blank lines.
# Each entry is one exact fixture path, matched by full-string equality below.
entries=()
if [[ -f "$BASELINE" ]]; then
  mapfile -t entries < <(sed -E 's/#.*//; s/^[[:space:]]+//; s/[[:space:]]+$//' "$BASELINE" | grep -v '^$')
fi

is_grandfathered() {
  local path="$1" entry
  for entry in "${entries[@]}"; do
    if [[ "$path" == "$entry" ]]; then
      return 0
    fi
  done
  return 1
}

# plugin root that owns a path under plugins/<name>/… -> plugins/<name>
plugin_root_of() {
  local path="$1"
  # plugins / <name> / rest…  -> keep the first two segments
  printf 'plugins/%s' "${path#plugins/}" | cut -d/ -f1-2
}

# consumed <fixture-path> -> 0 if some grader consumes it
consumed() {
  local fixture="$1"
  local fixtures_dir evals_dir skill_dir evals_json rel base plugin

  fixtures_dir="${fixture%/*}"
  # walk up to the nearest 'fixtures' segment (fixtures may nest a subdir)
  while [[ "$fixtures_dir" == */* && "${fixtures_dir##*/}" != "fixtures" ]]; do
    fixtures_dir="${fixtures_dir%/*}"
  done
  evals_dir="${fixtures_dir%/fixtures}"   # …/evals
  skill_dir="${evals_dir%/evals}"         # dir that owns evals/
  evals_json="$evals_dir/evals.json"
  rel="${fixture#"$skill_dir"/}"          # evals/fixtures/<sub>
  base="${fixture##*/}"

  if [[ -f "$evals_json" ]]; then
    if grep -qF "$rel" "$evals_json"; then
      return 0
    fi
    if grep -qwF "$base" "$evals_json"; then
      return 0
    fi
  fi

  plugin="$(plugin_root_of "$fixture")"
  while IFS= read -r -d '' test_file; do
    if grep -qwF "$base" "$test_file"; then
      return 0
    fi
  done < <(find "$plugin" -type f -name '*.test.*' -print0 2>/dev/null)

  return 1
}

# Collect every fixture under a **/evals/fixtures/ directory.
fixtures=()
while IFS= read -r -d '' dir; do
  while IFS= read -r -d '' f; do
    fixtures+=("$f")
  done < <(find "$dir" -type f -print0)
done < <(find plugins -type d -path '*/evals/fixtures' -print0 2>/dev/null)

if ((${#fixtures[@]} > 0)); then
  mapfile -t -d '' fixtures < <(printf '%s\0' "${fixtures[@]}" | sort -z)
fi

# Track which baseline entries actually shadow an orphan, to flag stale ones.
declare -A entry_used
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

orphans=0
if [[ "$mode" == "discover" ]]; then
  for f in "${fixtures[@]}"; do
    if consumed "$f"; then
      printf '%-14s %s\n' "CONSUMED" "$f"
    elif is_grandfathered "$f"; then
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
