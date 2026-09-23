#!/usr/bin/env bash
# Regression tests for skill-evidence.sh.
#
# Black-box through the CLI against throwaway git fixtures under a mktemp dir,
# a JSONL ledger, a PR body, a saved REST compare payload, and a stubbed `gh`.
# Nothing here sources the engine or reaches into its internals, so a rewrite
# that keeps the four subcommands' contract keeps this suite green. No network.
#
# The discriminating cases: the two freshness tiers (terminal at the head
# exactly, others on the head's history), a tracked path the repository's OWN
# .gitignore matches (which must not count as a class match, because
# `check-ignore --no-index` still consults those rules), the round trip from
# ledger rows through `render` to a body `check` accepts, and the base-merge
# case that keeps non-terminal rows fresh while the terminal row goes stale.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/skill-evidence.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"
command -v jq >/dev/null 2>&1 || skip_suite "jq not available"

# The engine resolves the repository root from CLAUDE_PROJECT_DIR first; an
# inherited value would point every fixture run at the real checkout.
unset CLAUDE_PROJECT_DIR

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

MAP='- code | **/*.sh **/*.py | verification:confirm! review:quality-gate,review:fanout simplify
- markdown | **/*.md | ai-slop:audit
- renames | @renamed | docs-hygiene:rename-references
- security | @file:.github/security-paths | review:security-review'

# mkfixture — a git repository carrying the mandatory map, one commit on main,
# and a `work` branch with one shell file and one markdown file. Echoes the
# repository path. `node_modules/` is gitignored by the fixture itself and a
# tracked .sh lives under it, which is the negative control for the
# check-ignore source filter.
mkfixture() {
  local repo
  repo="$(mktemp -d "$TEST_TMPDIR/repoXXXXXX")"
  {
    git init -q -b main "$repo"
    git -C "$repo" config user.email t@t.t
    git -C "$repo" config user.name t
    git -C "$repo" config commit.gpgsign false
    git -C "$repo" config core.autocrlf false
    mkdir -p "$repo/.claude" "$repo/.github" "$repo/scripts" "$repo/docs" "$repo/node_modules"
    printf 'node_modules/\n' >"$repo/.gitignore"
    printf '# repo config\n\n## pr_skill_evidence\n\n%s\n\n## other_key\n\nvalue\n' "$MAP" \
      >"$repo/.claude/source-control.md"
    printf '# comment\n\nscripts/**\n' >"$repo/.github/security-paths"
    printf 'seed\n' >"$repo/README.md"
    printf 'vendored\n' >"$repo/node_modules/vendor.sh"
    git -C "$repo" add -A
    git -C "$repo" add -f node_modules/vendor.sh
    git -C "$repo" commit -qm init
    git -C "$repo" branch work
    git -C "$repo" checkout -q work
    printf 'echo hi\n' >"$repo/scripts/a.sh"
    printf 'note\n' >"$repo/docs/n.md"
    git -C "$repo" add -A
    git -C "$repo" commit -qm work
  } >/dev/null 2>&1
  printf '%s' "$repo"
}

# run_in <dir> <args...> — engine run with the fixture as the working
# directory, stdout and stderr captured separately.
RUN_OUT=""
RUN_ERR=""
RUN_CODE=0
run_in() {
  local dir="$1"
  shift
  RUN_ERR="$TEST_TMPDIR/stderr.txt"
  RUN_OUT="$(cd "$dir" && "$ENGINE" "$@" 2>"$RUN_ERR")"
  RUN_CODE=$?
  return 0
}

# row <ledger> <skill> <sha> <ts> [event]
row() {
  local ledger="$1" skill="$2" sha="$3" ts="$4" event="${5:-SkillUse}"
  printf '{"event":"%s","skill":"%s","sha":"%s","ts":"%s"}\n' \
    "$event" "$skill" "$sha" "$ts" >>"$ledger"
}

sha_of() { git -C "$1" rev-parse "$2"; }

# --- classes -----------------------------------------------------------------

REPO="$(mkfixture)"
HEAD_SHA="$(sha_of "$REPO" HEAD)"
BASE_SHA="$(sha_of "$REPO" main)"

run_in "$REPO" classes --base main
assert_exit "classes exits 0" 0 "$RUN_CODE"
assert_contains "glob pattern detects the code class" "$RUN_OUT" "class=code"
assert_contains "glob pattern detects the markdown class" "$RUN_OUT" "class=markdown"
assert_contains "@file: pattern detects the security class" "$RUN_OUT" "class=security"
assert_not_contains "no rename in the diff, no renames class" "$RUN_OUT" "class=renames"

# A tracked path the repository's own .gitignore matches must not count: it is
# the map's patterns that decide a class, never .gitignore's.
printf 'changed\n' >>"$REPO/node_modules/vendor.sh"
git -C "$REPO" add -f node_modules/vendor.sh >/dev/null 2>&1
git -C "$REPO" commit -qm vendored >/dev/null 2>&1
IGNORED_ONLY="$TEST_TMPDIR/ignored-only.txt"
printf 'node_modules/vendor.sh\n' >"$IGNORED_ONLY"
run_in "$REPO" classes --files "$IGNORED_ONLY"
assert_exit "classes --files exits 0" 0 "$RUN_CODE"
assert_silent "a gitignored tracked path matches no class" "$RUN_OUT"
git -C "$REPO" reset -q --hard "$HEAD_SHA"

# @renamed
# A `**/` pattern must be handed to git, not to the shell. Left unquoted in a
# word split, `**/*.sh` expands against the working directory and the map
# quietly matches whatever files sit two levels down in this checkout instead.
# The only changed code file here is deeper than any such expansion reaches.
DEEP_REPO="$(mkfixture)"
{
  git -C "$DEEP_REPO" checkout -q main
  printf 'echo decoy\n' >"$DEEP_REPO/scripts/decoy.sh"
  git -C "$DEEP_REPO" add -A
  git -C "$DEEP_REPO" commit -qm decoy
  git -C "$DEEP_REPO" checkout -q work
  git -C "$DEEP_REPO" reset -q --hard main
  mkdir -p "$DEEP_REPO/one/two/three"
  printf 'echo deep\n' >"$DEEP_REPO/one/two/three/deep.sh"
  git -C "$DEEP_REPO" add -A
  git -C "$DEEP_REPO" commit -qm deep
} >/dev/null 2>&1
run_in "$DEEP_REPO" classes --base main
assert_contains "a pattern matches at any depth, never the shell's expansion" "$RUN_OUT" "class=code"
assert_not_contains "an unchanged decoy does not become a pattern" "$RUN_OUT" "class=markdown"

# The rename has to be of a file the BASE carries: a file the branch both adds
# and moves is a plain addition from the base's point of view.
RENAME_REPO="$(mkfixture)"
git -C "$RENAME_REPO" mv README.md READYOU.md >/dev/null 2>&1
git -C "$RENAME_REPO" commit -qm rename >/dev/null 2>&1
run_in "$RENAME_REPO" classes --base main
assert_contains "@renamed detects a rename" "$RUN_OUT" "class=renames"

# A `@file:` ref reads a file inside the checkout or nothing at all. An
# absolute ref and a `..` segment are both refused, and the run keeps going.
for BAD_REF in "/etc/passwd" "../../etc/passwd"; do
  ESCAPE_REPO="$(mkfixture)"
  printf '# repo config\n\n## pr_skill_evidence\n\n- escape | @file:%s | review:security-review\n' \
    "$BAD_REF" >"$ESCAPE_REPO/.claude/source-control.md"
  run_in "$ESCAPE_REPO" classes --base main
  assert_exit "an escaping @file: ref still exits 0 ($BAD_REF)" 0 "$RUN_CODE"
  assert_contains "an escaping @file: ref is warned about ($BAD_REF)" "$RUN_OUT" \
    "warning=unsafe-pattern-file"
  assert_not_contains "an escaping @file: ref matches no class ($BAD_REF)" "$RUN_OUT" \
    "class=escape"
done

# A gitignore negation re-includes a path, and `check-ignore -v` reports the
# negated line as the source of the match exactly as it reports a positive one.
# Left in the patterns file, `!scripts/keep.sh` therefore MATCHES scripts/keep.sh
# and nothing else: the one path the author wrote the line to exclude becomes
# the only path that selects the class. Dropping the line is what stops a
# negation from registering a match of its own. A positive pattern written
# beside it still matches on its own terms, since the negation is dropped and
# not honored.
NEGATION_REPO="$(mkfixture)"
{
  printf '# repo config\n\n## pr_skill_evidence\n\n'
  # shellcheck disable=SC2016  # the pattern field is a literal markdown code span
  printf -- '- code | `scripts/** !scripts/keep.sh` | review:security-review\n'
  # shellcheck disable=SC2016  # the pattern field is a literal markdown code span
  printf -- '- negated | `!scripts/keep.sh` | review:security-review\n'
} >"$NEGATION_REPO/.claude/source-control.md"
KEEP_ONLY="$TEST_TMPDIR/keep-only.txt"
printf 'scripts/keep.sh\n' >"$KEEP_ONLY"
run_in "$NEGATION_REPO" classes --files "$KEEP_ONLY"
assert_exit "a negation pattern still exits 0" 0 "$RUN_CODE"
assert_contains "a negation pattern is warned about" "$RUN_OUT" \
  "warning=negation-pattern-ignored pattern=!scripts/keep.sh"
assert_not_contains "a negation registers no class match of its own" "$RUN_OUT" "class=negated"
assert_contains "a positive pattern beside a negation still matches" "$RUN_OUT" "class=code"
OTHER_ONLY="$TEST_TMPDIR/other-only.txt"
printf 'scripts/other.sh\n' >"$OTHER_ONLY"
run_in "$NEGATION_REPO" classes --files "$OTHER_ONLY"
assert_contains "the positive pattern matches the path it names" "$RUN_OUT" "class=code"
assert_not_contains "a dropped negation leaves its class with no patterns" "$RUN_OUT" "class=negated"

# --- inert config ------------------------------------------------------------

INERT="$(mkfixture)"
printf '# repo config\n\n## pr_skill_evidence\n\nnone\n' >"$INERT/.claude/source-control.md"
run_in "$INERT" classes --base main
assert_exit "inert classes exits 0" 0 "$RUN_CODE"
assert_silent "a none map detects no class" "$RUN_OUT"

INERT_LEDGER="$TEST_TMPDIR/inert.jsonl"
: >"$INERT_LEDGER"
run_in "$INERT" check --head "$(sha_of "$INERT" HEAD)" --ledger "$INERT_LEDGER" --base main
assert_exit "inert check exits 0" 0 "$RUN_CODE"
assert_contains "inert check reports the inert verdict" "$RUN_OUT" "verdict=inert"

run_in "$INERT" render --ledger "$INERT_LEDGER" --head "$(sha_of "$INERT" HEAD)"
assert_exit "inert render exits 0" 0 "$RUN_CODE"
assert_silent "inert render prints nothing" "$RUN_OUT"

NOSECTION="$(mkfixture)"
printf '# repo config\n\n## pr_body_required_sections\n\n- Summary\n' \
  >"$NOSECTION/.claude/source-control.md"
run_in "$NOSECTION" check --head "$(sha_of "$NOSECTION" HEAD)" --ledger "$INERT_LEDGER" --base main
assert_contains "an absent section is inert too" "$RUN_OUT" "verdict=inert"

# --- check --ledger ----------------------------------------------------------

EMPTY_LEDGER="$TEST_TMPDIR/empty.jsonl"
: >"$EMPTY_LEDGER"
run_in "$REPO" check --head "$HEAD_SHA" --ledger "$EMPTY_LEDGER" --base main
assert_exit "check with no rows exits 0" 0 "$RUN_CODE"
assert_contains "no rows: the terminal skill is missing" "$RUN_OUT" "missing=verification:confirm"
assert_contains "no rows: the any-of group prints as the group" "$RUN_OUT" "missing=review:quality-gate,review:fanout"
assert_contains "no rows: simplify is missing" "$RUN_OUT" "missing=simplify"
assert_contains "no rows: the markdown class skill is missing" "$RUN_OUT" "missing=ai-slop:audit"
assert_contains "no rows: the security class skill is missing" "$RUN_OUT" "missing=review:security-review"
assert_not_contains "an undetected class owes nothing" "$RUN_OUT" "missing=docs-hygiene:rename-references"
assert_contains "no rows: the verdict is a gap" "$RUN_OUT" "verdict=gap"

FULL_LEDGER="$TEST_TMPDIR/full.jsonl"
: >"$FULL_LEDGER"
row "$FULL_LEDGER" review:fanout "$BASE_SHA" "2026-09-13T10:00:00Z"
row "$FULL_LEDGER" simplify "$BASE_SHA" "2026-09-13T10:01:00Z"
row "$FULL_LEDGER" ai-slop:audit "$HEAD_SHA" "2026-09-13T10:02:00Z"
row "$FULL_LEDGER" review:security-review "$HEAD_SHA" "2026-09-13T10:03:00Z"
row "$FULL_LEDGER" verification:confirm "$HEAD_SHA" "2026-09-13T10:04:00Z"
run_in "$REPO" check --head "$HEAD_SHA" --ledger "$FULL_LEDGER" --base main
assert_exit "a complete ledger exits 0" 0 "$RUN_CODE"
assert_contains "the terminal row at the head is fresh" "$RUN_OUT" "fresh=verification:confirm sha=$HEAD_SHA commits-since=0"
assert_contains "an any-of member satisfies the group" "$RUN_OUT" "fresh=review:fanout sha=$BASE_SHA commits-since=1"
assert_contains "an ancestor row is fresh and reports its distance" "$RUN_OUT" "fresh=simplify sha=$BASE_SHA commits-since=1"
assert_not_contains "a complete ledger names nothing missing" "$RUN_OUT" "missing="
assert_not_contains "a complete ledger names nothing stale" "$RUN_OUT" "stale="
assert_contains "a complete ledger is clean" "$RUN_OUT" "verdict=clean"

# The terminal skill passes at the head EXACTLY, never at an ancestor.
TERMINAL_BEHIND="$TEST_TMPDIR/terminal-behind.jsonl"
: >"$TERMINAL_BEHIND"
row "$TERMINAL_BEHIND" verification:confirm "$BASE_SHA" "2026-09-13T10:04:00Z"
run_in "$REPO" check --head "$HEAD_SHA" --ledger "$TERMINAL_BEHIND" --base main
assert_contains "a terminal row one commit behind is stale" "$RUN_OUT" "stale=verification:confirm sha=$BASE_SHA"
assert_contains "a stale terminal row is a gap" "$RUN_OUT" "verdict=gap"

# A row on a commit that is no longer on the head's history is stale.
REBASED_AWAY="$(git -C "$REPO" rev-parse "HEAD@{0}")"
git -C "$REPO" checkout -q -b throwaway
printf 'orphan\n' >>"$REPO/scripts/a.sh"
git -C "$REPO" commit -qam orphan >/dev/null 2>&1
ORPHAN_SHA="$(sha_of "$REPO" HEAD)"
git -C "$REPO" checkout -q work
git -C "$REPO" branch -qD throwaway
ORPHAN_LEDGER="$TEST_TMPDIR/orphan.jsonl"
: >"$ORPHAN_LEDGER"
row "$ORPHAN_LEDGER" simplify "$ORPHAN_SHA" "2026-09-13T11:00:00Z"
run_in "$REPO" check --head "$REBASED_AWAY" --ledger "$ORPHAN_LEDGER" --base main
assert_contains "a row on a commit off the head's history is stale" "$RUN_OUT" "stale=simplify sha=$ORPHAN_SHA"

# Latest row per skill wins, and a non-SkillUse row is not evidence.
LATEST_LEDGER="$TEST_TMPDIR/latest.jsonl"
: >"$LATEST_LEDGER"
row "$LATEST_LEDGER" simplify "$ORPHAN_SHA" "2026-09-13T09:00:00Z"
row "$LATEST_LEDGER" simplify "$BASE_SHA" "2026-09-13T12:00:00Z"
row "$LATEST_LEDGER" ai-slop:audit "$HEAD_SHA" "2026-09-13T12:00:00Z" SkillEnd
run_in "$REPO" check --head "$HEAD_SHA" --ledger "$LATEST_LEDGER" --base main
assert_contains "the qualifying row wins over an orphan one" "$RUN_OUT" "fresh=simplify sha=$BASE_SHA"
assert_contains "a row whose event is not SkillUse is not evidence" "$RUN_OUT" "missing=ai-slop:audit"

# CRLF ledger lines read the same as LF ones.
CRLF_LEDGER="$TEST_TMPDIR/crlf.jsonl"
printf '{"event":"SkillUse","skill":"simplify","sha":"%s","ts":"2026-09-13T10:00:00Z"}\r\n' \
  "$BASE_SHA" >"$CRLF_LEDGER"
run_in "$REPO" check --head "$HEAD_SHA" --ledger "$CRLF_LEDGER" --base main
assert_contains "a CRLF ledger row is read" "$RUN_OUT" "fresh=simplify sha=$BASE_SHA"

# A ledger that is not there is "no rows", never a crash.
run_in "$REPO" check --head "$HEAD_SHA" --ledger "$TEST_TMPDIR/absent.jsonl" --base main
assert_exit "an absent ledger still exits 0" 0 "$RUN_CODE"
assert_contains "an absent ledger reads as no rows" "$RUN_OUT" "missing=verification:confirm"

# --- render ------------------------------------------------------------------

run_in "$REPO" render --ledger "$FULL_LEDGER" --head "$HEAD_SHA"
assert_exit "render exits 0" 0 "$RUN_CODE"
BLOCK="$RUN_OUT"
assert_contains "render opens the fenced block" "$BLOCK" '```skill-evidence'
assert_contains "render carries the terminal row" "$BLOCK" "verification:confirm $HEAD_SHA 2026-09-13T10:04:00Z"
assert_contains "render carries an ancestor row" "$BLOCK" "simplify $BASE_SHA 2026-09-13T10:01:00Z"
FIRST_ROW="$(printf '%s\n' "$BLOCK" | awk 'NR == 2 { print $1 }')"
assert_eq "render sorts rows by skill name" "ai-slop:audit" "$FIRST_ROW"

DUP_LEDGER="$TEST_TMPDIR/dup.jsonl"
: >"$DUP_LEDGER"
row "$DUP_LEDGER" simplify "$BASE_SHA" "2026-09-13T10:00:00Z"
row "$DUP_LEDGER" simplify "$HEAD_SHA" "2026-09-13T13:00:00Z"
run_in "$REPO" render --ledger "$DUP_LEDGER" --head "$HEAD_SHA"
assert_eq "render emits one row per skill" "1" "$(printf '%s\n' "$RUN_OUT" | grep -c '^simplify ')"
assert_contains "render keeps the latest row" "$RUN_OUT" "simplify $HEAD_SHA 2026-09-13T13:00:00Z"

OFF_HISTORY="$TEST_TMPDIR/off-history.jsonl"
: >"$OFF_HISTORY"
row "$OFF_HISTORY" simplify "$ORPHAN_SHA" "2026-09-13T10:00:00Z"
run_in "$REPO" render --ledger "$OFF_HISTORY" --head "$REBASED_AWAY"
assert_exit "render with no qualifying row exits 0" 0 "$RUN_CODE"
assert_silent "render emits nothing when no row is on the head's history" "$RUN_OUT"

# --- check --body ------------------------------------------------------------

BODY="$TEST_TMPDIR/body.md"
{
  printf '## Summary\n\nProse that mentions verification:confirm without evidence.\n\n'
  printf '## Verification\n\n'
  printf '%s\n' "$BLOCK"
  # shellcheck disable=SC2016 # the fence backticks are literal block syntax, not a substitution
  printf '\n<!--\n```skill-evidence\nsimplify %s 2026-09-13T10:01:00Z\n```\n-->\n' "$HEAD_SHA"
} >"$BODY"
run_in "$REPO" check --head "$HEAD_SHA" --body "$BODY" --base main
assert_exit "check --body exits 0" 0 "$RUN_CODE"
assert_contains "a rendered block passes check --body" "$RUN_OUT" "verdict=clean"
assert_not_contains "prose outside the block is not evidence" "$RUN_OUT" "missing="
assert_not_contains "a commented-out block raises no second-block warning" "$RUN_OUT" "warning=second-block-ignored"

SECOND_BODY="$TEST_TMPDIR/body-two-blocks.md"
{
  printf '## Verification\n\n'
  printf '%s\n' "$BLOCK"
  printf '\n'
  # shellcheck disable=SC2016 # the fence backticks are literal block syntax, not a substitution
  printf '```skill-evidence\nsimplify %s 2026-09-13T20:00:00Z\n```\n' "$ORPHAN_SHA"
} >"$SECOND_BODY"
run_in "$REPO" check --head "$HEAD_SHA" --body "$SECOND_BODY" --base main
assert_contains "a second block is reported" "$RUN_OUT" "warning=second-block-ignored"
assert_contains "the first block is the one read" "$RUN_OUT" "verdict=clean"

MISSING_BODY="$TEST_TMPDIR/body-missing-row.md"
printf '%s\n' "$BLOCK" | grep -v '^simplify ' >"$MISSING_BODY"
run_in "$REPO" check --head "$HEAD_SHA" --body "$MISSING_BODY" --base main
assert_contains "a dropped row is named by check --body" "$RUN_OUT" "missing=simplify"
assert_contains "a dropped row makes the body verdict a gap" "$RUN_OUT" "verdict=gap"

DROPPED_LEDGER="$TEST_TMPDIR/dropped.jsonl"
grep -v '"skill":"simplify"' "$FULL_LEDGER" >"$DROPPED_LEDGER"
run_in "$REPO" check --head "$HEAD_SHA" --ledger "$DROPPED_LEDGER" --base main
assert_contains "a dropped row is named by check --ledger too" "$RUN_OUT" "missing=simplify"

# --- the row grammar: 40 hex, case-insensitive -------------------------------
# The babysit gate's Python reader lowercases the SHA it matches, so a block
# written in upper case must read the same here or the two readers disagree on
# the same body.

UPPER_BODY="$TEST_TMPDIR/body-upper-sha.md"
{
  printf '## Verification\n\n'
  printf '%s\n' "$BLOCK" | awk 'NF == 3 { print $1, toupper($2), $3; next } { print }'
} >"$UPPER_BODY"
run_in "$REPO" check --head "$HEAD_SHA" --body "$UPPER_BODY" --base main
assert_contains "an uppercase row SHA matches a lowercase head" "$RUN_OUT" "fresh=verification:confirm sha=$HEAD_SHA"
assert_not_contains "an uppercase row SHA is not malformed" "$RUN_OUT" "warning=malformed-row"
assert_contains "an uppercase block is clean" "$RUN_OUT" "verdict=clean"

# A ref name where a commit id belongs names no commit either reader can
# compare, so it is skipped and said out loud rather than read as evidence.
BRANCH_ROW_BODY="$TEST_TMPDIR/body-branch-row.md"
{
  printf '## Verification\n\n'
  printf '%s\n' "$BLOCK" |
    awk 'NF == 3 && $1 == "simplify" { print $1, "main", $3; next } { print }'
} >"$BRANCH_ROW_BODY"
run_in "$REPO" check --head "$HEAD_SHA" --body "$BRANCH_ROW_BODY" --base main
assert_contains "a row whose SHA field is a branch name is reported" "$RUN_OUT" "warning=malformed-row"
assert_contains "a row whose SHA field is a branch name is not evidence" "$RUN_OUT" "missing=simplify"

SHORT_SHA_LEDGER="$TEST_TMPDIR/short-sha.jsonl"
: >"$SHORT_SHA_LEDGER"
row "$SHORT_SHA_LEDGER" simplify "$(printf '%s' "$BASE_SHA" | cut -c1-7)" "2026-09-13T10:00:00Z"
run_in "$REPO" check --head "$HEAD_SHA" --ledger "$SHORT_SHA_LEDGER" --base main
assert_contains "an abbreviated ledger SHA is reported malformed" "$RUN_OUT" "warning=malformed-row"
assert_contains "an abbreviated ledger SHA is not evidence" "$RUN_OUT" "missing=simplify"

# --- the base merge ----------------------------------------------------------

git -C "$REPO" checkout -q main
printf 'base moved\n' >>"$REPO/README.md"
git -C "$REPO" commit -qam "base moves" >/dev/null 2>&1
git -C "$REPO" checkout -q work
git -C "$REPO" merge -q --no-ff -m "merge base" main >/dev/null 2>&1
MERGED_SHA="$(sha_of "$REPO" HEAD)"
run_in "$REPO" check --head "$MERGED_SHA" --ledger "$FULL_LEDGER" --base main
assert_contains "a base merge keeps a non-terminal row fresh" "$RUN_OUT" "fresh=simplify sha=$BASE_SHA"
assert_contains "a base merge keeps the markdown row fresh" "$RUN_OUT" "fresh=ai-slop:audit sha=$HEAD_SHA"
assert_contains "a base merge makes the terminal row stale" "$RUN_OUT" "stale=verification:confirm sha=$HEAD_SHA"
assert_contains "a stale terminal row after a merge is a gap" "$RUN_OUT" "verdict=gap"

# --- check --compare (no history on disk) ------------------------------------

FILES_LIST="$TEST_TMPDIR/changed-files.txt"
printf 'scripts/a.sh\ndocs/n.md\n' >"$FILES_LIST"
COMPARE="$TEST_TMPDIR/compare.json"
printf '[{"status":"ahead","ahead_by":1,"base_commit":{"sha":"%s"}},{"status":"identical","ahead_by":0,"base_commit":{"sha":"%s"}}]\n' \
  "$BASE_SHA" "$HEAD_SHA" >"$COMPARE"
run_in "$REPO" check --head "$HEAD_SHA" --body "$BODY" --files "$FILES_LIST" --compare "$COMPARE"
assert_exit "check --compare exits 0" 0 "$RUN_CODE"
assert_contains "compare mode detects the code class" "$RUN_OUT" "class=code"
assert_contains "compare mode reads an ahead status as an ancestor" "$RUN_OUT" "fresh=simplify sha=$BASE_SHA"
assert_contains "compare mode gives the same clean verdict" "$RUN_OUT" "verdict=clean"

COMPARE_BEHIND="$TEST_TMPDIR/compare-behind.json"
printf '[{"status":"diverged","base_commit":{"sha":"%s"}}]\n' "$BASE_SHA" >"$COMPARE_BEHIND"
run_in "$REPO" check --head "$HEAD_SHA" --body "$BODY" --files "$FILES_LIST" --compare "$COMPARE_BEHIND"
assert_contains "a diverged compare status is stale" "$RUN_OUT" "stale=simplify sha=$BASE_SHA"
assert_contains "a sha the payload omits is stale, never assumed fresh" "$RUN_OUT" "stale=review:fanout"

# A row is answered by the payload fetched FOR it, never by one whose merge
# base it happens to be. Every payload is `compare/<row>...<head>`, so a
# diverged row's merge base is routinely another row's commit, and reading the
# merge base would hand that second row the first one's verdict.
COMPARE_COLLIDE="$TEST_TMPDIR/compare-merge-base-collision.json"
printf '[{"status":"diverged","base_commit":{"sha":"%s"},"merge_base_commit":{"sha":"%s"}},{"status":"identical","base_commit":{"sha":"%s"},"merge_base_commit":{"sha":"%s"}}]\n' \
  "$ORPHAN_SHA" "$BASE_SHA" "$BASE_SHA" "$BASE_SHA" >"$COMPARE_COLLIDE"
run_in "$REPO" check --head "$HEAD_SHA" --body "$BODY" --files "$FILES_LIST" --compare "$COMPARE_COLLIDE"
assert_contains "a row is read from its own payload, not from one it is the merge base of" \
  "$RUN_OUT" "fresh=simplify sha=$BASE_SHA"

# --- report ------------------------------------------------------------------

STUB_DIR="$TEST_TMPDIR/stub"
mkdir -p "$STUB_DIR"
cat >"$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
# Stubbed gh: five closed PRs, four of them merged. PR 1 carried a validator
# gap marker and then a validator clean one at a later head (agreed); PR 2
# carried a validator gap marker, with an OUTSIDER's clean marker after it that
# must not read as an agreement; PR 3 never merged and is not sampled; PR 4's
# only marker is an outsider's and is no firing at all; PR 5 carried a gap and
# then a clean marker at the SAME head, the body re-rendered with no new
# commit, which is an agreement too.
#
# The pull-request walk is served as ONE page and refuses `--paginate`: the
# report asks about recently merged pull requests, not about every closed one
# a repository has ever had.
set -u
case "$*" in
*pulls\?*)
  case "$*" in
  *--paginate*) printf 'stub: the pull-request walk must not paginate\n' >&2; exit 1 ;;
  # Anchored on the trailing `&page=1`, because a bare `*page=1*` would match
  # the `per_page=100` every page carries and serve page two as page one.
  *\&page=1)
    cat <<'JSON'
[{"number":1,"merged_at":"2026-09-01T00:00:00Z"},
 {"number":2,"merged_at":"2026-09-02T00:00:00Z"},
 {"number":3,"merged_at":null},
 {"number":4,"merged_at":"2026-09-03T00:00:00Z"},
 {"number":5,"merged_at":"2026-09-04T00:00:00Z"}]
JSON
    ;;
  *) printf '[]\n' ;;
  esac
  ;;
*issues/1/comments*)
  cat <<'JSON'
[{"user":{"login":"github-actions[bot]"},"body":"gap <!-- pr-skill-evidence head=aaaaaaa verdict=gap -->"},
 {"user":{"login":"github-actions[bot]"},"body":"clean <!-- pr-skill-evidence head=bbbbbbb verdict=clean -->"}]
JSON
  ;;
*issues/2/comments*)
  cat <<'JSON'
[{"user":{"login":"github-actions[bot]"},"body":"gap <!-- pr-skill-evidence head=ccccccc verdict=gap -->"},
 {"user":{"login":"drive-by"},"body":"clean <!-- pr-skill-evidence head=ddddddd verdict=clean -->"}]
JSON
  ;;
*issues/4/comments*)
  cat <<'JSON'
[{"user":{"login":"drive-by"},"body":"gap <!-- pr-skill-evidence head=eeeeeee verdict=gap -->"}]
JSON
  ;;
*issues/5/comments*)
  cat <<'JSON'
[{"user":{"login":"github-actions[bot]"},"body":"gap <!-- pr-skill-evidence head=fffffff verdict=gap -->"},
 {"user":{"login":"github-actions[bot]"},"body":"clean <!-- pr-skill-evidence head=fffffff verdict=clean -->"}]
JSON
  ;;
*) printf '[]\n' ;;
esac
STUB
chmod +x "$STUB_DIR/gh"
RUN_OUT="$(cd "$REPO" && PATH="$STUB_DIR:$PATH" "$ENGINE" report --repo acme/app 2>"$TEST_TMPDIR/stderr.txt")"
RUN_CODE=$?
assert_exit "report exits 0" 0 "$RUN_CODE"
# fired=3: PRs 1, 2 and 5. agreed=2: PR 1 (a later head) and PR 5 (the same
# head), but not PR 2, whose clean marker is an outsider's. sampled=4: PRs 1,
# 2, 4 and 5, PR 4 carrying no countable marker.
assert_eq "report counts only the validator's own markers" \
  "fired=3 agreed=2 sampled=4" "$RUN_OUT"

# A clean marker at the SAME head as the gap is a real agreement: the body was
# re-rendered without a new commit, which is exactly how a gap closes when the
# evidence existed and the block did not.
assert_contains "a clean marker at the gap's own head counts as agreement" "$RUN_OUT" "agreed=2"

# --- usage -------------------------------------------------------------------

run_in "$REPO" --help
assert_exit "--help exits 0" 0 "$RUN_CODE"
assert_contains "--help names every subcommand" "$RUN_OUT" "render"

for sub in classes check render report; do
  run_in "$REPO" "$sub" --help
  assert_exit "$sub --help exits 0" 0 "$RUN_CODE"
  assert_contains "$sub --help describes $sub" "$RUN_OUT" "skill-evidence.sh $sub"
done

run_in "$REPO" nonsense
assert_exit "an unknown subcommand is a usage error" 2 "$RUN_CODE"

run_in "$REPO" check --head "$HEAD_SHA" --base main
assert_exit "check with no evidence source is a usage error" 2 "$RUN_CODE"

run_in "$REPO" check --head "$HEAD_SHA" --ledger "$FULL_LEDGER"
assert_exit "check with no class source is a usage error" 2 "$RUN_CODE"

run_in "$REPO" classes --base does-not-exist
assert_exit "an unresolvable base ref is a usage error" 2 "$RUN_CODE"

printf 'PASS/FAIL summary: %d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
