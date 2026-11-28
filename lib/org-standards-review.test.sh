#!/usr/bin/env bash
# test-scope: lib/org-standards.sh lib/org-standards-test-helpers.sh plugins/harness-config/skills/audit-automation-gaps/scripts/rule-inventory.sh lib/fixtures/standards-shaped/index.txt lib/fixtures/standards-shaped/review.txt
set -uo pipefail

# shellcheck source=org-standards-test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/org-standards-test-helpers.sh"

o="$TEST_TMPDIR/cite-org"
mkdir -p "$o/docs"
printf '# Rules\n' >"$o/docs/rules.md"
ln -s "$SECRET" "$o/docs/linked.md"
cat >"$o/REVIEW.md" <<'EOF'
# Org review

- keep `docs/rules.md#naming`
- climb `../../secret.md#x`
- absolute `/etc/passwd.md#x`
- linked `docs/linked.md#x`
- spaced `../x docs/rules.md#naming`
- link [a](../../secret.md#x)
EOF
tcite=$(target cite "$OPTED")
# shellcheck disable=SC2016  # the backticks are the markdown code span under test
assert_eq "org REVIEW.md: a line citing a file outside the org checkout is dropped, an in-checkout citation stays" \
  "$(listed "$(printf '# Org review\n\n- keep `docs/rules.md#naming`')" "docs/rules.md#naming${TAB}$o/docs/rules.md#naming")" \
  "$(STANDARDS_DIR="$o" composed --root "$tcite")"
assert_eq "org REVIEW.md: each dropped citation is reported with its file, line and value" \
  "org-standards: $o/REVIEW.md:4: citation ../../secret.md#x has a '..' segment; line dropped|org-standards: $o/REVIEW.md:5: citation /etc/passwd.md#x is absolute; line dropped|org-standards: $o/REVIEW.md:6: citation docs/linked.md#x resolves outside the org checkout; line dropped|org-standards: $o/REVIEW.md:7: citation ../x docs/rules.md#naming has a '..' segment; line dropped|org-standards: $o/REVIEW.md:8: citation ../../secret.md#x has a '..' segment; line dropped" \
  "$(STANDARDS_DIR="$o" errs review --root "$tcite" | paste -sd'|' -)"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/escape-cache"
noisy_tree() { printf '%s\n' "$HANDBOOK_INDEX" >"$1/docs/standards/README.md"; }
publish_tree stranger/noisy noisy_tree
NOISY=$(head_of stranger/noisy)
printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| testing | writing tests%s]0;owned%s | testing.md |\n| new%s[31mid | x | new.md |\n' \
  "$ESC" "$BEL" "$ESC" >"$TEST_TMPDIR/work/stranger/noisy/docs/standards/README.md"
push_main stranger/noisy noisy
NOISY2=$(head_of stranger/noisy)
pin stranger/noisy "$NOISY"
run subscriptions --root "$tp" >/dev/null
pin stranger/noisy "$NOISY2"
noisy=$(errs subscriptions --root "$tp")
assert_eq "a ref change prints its index diff and drift with every control character escaped" "1|1|0" \
  "$(grep -cxF '+| testing | writing tests\x1b]0;owned\x07 | testing.md |' <<<"$noisy")|$(grep -c 'index drift since .*: added new\\x1b\[31mid$' <<<"$noisy")|$(LC_ALL=C grep -c "[$ESC$BEL]" <<<"$noisy")"

o="$TEST_TMPDIR/cite-shapes-org"
mkdir -p "$o/docs"
printf '# Rules\n' >"$o/docs/rules.md"
# shellcheck disable=SC2016  # the backticks are the markdown code spans under test
{
  printf '# Org review\n'
  printf -- '- a `standards/review/<file>.md#<heading>` names a placeholder\n'
  printf -- '- b ` ../escape.md#h ` padded span\n'
  printf -- '- c `` ../escape2.md#h `` double backticks\n'
  printf -- '- d [t]( ../escape3.md#h ) padded link\n'
  printf -- '- e `../../X.MD#h` upper case\n'
  printf -- '- f `docs/rules.md#a ../../z.md#q` two citations in one span\n'
  printf -- '- g `%%2e%%2e/%%2e%%2e/x.md#h` percent escapes\n'
  printf -- '- h <a href="../../x.md#h">x</a>\n'
  printf -- '- i `../<file>.md#h` a placeholder that climbs\n'
  printf -- '- j `docs/rules.md#naming` stays\n'
  printf -- '- k red %s[31m bell %s\n' "$ESC" "$BEL"
} >"$o/REVIEW.md"
tcite=$(target cite-shapes "$OPTED")
# shellcheck disable=SC2016  # the backticks are the markdown code spans under test
assert_eq "org REVIEW.md: every citation-shaped token is checked as a reader would resolve it, and control characters are escaped" \
  "$(listed "$(printf '# Org review\n- a `standards/review/<file>.md#<heading>` names a placeholder\n- j `docs/rules.md#naming` stays\n- k red \\x1b[31m bell \\x07')" \
    "docs/rules.md#naming${TAB}$o/docs/rules.md#naming")" \
  "$(STANDARDS_DIR="$o" composed --root "$tcite")"
assert_eq "org REVIEW.md: each dropped line is reported once" "8" \
  "$(STANDARDS_DIR="$o" errs review --root "$tcite" | grep -c 'line dropped$')"

FIX="$SCRIPT_DIR/fixtures/standards-shaped"
o="$TEST_TMPDIR/standards-shaped"
mkdir -p "$o/docs/conventions" "$o/standards"
printf 'standards_dir: standards\n' >"$o/docs/conventions/standards.yaml"
cp "$FIX/index.txt" "$o/standards/README.md"
cp "$FIX/review.txt" "$o/REVIEW.md"
for f in standards/review/observability.md standards/review/error-handling.md components/dependabot-policy/README.md \
  standards/review/security.md standards/review/multi-tenancy.md; do
  mkdir -p "$o/$(dirname "$f")"
  printf '# Cited\n' >"$o/$f"
done
assert_eq "standards-shaped org: the composed criteria lose no line, report nothing, and list each citation" \
  "$(listed "$(cat "$FIX/review.txt")" \
    "standards/review/observability.md#logging${TAB}$o/standards/review/observability.md#logging" \
    "standards/review/error-handling.md#atomicity${TAB}$o/standards/review/error-handling.md#atomicity" \
    "components/dependabot-policy/README.md#merge-tiers-for-dependabot-pull-requests${TAB}$o/components/dependabot-policy/README.md#merge-tiers-for-dependabot-pull-requests" \
    "standards/review/security.md#object-level-authorization${TAB}$o/standards/review/security.md#object-level-authorization" \
    "standards/review/multi-tenancy.md#tenant-scoped-data-access${TAB}$o/standards/review/multi-tenancy.md#tenant-scoped-data-access" \
    "standards/review/security.md#secrets-and-credentials${TAB}$o/standards/review/security.md#secrets-and-credentials" \
    "standards/review/security.md#trust-boundaries-and-injection${TAB}$o/standards/review/security.md#trust-boundaries-and-injection")|" \
  "$(STANDARDS_DIR="$o" composed --root "$tcite")|$(STANDARDS_DIR="$o" errs review --root "$tcite")"
