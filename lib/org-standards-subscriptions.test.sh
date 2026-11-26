#!/usr/bin/env bash
# test-scope: lib/org-standards.sh lib/org-standards-test-helpers.sh plugins/harness-config/skills/audit-automation-gaps/scripts/rule-inventory.sh
set -uo pipefail

# shellcheck source=org-standards-test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/org-standards-test-helpers.sh"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/sub-cache"

assert_eq "the fixture remote serves any commit by SHA, as GitHub does" "true" \
  "$(g -C "$TEST_TMPDIR/git/stranger/guide.git" config uploadpack.allowAnySHA1InWant)"
assert_eq "the fixture remote leaves allowReachableSHA1InWant unset" "" \
  "$(g -C "$TEST_TMPDIR/git/stranger/guide.git" config uploadpack.allowReachableSHA1InWant)"

t=$(target subs 'pr_open_state: ready\n')

rm -f "$USER_INDEX"
assert_eq "no user index: no subscribed layers, exit 0" "0|" "$(code subscriptions --root "$t")|$(run subscriptions --root "$t")"
user_index ''
assert_eq "a user index with no list: no subscribed layers" "" "$(run subscriptions --root "$t")"

user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
assert_eq "live trusted: main is read, keyed by its commit" \
  "$(expect_layer acme/handbook "$HANDBOOK")" "$(run subscriptions --root "$t" | shown)"

user_index "standards_repositories:
  - repo: stranger/guide
    ref: $GUIDE
"
assert_eq "pinned untrusted: the pinned commit is read" \
  "$(expect_layer stranger/guide "$GUIDE")" "$(run subscriptions --root "$t" | shown)"

user_index $'standards_repositories:\n  - repo: stranger/other\n'
assert_eq "unpinned untrusted: refused, nothing read" "" "$(run subscriptions --root "$t")"
assert_eq "unpinned untrusted: the refusal names the file and line" "1" \
  "$(errs subscriptions --root "$t" | grep -c "^org-standards: $USER_INDEX:4: stranger/other is not pinned")"

user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n    topics:\n      - naming\n'
filtered=$(run subscriptions --root "$t" | cut -f3)
assert_eq "topic filter: the index keeps only the rows of the named Surface ids" \
  "$(printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| naming | naming things | %s/acme/handbook@%s/docs/standards/naming.md |' "$ORG_STANDARDS_CACHE" "$HANDBOOK")" \
  "$(cat "$filtered")"
assert_eq "topic filter: the filtered index is the reader's copy under its state" \
  "$ORG_STANDARDS_CACHE/.state/confined" "$(dirname "$filtered")"
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n    topics:\n      - nope\n'
assert_eq "topic filter: a topic the index lacks is reported" "1" \
  "$(errs subscriptions --root "$t" | grep -c 'topic nope is not a Surface id')"

scoped=$(target scoped 'pr_open_state: ready\n')
g init -q "$scoped"
g -C "$scoped" remote add origin git@github.com:Acme/App.git
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n    only_in:\n      - acme/app\n'
assert_eq "only_in: a matching origin reads the subscription" "acme/handbook@$HANDBOOK" "$(run subscriptions --root "$scoped" | cut -f1)"
assert_eq "only_in: a repository with another origin skips it" "" "$(run subscriptions --root "$t")"
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n    only_in:\n      - acme\n'
assert_eq "only_in: an owner alone matches every repository of that owner" "acme/handbook@$HANDBOOK" "$(run subscriptions --root "$scoped" | cut -f1)"
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n    except_in:\n      - "acme/a*"\n'
assert_eq "except_in: a matching glob skips the subscription" "" "$(run subscriptions --root "$scoped")"
assert_eq "except_in: a repository it does not match reads it" "acme/handbook@$HANDBOOK" "$(run subscriptions --root "$t" | cut -f1)"

user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
assert_eq "session switch: STANDARDS_SUBSCRIPTIONS_DISABLED=true reads no subscription" "" \
  "$(STANDARDS_SUBSCRIPTIONS_DISABLED=true run subscriptions --root "$t")"
assert_eq "session switch: any other value leaves subscriptions on" "acme/handbook@$HANDBOOK" \
  "$(STANDARDS_SUBSCRIPTIONS_DISABLED=false run subscriptions --root "$t" | cut -f1)"

