#!/usr/bin/env bash
# Exit 0 clean, 1 findings, 2 environment.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2

roster_problems() {
  local dir="$1" hint lens
  local -a playbooks=() rows=() hinted=()
  for f in "$dir"/actions/*.md; do
    [[ -e "$f" ]] || continue
    lens="${f##*/}"
    playbooks+=("${lens%.md}")
  done
  hint="$(sed -n 's/^argument-hint: *"\[\([^]]*\)\].*/\1/p' "$dir/SKILL.md")"
  IFS='|' read -r -a hinted <<<"$hint"
  mapfile -t rows < <(awk '/^## Actions/{on=1; next} on && /^#/{on=0} on && /^\| `[a-z-]+` \|/{sub(/^\| `/, ""); sub(/`.*/, ""); print}' "$dir/SKILL.md")
  for lens in "${playbooks[@]}"; do
    [[ " ${rows[*]} " == *" $lens "* ]] || echo "actions/$lens.md has no Actions-table row"
    [[ " ${hinted[*]} " == *" $lens "* ]] || echo "actions/$lens.md has no argument-hint entry"
  done
  for lens in "${rows[@]}"; do
    [[ " ${playbooks[*]} " == *" $lens "* ]] || echo "Actions-table row $lens has no actions/$lens.md"
  done
  for lens in "${hinted[@]}"; do
    [[ " ${playbooks[*]} " == *" $lens "* ]] || echo "argument-hint entry $lens has no actions/$lens.md"
  done
}

failed=0
check() {
  if [[ "$2" == ok ]]; then
    echo "ok: $1"
  else
    echo "FAIL: $1" >&2
    [[ -z "${3:-}" ]] || printf '  %s\n' "$3" >&2
    failed=1
  fi
}

out="$(roster_problems "$SKILL_DIR")"
[[ -z "$out" ]] && r=ok || r=bad
check "every playbook in actions/ has a row and a hint entry, and each has a playbook" "$r" "$out"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/extra"
cp -R "$SKILL_DIR/actions" "$SKILL_DIR/SKILL.md" "$work/extra/"
: >"$work/extra/actions/zzlens.md"
out="$(roster_problems "$work/extra")"
[[ "$out" == *"actions/zzlens.md has no Actions-table row"* && "$out" == *"actions/zzlens.md has no argument-hint entry"* ]] && r=ok || r=bad
check "a playbook with no row and no hint entry is reported" "$r" "$out"

mkdir -p "$work/gone"
cp -R "$SKILL_DIR/actions" "$SKILL_DIR/SKILL.md" "$work/gone/"
first="$(find "$work/gone/actions" -name '*.md' | sort | head -n 1)"
lens="$(basename "$first" .md)"
rm -- "$first"
out="$(roster_problems "$work/gone")"
[[ "$out" == *"Actions-table row $lens has no actions/$lens.md"* && "$out" == *"argument-hint entry $lens has no actions/$lens.md"* ]] && r=ok || r=bad
check "a row and a hint entry with no playbook are reported" "$r" "$out"

exit "$failed"
