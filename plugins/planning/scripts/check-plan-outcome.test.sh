#!/usr/bin/env bash
# Black-box contract test for check-plan-outcome.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir. Host
# paths and the not-started phase tag in the fixtures are assembled at runtime
# from pieces, so this file carries no literal machine path or deferred-work
# marker for the repository's path and comment-hygiene lints to flag.
#
# SC2016 is disabled file-wide on purpose: the single-quoted `$HOME` and
# backtick spans are literal fixture text, not expansions.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-plan-outcome.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

DRIVE_PATH="C:""/Us""ers/alice/.local/share/chezmoi"
BACKSLASH_PATH='D:'"\\"'work\repo'
HOME_PATH="/ho""me/alice/src/repo"
NOT_STARTED_TAG="[TO""DO]"

good_plan() {
  sed "s/@NOT_STARTED@/$NOT_STARTED_TAG/" <<'EOF'
## Brief
Move dotfiles under chezmoi.

## Plan

### Phase 1: Integration slice @NOT_STARTED@
- Add `.chezmoiignore`. [EXEC-SHAPE]
- **Sanity Check:** `chezmoi apply --dry-run` exits 0.

### Phase 2: Migrate shell config [DOING]
- Move `.bashrc`.
- **Sanity Check:** `grep -c source ~/.bashrc` returns 1.

### Phase 3: Docs [DONE]
- **Sanity Check:** `grep -n chezmoi README.md` is non-empty.

## Blast radius
MEDIUM: touches every login shell.

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) | Source |
|---|---|---|---|
| Ignore file first | Phase 1 adds `.chezmoiignore` | chezmoi docs read this session | plan |

## Handoff to implementation

### Execution shape ([EXEC-SHAPE] tagged)
Sequential.
EOF
}

# run <label> <want_exit> <file> [grep-pattern-that-must-appear]
run() {
  local label="$1" want="$2" file="$3" pattern="${4-}" out got
  out="$(bash "$SUT" "$file" 2>&1)"
  got=$?
  if [[ "$got" -ne "$want" ]]; then
    fail "$label (want exit $want, got $got)"
    printf '%s\n' "$out" | sed 's/^/       /' >&2
    return
  fi
  if [[ -n "$pattern" ]] && ! grep -qE -- "$pattern" <<<"$out"; then
    fail "$label (exit $got as wanted, but no /$pattern/ in output)"
    printf '%s\n' "$out" | sed 's/^/       /' >&2
    return
  fi
  pass "$label"
}

run "--help exits 0" 0 --help 'Mechanical outcome gate'

out="$(bash "$SUT" 2>&1)"
if [[ $? -eq 2 ]]; then pass "no argument exits 2"; else fail "no argument exits 2"; fi
out="$(bash "$SUT" "$TMP/missing.md" 2>&1)"
if [[ $? -eq 2 ]]; then pass "missing file exits 2"; else fail "missing file exits 2"; fi

good_plan >"$TMP/good.md"
run "a complete plan passes every criterion" 0 "$TMP/good.md" '^phases=3 status=ok$'

printf '%s' "$(good_plan)" | sed 's/$/\r/' >"$TMP/crlf.md"
run "a CRLF plan grades the same" 0 "$TMP/crlf.md" '^phases=3 status=ok$'

good_plan | sed 's/^### Phase 2: Migrate shell config \[DOING\]$/### Phase 2: Migrate shell config/' >"$TMP/untagged.md"
run "an untagged phase fails status-tags" 1 "$TMP/untagged.md" 'criterion=status-tags status=fail untagged=Phase-2'

good_plan | sed 's/^### Phase 3: Docs \[DONE\]$/### Phase 3: Docs [WIP]/' >"$TMP/badtag.md"
run "an unknown tag fails status-tags" 1 "$TMP/badtag.md" 'untagged=Phase-3'

good_plan | sed 's/^### Phase 2: Migrate shell config \[DOING\]$/### Phase 2: Migrate shell config [DOING - standing]/' >"$TMP/notedtag.md"
run "a note inside a valid tag's brackets passes" 0 "$TMP/notedtag.md" 'criterion=status-tags status=pass'

good_plan | sed 's/^### Phase 3: Docs \[DONE\]$/### Phase 3: Docs [DONEE]/' >"$TMP/typotag.md"
run "a tag that only starts with a valid state fails" 1 "$TMP/typotag.md" 'untagged=Phase-3'

good_plan | sed '/^## Decisions made/,/^$/{/^## Decisions made/d}' | sed '/^## Decisions made/d' >"$TMP/tableonly.md"
run "the Decision table counts without a Decisions made heading" 0 "$TMP/tableonly.md" 'criterion=decisions status=pass tagged=1 rows=1'

good_plan | grep -v 'grep -c source' >"$TMP/nosanity.md"
run "a phase with no Sanity Check fails, and is named" 1 "$TMP/nosanity.md" 'criterion=sanity-checks status=fail missing=Phase-2$'

