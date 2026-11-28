#!/usr/bin/env bash
# test-scope: lib/org-standards.sh lib/org-standards-test-helpers.sh
set -uo pipefail

# shellcheck source=org-standards-test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/org-standards-test-helpers.sh"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/guidance-cache"
CONFINED="$ORG_STANDARDS_CACHE/.state/confined"
HEAD_ROW='| Surface | Applies when | File |
|---|---|---|'
GUIDANCE_INDEX='---
standards-contract: 2.0.0
---

# Guidance

Positions to weigh, never rules.

| Surface | Applies when | File |
|---|---|---|
| design.coupling | splitting modules | design/coupling.md |
| testing.doubles | choosing a test double | testing/doubles.md |'

guidance_files() {
  mkdir -p "$1/guidance/design" "$1/guidance/testing"
  printf '%s\n' "$GUIDANCE_INDEX" >"$1/guidance/README.md"
  printf '# Coupling\n' >"$1/guidance/design/coupling.md"
  printf '# Doubles\n' >"$1/guidance/testing/doubles.md"
}
guided_org_tree() {
  mkdir -p "$1/docs/conventions" "$1/standards"
  printf 'standards_dir: standards\nguidance_dir: guidance\nstandards_repositories:\n  - repo: acme/handbook\n  - repo: stranger/other\n' \
    >"$1/docs/conventions/standards.yaml"
  printf -- '---\nstandards-contract: 2.0.0\n---\n\n%s\n| naming | naming things | naming.md |\n' "$HEAD_ROW" >"$1/standards/README.md"
  printf '# Naming\n' >"$1/standards/naming.md"
  printf '# Org review\n' >"$1/REVIEW.md"
  guidance_files "$1"
}
guided_layer_tree() {
  mkdir -p "$1/docs/conventions"
  printf 'guidance_dir: guidance\n' >"$1/docs/conventions/standards.yaml"
  printf '%s\n' "$HANDBOOK_INDEX" >"$1/docs/standards/README.md"
  printf '# Naming\n' >"$1/docs/standards/naming.md"
  printf '# Testing\n' >"$1/docs/standards/testing.md"
  guidance_files "$1"
}
advice_tree() {
  mkdir -p "$1/docs/conventions"
  printf 'guidance_dir: guidance\n' >"$1/docs/conventions/standards.yaml"
  guidance_files "$1"
}
guidance_printed() {
  printf -- '---\nstandards-contract: 2.0.0\nkind: guidance\n---\n\n%s' "$HEAD_ROW"
  [[ "${2:-design.coupling}" != *design.coupling* ]] || printf '\n| design.coupling | splitting modules | %s/guidance/design/coupling.md |' "$1"
  [[ "${2:-testing.doubles}" != *testing.doubles* ]] || printf '\n| testing.doubles | choosing a test double | %s/guidance/testing/doubles.md |' "$1"
}

publish_tree acme/guide-org guided_org_tree
publish_tree acme/guided guided_layer_tree
publish_tree stranger/advice advice_tree
GUIDED=$(head_of acme/guided)
ADVICE=$(head_of stranger/advice)
ORG_CO="$ORG_STANDARDS_CACHE/acme/guide-org"
GUIDED_CO="$ORG_STANDARDS_CACHE/acme/guided@$GUIDED"
ADVICE_CO="$ORG_STANDARDS_CACHE/stranger/advice@$ADVICE"
tg=$(target guided $'standards_repository: acme/guide-org\n')

printed=$(run guidance --root "$tg")
assert_eq "guidance: prints the org layer's guidance index as a copy under the reader's state, marked kind: guidance, its rows resolved inside the org checkout" \
  "$CONFINED|$(guidance_printed "$ORG_CO")" "$(dirname "$printed")|$(cat "$printed")"
assert_eq "index: the org standards index the same concern file names carries no kind line" \
  "$(printf -- '---\nstandards-contract: 2.0.0\n---\n\n%s\n| naming | naming things | %s/standards/naming.md |' "$HEAD_ROW" "$ORG_CO")" \
  "$(cat "$(run index --root "$tg")")"
assert_eq "guidance: the org layer's REVIEW.md criteria are unchanged by a guidance index" "# Org review" "$(run review --root "$tg")"

o="$TEST_TMPDIR/no-guidance"
mkdir -p "$o/docs/standards"
printf -- '---\nstandards-contract: 2.0.0\n---\n' >"$o/docs/standards/README.md"
guidance_files "$o"
assert_eq "guidance: no guidance_dir means no guidance index, even with a guidance folder present: exit 5, said on stderr" "5|1" \
  "$(STANDARDS_DIR="$o" code guidance --root "$tg")|$(STANDARDS_DIR="$o" errs guidance --root "$tg" | grep -cxF "org-standards: $o has no guidance index")"
