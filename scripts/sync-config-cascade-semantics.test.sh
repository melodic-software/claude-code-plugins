#!/usr/bin/env bash
# Black-box contract test for sync-config-cascade-semantics.py.
#
# Every case runs the generator against a fixture README under a mktemp dir, passed
# as the positional override, so the real README is only ever read (last case).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/sync-config-cascade-semantics.py"
REAL_README="$SCRIPT_DIR/../docs/conventions/config-cascade/README.md"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

BEGIN='<!-- BEGIN GENERATED: config-cascade semantics. Edit the Implementers table, then run scripts/sync-config-cascade-semantics.py -->'
END='<!-- END GENERATED: config-cascade semantics -->'
HEAD='| Surface | Path | Who wins | Merge form |
|---|---|---|---|'
ROWS='| `a` | p | first | per-key |
| `b` | q | second | replace |'

root=""
fixture_tree::build root --no-lib --label cascade-semantics || exit 1
readme="$root/README.md"

# write_readme <implementers-rows>: a README whose generated block is a placeholder.
write_readme() {
  printf '# T\n\n## Implementers\n\n%s\n%s\n\n## Semantics at a glance\n\n%s\n\nplaceholder\n\n%s\n' \
    "$HEAD" "$1" "$BEGIN" "$END" >"$readme"
}

run() { python3 "$SUT" "$@" "$readme" 2>&1; }

# expect <label> <expected-rc> <rc> <out>
expect() {
  if [[ $3 -eq $2 ]]; then ok "$1"; else fail "$1: expected rc=$2, got rc=$3: $4"; fi
}

write_readme "$ROWS"
out="$(run --check)"
expect "a stale generated block fails --check" 1 $? "$out"
out="$(run)"
expect "default mode rewrites the block" 0 $? "$out"
out="$(run --check)"
expect "clean fixture passes --check" 0 $? "$out"

sed -i 's/^| `a` | first | per-key |$/| `a` | hand edit | per-key |/' "$readme"
out="$(run --check)"
expect "hand-editing the generated region fails --check" 1 $? "$out"
run >/dev/null

sed -i 's/^| `a` | p | first | per-key |$/| `a` | p | first | concatenate |/' "$readme"
out="$(run --check)"
expect "an Implementers cell change makes --check fail" 1 $? "$out"
run >/dev/null
out="$(run --check)"
expect "default mode then --check passes" 0 $? "$out"
grep -qF '| `a` | first | concatenate |' "$readme" && ok "the new cell reaches the generated block" || fail "the new cell is missing from the generated block"

write_readme '| `a` | p |  | per-key |'
out="$(run --check)"
expect "empty Who wins cell exits 1" 1 $? "$out"

write_readme '| `a` | p | first | per-key |
| `a` | q | second | replace |'
out="$(run --check)"
expect "duplicate surface exits 1" 1 $? "$out"

printf '# T\n\n## Implementers\n\n%s\n%s\n' "$HEAD" "$ROWS" >"$readme"
out="$(run --check)"
expect "missing markers exit 2" 2 $? "$out"

out="$(python3 "$SUT" --check "$REAL_README" 2>&1)"
expect "the real README passes --check" 0 $? "$out"

test_harness::report
