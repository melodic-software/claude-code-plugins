#!/usr/bin/env bash
# Run skill-quality check 25 (description/verb-contract polarity) across every
# marketplace skill. Changed-file scoping in check-changed-skills.sh only
# guards skills a PR touches; this job keeps the full corpus green (#4586).
#
# The checker runs in its root form, once per plugins/*/skills root and in
# parallel, with CHECK_SKILL_ONLY=25 so it runs check 25 and nothing else. Only
# check-25 lines count here. A run that cannot vouch for every skill exits 2:
# a checker exit other than 0 or 1, or a pass/fail rollup that does not add up
# to the number of skills on disk. That second test is what keeps a checker
# that stops accepting its input from reading as a clean pass.
#
# scripts/verb-contract-baseline.txt lists skill directories with a known
# mismatch; a listed skill that no longer mismatches is a stale row and fails.
#
# Exit: 0 clean, 1 a mismatch or stale baseline row, 2 the gate could not run.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
# shellcheck source=lib/read-list.sh
source scripts/lib/read-list.sh || exit 2

CHECKER="${CHECK_SKILL_BIN:-plugins/skill-quality/scripts/check-skill.sh}"
if [[ ! -f "$CHECKER" ]]; then
  printf 'Error: skill checker not found: %s\n' "$CHECKER" >&2
  exit 2
fi
BASELINE="scripts/verb-contract-baseline.txt"
MISMATCH='description/verb-contract mismatch'

roots=()
for root in plugins/*/skills; do
  [[ -d "$root" ]] && roots+=("$root")
done
expected=0
for skill_md in plugins/*/skills/*/SKILL.md; do
  [[ -f "$skill_md" ]] && expected=$((expected + 1))
done
((expected > 0)) || {
  printf 'Error: no skills found under plugins/*/skills\n' >&2
  exit 2
}

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

# One checker run per root: <n>.out holds its output, <n>.rc its exit code.
jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
# shellcheck disable=SC2016  # the inner script expands its own positionals
for i in "${!roots[@]}"; do
  printf '%s\t%s\n' "$i" "${roots[$i]}"
done | xargs -P "$jobs" -L 1 bash -c '
  CHECK_SKILL_ONLY=25 bash "$1" "$4" >"$2/$3.out" 2>&1
  echo $? >"$2/$3.rc"
' _ "$CHECKER" "$work"

passed=0
failed=0
env_error=0
hits=()
for i in "${!roots[@]}"; do
  root="${roots[$i]}"
  rc="$(cat "$work/$i.rc" 2>/dev/null || echo missing)"
  if [[ "$rc" != 0 && "$rc" != 1 ]]; then
    printf 'ERROR: checker exited %s on %s\n' "$rc" "$root" >&2
    sed 's/^/  /' "$work/$i.out" >&2 2>/dev/null
    env_error=1
    continue
  fi
  rollup="$(grep -E '^[0-9]+ passed, [0-9]+ failed$' "$work/$i.out" | tail -1)"
  if [[ -z "$rollup" ]]; then
    printf 'ERROR: no pass/fail rollup from the checker on %s\n' "$root" >&2
    env_error=1
    continue
  fi
  read -r p _ f _ <<<"$rollup"
  passed=$((passed + p))
  failed=$((failed + f))
  # A check-25 FAIL line precedes its skill's `CHECK-SKILL <leaf>:` summary.
  while IFS= read -r leaf; do
    hits+=("$root/$leaf")
  done < <(awk -v m="$MISMATCH" '
    index($0, "FAIL: " m) == 1 { hit = 1 }
    /^CHECK-SKILL / { if (hit) { leaf = $2; sub(/:$/, "", leaf); print leaf }; hit = 0 }
  ' "$work/$i.out")
done

if ((env_error == 0 && passed + failed != expected)); then
  printf 'ERROR: the checker reported %d skill(s) but %d exist under plugins/*/skills\n' \
    "$((passed + failed))" "$expected" >&2
  env_error=1
fi
((env_error == 0)) || exit 2

baseline=()
if [[ -f "$BASELINE" ]]; then
  read_list::into baseline "$BASELINE" --comments leading || exit 2
fi
listed() {
  local needle="$1" b
  for b in ${baseline[@]+"${baseline[@]}"}; do
    [[ "$b" == "$needle" ]] && return 0
  done
  return 1
}
hit() {
  local needle="$1" h
  for h in ${hits[@]+"${hits[@]}"}; do
    [[ "$h" == "$needle" ]] && return 0
  done
  return 1
}

bad=0
for h in ${hits[@]+"${hits[@]}"}; do
  listed "$h" && continue
  printf 'FAIL: %s: %s\n' "$h" "$MISMATCH" >&2
  bad=$((bad + 1))
done
for b in ${baseline[@]+"${baseline[@]}"}; do
  hit "$b" && continue
  printf 'FAIL: stale row in %s, %s no longer mismatches: delete the row\n' "$BASELINE" "$b" >&2
  bad=$((bad + 1))
done

if ((bad > 0)); then
  printf 'check-all-skills-verb-contract: %d problem(s) across %d skills\n' "$bad" "$expected" >&2
  exit 1
fi
printf 'check-all-skills-verb-contract: PASS (%d skills, %d baselined)\n' "$expected" "${#baseline[@]}"
exit 0
