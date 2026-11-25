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
errs() { { bash "$SCRIPT" "$@" >/dev/null; } 2>&1; }

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

for dots in acme/.. acme/. acme/...; do
  t=$(target "dots-${dots##*/}" "standards_repository: $dots"$'\n')
  assert_eq "a repository name of only dots ($dots) is no org layer" "3" "$(code dir --root "$t")"
done

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

OUTSIDE="$TEST_TMPDIR/outside"
mkdir -p "$OUTSIDE"
printf -- '---\nstandards-contract: 1.2.0\n---\n' >"$OUTSIDE/README.md"
SECRET="$TEST_TMPDIR/secret.txt"
printf 'secret\n' >"$SECRET"
org_checkout() {
  local dir="$TEST_TMPDIR/$1"
  mkdir -p "$dir/.claude"
  [[ -z "$2" ]] || printf 'standards_dir: %s\n' "$2" >"$dir/.claude/standards.yaml"
  printf '%s\n' "$dir"
}
o=$(org_checkout escape-dots ../outside)
assert_eq "a standards_dir with a '..' segment is no usable index: exit 5" "5" "$(STANDARDS_DIR="$o" code index --root "$t")"
assert_eq "a standards_dir with a '..' segment is refused naming the file" "1" \
  "$(STANDARDS_DIR="$o" errs index --root "$t" | grep -c "^org-standards: $o/.claude/standards.yaml: standards_dir ../outside has a '..' segment; no usable index")"
o=$(org_checkout escape-abs "$OUTSIDE")
assert_eq "an absolute standards_dir is no usable index: exit 5" "5" "$(STANDARDS_DIR="$o" code index --root "$t")"
assert_eq "an absolute standards_dir is refused naming the file" "1" \
  "$(STANDARDS_DIR="$o" errs index --root "$t" | grep -c "^org-standards: $o/.claude/standards.yaml: standards_dir $OUTSIDE is absolute; no usable index")"
o=$(org_checkout escape-link '')
mkdir -p "$o/docs"
ln -s "$OUTSIDE" "$o/docs/standards"
assert_eq "a standards directory symlinked out of the checkout is no usable index: exit 5" "5" "$(STANDARDS_DIR="$o" code index --root "$t")"
assert_eq "a standards directory symlinked out of the checkout is refused naming the index" "1" \
  "$(STANDARDS_DIR="$o" errs index --root "$t" | grep -c "^org-standards: $o/docs/standards/README.md: the index resolves outside its checkout; no usable index")"

o=$(org_checkout escape-rows '')
mkdir -p "$o/docs/standards"
printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| testing | writing tests | testing.md |\n| linked | x | linked.md |\n| nested | x | sub/README.md |\n| external | x | ext.md |\n' \
  >"$o/docs/standards/README.md"
printf '# Testing\n' >"$o/docs/standards/testing.md"
ln -s "$SECRET" "$o/docs/standards/linked.md"
ln -s "$OUTSIDE" "$o/docs/standards/sub"
ln -s "$SECRET" "$o/ext.md"
confined=$(STANDARDS_DIR="$o" run index --root "$t")
assert_eq "org index: rows whose File resolves outside the checkout are dropped" \
  "$(printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| testing | writing tests | testing.md |')" \
  "$(cat "$confined")"
assert_eq "org index: the confined index sits beside the original, so its rows resolve there" "$o/docs/standards" "$(dirname "$confined")"
rows=$(STANDARDS_DIR="$o" errs index --root "$t")
assert_eq "org index: each dropped row is reported with its file, line and value" \
  "org-standards: $o/docs/standards/README.md:8: File linked.md resolves outside its checkout; row dropped|org-standards: $o/docs/standards/README.md:9: File sub/README.md resolves outside its checkout; row dropped|org-standards: $o/docs/standards/README.md:10: File ext.md resolves outside its checkout; row dropped" \
  "$(paste -sd'|' - <<<"$rows")"
