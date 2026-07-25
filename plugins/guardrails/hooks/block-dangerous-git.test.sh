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
run "git push --force-with-lease (no expected value, blocked)" "git push --force-with-lease" 2
run "git push --force-with-lease=main (refname only, no expectation, blocked)" "git push --force-with-lease=main origin main" 2
run "git push --force-with-lease=main:abc123 (expectation stated, allowed)" "git push --force-with-lease=main:abc123 origin main" 0
run "git push --force-with-lease=main: (empty expect means ref must not exist, allowed)" "git push --force-with-lease=main: origin main" 0
run "git push --force-with-lease --force-if-includes (mitigated, allowed)" "git push --force-with-lease --force-if-includes" 0
run "git push --force-with-lease=main --force-if-includes (mitigated, allowed)" "git push --force-with-lease=main --force-if-includes origin main" 0
run "git push --force-if-includes alone (no lease, git no-ops it, allowed)" "git push --force-if-includes origin main" 0
run "git push --force-w (unique abbrev of the lease flag, blocked)" "git push --force-w" 2
run "git push --force-w=main:abc (abbrev with expectation, allowed)" "git push --force-w=main:abc origin main" 0
run "git push --force-w --force-i (both abbreviated, mitigated, allowed)" "git push --force-w --force-i" 0
run "git push --force-with-lease --dry-run (preview updates nothing, allowed)" "git push --force-with-lease --dry-run" 0
run "git push --force-with-lease -- --force-if-includes (after --, operand not flag, blocked)" "git push --force-with-lease -- --force-if-includes" 2
run "git push --force-with-lease --force-if-includes --no-force-if-includes (negated mitigation, blocked)" "git push --force-with-lease --force-if-includes --no-force-if-includes origin main" 2
run "git push --force-with-lease --no-force-if-includes --force-if-includes (re-armed mitigation, allowed)" "git push --force-with-lease --no-force-if-includes --force-if-includes origin main" 0
run "git push --force-with-lease --force-i --no-force-i (abbreviated negation, blocked)" "git push --force-with-lease --force-i --no-force-i origin main" 2
run "git push --force-with-lease --force-if-includes --no-force-w (lease negation does not clear the mitigation, allowed)" "git push --force-with-lease --force-if-includes --no-force-w origin main" 0
run "git push --force-with-lease --no-force-with-lease (lease negated, not a lease push, allowed)" "git push --force-with-lease --no-force-with-lease origin main" 0
run "git push --force-with-lease --no-force-with-lease --force-with-lease (lease re-armed, blocked)" "git push --force-with-lease --no-force-with-lease --force-with-lease origin main" 2
run "git push --no-force-with-lease alone (nothing to negate, allowed)" "git push --no-force-with-lease origin main" 0
run "git push --force-with-lease=main:abc --no-force-with-lease (stated expectation negated, allowed)" "git push --force-with-lease=main:abc --no-force-with-lease origin main" 0
run "git push --force-with-lease --force-if-includes --no-dry-run (dry-run negation does not clear the mitigation, allowed)" "git push --force-with-lease --force-if-includes --no-dry-run origin main" 0
run "git push --force-with-lease=main:abc --no-force-if-includes (stated expectation stands without the mitigation, allowed)" "git push --force-with-lease=main:abc --no-force-if-includes origin main" 0
run "git push (plain, allowed)" "git push" 0
run "git push -u origin main (allowed)" "git push -u origin main" 0
run "git push -o f (option value f, allowed)" "git push -o f origin main" 0
run "git push -ofoo (attached option value, allowed)" "git push -ofoo origin main" 0
run "git push --dry-run --force (push dry run disarms, allowed)" "git push --dry-run --force origin main" 0
run "git push -n -f (short dry run disarms, allowed)" "git push -n -f origin main" 0
run "git push --dry-run --no-dry-run --force (negated dry run, blocked)" "git push --dry-run --no-dry-run --force origin main" 2
run "git push --mi backup (abbreviated mirror, blocked)" "git push --mi backup" 2
run "git push --m backup (shortest unique mirror abbrev, blocked)" "git push --m backup" 2
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
run "git switch --di other (shortest discard abbrev, blocked)" "git switch --di other" 2
run "git switch --dis other (discard abbrev, blocked)" "git switch --dis other" 2
run "git switch --detach main (detach, not discard, allowed)" "git switch --detach main" 0
run "git switch --de main (detach abbrev, allowed)" "git switch --de main" 0
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
run "cat <(git reset --hard) (process substitution, blocked)" "cat <(git reset --hard)" 2
run "diff <(git status) <(git reset --hard) (second substitution, blocked)" "diff <(git status) <(git reset --hard)" 2
run "cat <(git status) (safe substitution, allowed)" "cat <(git status)" 0
run "heredoc body with git reset (stdin, not a command, allowed)" $'cat >notes <<EOF\ngit reset --hard\nEOF' 0
run "quoted-delimiter heredoc with git push --force (allowed)" $'cat <<\'EOF\'\ngit push --force\nEOF' 0
run "tab-indented heredoc <<- body (allowed)" $'cat <<-EOF\n\tgit reset --hard\n\tEOF' 0
run "real git reset --hard after a heredoc (blocked)" $'cat <<EOF\nhello\nEOF\ngit reset --hard' 2
run "here-string git reset --hard (not a heredoc, blocked)" $'git reset --hard <<<input' 2
run "git -c alias.rh='reset --hard' rh (inline git alias, blocked)" "git -c alias.rh='reset --hard' rh" 2
run "git -c alias.nuke='!git reset --hard' nuke (inline shell alias, blocked)" "git -c alias.nuke='!git reset --hard' nuke" 2
run "git -c alias.st=status st (safe alias, allowed)" "git -c alias.st=status st" 0
run "git -c alias.rh='reset --hard' status (alias defined, not run, allowed)" "git -c alias.rh='reset --hard' status" 0
# --config-env=<key>=<envvar> holds the alias expansion in an ENVIRONMENT VARIABLE, and
# this guard never reads that value: its origin — an ambient var, an inline/`env` prefix,
# an `export`, `set -a`, or a nested `bash -c` in any wrapper — is the recurring fail-open
# surface. An env-defined alias for the INVOKED subcommand is refused by SHAPE alone.
run "env-defined alias for the invoked sub (blocked by shape)" "git --config-env=alias.rh=AV rh" 2
run "env-defined alias, two-word --config-env form (blocked)" "git --config-env alias.rh=AV rh" 2
run "env-defined alias, benign-looking value STILL blocked (value never read)" "git --config-env=alias.st=AV st" 2 AV=status
run "env-defined alias, case-folded key (blocked)" "git --config-env=alias.RH=AV rh" 2
run "env-defined alias, non-identifier env name (blocked)" "git --config-env=alias.rh=bad-rh rh" 2
run "env-defined alias, leading-dash env name (blocked)" "env -- '-AV=x' git --config-env=alias.rh=-AV rh" 2
run "env value last-wins over an inline decoy for the same key (blocked)" "git -c alias.rh=status --config-env=alias.rh=AV rh" 2
# Inline (-c/--config) aliases still carry the expansion literally and are resolved.
run "inline dangerous alias (blocked)" "git -c alias.rh='reset --hard' rh" 2
run "inline alias, case-folded subcommand (blocked)" "git -c alias.rh='reset --hard' RH" 2
run "inline alias, case-folded key (blocked)" "git -c alias.RH='reset --hard' rh" 2
# git also reads the `alias.<sub>.command` subkey as the alias definition
# (`git -c alias.rh.command='reset --hard' rh` runs it); the guard classifies that
# spelling as an alias too, inline and by --config-env shape.
run "inline dangerous .command-subkey alias (blocked)" "git -c alias.rh.command='reset --hard' rh" 2
run "env-defined .command-subkey alias for the invoked sub (blocked by shape)" "git --config-env=alias.rh.command=AV rh" 2
run ".command-subkey alias, case-folded key (blocked)" "git -c alias.RH.command='reset --hard' rh" 2
# A non-`command` alias subkey is not an alias to git, so it must not be blocked.
run "non-command alias subkey is not an alias (allowed)" "git -c alias.rh.nope='reset --hard' rh" 0
# MAX-DANGER UNION: which spelling git runs when both are set is version-dependent, so a
# benign value in one spelling must never mask a dangerous value in the other — the guard
# blocks if EITHER spelling is dangerous, and allows only when BOTH are benign.
run "dangerous plain masked by a benign .command (blocked by union)" "git -c alias.rh='reset --hard' -c alias.rh.command=status rh" 2
run "dangerous .command masked by a benign plain (blocked by union)" "git -c alias.rh=status -c alias.rh.command='reset --hard' rh" 2
run "dangerous plain, benign .command decoy first (blocked by union)" "git -c alias.rh.command=status -c alias.rh='reset --hard' rh" 2
run "both spellings benign (allowed)" "git -c alias.rh=status -c alias.rh.command=log rh" 0
# Union on the --config-env shape path: an env spelling refuses even when the sibling
# inline spelling is benign (both command-line orders).
run "env plain spelling refuses despite a benign inline .command (blocked)" "git --config-env=alias.rh=AV -c alias.rh.command=status rh" 2
run "env .command spelling refuses despite a benign inline plain (blocked)" "git --config-env=alias.rh.command=AV -c alias.rh=status rh" 2

