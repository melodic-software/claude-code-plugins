#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixture bodies are literal skill content in single quotes; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
SCRIPT="$SELF_DIR/check-skill-portability.sh"

# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

fx=""

REAL_TOKENS="$REPO_ROOT/scripts/skill-portability-tokens.txt"
. "$SELF_DIR/test-git-helpers.sh"

TEST_TOKENS="$(mktemp)"
printf 'origin/(main|master)\n' >"$TEST_TOKENS"
trap 'rm -f "$TEST_TOKENS"' EXIT

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

scan_paths() {
  SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash "$SCRIPT" --paths "$@"
}

scan_with() {
  local tokens="$1"
  shift
  SKILL_PORTABILITY_TOKENS="$tokens" bash "$SCRIPT" --paths "$@"
}

tmpfile() {
  local f
  f="$(mktemp --suffix=.md)"
  printf '%s\n' "$1" >"$f"
  printf '%s' "$f"
}

tokenfile() {
  local f
  f="$(mktemp)"
  printf '%s\n' "$1" >"$f"
  printf '%s' "$f"
}

assert_staged() {
  local label="$1" pattern="$2"
  if grep -qxF -- "# $pattern" "$REAL_TOKENS"; then
    ok "staged $label pattern is present verbatim in the shipped token list"
  else
    fail "staged $label pattern not found verbatim in $REAL_TOKENS: $pattern"
  fi
}

f="$(tmpfile 'Base the diff on origin/main for the review.')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "bare origin/main should fail, got success: $out"
elif grep -q "COUPLING: ${f}:1:" <<<"$out"; then
  ok "bare origin/main fails with file:line"
else
  fail "expected COUPLING with file:line, got: $out"
fi
rm -f "$f"

f="$(tmpfile 'git checkout -b feature origin/master')"
if scan_paths "$f" >/dev/null 2>&1; then
  fail "bare origin/master should fail"
else
  ok "bare origin/master fails"
fi
rm -f "$f"

f="$(tmpfile 'git merge-base origin/HEAD HEAD (falling back to origin/main, then HEAD)')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "detection-first ladder passes (guarded)"
else
  fail "detection-ladder use should pass"
fi
rm -f "$f"

f="$(tmpfile 'If using a rebase workflow, diff origin/main first.')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "generic 'if using' prose must not guard a bare branch default: $out"
elif grep -q "COUPLING: ${f}:1:" <<<"$out"; then
  ok "generic optional-dependency prose does not guard the active branch token"
else
  fail "expected line 1 flagged for bare origin/main under 'if using' prose, got: $out"
fi
rm -f "$f"

f="$(tmpfile 'As a fallback for a network timeout, run git diff origin/main.')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "standalone 'fallback' prose must not guard a bare branch default: $out"
elif grep -q "COUPLING: ${f}:1:" <<<"$out"; then
  ok "standalone 'fallback' prose does not guard the active branch token"
else
  fail "expected line 1 flagged for bare origin/main under 'fallback' prose, got: $out"
fi
rm -f "$f"

BAD_TOKENS="$(mktemp)"
printf 'origin/(main\n' >"$BAD_TOKENS" # unmatched '(' — invalid ERE, awk faults
f="$(tmpfile 'diff against origin/main here')"
SKILL_PORTABILITY_TOKENS="$BAD_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
if [[ "$?" -eq 2 ]]; then
  ok "malformed active token exits 2 (fail closed, no silent pass)"
else
  fail "malformed active token should exit 2, not silently treat the file as clean"
fi
rm -f "$f" "$BAD_TOKENS"

EMPTY_TOKENS="$(mktemp)"
printf '# only comments\n#\n\n' >"$EMPTY_TOKENS"
f="$(tmpfile 'diff against origin/main here')"
SKILL_PORTABILITY_TOKENS="$EMPTY_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
rc=$?
scan_paths "$f" >/dev/null 2>&1
control=$?
if [[ "$rc" -eq 2 && "$control" -eq 1 ]]; then
  ok "a token list with no active patterns exits 2 (fail closed, gate never silently disabled)"
else
  fail "empty token list should exit 2 (got $rc); control with real tokens should be 1 (got $control)"
fi
rm -f "$f" "$EMPTY_TOKENS"

