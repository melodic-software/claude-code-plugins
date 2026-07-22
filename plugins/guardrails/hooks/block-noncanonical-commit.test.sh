#!/usr/bin/env bash
# Contract test for block-noncanonical-commit.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash JSON on
# stdin, asserts on exit code (2 = blocked, 0 = allowed). Self-contained — no
# host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-noncanonical-commit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# Isolate every git fixture below from ambient user/system config. Exported once
# here rather than inside each subshell, so the setting is visibly process-wide
# and the fixtures stay comparable.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# run <label> <command> <expected-exit> [extra-env NAME=VAL ...]
run() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc
  env "$@" bash "$HOOK" <<<"$(command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

# --- the anti-pattern this guard exists for -----------------------------------
run "git commit -m (blocked)" "git commit -m 'feat: x'" 2
run "git commit -am (bundled, blocked)" "git commit -am 'feat: x'" 2
run "git commit -m with --trailer (still blocked — trailer is not the mechanic)" \
  "git commit -m 'feat: x' --trailer 'Co-Authored-By: X <x@y.z>'" 2
run "bare git commit (opens EDITOR, blocked)" "git commit" 2
run "git commit -a (no message source, blocked)" "git commit -a" 2

# --- the canonical form -------------------------------------------------------
run "git commit -F - (allowed)" "git commit -F - --cleanup=verbatim" 0
run "git commit --file - (allowed)" "git commit --file - " 0
run "git commit --file=- (allowed)" "git commit --file=-" 0
run "git commit -F- (attached, allowed)" "git commit -F-" 0

# The trailer_policy `none` case: /commit's own output when the repo convention
# forbids a co-author trailer. Requiring --trailer here would deadlock the skill.
run "git commit -F - without --trailer (allowed — trailer_policy none)" \
  "git commit -F - --cleanup=verbatim" 0

# --- exempt operations (no message-on-stdin form exists) ----------------------
run "git commit --amend --no-edit (allowed)" "git commit --amend --no-edit" 0
# --no-edit is NOT an exemption on its own: git accepts it for an ordinary
# commit, so exempting it unconditionally would let `--no-edit -m` straight past.
run "git commit --no-edit -m (blocked — --no-edit is not an amend)" \
  "git commit --no-edit -m subject" 2
run "git commit --amend (allowed)" "git commit --amend" 0
run "git commit -C HEAD (allowed)" "git commit -C HEAD" 0
run "git commit --reuse-message=HEAD (allowed)" "git commit --reuse-message=HEAD" 0
run "git commit --fixup HEAD (allowed)" "git commit --fixup HEAD" 0
run "git commit --squash=HEAD (allowed)" "git commit --squash=HEAD" 0
run "git commit -F msg.txt (path, allowed)" "git commit -F msg.txt" 0
run "git commit --file=msg.txt (path, allowed)" "git commit --file=msg.txt" 0

# --- top-level git options must not be confused with commit options ----------
# `-c` BEFORE the subcommand is config; only after `commit` is it --reedit.
run "git -c user.name=x commit -m (config, still blocked)" \
  "git -c user.name=x commit -m 'feat: x'" 2
run "git -c user.name=x commit -F - (config, allowed)" \
  "git -c user.name=x commit -F -" 0

# --- inline git aliases are expanded before the subcommand verdict -----------
# `git -c alias.c=commit c -m x` commits. Without expansion the subcommand reads
# as `c`, not `commit`, and the guard waves the whole thing through.
run "inline git alias to commit -m (blocked)" \
  "git -c alias.c=commit c -m bypass" 2
run "inline git alias carrying -m in the expansion (blocked)" \
  "git -c alias.ci='commit -m x' ci" 2
run "inline shell alias (leading !) to commit -m (blocked)" \
  "git -c alias.sh='!git commit -m x' sh" 2
run "inline git alias to a canonical commit (allowed)" \
  "git -c alias.c=commit c -F -" 0
