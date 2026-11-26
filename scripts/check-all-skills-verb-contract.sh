#!/usr/bin/env bash
# Exit: 0 clean, 1 a mismatch, 2 the gate could not run.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

CHECKER="${CHECK_SKILL_BIN:-plugins/skill-quality/scripts/check-skill.sh}"
if [[ ! -f "$CHECKER" ]]; then
  printf 'Error: skill checker not found: %s\n' "$CHECKER" >&2
  exit 2
fi
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

if ((${#hits[@]} > 0)); then
  for h in "${hits[@]}"; do
    printf 'FAIL: %s: %s\n' "$h" "$MISMATCH" >&2
  done
  printf 'check-all-skills-verb-contract: %d problem(s) across %d skills\n' "${#hits[@]}" "$expected" >&2
  exit 1
fi
printf 'check-all-skills-verb-contract: PASS (%d skills)\n' "$expected"
exit 0