f="$(tmpfile 'nothing to flag here')"
scan_tmp="$(mktemp -d)"
TMPDIR="$scan_tmp" scan_paths "$f" >/dev/null 2>&1
rc=$?
left="$(ls -A "$scan_tmp")"
if [[ "$rc" -eq 0 && -z "$left" ]]; then
  ok "a clean scan exits 0 and its EXIT trap removes the active-pattern temp file"
else
  fail "clean scan should exit 0 (got $rc) and leave TMPDIR empty (left: $left)"
fi
rm -rf "$scan_tmp" "$f"

f="$(tmpfile 'reset --hard origin/main <!-- portability-ok: fixture asserts the hardcode on purpose -->')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "same-line portability-ok passes"
else
  fail "same-line portability-ok should pass"
fi
rm -f "$f"

f="$(tmpfile 'reset --hard origin/main <!-- portability-ok: -->')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "empty portability-ok should not exempt the hit, got success: $out"
elif grep -q "COUPLING:" <<<"$out"; then
  ok "empty portability-ok does not exempt"
else
  fail "expected COUPLING for empty portability-ok, got: $out"
fi
rm -f "$f"

f="$(tmpfile '<!-- portability-ok: this reference is intentionally pinned -->
The base branch is origin/main here.')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "comment-block-above portability-ok passes"
else
  fail "comment-block-above portability-ok should pass"
fi
rm -f "$f"

f="$(tmpfile '<!-- portability-ok: covers only the next line -->
diff against origin/main here
now a plain line
diff against origin/main again')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "annotation should not sanction a later hit, got success: $out"
elif grep -q ":4:" <<<"$out" && ! grep -q ":2:" <<<"$out"; then
  ok "annotation covers line 2 only and does not leak past intervening code"
else
  fail "expected line 4 flagged and line 2 clean, got: $out"
fi
rm -f "$f"

f="$(tmpfile '<!-- portability-ok: covers only line 2 -->
diff against origin/main here <!-- unrelated inline note, not an annotation -->
diff against origin/main again, unannotated')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "content line with inline HTML comment must not carry annotation to line 3, got success: $out"
elif grep -q ":3:" <<<"$out" && ! grep -q ":2:" <<<"$out"; then
  ok "content line with inline HTML comment does not extend pending_annot to the next line"
else
  fail "expected line 3 flagged and line 2 excused (annotated above), got: $out"
fi
rm -f "$f"

for prefix in '- ' '> ' '* ' '+ ' '1. ' '2) ' '> - '; do
  f="$(tmpfile "${prefix}<!-- portability-ok: container-nested annotation -->
The base branch is origin/main here.")"
  if scan_paths "$f" >/dev/null 2>&1; then
    ok "container-nested annotation comment (\`${prefix}<!--\`) carries to the next line"
  else
    fail "container-nested annotation comment (\`${prefix}<!--\`) should exempt the next line"
  fi
  rm -f "$f"
done

f="$(tmpfile '<!-- portability-ok: covers only line 2 -->
- diff against origin/main here <!-- inline note, not an annotation -->
- diff against origin/main again, unannotated')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "list-item content line with inline comment must not carry annotation to line 3, got success: $out"
elif grep -q ":3:" <<<"$out" && ! grep -q ":2:" <<<"$out"; then
  ok "list-item content line with inline HTML comment does not extend pending_annot"
else
  fail "expected line 3 flagged and line 2 excused (annotated above), got: $out"
fi
rm -f "$f"

f="$(tmpfile '> <!-- portability-scope: forge=github — inherent, declared boundary -->
This skill diffs origin/main and pushes with origin/master.')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "blockquote-nested portability-scope declaration exempts the file"
else
  fail "blockquote-nested portability-scope declaration should exempt the file"
fi
rm -f "$f"

f="$(tmpfile '<!-- portability-scope: forge=github — inherent, declared boundary -->
This skill diffs origin/main and pushes with origin/master.')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "whole-file portability-scope passes"
else
  fail "whole-file portability-scope should pass"
fi
rm -f "$f"

f="$(tmpfile 'This gate supports a whole-file portability-scope: <reason> declaration.
Base the diff on origin/main for the review.')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "prose merely mentioning portability-scope: should not exempt the file, got success: $out"
elif grep -q "COUPLING: ${f}:2:" <<<"$out"; then
  ok "prose mentioning portability-scope: (not a genuine declaration) does not exempt the file"