run "inline alias to an unrelated subcommand (allowed)" \
  "git -c alias.st=status st" 0
# git applies the LAST -c value for a key; taking the first would let a decoy
# earlier value expanding to a harmless subcommand mask the real one.
run "last inline alias value wins (blocked)" \
  "git -c alias.c=status -c alias.c=commit c -m x" 2
run "last inline alias value wins (allowed when the last is harmless)" \
  "git -c alias.c=commit -c alias.c=status c -m x" 0

# --- #964: git chains aliases — re-expansion recurses to the commit -----------
# git expands an alias whose first word is itself an alias, so a non-canonical
# commit reached through a SECOND hop must still block. Command-line globals ride
# into each hop (so a second-hop --config-env alias is refused by shape), and the
# recursion stops on git's own alias-loop.
run "#964 case C: two-hop inline chain to commit -m (blocked)" \
  "git -c alias.c=x -c alias.x='commit -m bypass' c" 2
run "#964 H1: inline first hop, --config-env second hop (blocked by shape)" \
  "git -c alias.c=x --config-env=alias.x=AV c" 2 "AV=commit"
run "#964 three-hop inline chain to commit -m (blocked)" \
  "git -c alias.a=b -c alias.b=c -c alias.c='commit -m bypass' a" 2
run "#964 .command-spelled second hop to commit -m (blocked)" \
  "git -c alias.c=x -c alias.x.command='commit -m bypass' c" 2
# Benign controls — a two-hop chain to the canonical -F - form still ALLOWS, and
# an alias cycle terminates (git's alias-loop stop) and allows without hanging.
run "#964 benign two-hop chain to canonical commit -F - (allowed)" \
  "git -c alias.c=x -c alias.x='commit -F -' c" 0
run "#964 alias cycle terminates and allows (no hang)" \
  "git -c alias.a=b -c alias.b=a a" 0

# --- --config-env aliases are refused by SHAPE -------------------------------
# `--config-env=<key>=<envvar>` holds the alias expansion in an env var this guard never
# reads (its origin — an ambient var, an inline/`env` prefix, an `export`, `set -a`, or a
# nested `bash -c` in any wrapper — is the recurring fail-open surface). An env-defined
# alias for the INVOKED subcommand is refused by shape; a commit smuggled through it can
# never be verified. The extra-env below is ignored by the guard.
run "config-env alias for the invoked sub (blocked by shape)" "git --config-env=alias.c=AV c" 2
run "config-env alias, two-word --config-env form (blocked)" "git --config-env alias.c=AV c" 2
run "config-env alias, benign-looking value STILL blocked (value never read)" "git --config-env=alias.st=AV st" 2 AV=status
run "config-env alias, case-folded key (blocked)" "git --config-env=alias.C=AV c" 2
run "config-env alias, non-identifier env name (blocked)" "git --config-env=alias.c=bad-name c" 2
run "config-env alias, leading-dash env name (blocked)" "env -- '-CV=x' git --config-env=alias.c=-CV c" 2
run "config-env value last-wins over an inline decoy (blocked)" "git -c alias.c=log --config-env=alias.c=AV c" 2

# Refused wherever it APPEARS, through any wrapper — no env propagation is tracked, so
# every prior env-carrying bypass is closed by construction.
run "config-env alias inside an inline '!' shell alias (blocked)" "git -c \"alias.sh=!git --config-env=alias.c=AV c --allow-empty -m x\" sh" 2
# An inline alias whose expansion is itself a `--config-env` alias for the invoked sub
# runs at recursion depth 2, where the SHAPE refusal must still fire (real git commits).
run "wrapping inline alias expands to a --config-env alias (depth-2 shape refusal, blocked)" \
  "git -c alias.c='--config-env=alias.foo=AV foo' c" 2 AV=commit
