#!/usr/bin/env bash
# Unit tests for check-skill-portability.sh. Synthetic cases run through --paths
# mode against files in a temp dir with a minimal single-pattern token list
# (SKILL_PORTABILITY_TOKENS); the exclusion case builds a synthetic plugins/ tree
# and runs the script's --all mode from a fixture root, exactly as the
# silent-skip suite does. Two cases run against the REAL corpus to prove the
# bare-vs-guarded discrimination on live files, not only synthetic ones.
#
# Bespoke PASS/FAIL counters by design, not drift: this is repo tooling, not a
# plugin, so no plugin assertion library applies here — see
# docs/conventions/shell-test-helpers/README.md.
# shellcheck disable=SC2016  # fixture bodies are literal skill content in single quotes; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
SCRIPT="$SELF_DIR/check-skill-portability.sh"
REAL_TOKENS="$REPO_ROOT/scripts/skill-portability-tokens.txt"

# Minimal token list: just the active branch class, so a synthetic case is not
# coupled to the shipping list's staged entries.
TEST_TOKENS="$(mktemp)"
printf 'origin/(main|master)\n' >"$TEST_TOKENS"
trap 'rm -f "$TEST_TOKENS"' EXIT

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

# scan_paths <file>... — run the gate over explicit paths with the test tokens.
scan_paths() {
  SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash "$SCRIPT" --paths "$@"
}

# scan_with <token-file> <file>... — run the gate over explicit paths with a
# caller-supplied token list, for the staged Stage-2 classes whose patterns are
# not in the default single-pattern list above.
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

# tokenfile <pattern> — a one-pattern token list, the caller's to remove.
tokenfile() {
  local f
  f="$(mktemp)"
  printf '%s\n' "$1" >"$f"
  printf '%s' "$f"
}

# assert_staged <label> <pattern> — assert <pattern> is present VERBATIM as a
# commented line in the shipping token list's STAGED section.
#
# The fixtures below carry each staged pattern as a literal and assert it still
# matches what ships, rather than parsing it back out of the token file:
# a staged class is documented in prose that necessarily quotes its own pattern
# fragments, so no "which commented line is the data" rule separates pattern
# from commentary without marking up the shipped file with test scaffolding.
#
# Deliberately an assertion in the PARENT shell, never a value-returning
# helper. A `fail` inside a `$(...)` substitution increments a subshell's copy
# of the counter and is lost, and the empty result then makes every
# `if [[ -n "$TOKEN" ]]` fixture below skip in silence — a green suite whose
# Stage 2 coverage has quietly stopped running. That is the silent-skip this
# repo's gates exist to forbid, so the pattern is always non-empty and a drifted
# token file fails loudly here instead.
assert_staged() {
  local label="$1" pattern="$2"
  if grep -qxF -- "# $pattern" "$REAL_TOKENS"; then
    ok "staged $label pattern is present verbatim in the shipped token list"
  else
    fail "staged $label pattern not found verbatim in $REAL_TOKENS: $pattern"
  fi
}

# --- bare origin/main fails with file:line ---------------------------------
f="$(tmpfile 'Base the diff on origin/main for the review.')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "bare origin/main should fail, got success: $out"
elif echo "$out" | grep -q "COUPLING: ${f}:1:"; then
  ok "bare origin/main fails with file:line"
else
  fail "expected COUPLING with file:line, got: $out"
fi
rm -f "$f"

# --- bare origin/master also fails -----------------------------------------
f="$(tmpfile 'git checkout -b feature origin/master')"
if scan_paths "$f" >/dev/null 2>&1; then
  fail "bare origin/master should fail"
else
  ok "bare origin/master fails"
fi
rm -f "$f"

# --- detection-ladder use (origin/HEAD fallback) passes --------------------
f="$(tmpfile 'git merge-base origin/HEAD HEAD (falling back to origin/main, then HEAD)')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "detection-first ladder passes (guarded)"
else
  fail "detection-ladder use should pass"
fi
rm -f "$f"