s="$o/standards"
assert_eq "standards-shaped org: the printed index keeps all 11 rows" \
  "$(printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n')
| bulk-mutation | a command or sweep that creates, deletes, or changes many objects; background or unattended runs; work spanning several targets | $s/engineering/bulk-mutation.md |
| concise-prose | writing or reviewing any prose: docs, comments, commit messages, PR bodies, replies | $s/engineering/concise-prose.md |
| configuration-switch-naming | naming or reading an environment variable, CI, organization or repository variable, or settings key that turns a behavior on or off | $s/engineering/configuration-switch-naming.md |
| design-for-change | designing or reviewing a module boundary, an extension point, configuration, dependency wiring, or a design pattern; any change whose reversal would edit many files | $s/engineering/design-for-change.md |
| deterministic-work-execution | counts, diffs, sorting, arithmetic, inventories; composing shell commands an agent runs | $s/engineering/deterministic-work-execution.md |
| documentation-and-citations | citing upstream docs; recording an external default or version; labeling the basis of a recommendation | $s/engineering/documentation-and-citations.md |
| filing-prs-and-issues | opening a pull request or filing an issue: the title rule, body sections, linkage line, issue fields per type, and the routing labels | $s/process/filing-prs-and-issues.md |
| issue-tracker | filing, titling, triaging or closing an issue; adding, renaming or deleting a label, issue field or milestone; choosing labels versus fields | $s/process/issue-tracker.md |
| reference-dont-duplicate | a fact, value, or rule appearing in more than one place; origin or history notes in code or docs | $s/engineering/reference-dont-duplicate.md |
| simpler-code | writing or reviewing code; proposing a new check, process, document, or dependency; serializing work; keeping an existing mechanism | $s/engineering/simpler-code.md |
| source-authority-tiers | grounding a recommendation, option, or decision; judging how much a source is worth | $s/engineering/source-authority-tiers.md |" \
  "$(cat "$(STANDARDS_DIR="$o" run index --root "$tcite")")"