ln -s "$SECRET" "$o/REVIEW.md"
assert_eq "an org REVIEW.md that resolves outside the checkout is not read" "3|" \
  "$(STANDARDS_DIR="$o" code review --root "$t")|$(STANDARDS_DIR="$o" run review --root "$t")"

assert_eq "an unknown command is a usage error" "2" "$(code bogus)"

export HOME="$TEST_TMPDIR/home"
export ORG_STANDARDS_CACHE="$TEST_TMPDIR/sub-cache"
unset STANDARDS_SUBSCRIPTIONS_DISABLED
USER_INDEX="$HOME/.claude/standards/README.md"
mkdir -p "$HOME/.claude/standards"

HANDBOOK_INDEX='---
standards-contract: 1.2.0
---

# Handbook

| Surface | Applies when | File |
|---|---|---|
| testing | writing tests | testing.md |
| naming | naming things | naming.md |'

publish() {
  local work="$TEST_TMPDIR/work/$1" bare="$TEST_TMPDIR/git/$1.git"
  mkdir -p "$work/docs/standards" "$(dirname "$bare")"
  printf '%s\n' "$2" >"$work/docs/standards/README.md"
  printf '# %s review\n' "$1" >"$work/REVIEW.md"
  g init -q -b main "$work"
  g -C "$work" add -A
  g -C "$work" commit -q -m init
  g clone -q --bare "$work" "$bare"
  g -C "$bare" config uploadpack.allowAnySHA1InWant true
  g -C "$work" remote add origin "$bare"
}
head_of() { g -C "$TEST_TMPDIR/work/$1" rev-parse HEAD; }
user_index() { printf -- '---\nstandards-contract: 1.3.0\n%s---\n\n# My standards\n' "$1" >"$USER_INDEX"; }

publish acme/handbook "$HANDBOOK_INDEX"
publish stranger/guide "$HANDBOOK_INDEX"
publish stranger/other "$HANDBOOK_INDEX"
HANDBOOK=$(head_of acme/handbook)
GUIDE=$(head_of stranger/guide)
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
  "acme/handbook@$HANDBOOK	$ORG_STANDARDS_CACHE/acme/handbook@$HANDBOOK	$ORG_STANDARDS_CACHE/acme/handbook@$HANDBOOK/docs/standards/README.md" \
  "$(run subscriptions --root "$t")"

user_index "standards_repositories:
  - repo: stranger/guide
    ref: $GUIDE
"
assert_eq "pinned untrusted: the pinned commit is read" \
  "stranger/guide@$GUIDE	$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE	$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE/docs/standards/README.md" \
  "$(run subscriptions --root "$t")"

user_index $'standards_repositories:\n  - repo: stranger/other\n'
assert_eq "unpinned untrusted: refused, nothing read" "" "$(run subscriptions --root "$t")"
assert_eq "unpinned untrusted: the refusal names the file and line" "1" \
  "$(errs subscriptions --root "$t" | grep -c "^org-standards: $USER_INDEX:4: stranger/other is not pinned")"

user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n    topics:\n      - naming\n'
filtered=$(run subscriptions --root "$t" | cut -f3)
assert_eq "topic filter: the index keeps only the rows of the named Surface ids" \
  "$(printf -- '---\nstandards-contract: 1.2.0\n---\n\n# Handbook\n\n| Surface | Applies when | File |\n|---|---|---|\n| naming | naming things | naming.md |')" \
  "$(cat "$filtered")"
assert_eq "topic filter: the filtered index sits beside the original, so its rows resolve there" \
  "$ORG_STANDARDS_CACHE/acme/handbook@$HANDBOOK/docs/standards" "$(dirname "$filtered")"
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

rm -f "$USER_INDEX"
mkdir "$USER_INDEX"
assert_eq "an unreadable user index: no subscription, exit 0" "0|" "$(code subscriptions --root "$t")|$(run subscriptions --root "$t")"
assert_eq "an unreadable user index says so" "1" "$(errs subscriptions --root "$t" | grep -c '^org-standards: subscriptions not read: user index unreadable')"
rmdir "$USER_INDEX"

