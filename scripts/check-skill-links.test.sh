#!/usr/bin/env bash
# test-scope: scripts/skill-links.json # check-skill-links.py reads the accepted table
# test-scope: plugins/*/skills/*/SKILL.md plugins/*/.claude-plugin/plugin.json # the checkout case scans every skill and manifest
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

TMP=""
fixture_tree::build TMP --sut check-skill-links.sh --sut check-skill-links.py --plugins --no-lib --label check-skill-links

skill() {
  mkdir -p "$TMP/plugins/$1/skills/$2"
  printf -- '---\nname: %s\ndescription: Mentions /%s:other bare in frontmatter.\n---\n\n%s\n' "$2" "$1" "$3" \
    >"$TMP/plugins/$1/skills/$2/SKILL.md"
}

# shellcheck disable=SC2016  # backticks are literal markdown
skill alpha match '# Match

Run `/beta:x` (if enabled); otherwise read the file.

```text
/beta:x inside a fence
```

## Next

/alpha:differ <target>

## Related

- A wider sweep: /beta:x fix.'

skill alpha differ '# Differ

## Next

- Done: /alpha:match.
- Stale: /beta:x.'

# shellcheck disable=SC2016  # see above
skill alpha stray '# Stray

Hand off to `/beta:x fix`, then /beta:x (if enabled).'

skill beta x '# X

Then run /alpha:match on the result, and /beta:x again.'

printf '{"skills":{%s}}\n' \
  '"alpha:match":{"next":["/alpha:differ <target>"],"related":["A wider sweep: /beta:x fix"]},
   "alpha:differ":{"next":["Done: /alpha:match."],"related":["A follow-up: /alpha:stray"]},
   "beta:x":{"next":[],"related":[]}' >"$TMP/scripts/skill-links.json"

out="$(bash "$TMP/scripts/check-skill-links.sh" "$TMP" 2>"$TMP/err")"
status=$?
err="$(cat "$TMP/err")"

if [[ $status -eq 0 ]]; then ok "findings still exit 0 (report only)"; else fail "expected exit 0, got $status: $err"; fi

if [[ "$err" == *"DIFFERS: alpha:differ: next extra /beta:x; related missing /alpha:stray"* ]]; then
  ok "a differing skill names the targets missing and extra per section"
else
  fail "expected the alpha:differ line; got: $err"
fi
if [[ "$err" != *"DIFFERS: alpha:match"* && "$err" != *"NO ROW: alpha:match"* ]]; then ok "a matching skill is not reported"; else fail "alpha:match was reported: $err"; fi
if [[ "$err" == *$'NO ROW: alpha:stray\n'* ]]; then ok "a skill with no row is on its own line"; else fail "expected NO ROW: alpha:stray; got: $err"; fi

wording="$(grep '^WORDING:' <<<"$err")"
expected='WORDING: plugins/alpha/skills/stray/SKILL.md:8: /beta:x lacks "(if enabled)"
WORDING: plugins/beta/skills/x/SKILL.md:8: /alpha:match lacks "(if enabled)"'
if [[ "$wording" == "$expected" ]]; then
  ok "only unguarded optional-plugin mentions outside Next and Related are reported"
else
  fail "wording lines: wanted
$expected
got
$wording"
fi
if [[ "$out" == *"4 skills; 1 differ from the table, 1 have no row, 0 rows name no skill, 2 optional-plugin"* ]]; then
  ok "stdout carries the summary"
else
  fail "expected the summary on stdout; got: $out"
fi

rm "$TMP/scripts/skill-links.json"
bash "$TMP/scripts/check-skill-links.sh" "$TMP" >"$TMP/out" 2>"$TMP/err"
status=$?
if [[ $status -eq 2 && -s "$TMP/err" && ! -s "$TMP/out" ]]; then
  ok "a missing table exits 2 on stderr"
else
  fail "expected exit 2 with stderr only, got $status: $(cat "$TMP/out" "$TMP/err")"
fi

bash "$SCRIPT_DIR/check-skill-links.sh" >/dev/null 2>"$TMP/err"
status=$?
if [[ $status -eq 0 ]]; then ok "this checkout exits 0"; else fail "expected exit 0 on the checkout, got $status: $(cat "$TMP/err")"; fi

test_harness::report
