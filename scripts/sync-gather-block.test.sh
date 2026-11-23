#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixture skill bodies are literal markdown with backticks, never expanded
# test-scope: plugins/*/skills/*/SKILL.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/sync-gather-block.py"
REAL_ROOT="$SCRIPT_DIR/.."

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

BEGIN='<!-- BEGIN GENERATED: gather-block. Edit docs/conventions/gather-block/block.md, then run scripts/sync-gather-block.py -->'
END='<!-- END GENERATED: gather-block -->'

root=""
fixture_tree::build root --no-lib --label gather-block || exit 1
source_md="$root/docs/conventions/gather-block/block.md"
skill_a="$root/plugins/p/skills/a/SKILL.md"
skill_b="$root/plugins/q/skills/b/SKILL.md"
plain="$root/plugins/q/skills/plain/SKILL.md"
mkdir -p "${source_md%/*}" "${skill_a%/*}" "${skill_b%/*}" "${plain%/*}"

write_skill() {
  printf '# S\n\n## Repository context. Gather first\n\n%s\n\nplaceholder\n\n%s\n\n%s\n\n## Next\n' \
    "$BEGIN" "$END" "$2" >"$1"
}

reset_tree() {
  printf 'Rule text one.\n' >"$source_md"
  write_skill "$skill_a" '- Current branch, `git branch --show-current`'
  write_skill "$skill_b" '- Recent commits, `git log --oneline -5`'
  printf '# Plain\n\nNo gather section.\n' >"$plain"
}

run() { python3 "$SUT" "$@" "$root" 2>&1; }

expect() {
  if [[ $3 -eq $2 ]]; then ok "$1"; else fail "$1: expected rc=$2, got rc=$3: $4"; fi
}

has() {
  if grep -qF -- "$3" "$2"; then ok "$1"; else fail "$1: '$3' not in $2"; fi
}

reset_tree
out="$(run --check)"
expect "a placeholder block fails --check" 1 $? "$out"
out="$(run)"
expect "default mode rewrites the blocks" 0 $? "$out"
out="$(run --check)"
expect "a freshly generated tree passes --check" 0 $? "$out"
has "the source text reaches the first skill" "$skill_a" 'Rule text one.'
has "the source text reaches the second skill" "$skill_b" 'Rule text one.'
has "a command bullet outside the markers survives" "$skill_b" '- Recent commits, `git log --oneline -5`'
if grep -qF placeholder "$skill_a"; then
  fail "the placeholder inside the markers is replaced"
else
  ok "the placeholder inside the markers is replaced"
fi
if [[ "$(cat "$plain")" == $'# Plain\n\nNo gather section.' ]]; then
  ok "a skill without markers is left byte for byte"
else
  fail "a skill without markers is left byte for byte"
fi

sed 's/^Rule text one\.$/Rule text hand edit./' "$skill_a" >"$skill_a.tmp" && mv "$skill_a.tmp" "$skill_a"
out="$(run --check)"
expect "hand-editing a generated block fails --check" 1 $? "$out"
run >/dev/null

printf 'Rule text two.\n' >"$source_md"
out="$(run --check)"
expect "a source change makes --check fail" 1 $? "$out"
run >/dev/null
out="$(run --check)"
expect "default mode then --check passes" 0 $? "$out"
has "the new source text reaches the first skill" "$skill_a" 'Rule text two.'
has "the new source text reaches the second skill" "$skill_b" 'Rule text two.'

reset_tree
run >/dev/null
printf '# U\n\n## Repository context. Gather first\n\n- Current branch, `git branch --show-current`\n' \
  >"$plain"
out="$(run --check)"
expect "a gather heading without markers exits 1" 1 $? "$out"
if [[ "$out" == *plugins/q/skills/plain/SKILL.md* ]]; then
  ok "the unmarked skill is named"
else
  fail "the unmarked skill is named: $out"
fi

reset_tree
printf '%s\n%s\n' "$BEGIN" "$END" >>"$skill_a"
out="$(run --check)"
expect "a second marker pair exits 2" 2 $? "$out"

reset_tree
rm "$source_md"
out="$(run --check)"
expect "a missing block.md exits 2" 2 $? "$out"

reset_tree
: >"$source_md"
out="$(run --check)"
expect "an empty block.md exits 2" 2 $? "$out"

reset_tree
printf '# A\n' >"$skill_a"
printf '# B\n' >"$skill_b"
out="$(run --check)"
expect "no skill carrying the markers exits 2" 2 $? "$out"

out="$(python3 "$SUT" --check "$REAL_ROOT" 2>&1)"
expect "the real repository passes --check" 0 $? "$out"

test_harness::report