# --- generic presence prose does NOT guard a bare branch default -----------
f="$(tmpfile 'If using a rebase workflow, diff origin/main first.')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "generic 'if using' prose must not guard a bare branch default: $out"
elif echo "$out" | grep -q "COUPLING: ${f}:1:"; then
  ok "generic optional-dependency prose does not guard the active branch token"
else
  fail "expected line 1 flagged for bare origin/main under 'if using' prose, got: $out"
fi
rm -f "$f"

# --- the bare word "fallback" does NOT guard a bare branch default ----------
f="$(tmpfile 'As a fallback for a network timeout, run git diff origin/main.')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "standalone 'fallback' prose must not guard a bare branch default: $out"
elif echo "$out" | grep -q "COUPLING: ${f}:1:"; then
  ok "standalone 'fallback' prose does not guard the active branch token"
else
  fail "expected line 1 flagged for bare origin/main under 'fallback' prose, got: $out"
fi
rm -f "$f"

# --- a malformed active token fails closed (exit 2), not a silent pass ------
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

# --- same-line portability-ok annotation passes ----------------------------
f="$(tmpfile 'reset --hard origin/main <!-- portability-ok: fixture asserts the hardcode on purpose -->')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "same-line portability-ok passes"
else
  fail "same-line portability-ok should pass"
fi
rm -f "$f"

# --- portability-ok in the comment block above passes ----------------------
f="$(tmpfile '<!-- portability-ok: this reference is intentionally pinned -->
The base branch is origin/main here.')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "comment-block-above portability-ok passes"
else
  fail "comment-block-above portability-ok should pass"
fi
rm -f "$f"

# --- annotation does not leak past intervening code ------------------------
f="$(tmpfile '<!-- portability-ok: covers only the next line -->
diff against origin/main here
now a plain line
diff against origin/main again')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "annotation should not sanction a later hit, got success: $out"
elif echo "$out" | grep -q ":4:" && ! echo "$out" | grep -q ":2:"; then
  ok "annotation covers line 2 only and does not leak past intervening code"
else
  fail "expected line 4 flagged and line 2 clean, got: $out"
fi
rm -f "$f"

# --- a content line with an inline HTML comment does not act as a comment --
# line for pending_annot carry-forward purposes (#611): only a genuine
# block-level `<!--` comment line (opening at start-of-line, modulo leading
# whitespace) may extend an annotation to the next line. Line 2 below has a
# hardcoded token AND an inline `<!--` marker that is NOT itself a
# portability-ok annotation — under the pre-fix bug this made is_comment()
# true for line 2, which left pending_annot carried over from line 1 instead
# of resetting it, wrongly excusing line 3's unannotated hit too.
f="$(tmpfile '<!-- portability-ok: covers only line 2 -->
diff against origin/main here <!-- unrelated inline note, not an annotation -->
diff against origin/main again, unannotated')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "content line with inline HTML comment must not carry annotation to line 3, got success: $out"
elif echo "$out" | grep -q ":3:" && ! echo "$out" | grep -q ":2:"; then
  ok "content line with inline HTML comment does not extend pending_annot to the next line"
else
  fail "expected line 3 flagged and line 2 excused (annotated above), got: $out"
fi
rm -f "$f"

# --- whole-file portability-scope declaration passes -----------------------
f="$(tmpfile '<!-- portability-scope: forge=github — inherent, declared boundary -->
This skill diffs origin/main and pushes with origin/master.')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "whole-file portability-scope passes"
else
  fail "whole-file portability-scope should pass"
fi
rm -f "$f"

# --- a mere MENTION of the token (not a genuine comment-line declaration) --
# does NOT exempt the file -- #1513, shared fix with
# check-shell-portability.sh's identical mechanism.
f="$(tmpfile 'This gate supports a whole-file portability-scope: <reason> declaration.
Base the diff on origin/main for the review.')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "prose merely mentioning portability-scope: should not exempt the file, got success: $out"
elif echo "$out" | grep -q "COUPLING: ${f}:2:"; then
  ok "prose mentioning portability-scope: (not a genuine declaration) does not exempt the file"
else
  fail "expected line 2 flagged (not exempted), got: $out"
fi
rm -f "$f"