o="$TEST_TMPDIR/split-cite-org"
mkdir -p "$o/docs"
printf '# Rules\n' >"$o/docs/rules.md"
# shellcheck disable=SC2016  # the backticks are the markdown code spans under test
{
  printf '# Org review\n'
  printf -- '- split `../../\n'
  printf 'secret.md#h` continued\n'
  printf -- '- a stray `x\n'
  printf -- '- b `../x\n'
  printf 'y.md` z\n'
  printf '\n'
  printf -- '- c `docs/rules.md#naming` stays\n'
  printf -- '- d a closing ` and an opening `` ../climb.md`` beside it\n'
} >"$o/REVIEW.md"
tsplit=$(target split-cite "$OPTED")
# shellcheck disable=SC2016  # the backticks are the markdown code spans under test
assert_eq "org REVIEW.md: a code span that crosses a line break is checked whole, and every line it covers is dropped" \
  "$(listed "$(printf '# Org review\n- a stray `x\n\n- c `docs/rules.md#naming` stays')" "docs/rules.md#naming${TAB}$o/docs/rules.md#naming")" \
  "$(STANDARDS_DIR="$o" composed --root "$tsplit")"
assert_eq "org REVIEW.md: each line a split code span covers is reported" "2|3|5|6|9" \
  "$(STANDARDS_DIR="$o" errs review --root "$tsplit" | sed -n 's/^org-standards: .*REVIEW.md:\([0-9]*\): citation .*; line dropped$/\1/p' | paste -sd'|' -)"

o="$TEST_TMPDIR/hidden-cite-org"
mkdir -p "$o"
# shellcheck disable=SC2016  # the backticks are the markdown code spans under test
{
  printf '# Org review\n'
  printf -- '- zwsp `../secret.md\342\200\213#h`\n'
  printf -- '- nbsp `../secret.md\302\240#h`\n'
  printf -- '- joined word\302\240../x.md here\n'
  printf -- '- pct `../secret%%2Emd#h` and [t](../secret.m%%64#h)\n'
  printf -- '- dblpct `../secret%%252Emd#h`\n'
  printf -- '- query `../secret.md?x#h`\n'
  printf -- '- long `../a.markdown#h`\n'
  printf -- '- bidi `../secret.md\342\200\256#h`\n'
  printf -- '- angle [t](<../a b.md>)\n'
  printf -- '- keeps `ok.md#h`\n'
} >"$o/REVIEW.md"
# shellcheck disable=SC2016  # the backticks are the markdown code span under test
assert_eq "org REVIEW.md: an invisible or format character, an encoded or queried suffix, .markdown and an angle destination hide no citation" \
  "$(listed "$(printf '# Org review\n- keeps `ok.md#h`')")" "$(STANDARDS_DIR="$o" composed --root "$tsplit")"

o="$TEST_TMPDIR/c1-org"
mkdir -p "$o"
# shellcheck disable=SC2016  # the backticks are the markdown code span under test
printf '# Org review\n- csi \302\233[31m red\n- cite `../a\302\233.md`\n' >"$o/REVIEW.md"
assert_eq "org REVIEW.md: a C1 control character is escaped in the criteria and in the report" \
  "$(listed "$(printf '# Org review\n- csi \\x9b[31m red')")|0" \
  "$(STANDARDS_DIR="$o" composed --root "$tsplit")|$(STANDARDS_DIR="$o" errs review --root "$tsplit" | LC_ALL=C grep -c $'\302[\200-\237]')"

printf -- '---\nstandards-contract: 1.%s\nstandards_repositories:\n  - repo: x%s]0;T%sy%s/z\n---\n' \
  $'\033[31m' "$ESC" "$BEL" $'\302\233' >"$USER_INDEX"
