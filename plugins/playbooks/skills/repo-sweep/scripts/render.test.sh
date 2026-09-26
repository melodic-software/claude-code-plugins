#!/usr/bin/env bash
# Tests for render.sh: checklist output against a hand-written golden file, page data
# injection into a tiny fixture template, and input validation.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/render.sh"
CATALOG="$HERE/testdata/fixture.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_err() { # <label> <expected-exit> <stderr-substring> <args...>
  local label=$1 want=$2 sub=$3 out rc
  shift 3
  out=$(bash "$SCRIPT" "$@" 2>"$TMP/err")
  rc=$?
  assert_eq "$label: exit $want" "$want" "$rc"
  assert_eq "$label: no stdout" "" "$out"
  case "$(cat "$TMP/err")" in *"$sub"*) pass "$label: stderr names it" ;; *) fail "$label: stderr" "*$sub*" "$(cat "$TMP/err")" ;; esac
}

recs="$TMP/recs.tsv"
printf '%s\t%s\t%s\r\n' \
  dead-code run 'never ran: a:x' \
  residue-dissolve rerun 'version changed: c:x 1.0 -> 1.1' \
  testing-audit not-applicable 'repo has no tests' \
  tidy run 'never ran: c:t' \
  prompt-audit rerun-optional 'same version ran: claude-api@builtin' >"$recs"
sel=$'repo-sweep-selection: residue-dissolve, dead-code,prompt-audit\r'

bash "$SCRIPT" --checklist "$CATALOG" "$sel" "$recs" >"$TMP/checklist.md"
assert_eq "checklist: exit 0" "0" "$?"
if cmp -s "$HERE/testdata/checklist.golden.txt" "$TMP/checklist.md"; then
  pass "checklist byte-equals testdata/checklist.golden.txt"
else
  fail "checklist byte-equals golden" "$(cat "$HERE/testdata/checklist.golden.txt")" "$(cat "$TMP/checklist.md")"
fi
assert_eq "checklist without a TSV: markers only" "<!-- repo-sweep:begin playbook=fixture -->
- [ ] tidy: c:t
<!-- repo-sweep:end -->" "$(bash "$SCRIPT" --checklist "$CATALOG" 'repo-sweep-selection: tidy')"
assert_eq "every entry selected: no Not run section" "0" \
  "$(bash "$SCRIPT" --checklist "$CATALOG" 'repo-sweep-selection: dead-code,residue-dissolve,testing-audit,tidy,prompt-audit' "$recs" | grep -c 'Not run')"

assert_err "unknown selected id" 1 "unknown id in selection: nope" --checklist "$CATALOG" 'repo-sweep-selection: dead-code,nope'
assert_err "duplicate selected id" 1 "duplicate id in selection: tidy" --checklist "$CATALOG" 'repo-sweep-selection: tidy,tidy'
assert_err "missing selection prefix" 1 "repo-sweep-selection:" --checklist "$CATALOG" 'dead-code,tidy'
printf 'dead-code\tmaybe\tx\n' >"$TMP/badrec.tsv"
assert_err "bad recommendation value" 1 "bad recommendation for dead-code" --checklist "$CATALOG" 'repo-sweep-selection: tidy' "$TMP/badrec.tsv"
assert_err "no arguments" 2 "usage" --checklist

tpl="$TMP/page.html"
printf '<html><script type="application/json">__REPO_SWEEP_DATA__</script></html>\n' >"$tpl"
page=$(REPO_SWEEP_PAGE_TEMPLATE="$tpl" bash "$SCRIPT" --page "$CATALOG" "$recs")
assert_eq "page: exit 0" "0" "$?"
data=$(sed -e 's|^<html><script type="application/json">||' -e 's|</script></html>$||' <<<"$page")
assert_eq "page: data is valid JSON with every catalog id in order" \
  "dead-code residue-dissolve testing-audit tidy prompt-audit" "$(jq -r '[.entries[].id] | join(" ")' <<<"$data")"
assert_eq "page: playbook is the catalog stem" "fixture" "$(jq -r .playbook <<<"$data")"
assert_eq "page: not-applicable and catalog-unchecked rows start unchecked" "true true false false true" \
  "$(jq -r '[.entries[].checked | tostring] | join(" ")' <<<"$data")"
assert_eq "page: skills split, recommendation and reason joined" '["c:x","c:y"] rerun version changed: c:x 1.0 -> 1.1' \
  "$(jq -r '.entries[1] | "\(.skills | tojson) \(.recommendation) \(.reason)"' <<<"$data")"
assert_eq "page: < escaped so it cannot close the script element" "<lane> 0" \
  "$(jq -r '.entries[3].args' <<<"$data") $(grep -c '<lane>' <<<"$page")"

head -2 "$recs" >"$TMP/short.tsv"
assert_err "page: missing recommendation row" 1 "no recommendation row for tidy" --page "$CATALOG" "$TMP/short.tsv"
printf '<html></html>\n' >"$TMP/notoken.html"
REPO_SWEEP_PAGE_TEMPLATE="$TMP/notoken.html" assert_err "page: template without the token" 1 "exactly one __REPO_SWEEP_DATA__" --page "$CATALOG" "$recs"
printf '__REPO_SWEEP_DATA__ __REPO_SWEEP_DATA__\n' >"$TMP/twotoken.html"
REPO_SWEEP_PAGE_TEMPLATE="$TMP/twotoken.html" assert_err "page: template with two tokens" 1 "exactly one" --page "$CATALOG" "$recs"
REPO_SWEEP_PAGE_TEMPLATE="$TMP/absent.html" assert_err "page: missing template" 1 "page template not found" --page "$CATALOG" "$recs"

real_catalog="$HERE/../catalogs/hygiene.md"
real_recs="$TMP/real-recs.tsv"
bash "$HERE/catalog.sh" "$real_catalog" | cut -f1 | while IFS= read -r id; do
  printf '%s\trun\tverification pass\n' "$id"
done >"$real_recs"
real_page=$(bash "$SCRIPT" --page "$real_catalog" "$real_recs")
assert_eq "real page: exit 0" "0" "$?"
missing=$(bash "$HERE/catalog.sh" "$real_catalog" | cut -f1 | while IFS= read -r id; do
  grep -qw -- "$id" <<<"$real_page" || printf '%s\n' "$id"
done)
assert_eq "real page: every hygiene.md id present" "" "$missing"
assert_eq "real page: no external src=http/href=http" "0" \
  "$(grep -c 'src="http\|href="http' <<<"$real_page")"

if ((FAILED)); then
  printf '%d FAILED\n' "$FAILED" >&2
  exit 1
fi
printf 'render.test.sh: all passed\n'