# --- a genuine # -comment declaration (not only <!-- -->) also exempts -----
f="$(tmpfile '# portability-scope: shell-script skill file, hash-comment style
Base the diff on origin/main for the review.')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "a genuine #-comment portability-scope declaration also exempts the file"
else
  fail "a genuine #-comment portability-scope declaration should exempt the file"
fi
rm -f "$f"

# =============================================================================
# awk operand disambiguation: a scanned file whose name is shaped like an
# identifier=value assignment must not be silently dropped from the scan
# (#1513, shared fix with check-shell-portability.sh's identical mechanism —
# see #1531)
# =============================================================================
fx="$(mktemp -d)"
mkdir -p "$fx/scripts"
cp "$SCRIPT" "$fx/scripts/"
printf 'diff against origin/main\n' >"$fx/FOO=bar.md"
out="$(cd "$fx" && SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash scripts/check-skill-portability.sh --paths "FOO=bar.md" 2>&1)"
rc=$?
if [[ "$rc" -ne 0 ]] && echo "$out" | grep -q 'COUPLING: FOO=bar\.md:1:'; then
  ok "a filename shaped like identifier=value is scanned, not silently dropped by awk"
else
  fail "an identifier=value-shaped filename must be scanned, not dropped (rc=$rc): $out"
fi
rm -rf "$fx"

# --- staged (commented) tokens stay inactive under the REAL token list -----
f="$(mktemp --suffix=.md)"
printf '%s\n' 'This agnostic skill mentions dotnet and raw.githubusercontent.com.' >"$f"
if SKILL_PORTABILITY_TOKENS="$REAL_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1; then
  ok "staged tokens (dotnet, raw.githubusercontent) are inactive in the shipped list"
else
  fail "shipped list should only enforce the active branch class"
fi
rm -f "$f"

# =============================================================================
# Stage 2 (#713) — forge / branch / remote grammar classes.
#
# Every class below is STAGED in the shipping token list, so each fixture first
# asserts its pattern still matches what ships (assert_staged), then activates
# that pattern in an isolated one-pattern list. Editing a staged class into a
# shape that no longer catches its own defect therefore fails here rather than
# leaving these tests passing against a stale retyped copy.
#
# Each case pairs the coupling that must FAIL with the compliant or declared
# shape that must PASS — a token that only ever fires is indistinguishable from
# one that fires on everything.
# =============================================================================

# --- remote-name class: bare `origin` as a git remote ARGUMENT (#442) -------
REMOTE_TOKEN='git (push|fetch|pull|clone|ls-remote|remote (prune|show|add|rename|get-url|set-url))([[:space:]]+-[^[:space:]]+)*[[:space:]]+origin([^a-zA-Z0-9_/.-]|$)'
assert_staged 'remote-name' "$REMOTE_TOKEN"
rt="$(tokenfile "$REMOTE_TOKEN")"

f="$(tmpfile 'Publish the branch with `git push origin HEAD` when the work is ready.')"
if out="$(scan_with "$rt" "$f" 2>&1)"; then
  fail "a bare 'git push origin' should fail, got success: $out"
elif echo "$out" | grep -q "COUPLING: ${f}:1:"; then
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

# The compliant shape: the remote is resolved into a variable first, so no
# literal `origin` sits in the remote-argument position at all.
f="$(tmpfile 'REMOTE="$(bash scripts/resolve-remote.sh --push)"; git push "$REMOTE" HEAD')"
if scan_with "$rt" "$f" >/dev/null 2>&1; then
  ok "remote class: a resolved remote variable is not flagged"
else
  fail "a resolved remote variable must pass — it is the pattern this class asks for"
fi
rm -f "$f"

# The word `origin` appears in ordinary English and in unrelated compounds
# without asserting a remote NAME; the class is anchored to the
# remote-argument position precisely so none of these fire.
f="$(tmpfile 'The lane requires cross-origin reads to succeed.
Each finding records its origin, and the origin of a default is what this gate tests.')"
if scan_with "$rt" "$f" >/dev/null 2>&1; then
  ok "remote class: prose uses of the word origin are not flagged"
else
  fail "the word origin in prose must not flag — only the remote-argument position"
fi
rm -f "$f"