# Two Sanity Checks in one phase must not cover a phase that has none.
good_plan | grep -v 'grep -c source' | sed 's/^- \*\*Sanity Check:\*\* `chezmoi apply --dry-run` exits 0\.$/&\n- **Sanity Check:** second check./' >"$TMP/uneven.md"
run "the count is per phase, not a file total" 1 "$TMP/uneven.md" 'missing=Phase-2'

good_plan | sed 's/^### Phase 1:/### Phase I:/; s/^### Phase 2:/### Phase 2.5:/; s/^### Phase 3:/### Phase 3a:/' >"$TMP/numbering.md"
run "Roman, decimal and lettered phase numbers all count" 0 "$TMP/numbering.md" '^phases=3 status=ok$'

good_plan | sed 's/ \[EXEC-SHAPE\]$/ [FALLBACK - confirm or override]/' | sed '/^| Ignore file first/d' >"$TMP/annotatedtag.md"
run "an annotated decision tag still needs a table row" 1 "$TMP/annotatedtag.md" 'criterion=decisions status=fail tagged=1 rows=0'

printf '# Plan\n\nNo phases here.\n\nBlast radius: LOW\n' >"$TMP/nophase.md"
run "a plan with no phase heading fails" 1 "$TMP/nophase.md" 'criterion=phases status=fail'

good_plan | sed '/^## Decisions made/,/^## Handoff/{/^## Handoff/!d}' >"$TMP/nodecisions.md"
run "a tagged decision with no Decision table fails" 1 "$TMP/nodecisions.md" "criterion=decisions status=fail tagged=1 \(no '\| Decision \| What it changes' table\)"

good_plan | sed '/^| Ignore file first/d' >"$TMP/emptydecisions.md"
run "a Decisions made table with no row fails" 1 "$TMP/emptydecisions.md" 'criterion=decisions status=fail tagged=1 rows=0'

good_plan | sed 's/ \[EXEC-SHAPE\]$//' | sed '/^## Decisions made/,/^## Handoff/{/^## Handoff/!d}' >"$TMP/notags.md"
run "the Handoff heading's own tag is not a decision" 0 "$TMP/notags.md" 'criterion=decisions status=pass tagged=0'

good_plan | sed 's/^MEDIUM: touches every login shell\.$/Touches every login shell./' >"$TMP/noblastlevel.md"
run "a Blast radius heading with no level fails" 1 "$TMP/noblastlevel.md" 'criterion=blast-radius status=fail'

good_plan | sed '/^## Blast radius$/,/^MEDIUM/d' | sed 's/^## Brief$/## Brief\n\n**Blast radius**: HIGH/' >"$TMP/blastline.md"
run "an inline Blast radius line with a level passes" 0 "$TMP/blastline.md" 'criterion=blast-radius status=pass'

{ good_plan; printf '\nSource lives at %s.\n' "$DRIVE_PATH"; } >"$TMP/drive.md"
run "a drive-letter user path fails portable-paths" 1 "$TMP/drive.md" 'criterion=portable-paths status=fail hits=1'

{ good_plan; printf '\nClone into %s first.\n' "/Us""ers/Alice/src"; } >"$TMP/upper.md"
run "a capitalized user name still fails portable-paths" 1 "$TMP/upper.md" 'criterion=portable-paths status=fail hits=1'

{ good_plan; printf '\nClone to %s first.\n' "$BACKSLASH_PATH"; } >"$TMP/backslash.md"
run "a backslash drive path fails portable-paths" 1 "$TMP/backslash.md" 'path-hit=[0-9]+:Clone to D:'

{ good_plan; printf '\n```\ncd %s\n```\n' "$HOME_PATH"; } >"$TMP/home.md"
run "a home path fails even inside a code fence" 1 "$TMP/home.md" 'criterion=portable-paths status=fail'

{ good_plan; printf '\nFor example %s <!-- path-example -->\n' "$DRIVE_PATH"; } >"$TMP/annotated.md"
run "an annotated example path passes" 0 "$TMP/annotated.md" 'criterion=portable-paths status=pass hits=0'

{ good_plan; printf '\nSee https://example.com/a and ~/.local/share/chezmoi and $HOME/src.\n'; } >"$TMP/portable.md"
run "URLs and portable forms do not trip the path check" 0 "$TMP/portable.md" 'criterion=portable-paths status=pass'

{ good_plan; printf '\n```markdown\n### Phase 9: quoted template\n```\n'; } >"$TMP/fenced.md"
run "a phase heading inside a code fence is not counted" 0 "$TMP/fenced.md" '^phases=3 status=ok$'

{ good_plan; printf '\nThe folders %s and %s are repo paths.\n' "Domain/Us""ers/User.cs" "src/ho""me/index.ts"; } >"$TMP/repodirs.md"
run "repo folders named Users and home mid-path pass portable-paths" 0 "$TMP/repodirs.md" 'criterion=portable-paths status=pass hits=0'