else
  fail "expected line 2 flagged (not exempted), got: $out"
fi
rm -f "$f"

f="$(tmpfile '# portability-scope: shell-script skill file, hash-comment style
Base the diff on origin/main for the review.')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "a genuine #-comment portability-scope declaration also exempts the file"
else
  fail "a genuine #-comment portability-scope declaration should exempt the file"
fi
rm -f "$f"

fixture_tree::build fx --sut "$SCRIPT"
printf 'diff against origin/main\n' >"$fx/FOO=bar.md"
out="$(cd "$fx" && SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash scripts/check-skill-portability.sh --paths "FOO=bar.md" 2>&1)"
rc=$?
if [[ "$rc" -ne 0 ]] && grep -q 'COUPLING: FOO=bar\.md:1:' <<<"$out"; then
  ok "a filename shaped like identifier=value is scanned, not silently dropped by awk"
else
  fail "an identifier=value-shaped filename must be scanned, not dropped (rc=$rc): $out"
fi
rm -rf "$fx"

fixture_tree::build fx --sut "$SCRIPT"
cp "$TEST_TOKENS" "$fx/t=custom.txt"
printf 'diff against origin/main\n' >"$fx/plain.md"
out="$(cd "$fx" && SKILL_PORTABILITY_TOKENS="t=custom.txt" bash scripts/check-skill-portability.sh --paths "plain.md" 2>&1)"
rc=$?
if [[ "$rc" -eq 1 ]] && grep -q 'COUPLING: plain\.md:1:' <<<"$out"; then
  ok "a token list shaped like identifier=value still loads its patterns"
else
  fail "an identifier=value-shaped token list must not silently disable the gate (rc=$rc): $out"
fi
cp "$TEST_TOKENS" "$fx/plain-tokens.txt"
out="$(cd "$fx" && SKILL_PORTABILITY_TOKENS="plain-tokens.txt" bash scripts/check-skill-portability.sh --paths "plain.md" 2>&1)"
if [[ "$?" -eq 1 ]] && grep -q 'COUPLING: plain\.md:1:' <<<"$out"; then
  ok "the same fixture flags through an ordinary token path (guard is discriminating)"
else
  fail "control case did not flag; the token-list assertion above is not discriminating"
fi
rm -rf "$fx"

f="$(mktemp --suffix=.md)"
printf '%s\n' 'This agnostic skill mentions dotnet and raw.githubusercontent.com.' >"$f"
if SKILL_PORTABILITY_TOKENS="$REAL_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1; then
  ok "staged tokens (dotnet, raw.githubusercontent) are inactive in the shipped list"
else
  fail "shipped list should only enforce the active branch class"
fi
rm -f "$f"

REMOTE_TOKEN='git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+(push|fetch|pull|clone|ls-remote|remote (prune|show|add|rename|get-url|set-url))([[:space:]]+-[^[:space:]]+)*[[:space:]]+origin([^a-zA-Z0-9_/.-]|$)'
assert_staged 'remote-name' "$REMOTE_TOKEN"
rt="$(tokenfile "$REMOTE_TOKEN")"

f="$(tmpfile 'Publish the branch with `git push origin HEAD` when the work is ready.')"
if out="$(scan_with "$rt" "$f" 2>&1)"; then
  fail "a bare 'git push origin' should fail, got success: $out"
elif grep -q "COUPLING: ${f}:1:" <<<"$out"; then
  ok "remote class: a bare origin remote argument fails with file:line"
else
  fail "expected line 1 flagged for a bare origin remote argument, got: $out"
fi
rm -f "$f"

f="$(tmpfile 'Fetch the base with `git fetch origin "$DEFAULT_BRANCH"` before merging.')"
if scan_with "$rt" "$f" >/dev/null 2>&1; then
  fail "a bare origin remote argument must flag even when the BRANCH is resolved"
else
  ok "remote class: resolving the branch does not excuse a hardcoded remote name"
fi
rm -f "$f"

f="$(tmpfile 'Re-fetch the base ref (`git -C <worktree> fetch origin <base>`) before merging.')"
if out="$(scan_with "$rt" "$f" 2>&1)"; then
  fail "a global option before the subcommand must not hide the hardcoded remote: $out"
