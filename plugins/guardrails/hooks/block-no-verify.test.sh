#!/usr/bin/env bash
# Contract test for block-no-verify.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash JSON on
# stdin, asserts on exit code (2 = blocked, 0 = allowed). Self-contained — no
# host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-no-verify.sh"
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

# --- Form 1: --no-verify / -n on git commit ---------------------------------
run "git commit --no-verify (blocked)" "git commit --no-verify -m test" 2
run "git commit -n (blocked)" "git commit -n -m test" 2
run "cd foo && git commit --no-verify (compound, blocked)" "cd foo && git commit --no-verify -m test" 2
run "git commit -m test (allowed)" "git commit -m test" 0
run "git push --no-verify (blocked)" "git push --no-verify" 2
run "quoted --no-verify prose (allowed)" 'echo "git commit --no-verify is banned"' 0
run "echo git commit --no-verify (git as arg, allowed)" 'echo git commit --no-verify' 0

# --- Form 1b: core.hooksPath assignment -------------------------------------
run "git -c core.hooksPath=/dev/null commit (blocked)" "git -c core.hooksPath=/dev/null commit -m test" 2
run "git -c core.hookspath=/dev/null push (blocked)" "git -c core.hookspath=/dev/null push" 2
run "git commit -m core.hooksPath=/tmp (message literal, allowed)" \
  "git commit -m 'core.hooksPath=/tmp'" 0
run "cd foo && git -c core.hooksPath commit (compound, blocked)" "cd foo && git -c core.hooksPath=/dev/null commit -m test" 2
run "quoted core.hooksPath prose (allowed)" 'echo "git -c core.hooksPath=/dev/null commit"' 0

# --- Argv-faithful gate regressions (P3) ------------------------------------
# The shell removes quotes/escapes before git parses argv, so quoting the git
# executable, the subcommand, OR the flag must all still be caught.
run "git commit \"--no-verify\" (quoted flag, blocked)" \
  'git commit "--no-verify" -m test' 2
run "git commit --no-ver'ify' (partial-quote flag, blocked)" \
  "git commit --no-ver'ify' -m test" 2
run "git commit \"-n\" (quoted short flag, blocked)" \
  'git commit "-n" -m test' 2
run "git commit --no-\\verify (escaped flag, blocked)" \
  'git commit --no-\verify -m test' 2
run "\"git\" commit --no-verify (quoted executable, blocked)" \
  '"git" commit --no-verify -m test' 2
run "git \"commit\" --no-verify (quoted subcommand, blocked)" \
  'git "commit" --no-verify -m test' 2
run "g'i't commit --no-verify (split-quoted executable, blocked)" \
  "g'i't commit --no-verify -m test" 2
run "git -c \"core.hooksPath=…\" commit (quoted config, blocked)" \
  'git -c "core.hooksPath=/dev/null" commit -m test' 2
run "\"git\" -c core.hooksPath=… commit (quoted exec + config, blocked)" \
  '"git" -c core.hooksPath=/dev/null commit -m test' 2
run "git -c 'core.hooksPath=…' push (single-quoted config, blocked)" \
  "git -c 'core.hooksPath=/dev/null' push" 2

# --- Argv-faithful negatives — must NOT block (exit 0) ----------------------
run "echo \"git commit --no-verify\" (quoted arg, allowed)" \
  'echo "git commit --no-verify"' 0
run "echo 'use git commit --no-verify never' (quoted arg, allowed)" \
  "echo 'use git commit --no-verify never'" 0
run "echo \"a && git commit --no-verify\" (operator in quotes, allowed)" \
  'echo "a && git commit --no-verify"' 0
run "\"git commit\" --no-verify (command-not-found form, allowed)" \
  '"git commit" --no-verify -m test' 0
run "git commit -m \"explain --no-verify\" (flag in message value, allowed)" \
  'git commit -m "explain --no-verify"' 0

# --- [P2] git global options that consume an argument -----------------------
run "git -C . commit --no-verify (arg-consuming -C, blocked)" \
  'git -C . commit --no-verify -m test' 2
run "git --git-dir=/x commit --no-verify (=-form global, blocked)" \
  'git --git-dir=/x commit --no-verify -m test' 2
run "git --work-tree /tmp commit --no-verify (two-word global, blocked)" \
  'git --work-tree /tmp commit --no-verify -m test' 2
