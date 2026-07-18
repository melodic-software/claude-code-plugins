#!/usr/bin/env bash
# Contract test for block-dangerous-git.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash JSON on
# stdin, asserts on exit code (2 = blocked, 0 = allowed). Self-contained — no
# host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-dangerous-git.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# run <label> <command> <expected-exit> [extra-env NAME=VAL ...]
run() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc
  env "$@" bash "$HOOK" <<<"$(command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

# --- push-force ---------------------------------------------------------------
run "git push --force (blocked)" "git push --force" 2
run "git push -f (blocked)" "git push -f origin main" 2
run "git push origin main --force (flag after operands, blocked)" "git push origin main --force" 2
run "git push -uf (bundled f, blocked)" "git push -uf origin main" 2
run "git push origin +HEAD:main (refspec force, blocked)" "git push origin +HEAD:main" 2
run "git push origin +feature (bare + refspec, blocked)" "git push origin +feature" 2
run "git push --mirror (force-updates all refs, blocked)" "git push --mirror backup" 2
run "git push --force-with-lease (safe force, allowed)" "git push --force-with-lease" 0
run "git push --force-with-lease=main (valued lease, allowed)" "git push --force-with-lease=main origin main" 0
run "git push --force-if-includes (allowed)" "git push --force-with-lease --force-if-includes" 0
run "git push (plain, allowed)" "git push" 0
run "git push -u origin main (allowed)" "git push -u origin main" 0
run "git push -o f (option value f, allowed)" "git push -o f origin main" 0
run "git push -ofoo (attached option value, allowed)" "git push -ofoo origin main" 0
run "git push --dry-run --force (push dry run disarms, allowed)" "git push --dry-run --force origin main" 0
run "git push -n -f (short dry run disarms, allowed)" "git push -n -f origin main" 0
run "git push --dry-run --no-dry-run --force (negated dry run, blocked)" "git push --dry-run --no-dry-run --force origin main" 2
run "git push --mi backup (abbreviated mirror, blocked)" "git push --mi backup" 2
run "cd x && git push --force (compound, blocked)" "cd x && git push --force" 2
run "quoted push --force prose (allowed)" 'echo "git push --force is banned"' 0

# --- reset-hard ---------------------------------------------------------------
run "git reset --hard (blocked)" "git reset --hard" 2
run "git reset --h HEAD (abbreviated hard, blocked)" "git reset --h HEAD" 2
run "git reset --ha HEAD (abbreviated hard, blocked)" "git reset --ha HEAD" 2
run "git reset --hard HEAD~1 (blocked)" "git reset --hard HEAD~1" 2
run "git reset --soft HEAD~1 (allowed)" "git reset --soft HEAD~1" 0
run "git reset (mixed, allowed)" "git reset" 0
run "git reset --keep (allowed)" "git reset --keep HEAD~1" 0
run "git reset --pathspec-from paths (abbreviated value skipped, allowed)" "git reset --pathspec-from paths" 0
run "git commit -m 'reset --hard' (message literal, allowed)" "git commit -m 'reset --hard'" 0

# --- clean-force --------------------------------------------------------------
run "git clean -f (blocked)" "git clean -f" 2
run "git clean -fd (blocked)" "git clean -fd" 2
run "git clean -fdx (blocked)" "git clean -fdx" 2
run "git clean -fen (e absorbs n as its value, blocked)" "git clean -fen" 2
run "git clean -fe -n (trailing e absorbs -n, blocked)" "git clean -fe -n" 2
run "git clean -nef (dry-run before e, allowed)" "git clean -nef" 0
run "git clean --force (blocked)" "git clean --force" 2
run "git clean -n (dry run, allowed)" "git clean -n" 0
run "git clean -nd (dry run bundle, allowed)" "git clean -nd" 0 # spellchecker:disable-line
run "git clean -n -fd (dry run disarms force, allowed)" "git clean -n -fd" 0
run "git clean -fdn (dry run in force bundle, allowed)" "git clean -fdn" 0
run "git clean --dry-run -f (long dry run, allowed)" "git clean --dry-run -f" 0
run "git clean -f -e --dry-run (dry-run as exclude value, blocked)" "git clean -f -e --dry-run" 2
run "git clean --f (abbreviated force, blocked)" "git clean --f" 2
run "git clean -f -- --dry-run (dry-run pathspec after --, blocked)" "git clean -f -- --dry-run" 2
run "git clean --dry-run --no-dry-run -f (negated dry run, blocked)" "git clean --dry-run --no-dry-run -f" 2
run "git clean --no-dry-run -n -f (dry run after negation, allowed)" "git clean --no-dry-run -n -f" 0
run "git clean -f --ex --dry-run (abbrev exclude eats dry-run, blocked)" "git clean -f --ex --dry-run" 2

