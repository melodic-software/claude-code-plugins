#!/usr/bin/env bash
# Regression tests for plan-migration.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/plan-migration.sh"

CASE_NUM=0
FAILED=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1"
  printf '      %s\n' "$2"
}

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}

assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "expected NOT to contain: $3" ;;
  *) pass "$1" ;;
  esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG
  mkdir -p "$1"
  (cd "$1" && git init -q && git config user.email "t@example.com" &&
    git config user.name "t" && git commit -q --allow-empty -m init)
}

commit_all() { (cd "$1" && git add -A && git commit -q -m "${2:-fixture}"); }

# --- Case 1: --help, an unknown argument, and a non-repository ---

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_eq "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"
assert_contains "--help names the row kinds" "$OUT" "DIR, BUDGET, CASE, SUPPRESS, PATHDET, CITE, MENTION, DOCSHOME, ACTION"
assert_contains "--help explains the NONE row" "$OUT" "NONE"
for kind in DIR BUDGET CASE SUPPRESS PATHDET CITE MENTION DOCSHOME ACTION; do
  assert_contains "--help documents the $kind row" "$OUT" "$kind"
done

rc=0
bash "$SCRIPT" --bogus >/dev/null 2>&1 || rc=$?
assert_eq "an unknown argument exits 2" 2 "$rc"

mkdir -p "$TMP/norepo"
rc=0
GIT_CEILING_DIRECTORIES="$TMP" bash "$SCRIPT" --root "$TMP/norepo" >/dev/null 2>&1 || rc=$?
assert_eq "outside a git repository exits 1" 1 "$rc"

# --- Case 2: all five directory states in one repository ---

REPO="$TMP/states"
make_repo "$REPO"
mkdir -p "$REPO/content" "$REPO/shimmed" "$REPO/agentsonly" "$REPO/both" "$REPO/empty"
printf '# Root conventions\n' >"$REPO/AGENTS.md"
printf '@AGENTS.md\n' >"$REPO/CLAUDE.md"
printf '# Everything still here\n\nbody\n' >"$REPO/content/CLAUDE.md"
printf '' >"$REPO/content/AGENTS.md"
printf '# Shared\n' >"$REPO/shimmed/AGENTS.md"
printf '@AGENTS.md\n' >"$REPO/shimmed/CLAUDE.md"
printf '# Portable only\n' >"$REPO/agentsonly/AGENTS.md"
printf '# Shared\n' >"$REPO/both/AGENTS.md"
printf '@AGENTS.md\n\nPlus Claude-only extensions.\n' >"$REPO/both/CLAUDE.md"
printf '' >"$REPO/empty/AGENTS.md"
printf '' >"$REPO/empty/CLAUDE.md"
commit_all "$REPO"

OUT=$(bash "$SCRIPT" --root "$REPO" --home "$TMP/nohome")
assert_contains "the root shim is reported as shim" "$OUT" "DIR	.	shim"
assert_contains "content still in CLAUDE.md" "$OUT" "DIR	content	content-in-claude"
assert_contains "a nested shim is reported as shim" "$OUT" "DIR	shimmed	shim"
assert_contains "an AGENTS.md with no CLAUDE.md" "$OUT" "DIR	agentsonly	agents-only"
assert_contains "both carrying content" "$OUT" "DIR	both	both-with-content"
assert_contains "two empty files" "$OUT" "DIR	empty	zero-byte"

# An HTML-comment note above the import does not stop it being a shim: the
# comment is content the target shape removes, not a different load state.
printf '<!-- see AGENTS.md -->\n@AGENTS.md\n' >"$REPO/shimmed/CLAUDE.md"
commit_all "$REPO" "comment above the import"
OUT=$(bash "$SCRIPT" --root "$REPO" --home "$TMP/nohome")
assert_contains "a comment above the import is still a shim" "$OUT" "DIR	shimmed	shim"

# --- Case 3: other tools' directories are never reported ---

TOOLS="$TMP/tools"
make_repo "$TOOLS"
mkdir -p "$TOOLS/.cursor/rules" "$TOOLS/.codex" "$TOOLS/.github" "$TOOLS/.claude" "$TOOLS/src"
printf '# Root\n' >"$TOOLS/AGENTS.md"
printf '# Cursor\n' >"$TOOLS/.cursor/AGENTS.md"
printf '# Cursor rules\n' >"$TOOLS/.cursor/rules/AGENTS.md"
printf '# Codex\n' >"$TOOLS/.codex/AGENTS.md"
printf '# Actions\n' >"$TOOLS/.github/AGENTS.md"
printf '# Claude dir\n' >"$TOOLS/.claude/CLAUDE.md"
printf '# Src\n' >"$TOOLS/src/AGENTS.md"
commit_all "$TOOLS"