user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
run subscriptions --root "$t" >/dev/null
printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| names | naming things | naming.md |\n| security | auth | security.md |\n' \
  >"$TEST_TMPDIR/work/acme/handbook/docs/standards/README.md"
g -C "$TEST_TMPDIR/work/acme/handbook" commit -q -am v2
g -C "$TEST_TMPDIR/work/acme/handbook" push -q origin main
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
  "stranger/guide@$GUIDE	$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE	$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE/docs/standards/README.md|" \
  "$(run subscriptions --root "$t")|$(find "$ORG_STANDARDS_CACHE" -name "*@$TAG_OBJECT")"

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
linked="$(dirname "$(run subscriptions --root "$t" | cut -f3)")/linked.md"
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
  "$(printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| testing | writing tests | testing.md |\n| naming | naming things | naming.md |')" \
  "$(cat "$confined")"
assert_eq "subscription: the confined index sits beside the original" "$(dirname "$ROWS_INDEX")" "$(dirname "$confined")"
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
  "$(printf -- '---\nstandards-contract: 1.2.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| naming | naming things | naming.md |')" \
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
assert_eq "two concurrent reads at two commits: each checkout holds its commit's index" \
  "$(g -C "$GUIDE_WORK" show "$GUIDE:docs/standards/README.md")|$(g -C "$GUIDE_WORK" show "$GUIDE2:docs/standards/README.md")" \
  "$(cat "$(cut -f3 "$TEST_TMPDIR/c1.out")")|$(cat "$(cut -f3 "$TEST_TMPDIR/c2.out")")"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/lost-race-cache"
mkdir -p "$TEST_TMPDIR/shim"
cat >"$TEST_TMPDIR/shim/git" <<EOF
#!/usr/bin/env bash
"$(command -v git)" "\$@"
rc=\$?
if [[ \$rc -eq 0 && "\$1" == -C && "\$2" == */.build.* && " \$* " == *" checkout "* ]]; then
  name=\$(basename "\$("$(command -v git)" -C "\$2" remote get-url origin)" .git)
  cp -R "\$2" "\$(dirname "\$2")/\$name@\${*: -1}"
fi
exit \$rc
EOF
chmod +x "$TEST_TMPDIR/shim/git"
printf -- '---\nstandards-contract: 1.3.0\nstandards_repositories:\n  - repo: stranger/guide\n    ref: %s\n---\n' "$GUIDE" \
  >"$TEST_TMPDIR/home1/.claude/standards/README.md"
lost=$(PATH="$TEST_TMPDIR/shim:$PATH" HOME="$TEST_TMPDIR/home1" bash "$SCRIPT" subscriptions --root "$t" 2>&1)
assert_eq "a build that loses the rename to another reader uses the winner's checkout" \
  "stranger/guide@$GUIDE	$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE	$ORG_STANDARDS_CACHE/stranger/guide@$GUIDE/docs/standards/README.md" "$lost"
assert_eq "a build that loses the rename leaves no build directory behind" "" "$(find "$ORG_STANDARDS_CACHE" -name '.build.*')"

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

INVENTORY="$SCRIPT_DIR/../plugins/harness-config/skills/audit-automation-gaps/scripts/rule-inventory.sh"
inv=$(target inventory 'pr_open_state: ready\n')
g init -q "$inv"
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
assert_eq "rule inventory: a subscribed layer is named as present, not counted" "1|0" \
  "$(bash "$INVENTORY" --root "$inv" 2>/dev/null | grep -cxF -e "- review: the personal standards subscription acme/handbook@$HANDBOOK2 is present, not counted: it is the user's, not this repository's")|$(bash "$INVENTORY" --root "$inv" --rows 2>/dev/null | grep -c 'acme/handbook')"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/net-cache"