# --- checkout-dot / restore-dot ----------------------------------------------
run "git checkout . (blocked)" "git checkout ." 2
run "git checkout -- . (blocked)" "git checkout -- ." 2
run "git checkout .github/workflows (path-scoped, allowed)" "git checkout .github/workflows" 0
run "git checkout main (branch switch, allowed)" "git checkout main" 0
run "git checkout -b feat/x (new branch, allowed)" "git checkout -b feat/x" 0
run "git restore . (blocked)" "git restore ." 2
run "git restore -- . (blocked)" "git restore -- ." 2
run "git restore --worktree . (blocked)" "git restore --worktree ." 2
run "git restore --staged --worktree . (blocked)" "git restore --staged --worktree ." 2
run "git restore --staged . (index-only, allowed)" "git restore --staged ." 0
run "git restore path/file (path-scoped, allowed)" "git restore path/file" 0
run "git restore --source HEAD~1 file (source value, allowed)" "git restore --source HEAD~1 file" 0
run "git checkout :/ (root-magic pathspec, blocked)" "git checkout :/" 2
run "git restore :/ (root-magic pathspec, blocked)" "git restore :/" 2
run "git restore ':(top)' (top-magic pathspec, blocked)" "git restore ':(top)'" 2
run "git restore ':(literal,top)' (reordered top magic, blocked)" "git restore ':(literal,top)'" 2
run "git restore ':(literal)x' (non-top magic, allowed)" "git restore ':(literal)x'" 0
run "git restore ':(top)src/a' (top magic with subpath, allowed)" "git restore ':(top)src/a'" 0
run "git restore ':(top,glob)**' (glob-all top, blocked)" "git restore ':(top,glob)**'" 2
run "git restore '*' (bare wildcard-all, blocked)" "git restore '*'" 2
run "git restore --staged --w . (abbrev worktree, blocked)" "git restore --staged --w ." 2
run "git checkout -- . (dot after end-of-options, blocked)" "git checkout -- ." 2
run "git checkout -- -f (pathspec named -f, allowed)" "git checkout -- -f" 0
run "git reset -- --hard (pathspec named --hard, allowed)" "git reset -- --hard" 0
run "git checkout --pathspec-from-file=paths (unverifiable pathspec file, blocked)" "git checkout --pathspec-from-file=paths" 2
run "git restore --pathspec-from-file paths (unverifiable pathspec file, blocked)" "git restore --pathspec-from-file paths" 2
run "git checkout --pathspec-from paths (abbreviated pathspec file, blocked)" "git checkout --pathspec-from paths" 2
run "git restore --pathspec-fr paths (shortest unique abbreviation, blocked)" "git restore --pathspec-fr paths" 2
run "git restore --pathspec-from=paths (abbreviated = form, blocked)" "git restore --pathspec-from=paths" 2
run "git checkout --pathspec-file-nul (boolean flag alone, allowed)" "git checkout --pathspec-file-nul" 0
run "git restore ':/*' (root-magic wildcard, blocked)" "git restore ':/*'" 2
run "git restore ':/**' (root-magic recursive wildcard, blocked)" "git restore ':/**'" 2
run "git checkout ':/*' (root-magic wildcard, blocked)" "git checkout ':/*'" 2
run "git restore ':/src' (root magic with subpath, allowed)" "git restore ':/src'" 0
run "git restore ./ (dot-slash worktree discard, blocked)" "git restore ./" 2
run "git restore .. (parent-dir discard, blocked)" "git restore .." 2
run "git checkout -- ./ (dot-slash after end-of-options, blocked)" "git checkout -- ./" 2
run "git restore '?*' (question-mark wildcard-all, blocked)" "git restore '?*'" 2
run "git checkout '?*' (question-mark wildcard-all, blocked)" "git checkout '?*'" 2
run "git restore './*' (dot-slash wildcard-all, blocked)" "git restore './*'" 2
run "git restore ':/?*' (root-magic question wildcard, blocked)" "git restore ':/?*'" 2
run "git restore '*.md' (extension-scoped wildcard, allowed)" "git restore '*.md'" 0
run "git restore ':(exclude)zzz' (exclude-only pathspec, blocked)" "git restore ':(exclude)zzz'" 2
run "git checkout ':!zzz' (exclude-only short magic, blocked)" "git checkout ':!zzz'" 2
run "git restore ':^zzz' (exclude-only caret magic, blocked)" "git restore ':^zzz'" 2
run "git restore ':(exclude)sub' root.txt (positive scopes exclude, allowed)" "git restore ':(exclude)sub' root.txt" 0
run "git checkout main ':!docs' (tree-ish plus exclude-only, blocked)" "git checkout main ':!docs'" 2
run "git checkout HEAD -- ':!docs' (tree-ish, exclude after --, blocked)" "git checkout HEAD -- ':!docs'" 2
run "git checkout main ':!docs' src/ (positive path scopes, allowed)" "git checkout main ':!docs' src/" 0
run "git checkout ':!a' src/ (exclude then positive, allowed)" "git checkout ':!a' src/" 0
run "git restore --conflict merge ':(exclude)docs' (option value not positive, blocked)" "git restore --conflict merge ':(exclude)docs'" 2
run "git restore --c merge ':(exclude)docs' (abbrev conflict value, blocked)" "git restore --c merge ':(exclude)docs'" 2
run "git restore --so HEAD ':(exclude)docs' (abbrev source value, blocked)" "git restore --so HEAD ':(exclude)docs'" 2
run "git restore --so HEAD file (abbrev source, scoped, allowed)" "git restore --so HEAD file" 0
run "git checkout --c merge HEAD ':!docs' (abbrev conflict value, blocked)" "git checkout --c merge HEAD ':!docs'" 2
run "git restore ':' (bare no-pathspec marker, blocked)" "git restore ':'" 2
run "git restore '::' (double-colon marker, blocked)" "git restore '::'" 2
run "git checkout ':(literal)' (empty non-top magic, blocked)" "git checkout ':(literal)'" 2
run "git checkout ':(glob)' (empty glob magic, blocked)" "git checkout ':(glob)'" 2
run "git checkout -f (forced discard, blocked)" "git checkout -f" 2
run "git checkout --force main (forced switch, blocked)" "git checkout --force main" 2
run "git checkout --f main (abbreviated force, blocked)" "git checkout --f main" 2
run "git checkout -bf (attached branch name f, allowed)" "git checkout -bf" 0
run "git switch -f main (forced switch, blocked)" "git switch -f main" 2
run "git switch --discard-changes main (blocked)" "git switch --discard-changes main" 2
run "git switch main (plain switch, allowed)" "git switch main" 0
run "git switch -c feat/x (create, allowed)" "git switch -c feat/x" 0
run "git switch -cfix (attached branch name with f, allowed)" "git switch -cfix" 0
run "git switch -Cfix (attached force-create name, allowed)" "git switch -Cfix" 0
run "git switch -cfix -f (force after attached value, blocked)" "git switch -cfix -f" 2