# A branch-DETECTION ladder still names the remote it queries, so it is a
# true positive for this class even though it is exemplary for the branch
# class. The two couplings are independent: resolving which branch is the
# default says nothing about which remote holds it, and a `git clone -o
# vendor` consumer breaks on the remote name regardless. Recorded as an
# expectation because it is the shape most likely to be mistaken for a
# false positive when this class is activated.
f="$(tmpfile 'Resolve the default via `git ls-remote --symref origin HEAD`.')"
if scan_with "$rt" "$f" >/dev/null 2>&1; then
  fail "a branch-detection ladder still hardcodes its remote name and must flag"
else
  ok "remote class: a branch-detection ladder still flags on its hardcoded remote"
fi
rm -f "$f"

# A per-site escape works on this class exactly as on the active one.
f="$(tmpfile 'Run `git fetch origin` here. <!-- portability-ok: this lane documents a single-remote reset -->')"
if scan_with "$rt" "$f" >/dev/null 2>&1; then
  ok "remote class: a per-site portability-ok escape is honored"
else
  fail "the remote class must honor a per-site portability-ok escape"
fi
rm -f "$f"

rm -f "$rt"

# --- branch-grammar class: shipped Conventional-Commits types (#415) --------
GRAMMAR_TOKEN='`(feat|fix|refactor|chore|docs|test|build|perf|style)/`[^`]*`(feat|fix|refactor|chore|docs|test|build|perf|style)/`'
assert_staged 'branch-grammar' "$GRAMMAR_TOKEN"
gt="$(tokenfile "$GRAMMAR_TOKEN")"

f="$(tmpfile 'Derive the type from the change: `feat/`, `fix/`, `refactor/`, `chore/`.')"
if out="$(scan_with "$gt" "$f" 2>&1)"; then
  fail "a shipped Conventional-Commits type list should fail, got success: $out"
elif echo "$out" | grep -q "COUPLING: ${f}:1:"; then
  ok "branch-grammar class: a shipped type enumeration fails with file:line"
else
  fail "expected line 1 flagged for a shipped type enumeration, got: $out"
fi
rm -f "$f"

# The compliant shape: the grammar is READ from the consuming repo rather
# than shipped, so no enumeration appears at all.
f="$(tmpfile "Read the branch convention from the project's CLAUDE.md or rules index; do not assume one.")"
if scan_with "$gt" "$f" >/dev/null 2>&1; then
  ok "branch-grammar class: deferring to the consumer's convention is not flagged"
else
  fail "reading the consumer's convention must pass — it is this class's fix direction"
fi
rm -f "$f"

# Ordinary prose paths share the type words and must not fire — the reason
# this class ships as the narrow enumeration shape, not a bare alternation.
f="$(tmpfile 'Screenshots land under `build/shots/` and the contract under `docs/conventions/`.')"
if scan_with "$gt" "$f" >/dev/null 2>&1; then
  ok "branch-grammar class: ordinary prose paths are not false-positives"
else
  fail "a prose path like build/shots must not be read as a branch-type grammar"
fi
rm -f "$f"

rm -f "$gt"

# --- branch-shape class: a shipped `<type>/<...>` placeholder (#415) --------
SHAPE_TOKEN='<type>/<'
assert_staged 'branch-shape' "$SHAPE_TOKEN"
st="$(tokenfile "$SHAPE_TOKEN")"

f="$(tmpfile 'Suggest `git checkout -b <type>/<topic-slug>` derived from the plan.')"
if out="$(scan_with "$st" "$f" 2>&1)"; then
  fail "a shipped <type>/<slug> branch shape should fail, got success: $out"
elif echo "$out" | grep -q "COUPLING: ${f}:1:"; then
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

# --- forge class: a hardcoded raw.githubusercontent URL (#432) --------------
FORGE_TOKEN='raw\.githubusercontent\.com'
assert_staged 'forge-URL' "$FORGE_TOKEN"
ft="$(tokenfile "$FORGE_TOKEN")"

f="$(tmpfile 'Apply the contract at <https://raw.githubusercontent.com/acme/plugins/main/docs/README.md> as written.')"
if out="$(scan_with "$ft" "$f" 2>&1)"; then
  fail "a runtime raw.githubusercontent fetch should fail, got success: $out"