elif grep -q "COUPLING: ${f}:1:" <<<"$out"; then
  ok "remote class: a global option before the subcommand still flags the remote"
else
  fail "expected line 1 flagged for 'git -C <path> fetch origin', got: $out"
fi
rm -f "$f"

f="$(tmpfile 'Run `git -c core.hooksPath=/dev/null --git-dir=/w/.git push origin HEAD` in the sandbox.')"
if scan_with "$rt" "$f" >/dev/null 2>&1; then
  fail "a run of global options must not hide the hardcoded remote"
else
  ok "remote class: a run of value-taking global options still flags the remote"
fi
rm -f "$f"

f="$(tmpfile 'Run `git -C "$WT" status`, then push to the origin remote you resolved.')"
if scan_with "$rt" "$f" >/dev/null 2>&1; then
  ok "remote class: global options on a non-remote subcommand are not false-positives"
else
  fail "a global option on an unrelated subcommand must not flag on nearby prose"
fi
rm -f "$f"

f="$(tmpfile 'REMOTE="$(bash scripts/resolve-remote.sh --push)"; git push "$REMOTE" HEAD
Re-fetch with `git -C "$WT" fetch "$REMOTE" "$BASE"` before merging.')"
if scan_with "$rt" "$f" >/dev/null 2>&1; then
  ok "remote class: a resolved remote variable is not flagged"
else
  fail "a resolved remote variable must pass — it is the pattern this class asks for"
fi
rm -f "$f"

f="$(tmpfile 'The lane requires cross-origin reads to succeed.
Each finding records its origin, and the origin of a default is what this gate tests.')"
if scan_with "$rt" "$f" >/dev/null 2>&1; then
  ok "remote class: prose uses of the word origin are not flagged"
else
  fail "the word origin in prose must not flag — only the remote-argument position"
fi
rm -f "$f"

f="$(tmpfile 'Resolve the default via `git ls-remote --symref origin HEAD`.')"
if scan_with "$rt" "$f" >/dev/null 2>&1; then
  fail "a branch-detection ladder still hardcodes its remote name and must flag"
else
  ok "remote class: a branch-detection ladder still flags on its hardcoded remote"
fi
rm -f "$f"

f="$(tmpfile 'Run `git fetch origin` here. <!-- portability-ok: this lane documents a single-remote reset -->')"
if scan_with "$rt" "$f" >/dev/null 2>&1; then
  ok "remote class: a per-site portability-ok escape is honored"
else
  fail "the remote class must honor a per-site portability-ok escape"
fi
rm -f "$f"

rm -f "$rt"

GRAMMAR_TOKEN='`(feat|fix|refactor|chore|docs|test|build|perf|style)/`[^`]*`(feat|fix|refactor|chore|docs|test|build|perf|style)/`'
assert_staged 'branch-grammar' "$GRAMMAR_TOKEN"
gt="$(tokenfile "$GRAMMAR_TOKEN")"

f="$(tmpfile 'Derive the type from the change: `feat/`, `fix/`, `refactor/`, `chore/`.')"
if out="$(scan_with "$gt" "$f" 2>&1)"; then
  fail "a shipped Conventional-Commits type list should fail, got success: $out"
elif grep -q "COUPLING: ${f}:1:" <<<"$out"; then
  ok "branch-grammar class: a shipped type enumeration fails with file:line"
else
  fail "expected line 1 flagged for a shipped type enumeration, got: $out"
fi
rm -f "$f"

f="$(tmpfile "Read the branch convention from the project's CLAUDE.md or rules index; do not assume one.")"
if scan_with "$gt" "$f" >/dev/null 2>&1; then
  ok "branch-grammar class: deferring to the consumer's convention is not flagged"
else
  fail "reading the consumer's convention must pass — it is this class's fix direction"
fi
rm -f "$f"

f="$(tmpfile 'Screenshots land under `build/shots/` and the contract under `docs/conventions/`.')"
if scan_with "$gt" "$f" >/dev/null 2>&1; then
  ok "branch-grammar class: ordinary prose paths are not false-positives"
else
  fail "a prose path like build/shots must not be read as a branch-type grammar"
fi
rm -f "$f"

rm -f "$gt"