run "git -C . -c core.hooksPath=/dev/null push (blocked)" \
  'git -C . -c core.hooksPath=/dev/null push' 2

# --- [P2] short-option bundle -n --------------------------------------------
run "git commit -nm msg (n before arg-taking m, blocked)" \
  'git commit -nm msg' 2
run "git commit -vn (n after non-arg short, blocked)" \
  'git commit -vn -m test' 2
run "git commit -mn (m takes value 'n', allowed)" \
  'git commit -mn' 0
run "git commit -am fix (no n-flag, allowed)" \
  'git commit -am fix' 0

# --- [P2] wrappers (with options) transparently pass through ----------------
run "env -i git commit --no-verify (env + option, blocked)" \
  'env -i git commit --no-verify -m test' 2
run "nice git commit --no-verify (blocked)" \
  'nice git commit --no-verify -m test' 2
run "timeout 5 git commit --no-verify (positional-arg wrapper, blocked)" \
  'timeout 5 git commit --no-verify -m test' 2
run "timeout -s KILL 5 git commit --no-verify (option + duration, blocked)" \
  'timeout -s KILL 5 git commit --no-verify -m test' 2
run "command git commit --no-verify (builtin prefix, blocked)" \
  'command git commit --no-verify -m test' 2
run "if git commit --no-verify (shell keyword prefix, blocked)" \
  'if git commit --no-verify -m test; then echo ok; fi' 2
run "sudo -u x git commit --no-verify (wrapper option, blocked)" \
  'sudo -u x git commit --no-verify -m test' 2
run "nice -n 10 git commit --no-verify (nice -n option, blocked)" \
  'nice -n 10 git commit --no-verify -m test' 2
run "time -p git commit --no-verify (time -p option, blocked)" \
  'time -p git commit --no-verify -m test' 2
run "git commit -m --no-verify (message value, allowed)" \
  'git commit -m --no-verify' 0
run "git commit -m 'LEFTHOOK=0' (message literal, allowed)" \
  "git commit -m 'LEFTHOOK=0'" 0
run "env -S 'git commit --no-verify' (split-string operand, blocked)" \
  "env -S 'git commit --no-verify -m test'" 2
run "env -S'git commit --no-verify' (attached split-string, blocked)" \
  "env -S'git commit --no-verify -m test'" 2
run "env --split-string='git commit --no-verify' (long form, blocked)" \
  "env --split-string='git commit --no-verify -m test'" 2
run "eval git commit --no-verify (eval prefix, blocked)" \
  'eval git commit --no-verify -m test' 2
run "env -S 'ls -la' (split-string non-git, allowed)" \
  "env -S 'ls -la'" 0

# --- [P3] case-insensitive executable + .exe strip (OS-gated) ----------------
case "${OSTYPE:-}" in
msys* | cygwin* | win32) exp_win=2 ;; # Windows/MSYS folds case + strips .exe
*) exp_win=0 ;;                       # POSIX stays case-sensitive
esac
run "GIT commit --no-verify (uppercase exec, OS-gated)" \
  'GIT commit --no-verify -m test' "$exp_win"
run "git.exe commit --no-verify (.exe strip, OS-gated)" \
  'git.exe commit --no-verify -m test' "$exp_win"

# --- [P5 subset] ANSI-C $'…' + backslash-newline continuation ---------------
run "git commit \$'--no-verify' (ANSI-C plain, blocked)" \
  "git commit \$'--no-verify' -m test" 2
run "git commit \$'\\x2d\\x2dno-verify' (ANSI-C hex, blocked)" \
  "git commit \$'\\x2d\\x2dno-verify' -m test" 2
lc_cmd=$(printf 'git commit --no-\\\nverify -m test')
run "git commit --no-<backslash-newline>verify (continuation, blocked)" \
  "$lc_cmd" 2

# --- [P4] over-length command fails CLOSED (blocked) ------------------------
long_cmd="echo $(printf 'a%.0s' {1..20000})"
run "command over the parse cap (fail-closed, blocked)" \
  "$long_cmd" 2

# --- Form 2: hook-manager env-var bypass on git commit / push ---------------
run "LEFTHOOK=0 git commit (blocked)" "LEFTHOOK=0 git commit -m test" 2
run "LEFTHOOK=false git push (blocked)" "LEFTHOOK=false git push" 2
run "LEFTHOOK=FALSE git commit (blocked, uppercase)" "LEFTHOOK=FALSE git commit -m test" 2
run "LEFTHOOK=False git push (blocked, mixed case)" "LEFTHOOK=False git push origin main" 2
run "LEFTHOOK_SUFFIX=false git push (blocked, suffix var)" "LEFTHOOK_VERIFY_GATE_ENABLED=false git push" 2
run "cd foo && LEFTHOOK=0 git commit (compound, blocked)" "cd foo && LEFTHOOK=0 git commit -m test" 2