elif echo "$out" | grep -q "COUPLING: ${f}:1:"; then
  ok "forge class: a hardcoded raw content URL fails with file:line"
else
  fail "expected line 1 flagged for a hardcoded raw content URL, got: $out"
fi
rm -f "$f"

# The compliant shape: the contract is bundled with the plugin, so resolution
# needs no network and no publisher repo name.
f="$(tmpfile 'Read the bundled contract at `${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`.')"
if scan_with "$ft" "$f" >/dev/null 2>&1; then
  ok "forge class: a bundled CLAUDE_PLUGIN_ROOT reference is not flagged"
else
  fail "a bundled reference must pass — it is this class's fix direction"
fi
rm -f "$f"

rm -f "$ft"

# =============================================================================
# Declared-narrower-scope honor (#441): the acceptance pair proving a
# scope-declared file is exempt while an otherwise identical undeclared one is
# flagged, and that the two escapes do NOT have the same reach — a per-site
# portability-ok covers its site only and must never silence the rest of the
# file the way a whole-file portability-scope does.
# =============================================================================
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
elif echo "$out" | grep -q "COUPLING: ${undeclared}:1:"; then
  ok "declared-scope: the otherwise identical undeclared file is still flagged"
else
  fail "expected the undeclared twin flagged on line 1, got: $out"
fi
rm -f "$declared" "$undeclared"

# Reach asymmetry: a per-site annotation is NOT a whole-file declaration.
# Line 1 is excused by its own annotation; line 3's identical coupling is a
# separate site and must still fail. Conflating the two would turn every
# single-site exemption into a silent file-wide opt-out.
f="$(tmpfile 'Run `git fetch origin` here. <!-- portability-ok: single-remote reset lane -->
Then review the result.
Finally run `git push origin HEAD` with no annotation at all.')"
if out="$(scan_with "$rt" "$f" 2>&1)"; then
  fail "a per-site portability-ok must not exempt the whole file, got success: $out"
elif echo "$out" | grep -q ":3:" && ! echo "$out" | grep -q ":1:"; then
  ok "declared-scope: a per-site portability-ok covers its site only, not the file"
else
  fail "expected line 3 flagged and line 1 excused, got: $out"
fi
rm -f "$f"

rm -f "$rt"

# =============================================================================
# Guard markers are CLASS-SCOPED (#713): is_guarded() receives the matched
# pattern, so the branch class's branch-detection evidence excuses only the
# branch class. Without the scoping, one line carrying both a symbolic-ref
# resolution and a hardcoded remote name would go green on BOTH — the false
# exemption the token file's staged-class preamble forbids.
# =============================================================================
BOTH_TOKENS="$(mktemp)"
printf '%s\n%s\n' 'origin/(main|master)' "$REMOTE_TOKEN" >"$BOTH_TOKENS"

# One line, both couplings. `merge-base` is a branch-class guard marker, so
# the co-located `origin/main` is legitimately excused as a detection-ladder
# fallback. The `git fetch origin` on the same line is a DIFFERENT coupling
# with no guard of its own and must still be reported. Before the guard was
# class-scoped, the branch marker excused the whole line and this hit
# vanished — a real remote hardcode reported clean.
f="$(tmpfile 'Use `git merge-base origin/main HEAD` for the base, then `git fetch origin` to refresh.')"
out="$(scan_with "$BOTH_TOKENS" "$f" 2>&1)"
if echo "$out" | grep -q 'origin/(main|master)'; then
  fail "branch-detection evidence must still guard the BRANCH class on its own line: $out"
elif echo "$out" | grep -q 'ls-remote'; then
  ok "class-scoped guards: branch evidence guards the branch class but not the remote class"
else
  fail "expected the remote class flagged while the branch class stayed guarded, got: $out"
fi
rm -f "$f" "$BOTH_TOKENS"

# --- missing token list fails closed (exit 2) ------------------------------
f="$(tmpfile 'origin/main')"
SKILL_PORTABILITY_TOKENS="/nonexistent/tokens.txt" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
if [[ "$?" -eq 2 ]]; then
  ok "missing token list exits 2 (fail closed)"
