#!/usr/bin/env bash
# Deterministic consumer-repo simulation for the plugin-quality convention-doc
# pilot (Phase 2d, ADR 0018). Exercises the SHIPPED helper copies
# (plugins/plugin-quality/lib/*) and the plugin's retirements.yaml against a
# fixture consumer repository:
#
#   1. resolver exit 1 before any pointer region exists
#   2. apply's region write appends to a POPULATED AGENTS.md; the surrounding
#      prose stays byte-identical and the resolver then resolves the home
#   3. the manifest detects the retired tracked file and the retired overlay
#      (exit 1, exact TSV rows)
#   4. --clean on the migrate record refuses without --i-migrated
#   5. --clean with --i-migrated cleans; the delete record cleans; re-run clean
#   6. a CRLF-authored AGENTS.md also resolves
#
# This scripts the deterministic halves of the pilot's licence; the
# model-judgment halves (interview, migration prose, gating) are covered by the
# setup and audit eval cases. Per-script assertion helpers are deliberately
# duplicated, not shared: docs/conventions/shell-test-helpers/README.md.
#
# shellcheck disable=SC2016 # single-quoted backticks are the pointer grammar under test
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$ROOT/plugins/plugin-quality/lib/resolve-convention-home.sh"
CHECKER="$ROOT/plugins/plugin-quality/lib/check-retirements.sh"
MANIFEST="$ROOT/plugins/plugin-quality/retirements.yaml"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3 -- got: $2" ;;
  esac
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_file_present() {
  if [[ -f "$2" ]]; then pass "$1"; else fail "$1" "missing file: $2"; fi
}
assert_file_absent() {
  if [[ ! -e "$2" ]]; then pass "$1"; else fail "$1" "unexpected file: $2"; fi
}
assert_files_eq() {
  # assert_files_eq <label> <expected-file> <actual-file> — byte-for-byte
  if cmp -s "$2" "$3"; then pass "$1"; else fail "$1" "files differ: $2 vs $3"; fi
}

TAB=$(printf '\t')

# run_resolver <root> — OUT/ERR/RC via globals (a command substitution for RC
# would run in a subshell and keep the previous case's value).
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

# --- Fixture: a consumer repo mid-migration -----------------------------------
# Populated AGENTS.md (real prose, including a backticked path OUTSIDE any
# region, which must never be read as a pointer), the retired tracked config
# with known keys, and a pre-existing overlay.
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

# --- Case 1: no region anywhere -> resolver exit 1 (ask, never infer) ---------
run_resolver "$fixture"
assert_exit "case 1: resolver exits 1 before the region exists" 1 "$RC"
assert_contains "case 1: routes to asking the operator" "$ERR" "ask the operator"
assert_eq "case 1: prints no home" "" "$OUT"

# --- Case 2: apply's region write, appended to the populated AGENTS.md --------
# The script writes the region the way setup's apply would: APPEND the marked
# region, never touch any other byte, and create the confirmed home + topic doc.
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

# --- Case 3: manifest detection finds both leftovers --------------------------
run_checker --manifest "$MANIFEST" --root "$fixture"
assert_exit "case 3: detection exits 1 on active leftovers" 1 "$RC"
assert_contains "case 3: r001 row (migrate, active) is exact" "$OUT" \
  "plugin-quality-r001${TAB}file${TAB}.claude/plugin-quality.md${TAB}migrate${TAB}active${TAB}"
assert_contains "case 3: r002 row (delete, active) is exact" "$OUT" \
  "plugin-quality-r002${TAB}file${TAB}.claude/plugin-quality.local.md${TAB}delete${TAB}active${TAB}"
assert_contains "case 3: summary counts two active leftovers" "$ERR" "2 active leftover(s)"

# --- Case 4: the migrate record refuses --clean without --i-migrated ----------
run_checker --manifest "$MANIFEST" --clean plugin-quality-r001 --root "$fixture"
assert_exit "case 4: --clean without --i-migrated refuses" 2 "$RC"
assert_contains "case 4: names the flag it needs" "$ERR" "--i-migrated"
assert_file_present "case 4: the retired file is untouched" "$fixture/.claude/plugin-quality.md"

# --- Case 5: gated cleans succeed and a re-run is clean -----------------------
run_checker --manifest "$MANIFEST" --clean plugin-quality-r001 --i-migrated --root "$fixture"
assert_exit "case 5: r001 cleans with --i-migrated" 0 "$RC"
assert_file_absent "case 5: the retired tracked file is gone" "$fixture/.claude/plugin-quality.md"
run_checker --manifest "$MANIFEST" --clean plugin-quality-r002 --root "$fixture"
assert_exit "case 5: r002 (delete) cleans without a migrate gate" 0 "$RC"
assert_file_absent "case 5: the retired overlay is gone" "$fixture/.claude/plugin-quality.local.md"
run_checker --manifest "$MANIFEST" --root "$fixture"
assert_exit "case 5: re-run detection is clean" 0 "$RC"
assert_eq "case 5: no rows after cleanup" "" "$OUT"

# --- Case 6: a CRLF-authored AGENTS.md also resolves --------------------------
crlf="$TEST_TMPDIR/crlf-consumer"
mkdir -p "$crlf/docs/conventions"
{
  printf '# Repo\r\n\r\nCRLF-authored prose.\r\n\r\n'
  printf '<!-- BEGIN GENERATED: convention-home -->\r\n'
  printf 'Team conventions live in `docs/conventions` - read the topic doc there first.\r\n'
  printf '<!-- END GENERATED: convention-home -->\r\n'
} >"$crlf/AGENTS.md"
run_resolver "$crlf"
assert_exit "case 6: CRLF AGENTS.md resolves" 0 "$RC"
assert_eq "case 6: prints the home despite CRLF endings" "docs/conventions" "$OUT"

# ------------------------------------------------------------------------------
echo
if [[ $FAILED -gt 0 ]]; then
  echo "FAILED: $FAILED of $CASE_NUM checks." >&2
  exit 1
fi
echo "All $CASE_NUM checks passed."