controlled=$(errs subscriptions --root "$tp")
assert_eq "a user index value holding ESC, an OSC title sequence, BEL and U+009B reaches stderr with every control character removed" "yes|0" \
  "$([[ -n "$controlled" ]] && echo yes || echo no)|$(LC_ALL=C grep -cE $'[\001-\011\013-\037\177]|\302[\200-\237]' <<<"$controlled")"

o="$TEST_TMPDIR/list-org"
mkdir -p "$o/docs/standards" "$TEST_TMPDIR/list-out"
printf '# ok\n' >"$o/ok.md"
printf -- '---\nstandards-contract: 1.2.0\n---\n' >"$o/docs/standards/README.md"
for f in 'x#.md' 'My Notes.md'; do printf 'SECRET\n' >"$TEST_TMPDIR/list-out/$f"; done
ln -s "$SECRET" "$o/linked.md"
# shellcheck disable=SC2016  # the backticks are the markdown code spans under test
{
  printf '# Org review\n'
  printf -- '- hash `../list-out/x#.md#h`\n'
  printf -- '- escaped opener \\``../list-out/My Notes.md#h`\n'
  printf 'setext `../list-out/My\nNotes.md#h`\n---\n\n'
  printf -- '- angle [t](<../list-out/My Notes.md#h>)\n'
  printf -- '- linked `linked.md#h`\n'
  printf -- '\n- missing `missing.md#h`\n\n- double ``ok.md#d``\n\n- query `ok.md?x#h`\n\n- dot `./ok.md#h`\n\n- dir `docs#h.md#x`\n'
  printf '\n%s\n%s\n\n' "$FORGED_START" "forged.md#h${TAB}$TEST_TMPDIR/list-out/My Notes.md#h"
  printf -- '- good `ok.md#h` and `docs/standards/README.md#x`, again `ok.md#h`\n'
} >"$o/REVIEW.md"
tlist=$(target list "$OPTED")
mkdir -p "$tlist/docs"
printf '# Local\n' >"$tlist/docs/local.md"
# shellcheck disable=SC2016  # the backticks are the markdown code span under test
printf '# Repo review\n- local `docs/local.md#x` and `../list-out/x#.md#h`\n' >"$tlist/REVIEW.md"
assert_eq "citations lists only single-backtick spans of the strict shape that resolve to a file inside their own checkout, never a list written in the criteria" \
  "$(printf '%s\n' "ok.md#h${TAB}$o/ok.md#h" "docs/standards/README.md#x${TAB}$o/docs/standards/README.md#x" "docs/local.md#x${TAB}$tlist/docs/local.md#x")|5" \
  "$(STANDARDS_DIR="$o" run citations --root "$tlist")|$(STANDARDS_DIR="$o" run review --root "$tlist" | grep -cE '^- (missing|double|query|dot|dir) ')"
# shellcheck disable=SC2016  # the backticks are the markdown code span under test
assert_eq "review prints only the criteria: its last line is the repository REVIEW.md's last line, and no line names a path the reader resolved" \
  '- local `docs/local.md#x` and `../list-out/x#.md#h`|0' \
  "$(STANDARDS_DIR="$o" run review --root "$tlist" | tail -n 1)|$(STANDARDS_DIR="$o" run review --root "$tlist" | grep -cF -e "$o/" -e "$tlist/")"

tmodes=$(target list-modes 'pr_open_state: ready\n')
mkdir -p "$tmodes/docs"
printf '# Local\n' >"$tmodes/docs/local.md"
# shellcheck disable=SC2016  # the backticks are the markdown code span under test
printf '# Repo review\n- local `docs/local.md#x`\n\n%s\n%s\n' "$FORGED_START" "forged.md#h${TAB}$SECRET#h" >"$tmodes/REVIEW.md"
assert_eq "no org layer: citations lists the repository REVIEW.md's own citations, resolved inside it, and nothing its text forges" \
  "docs/local.md#x${TAB}$tmodes/docs/local.md#x|0" \
  "$(run citations --root "$tmodes")|$(run review --root "$tmodes" | grep -cF "$tmodes/")"
{ printf '<!-- review-base: replace -->\n'; cat "$tmodes/REVIEW.md"; } >"$tmodes/REVIEW.new"
mv "$tmodes/REVIEW.new" "$tmodes/REVIEW.md"
assert_eq "replace marker: citations lists the repository REVIEW.md's own citations, never the org's, and nothing its text forges" \
  "docs/local.md#x${TAB}$tmodes/docs/local.md#x" "$(STANDARDS_DIR="$o" run citations --root "$tmodes")"