U_ROOT="/Us""ers/alice/x"
{
  good_plan
  printf '%s\n' "$HOME_PATH"
  printf 'in ticks `%s` here\n' "$HOME_PATH"
  printf 'in quotes "%s" here\n' "$HOME_PATH"
  printf 'in parens (%s) here\n' "$HOME_PATH"
  printf 'assigned ROOT=%s here\n' "$U_ROOT"
} >"$TMP/rooted.md"
run "a /home or /Users path at line start, in ticks, quotes, parens or after = fails" 1 "$TMP/rooted.md" 'criterion=portable-paths status=fail hits=5'

# A three-backtick block quoted inside a four-backtick block must not count as
# real structure: its Phase heading and Sanity Check line are text.
{
  good_plan | sed 's/^- \*\*Sanity Check:\*\* `grep -c source ~\/.bashrc` returns 1\.$//'
  printf '\n````markdown\n```\n### Phase 9: quoted\n- **Sanity Check:** quoted.\n```\n### Phase 8: still quoted\n````\n'
} >"$TMP/nested.md"
run "a nested three-backtick fence adds no phantom phase and no false sanity pass" 1 "$TMP/nested.md" 'criterion=sanity-checks status=fail missing=Phase-2$'
out="$(bash "$SUT" "$TMP/nested.md" 2>&1)"
if grep -q 'Phase-9\|Phase-8' <<<"$out"; then fail "nested fence content leaked into a criterion"; else pass "nested fence content is not graded"; fi

{ good_plan; printf '\n~~~~\n~~~\n### Phase 7: quoted\n~~~\n### Phase 6: quoted\n~~~~\n'; } >"$TMP/nestedtilde.md"
run "a nested tilde fence stays inside its longer outer fence" 0 "$TMP/nestedtilde.md" '^phases=3 status=ok$'

{ good_plan; printf '\n```\n~~~\n### Phase 5: quoted\n```\n'; } >"$TMP/mixedfence.md"
run "a tilde line does not close a backtick fence" 0 "$TMP/mixedfence.md" '^phases=3 status=ok$'

{ good_plan; printf '\n```\n```markdown\n### Phase 4: quoted\n```\n'; } >"$TMP/infostring.md"
run "a fence with an info string does not close an open fence" 0 "$TMP/infostring.md" '^phases=3 status=ok$'

# --approval-only: one criterion, graded after the Approval: line is written.
with_approval() { good_plan | sed "s|^Sequential\.\$|Approval: $1\nSequential.|"; }
approval_run() { # <label> <want_exit> <file> [pattern]
  local label="$1" want="$2" file="$3" pattern="${4-}" out got
  out="$(bash "$SUT" --approval-only "$file" 2>&1)"
  got=$?
  if [[ "$got" -ne "$want" ]]; then
    fail "$label (want exit $want, got $got)"
    printf '%s\n' "$out" | sed 's/^/       /' >&2
  elif [[ -n "$pattern" ]] && ! grep -qE -- "$pattern" <<<"$out"; then
    fail "$label (no /$pattern/ in output)"
    printf '%s\n' "$out" | sed 's/^/       /' >&2
  else
    pass "$label"
  fi
}

with_approval 'attended: approved by Kyle on 2026-09-29' >"$TMP/ap-attended.md"
approval_run "an attended Approval line passes" 0 "$TMP/ap-attended.md" '^criterion=approval status=pass$'

with_approval 'unattended: standing mandate work-loop lane, granted by Kyle in issue 12, review surface the PR' >"$TMP/ap-unattended.md"
approval_run "an unattended Approval line naming mandate, who, where and review surface passes" 0 "$TMP/ap-unattended.md" '^criterion=approval status=pass$'

approval_run "a plan with no Approval line fails" 1 "$TMP/good.md" '^criterion=approval status=fail'

with_approval '' | sed 's/^Approval: $/Approval:/' >"$TMP/ap-empty.md"
approval_run "an empty Approval value fails" 1 "$TMP/ap-empty.md" '^criterion=approval status=fail'

with_approval '<attended: approved by <who> on <date>; unattended: standing mandate <which>, granted by <who> in <where>, review surface <e.g. the PR>>' >"$TMP/ap-template.md"
approval_run "the template placeholder fails" 1 "$TMP/ap-template.md" '^criterion=approval status=fail'

with_approval 'TBD' >"$TMP/ap-tbd.md"
approval_run "a TBD value fails" 1 "$TMP/ap-tbd.md" '^criterion=approval status=fail'

run "the default run does not require an Approval line" 0 "$TMP/good.md" '^phases=3 status=ok$'
run "the default run ignores an unapproved placeholder line" 0 "$TMP/ap-template.md" '^phases=3 status=ok$'

out="$(bash "$SUT" --approval-only 2>&1)"
if [[ $? -eq 2 ]]; then pass "--approval-only with no file exits 2"; else fail "--approval-only with no file exits 2"; fi
run "--help documents --approval-only" 0 --help '--approval-only'

printf '\n'
if [[ "$fails" -eq 0 ]]; then
  printf 'All check-plan-outcome tests passed.\n'
  exit 0
fi
printf '%d check-plan-outcome test(s) failed.\n' "$fails" >&2
exit 1