# The env-defined alias is refused wherever it APPEARS, through any wrapper — no env
# propagation is tracked, so every prior env-carrying bypass (export / set -a / command
# prefix / bash -c / snapshot-global collision) is closed by construction.
run "env-defined alias inside an inline '!' shell alias (blocked)" "git -c \"alias.sh=!git --config-env=alias.rh=AV rh\" sh" 2
# An inline alias whose expansion is itself a `--config-env` alias for the invoked sub
# runs at recursion depth 2, where the SHAPE refusal must still fire (real git runs it:
# reverts the worktree). Verified against ground truth.
run "wrapping inline alias expands to a --config-env alias (depth-2 shape refusal, blocked)" \
  "git -c alias.rh='--config-env=alias.foo=AV foo' rh" 2 "AV=reset --hard"
run "env-defined alias inside an env-prefixed bash -c (blocked)" "AV='reset --hard' bash -c 'git --config-env=alias.rh=AV rh'" 2
run "env-defined alias after export in a shell-alias body (blocked)" "git -c \"alias.sh=!export AV='reset --hard'; git --config-env=alias.rh=AV rh\" sh" 2
run "env-defined alias after 'then export' in a compound command (blocked)" "git -c 'alias.sh=!if true; then export AV=\"reset --hard\"; fi; git --config-env=alias.rh=AV rh' sh" 2
run "env-defined alias after 'export NAME; NAME=val' (blocked)" "git -c 'alias.sh=!export AV; AV=\"reset --hard\"; git --config-env=alias.rh=AV rh' sh" 2
run "env-defined alias after an assignment-prefixed export (blocked)" "git -c 'alias.sh=!AV=\"reset --hard\" export AV; git --config-env=alias.rh=AV rh' sh" 2
run "env-defined alias after 'set -a; NAME=val' allexport (blocked)" "set -a; AV='reset --hard'; git --config-env=alias.rh=AV rh" 2
run "env-defined alias whose env name collides with an internal global (blocked)" "git --config-env=alias.rh=HOOK_ENV_SNAPSHOT_OK rh" 2 "HOOK_ENV_SNAPSHOT_OK=reset --hard"

