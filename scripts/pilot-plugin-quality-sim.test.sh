#!/usr/bin/env bash
# shellcheck disable=SC2016 # single-quoted backticks are the pointer grammar under test
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$ROOT/plugins/plugin-quality/lib/resolve-convention-home.sh"
CHECKER="$ROOT/plugins/plugin-quality/lib/check-retirements.sh"
MANIFEST="$ROOT/plugins/plugin-quality/retirements.yaml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$ROOT/scripts/lib/fixture-tree.sh"

TEST_TMPDIR=""
fixture_tree::build TEST_TMPDIR --label plugin-quality-sim

pass() { ok "$1"; }
bad() { fail "$1${2:+ — detail: $2}"; }
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else bad "$1" "expected [$2], got [$3]"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) bad "$1" "expected to contain: $3 -- got: $2" ;;
  esac
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else bad "$1" "expected exit $2, got $3"; fi
}
assert_file_present() {
  if [[ -f "$2" ]]; then pass "$1"; else bad "$1" "missing file: $2"; fi
}
assert_file_absent() {
  if [[ ! -e "$2" ]]; then pass "$1"; else bad "$1" "unexpected file: $2"; fi
}
assert_files_eq() {
  if cmp -s "$2" "$3"; then pass "$1"; else bad "$1" "files differ: $2 vs $3"; fi
}

TAB=$(printf '\t')

OUT=""
ERR=""
RC=0
run_resolver() {
  OUT="$(bash "$RESOLVER" --root "$1" 2>"$TEST_TMPDIR/err")"
  RC=$?
  ERR="$(cat "$TEST_TMPDIR/err")"
}

run_checker() {
  OUT="$(bash "$CHECKER" "$@" 2>"$TEST_TMPDIR/err")"
  RC=$?
  ERR="$(cat "$TEST_TMPDIR/err")"
}

fixture="$TEST_TMPDIR/consumer"
mkdir -p "$fixture/.claude"

cat >"$fixture/AGENTS.md" <<'EOF'
# Acme Web

Monorepo for the Acme storefront and its services.

## Working agreements

- Run the unit suite before pushing.
- Feature flags live in `config/flags.yaml`.
EOF

cat >"$fixture/.claude/plugin-quality.md" <<'EOF'
# plugin-quality config

```yaml
sink: markdown-dir
markdown_dir: ~/audit-items
zone_behavior: default
```
EOF

cat >"$fixture/.claude/plugin-quality.local.md" <<'EOF'
```yaml
sink: local-fallback
```
EOF

if command -v git >/dev/null 2>&1; then
  git -C "$fixture" init -q 2>/dev/null
  git -C "$fixture" add -A 2>/dev/null
  git -C "$fixture" -c user.email=sim@example.invalid -c user.name=sim commit -qm fixture 2>/dev/null
fi

cp "$fixture/AGENTS.md" "$TEST_TMPDIR/AGENTS.orig"

run_resolver "$fixture"
assert_exit "case 1: resolver exits 1 before the region exists" 1 "$RC"
assert_contains "case 1: routes to asking the operator" "$ERR" "ask the operator"
assert_eq "case 1: prints no home" "" "$OUT"

mkdir -p "$fixture/docs/conventions/plugin-quality"
cat >"$fixture/docs/conventions/plugin-quality/README.md" <<'EOF'
# plugin-quality conventions

```yaml
sink: markdown-dir
markdown_dir: ~/audit-items
zone_behavior: default
```
EOF

region_block() {
  printf '\n'
  printf '%s\n' '<!-- BEGIN GENERATED: convention-home -->'
  printf '%s\n' 'Team conventions live in `docs/conventions` - read the topic doc there before changing a governed surface.'
  printf '%s\n' '<!-- END GENERATED: convention-home -->'
}
region_block >>"$fixture/AGENTS.md"

run_resolver "$fixture"
assert_exit "case 2: resolver resolves after the region write" 0 "$RC"
assert_eq "case 2: prints the repo-relative home" "docs/conventions" "$OUT"
assert_eq "case 2: no duplicate or FAIL warnings" "" "$ERR"

orig_size=$(wc -c <"$TEST_TMPDIR/AGENTS.orig" | tr -d '[:space:]')
head -c "$orig_size" "$fixture/AGENTS.md" >"$TEST_TMPDIR/AGENTS.prefix"
assert_files_eq "case 2: pre-existing AGENTS.md prose is byte-identical" \
  "$TEST_TMPDIR/AGENTS.orig" "$TEST_TMPDIR/AGENTS.prefix"
cp "$TEST_TMPDIR/AGENTS.orig" "$TEST_TMPDIR/AGENTS.expected"
region_block >>"$TEST_TMPDIR/AGENTS.expected"
assert_files_eq "case 2: the whole file is exactly prose + appended region" \
  "$TEST_TMPDIR/AGENTS.expected" "$fixture/AGENTS.md"

run_checker --manifest "$MANIFEST" --root "$fixture"
assert_exit "case 3: detection exits 1 on active leftovers" 1 "$RC"
assert_contains "case 3: r001 row (migrate, active) is exact" "$OUT" \
  "plugin-quality-r001${TAB}file${TAB}.claude/plugin-quality.md${TAB}migrate${TAB}active${TAB}"
assert_contains "case 3: r002 row (delete, active) is exact" "$OUT" \
  "plugin-quality-r002${TAB}file${TAB}.claude/plugin-quality.local.md${TAB}delete${TAB}active${TAB}"
assert_contains "case 3: summary counts two active leftovers" "$ERR" "2 active leftover(s)"

run_checker --manifest "$MANIFEST" --clean plugin-quality-r001 --root "$fixture"
assert_exit "case 4: --clean without --i-migrated refuses" 2 "$RC"
assert_contains "case 4: names the flag it needs" "$ERR" "--i-migrated"
assert_file_present "case 4: the retired file is untouched" "$fixture/.claude/plugin-quality.md"

run_checker --manifest "$MANIFEST" --clean plugin-quality-r001 --i-migrated --root "$fixture"
assert_exit "case 5: r001 cleans with --i-migrated" 0 "$RC"
assert_file_absent "case 5: the retired tracked file is gone" "$fixture/.claude/plugin-quality.md"
run_checker --manifest "$MANIFEST" --clean plugin-quality-r002 --root "$fixture"
assert_exit "case 5: r002 (delete) cleans without a migrate gate" 0 "$RC"
assert_file_absent "case 5: the retired personal override is gone" "$fixture/.claude/plugin-quality.local.md"
run_checker --manifest "$MANIFEST" --root "$fixture"
assert_exit "case 5: re-run detection is clean" 0 "$RC"
assert_eq "case 5: no rows after cleanup" "" "$OUT"

crlf="$TEST_TMPDIR/crlf-consumer"
mkdir -p "$crlf/docs/conventions"
git init -q "$crlf" >/dev/null 2>&1
{
  printf '# Repo\r\n\r\nCRLF-authored prose.\r\n\r\n'
  printf '<!-- BEGIN GENERATED: convention-home -->\r\n'
  printf 'Team conventions live in `docs/conventions` - read the topic doc there first.\r\n'
  printf '<!-- END GENERATED: convention-home -->\r\n'
} >"$crlf/AGENTS.md"
run_resolver "$crlf"
assert_exit "case 6: CRLF AGENTS.md resolves" 0 "$RC"
assert_eq "case 6: prints the home despite CRLF endings" "docs/conventions" "$OUT"

test_harness::report