both=$(target both $'standards_repository: Stranger/Guide\n')
user_index "standards_repositories:
  - repo: acme/handbook
    ref: $HANDBOOK
  - repo: stranger/guide
    ref: $GUIDE
"
assert_eq "both scopes: a repository that is also the org layer is not read again as a subscription" \
  "acme/handbook@$HANDBOOK" "$(run subscriptions --root "$both" | cut -f1)"
assert_eq "both scopes: the skipped pin is reported" "1" \
  "$(errs subscriptions --root "$both" | grep -c "^org-standards: $USER_INDEX:6: stranger/guide is also this repository's org layer.*pin ${GUIDE:0:12} skipped")"

layered=$(target layered $'trusted_owners:\n  - stranger\n')
mkdir -p "$layered/docs/standards"
printf -- '---\nstandards-contract: 1.3.0\ntrusted_owners:\n  - stranger\n---\n' >"$layered/docs/standards/README.md"
user_index $'standards_repositories:\n  - repo: stranger/other\n'
assert_eq "a repository-layer trusted_owners is ignored: the unpinned subscription stays refused" "" \
  "$(run subscriptions --root "$layered")"
assert_eq "a repository-layer trusted_owners is reported as ignored, naming each file and line" \
  "org-standards: $layered/docs/conventions/source-control.yaml:1: trusted_owners is read from the user-global index only; ignored here|org-standards: $layered/docs/standards/README.md:3: trusted_owners is read from the user-global index only; ignored here" \
  "$(errs subscriptions --root "$layered" | grep 'ignored here' | paste -sd'|' -)"
for spelling in '"trusted_owners": [stranger]' 'trusted_owners : [stranger]' "'trusted_owners':"$'\n  - stranger'; do
  printf 'pr_open_state: ready\n%s\n' "$spelling" >"$layered/docs/conventions/source-control.yaml"
  printf -- '---\nstandards-contract: 1.3.0\n%s\n---\n' "$spelling" >"$layered/docs/standards/README.md"
  assert_eq "a repository-layer trusted_owners written as $spelling is reported as ignored, naming each file and line" \
    "org-standards: $layered/docs/conventions/source-control.yaml:2: trusted_owners is read from the user-global index only; ignored here|org-standards: $layered/docs/standards/README.md:3: trusted_owners is read from the user-global index only; ignored here" \
    "$(errs subscriptions --root "$layered" | grep 'ignored here' | paste -sd'|' -)"
done
printf 'labels: {a: b}\ntrusted_owners:\n  - stranger\n' >"$layered/docs/conventions/source-control.yaml"
assert_eq "a repository-layer trusted_owners below a line outside the YAML subset is still reported" "1" \
  "$(errs subscriptions --root "$layered" | grep -cxF "org-standards: $layered/docs/conventions/source-control.yaml:2: trusted_owners is read from the user-global index only; ignored here")"

user_index "trusted_owners:
  - acme
standards_repositories:
  - repo: stranger/guide
    ref: abc123
  - repo: acme/handbook
    refs: main
  - {repo: acme/handbook}
  - repo: stranger/guide
    ref: $GUIDE
"
assert_eq "malformed entries are skipped and the well-formed one is still read" "stranger/guide@$GUIDE" "$(run subscriptions --root "$t" | cut -f1)"
malformed=$(errs subscriptions --root "$t")
assert_eq "a short ref is reported as malformed with its file and line" "1" \
  "$(grep -c "^org-standards: $USER_INDEX:6: malformed subscription (ref is not a full commit SHA); entry skipped" <<<"$malformed")"
assert_eq "an unknown key is reported as malformed with its file and line" "1" \
  "$(grep -c "^org-standards: $USER_INDEX:8: malformed subscription (unknown key refs)" <<<"$malformed")"