# --- Form 2 negatives — env-var alone or with non-git command must NOT block -
run "LEFTHOOK=0 echo foo (not git, allowed)" "LEFTHOOK=0 echo foo" 0

# Default manager set covers more than lefthook.
run "HUSKY=0 git commit (default set, blocked)" "HUSKY=0 git commit -m test" 2
run "HUSKY=false git push (default set, blocked)" "HUSKY=false git push" 2
run "PRE_COMMIT=0 git commit (default set, blocked)" "PRE_COMMIT=0 git commit -m test" 2
run "SIMPLE_GIT_HOOKS=false git commit (default set, blocked)" "SIMPLE_GIT_HOOKS=false git commit -m test" 2
run "UNKNOWNMGR=0 git commit (not in set, allowed)" "UNKNOWNMGR=0 git commit -m test" 0

# --- Form 2b: the hook-manager prefix set is configurable -------------------
run "custom prefix blocks its manager" "MYHOOKS=0 git commit -m test" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_HOOK_MANAGER_PREFIXES="myhooks"
run "custom set replaces the default (lefthook now allowed)" "LEFTHOOK=0 git commit -m test" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_HOOK_MANAGER_PREFIXES="myhooks"
run "regex metachars in a prefix value are sanitized, not injected" "MYHOOKS=0 git commit -m test" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_HOOK_MANAGER_PREFIXES="my.*hooks,myhooks"
run "LEFTHOOK=false ls (not git, allowed)" "LEFTHOOK=false ls" 0
run "LEFTHOOK=1 git commit (truthy value, allowed)" "LEFTHOOK=1 git commit -m test" 0
run "LEFTHOOK=true git push (truthy value, allowed)" "LEFTHOOK=true git push" 0

# --- Unrelated commands — always no-op --------------------------------------
run "git status (read-only, allowed)" "git status" 0
run "empty command (allowed)" "" 0
run "git push (no env-var, allowed)" "git push" 0

# --- Kill switch — disabled path is a clean no-op even on a bypass -----------
run "kill switch off → no-op despite --no-verify" "git commit --no-verify -m test" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_ENABLED=false

# --- Telemetry: block emits a `blocked` envelope ----------------------------
TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK="$(make_sink "cat >\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$TEST_TMPDIR" \
  bash "$HOOK" <<<"$(command_json 'git commit --no-verify -m test')" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "block-no-verify"
  assert_contains "telemetry: status blocked" "$(jq -r '.status' "$TEL")" "blocked"
  assert_contains "telemetry: subject Bash:git" "$(jq -r '.data.subject' "$TEL")" "Bash:git"
  assert_contains "telemetry: form no-verify" "$(jq -r '.data.form' "$TEL")" "no-verify"
else
  bad "telemetry: no envelope written on block"
fi