SHAPE_TOKEN='<type>/<'
assert_staged 'branch-shape' "$SHAPE_TOKEN"
st="$(tokenfile "$SHAPE_TOKEN")"

f="$(tmpfile 'Suggest `git checkout -b <type>/<topic-slug>` derived from the plan.')"
if out="$(scan_with "$st" "$f" 2>&1)"; then
  fail "a shipped <type>/<slug> branch shape should fail, got success: $out"
elif grep -q "COUPLING: ${f}:1:" <<<"$out"; then
  ok "branch-shape class: a shipped <type>/<slug> placeholder fails with file:line"
else
  fail "expected line 1 flagged for a shipped branch shape, got: $out"
fi
rm -f "$f"

f="$(tmpfile "Propose a name following the project's own branch-naming convention.")"
if scan_with "$st" "$f" >/dev/null 2>&1; then
  ok "branch-shape class: a convention-deferring suggestion is not flagged"
else
  fail "a convention-deferring suggestion must pass"
fi
rm -f "$f"

rm -f "$st"

FORGE_TOKEN='raw\.githubusercontent\.com'
assert_staged 'forge-URL' "$FORGE_TOKEN"
ft="$(tokenfile "$FORGE_TOKEN")"

f="$(tmpfile 'Apply the contract at <https://raw.githubusercontent.com/acme/plugins/main/docs/README.md> as written.')"
if out="$(scan_with "$ft" "$f" 2>&1)"; then
  fail "a runtime raw.githubusercontent fetch should fail, got success: $out"
elif grep -q "COUPLING: ${f}:1:" <<<"$out"; then
  ok "forge class: a hardcoded raw content URL fails with file:line"
else
  fail "expected line 1 flagged for a hardcoded raw content URL, got: $out"
fi
rm -f "$f"

f="$(tmpfile 'Read the bundled contract at `${CLAUDE_PLUGIN_ROOT}/reference/contract.md`.')"
if scan_with "$ft" "$f" >/dev/null 2>&1; then
  ok "forge class: a bundled CLAUDE_PLUGIN_ROOT reference is not flagged"
else
  fail "a bundled reference must pass — it is this class's fix direction"
fi
rm -f "$f"

rm -f "$ft"

rt="$(tokenfile "$REMOTE_TOKEN")"

declared="$(tmpfile '<!-- portability-scope: forge=github — this skill wraps gh and is inherently GitHub-locked -->
Fetch with `git fetch origin` and publish with `git push origin HEAD`.')"
undeclared="$(tmpfile 'Fetch with `git fetch origin` and publish with `git push origin HEAD`.')"

if scan_with "$rt" "$declared" >/dev/null 2>&1; then
  ok "declared-scope: a portability-scope file is exempt from a Stage 2 class"
else
  fail "a portability-scope declaration must exempt the whole file for every active class"
fi

if out="$(scan_with "$rt" "$undeclared" 2>&1)"; then
  fail "the undeclared twin of a scope-declared file must still flag, got success: $out"
elif grep -q "COUPLING: ${undeclared}:1:" <<<"$out"; then
  ok "declared-scope: the otherwise identical undeclared file is still flagged"
else
  fail "expected the undeclared twin flagged on line 1, got: $out"
fi
rm -f "$declared" "$undeclared"

f="$(tmpfile 'Run `git fetch origin` here. <!-- portability-ok: single-remote reset lane -->
Then review the result.
Finally run `git push origin HEAD` with no annotation at all.')"
if out="$(scan_with "$rt" "$f" 2>&1)"; then
  fail "a per-site portability-ok must not exempt the whole file, got success: $out"
elif grep -q ":3:" <<<"$out" && ! grep -q ":1:" <<<"$out"; then
  ok "declared-scope: a per-site portability-ok covers its site only, not the file"
else
  fail "expected line 3 flagged and line 1 excused, got: $out"
fi
rm -f "$f"

rm -f "$rt"

BOTH_TOKENS="$(mktemp)"
printf '%s\n%s\n' 'origin/(main|master)' "$REMOTE_TOKEN" >"$BOTH_TOKENS"