assert_eq "a flow-style entry is reported as malformed with its file and line" "1" \
  "$(grep -c "^org-standards: $USER_INDEX:10: malformed subscription (flow mapping" <<<"$malformed")"

user_index $'standards_repositories: [acme/handbook]\n'
assert_eq "a flow-style list reads no subscription" "" "$(run subscriptions --root "$t")"
assert_eq "a flow-style list is reported" "1" "$(errs subscriptions --root "$t" | grep -c 'subscriptions not read: .*not a block list')"

user_index "trusted_owners:
  - acme
standards_repositories:
  - repo: acme/..
  - repo: stranger/guide
    ref: $GUIDE
"
assert_eq "a subscription whose repository name is only dots is skipped" "stranger/guide@$GUIDE" "$(run subscriptions --root "$t" | cut -f1)"
assert_eq "a subscription whose repository name is only dots is reported as malformed" "1" \
  "$(errs subscriptions --root "$t" | grep -c "^org-standards: $USER_INDEX:6: malformed subscription (repo acme/.. is not <owner>/<repo>)")"
assert_eq "no checkout lands outside a repository's own cache entry" "" "$(find "$ORG_STANDARDS_CACHE" -maxdepth 1 -name '*@*')"

printf -- '---\nstandards_repositories:\n  - repo: stranger/guide\n    ref: %s\n---\n' "$GUIDE" >"$USER_INDEX"
assert_eq "a user README without the standards-contract key is no index: nothing read" "" "$(run subscriptions --root "$t")"
printf -- '---\nstandards-contract: 1.2.0\nstandards_repositories:\n  - repo: stranger/guide\n    ref: %s\n---\n' "$GUIDE" >"$USER_INDEX"
assert_eq "an index below the subscriptions version is still read" "stranger/guide@$GUIDE" "$(run subscriptions --root "$t" | cut -f1)"
assert_eq "an index below the subscriptions version is told to declare it" "1" \
  "$(errs subscriptions --root "$t" | grep -c 'declares standards-contract 1.2.0; standards_repositories needs 1.3.0')"
printf -- '---\r\nstandards-contract: 1.3.0\r\nstandards_repositories:\r\n  - repo: stranger/guide\r\n    ref: %s\r\n---\r\n' "$GUIDE" >"$USER_INDEX"
assert_eq "a user index with CRLF line endings is read like one with LF endings" "stranger/guide@$GUIDE|" \
  "$(run subscriptions --root "$t" | cut -f1)|$(errs subscriptions --root "$t")"
user_index "x:
  standards_repositories:
    - repo: stranger/guide
      ref: $GUIDE
"
assert_eq "a standards_repositories nested under another key reads nothing and is reported with its file and line" "|1" \
  "$(run subscriptions --root "$t")|$(errs subscriptions --root "$t" | grep -cxF "org-standards: $USER_INDEX:4: x.standards_repositories is under another key, so it is not read; write standards_repositories at the top level of the frontmatter")"

rm -f "$USER_INDEX"
mkdir "$USER_INDEX"
assert_eq "an unreadable user index: no subscription, exit 0" "0|" "$(code subscriptions --root "$t")|$(run subscriptions --root "$t")"
assert_eq "an unreadable user index says so" "1" "$(errs subscriptions --root "$t" | grep -c '^org-standards: subscriptions not read: user index unreadable')"
rmdir "$USER_INDEX"

user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
run subscriptions --root "$t" >/dev/null
handbook_v2
HANDBOOK2=$(head_of acme/handbook)
assert_eq "within the refresh window a live subscription keeps its commit" "acme/handbook@$HANDBOOK" "$(run subscriptions --root "$t" | cut -f1)"
drift=$(ORG_STANDARDS_TTL=0 bash "$SCRIPT" subscriptions --root "$t" 2>&1)
assert_eq "past the refresh window a live subscription moves to the new main" "1" "$(grep -c "^acme/handbook@$HANDBOOK2	" <<<"$drift")"
assert_eq "drift: a Surface id that moved to another name over the same file is a rename" "1" \
  "$(grep -c "^org-standards: acme/handbook: index drift since ${HANDBOOK:0:12}: renamed naming -> names$" <<<"$drift")"
assert_eq "drift: a new Surface id is reported as added" "1" "$(grep -c 'index drift since .*: added security$' <<<"$drift")"
assert_eq "drift: a vanished Surface id is reported as removed" "1" "$(grep -c 'index drift since .*: removed testing$' <<<"$drift")"
assert_eq "drift: a second read at the same commit reports nothing" "0" "$(errs subscriptions --root "$t" | grep -c 'index drift')"

printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| testing | writing tests | testing.md |\n| auth | auth | auth.md |\n' \
  >"$TEST_TMPDIR/work/stranger/guide/docs/standards/README.md"
g -C "$TEST_TMPDIR/work/stranger/guide" commit -q -am v2
g -C "$TEST_TMPDIR/work/stranger/guide" push -q origin main
GUIDE2=$(head_of stranger/guide)
user_index "standards_repositories:
  - repo: stranger/guide
    ref: $GUIDE2
"
changed=$(bash "$SCRIPT" subscriptions --root "$t" 2>&1)
assert_eq "a ref change reads the new pin" "1" "$(grep -c "^stranger/guide@$GUIDE2	" <<<"$changed")"
assert_eq "a ref change says the pin moved" "1" "$(grep -c "ref of stranger/guide changed from ${GUIDE:0:12} to ${GUIDE2:0:12}" <<<"$changed")"
assert_eq "a ref change prints the index diff for review" "1" "$(grep -cxF '+| auth | auth | auth.md |' <<<"$changed")"

GUIDE_WORK="$TEST_TMPDIR/work/stranger/guide"
g -C "$GUIDE_WORK" checkout -q -b fork
printf '# Injected\n' >"$GUIDE_WORK/docs/standards/injected.md"
g -C "$GUIDE_WORK" add -A
g -C "$GUIDE_WORK" commit -q -m fork
FORK=$(head_of stranger/guide)
g -C "$GUIDE_WORK" push -q origin fork
g -C "$TEST_TMPDIR/git/stranger/guide.git" update-ref -d refs/heads/fork
g -C "$GUIDE_WORK" checkout -q main
g init -q "$TEST_TMPDIR/fork-probe"
assert_eq "the fixture remote still serves the fork-only commit by SHA" "0" \
  "$(g -C "$TEST_TMPDIR/fork-probe" fetch -q --depth=1 "file://$TEST_TMPDIR/git/stranger/guide.git" "$FORK" >/dev/null 2>&1; echo $?)"
user_index "standards_repositories:
  - repo: stranger/guide
    ref: $FORK
"
assert_eq "a commit on no branch or tag of the repository is refused" "" "$(run subscriptions --root "$t")"
assert_eq "the fork-only refusal says why" "1" "$(errs subscriptions --root "$t" | grep -c "$FORK is not reachable from a branch or tag of stranger/guide")"
g -C "$TEST_TMPDIR/git/stranger/guide.git" tag released "$FORK"
assert_eq "a commit a tag reaches is accepted" "stranger/guide@$FORK" "$(run subscriptions --root "$t" | cut -f1)"

g -C "$TEST_TMPDIR/git/stranger/guide.git" tag -a -m pinned pinned "$GUIDE"
TAG_OBJECT=$(g -C "$TEST_TMPDIR/git/stranger/guide.git" rev-parse pinned)
user_index "standards_repositories:
  - repo: stranger/guide
    ref: $TAG_OBJECT
"
assert_eq "a pin naming an annotated tag object reads, caches and names the commit it tags" \
  "$(expect_layer stranger/guide "$GUIDE")|" \
  "$(run subscriptions --root "$t" | shown)|$(find "$ORG_STANDARDS_CACHE" -name "*@$TAG_OBJECT")"

printf 'private\n' >"$TEST_TMPDIR/private.txt"
ln -s "$TEST_TMPDIR/private.txt" "$GUIDE_WORK/docs/standards/linked.md"
g -C "$GUIDE_WORK" add -A
g -C "$GUIDE_WORK" commit -q -m link
g -C "$GUIDE_WORK" push -q origin main
LINKED=$(head_of stranger/guide)
user_index "standards_repositories:
  - repo: stranger/guide
    ref: $LINKED
"
linked="$(run subscriptions --root "$t" | cut -f2)/docs/standards/linked.md"
assert_eq "a subscribed symlink is checked out as a plain file holding its target path" \
  "file|$TEST_TMPDIR/private.txt" "$([[ -L "$linked" ]] && echo link || echo file)|$(cat "$linked")"

publish stranger/escape "$HANDBOOK_INDEX"
ESCAPE_WORK="$TEST_TMPDIR/work/stranger/escape"
mkdir -p "$ESCAPE_WORK/.claude"
printf 'standards_dir: ../../../outside\n' >"$ESCAPE_WORK/.claude/standards.yaml"
g -C "$ESCAPE_WORK" add -A
g -C "$ESCAPE_WORK" commit -q -m escape
g -C "$ESCAPE_WORK" push -q origin main
ESCAPE=$(head_of stranger/escape)
user_index "standards_repositories:
  - repo: stranger/escape
    ref: $ESCAPE
  - repo: stranger/guide
    ref: $GUIDE
"
assert_eq "a subscribed standards_dir that leaves its checkout skips that layer only" "stranger/guide@$GUIDE" \
  "$(run subscriptions --root "$t" | cut -f1)"
assert_eq "a subscribed standards_dir that leaves its checkout is refused naming the file" "1" \
  "$(errs subscriptions --root "$t" | grep -c "^org-standards: $ORG_STANDARDS_CACHE/stranger/escape@$ESCAPE/.claude/standards.yaml: standards_dir ../../../outside has a '..' segment")"

publish stranger/rows "$(printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| testing | writing tests | testing.md |\n| up | x | ../../../secret.txt |\n| abs | x | /etc/hostname |\n| home | x | ~/.ssh/id_rsa |\n| naming | naming things | naming.md |')"
ROWS=$(head_of stranger/rows)
ROWS_INDEX="$ORG_STANDARDS_CACHE/stranger/rows@$ROWS/docs/standards/README.md"
user_index "standards_repositories:
  - repo: stranger/rows
    ref: $ROWS
"
confined=$(run subscriptions --root "$t" | cut -f3)
assert_eq "subscription: rows whose File is absolute, home-relative or climbs out are dropped" \
  "$(printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| testing | writing tests | %s/testing.md |\n| naming | naming things | %s/naming.md |' "$(dirname "$ROWS_INDEX")" "$(dirname "$ROWS_INDEX")")" \
  "$(cat "$confined")"
assert_eq "subscription: the confined index is the reader's copy under its state" "$ORG_STANDARDS_CACHE/.state/confined" "$(dirname "$confined")"
rows=$(errs subscriptions --root "$t")
assert_eq "subscription: each dropped row is reported with its file, line and value" \
  "org-standards: $ROWS_INDEX:8: File ../../../secret.txt has a '..' segment; row dropped|org-standards: $ROWS_INDEX:9: File /etc/hostname is absolute; row dropped|org-standards: $ROWS_INDEX:10: File ~/.ssh/id_rsa is not a relative forward-slash path; row dropped" \
  "$(paste -sd'|' - <<<"$rows")"
user_index "standards_repositories:
  - repo: stranger/rows
    ref: $ROWS
    topics:
      - up
      - naming
"
assert_eq "subscription: a topic filter keeps only confined rows" \
  "$(printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| naming | naming things | %s/naming.md |' "$(dirname "$ROWS_INDEX")")" \
  "$(cat "$(run subscriptions --root "$t" | cut -f3)")"

user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
printf '# Local\n' >"$t/REVIEW.md"
assert_eq "a subscribed REVIEW.md is not loaded into the review criteria" "# Local" "$(run review --root "$t")"
rm -f "$t/REVIEW.md"
assert_eq "a subscribed REVIEW.md does not stand in for missing criteria" "3" "$(code review --root "$t")"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/concurrent-cache"
for n in 1 2; do mkdir -p "$TEST_TMPDIR/home$n/.claude/standards"; done
printf -- '---\nstandards-contract: 1.3.0\nstandards_repositories:\n  - repo: stranger/guide\n    ref: %s\n---\n' "$GUIDE" >"$TEST_TMPDIR/home1/.claude/standards/README.md"
printf -- '---\nstandards-contract: 1.3.0\nstandards_repositories:\n  - repo: stranger/guide\n    ref: %s\n---\n' "$GUIDE2" >"$TEST_TMPDIR/home2/.claude/standards/README.md"
HOME="$TEST_TMPDIR/home1" bash "$SCRIPT" subscriptions --root "$t" >"$TEST_TMPDIR/c1.out" 2>"$TEST_TMPDIR/c1.err" &
HOME="$TEST_TMPDIR/home2" bash "$SCRIPT" subscriptions --root "$t" >"$TEST_TMPDIR/c2.out" 2>"$TEST_TMPDIR/c2.err" &
wait
assert_eq "two concurrent reads at two commits: each reads its own commit" \
  "stranger/guide@$GUIDE|stranger/guide@$GUIDE2" "$(cut -f1 "$TEST_TMPDIR/c1.out")|$(cut -f1 "$TEST_TMPDIR/c2.out")"
assert_eq "two concurrent reads at two commits: each printed index holds its own commit's rows" \
  "$(handbook_confined "$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE")|$(printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| testing | writing tests | %s/docs/standards/testing.md |\n| auth | auth | %s/docs/standards/auth.md |' "$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE2" "$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE2")" \
  "$(cat "$(cut -f3 "$TEST_TMPDIR/c1.out")")|$(cat "$(cut -f3 "$TEST_TMPDIR/c2.out")")"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/lost-race-cache"
mkdir -p "$TEST_TMPDIR/shim"
cat >"$TEST_TMPDIR/shim/git" <<EOF
#!/usr/bin/env bash
"$(command -v git)" "\$@"
rc=\$?
dir="" prev=""
for a in "\$@"; do [[ "\$prev" != -C ]] || dir=\$a; prev=\$a; done
if [[ \$rc -eq 0 && "\$dir" == */.build.* && " \$* " == *" checkout "* ]]; then
  name=\$(basename "\$("$(command -v git)" -C "\$dir" remote get-url origin)" .git)
  cp -R "\$dir" "\$(dirname "\$dir")/\$name@\${*: -1}"
  printf 'another reader won\n' >>"$TEST_TMPDIR/race.log"
fi
exit \$rc
EOF
cat >"$TEST_TMPDIR/shim/mv" <<EOF
#!/usr/bin/env bash
"$(command -v mv)" "\$@"
rc=\$?
find "$ORG_STANDARDS_CACHE" -mindepth 3 -maxdepth 3 -name '.build.*' >>"$TEST_TMPDIR/race.log"
exit \$rc
EOF
chmod +x "$TEST_TMPDIR/shim/git" "$TEST_TMPDIR/shim/mv"
printf -- '---\nstandards-contract: 1.3.0\nstandards_repositories:\n  - repo: stranger/guide\n    ref: %s\n---\n' "$GUIDE" \
  >"$TEST_TMPDIR/home1/.claude/standards/README.md"
lost=$(PATH="$TEST_TMPDIR/shim:$PATH" HOME="$TEST_TMPDIR/home1" bash "$SCRIPT" subscriptions --root "$t" 2>&1)
assert_eq "a build that loses the rename to another reader uses the winner's checkout" \
  "stranger/guide@$GUIDE	$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE|$ORG_STANDARDS_CACHE/.state/confined" "${lost%	*}|$(dirname "${lost##*	}")"
assert_eq "a build that loses the rename leaves no build directory behind" "" "$(find "$ORG_STANDARDS_CACHE" -name '.build.*')"
assert_eq "a build that loses the rename is never moved inside the winner's checkout" "another reader won" "$(cat "$TEST_TMPDIR/race.log")"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/live-cache"
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
ORG_STANDARDS_TTL=0 bash "$SCRIPT" subscriptions --root "$t" >"$TEST_TMPDIR/l1.out" 2>"$TEST_TMPDIR/l1.err" &
ORG_STANDARDS_TTL=0 bash "$SCRIPT" subscriptions --root "$t" >"$TEST_TMPDIR/l2.out" 2>"$TEST_TMPDIR/l2.err" &
wait
assert_eq "two concurrent refreshes of one live repository: both read main" \
  "acme/handbook@$HANDBOOK2|acme/handbook@$HANDBOOK2" "$(cut -f1 "$TEST_TMPDIR/l1.out")|$(cut -f1 "$TEST_TMPDIR/l2.out")"
assert_eq "two concurrent refreshes of one live repository: no error and no leftover build directory" "|||" \
  "$(cat "$TEST_TMPDIR/l1.err")|$(cat "$TEST_TMPDIR/l2.err")|$(find "$ORG_STANDARDS_CACHE" -name '.build.*')|$(find "$ORG_STANDARDS_CACHE/acme/handbook@$HANDBOOK2" -maxdepth 1 -name '.build.*')"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/collide-cache"
publish acme/handbook.last "$HANDBOOK_INDEX"
collide=$(target collide $'standards_repository: acme/handbook.last\n')
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
run subscriptions --root "$collide" >/dev/null
collided=$(run dir --root "$collide")
assert_eq "a subscription's read state never takes the cache path of a repository named <repo>.last" \
  "$ORG_STANDARDS_CACHE/acme/handbook.last|checkout" "$collided|$([[ -d "$collided/.git" ]] && echo checkout || echo 'not a checkout')"

inv=$(target inventory 'pr_open_state: ready\n')
g init -q "$inv"
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
assert_eq "rule inventory: a subscribed layer is named as present, not counted" "1|0" \
  "$(bash "$INVENTORY" --root "$inv" 2>/dev/null | grep -cxF -e "- review: the personal standards subscription acme/handbook@$HANDBOOK2 is present, not counted: it is the user's, not this repository's")|$(bash "$INVENTORY" --root "$inv" --rows 2>/dev/null | grep -c 'acme/handbook')"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/tab-cache"
user_index "standards_repositories:
  - repo: stranger/guide
	  ref: $GUIDE
  - repo: stranger/guide
    ref: $GUIDE
"
tabbed=$(bash "$SCRIPT" subscriptions --root "$tp" 2>&1)
assert_eq "a tab-indented line skips only its own entry, reported with its file and line" "1|1|0" \
  "$(grep -c "^stranger/guide@$GUIDE	" <<<"$tabbed")|$(grep -c "^org-standards: $USER_INDEX:4: malformed subscription (tab indentation at line 5); entry skipped$" <<<"$tabbed")|$(grep -c 'subscriptions not read' <<<"$tabbed")"

user_index $'trusted_owners: [acme]\nstandards_repositories:\n  - repo: acme/handbook\n'
assert_eq "a flow-style trusted_owners trusts no owner and is reported with its file and line" "|1" \
  "$(run subscriptions --root "$tp")|$(errs subscriptions --root "$tp" | grep -c "^org-standards: $USER_INDEX:3: trusted_owners is not a block list; no owner is trusted$")"

for spelling in '"trusted_owners": [acme]' "'trusted_owners': [acme]" 'trusted_owners : [acme]' 'trusted_owners: acme' '"trusted_owners": acme' 'trusted_owners: []'; do
  user_index "$spelling"$'\nstandards_repositories:\n  - repo: acme/handbook\n'
  assert_eq "trusted_owners written as $spelling trusts no owner and is reported with its file and line" "|1" \
    "$(run subscriptions --root "$tp")|$(errs subscriptions --root "$tp" | grep -c "^org-standards: $USER_INDEX:3: trusted_owners is not a block list; no owner is trusted$")"
done
user_index $'"trusted_owners":\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
assert_eq "a quoted trusted_owners key over a block list trusts its owners and reports nothing" "acme/handbook@$HANDBOOK2|0" \
  "$(run subscriptions --root "$tp" | cut -f1)|$(errs subscriptions --root "$tp" | grep -c 'trusted_owners')"
user_index $'trusted_owners:\n  - acme other\n  - stranger\nstandards_repositories:\n  - repo: acme/handbook\n  - repo: stranger/other\n'
assert_eq "a trusted_owners item holding a space trusts no owner; the other items still count, and the item is reported with its file and line" \
  "stranger/other@$(head_of stranger/other)|1|1" \
  "$(run subscriptions --root "$tp" | cut -f1)|$(errs subscriptions --root "$tp" | grep -c "^org-standards: $USER_INDEX:4: trusted_owners item \"acme other\" holds a space, and an owner name has none; it trusts no owner$")|$(errs subscriptions --root "$tp" | grep -c "^org-standards: $USER_INDEX:7: acme/handbook is not pinned")"
for spelling in '"standards_repositories":' "'standards_repositories':" 'standards_repositories :'; do
  user_index "$spelling
  - repo: stranger/guide
    ref: $GUIDE
"
  assert_eq "a block list under $spelling is read like the plain key" "stranger/guide@$GUIDE" "$(run subscriptions --root "$tp" | cut -f1)"
done
user_index $'"standards_repositories": [stranger/guide]\n'
assert_eq "a flow list under a quoted standards_repositories key reads nothing and is reported with its file and line" "|1" \
  "$(run subscriptions --root "$tp")|$(errs subscriptions --root "$tp" | grep -c "^org-standards: subscriptions not read: $USER_INDEX:3: standards_repositories is not a block list")"

finish