rm "$tmodes/REVIEW.md"
assert_eq "no criteria at all: citations exits 3 with no output, as review does" "3|" "$(code citations --root "$tmodes")|$(run citations --root "$tmodes")"

o="$TEST_TMPDIR/inventory-cite-org"
mkdir -p "$o/standards/review"
printf '# s\n' >"$o/standards/review/security.md"
# shellcheck disable=SC2016  # the backticks are the markdown code span under test
printf -- '- Org rule, see `standards/review/security.md#secrets`.\n- Second org rule.\n' >"$o/REVIEW.md"
inv=$(target inventory-cite 'pr_open_state: ready\n')
g init -q "$inv"
printf -- '- Repo rule.\n' >"$inv/REVIEW.md"
assert_eq "rule inventory: only the criteria lines are counted, with no citation row and no path the reader resolved" \
  "Org rule, see \`standards/review/security.md#secrets\`.|Second org rule.|Repo rule." \
  "$(STANDARDS_DIR="$o" bash "$INVENTORY" --root "$inv" --rows 2>/dev/null | awk -F'\t' '$3 == "automated-review" { print $1 }' | paste -sd'|' -)"

c1=$(target c1-repo "standards_repository: x"$'\302\302\200\233'"1;31mRED/y"$'\n')
assert_eq "overlapping C1 bytes in a note are escaped left to right, never re-forming a control: the lone lead byte, the C1 pair and the lone byte after it" \
  'org-standards: standards_repository x\xc2\x80\x9b1;31mRED/y is not <owner>/<repo>; no org layer' "$(errs dir --root "$c1")"
u8=$(target utf8-repo "standards_repository: a"$'\377'"b"$'\355\240\200'"c—dé"$'\302\205'"f"$'\n')
assert_eq "invalid UTF-8 in a note is escaped byte by byte, while valid characters pass unchanged and a C1 character is escaped" \
  'org-standards: standards_repository a\xffb\xed\xa0\x80c—dé\x85f is not <owner>/<repo>; no org layer' "$(errs dir --root "$u8")"

c1diff_tree() { printf '%s\n' "$HANDBOOK_INDEX" >"$1/docs/standards/README.md"; }
publish_tree stranger/c1diff c1diff_tree
C1A=$(head_of stranger/c1diff)
printf 'Prose \302\302\200\2331;31mRED\n' >>"$TEST_TMPDIR/work/stranger/c1diff/docs/standards/README.md"
push_main stranger/c1diff c1
pin stranger/c1diff "$C1A"
run subscriptions --root "$tp" >/dev/null
pin stranger/c1diff "$(head_of stranger/c1diff)"
c1d=$(errs subscriptions --root "$tp")
assert_eq "a ref change's index diff escapes overlapping C1 bytes left to right and leaves no control byte" "1|0" \
  "$(grep -cxF '+Prose \xc2\x80\x9b1;31mRED' <<<"$c1d")|$(LC_ALL=C grep -c $'[\001-\010\013-\037\177\200-\237]' <<<"$c1d")"

CTL=$'\033[31m\033]0;T\007\302\233'
SHOWN='\x1b[31m\x1b]0;T\x07\x9b'
ctl_org="$TEST_TMPDIR/ctl-org$CTL"
mkdir -p "$ctl_org/docs/standards"
printf '# Org\n' >"$ctl_org/REVIEW.md"
printf -- '---\nstandards-contract: 1.2.0\n---\n\377\n' >"$ctl_org/docs/standards/README.md"
row_org="$TEST_TMPDIR/ctl-rows"
mkdir -p "$row_org/docs/standards"
printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| a%s | x | a.md |\n| b | x%s\377 | b.md |\n| c | x | c%s.md |\n' \
  "$CTL" "$CTL" "$CTL" >"$row_org/docs/standards/README.md"