f="$(tmpfile 'Use `git merge-base origin/main HEAD` for the base, then `git fetch origin` to refresh.')"
out="$(scan_with "$BOTH_TOKENS" "$f" 2>&1)"
if grep -q 'origin/(main|master)' <<<"$out"; then
  fail "branch-detection evidence must still guard the BRANCH class on its own line: $out"
elif grep -q 'ls-remote' <<<"$out"; then
  ok "class-scoped guards: branch evidence guards the branch class but not the remote class"
else
  fail "expected the remote class flagged while the branch class stayed guarded, got: $out"
fi
rm -f "$f" "$BOTH_TOKENS"

f="$(tmpfile 'origin/main')"
SKILL_PORTABILITY_TOKENS="/nonexistent/tokens.txt" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
if [[ "$?" -eq 2 ]]; then
  ok "missing token list exits 2 (fail closed)"
else
  fail "missing token list should exit 2"
fi
rm -f "$f"

(cd "$REPO_ROOT" && SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash "$SCRIPT" definitely-not-a-ref >/dev/null 2>&1)
if [[ "$?" -eq 2 ]]; then
  ok "invalid base ref exits 2 (fail closed)"
else
  fail "invalid base ref should exit 2"
fi

fixture_tree::build fx --sut "$SCRIPT"
mkdir -p "$fx/plugins/alpha/skills/x/vendor" "$fx/plugins/alpha/skills/x/evals"
printf 'diff against origin/main\n' >"$fx/plugins/alpha/skills/x/SKILL.md"
printf 'origin/main\n' >"$fx/plugins/alpha/skills/x/vendor/upstream.md"
printf 'origin/main\n' >"$fx/plugins/alpha/skills/x/evals/e.md"
printf 'origin/main\n' >"$fx/plugins/alpha/skills/x/gen.test.sh"
out="$(cd "$fx" && SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash scripts/check-skill-portability.sh --all 2>&1)"
rc=$?
if [[ "$rc" -ne 0 ]] &&
  grep -q 'skills/x/SKILL.md' <<<"$out" &&
  ! grep -qE 'vendor/|evals/|test\.sh' <<<"$out"; then
  ok "--all scans SKILL.md but excludes vendor/, evals/, and *.test.sh"
else
  fail "--all exclusion set wrong (rc=$rc): $out"
fi
rm -rf "$fx"

fixture_tree::build fx --sut "$SCRIPT" --plugins
if (cd "$fx" && SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash scripts/check-skill-portability.sh --all >/dev/null 2>&1); then
  ok "empty skill tree passes"
else
  fail "empty skill tree should pass"
fi
rm -rf "$fx"

fixture_tree::build fx --sut "$SCRIPT"
quoted_name="$(printf 'quoted-\303\251.md')" # trailing U+00E9 byte — non-ASCII, triggers Git quoting
out="$(
  cd "$fx" &&
    git_init_test_repo "$fx" &&
    git -C "$fx" commit -q --allow-empty -m base &&
    base="$(git -C "$fx" rev-parse HEAD)" &&
    mkdir -p 'plugins/p/skills/s' &&
    printf 'diff against origin/main\n' >'plugins/p/skills/s/plain.md' &&
    printf 'diff against origin/main\n' >"plugins/p/skills/s/${quoted_name}" &&
    git -C "$fx" add -A >/dev/null 2>&1 &&
    git -C "$fx" commit -q -m add-skills &&
    SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash scripts/check-skill-portability.sh "$base" 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]] &&
  grep -q 'plain.md:1:' <<<"$out" &&
  [[ "$(echo "$out" | grep -c 'COUPLING:')" -eq 2 ]]; then
  ok "diff-mode gates a Git-quoted (non-ASCII) changed path (not silently dropped)"
else
  fail "diff-mode should flag both the ASCII and non-ASCII coupling files (rc=$rc): $out"
fi
rm -rf "$fx"

ECO_TOKEN='[Dd]otnet'
et="$(tokenfile "$ECO_TOKEN")"

f="$(tmpfile 'Build the project with `dotnet build` before running the tests.')"
if out="$(scan_with "$et" "$f" 2>&1)"; then
  fail "a bare 'dotnet build' should fail in an agnostic skill, got success: $out"
elif grep -q "COUPLING: ${f}:1:" <<<"$out"; then
  ok "ecosystem class: a bare stack default fails with file:line"
else
  fail "expected line 1 flagged for a bare stack default, got: $out"