run "config-env alias inside an env-prefixed bash -c (blocked)" "AV=commit bash -c 'git --config-env=alias.c=AV c -m x'" 2
run "config-env alias after export in a shell-alias body (blocked)" "git -c \"alias.sh=!export AV=commit; git --config-env=alias.c=AV c --allow-empty -m x\" sh" 2
run "config-env alias after 'then export' in a compound command (blocked)" "git -c 'alias.sh=!if true; then export AV=commit; fi; git --config-env=alias.c=AV c --allow-empty -m x' sh" 2
run "config-env alias after an assignment-prefixed export (blocked)" "git -c 'alias.sh=!AV=commit export AV; git --config-env=alias.c=AV c --allow-empty -m x' sh" 2
run "config-env alias after 'set -a; NAME=val' allexport (blocked)" "set -a; AV=commit; git --config-env=alias.c=AV c -m x" 2
run "config-env alias, env name colliding with an internal global (blocked)" "git --config-env=alias.c=HOOK_ENV_SNAPSHOT_OK c" 2 "HOOK_ENV_SNAPSHOT_OK=commit"

# ACCEPTANCE — decidable safe WITHOUT reading a value, so still allowed:
run "--config-env setting a NON-alias key, canonical commit (allowed)" "git --config-env=user.name=NAMEVAR commit -F -" 0
run "--config-env alias for a subcommand that is NOT invoked (allowed)" "git --config-env=alias.foo=AV status" 0
run "inline value last-wins over an earlier --config-env for the same key (allowed)" "git --config-env=alias.c=AV -c alias.c=log c" 0
# A `$( )` env name is command-substituted by the shell before git and split by the
# static parser — neither evaluates it, so no exec and (git-fatal) no commit runs.
rm -f "$TEST_TMPDIR/pwned-nc"
run "injection-shaped config-env env name (allowed — never evaluated)" \
  "git --config-env=alias.c=\$(touch $TEST_TMPDIR/pwned-nc) c" 0
assert_file_absent "config-env injection: no exec for a shell-metachar env name" "$TEST_TMPDIR/pwned-nc"

# --- case-insensitive alias resolution (git folds config names) --------------
run "inline alias, uppercase subcommand (blocked)" "git -c alias.c=commit C -m x" 2
run "inline alias, uppercase alias key (blocked)" "git -c alias.C=commit c -m x" 2
run "inline alias, uppercase both, to canonical form (allowed)" "git -c alias.C=commit C -F -" 0

# --- `alias.<sub>.command` subkey is an alias definition too ------------------
# git reads the `alias.<sub>.command` subkey as the alias (`git -c alias.c.command=commit
# c -m x` commits non-canonically); the guard classifies that spelling inline and by shape.
run "inline .command-subkey alias to commit -m (blocked)" "git -c alias.c.command=commit c -m bypass" 2
run "config-env .command-subkey alias for the invoked sub (blocked by shape)" "git --config-env=alias.c.command=AV c" 2
run ".command-subkey alias, case-folded key (blocked)" "git -c alias.C.command=commit c -m x" 2
# A non-`command` alias subkey is not an alias to git, so it must not be blocked.
run "non-command alias subkey is not an alias (allowed)" "git -c alias.c.nope=commit c -m bypass" 0
# MAX-DANGER UNION: which spelling git runs when both are set is version-dependent, so a
# benign value in one spelling must never mask a commit alias in the other — the guard
# blocks if EITHER spelling commits non-canonically, and allows only when BOTH are benign.
run "commit plain masked by a benign .command (blocked by union)" "git -c alias.c=commit -c alias.c.command=status c -m x" 2
run "commit .command masked by a benign plain (blocked by union)" "git -c alias.c=status -c alias.c.command=commit c -m x" 2
run "commit plain, benign .command decoy first (blocked by union)" "git -c alias.c.command=status -c alias.c=commit c -m x" 2
run "both spellings benign non-commit (allowed)" "git -c alias.c=status -c alias.c.command=log c" 0
# Union on the --config-env shape path: an env spelling refuses even when the sibling
# inline spelling is benign (both command-line orders).
run "env plain spelling refuses despite a benign inline .command (blocked)" "git --config-env=alias.c=AV -c alias.c.command=status c" 2
run "env .command spelling refuses despite a benign inline plain (blocked)" "git --config-env=alias.c.command=AV -c alias.c=status c" 2