else
  fail "missing token list should exit 2"
fi
rm -f "$f"

# --- an invalid base ref fails closed (exit 2) -----------------------------
(cd "$REPO_ROOT" && SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash "$SCRIPT" definitely-not-a-ref >/dev/null 2>&1)
if [[ "$?" -eq 2 ]]; then
  ok "invalid base ref exits 2 (fail closed)"
else
  fail "invalid base ref should exit 2"
fi

# --- --all excludes vendor/, evals/, and *.test.sh -------------------------
fx="$(mktemp -d)"
mkdir -p "$fx/scripts" "$fx/plugins/alpha/skills/x/vendor" "$fx/plugins/alpha/skills/x/evals"
cp "$SCRIPT" "$fx/scripts/"
printf 'diff against origin/main\n' >"$fx/plugins/alpha/skills/x/SKILL.md"
printf 'origin/main\n' >"$fx/plugins/alpha/skills/x/vendor/upstream.md"
printf 'origin/main\n' >"$fx/plugins/alpha/skills/x/evals/e.md"
printf 'origin/main\n' >"$fx/plugins/alpha/skills/x/gen.test.sh"
out="$(cd "$fx" && SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash scripts/check-skill-portability.sh --all 2>&1)"
rc=$?
if [[ "$rc" -ne 0 ]] &&
  echo "$out" | grep -q 'skills/x/SKILL.md' &&
  ! echo "$out" | grep -qE 'vendor/|evals/|test\.sh'; then
  ok "--all scans SKILL.md but excludes vendor/, evals/, and *.test.sh"
else
  fail "--all exclusion set wrong (rc=$rc): $out"
fi
rm -rf "$fx"

# --- empty scope passes ----------------------------------------------------
fx="$(mktemp -d)"
mkdir -p "$fx/scripts" "$fx/plugins"
cp "$SCRIPT" "$fx/scripts/"
if (cd "$fx" && SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash scripts/check-skill-portability.sh --all >/dev/null 2>&1); then
  ok "empty skill tree passes"
else
  fail "empty skill tree should pass"
fi
rm -rf "$fx"

# --- diff-mode reads a Git-quoted (non-ASCII) changed path -----------------
# A changed file whose pathname triggers Git's C-style quoting (here a non-ASCII
# byte; core.quotePath defaults on) must still be gated. Without -z, git diff
# emits `"plugins/.../quoted-\303\251.md"`, the leading quote misses the
# plugins/*/skills/* glob, and the file is silently dropped — the silent
# exclusion the contract forbids. The fixture commits one ASCII-named and one
# non-ASCII-named coupling file, then diffs against the empty base commit: the
# ASCII hit proves -z left the common path intact, and two COUPLING lines prove
# the quoted path was read, not skipped. The non-ASCII name is built with octal
# escapes so this test source stays pure ASCII.
fx="$(mktemp -d)"
mkdir -p "$fx/scripts"
cp "$SCRIPT" "$fx/scripts/"
quoted_name="$(printf 'quoted-\303\251.md')" # trailing U+00E9 byte — non-ASCII, triggers Git quoting
out="$(
  cd "$fx" &&
    git init -q &&
    git config user.email test@example.com &&
    git config user.name test &&
    git commit -q --allow-empty -m base &&
    base="$(git rev-parse HEAD)" &&
    mkdir -p 'plugins/p/skills/s' &&
    printf 'diff against origin/main\n' >'plugins/p/skills/s/plain.md' &&
    printf 'diff against origin/main\n' >"plugins/p/skills/s/${quoted_name}" &&
    git add -A >/dev/null 2>&1 &&
    git commit -q -m add-skills &&
    SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash scripts/check-skill-portability.sh "$base" 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]] &&
  echo "$out" | grep -q 'plain.md:1:' &&
  [[ "$(echo "$out" | grep -c 'COUPLING:')" -eq 2 ]]; then
  ok "diff-mode gates a Git-quoted (non-ASCII) changed path (not silently dropped)"
else
  fail "diff-mode should flag both the ASCII and non-ASCII coupling files (rc=$rc): $out"
fi
rm -rf "$fx"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