mkdir -p "$o/docs/conventions"
printf 'guidance_dir: ../outside\n' >"$o/docs/conventions/standards.yaml"
assert_eq "guidance: a guidance_dir with a '..' segment is no usable index: exit 5, naming the file and key" "5|1" \
  "$(STANDARDS_DIR="$o" code guidance --root "$tg")|$(STANDARDS_DIR="$o" errs guidance --root "$tg" | grep -c "^org-standards: $o/docs/conventions/standards.yaml: guidance_dir ../outside has a '..' segment; no usable index")"
printf 'guidance_dir: guidance\n' >"$o/docs/conventions/standards.yaml"
printf '# not an index\n' >"$o/guidance/README.md"
assert_eq "guidance: a guidance README without the standards-contract key is no index: exit 5" "5" "$(STANDARDS_DIR="$o" code guidance --root "$tg")"

o="$TEST_TMPDIR/old-concern"
mkdir -p "$o/.claude" "$o/std" "$o/docs/standards"
printf 'standards_dir: std\nguidance_dir: std\n' >"$o/.claude/standards.yaml"
printf -- '---\nstandards-contract: 1.3.1\n---\n\n%s\n| moved | x | moved.md |\n' "$HEAD_ROW" >"$o/std/README.md"
printf -- '---\nstandards-contract: 1.3.1\n---\n\n%s\n| default | x | default.md |\n' "$HEAD_ROW" >"$o/docs/standards/README.md"
assert_eq "an org layer with only .claude/standards.yaml: its keys are not read, so index reads the default folder" \
  "$(printf -- '---\nstandards-contract: 1.3.1\n---\n\n%s\n| default | x | %s/docs/standards/default.md |' "$HEAD_ROW" "$o")" \
  "$(cat "$(STANDARDS_DIR="$o" run index --root "$tg")")"
assert_eq "an org layer with only .claude/standards.yaml is told the file moved" "1" \
  "$(STANDARDS_DIR="$o" errs index --root "$tg" | grep -cxF "org-standards: $o/.claude/standards.yaml: moved to docs/conventions/standards.yaml in standards-contract 2.0.0; not read")"
assert_eq "an org layer with only .claude/standards.yaml has no guidance index: exit 5" "5" "$(STANDARDS_DIR="$o" code guidance --root "$tg")"
mkdir -p "$o/docs/conventions"
printf 'standards_dir: std\n' >"$o/docs/conventions/standards.yaml"
assert_eq "beside docs/conventions/standards.yaml an old .claude/standards.yaml is not mentioned" "0" \
  "$(STANDARDS_DIR="$o" errs index --root "$tg" | grep -c 'moved to')"

tp2=$(target guided-plain 'pr_open_state: ready\n')
user_index "standards_repositories:
  - repo: acme/guided
    ref: $GUIDED
  - repo: stranger/advice
    ref: $ADVICE
"
lines=$(run subscriptions --root "$tp2")
assert_eq "subscriptions: each line carries a fourth field, the layer's printed guidance index, or - when it has none" \
  "acme/guided@$GUIDED	$GUIDED_CO	$CONFINED	$CONFINED|stranger/advice@$ADVICE	$ADVICE_CO	-	$CONFINED" \
  "$(while IFS=$'\t' read -r l c i g; do
      [[ "$i" == - ]] || i=$(dirname "$i")
      printf '%s\t%s\t%s\t%s\n' "$l" "$c" "$i" "$(dirname "$g")"
    done <<<"$lines" | paste -sd'|' -)"
assert_eq "subscriptions: the printed guidance index is marked kind: guidance and resolves its rows inside the layer's checkout" \
  "$(guidance_printed "$GUIDED_CO")" "$(cat "$(head -n 1 <<<"$lines" | cut -f4)")"
assert_eq "subscriptions: the printed standards index of a layer with both is unchanged" \
  "$(handbook_confined "$GUIDED_CO")" "$(cat "$(head -n 1 <<<"$lines" | cut -f3)")"

user_index "standards_repositories:
  - repo: acme/guided
    ref: $GUIDED
    surfaces:
      - naming
      - design.coupling
      - nope
"
filtered=$(run subscriptions --root "$tp2")
assert_eq "surfaces: one entry's list filters both of the layer's indexes" \
  "$(printf -- '---\nstandards-contract: 1.2.0\n---\n\n%s\n| naming | naming things | %s/docs/standards/naming.md |' "$HEAD_ROW" "$GUIDED_CO")|$(guidance_printed "$GUIDED_CO" design.coupling)" \
  "$(cat "$(cut -f3 <<<"$filtered")")|$(cat "$(cut -f4 <<<"$filtered")")"