# ACCEPTANCE — decidable safe WITHOUT reading any value, so still allowed:
run "--config-env setting a NON-alias key (allowed)" "git --config-env=core.pager=PAGERVAR status" 0
run "--config-env alias for a subcommand that is NOT invoked (allowed)" "git --config-env=alias.foo=AV status" 0
run "inline value last-wins over an earlier --config-env for the same key (allowed)" "git --config-env=alias.rh=AV -c alias.rh=status rh" 0
# A `$( )` env name is command-substituted by the shell before git and split by the
# static parser — neither evaluates it, so no exec and nothing dangerous runs (git-fatal).
rm -f "$TEST_TMPDIR/pwned-dg"
run "injection-shaped config-env env name (allowed — never evaluated)" \
  "git --config-env=alias.rh=\$(touch $TEST_TMPDIR/pwned-dg) rh" 0
assert_file_absent "config-env injection: no exec for a shell-metachar env name" "$TEST_TMPDIR/pwned-dg"
run "command -p git reset --hard (command wrapper option, blocked)" "command -p git reset --hard" 2
run "command -- git reset --hard (command end-of-options, blocked)" "command -- git reset --hard" 2
run "exec -c git reset --hard (exec wrapper option, blocked)" "exec -c git reset --hard" 2
run "command git status (wrapper, no dangerous op, allowed)" "command git status" 0
run "command -v git reset --hard (introspection probe, allowed)" "command -v git reset --hard" 0
run "command -V git commit (introspection probe, allowed)" "command -V git commit" 0
run "command -pv git reset --hard (probe bundle with v, allowed)" "command -pv git reset --hard" 0
run "git -c alias.x='!git' x reset --hard (shell alias appends args, blocked)" "git -c alias.x='!git' x reset --hard" 2
run 'git -c alias.pf=push "--force" pf origin main (quoted alias, blocked)' 'git -c alias.pf='"'"'push "--force"'"'"' pf origin main' 2
run "git push --push-op --dry-run --force origin (abbrev push-option eats dry-run, blocked)" "git push --push-op --dry-run --force origin" 2
run "git push --push-option ci --force origin (full push-option value, blocked)" "git push --push-option ci --force origin" 2
run "git push --recurse-submodules=check origin (non-value long option, allowed)" "git push --recurse-submodules=check origin" 0
run "git restore --staged --worktree --no-worktree . (index-only, allowed)" "git restore --staged --worktree --no-worktree ." 0
run "git restore --staged --no-w . (abbrev no-worktree, allowed)" "git restore --staged --no-w ." 0
run "git restore --no-worktree --worktree . (worktree re-armed, blocked)" "git restore --no-worktree --worktree ." 2
run "git restore --staged --no-staged . (staged cleared, worktree discard, blocked)" "git restore --staged --no-staged ." 2