fi
rm -f "$f"

f="$(tmpfile 'Run `${user_config.build_command}` — never assume dotnet build.')"
if scan_with "$et" "$f" >/dev/null 2>&1; then
  ok "ecosystem class: a userConfig seam read on the line is honored"
else
  fail "a '\${user_config.*}' seam read must excuse the ecosystem class"
fi
rm -f "$f"

f="$(tmpfile 'This skill has a userConfig seam, so run dotnet build here.')"
if scan_with "$et" "$f" >/dev/null 2>&1; then
  fail "prose mentioning userConfig must NOT guard a bare stack default"
else
  ok "ecosystem class: prose about a seam does not stand in for a seam read"
fi
rm -f "$f"

f="$(tmpfile 'Run `<build-command>` — e.g. `dotnet build`, `npm run build`, `cargo build`.')"
if scan_with "$et" "$f" >/dev/null 2>&1; then
  ok "ecosystem class: a placeholder with an explicit illustration lead is honored"
else
  fail "a '<placeholder> ... e.g. <stack>' illustration must be honored"
fi
rm -f "$f"

f="$(tmpfile 'Run `<build-command>` — for example `dotnet build` or `npm run build`.')"
if scan_with "$et" "$f" >/dev/null 2>&1; then
  ok "ecosystem class: 'for example' is accepted as an illustration lead"
else
  fail "'for example' must be accepted as an illustration lead"
fi
rm -f "$f"

f="$(tmpfile 'Run `<build-command>`, such as `dotnet build` or `cargo build`.')"
if scan_with "$et" "$f" >/dev/null 2>&1; then
  ok "ecosystem class: 'such as' is accepted as an illustration lead"
else
  fail "'such as' must be accepted as an illustration lead"
fi
rm -f "$f"

f="$(tmpfile 'Run dotnet build from <repo-root> before continuing.')"
if scan_with "$et" "$f" >/dev/null 2>&1; then
  fail "a placeholder alone must NOT guard a shipped stack default"
else
  ok "ecosystem class: a placeholder without an illustration lead still flags"
fi
rm -f "$f"

f="$(tmpfile 'Build the project, e.g. run dotnet build at the repository root.')"
if scan_with "$et" "$f" >/dev/null 2>&1; then
  fail "an 'e.g.' hedge alone must NOT guard a shipped stack default"
else
  ok "ecosystem class: an illustration lead without a placeholder still flags"
fi
rm -f "$f"

f="$(tmpfile 'Run `dotnet build`. <!-- portability-ok: this plugin ships a .NET analyzer -->')"
if scan_with "$et" "$f" >/dev/null 2>&1; then
  ok "ecosystem class: a per-site portability-ok escape is honored"
else
  fail "the ecosystem class must honor a per-site portability-ok escape"
fi
rm -f "$f"

f="$(tmpfile '<!-- portability-scope: this skill targets .NET solutions only -->
Run `dotnet build` to restore and compile.')"
if scan_with "$et" "$f" >/dev/null 2>&1; then
  ok "ecosystem class: a whole-file portability-scope declaration is honored"
else
  fail "the ecosystem class must honor a whole-file portability-scope declaration"
fi
rm -f "$f"

f="$(tmpfile 'Resolve the base with `git symbolic-ref refs/remotes/origin/HEAD`, then run dotnet build.')"
if scan_with "$et" "$f" >/dev/null 2>&1; then
  fail "branch-resolution evidence must NOT excuse an ecosystem hardcode"
else
  ok "ecosystem class: branch-detection evidence does not excuse a stack default"
fi
rm -f "$f"

f="$(tmpfile 'Read `${user_config.build_command}`, then diff against origin/main.')"
if scan_paths "$f" >/dev/null 2>&1; then
  fail "a userConfig seam read must NOT excuse a bare branch default"
else
  ok "branch class: an ecosystem seam read does not excuse a branch default"
fi
rm -f "$f"

rm -f "$et"