# --- not blocked by design ----------------------------------------------------
run "git branch -D feat/x (reflog-recoverable, allowed)" "git branch -D feat/x" 0
run "git branch -d feat/x (safe delete, allowed)" "git branch -d feat/x" 0
run "git status (read-only, allowed)" "git status" 0
run "empty command (allowed)" "" 0

# --- argv-faithful regressions ------------------------------------------------
run "git push \"--force\" (quoted flag, blocked)" 'git push "--force"' 2
run "git push --for'ce' (partial-quote flag, blocked)" "git push --for'ce'" 2
run "\"git\" push --force (quoted executable, blocked)" '"git" push --force' 2
run "git \$'--force' push? no — push \$'--force' (ANSI-C flag, blocked)" "git push \$'--force'" 2
run "echo git push --force (git as argument, allowed)" "echo git push --force" 0
run "echo \"a && git reset --hard\" (operator in quotes, allowed)" 'echo "a && git reset --hard"' 0
run "grep 'git clean -f' notes.md (quoted pattern, allowed)" "grep 'git clean -f' notes.md" 0
run "git -C . push --force (arg-consuming global, blocked)" "git -C . push --force" 2
run "env -i git push --force (wrapper, blocked)" "env -i git push --force" 2
run "env -S 'git push --force' (split-string, blocked)" "env -S 'git push --force'" 2
run "env -S quoted flag (inner-quote split-string, blocked)" "env -S 'git push \"--force\"'" 2
run "bash -lc 'git reset --hard' (shell -c wrapper, blocked)" "bash -lc 'git reset --hard'" 2
run "sh -c 'git push --force' (shell -c wrapper, blocked)" "sh -c 'git push --force'" 2
run "bash -c compound (wrapped operator chain, blocked)" "bash -c 'git status && git clean -fd'" 2
run "bash -c 'git status' (wrapped read-only, allowed)" "bash -c 'git status'" 0
run "bash script.sh (script file, not -c, allowed)" "bash script.sh" 0
run "env --unset FOO git push --force (two-word unset, blocked)" "env --unset FOO git push --force" 2
run "bash -O extglob -c 'git reset --hard' (shopt operand, blocked)" "bash -O extglob -c 'git reset --hard'" 2
run "bash --rcfile /dev/null -c 'git reset --hard' (rcfile operand, blocked)" "bash --rcfile /dev/null -c 'git reset --hard'" 2
run "bash --init-file rc -c 'git checkout .' (init-file operand, blocked)" "bash --init-file rc -c 'git checkout .'" 2
run "if true; then git reset --hard; fi (then-body, blocked)" "if true; then git reset --hard; fi" 2
run "while true; do git clean -fd; done (do-body, blocked)" "while true; do git clean -fd; done" 2
run "if false; then :; else git push --force; fi (else-body, blocked)" "if false; then :; else git push --force; fi" 2
run "if git reset --hard; then :; fi (if-condition, blocked)" "if git reset --hard; then :; fi" 2
run "git reset --hard>/tmp/out (attached redirection, blocked)" "git reset --hard>/tmp/out" 2
run "git reset --hard 2>&1 (fd-dup redirection, blocked)" "git reset --hard 2>&1" 2
run "git checkout . >log (redirect after dot, blocked)" "git checkout . >log" 2
run "git clean -f > -n (redirect target not a dry-run flag, blocked)" "git clean -f > -n" 2
run "git push origin main >push.log (redirect target dropped, allowed)" "git push origin main >push.log" 0
run "git restore --staged --worktree --no-worktree . (index-only, allowed)" "git restore --staged --worktree --no-worktree ." 0
run "git restore --staged --no-w . (abbrev no-worktree, allowed)" "git restore --staged --no-w ." 0
run "git restore --no-worktree --worktree . (worktree re-armed, blocked)" "git restore --no-worktree --worktree ." 2
run "git restore --staged --no-staged . (staged cleared, worktree discard, blocked)" "git restore --staged --no-staged ." 2