OUT=$(bash "$SCRIPT" --root "$TOOLS" --home "$TMP/nohome")
assert_not_contains "a .cursor/AGENTS.md gets no row" "$OUT" ".cursor"
assert_not_contains "a .codex/AGENTS.md gets no row" "$OUT" ".codex/AGENTS.md"
assert_not_contains "a .github/AGENTS.md gets no row" "$OUT" ".github/AGENTS.md"
assert_not_contains "a .claude/CLAUDE.md gets no row" "$OUT" "DIR	.claude"
assert_contains "an ordinary subtree still gets one" "$OUT" "DIR	src	agents-only"

# --- Case 4: the Codex budget is summed along the root-to-directory path ---

BUDGET="$TMP/budget"
make_repo "$BUDGET"
mkdir -p "$BUDGET/deep/leaf"
head -c 20000 /dev/zero | tr '\0' 'a' >"$BUDGET/AGENTS.md"
head -c 20000 /dev/zero | tr '\0' 'b' >"$BUDGET/deep/AGENTS.md"
printf '# Leaf\n' >"$BUDGET/deep/leaf/AGENTS.md"
commit_all "$BUDGET"

OUT=$(bash "$SCRIPT" --root "$BUDGET" --home "$TMP/nohome")
assert_contains "the root alone is under budget" "$OUT" "BUDGET	.	20000	OK"
assert_contains "the path sum trips the Codex budget" "$OUT" "BUDGET	deep	40000	OVER"
assert_contains "and every directory below it inherits the sum" "$OUT" "BUDGET	deep/leaf	40007	OVER"

# --- Case 5: case variants, path detection, citations and action pins ---

HAZARD="$TMP/hazard"
make_repo "$HAZARD"
mkdir -p "$HAZARD/.github/workflows" "$HAZARD/tools" "$HAZARD/docs"
printf '# Root\n' >"$HAZARD/AGENTS.md"
printf '@AGENTS.md\n' >"$HAZARD/CLAUDE.md"
# A case-variant fixture needs a case-sensitive filesystem: on NTFS `agents.md`
# and `AGENTS.md` are one file, so the fixture cannot exist to be reported.
case_sensitive=0
printf 'a' >"$TMP/CaseProbe"
[[ -f "$TMP/caseprobe" ]] || case_sensitive=1
rm -f "$TMP/CaseProbe"
[[ "$case_sensitive" -eq 1 ]] && printf '# Variant\n' >"$HAZARD/agents.md"
printf 'if [[ -f "$root/CLAUDE.md" ]]; then echo found; fi\n' >"$HAZARD/tools/find-root.sh"
printf '# Comment: -f CLAUDE.md is not a path detector\n' >>"$HAZARD/tools/find-root.sh"
printf 'See [the conventions](../CLAUDE.md#naming) for names.\n' >"$HAZARD/docs/guide.md"
printf 'Prose that merely names CLAUDE.md is not a citation.\n' >>"$HAZARD/docs/guide.md"
printf 'jobs:\n  claude:\n    steps:\n      - uses: anthropics/claude-code-action@8251c10 # v1.0.213\n' \
  >"$HAZARD/.github/workflows/assistant.yml"
commit_all "$HAZARD"

OUT=$(bash "$SCRIPT" --root "$HAZARD" --home "$TMP/nohome")
if [[ "$case_sensitive" -eq 1 ]]; then
  assert_contains "a case-variant file is reported" "$OUT" "CASE	agents.md"
else
  # The variant is what is being detected, so there is no weaker assertion to
  # fall back to: a host that cannot hold both names cannot host this case.
  CASE_NUM=$((CASE_NUM + 1))
  printf 'SKIP: a case-variant file is reported (host filesystem folds case)\n'