STAGED_COVERAGE=(
  '[Dd]otnet' 'dotnet build'
  '(^|[^a-zA-Z0-9_])\.NET([^a-zA-Z0-9_]|$)' 'the .NET SDK'
  '\.csproj' 'src/App.csproj'
  '(^|[^a-zA-Z0-9_])C#([^a-zA-Z0-9_]|$)' 'the C# compiler'
  '[Bb]lazor' 'Blazor components'
  '\.sln([^a-zA-Z0-9_]|$)' 'App.sln here'
  '\.razor' 'Page.razor here'
  '\*\*/\*\.cs([^a-zA-Z0-9_]|$)' 'the **/*.cs glob'
)
for ((i = 0; i < ${#STAGED_COVERAGE[@]}; i += 2)); do
  pat="${STAGED_COVERAGE[i]}"
  sample="${STAGED_COVERAGE[i + 1]}"
  tf="$(tokenfile "$pat")"
  control="$(tmpfile "Then run ${sample} at the repository root.")"
  guarded="$(tmpfile "Read \`\${user_config.build_command}\` — never assume ${sample}.")"
  if scan_with "$tf" "$control" >/dev/null 2>&1; then
    fail "coverage fixture for '$pat' does not match it — the assertion would be vacuous"
  elif scan_with "$tf" "$guarded" >/dev/null 2>&1; then
    ok "ecosystem class membership: '$pat' is recognized by the guard"
  else
    fail "staged ecosystem literal '$pat' is not covered by is_ecosystem_pattern"
  fi
  rm -f "$tf" "$control" "$guarded"
done

f="$(tmpfile 'Place the handler in the Application layer per Clean Architecture.')"
if out="$(SKILL_PORTABILITY_TOKENS="$REAL_TOKENS" bash "$SCRIPT" --paths "$f" 2>&1)"; then
  fail "Clean Architecture vocabulary should be enforced by the shipped list: $out"
elif grep -q "COUPLING: ${f}:1:" <<<"$out"; then
  ok "Clean-Architecture vocabulary is ACTIVE in the shipped token list"
else
  fail "expected line 1 flagged for Clean-Architecture vocabulary, got: $out"
fi
rm -f "$f"

f="$(tmpfile '<!-- portability-scope: this skill teaches Clean Architecture itself -->
Place the handler in the Application layer per Clean Architecture.')"
if SKILL_PORTABILITY_TOKENS="$REAL_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1; then
  ok "Clean-Architecture vocabulary is excused by a declared narrower scope"
else
  fail "an active Clean-Architecture token must honor portability-scope"
fi
rm -f "$f"

f="$(tmpfile 'Organize by `<architecture-style>` — e.g. Clean Architecture, vertical slices.')"
if SKILL_PORTABILITY_TOKENS="$REAL_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1; then
  ok "Clean-Architecture vocabulary is excused by placeholder-plus-illustration"
else
  fail "the architecture token must honor the placeholder-plus-illustration shape"
fi
rm -f "$f"

f="$(tmpfile 'Read `${user_config.test_command}`, then place handlers per Clean Architecture.')"
if SKILL_PORTABILITY_TOKENS="$REAL_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1; then
  fail "an unrelated userConfig read must NOT excuse a hardcoded architecture"
else
  ok "architecture token: an unrelated userConfig read does not excuse it"
fi
rm -f "$f"

f="$(tmpfile 'Move the tarball to the Clean Archive directory before pruning.')"
if SKILL_PORTABILITY_TOKENS="$REAL_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1; then
  ok "architecture token: 'Clean Archive' is not a Clean-Architecture hit"
else
  fail "'Clean Archive directory' must not flag — the optional suffix stopped short"
fi
rm -f "$f"

f="$(tmpfile 'The reviewer called the result UnClean Architecture, half-migrated.')"
if SKILL_PORTABILITY_TOKENS="$REAL_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1; then
  ok "architecture token: a match cannot begin inside a preceding word"
else
  fail "'UnClean Architecture' must not flag — the token needs a left boundary"
fi
rm -f "$f"

for ((i = 0; i < ${#STAGED_COVERAGE[@]}; i += 2)); do
  assert_staged 'ecosystem literal' "${STAGED_COVERAGE[i]}"
done

if grep -q '[\]b' < <(grep -vE '^[[:space:]]*(#|$)' "$REAL_TOKENS"); then
  fail "a backslash-b word-boundary escape reached an ACTIVE token — POSIX ERE does not define it"
else
  ok "no ACTIVE token carries a backslash-b word-boundary escape"
fi

test_harness::report