# --- allow-list ---------------------------------------------------------------
run "allow-list push-force → allowed" "git push --force" 0 \
  HOOK_BLOCK_DANGEROUS_GIT_ALLOW=push-force
run "allow-list push-force,reset-hard → reset allowed" "git reset --hard" 0 \
  HOOK_BLOCK_DANGEROUS_GIT_ALLOW=push-force,reset-hard
run "allow-list push-force only → clean still blocked" "git clean -fd" 2 \
  HOOK_BLOCK_DANGEROUS_GIT_ALLOW=push-force
run "allow-list empty → blocked" "git push --force" 2 \
  HOOK_BLOCK_DANGEROUS_GIT_ALLOW=

# --- kill switch ---------------------------------------------------------------
run "kill switch off → no-op despite push --force" "git push --force" 0 \
  HOOK_BLOCK_DANGEROUS_GIT_ENABLED=false

# --- over-length command fails CLOSED ------------------------------------------
long_cmd="echo $(printf 'a%.0s' {1..20000})"
run "command over the parse cap (fail-closed, blocked)" "$long_cmd" 2
run "allow-list cannot bypass the parse cap (still blocked)" "$long_cmd" 2 \
  HOOK_BLOCK_DANGEROUS_GIT_ALLOW=too-long

# --- telemetry: block emits a `blocked` envelope --------------------------------
TEL="$(mktemp -p "$TEST_TMPDIR")"
SINK="$(make_sink "cat >\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$TEST_TMPDIR" \
  bash "$HOOK" <<<"$(command_json 'git push --force')" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "block-dangerous-git"
  assert_contains "telemetry: status blocked" "$(jq -r '.status' "$TEL")" "blocked"
  assert_contains "telemetry: subject Bash:git" "$(jq -r '.data.subject' "$TEL")" "Bash:git"
  assert_contains "telemetry: form push-force" "$(jq -r '.data.form' "$TEL")" "push-force"
else
  bad "telemetry: no envelope written on block"
fi

report