# --- other subcommands are untouched -----------------------------------------
run "git log (allowed)" "git log --oneline -5" 0
run "git push (allowed)" "git push origin main" 0
run "non-git command (allowed)" "echo git commit -m nope" 0

# --- prose containing the anti-pattern is not a false positive ---------------
run "quoted mention in a heredoc body (allowed)" \
  "git commit -F - <<'EOF'
docs: explain why git commit -m 'x' is wrong
EOF" 0

# --- shell -c wrappers are re-parsed -----------------------------------------
run "bash -lc wrapped -m (blocked)" "bash -lc \"git commit -m 'feat: x'\"" 2
run "bash -lc wrapped -F - (allowed)" "bash -lc 'git commit -F -'" 0

# --- control operators: a later segment is still checked ---------------------
run "second segment carries -m (blocked)" "git add -A && git commit -m 'x'" 2

# --- kill switch and allow-list ----------------------------------------------
run "kill switch disables the guard" "git commit -m 'feat: x'" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ENABLED=false
run "allow-list message-flag permits -m" "git commit -m 'feat: x'" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW=message-flag
run "unrelated allow token does not permit -m" "git commit -m 'feat: x'" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW=something-else

# --- in-progress sequencer is exempt -----------------------------------------
# A real repo mid-merge: `git commit` concludes the merge with the message git
# prepared, and gating it would strand the conflict resolution.
SEQ="$TEST_TMPDIR/seq"
mkdir -p "$SEQ"
(
  cd "$SEQ" || exit 1
  git init -q .
  git config user.email t@e.st
  git config user.name t
  : >a
  git add a
  git commit -qm base --no-verify 2>/dev/null
) >/dev/null 2>&1

GITDIR="$SEQ/.git"
if [[ -d "$GITDIR" ]]; then
  : >"$GITDIR/MERGE_HEAD"
  rc=0
  MSYS_NO_PATHCONV=1 jq -n --arg c "git commit -m 'merge fix'" --arg d "$SEQ" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    bash "$HOOK" >/dev/null 2>&1
  rc=$?
  assert_exit "in-progress merge is exempt" 0 "$rc"

  rm -f "$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git commit -m 'not a merge'" --arg d "$SEQ" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    bash "$HOOK" >/dev/null 2>&1
  rc=$?
  assert_exit "same repo with no sequencer state is blocked" 2 "$rc"
else
  echo "ok: sequencer fixture skipped (git init unavailable)"
  PASS=$((PASS + 1))
fi

# --- `git -C <repo>` targets another repo's state ----------------------------
# A conflict resolution driven at another repo must read THAT repo's sequencer
# state, not the session cwd's.
if [[ -d "$GITDIR" ]]; then
  : >"$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git -C $SEQ commit -m 'merge fix'" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:"/"}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "git -C honors the target repo's in-progress merge" 0 $?

  rm -f "$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git -C $SEQ commit -m 'not a merge'" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:"/"}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "git -C with no sequencer state in the target repo is blocked" 2 $?
fi

# --- explicit --git-dir names the repo whose sequencer state matters ---------
if [[ -d "$GITDIR" ]]; then
  : >"$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git --git-dir=$GITDIR --work-tree=$SEQ commit -m x" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:"/"}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "--git-dir honors that repo's in-progress merge" 0 $?

  rm -f "$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git --git-dir=$GITDIR --work-tree=$SEQ commit -m x" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:"/"}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "--git-dir with no sequencer state is blocked" 2 $?
fi