# --- PowerShell tool coverage ------------------------------------------------
# The guard is matched on Bash|PowerShell. The proven bypass must be caught on
# the PowerShell tool; the canonical PowerShell commit form must be allowed; and
# commit/push-shaped PowerShell the guard cannot parse must fail closed.
run_pwsh() {
  local label="$1" command="$2" expected="$3" rc
  bash "$HOOK" <<<"$(pwsh_command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}
run_pwsh "PS: git commit --no-verify (blocked — the proven bypass)" "git commit --no-verify -m x" 2
run_pwsh "PS: git commit -n (blocked)" "git commit -n -m x" 2
run_pwsh "PS: git push --no-verify (blocked)" "git push --no-verify" 2
run_pwsh "PS: canonical here-string | git commit -F - (allowed)" \
  "$(printf '%s\n%s\n%s' "@'" "fix: x" "'@ | git commit -F -")" 0
run_pwsh "PS: git commit -m here-string (allowed here — noncanonical's concern, no bypass)" \
  "$(printf '%s\n%s\n%s' "git commit -m @'" "msg" "'@")" 0
run_pwsh "PS: git status (allowed)" "git status" 0
run_pwsh "PS: backtick-continued commit (fail-closed block)" \
  "$(printf 'git commit `\n --no-verify')" 2
run_pwsh "PS: unbalanced here-string hiding --no-verify (fail-closed block)" \
  "$(printf '%s\n%s\n%s' "@'" "body" "'X | git commit --no-verify")" 2
run_pwsh "PS: brace-grouped commit --no-verify (fail-closed block)" \
  "& { git commit --no-verify }" 2
run_pwsh "PS: LEFTHOOK=0 git commit (env bypass, blocked)" "LEFTHOOK=0 git commit -m x" 2

# Obfuscation regressions (independent security review, sink-level fail-closed).
# A construct that defeats the Bash tokenizer must not let an obfuscated git
# invocation through — the sink blocks unless the command is provably git-free,
# rather than trusting a negative shape match on the mangled scan.
bt='`'
run_pwsh "PS: backtick inside subcommand (git com\`mit, blocked)" "git com${bt}mit --no-verify" 2
run_pwsh "PS: backtick inside push (git pu\`sh --force, blocked)" "git pu${bt}sh --force" 2
run_pwsh "PS: backtick inside git itself (g\`it com\`mit, blocked)" "g${bt}it com${bt}mit --no-verify" 2
run_pwsh "PS: quoted subcommand + subexpression decoy (blocked)" "git 'commit' --no-verify \$(whoami)" 2
run_pwsh "PS: quoted git command word (blocked via parser)" "& 'git' commit --no-verify" 2
# Provably git-free PowerShell carrying an unparsable construct is NOT blocked
# by the git guards (no over-block of legitimate non-git PowerShell).
run_pwsh "PS: non-git scriptblock (allowed)" "Get-Process | Where-Object { \$_.CPU -gt 5 }" 0
run_pwsh "PS: read-only git with scriptblock (allowed — #1415)" \
  "git fetch origin 2>&1 | ForEach-Object { \$_ | Select-Object -Last 5 }" 0
run_pwsh "PS: non-git subexpression (allowed)" "Write-Output \$(Get-Date)" 0

# --- ps::git_command_is_readonly — the `readonly-ok` sink scope (SECURITY) -----
# This guard is the ONLY caller that passes `readonly-ok`, so it is the only place
# a wrongly-classified subcommand is observable. Every case below carries a SINK
# TRIGGER (`& { … }`, a `{}` pipeline, or `()` grouping): without one the command
# takes the Bash-parser path and never reaches ps::git_command_is_readonly at all,
# which would make the assertion vacuous.
#
# The classifier is a blocklist, so a subcommand it omits classifies as READ-ONLY
# and the whole guard skips. `git clean -fdx` and `git restore .` destroy
# uncommitted work irrecoverably and were both omitted — hence one case per
# mutating subcommand, so an accidental deletion from the alternation fails here.
run_pwsh "PS: git clean -fdx in scriptblock (destructive, blocked)" "& { git clean -fdx }" 2
run_pwsh "PS: git clean -fdx in a pipeline (destructive, blocked)" \
  "git clean -fdx | ForEach-Object { \$_ }" 2
run_pwsh "PS: git restore . in scriptblock (destructive, blocked)" "& { git restore . }" 2
run_pwsh "PS: git restore . in grouping (destructive, blocked)" "(git restore .)" 2
run_pwsh "PS: git add (index write, blocked)" "& { git add -A }" 2
run_pwsh "PS: git apply (working-tree write, blocked)" "& { git apply fix.diff }" 2
run_pwsh "PS: git bisect (moves HEAD, blocked)" "& { git bisect start }" 2
run_pwsh "PS: git branch -D (ref delete, blocked)" "& { git branch -D feature }" 2
run_pwsh "PS: git checkout-index -f (worktree overwrite, blocked)" "& { git checkout-index -a -f }" 2
run_pwsh "PS: git config --unset (config write, blocked)" "& { git config --unset core.hookspath }" 2
run_pwsh "PS: git filter-branch (history rewrite, blocked)" "& { git filter-branch --all }" 2
run_pwsh "PS: git gc --prune=now (object destruction, blocked)" "& { git gc --prune=now }" 2
run_pwsh "PS: git maintenance run (gc under another name, blocked)" \
  "& { git maintenance run --task=incremental-repack }" 2
run_pwsh "PS: git merge-file (overwrites operand, blocked)" "& { git merge-file a.txt base.txt b.txt }" 2
run_pwsh "PS: git mv (worktree+index move, blocked)" "& { git mv old.txt new.txt }" 2
run_pwsh "PS: git prune (object destruction, blocked)" "& { git prune --expire=now }" 2
run_pwsh "PS: git pull (merges into the worktree, blocked)" "& { git pull --rebase }" 2
run_pwsh "PS: git read-tree -u (index+worktree write, blocked)" "& { git read-tree -m -u HEAD }" 2
run_pwsh "PS: git reflog expire (destroys the recovery path, blocked)" \
  "& { git reflog expire --expire=now --all }" 2
run_pwsh "PS: git remote remove (remote config write, blocked)" "& { git remote remove origin }" 2
run_pwsh "PS: git repack -a -d (drops packs, blocked)" "& { git repack -a -d }" 2
run_pwsh "PS: git replace (rewrites object reads, blocked)" "& { git replace --delete abc1234 }" 2
run_pwsh "PS: git rerere forget (resolution-cache write, blocked)" "& { git rerere forget src/a.txt }" 2
run_pwsh "PS: git rm -f (tracked-file delete, blocked)" "& { git rm -f secrets.txt }" 2
run_pwsh "PS: git sparse-checkout set (removes worktree files, blocked)" \
  "& { git sparse-checkout set docs }" 2
run_pwsh "PS: git submodule deinit -f (discards submodule work, blocked)" \
  "& { git submodule deinit -f . }" 2
run_pwsh "PS: git subtree split (merges and commits, blocked)" "& { git subtree split --prefix=lib }" 2
run_pwsh "PS: git switch -f (checkout's replacement, blocked)" "& { git switch -f main }" 2
run_pwsh "PS: git symbolic-ref (repoints HEAD, blocked)" \
  "& { git symbolic-ref HEAD refs/heads/other }" 2
run_pwsh "PS: git update-index (index write, blocked)" "& { git update-index --force-remove a.txt }" 2
run_pwsh "PS: git update-ref -d (ref delete, blocked)" "& { git update-ref -d refs/heads/main }" 2

# Hyphenated siblings that the `-`-excluding boundary keeps from riding on an
# already-listed token, so each needs its own entry and its own case: `commit-graph`
# is not `commit`, `merge-index`/`merge-one-file` are not `merge`, `fast-import` is
# not `import`, `update-server-info` is not `update-ref`.
run_pwsh "PS: git commit-graph write (admin-state write, not 'commit', blocked)" \
  "& { git commit-graph write --reachable }" 2
run_pwsh "PS: git fast-import (bulk ref force-update, blocked)" "& { git fast-import --force }" 2
run_pwsh "PS: git merge-index (worktree write, not 'merge', blocked)" \
  "& { git merge-index myprog -a }" 2
run_pwsh "PS: git merge-one-file (worktree write, not 'merge', blocked)" \
  "& { git merge-one-file }" 2
run_pwsh "PS: git mergetool (writes resolved files, blocked)" "& { git mergetool --tool=vimdiff }" 2
run_pwsh "PS: git multi-pack-index (object-store admin write, blocked)" \
  "& { git multi-pack-index write }" 2
run_pwsh "PS: git update-server-info (admin-state write, blocked)" \
  "& { git update-server-info -f }" 2
# Foreign-SCM bridges: dual-mode, and the mutating mode rewrites history and publishes.
run_pwsh "PS: git svn dcommit (rewrites history + publishes, blocked)" "& { git svn dcommit }" 2
run_pwsh "PS: git p4 submit (publishes to Perforce, blocked)" "& { git p4 submit }" 2
run_pwsh "PS: git cvsexportcommit (publishes to CVS, blocked)" "& { git cvsexportcommit -c HEAD }" 2

# SYNONYMS AND PLUMBING BENEATH A LISTED PORCELAIN. Listing the porcelain alone
# leaves the identical mutation reachable under another spelling — and `send-pack`
# is the sharpest case for THIS guard: it is what `push` calls, and it does NOT
# run the pre-push hook, so omitting it left a hook bypass wide open.
run_pwsh "PS: git stage (documented synonym of add, blocked)" "& { git stage -A }" 2
run_pwsh "PS: git send-pack (push plumbing, skips pre-push hook, blocked)" \
  "& { git send-pack origin +refs/heads/main:refs/heads/main --force }" 2
run_pwsh "PS: git http-push (publishes over DAV, blocked)" \
  "& { git http-push https://example.invalid/r main }" 2
run_pwsh "PS: git receive-pack (updates refs in the receiving repo, blocked)" \
  "& { git receive-pack . }" 2
run_pwsh "PS: git quiltimport (creates commits from a patch series, blocked)" \
  "& { git quiltimport }" 2
run_pwsh "PS: git prune-packed (object-store admin write, not 'prune', blocked)" \
  "& { git prune-packed }" 2
run_pwsh "PS: git credential (credential-store write, blocked)" "& { git credential reject }" 2
run_pwsh "PS: git interpret-trailers --in-place (rewrites the file, blocked)" \
  "& { git interpret-trailers --in-place msg.txt }" 2
# Widely-installed third-party subcommands invoked through the git dispatcher.
run_pwsh "PS: git filter-repo (history rewrite, blocked)" "& { git filter-repo --force }" 2
run_pwsh "PS: git lfs prune (destroys local LFS objects, blocked)" "& { git lfs prune }" 2
run_pwsh "PS: git annex drop (destroys file content, blocked)" "& { git annex drop f.bin }" 2

# The #1415 read-only allowance must SURVIVE the widening — over-blocking routine
# read-only work is the friction class this narrowing exists to prevent. The
# hyphen cases are the load-bearing ones: the boundary class excludes `-`, so a
# hyphenated sibling or option must never match a listed token.
run_pwsh "PS: git log in scriptblock (read-only, allowed)" "& { git log --oneline -5 }" 0
run_pwsh "PS: git status in scriptblock (read-only, allowed)" "& { git status --porcelain }" 0
run_pwsh "PS: git rev-list in scriptblock (read-only, allowed)" "& { git rev-list --count HEAD }" 0
run_pwsh "PS: git merge-base (hyphen sibling of merge, allowed)" \
  "& { git merge-base --is-ancestor HEAD origin/main }" 0
run_pwsh "PS: git fetch --prune (hyphen option, not the prune subcommand, allowed)" \
  "& { git fetch --prune }" 0
run_pwsh "PS: git ls-remote (hyphen sibling of remote, allowed)" \
  "& { git ls-remote --heads origin }" 0
run_pwsh "PS: git log --no-merges (hyphen option, allowed)" "& { git log --no-merges }" 0
run_pwsh "PS: git describe --tags (hyphen option, allowed)" "& { git describe --tags }" 0
run_pwsh "PS: git diff in scriptblock (read-only, allowed)" "& { git diff --stat }" 0
run_pwsh "PS: git show in scriptblock (read-only, allowed)" "& { git show HEAD }" 0
run_pwsh "PS: git blame in scriptblock (read-only, allowed)" "& { git blame README.md }" 0
run_pwsh "PS: git rev-parse in scriptblock (read-only, allowed)" \
  "& { git rev-parse --show-toplevel }" 0
run_pwsh "PS: git archive (artifact producer, allowed)" "& { git archive --format=tar HEAD }" 0
run_pwsh "PS: git format-patch (artifact producer, allowed)" "& { git format-patch -1 }" 0
run_pwsh "PS: git clone (cannot destroy existing work, allowed)" \
  "& { git clone https://example.invalid/x }" 0
run_pwsh "PS: git fsck (interrogator, allowed)" "& { git fsck }" 0
run_pwsh "PS: git cat-file (interrogator, allowed)" "& { git cat-file -p HEAD }" 0
run_pwsh "PS: git write-tree (create-only plumbing, allowed)" "& { git write-tree }" 0
run_pwsh "PS: git pack-refs (lossless representation rewrite, allowed)" "& { git pack-refs --all }" 0
run_pwsh "PS: git commit-tree (create-only plumbing, not 'commit-graph', allowed)" \
  "& { git commit-tree -p HEAD -m x abc1234 }" 0
run_pwsh "PS: git bundle create (artifact producer, allowed)" \
  "& { git bundle create out.bundle HEAD }" 0
run_pwsh "PS: git ls-tree (interrogator, allowed)" "& { git ls-tree -r HEAD }" 0
run_pwsh "PS: git shortlog (interrogator, allowed)" "& { git shortlog -sn }" 0
# `--staged` must NOT match the newly-listed `stage`: the trailing `d` is
# alphanumeric, so the token boundary refuses to close. Without this the `stage`
# addition would silently over-block one of the most common read-only diffs.
run_pwsh "PS: git diff --staged ('staged' is not 'stage', allowed)" "& { git diff --staged }" 0
run_pwsh "PS: git fast-export (exports, does not mutate, allowed)" "& { git fast-export --all }" 0
run_pwsh "PS: git merge-tree (create-only plumbing, allowed)" \
  "& { git merge-tree --write-tree main HEAD }" 0
run_pwsh "PS: git count-objects (interrogator, allowed)" "& { git count-objects -v }" 0
run_pwsh "PS: git for-each-ref (interrogator, allowed)" "& { git for-each-ref refs/heads }" 0
# Dynamic-invocation regressions: iex / string-literal call run an opaque string,
# so a construct-free form must still route to the fail-closed sink (it otherwise
# reached the Bash parser, which sees `iex`, not git, and passed).
run_pwsh "PS: iex of a literal git command (blocked)" "iex 'git commit --no-verify'" 2
run_pwsh "PS: invoke-expression of a literal (blocked)" "invoke-expression 'git push --force'" 2
run_pwsh "PS: iex of a here-string (blocked)" \
  "$(printf 'iex @%s\ngit commit --no-verify\n%s@' "'" "'")" 2
run_pwsh "PS: call of a string-literal command (blocked)" "& 'git commit --no-verify'" 2
# A call/dot-source of a bare VARIABLE is the deferred variable-command-word form
# (same residual the Bash guards carry) — it takes the parser path, not the sink.
run_pwsh "PS: call of a bare variable (deferred residual — not blocked here)" "& \$sb" 0
# Launcher / nested-shell parity with the Bash guard's launcher + `-c` see-through.
# Routed to the sink; blocked only when the launched argv / command names git.
run_pwsh "PS: Start-Process git -ArgumentList (blocked)" "Start-Process git -ArgumentList 'commit','--no-verify'" 2
run_pwsh "PS: saps git (Start-Process alias, blocked)" "saps git -ArgumentList 'push','--force'" 2
run_pwsh "PS: pwsh -Command git (nested shell, blocked)" "pwsh -Command 'git commit --no-verify'" 2
run_pwsh "PS: powershell -Command git (blocked)" "powershell -Command 'git push --force'" 2
run_pwsh "PS: cmd /c git (blocked)" "cmd /c git commit --no-verify" 2
run_pwsh "PS: Start-Process notepad (no git, allowed)" "Start-Process notepad" 0
run_pwsh "PS: pwsh -File script (no inline git, allowed)" "pwsh -File build.ps1" 0

# `ps::might_invoke_git` is SHARED with block-dangerous-git, so the constant
# call-target false positive (#1968) false-blocked the same command twice — once
# per guard. Covered on both sides so a regression in the shared predicate cannot
# be caught by only one suite.
run_pwsh "PS: call-op, double-quoted literal script path (allowed)" \
  '& "C:\tools\publish.ps1"' 0
run_pwsh "PS: dot-source, single-quoted literal script path (allowed)" \
  ". 'C:\\tools\\lib.ps1'" 0
# shellcheck disable=SC2016
run_pwsh "PS: call-op, interpolated variable target (fail-closed block)" \
  '& "$tool" commit --no-verify' 2

# --- Sink remediation TEXT --------------------------------------------------
# run_pwsh discards stderr, so nothing asserted what the trigger lines actually
# SAY — and a remediation line that describes a shape it never sees is as much a
# dead end as no line at all. Both message defects fixed here (#1974 review) were
# exactly that, and both survived because only the exit code was checked.
pwsh_stderr() {
  bash "$HOOK" <<<"$(pwsh_command_json "$1")" 2>&1 >/dev/null
}

# PowerShell pairs each opener with its own quote, so the terminator named has to
# follow the opener rather than always being `'@`.
assert_contains "PS msg: @' opener names the '@ terminator" \
  "$(pwsh_stderr "$(printf '%s\n%s\n%s' "@'" "body" "'X | git commit --no-verify")")" \
  "the '@ terminator must start at column 0"
assert_contains "PS msg: @\" opener names the \"@ terminator" \
  "$(pwsh_stderr "$(printf '%s\n%s\n%s' '@"' "body" '"X | git commit --no-verify')")" \
  "the \"@ terminator must start at column 0"

# A literal call target is blocked by the invocation FORM, so the advice must be
# to drop the operator — not to "invoke the target by its literal name", which is
# the form the operator already used.
assert_contains "PS msg: literal call target is told to drop the operator" \
  "$(pwsh_stderr "& 'git' commit --no-verify")" \
  "Drop the iex/'&'/'.'"
assert_absent "PS msg: literal call target is not told to use a literal name" \
  "$(pwsh_stderr "& 'git' commit --no-verify")" \
  "Invoke the target by its literal name"
assert_contains "PS msg: iex of a literal gets the same actionable advice" \
  "$(pwsh_stderr "iex 'git commit --no-verify'")" \
  "Drop the iex/'&'/'.'"

# --- #2662: headlines must not assert a git command is present -----------------
# shellcheck disable=SC2016
iex_nov_out="$(pwsh_stderr 'Invoke-Expression $cmd')"
assert_contains "PS msg #2662: iex headline is shell-agnostic (no git-present claim)" \
  "$iex_nov_out" "this PowerShell command cannot be parsed with confidence"
assert_absent "PS msg #2662: iex headline does not say 'PowerShell git command'" \
  "$iex_nov_out" "PowerShell git command"
stop_nov_out="$(pwsh_stderr 'git --% commit --no-verify')"
assert_contains "PS msg #2662: unparsable-git path still cannot-parse" \
  "$stop_nov_out" "cannot be parsed with confidence"

malformed_rc=0
bash "$HOOK" <<< 'not json at all' >/dev/null 2>&1 || malformed_rc=$?
assert_exit "malformed JSON payload (blocked)" 2 "$malformed_rc"

# --- A NUL in the payload must not void the guard (#2122) --------------------
# hook::jq_fields separates its fields with a NUL. A JSON NUL escape inside the
# command used to split that value in two, fail the helper's cardinality check
# and return non-zero — which this hook spells `|| exit 0`, a PreToolUse ALLOW
# with no diagnostic. Asserted at the HOOK boundary, not in the helper, because
# the boundary is where the bypass was observable.
#
# The rule is one line with no exceptions: a NUL in any field the hook reads
# BLOCKS, whatever the surrounding text says. That includes a command whose text
# is entirely NUL bytes, which strips to nothing and would otherwise be waved
# through by the empty-command skip, and a NUL in a command with nothing
# dangerous in it. The guard refuses rather than matching because the text it can
# read is not dependably the text that would run — stripping SPLICES the bytes
# either side of the NUL into a token the payload never carried contiguously —
# and which executor behaviour applies has not been traced.
#
# A NUL cannot live in a shell variable, so the payload is assembled inside jq:
# `[0] | implode` is the one-character NUL string, which jq re-emits as a NUL
# escape on the wire — the form the harness would deliver.
run_nul() {
  local label="$1" head="$2" tail="$3" expected="$4" rc
  bash "$HOOK" <<<"$(jq -n --arg h "$head" --arg t "$tail" \
    '{tool_name:"Bash",tool_input:{command:($h + ([0] | implode) + $t)}}')" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}
run_nul "NUL after --no-verify (blocked)" "git push --no-verify" "" 2
run_nul "NUL splitting the flag itself (blocked)" "git push --no-veri" "fy" 2
run_nul "NUL then junk (blocked)" "git push --no-verify" "x" 2
run_nul "leading NUL, text preserved (blocked)" "" "git push --no-verify" 2
run_nul "all-NUL command strips to empty (blocked)" "" "" 2
run_nul "NUL in an otherwise harmless command (blocked)" "echo hi" "; echo bye" 2

# The block has to say what is wrong and what to do about it, not just refuse.
nul_stderr() {
  bash "$HOOK" <<<"$(jq -n --arg h "$1" --arg t "$2" \
    '{tool_name:"Bash",tool_input:{command:($h + ([0] | implode) + $t)}}')" 2>&1 >/dev/null
}
assert_contains "NUL msg: names the byte" "$(nul_stderr 'git push --no-verify' 'x')" "NUL byte"
assert_contains "NUL msg: gives the fix" "$(nul_stderr 'git push --no-verify' 'x')" \
  "reissue the tool call without the embedded NUL"

# The all-NUL command reaches the flag BEFORE the empty-COMMAND skip — its block
# must carry the NUL reason, and an empty command with no NUL must still take
# that skip. The pair is what pins the ordering; either row alone is equally
# consistent with a guard that refuses every empty command or blocks for some
# other reason.
assert_contains "NUL msg: all-NUL command refused by the flag, not skipped" \
  "$(nul_stderr '' '')" "NUL byte"
run "empty command, no NUL (allowed)" "" 0

report