unset GIT_SSH_COMMAND GIT_ASKPASS
mkdir -p "$TEST_TMPDIR/netshim"
cat >"$TEST_TMPDIR/netshim/git" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *" ls-remote "*|*" fetch "*|*" clone "*)
    printf '%s|%s|%s|%s\n' "\${GIT_TERMINAL_PROMPT-}" "\${GIT_SSH_COMMAND-}" "\${GIT_ASKPASS-unset}" "\$*" >>"$TEST_TMPDIR/net.log"
    [[ -z "\${SLOW_NET:-}" ]] || exec sleep 20
    [[ -z "\${BAD_LS:-}" || " \$* " != *" ls-remote "* ]] || { printf '../../escape\trefs/heads/main\n'; exit 0; } ;;
esac
exec "$(command -v git)" "\$@"
EOF
chmod +x "$TEST_TMPDIR/netshim/git"
net=$(target net "$OPTED")
user_index "trusted_owners:
  - acme
standards_repositories:
  - repo: acme/handbook
  - repo: stranger/guide
    ref: $GUIDE
"
PATH="$TEST_TMPDIR/netshim:$PATH" run dir --root "$net" >/dev/null
PATH="$TEST_TMPDIR/netshim:$PATH" ORG_STANDARDS_TTL=0 run dir --root "$net" >/dev/null
PATH="$TEST_TMPDIR/netshim:$PATH" run subscriptions --root "$net" >/dev/null
assert_eq "every clone, fetch and ls-remote runs with prompts off, ssh in batch mode, no askpass and no credential helper" "1|1|1|0" \
  "$(grep -cE '[| ]clone ' "$TEST_TMPDIR/net.log")|$(grep -cE -m1 '[| ]fetch ' "$TEST_TMPDIR/net.log")|$(grep -cE '[| ]ls-remote ' "$TEST_TMPDIR/net.log")|$(grep -vc '^0|ssh -o BatchMode=yes||-c credential.helper= ' "$TEST_TMPDIR/net.log")"

export ORG_STANDARDS_CACHE="$TEST_TMPDIR/bad-ls-cache"
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
assert_eq "a remote that answers main with something other than a commit SHA is not used as a cache key" "1|" \
  "$(PATH="$TEST_TMPDIR/netshim:$PATH" BAD_LS=1 errs subscriptions --root "$net" | grep -c 'cannot read acme/handbook; layer skipped')|$(find "$ORG_STANDARDS_CACHE" -name 'handbook@*')"

if command -v timeout >/dev/null 2>&1; then
  export ORG_STANDARDS_CACHE="$TEST_TMPDIR/slow-cache"
  user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/handbook\n'
  start=$SECONDS
  slow=$(PATH="$TEST_TMPDIR/netshim:$PATH" SLOW_NET=1 ORG_STANDARDS_GIT_TIMEOUT=1 bash "$SCRIPT" subscriptions --root "$net" 2>&1)
  assert_eq "a stalled remote is given up after ORG_STANDARDS_GIT_TIMEOUT and the layer skipped" "1|yes" \
    "$(grep -c 'cannot read acme/handbook; layer skipped' <<<"$slow")|$([[ $((SECONDS - start)) -lt 10 ]] && echo yes || echo "no, $((SECONDS - start))s")"
  start=$SECONDS
  assert_eq "a stalled org clone is given up after ORG_STANDARDS_GIT_TIMEOUT: exit 4" "4|yes" \
    "$(PATH="$TEST_TMPDIR/netshim:$PATH" SLOW_NET=1 ORG_STANDARDS_GIT_TIMEOUT=1 code dir --root "$net")|$([[ $((SECONDS - start)) -lt 10 ]] && echo yes || echo "no, $((SECONDS - start))s")"
fi

if [[ "$FAILED" -gt 0 ]]; then
  printf '%d test(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'All tests passed\n'