fi
assert_contains "an existence test on CLAUDE.md is a path detector" "$OUT" "PATHDET	tools/find-root.sh:1"
# A comment is not a path detector. It IS a mention, which is the row kind that
# exists so "checked and dismissed" beats "never shown".
assert_not_contains "a comment naming CLAUDE.md is not" "$OUT" "PATHDET	tools/find-root.sh:2"
assert_contains "it is reported as a mention instead" "$OUT" "MENTION	tools/find-root.sh:2"
assert_contains "a markdown link into CLAUDE.md is a citation" "$OUT" "CITE	docs/guide.md:1"
assert_not_contains "prose naming CLAUDE.md is not a citation" "$OUT" "CITE	docs/guide.md:2"
assert_contains "it is reported as a mention instead" "$OUT" "MENTION	docs/guide.md:2"
assert_contains "every claude-code-action pin is listed" "$OUT" "claude-code-action@8251c10"
assert_contains "a tracked docs directory is the detected home" "$OUT" "DOCSHOME	docs	found"

OUT=$(bash "$SCRIPT" --root "$BUDGET" --home "$TMP/nohome")
assert_contains "a repository with no docs directory reports absent" "$OUT" "DOCSHOME	docs	absent"

# --- Case 8: a shim carrying a comment is not yet the target shape ---
# The target shape is a CLAUDE.md that is exactly `@AGENTS.md`. A comment above
# the import still loads, but it is content the migration removes, so it gets
# its own state rather than hiding inside `shim` or `both-with-content`.

COMMENT="$TMP/comment"
make_repo "$COMMENT"
mkdir -p "$COMMENT/oneline" "$COMMENT/multiline" "$COMMENT/clean"
printf '# Root\n' >"$COMMENT/AGENTS.md"
printf '@AGENTS.md\n' >"$COMMENT/CLAUDE.md"
printf '# One\n' >"$COMMENT/oneline/AGENTS.md"
printf '<!-- intentionally a pointer -->\n@AGENTS.md\n' >"$COMMENT/oneline/CLAUDE.md"
printf '# Multi\n' >"$COMMENT/multiline/AGENTS.md"
printf '<!--\nthis note spans\nseveral lines\n-->\n@AGENTS.md\n' >"$COMMENT/multiline/CLAUDE.md"
printf '# Clean\n' >"$COMMENT/clean/AGENTS.md"
printf '@AGENTS.md\n' >"$COMMENT/clean/CLAUDE.md"
commit_all "$COMMENT"

OUT=$(bash "$SCRIPT" --root "$COMMENT" --home "$TMP/nohome")
assert_contains "a one-line comment above the import is shim-with-comment" "$OUT" "DIR	oneline	shim-with-comment"
assert_contains "a multi-line comment above the import is too" "$OUT" "DIR	multiline	shim-with-comment"
assert_contains "a bare import is still plain shim" "$OUT" "DIR	clean	shim"
assert_not_contains "and neither comment case is both-with-content" "$OUT" "both-with-content"

# --- Case 9: --root below the repository root still plans the repository ---
# git resolves relative to the directory it is run in, so a --root pointing at a
# subdirectory silently described a subtree as if it were the whole repository.

OUT=$(bash "$SCRIPT" --root "$COMMENT/multiline" --home "$TMP/nohome")
assert_contains "a subdirectory --root still reports the repository root" "$OUT" "DIR	.	shim"
assert_contains "and still reports its siblings" "$OUT" "DIR	oneline	shim-with-comment"

# --- Case 10: another tool's directory hides its AGENTS.md, not a CLAUDE.md ---

OWNED="$TMP/owned"
make_repo "$OWNED"
mkdir -p "$OWNED/.cursor" "$OWNED/.github"
printf '# Root\n' >"$OWNED/AGENTS.md"
printf '@AGENTS.md\n' >"$OWNED/CLAUDE.md"
printf '# Cursor\n' >"$OWNED/.cursor/AGENTS.md"
printf '# Cursor-dir notes for Claude\n' >"$OWNED/.cursor/CLAUDE.md"
printf '# Workflow notes for Claude\n' >"$OWNED/.github/CLAUDE.md"
commit_all "$OWNED"

OUT=$(bash "$SCRIPT" --root "$OWNED" --home "$TMP/nohome")
assert_contains "a Claude CLAUDE.md under .github is planned" "$OUT" "DIR	.github	content-in-claude"
# The AGENTS.md beside it is Cursor's, so it is not paired with the CLAUDE.md
# and contributes nothing: the directory reads as Claude content with no Claude
# AGENTS.md, which is what it is.
assert_contains "a Claude CLAUDE.md under .cursor is planned" "$OUT" "DIR	.cursor	content-in-claude"
# The root AGENTS.md is 7 bytes and still counts on the path; Cursor's own
# 9-byte file does not, so the sum is the root's alone.
assert_contains "and the Cursor file is left out of the Codex budget" "$OUT" "BUDGET	.cursor	7	OK"