# --- aliases persisted in git config (not just inline -c) --------------------
# `git config alias.c commit` lives in .git/config, where the parser's inline
# -c capture cannot see it; the hook must ask git to resolve it.
PCFG="$TEST_TMPDIR/persisted"
mkdir -p "$PCFG"
(
  cd "$PCFG" || exit 1
  git init -q .
  git config user.email t@e.st
  git config user.name t
  git config alias.c commit
) >/dev/null 2>&1

if [[ -d "$PCFG/.git" ]]; then
  for spec in "git c -m bypass:2" "git c -F -:0"; do
    cmd="${spec%:*}"
    want="${spec##*:}"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$cmd" --arg d "$PCFG" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      bash "$HOOK" >/dev/null 2>&1
    assert_exit "persisted config alias: $cmd" "$want" $?
  done
fi

# --- #964: persisted alias CHAIN (git resolves alias -> alias in config) ------
# `git config alias.c x; git config alias.x commit` chains in .git/config; git
# expands c -> x -> commit, so `git c -m` must block through both hops.
PCHAIN="$TEST_TMPDIR/persisted-chain"
mkdir -p "$PCHAIN"
(
  cd "$PCHAIN" || exit 1
  git init -q .
  git config user.email t@e.st
  git config user.name t
  git config alias.c x
  git config alias.x commit
) >/dev/null 2>&1

if [[ -d "$PCHAIN/.git" ]]; then
  for spec in "git c -m bypass:2" "git c -F -:0"; do
    cmd="${spec%:*}"
    want="${spec##*:}"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$cmd" --arg d "$PCHAIN" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      bash "$HOOK" >/dev/null 2>&1
    assert_exit "persisted alias chain: $cmd" "$want" $?
  done
fi

# --- the block message names the fix -----------------------------------------
out=$(bash "$HOOK" <<<"$(command_json "git commit -m 'feat: x'")" 2>&1)
assert_contains "block message names -F -" "$out" '-F -'
assert_contains "block message names the skill" "$out" '/commit'

# --- PowerShell tool coverage ------------------------------------------------
# The canonical PowerShell commit form (a here-string piped to `git commit -F -`)
# must be allowed exactly as the Bash `-F -` form is; a `-m` PowerShell commit
# must be blocked; commit-shaped PowerShell the guard cannot parse fails closed.
run_pwsh() {
  local label="$1" command="$2" expected="$3" rc
  bash "$HOOK" <<<"$(pwsh_command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}
run_pwsh "PS: canonical here-string | git commit -F - (allowed)" \
  "$(printf '%s\n%s\n%s' "@'" "feat: x" "'@ | git commit -F -")" 0
run_pwsh "PS: git commit -m here-string (blocked — not the stdin form)" \
  "$(printf '%s\n%s\n%s' "git commit -m @'" "feat: x" "'@")" 2
run_pwsh "PS: git commit -m literal (blocked)" "git commit -m 'feat: x'" 2
run_pwsh "PS: git commit --amend (allowed — exempt)" "git commit --amend" 0
run_pwsh "PS: git status (allowed — not a commit)" "git status" 0
run_pwsh "PS: backtick-continued commit (fail-closed block)" \
  "$(printf 'git commit -m x `\n --cleanup=verbatim')" 2
run_pwsh "PS: unbalanced here-string hiding a -m commit (fail-closed block)" \
  "$(printf '%s\n%s\n%s' "@'" "body" "'X ; git commit -m sneaky")" 2

# The PowerShell block message shows the here-string form, not a Bash heredoc.
psout=$(bash "$HOOK" <<<"$(pwsh_command_json "git commit -m 'x'")" 2>&1)
assert_contains "PS block message shows the here-string form" "$psout" "'@ | git commit -F -"
assert_absent "PS block message omits the Bash heredoc" "$psout" "<<'EOF'"

echo
echo "passed: $PASS   failed: $FAIL"
((FAIL == 0))
