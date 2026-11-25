#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/org-standards.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG STANDARDS_DIR ORG_STANDARDS_TTL

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: [$2], actual: [$3]"; fi
}

g() { git -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false "$@"; }

ORG_WORK="$TEST_TMPDIR/org-work"
mkdir -p "$ORG_WORK/docs/standards"
printf '# Org review\n\n- org rule\n' >"$ORG_WORK/REVIEW.md"
printf -- '---\nstandards-contract: 1.2.0\n---\n\n# Standards index\n' >"$ORG_WORK/docs/standards/README.md"
g init -q -b main "$ORG_WORK"
g -C "$ORG_WORK" add -A
g -C "$ORG_WORK" commit -q -m org
mkdir -p "$TEST_TMPDIR/git/acme"
g clone -q --bare "$ORG_WORK" "$TEST_TMPDIR/git/acme/standards.git"
g -C "$ORG_WORK" remote add origin "$TEST_TMPDIR/git/acme/standards.git"
export ORG_STANDARDS_GIT_BASE="file://$TEST_TMPDIR/git"
export ORG_STANDARDS_CACHE="$TEST_TMPDIR/cache"

ORG_REVIEW=$(cat "$ORG_WORK/REVIEW.md")
MARKER='<!-- The repository REVIEW.md follows: its criteria add to the organization criteria above. -->'

target() {
  local dir="$TEST_TMPDIR/$1"
  mkdir -p "$dir/docs/conventions"
  printf '%s' "$2" >"$dir/docs/conventions/source-control.yaml"
  printf '%s\n' "$dir"
}
run() { bash "$SCRIPT" "$@" 2>/dev/null; }
code() { bash "$SCRIPT" "$@" >/dev/null 2>&1; echo $?; }

OPTED=$'standards_repository: acme/standards # org layer\n'

t=$(target default "$OPTED")
assert_eq "default: no repository REVIEW.md gives the org criteria only" "$ORG_REVIEW" "$(run review --root "$t")"

t=$(target extend "$OPTED")
printf '# Repo review\n\n- repo rule\n' >"$t/REVIEW.md"
assert_eq "extend: repository additions follow the org criteria" \
  "$(printf '%s\n\n%s\n\n# Repo review\n\n- repo rule' "$ORG_REVIEW" "$MARKER")" "$(run review --root "$t")"

t=$(target override "$OPTED")
printf '\n<!-- review-base: replace -->\n# Repo only\n' >"$t/REVIEW.md"
assert_eq "override: the replace marker gives the repository criteria only" \
  "$(printf '\n<!-- review-base: replace -->\n# Repo only')" "$(run review --root "$t")"

t=$(target late-marker "$OPTED")
printf '# Repo\n<!-- review-base: replace -->\n' >"$t/REVIEW.md"
assert_eq "a marker below the first line is an ordinary addition" "1" "$(run review --root "$t" | grep -c '^# Org review$')"

t=$(target identical "$OPTED")
cp "$ORG_WORK/REVIEW.md" "$t/REVIEW.md"
assert_eq "identical copy: org criteria once" "$ORG_REVIEW" "$(run review --root "$t")"

t=$(target plain 'pr_open_state: ready\n')
assert_eq "no standards_repository and no REVIEW.md: exit 3" "3" "$(code review --root "$t")"
assert_eq "no standards_repository: dir exits 3" "3" "$(code dir --root "$t")"
printf '# Local\n' >"$t/REVIEW.md"
assert_eq "no standards_repository: the repository criteria only" "# Local" "$(run review --root "$t")"

t=$(target malformed 'standards_repository: not a repo\n')
assert_eq "a malformed standards_repository is no org layer" "3" "$(code dir --root "$t")"

t=$(target ci "$OPTED")
mkdir -p "$TEST_TMPDIR/ci-std"
printf '# CI org\n' >"$TEST_TMPDIR/ci-std/REVIEW.md"
assert_eq "STANDARDS_DIR is the org checkout" "# CI org" "$(STANDARDS_DIR="$TEST_TMPDIR/ci-std" run review --root "$t")"
assert_eq "a STANDARDS_DIR that is not a directory: exit 4" "4" "$(STANDARDS_DIR="$TEST_TMPDIR/none" code dir --root "$t")"

t=$(target cache "$OPTED")
cache=$(run dir --root "$t")
assert_eq "dir prints the cached clone" "$ORG_STANDARDS_CACHE/acme/standards" "$cache"
printf '# Org review v2\n' >"$ORG_WORK/REVIEW.md"
g -C "$ORG_WORK" commit -q -am v2
g -C "$ORG_WORK" push -q origin main
assert_eq "within the TTL the cache is not refetched" "$ORG_REVIEW" "$(run review --root "$t")"
assert_eq "past the TTL the cache is refreshed" "# Org review v2" "$(ORG_STANDARDS_TTL=0 run review --root "$t")"

mv "$TEST_TMPDIR/git/acme/standards.git" "$TEST_TMPDIR/moved.git"
assert_eq "a failed refresh still prints the cache" "$cache" "$(ORG_STANDARDS_TTL=0 run dir --root "$t")"
assert_eq "a failed refresh says so" "1" "$(ORG_STANDARDS_TTL=0 bash "$SCRIPT" dir --root "$t" 2>&1 >/dev/null | grep -c 'using the copy cached')"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/cache2"
assert_eq "clone failure with no cache: exit 4" "4" "$(code dir --root "$t")"
printf '# Local only\n' >"$t/REVIEW.md"
assert_eq "clone failure: review gives the repository criteria" "# Local only" "$(run review --root "$t")"
mv "$TEST_TMPDIR/moved.git" "$TEST_TMPDIR/git/acme/standards.git"

t=$(target index "$OPTED")
assert_eq "index prints the org index" "$ORG_STANDARDS_CACHE/acme/standards/docs/standards/README.md" "$(run index --root "$t")"
mkdir -p "$TEST_TMPDIR/no-index/docs/standards"
printf '# Not an index\n' >"$TEST_TMPDIR/no-index/docs/standards/README.md"
assert_eq "an org README without the key is no index: exit 5" "5" "$(STANDARDS_DIR="$TEST_TMPDIR/no-index" code index --root "$t")"
mkdir -p "$TEST_TMPDIR/moved-index/.claude" "$TEST_TMPDIR/moved-index/std"
printf 'standards_dir: std\n' >"$TEST_TMPDIR/moved-index/.claude/standards.yaml"
printf -- '---\nstandards-contract: 1.2.0\n---\n' >"$TEST_TMPDIR/moved-index/std/README.md"
assert_eq "index follows the org repository's standards_dir" "$TEST_TMPDIR/moved-index/std/README.md" \
  "$(STANDARDS_DIR="$TEST_TMPDIR/moved-index" run index --root "$t")"

assert_eq "an unknown command is a usage error" "2" "$(code bogus)"

if [[ "$FAILED" -gt 0 ]]; then
  printf '%d test(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'All tests passed\n'