assert_eq "surfaces: a surface in neither index is reported, and the ones found in either are not" "1|0|0" \
  "$(errs subscriptions --root "$tp2" | grep -c "surface nope is not a Surface id in any index of acme/guided@${GUIDED:0:12}")|$(errs subscriptions --root "$tp2" | grep -c 'surface naming')|$(errs subscriptions --root "$tp2" | grep -c 'surface design.coupling')"

user_index "standards_repositories:
  - repo: acme/guided
    ref: $GUIDED
    topics:
      - naming
  - repo: stranger/advice
    ref: $ADVICE
"
assert_eq "topics: an entry still using topics is skipped, and the rest of the list is read" "stranger/advice@$ADVICE" \
  "$(run subscriptions --root "$tp2" | cut -f1)"
assert_eq "topics: the skipped entry is reported with its file and line, naming the rename" "1" \
  "$(errs subscriptions --root "$tp2" | grep -cxF "org-standards: $USER_INDEX:4: malformed subscription (topics was renamed surfaces in standards-contract 2.0.0); entry skipped")"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/guidance-drift-cache"
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/guided\n'
run subscriptions --root "$tp2" >/dev/null
printf '| review.size | sizing a pull request | review/size.md |\n' >>"$TEST_TMPDIR/work/acme/guided/guidance/README.md"
push_main acme/guided "guidance v2"
drift=$(ORG_STANDARDS_TTL=0 bash "$SCRIPT" subscriptions --root "$tp2" 2>&1 >/dev/null)
assert_eq "guidance drift: a Surface id added to a live layer's guidance index is reported as guidance index drift" "1" \
  "$(grep -cxF "org-standards: acme/guided: guidance index drift since ${GUIDED:0:12}: added review.size" <<<"$drift")"
assert_eq "guidance drift: an unchanged standards index reports no drift" "0" "$(grep -c 'acme/guided: index drift' <<<"$drift")"

printf '| new.thing | x | new.md |\n' >>"$TEST_TMPDIR/work/stranger/advice/guidance/README.md"
push_main stranger/advice "advice v2"
ADVICE2=$(head_of stranger/advice)
user_index "standards_repositories:
  - repo: stranger/advice
    ref: $ADVICE
"
run subscriptions --root "$tp2" >/dev/null
user_index "standards_repositories:
  - repo: stranger/advice
    ref: $ADVICE2
"
changed=$(bash "$SCRIPT" subscriptions --root "$tp2" 2>&1 >/dev/null)
assert_eq "a ref change prints the guidance index diff for review, labeled as the guidance index" "1|1|1" \
  "$(grep -c "ref of stranger/advice changed from ${ADVICE:0:12} to ${ADVICE2:0:12}" <<<"$changed")|$(grep -cxF -- "+++ stranger/advice@${ADVICE2:0:12} guidance index" <<<"$changed")|$(grep -cxF '+| new.thing | x | new.md |' <<<"$changed")"

user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/guided\n'
GUIDED2=$(head_of acme/guided)
: >"$TEST_TMPDIR/work/acme/guided/docs/conventions/standards.yaml"
push_main acme/guided "no guidance"
GUIDED3=$(head_of acme/guided)
gone=$(ORG_STANDARDS_TTL=0 bash "$SCRIPT" subscriptions --root "$tp2" 2>&1 >/dev/null)
assert_eq "guidance drift: a live layer's guidance index that disappears reports each of its rows removed" "1|1" \
  "$(grep -cxF "org-standards: acme/guided: guidance index drift since ${GUIDED2:0:12}: removed design.coupling" <<<"$gone")|$(grep -cxF "org-standards: acme/guided: guidance index drift since ${GUIDED2:0:12}: removed testing.doubles" <<<"$gone")"
printf 'guidance_dir: guidance\n' >"$TEST_TMPDIR/work/acme/guided/docs/conventions/standards.yaml"
push_main acme/guided "guidance back"
GUIDED4=$(head_of acme/guided)
pin acme/guided "$GUIDED3"
run subscriptions --root "$tp2" >/dev/null
pin acme/guided "$GUIDED4"
back=$(bash "$SCRIPT" subscriptions --root "$tp2" 2>&1 >/dev/null)
assert_eq "a ref change to a commit whose guidance index first appears prints its diff from empty and reports each row added" "1|1|1" \
  "$(grep -cxF -- "+++ acme/guided@${GUIDED4:0:12} guidance index" <<<"$back")|$(grep -cxF '+| design.coupling | splitting modules | design/coupling.md |' <<<"$back")|$(grep -cxF "org-standards: acme/guided: guidance index drift since ${GUIDED3:0:12}: added design.coupling" <<<"$back")"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/list-cache"