# --- allow-list ---------------------------------------------------------------
run "allow-list push-force → allowed" "git push --force" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=push-force
run "allow-list push-force,reset-hard → reset allowed" "git reset --hard" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=push-force,reset-hard
run "allow-list push-force only → clean still blocked" "git clean -fd" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=push-force
run "allow-list empty → blocked" "git push --force" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=
run "allow-list push-lease-unsafe → bare lease allowed" "git push --force-with-lease" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=push-lease-unsafe
run "allow-list push-force only → bare lease still blocked" "git push --force-with-lease" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=push-force

# --- kill switch ---------------------------------------------------------------
run "kill switch off → no-op despite push --force" "git push --force" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ENABLED=false

# --- over-length command fails CLOSED ------------------------------------------
long_cmd="echo $(printf 'a%.0s' {1..20000})"
run "command over the parse cap (fail-closed, blocked)" "$long_cmd" 2
run "allow-list cannot bypass the parse cap (still blocked)" "$long_cmd" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW=too-long

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

# --- PowerShell tool coverage ------------------------------------------------
# The guard is matched on Bash|PowerShell. PowerShell-simple dangerous ops are
# caught; push-shaped PowerShell the guard cannot parse fails closed.
run_pwsh() {
  local label="$1" command="$2" expected="$3" rc
  bash "$HOOK" <<<"$(pwsh_command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}
run_pwsh "PS: git push --force (blocked)" "git push --force" 2
run_pwsh "PS: git reset --hard (blocked)" "git reset --hard" 2
run_pwsh "PS: git push --force-with-lease (no expected value, blocked)" "git push --force-with-lease" 2
run_pwsh "PS: git push --force-with-lease=main:abc (expectation stated, allowed)" "git push --force-with-lease=main:abc" 0
run_pwsh "PS: git push (plain, allowed)" "git push origin main" 0
run_pwsh "PS: git status (allowed)" "git status" 0
run_pwsh "PS: backtick-continued force push (fail-closed block)" \
  "$(printf 'git push `\n --force')" 2

# This guard owns destructive non-commit forms (reset/clean/checkout/restore), so
# unlike the commit/push guards it cannot defer an unparsable NON-commit/push git
# command — it must fail closed on ANY git-shaped PowerShell it cannot parse.
run_pwsh "PS: git --% reset --hard (stop-parsing token, fail-closed block)" \
  "git --% reset --hard" 2
run_pwsh "PS: git --% clean -fd (stop-parsing token, fail-closed block)" \
  "git --% clean -fd" 2
run_pwsh "PS: backtick-continued git reset --hard (fail-closed block)" \
  "$(printf 'git `\n reset --hard')" 2
# Single-quoted `$(...)` is deliberately literal PowerShell subexpression text
# (the construct under test), not a Bash expansion.
# shellcheck disable=SC2016
run_pwsh "PS: git checkout via subexpression (fail-closed block)" \
  'git checkout $(Get-Branch)' 2
# Negative control: a non-git unparsable PowerShell command is not this guard's
# concern — no over-block past git.
# shellcheck disable=SC2016
run_pwsh "PS: non-git unparsable command (allowed — not git-shaped)" \
  'Remove-Item $(Get-Foo)' 0

# Launcher-spelling parity (review round 4): the .exe-suffixed spellings of the
# covered launchers and the `start` alias of Start-Process are the same
# see-through surface — a spelling gap, not a new launcher class.
run_pwsh "PS: cmd.exe /c git reset --hard (fail-closed block)" \
  "cmd.exe /c git reset --hard" 2
run_pwsh "PS: powershell.exe -Command git reset --hard (fail-closed block)" \
  "powershell.exe -Command 'git reset --hard'" 2
run_pwsh "PS: start alias launches git (fail-closed block)" \
  "start git -ArgumentList 'reset --hard'" 2
run_pwsh "PS: start alias, no git (allowed)" "start notepad" 0
# A launcher whose program is a computed expression cannot be proven git-free.
run_pwsh "PS: Start-Process computed target (fail-closed block)" \
  "Start-Process ('g'+'it') -ArgumentList 'reset --hard'" 2
run_pwsh "PS: Start-Process -FilePath computed target (fail-closed block)" \
  "Start-Process -FilePath ('g'+'it') -ArgumentList 'reset --hard'" 2
# shellcheck disable=SC2016
run_pwsh "PS: launcher with variable target (fail-closed block)" \
  'saps $tool -ArgumentList "reset --hard"' 2

# Review round 6: quoted-string '@' is not a here-string opener; backslash
# path-qualified git normalizes for the tokenizer; separator-adjacent call
# operators are git-capable.
run_pwsh "PS: quoted '@' does not open a here-string (git line not swallowed)" \
  "$(printf "Write-Output '@'\ngit reset --hard\n'@'")" 2
run_pwsh "PS: backslash path-qualified git.exe (blocked)" \
  'C:\Git\cmd\git.exe reset --hard' 2
run_pwsh "PS: relative .\\git.exe (blocked)" \
  '.\git.exe reset --hard' 2
run_pwsh "PS: backslash path-qualified git.exe, safe op (allowed)" \
  'C:\Git\cmd\git.exe status' 0
run_pwsh "PS: semicolon-adjacent computed call (fail-closed block)" \
  "Write-Host ok;& ('g'+'it') reset --hard" 2

report
