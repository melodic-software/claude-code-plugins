#!/usr/bin/env bash
# Tests for check-map.sh: one planted defect per rule, a clean control skill that prints nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-map.sh"
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
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}

feature_readme() { # <entry lines> <drive line>
  cat <<EOF
# Feature

## Parts

- The behavior

## Sub-features

none

## Entry points

$1

## Reset

Reprovision through the admin page.

## Drive

1. $2

## Gotchas

- None seen yet.
EOF
}

# A control skill that meets every rule, under <root>/.claude/skills/control-shop.
make_clean() {
  local root="$1" skill="$1/.claude/skills/control-shop"
  mkdir -p "$skill/features/cart" "$skill/features/billing/export" "$skill/shared/sign-in" \
    "$root/src/cart/basket" "$root/src/billing"
  : >"$root/src/cart/basket/add.py"
  : >"$root/src/billing/export.py"
  cat >"$skill/SKILL.md" <<'EOF'
# control-shop

## Launch

Run the `run-shop` skill. See the [cart feature](features/cart/README.md) and the [docs](https://example.invalid/docs).

## Ready

curl -fsS http://localhost:8080/healthz

## Capture

screenshot: the browser driver

## Cleanup

Stop the process the launch started.

## Index

```text
- Example | features/example/README.md | entry points: 9 | sources: nowhere/*.py
```

- Cart | features/cart/README.md | entry points: 2 | sources: src/cart/**/*.py
- Export | features/billing/export/README.md | entry points: 1 | sources: src/billing/export.py
EOF
  feature_readme "- Basket icon in the header | driven
- Checkout page link | not driven: needs a payment sandbox" \
    "Sign in with shared/sign-in, then open the cart. Related: [export](../billing/export/README.md)." \
    >"$skill/features/cart/README.md"
  feature_readme "- Export button on the billing page | driven" \
    "Sign in with shared/sign-in, then press Export." \
    >"$skill/features/billing/export/README.md"
  printf '# Sign in\n\nWhy shared: cart and export both start signed in.\n' >"$skill/shared/sign-in/README.md"
}

# Replace the first occurrence of <old> with <new> in <file>.
replace() {
  local content
  content="$(<"$1")"
  [[ "$content" == *"$2"* ]] || {
    echo "fixture setup: '$2' not found in $1" >&2
    exit 3
  }
  printf '%s\n' "${content/"$2"/"$3"}" >"$1"
}

n=0
new_case() {
  n=$((n + 1))
  ROOT="$TEST_TMPDIR/case-$n"
  SKILL="$ROOT/.claude/skills/control-shop"
  make_clean "$ROOT"
}
run_check() { bash "$CHECK" "$SKILL" --root "$ROOT"; }
tree_sum() { (cd "$1" && find . -type f -exec cksum {} + | LC_ALL=C sort); }

# Usage.
out="$(bash "$CHECK" --help)"
assert_equals "usage: --help exits 0" "$?" "0"
bash "$CHECK" >/dev/null 2>&1
assert_equals "usage: no directory exits 2" "$?" "2"
bash "$CHECK" "$TEST_TMPDIR/absent" >/dev/null 2>&1
assert_equals "usage: missing directory exits 2" "$?" "2"
bash "$CHECK" "$TEST_TMPDIR" --nope >/dev/null 2>&1
assert_equals "usage: unknown argument exits 2" "$?" "2"

# Clean: nothing printed, exit 0, and the default root (three levels up) resolves the globs.
new_case
out="$(run_check)"
assert_equals "clean: exit 0" "$?" "0"
assert_equals "clean: prints nothing" "$out" ""
out="$(bash "$CHECK" "$SKILL")"
assert_equals "clean: default root prints nothing" "$out" ""

# index-dead, also: exit 0 with a finding and the tree is unchanged.
new_case
printf -- '- Refunds | features/refunds/README.md | entry points: 1 | sources: src/cart/**/*.py\n' >>"$SKILL/SKILL.md"
before="$(tree_sum "$ROOT")"
out="$(run_check)"
assert_equals "index-dead: exit 0 with a finding" "$?" "0"
assert_equals "index-dead" "$out" "index-dead | SKILL.md | features/refunds/README.md does not exist"
assert_equals "index-dead: tree unchanged" "$(tree_sum "$ROOT")" "$before"

new_case
printf -- '- Cart again | features/cart/README.md | entry points: 2 | sources: src/cart/**/*.py\n' >>"$SKILL/SKILL.md"
assert_equals "index-duplicate" "$(run_check)" "index-duplicate | SKILL.md | features/cart/README.md is indexed more than once"

new_case
mkdir -p "$SKILL/features/search"
feature_readme "- Search box | driven" "Type a query." >"$SKILL/features/search/README.md"
assert_equals "index-missing" "$(run_check)" "index-missing | features/search/README.md | no index line names this feature file"

new_case
printf '# Wishlist\n\n## States\n\n- empty\n' >"$SKILL/features/wishlist.md"
assert_equals "index-missing: legacy file gets no section findings" "$(run_check)" \
  "index-missing | features/wishlist.md | no index line names this feature file"

new_case
replace "$SKILL/SKILL.md" "entry points: 2" "entry points: 3"
assert_equals "index-entry-count" "$(run_check)" "index-entry-count | SKILL.md | features/cart/README.md: index says 3, the file has 2"

new_case
replace "$SKILL/SKILL.md" "src/billing/export.py" "src/billing/missing.py"
assert_equals "index-glob" "$(run_check)" "index-glob | SKILL.md | features/billing/export/README.md: src/billing/missing.py matches no file"

new_case
replace "$SKILL/features/billing/export/README.md" "## Reset

Reprovision through the admin page.

" ""
assert_equals "section-missing" "$(run_check)" "section-missing | features/billing/export/README.md | ## Reset"

new_case
printf '\n## States\n\n- empty\n' >>"$SKILL/features/billing/export/README.md"
assert_equals "section-extra" "$(run_check)" "section-extra | features/billing/export/README.md | ## States"

new_case
replace "$SKILL/features/cart/README.md" "## Reset" "## Swap"
replace "$SKILL/features/cart/README.md" "## Drive" "## Reset"
replace "$SKILL/features/cart/README.md" "## Swap" "## Drive"
assert_equals "section-order" "$(run_check)" "section-order | features/cart/README.md | Parts,Sub-features,Entry points,Drive,Reset,Gotchas"

new_case
replace "$SKILL/features/cart/README.md" "- Basket icon in the header | driven" "- Basket icon in the header"
assert_equals "entry-marker" "$(run_check)" "entry-marker | features/cart/README.md | - Basket icon in the header"

new_case
replace "$SKILL/features/cart/README.md" "not driven: needs a payment sandbox" "not driven"
assert_equals "entry-reason" "$(run_check)" "entry-reason | features/cart/README.md | - Checkout page link | not driven"

new_case
replace "$SKILL/features/cart/README.md" "../billing/export/README.md" "../billing/exports/README.md"
assert_equals "link" "$(run_check)" "link | features/cart/README.md | ../billing/exports/README.md does not resolve"

new_case
replace "$SKILL/features/billing/export/README.md" "Sign in with shared/sign-in, then press" "Press"
assert_equals "shared-use" "$(run_check)" "shared-use | shared/sign-in | named by 1 feature file(s); shared/ holds only what two or more use"

new_case
printf '# Sign in\n\nThe sign-in steps.\n' >"$SKILL/shared/sign-in/README.md"
assert_equals "shared-why" "$(run_check)" "shared-why | shared/sign-in | no 'Why shared: <reason>' line"

printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