# --- Case 11: every other mention of the literal CLAUDE.md ---
# A YAML list entry or a comment naming CLAUDE.md is neither a markdown link nor
# a filesystem-existence call, so CITE and PATHDET both miss it and the operator
# never sees it. claude-code-proxy's .github/workflows/ci.yml carried exactly
# that: a DOCUMENTATION_ROOTS list whose gate the new AGENTS.md failed.

MENTION="$TMP/mention"
make_repo "$MENTION"
mkdir -p "$MENTION/.github/workflows" "$MENTION/docs" "$MENTION/src"
printf '# Root\n' >"$MENTION/AGENTS.md"
printf '@AGENTS.md\n' >"$MENTION/CLAUDE.md"
printf 'env:\n  DOCUMENTATION_ROOTS: "CLAUDE.md README.md"\n' >"$MENTION/.github/workflows/ci.yml"
printf '# Changelog\n\n- moved CLAUDE.md content\n' >"$MENTION/CHANGELOG.md"
printf 'See [conventions](../CLAUDE.md) here.\n' >"$MENTION/docs/linked.md"
printf 'if [[ -f "CLAUDE.md" ]]; then :; fi\n' >"$MENTION/src/find.sh"
commit_all "$MENTION"

OUT=$(bash "$SCRIPT" --root "$MENTION" --home "$TMP/nohome")
assert_contains "a YAML list entry naming CLAUDE.md is a MENTION" "$OUT" "MENTION	.github/workflows/ci.yml:2"
assert_not_contains "a markdown link stays CITE, not MENTION" "$OUT" "MENTION	docs/linked.md"
assert_contains "and it is still reported as a CITE" "$OUT" "CITE	docs/linked.md"
assert_not_contains "an existence call stays PATHDET, not MENTION" "$OUT" "MENTION	src/find.sh"
assert_contains "and it is still reported as a PATHDET" "$OUT" "PATHDET	src/find.sh"
assert_not_contains "a changelog is history, not a mention to triage" "$OUT" "MENTION	CHANGELOG.md"
assert_not_contains "the instruction files themselves are not mentions" "$OUT" "MENTION	CLAUDE.md"

# --- Case 12: an empty row kind says so rather than staying silent ---
# "Checked, none" and "did not run" are the same output otherwise, and a reader
# cannot tell a clean repository from a broken script.

CLEAN="$TMP/cleanrows"
make_repo "$CLEAN"
printf '# Root\n' >"$CLEAN/AGENTS.md"
printf '@AGENTS.md\n' >"$CLEAN/CLAUDE.md"
commit_all "$CLEAN"

OUT=$(bash "$SCRIPT" --root "$CLEAN" --home "$TMP/nohome")
for kind in CASE PATHDET CITE MENTION ACTION; do
  assert_contains "an empty $kind kind reports NONE" "$OUT" "$kind	NONE"
done
assert_not_contains "a kind with rows does not also report NONE" "$OUT" "DIR	NONE"

OUT=$(bash "$SCRIPT" --root "$MENTION" --home "$TMP/nohome")
assert_not_contains "a populated CITE kind reports no NONE row" "$OUT" "CITE	NONE"
assert_not_contains "a populated PATHDET kind reports no NONE row" "$OUT" "PATHDET	NONE"
assert_contains "while an empty one alongside it still does" "$OUT" "CASE	NONE"

# --- Case 6: the home suppressors are reported either way ---

mkdir -p "$TMP/fakehome"
OUT=$(bash "$SCRIPT" --root "$HAZARD" --home "$TMP/fakehome")
assert_contains "an absent bare ~/CLAUDE.md is reported as absent" "$OUT" "CLAUDE.md	no"
printf '# Home\n' >"$TMP/fakehome/CLAUDE.md"
OUT=$(bash "$SCRIPT" --root "$HAZARD" --home "$TMP/fakehome")
assert_contains "a present bare ~/CLAUDE.md is reported as present" "$OUT" "/CLAUDE.md	yes"

# --- Case 7: the run writes nothing ---

BEFORE=$(cd "$HAZARD" && git status --porcelain)
bash "$SCRIPT" --root "$HAZARD" --home "$TMP/fakehome" >/dev/null
AFTER=$(cd "$HAZARD" && git status --porcelain)
assert_eq "the plan leaves the working tree untouched" "$BEFORE" "$AFTER"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