ORG_CO="$ORG_STANDARDS_CACHE/acme/guide-org"
HANDBOOK_NOW=$(head_of acme/handbook)
user_index $'trusted_owners:\n  - acme\n'
assert_eq "team list: with the org repository's owner trusted, its concern file's list is read, live for a trusted owner" \
  "acme/handbook@$HANDBOOK_NOW" "$(run subscriptions --root "$tg" | cut -f1)"
assert_eq "team list: an unpinned entry of an untrusted owner in it is refused, naming the org concern file and line" "1" \
  "$(errs subscriptions --root "$tg" | grep -c "^org-standards: $ORG_CO/docs/conventions/standards.yaml:5: stranger/other is not pinned")"
user_index $'trusted_owners:\n  - stranger\n'
assert_eq "team list: with the org repository's owner not trusted, its list is not read" "" "$(run subscriptions --root "$tg")"
rm -f "$USER_INDEX"
assert_eq "team list: with no user-global index, no list is read" "" "$(run subscriptions --root "$tg")"

repo_list() { printf 'standards_repositories:\n%s' "$1" >"$2/docs/conventions/standards.yaml"; }
tr_=$(target repo-list $'standards_repository: acme/guide-org\n')
mkdir -p "$tr_/docs/conventions"
repo_list "  - repo: stranger/guide
    ref: $GUIDE
" "$tr_"
g init -q -b main "$tr_"
g -C "$tr_" add -A
g -C "$tr_" commit -q -m init
g -C "$tr_" remote add origin git@github.com:acme/app.git
g -C "$tr_" update-ref refs/remotes/origin/main HEAD
user_index "trusted_owners:
  - acme
standards_repositories:
  - repo: stranger/advice
    ref: $ADVICE
"
assert_eq "order: the team list, then the repository list read from the default branch, then the personal list" \
  "acme/handbook@$HANDBOOK_NOW|stranger/guide@$GUIDE|stranger/advice@$ADVICE" "$(run subscriptions --root "$tr_" | cut -f1 | paste -sd'|' -)"
user_index "trusted_owners:
  - acme
standards_repositories:
  - repo: stranger/advice
    ref: $ADVICE
  - repo: acme/handbook
"
assert_eq "order: a repository the team list and the personal list both name is read at its personal listing" \
  "stranger/guide@$GUIDE|stranger/advice@$ADVICE|acme/handbook@$HANDBOOK_NOW" "$(run subscriptions --root "$tr_" | cut -f1 | paste -sd'|' -)"
assert_eq "order: a repository listed twice is read once, at its last listing, and the earlier listing is reported" "1" \
  "$(errs subscriptions --root "$tr_" | grep -cxF "org-standards: $ORG_CO/docs/conventions/standards.yaml:4: acme/handbook is listed again at $USER_INDEX:8; it is read once, there")"

OTHER=$(head_of stranger/other)
repo_list "  - repo: stranger/guide
    ref: $GUIDE
  - repo: stranger/other
    ref: $OTHER
trusted_owners:
  - stranger
" "$tr_"
assert_eq "repository list: an entry only in the working tree is not read" \
  "stranger/guide@$GUIDE|stranger/advice@$ADVICE|acme/handbook@$HANDBOOK_NOW" "$(run subscriptions --root "$tr_" | cut -f1 | paste -sd'|' -)"
assert_eq "repository list: a trusted_owners key in the repository's concern file is reported as ignored" "1" \
  "$(errs subscriptions --root "$tr_" | grep -cxF "org-standards: $tr_/docs/conventions/standards.yaml:6: trusted_owners is read from the user-global index only; ignored here")"
g -C "$tr_" commit -q -am trunk
g -C "$tr_" update-ref refs/remotes/origin/trunk HEAD
g -C "$tr_" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
assert_eq "repository list: the default branch origin/HEAD names is the one read" \
  "stranger/guide@$GUIDE|stranger/other@$OTHER|stranger/advice@$ADVICE|acme/handbook@$HANDBOOK_NOW" "$(run subscriptions --root "$tr_" | cut -f1 | paste -sd'|' -)"
assert_eq "repository list: its notes name the default branch and file" "1" \
  "$(errs subscriptions --root "$tr_" | grep -cxF "org-standards: origin/trunk:docs/conventions/standards.yaml:6: trusted_owners is read from the user-global index only; ignored here")"
user_index "trusted_owners:
  - stranger
standards_repositories:
  - repo: stranger/advice
    ref: $ADVICE
"
assert_eq "repository list: with the repository's owner not trusted, its list is not read" "stranger/advice@$ADVICE" \
  "$(run subscriptions --root "$tr_" | cut -f1 | paste -sd'|' -)"

finish