ctl_root="$TEST_TMPDIR/ctl-root$CTL"
mkdir -p "$ctl_root/docs/standards"
printf -- '---\nstandards-contract: 1.3.0\ntrusted_owners:\n  - acme\n---\n\377\n' >"$ctl_root/docs/standards/README.md"
ctl_repo=$(target ctl-repo "standards_repository: o/r$CTL"$'\n')
ctl_opted=$(target ctl-opted "$OPTED")
pin stranger/guide "$GUIDE"
ctl_out=$(
  for c in dir index review citations; do LC_ALL=C.UTF-8 STANDARDS_DIR="$ctl_org" bash "$SCRIPT" "$c" --root "$tp" 2>&1; echo "exit=$?"; done
  for c in dir review; do LC_ALL=C.UTF-8 bash "$SCRIPT" "$c" --root "$ctl_repo" 2>&1; echo "exit=$?"; done
  for c in dir subscriptions; do LC_ALL=C.UTF-8 ORG_STANDARDS_CACHE="$TEST_TMPDIR/ctl-cache$CTL" bash "$SCRIPT" "$c" --root "$ctl_opted" 2>&1; echo "exit=$?"; done
  LC_ALL=C.UTF-8 STANDARDS_DIR="$row_org" bash "$SCRIPT" index --root "$tp" 2>&1 >"$TEST_TMPDIR/ctl-rows.out"
  cat "$TEST_TMPDIR/ctl-rows.out" "$(tail -n 1 "$TEST_TMPDIR/ctl-rows.out")"
  LC_ALL=C.UTF-8 bash "$SCRIPT" subscriptions --root "$ctl_root" 2>&1
)
assert_eq "control characters in STANDARDS_DIR, the cache path, standards_repository, the root and index rows reach neither stdout nor stderr raw" \
  "0|4|2|4|2|2|2|1|1|1|1|0" \
  "$(LC_ALL=C grep -c $'[\001-\010\013-\037\177\200-\237]' <<<"$ctl_out")|$(grep -cF "STANDARDS_DIR $TEST_TMPDIR/ctl-org$SHOWN holds a control character or invalid UTF-8; no org layer" <<<"$ctl_out")|$(grep -cx 'exit=4' <<<"$ctl_out")|$(grep -cx 'exit=3' <<<"$ctl_out")|$(grep -cF "standards_repository o/r$SHOWN is not <owner>/<repo>" <<<"$ctl_out")|$(grep -cF "the cache directory $TEST_TMPDIR/ctl-cache$SHOWN holds a control character" <<<"$ctl_out")|$(grep -cx 'exit=2' <<<"$ctl_out")|$(grep -cF "Surface a$SHOWN is not an id" <<<"$ctl_out")|$(grep -cF "| b | x$SHOWN\\xff | " <<<"$ctl_out")|$(grep -cF "File c$SHOWN.md is not a relative forward-slash path" <<<"$ctl_out")|$(grep -cF "$TEST_TMPDIR/ctl-root$SHOWN/docs/standards/README.md:3: trusted_owners is read from the user-global index only" <<<"$ctl_out")|$(grep -c 'warning' <<<"$ctl_out")"

ctl_plain=$(target ctl-plain 'pr_open_state: ready\n')
printf '# Local\n' >"$ctl_plain/REVIEW.md"
user_index ''
ctl_free=$(
  LC_ALL=C.UTF-8 ORG_STANDARDS_CACHE="$TEST_TMPDIR/ctl-cache$CTL" bash "$SCRIPT" review --root "$ctl_plain" 2>&1; echo "exit=$?"
  LC_ALL=C.UTF-8 ORG_STANDARDS_CACHE="$TEST_TMPDIR/ctl-cache$CTL" bash "$SCRIPT" citations --root "$ctl_plain" 2>&1; echo "exit=$?"
  LC_ALL=C.UTF-8 ORG_STANDARDS_CACHE="$TEST_TMPDIR/ctl-cache$CTL" bash "$SCRIPT" subscriptions --root "$ctl_plain" 2>&1; echo "exit=$?"
  env -u ORG_STANDARDS_CACHE LC_ALL=C.UTF-8 XDG_CACHE_HOME="$TEST_TMPDIR/ctl-xdg$CTL" bash "$SCRIPT" review --root "$ctl_plain" 2>&1; echo "exit=$?"
)
assert_eq "a control character in the cache path stops no command that needs no cache: no org layer and no subscription read as usual" \
  "$(printf '# Local\nexit=0\nexit=0\nexit=0\n# Local\nexit=0')" "$ctl_free"

finish
