#!/usr/bin/env bash

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-noncanonical-commit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

GUARD_UNDER_TEST="$HOOK"

run() {
  local label="$1" command="$2" expected="$3"
  shift 3
  expect "$label" "$expected" --command "$command" -- "$@"
}

NL=$'\n'
run "git commit -m with a \$ in double quotes (blocked)" "git commit -m \"feat: x \$body\"" 2
run "git commit -m with backticks in double quotes (blocked)" \
  "git commit -m \"fix: rename \`foo\` to \`bar\`\"" 2
run "git commit -m with a \$(...) in double quotes (blocked)" \
  "git commit -m \"fix: \$(date)\"" 2
run "git commit -m with an unquoted-heredoc substitution (blocked: the body expands)" \
  "git commit -m \"\$(cat <<EOF${NL}fix: \$var${NL}EOF${NL})\"" 2
run "git commit -m with a heredoc substitution that runs more after it (blocked)" \
  "git commit -m \"\$(cat <<'EOF'${NL}fix: x${NL}EOF${NL}rm -rf /tmp/x${NL})\"" 2
run "git commit -m single-line (allowed — nothing the shell expands)" \
  "git commit -m 'feat: x'" 0
run "git commit -m multi-line double-quoted plain text (allowed)" \
  "git commit -m \"feat: x${NL}${NL}body${NL}${NL}Co-Authored-By: X <x@y.z>\"" 0
run "git commit -m multi-line single-quoted with \$ and backticks (allowed)" \
  "git commit -m 'feat: x${NL}${NL}body with \$dollar and \`tick\`'" 0
run "git commit -m multi-line via \$'…' (allowed — the tokenizer decodes ANSI-C)" \
  "git commit -m \$'feat: x\nbody'" 0
run "git commit -m from a quoted-heredoc substitution (allowed: the body expands nothing)" \
  "git commit -m \"\$(cat <<'EOF'${NL}fix: rename \`foo\` for \$total${NL}${NL}Body.${NL}EOF${NL})\"" 0
run "git commit -m with every \$ and backtick escaped (allowed)" \
  "git commit -m \"fix: costs \\\$5 and \\\`x\\\`\"" 0
run "git commit --message='...' with a \$ (allowed)" "git commit --message='has \$x'" 0
run "a single-quoted twin elsewhere does not excuse a double-quoted -m (blocked)" \
  ": m 'fix \$x'; git commit -m \"fix \$x\"" 2
run "the same single-quoted message twice (allowed)" "git commit -m 'fix \$x' -m 'fix \$x'" 0
run "a closed quoted heredoc elsewhere does not excuse an -m one that runs more (blocked)" \
  ": \"\$(cat <<'EOF'${NL}ok${NL}EOF${NL})\"; git commit -m \"\$(cat <<'EOF'${NL}fix${NL}EOF${NL}rm -rf x${NL})\"" 2
run "git commit -m \"\$msg\" (allowed)" "git commit -m \"\$msg\"" 0
run "git commit -m \"\$(printf '...')\" (allowed)" \
  "git commit -m \"\$(printf 'fix: x\\n\\nbody \`y\`')\"" 0
run "quoted-heredoc substitution whose body holds double quotes (allowed)" \
  "git commit -m \"\$(cat <<'EOF'${NL}fix: say \"quoted\" words${NL}EOF${NL})\"" 0
run "a substitution followed by \$HOME in the quotes (blocked)" "git commit -m \"\$(true) \$HOME\"" 2
run "a quoted-heredoc substitution followed by \$HOME in the quotes (blocked)" \
  "git commit -m \"\$(cat <<'EOF'${NL}feat${NL}EOF${NL}) \$HOME\"" 2
run "a quoted-heredoc substitution, then && another command (allowed)" \
  "git commit -m \"\$(cat <<'EOF'${NL}feat: x${NL}EOF${NL})\" && git status" 0
run "wsl git commit -m multi-line (blocked)" "wsl git commit -m \"feat: x \$body\"" 2
run "wsl git commit -m single-line (allowed)" "wsl git commit -m 'feat: x'" 0
run "git commit -am multi-line (bundled cluster, blocked)" "git commit -am \"feat: x \$body\"" 2
run "git commit -am single-line (allowed)" "git commit -am 'feat: x'" 0
run "git commit -m<attached> multi-line (blocked)" "git commit -m\"feat: x \$body\"" 2
run "git commit --message=<attached> multi-line (blocked)" \
  "git commit --message=\"feat: x \$body\"" 2
run "git commit --message <separated> multi-line (blocked)" \
  "git commit --message \"feat: x \$body\"" 2
run "git commit --message <separated> single-line (allowed)" \
  "git commit --message 'feat: x'" 0
run "git commit --mess=<abbreviated attached> multi-line (blocked)" \
  "git commit --mess=\"feat: x \$body\"" 2
run "git commit --mess=<abbreviated attached> single-line (allowed)" \
  "git commit --mess='feat: x'" 0
run "git commit --mess <abbreviated separated> multi-line (blocked)" \
  "git commit --mess \"feat: x \$body\"" 2
run "git commit --mess <abbreviated separated> single-line (allowed)" \
  "git commit --mess 'feat: x'" 0
run "git commit --m=<shortest abbreviation> multi-line (blocked)" \
  "git commit --m=\"feat: x \$body\"" 2
run "git commit --m=<shortest abbreviation> single-line (allowed)" \
  "git commit --m='feat: x'" 0
run "git commit --m <shortest abbreviation, separated> multi-line (blocked)" \
  "git commit --m \"feat: x \$body\"" 2
run "git commit --m <shortest abbreviation, separated> single-line (allowed)" \
  "git commit --m 'feat: x'" 0
run "git commit -m multi-line with --trailer (still blocked — trailer is not the mechanic)" \
  "git commit -m \"feat: x \$body\" --trailer 'Co-Authored-By: X <x@y.z>'" 2
run "repeated single-line -m (allowed — git itself joins the paragraphs)" \
  "git commit -m 'feat: x' -m 'body'" 0
run "bare git commit (no -m, allowed — opens EDITOR, no mangling hazard)" "git commit" 0
run "git commit -a (no message source, allowed)" "git commit -a" 0

run "git commit -F - (allowed)" "git commit -F - --cleanup=verbatim" 0
run "git commit --file - (allowed)" "git commit --file - " 0
run "git commit --file=- (allowed)" "git commit --file=-" 0
run "git commit -F- (attached, allowed)" "git commit -F-" 0

run "git commit -F - without --trailer (allowed — trailer_policy none)" \
  "git commit -F - --cleanup=verbatim" 0

run "git commit --amend --no-edit (allowed)" "git commit --amend --no-edit" 0
run "git commit --no-edit -m multi-line (blocked — --no-edit is not an amend)" \
  "git commit --no-edit -m \"subject \$body\"" 2
run "git commit --amend (allowed)" "git commit --amend" 0
run "git commit --amend -m multi-line (allowed — amending is exempt)" \
  "git commit --amend -m \"subject \$body\"" 0
run "git commit -C HEAD (allowed)" "git commit -C HEAD" 0
run "git commit --reuse-message=HEAD (allowed)" "git commit --reuse-message=HEAD" 0
run "git commit --fixup HEAD (allowed)" "git commit --fixup HEAD" 0
run "git commit --squash=HEAD (allowed)" "git commit --squash=HEAD" 0
run "git commit -F msg.txt (path, allowed)" "git commit -F msg.txt" 0
run "git commit --file=msg.txt (path, allowed)" "git commit --file=msg.txt" 0

run "git -c user.name=x commit -m multi-line (config, still blocked)" \
  "git -c user.name=x commit -m \"feat: x \$body\"" 2
run "git -c user.name=x commit -F - (config, allowed)" \
  "git -c user.name=x commit -F -" 0

run "inline git alias to a multi-line commit -m (blocked)" \
  "git -c alias.c=commit c -m \"bypass \$body\"" 2
run "inline git alias carrying a multi-line -m in the expansion (blocked)" \
  "git -c alias.ci='commit -m \"x \$y\"' ci" 2
run "inline shell alias (leading !) to a multi-line commit -m (blocked)" \
  "git -c alias.sh='!git commit -m \"x \$y\"' sh" 2
run "inline git alias to a single-line commit -m (allowed)" \
  "git -c alias.c=commit c -m bypass" 0
run "inline git alias to a canonical commit (allowed)" \
  "git -c alias.c=commit c -F -" 0
run "inline alias to an unrelated subcommand (allowed)" \
  "git -c alias.st=status st" 0
run "last inline alias value wins (blocked)" \
  "git -c alias.c=status -c alias.c=commit c -m \"x \$y\"" 2
run "last inline alias value wins (allowed when the last is harmless)" \
  "git -c alias.c=commit -c alias.c=status c -m \"x \$y\"" 0

run "#964 case C: two-hop inline chain to a multi-line commit -m (blocked)" \
  "git -c alias.c=x -c alias.x='commit -m \"bypass \$b\"' c" 2
run "#964 H1: inline first hop, --config-env second hop (blocked by shape)" \
  "git -c alias.c=x --config-env=alias.x=AV c" 2 "AV=commit"
run "#964 three-hop inline chain to a multi-line commit -m (blocked)" \
  "git -c alias.a=b -c alias.b=c -c alias.c='commit -m \"bypass \$b\"' a" 2
run "#964 .command-spelled second hop to a multi-line commit -m (blocked)" \
  "git -c alias.c=x -c alias.x.command='commit -m \"bypass \$b\"' c" 2
run "#964 benign two-hop chain to canonical commit -F - (allowed)" \
  "git -c alias.c=x -c alias.x='commit -F -' c" 0
run "#964 alias cycle terminates and allows (no hang)" \
  "git -c alias.a=b -c alias.b=a a" 0
run "#964 shell-alias body re-invoking the outer chain name (blocked)" \
  "git -c alias.a='!git -c alias.a=\"commit --allow-empty -m \\\"bypass \$b\\\"\" a' a" 2
run "#964 shell-alias re-invocation, canonical -F - twin (allowed)" \
  "git -c alias.a='!git -c alias.a=\"commit -F -\" a' a" 0

run "depth cap: a 3-hop chain to an allowed commit nested past the cap denies" \
  "git -c alias.a1=a2 -c alias.a2=a3 -c alias.a3='commit -m ok' a1" 2 GUARDRAILS_ALIAS_DEPTH_MAX=2
assert_contains "depth cap: the deny names the alias chain" "$GUARD_ERR" "alias chain"
run "depth cap: the same chain inside the cap is allowed" \
  "git -c alias.a1=a2 -c alias.a2=a3 -c alias.a3='commit -m ok' a1" 0 GUARDRAILS_ALIAS_DEPTH_MAX=8
NC_HOPS30=""
for ((nc_i = 1; nc_i < 30; nc_i++)); do NC_HOPS30+=" -c alias.a$nc_i=a$((nc_i + 1))"; done
NC_HOPS30+=" -c alias.a30='commit -m ok'"
if [[ -r /proc/self/limits ]]; then
  run "depth cap: a 30-hop chain to an allowed commit is allowed under the real stack" \
    "git$NC_HOPS30 a1" 0
else
  run "depth cap: a host with no /proc/self/limits caps at 25, so the 30-hop chain denies" \
    "git$NC_HOPS30 a1" 2
fi
run "depth cap: no limits file falls back to 25, so the 30-hop chain denies" \
  "git$NC_HOPS30 a1" 2 GUARDRAILS_PROC_LIMITS="$TEST_TMPDIR/no-such-limits"
assert_contains "depth cap: the no-/proc deny names the alias chain" "$GUARD_ERR" "alias chain"

HANG_GUARD_SECS=300

TRAVERSAL_CWD="$TEST_TMPDIR/traversal"
mkdir -p "$TRAVERSAL_CWD"
run_guarded() {
  local label="$1" command="$2" expected="$3" rc
  MSYS_NO_PATHCONV=1 jq -n --arg c "$command" --arg d "$TRAVERSAL_CWD" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  if ((rc == 124)); then
    bad "$label: no verdict inside the ${HANG_GUARD_SECS}s hang guard — the hook HUNG. An over-budget walk exits 2 naming the re-expansion ceiling; it does not hang."
  else
    assert_exit "$label" "$expected" "$rc"
  fi
}

run_guarded "traversal: 20-hop dual-spelling chain to a canonical commit (allowed, bounded)" \
  "$(alias_chain 20 'commit -F -')" 0
run_guarded "traversal: 20-hop dual-spelling chain to a multi-line commit -m (blocked, bounded)" \
  "$(alias_chain 20 "commit -m \"bypass \$b\"")" 2
NC_LONG_HOPS=60
[[ -r /proc/self/limits ]] || NC_LONG_HOPS=24
run_guarded "traversal: $NC_LONG_HOPS-hop single-spelling chain to a canonical commit (allowed)" \
  "$(
    cmd="git"
    for ((i = 1; i < NC_LONG_HOPS; i++)); do cmd+=" -c alias.a$i=a$((i + 1))"; done
    printf '%s' "$cmd -c alias.a$NC_LONG_HOPS='commit -F -' a1"
  )" 0
run_guarded "traversal: divergent-spelling chain exhausts the budget (blocked, bounded)" \
  "$(alias_chain 12 status diverge)" 2
budgetout=$(timeout "$HANG_GUARD_SECS" bash "$HOOK" <<<"$(command_json "$(alias_chain 12 status diverge)")" 2>&1)
assert_contains "traversal: budget block names the re-expansion ceiling" \
  "$budgetout" "re-expansions"

run "config-env alias for the invoked sub (blocked by shape)" "git --config-env=alias.c=AV c" 2
run "config-env alias, two-word --config-env form (blocked)" "git --config-env alias.c=AV c" 2
run "config-env alias, benign-looking value STILL blocked (value never read)" "git --config-env=alias.st=AV st" 2 AV=status
run "config-env alias, case-folded key (blocked)" "git --config-env=alias.C=AV c" 2
run "config-env alias, non-identifier env name (blocked)" "git --config-env=alias.c=bad-name c" 2
run "config-env alias, leading-dash env name (blocked)" "env -- '-CV=x' git --config-env=alias.c=-CV c" 2
run "config-env value last-wins over an inline decoy (blocked)" "git -c alias.c=log --config-env=alias.c=AV c" 2

run "config-env alias inside an inline '!' shell alias (blocked)" "git -c \"alias.sh=!git --config-env=alias.c=AV c --allow-empty -m x\" sh" 2
run "wrapping inline alias expands to a --config-env alias (depth-2 shape refusal, blocked)" \
  "git -c alias.c='--config-env=alias.foo=AV foo' c" 2 AV=commit
run "config-env alias inside an env-prefixed bash -c (blocked)" "AV=commit bash -c 'git --config-env=alias.c=AV c -m x'" 2
run "config-env alias after export in a shell-alias body (blocked)" "git -c \"alias.sh=!export AV=commit; git --config-env=alias.c=AV c --allow-empty -m x\" sh" 2
run "config-env alias after 'then export' in a compound command (blocked)" "git -c 'alias.sh=!if true; then export AV=commit; fi; git --config-env=alias.c=AV c --allow-empty -m x' sh" 2
run "config-env alias after an assignment-prefixed export (blocked)" "git -c 'alias.sh=!AV=commit export AV; git --config-env=alias.c=AV c --allow-empty -m x' sh" 2
run "config-env alias after 'set -a; NAME=val' allexport (blocked)" "set -a; AV=commit; git --config-env=alias.c=AV c -m x" 2
run "config-env alias, env name colliding with an internal global (blocked)" "git --config-env=alias.c=HOOK_ENV_SNAPSHOT_OK c" 2 "HOOK_ENV_SNAPSHOT_OK=commit"

run "--config-env setting a NON-alias key, canonical commit (allowed)" "git --config-env=user.name=NAMEVAR commit -F -" 0
run "--config-env alias for a subcommand that is NOT invoked (allowed)" "git --config-env=alias.foo=AV status" 0
run "inline value last-wins over an earlier --config-env for the same key (allowed)" "git --config-env=alias.c=AV -c alias.c=log c" 0
rm -f "$TEST_TMPDIR/pwned-nc"
run "injection-shaped config-env env name (blocked — the alias is not readable)" \
  "git --config-env=alias.c=\$(touch $TEST_TMPDIR/pwned-nc) c" 2
assert_file_absent "config-env injection: no exec for a shell-metachar env name" "$TEST_TMPDIR/pwned-nc"

run "inline alias, uppercase subcommand (blocked)" "git -c alias.c=commit C -m \"x \$y\"" 2
run "inline alias, uppercase alias key (blocked)" "git -c alias.C=commit c -m \"x \$y\"" 2
run "inline alias, uppercase both, to canonical form (allowed)" "git -c alias.C=commit C -F -" 0

run "inline .command-subkey alias to a multi-line commit -m (blocked)" "git -c alias.c.command=commit c -m \"bypass \$b\"" 2
run "config-env .command-subkey alias for the invoked sub (blocked by shape)" "git --config-env=alias.c.command=AV c" 2
run ".command-subkey alias, case-folded key (blocked)" "git -c alias.C.command=commit c -m \"x \$y\"" 2
run "non-command alias subkey is not an alias (allowed)" "git -c alias.c.nope=commit c -m \"bypass \$b\"" 0
run "commit plain masked by a benign .command (blocked by union)" "git -c alias.c=commit -c alias.c.command=status c -m \"x \$y\"" 2
run "commit .command masked by a benign plain (blocked by union)" "git -c alias.c=status -c alias.c.command=commit c -m \"x \$y\"" 2
run "commit plain, benign .command decoy first (blocked by union)" "git -c alias.c.command=status -c alias.c=commit c -m \"x \$y\"" 2
run "both spellings benign non-commit (allowed)" "git -c alias.c=status -c alias.c.command=log c" 0
run "env plain spelling refuses despite a benign inline .command (blocked)" "git --config-env=alias.c=AV -c alias.c.command=status c" 2
run "env .command spelling refuses despite a benign inline plain (blocked)" "git --config-env=alias.c.command=AV -c alias.c=status c" 2

run "git log (allowed)" "git log --oneline -5" 0
run "git push (allowed)" "git push origin main" 0
run "non-git command (allowed)" "echo git commit -m \"no \$pe\"" 0

run "quoted mention in a heredoc body (allowed)" \
  "git commit -F - <<'EOF'
docs: explain why git commit -m 'x' is wrong
EOF" 0

run "bash -lc wrapped -m with a \$ (blocked)" "bash -lc 'git commit -m \"feat: x \$body\"'" 2
run "bash -lc wrapped -F - (allowed)" "bash -lc 'git commit -F -'" 0

run "second segment carries a multi-line -m (blocked)" "git add -A && git commit -m \"x \$y\"" 2

run "kill switch disables the guard" "git commit -m \"feat: x \$body\"" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ENABLED=false
run "allow-list message-flag permits a multi-line -m" "git commit -m \"feat: x \$body\"" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW=message-flag
run "unrelated allow token does not permit a multi-line -m" "git commit -m \"feat: x \$body\"" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW=something-else

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
  MSYS_NO_PATHCONV=1 jq -n --arg c "git commit -m \"merge \$fix\"" --arg d "$SEQ" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    bash "$HOOK" >/dev/null 2>&1
  rc=$?
  assert_exit "in-progress merge is exempt (even with a multi-line -m)" 0 "$rc"

  rm -f "$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git commit -m \"not a \$merge\"" --arg d "$SEQ" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    bash "$HOOK" >/dev/null 2>&1
  rc=$?
  assert_exit "same repo with no sequencer state is blocked" 2 "$rc"
else
  echo "ok: sequencer fixture skipped (git init unavailable)"
  PASS=$((PASS + 1))
fi

if [[ -d "$GITDIR" ]]; then
  : >"$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git -C $SEQ commit -m \"merge \$fix\"" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:"/"}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "git -C honors the target repo's in-progress merge" 0 $?

  rm -f "$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git -C $SEQ commit -m \"not a \$merge\"" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:"/"}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "git -C with no sequencer state in the target repo is blocked" 2 $?
fi

if [[ -d "$GITDIR" ]]; then
  : >"$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git --git-dir=$GITDIR --work-tree=$SEQ commit -m \"x \$y\"" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:"/"}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "--git-dir honors that repo's in-progress merge" 0 $?

  rm -f "$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git --git-dir=$GITDIR --work-tree=$SEQ commit -m \"x \$y\"" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:"/"}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "--git-dir with no sequencer state is blocked" 2 $?
fi

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
  for spec in "git c -m \"bypass \$b\":2" "git c -F -:0"; do
    cmd="${spec%:*}"
    want="${spec##*:}"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$cmd" --arg d "$PCFG" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      bash "$HOOK" >/dev/null 2>&1
    assert_exit "persisted config alias: $cmd" "$want" $?
  done
fi

PSTAT="$TEST_TMPDIR/persisted-status"
mkdir -p "$PSTAT"
(
  cd "$PSTAT" || exit 1
  git init -q .
  git config user.email t@e.st
  git config user.name t
  git config alias.status $'commit -m "bypass $b"'
) >/dev/null 2>&1
if [[ -d "$PSTAT/.git" ]]; then
  MSYS_NO_PATHCONV=1 jq -n --arg d "$PSTAT" \
    '{tool_name:"Bash",tool_input:{command:"git status --short"},cwd:$d}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "git status is not a commit even when alias.status names one" 0 $?
fi

PWC="$TEST_TMPDIR/persisted-whatchanged"
mkdir -p "$PWC"
(
  cd "$PWC" || exit 1
  git init -q .
  git config user.email t@e.st
  git config user.name t
  git config alias.whatchanged $'commit -m "bypass $b"'
) >/dev/null 2>&1
if [[ -d "$PWC/.git" ]]; then
  MSYS_NO_PATHCONV=1 jq -n --arg d "$PWC" \
    '{tool_name:"Bash",tool_input:{command:"git whatchanged"},cwd:$d}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "git whatchanged alias to newline -m is still a commit" 2 $?
fi

PBR="$TEST_TMPDIR/persisted-bugreport"
mkdir -p "$PBR"
(
  cd "$PBR" || exit 1
  git init -q .
  git config user.email t@e.st
  git config user.name t
  git config alias.bugreport $'commit -m "bypass $b"'
) >/dev/null 2>&1
if [[ -d "$PBR/.git" ]]; then
  MSYS_NO_PATHCONV=1 jq -n --arg d "$PBR" \
    '{tool_name:"Bash",tool_input:{command:"git bugreport"},cwd:$d}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "git bugreport alias to newline -m is still a commit" 2 $?
fi

PCMD="$TEST_TMPDIR/persisted-command"
mkdir -p "$PCMD"
(
  cd "$PCMD" || exit 1
  git init -q .
  git config user.email t@e.st
  git config user.name t
  git config alias.c.command commit
) >/dev/null 2>&1

if [[ -d "$PCMD/.git" ]]; then
  for spec in "git c -m \"bypass \$b\":2" "git c -F -:0"; do
    cmd="${spec%:*}"
    want="${spec##*:}"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$cmd" --arg d "$PCMD" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      bash "$HOOK" >/dev/null 2>&1
    assert_exit "persisted .command-subkey alias: $cmd" "$want" $?
  done
fi

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
  for spec in "git c -m \"bypass \$b\":2" "git c -F -:0"; do
    cmd="${spec%:*}"
    want="${spec##*:}"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$cmd" --arg d "$PCHAIN" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      bash "$HOOK" >/dev/null 2>&1
    assert_exit "persisted alias chain: $cmd" "$want" $?
  done

  mixed="git"
  for ((i = 1; i < 12; i++)); do mixed+=" -c alias.a$i=a$((i + 1)) -c alias.a$i.command=a$((i + 1))"; done
  mixed+=" -c alias.a12=c -c alias.a12.command=c a1"
  for spec in "-m \"bypass \$b\":2" "-F -:0"; do
    args="${spec%:*}"
    want="${spec##*:}"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$mixed $args" --arg d "$PCHAIN" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
    assert_exit "inline dual-spelling chain into a persisted alias: git … a1 $args" "$want" $?
  done
fi

FORK_REAL_GIT="$(command -v git)"
FORK_SHIM="$TEST_TMPDIR/git-shim"
FORK_LOG="$TEST_TMPDIR/git-spawn-log"
mkdir -p "$FORK_SHIM"
if [[ -n "$FORK_REAL_GIT" ]]; then
  cat >"$FORK_SHIM/git" <<SHIM
#!/usr/bin/env bash
printf 'x\n' >>"\${BNC_GIT_SPAWN_LOG:-/dev/null}"
exec '$FORK_REAL_GIT' "\$@"
SHIM
  chmod +x "$FORK_SHIM/git"
fi

fork_chain_repo() {
  local dir="$1" n="$2" i
  mkdir -p "$dir"
  (
    cd "$dir" || exit 1
    git init -q .
    git config user.email t@e.st
    git config user.name t
    for ((i = 1; i < n; i++)); do git config "alias.f$i" "f$((i + 1))"; done
    git config "alias.f$n" 'commit -F -'
    git config alias.d status
  ) >/dev/null 2>&1
}
FORK10="$TEST_TMPDIR/fork-chain-10"
FORK20="$TEST_TMPDIR/fork-chain-20"
fork_chain_repo "$FORK10" 10
fork_chain_repo "$FORK20" 20

run_shimmed() {
  : >"$FORK_LOG"
  MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$2" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    BNC_GIT_SPAWN_LOG="$FORK_LOG" PATH="$FORK_SHIM:$PATH" \
      timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
  SPAWN_RC=$?
  SPAWN_COUNT=$(wc -l <"$FORK_LOG")
  SPAWN_COUNT=${SPAWN_COUNT//[[:space:]]/}
}
run_unshimmed() {
  MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$2" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
  PLAIN_RC=$?
}

if [[ -n "$FORK_REAL_GIT" && -d "$FORK10/.git" && -d "$FORK20/.git" ]]; then
  fork_diverge="git"
  for ((i = 1; i < 8; i++)); do
    fork_diverge+=" -c alias.g$i='g$((i + 1)) --x$i' -c alias.g$i.command='g$((i + 1)) --y$i'"
  done
  fork_diverge+=" -c alias.g8='d --x8' -c alias.g8.command='d --y8' g1"

  run_shimmed "git f1" "$FORK10"
  FORKS_10=$SPAWN_COUNT
  FORK_RC_10=$SPAWN_RC
  run_unshimmed "git f1" "$FORK10"
  assert_exit "fork pin: 10-hop persisted chain to commit -F - is allowed" 0 "$PLAIN_RC"
  assert_exit "fork pin: the shim leaves the 10-hop verdict unchanged" "$PLAIN_RC" "$FORK_RC_10"

  run_shimmed "git f1" "$FORK20"
  FORKS_20=$SPAWN_COUNT
  FORK_RC_20=$SPAWN_RC
  run_unshimmed "git f1" "$FORK20"
  assert_exit "fork pin: 20-hop persisted chain to commit -F - is allowed" 0 "$PLAIN_RC"
  assert_exit "fork pin: the shim leaves the 20-hop verdict unchanged" "$PLAIN_RC" "$FORK_RC_20"

  run_shimmed "$fork_diverge" "$FORK20"
  FORKS_DIV=$SPAWN_COUNT
  FORK_RC_DIV=$SPAWN_RC
  run_unshimmed "$fork_diverge" "$FORK20"
  assert_exit "fork pin: divergent chain into a persisted alias exhausts the budget" 2 "$PLAIN_RC"
  assert_exit "fork pin: the shim leaves the divergent verdict unchanged" "$PLAIN_RC" "$FORK_RC_DIV"

  if ((FORKS_10 > 0)); then
    ok "fork pin: git shim active (${FORKS_10} git spawns on the 10-hop persisted chain)"
  else
    bad "fork pin: the git shim never fired — the ceilings below cannot discriminate"
  fi
  if ((FORKS_DIV >= 1)); then
    ok "fork pin: the divergent chain reaches its persisted lookups (${FORKS_DIV} git spawns)"
  else
    bad "fork pin: the divergent chain forked ${FORKS_DIV} times — it never reached a persisted lookup, so its ceiling below is vacuous"
  fi

  if ((FORKS_20 <= 2 * FORKS_10 + 2)); then
    ok "fork pin: forks scale linearly in hops (${FORKS_10} at 10 hops, ${FORKS_20} at 20)"
  else
    bad "fork pin: per-hop fork cost grew with depth — ${FORKS_10} forks at 10 hops but ${FORKS_20} at 20"
  fi

  if ((FORKS_20 <= 30)); then
    ok "fork pin: 20-hop persisted chain stays under 30 forks (${FORKS_20})"
  else
    bad "fork pin: 20-hop persisted chain forked ${FORKS_20} times, over the 30 ceiling"
  fi

  if ((FORKS_DIV <= 16)); then
    ok "fork pin: divergent walk forks per distinct lookup, not per analysis (${FORKS_DIV})"
  else
    bad "fork pin: divergent walk forked ${FORKS_DIV} times, over the 16 ceiling — the per-analysis lookup cache is gone"
  fi
else
  echo "ok: alias-traversal fork pin skipped (git unavailable)"
  PASS=$((PASS + 1))
fi

PSHELL="$TEST_TMPDIR/persisted-shell"
mkdir -p "$PSHELL"
(
  cd "$PSHELL" || exit 1
  git init -q .
  git config user.email t@e.st
  git config user.name t
  git config alias.sc '!git x2'
  git config alias.x2 commit
  git config alias.a '!git a'
  git config alias.ma '!git mb'
  git config alias.mb '!git ma'
) >/dev/null 2>&1

if [[ -d "$PSHELL/.git" ]]; then
  for spec in "git sc -m \"bypass \$b\":2" "git sc -F -:0" "git a:0" "git ma:0"; do
    cmd="${spec%:*}"
    want="${spec##*:}"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$cmd" --arg d "$PSHELL" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      bash "$HOOK" >/dev/null 2>&1
    assert_exit "persisted shell-alias hop: $cmd" "$want" $?
  done
fi

out=$(bash "$HOOK" <<<"$(command_json "git commit -m \"feat: x \$body\"")" 2>&1)
assert_contains "block message names -F -" "$out" '-F -'
assert_contains "block message names the skill" "$out" '/source-control:commit'
assert_contains "block message names the expansion hazard" "$out" 'a backtick the shell expands'

NESTED="$TEST_TMPDIR/nested"
nested_repo() {
  mkdir -p "$1"
  (cd "$1" && git init -q . && git config user.email t@e.st && git config user.name t) >/dev/null 2>&1
}
nested_repo "$NESTED/a"
nested_repo "$NESTED/a/child"
nested_repo "$NESTED/a/child/child"
nested_repo "$NESTED/b"
nested_repo "$NESTED/b/child"
nested_repo "$NESTED/b/child/child"
nested_repo "$NESTED/dot"

if [[ -d "$NESTED/a/.git" && -d "$NESTED/a/child/child/.git" ]]; then
  git -C "$NESTED/a" config alias.a '!git -C child a'
  git -C "$NESTED/a/child" config alias.a '!git -C child a'
  git -C "$NESTED/a/child/child" config alias.a $'commit --allow-empty -m "bypass $b"'
  git -C "$NESTED/b" config alias.a '!git -C child a'
  git -C "$NESTED/b/child" config alias.a '!git -C child a'
  git -C "$NESTED/b/child/child" config alias.a 'commit -F -'
  git -C "$NESTED/dot" config alias.selfdot '!git -C . selfdot'
  git -C "$NESTED/dot" config alias.viadot '!git -C . realcommit'
  git -C "$NESTED/dot" config alias.realcommit $'commit --allow-empty -m "bypass $b"'
  git -C "$NESTED/a/child" config alias.z2 $'commit --allow-empty -m "bypass $b"'
  git -C "$NESTED/b/child" config alias.z2 'commit -F -'

  for spec in \
    "a|git a|2|nested descent reaches the grandchild commit -m" \
    "b|git a|0|nested descent to a canonical grandchild commit" \
    "dot|git selfdot|0|-C . self-reference normalizes to a cycle" \
    "dot|git viadot|2|-C . hop still reaches a real commit -m" \
    "a|git -c alias.z='!git -C child z2' z|2|inline ! descends into a persisted commit -m" \
    "b|git -c alias.z='!git -C child z2' z|0|inline ! descends into a canonical commit"; do
    IFS='|' read -r sub cmd want label <<<"$spec"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$cmd" --arg d "$NESTED/$sub" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
    rc=$?
    ((rc == 124)) && bad "$label: the hook HUNG — no verdict inside the ${HANG_GUARD_SECS}s hang guard" && continue
    assert_exit "$label" "$want" "$rc"
  done
fi

WRAP="$TEST_TMPDIR/wrapper"
nested_repo "$WRAP/outer"
nested_repo "$WRAP/outer/child"
nested_repo "$WRAP/outer/git"
nested_repo "$WRAP/outer/git/child"
nested_repo "$WRAP/outer/other"
nested_repo "$WRAP/outer/other/child"
nested_repo "$WRAP/outer/has space"

if [[ -d "$WRAP/outer/child/.git" && -d "$WRAP/outer/git/child/.git" ]]; then
  git -C "$WRAP/outer/child" config alias.p $'commit --allow-empty -m "bypass $b"'
  git -C "$WRAP/outer/git/child" config alias.p 'commit -F -'

  MSYS_NO_PATHCONV=1 jq -n --arg c "env -u -C git -c alias.a='!git -C child p' a" --arg d "$WRAP/outer" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  ((rc == 124)) && bad "env -u swallows -C: the hook HUNG — no verdict inside the ${HANG_GUARD_SECS}s hang guard"
  ((rc == 124)) || assert_exit "env -u swallows -C, so the wrapper option is not git's -C" 2 "$rc"

  git -C "$WRAP/outer/git/child" config alias.q $'commit --allow-empty -m "bypass $b"'
  MSYS_NO_PATHCONV=1 jq -n --arg c "git -C git -c alias.a='!git -C child q' a" --arg d "$WRAP/outer" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
  assert_exit "git's own -C still relocates the alias lookup" 2 "$?"
fi

wrapper_cd_case() {
  local label="$1" command="$2" expected="$3" rc
  MSYS_NO_PATHCONV=1 jq -n --arg c "$command" --arg d "$WRAP/outer" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  ((rc == 124)) && bad "$label: the hook HUNG — no verdict inside the ${HANG_GUARD_SECS}s hang guard" && return
  assert_exit "$label" "$expected" "$rc"
}

if [[ -d "$WRAP/outer/other/.git" ]]; then
  git -C "$WRAP/outer/other" config alias.a $'commit --allow-empty -m "bypass $b"'
  git -C "$WRAP/outer/other" config alias.k 'commit -F -'
  git -C "$WRAP/outer" config alias.a 'commit -F -'
  git -C "$WRAP/outer" config alias.k $'commit --allow-empty -m "bypass $b"'
  [[ -d "$WRAP/outer/has space/.git" ]] &&
    git -C "$WRAP/outer/has space" config alias.a $'commit --allow-empty -m "bypass $b"'

  wrapper_cd_case "env -C moves git, so the alias lookup follows" \
    "env -C other git a" 2
  wrapper_cd_case "env --chdir=DIR (attached long form) moves git" \
    "env --chdir=other git a" 2
  wrapper_cd_case "env --chdir DIR (separated long form) moves git" \
    "env --chdir other git a" 2
  wrapper_cd_case "env -CDIR (attached short form) moves git" \
    "env -Cother git a" 2
  wrapper_cd_case "env -vC DIR (clustered short form) moves git" \
    "env -vC other git a" 2
  wrapper_cd_case "env -u NAME before the chdir does not consume it" \
    "env -uFOO -C other git a" 2
  wrapper_cd_case "repeated env -C is last-wins, not cumulative (lands in cwd)" \
    "env -C other -C . git a" 0
  wrapper_cd_case "repeated env -C is last-wins (lands in the LAST operand)" \
    "env -C . -C other git a" 2
  wrapper_cd_case "a canonical commit through the same wrapper stays allowed" \
    "env -C other git k" 0
  wrapper_cd_case "a NAME=value operand ends option parsing" \
    "env FOO=1 -C other git a" 0
  wrapper_cd_case "sudo -D moves git, so the alias lookup follows" \
    "sudo -D other git a" 2
  wrapper_cd_case "sudo --chdir=DIR moves git" \
    "sudo --chdir=other git a" 2
  wrapper_cd_case "sudo -DDIR (attached) moves git" \
    "sudo -Dother git a" 2
  wrapper_cd_case "sudo -C is close-from, not a chdir" \
    "sudo -C 3 git k" 2

  wrapper_cd_case "a chdir before -S survives the splice restart" \
    "env -C other -S 'git a'" 2
  wrapper_cd_case "a wrapper chdir into a directory with a space" \
    "env -C 'has space' git a" 2
  wrapper_cd_case "env -0 does not hide the chdir from the peel" \
    "env -0 -C other git a" 2
  wrapper_cd_case "env -vi0C (three-flag cluster) still yields the chdir" \
    "env -vi0C other git a" 2
fi

if [[ -d "$WRAP/outer/other/child/.git" ]]; then
  git -C "$WRAP/outer/other/child" config alias.a $'commit --allow-empty -m "bypass $b"'
  git -C "$WRAP/outer/other/child" config alias.c 'commit -F -'

  wrapper_cd_case "env -C composes ahead of git's own -C" \
    "env -C other git -C child a" 2
  wrapper_cd_case "same composition, canonical leaf, stays allowed" \
    "env -C other git -C child c" 0
fi

if [[ -d "$WRAP/outer/other/.git" ]]; then
  nested_repo "$WRAP/outer/other/child"
  nested_repo "$WRAP/outer/other/child/child"
fi

if [[ -d "$WRAP/outer/other/child/child/.git" ]]; then
  git -C "$WRAP/outer/other" config alias.p '!git -C child p'
  git -C "$WRAP/outer/other/child" config alias.p '!git -C child p'
  git -C "$WRAP/outer/other/child/child" config alias.p $'commit --allow-empty -m "bypass $b"'
  git -C "$WRAP/outer/other" config alias.s '!git -C child s'
  git -C "$WRAP/outer/other/child" config alias.s '!git -C child s'
  git -C "$WRAP/outer/other/child/child" config alias.s 'commit -F -'

  wrapper_cd_case "wrapper chdir survives a persisted ! alias descent" \
    "env -C other git p" 2
  wrapper_cd_case "same descent, canonical leaf, stays allowed" \
    "env -C other git s" 0
  wrapper_cd_case "wrapper chdir is not applied twice on the git-alias splice" \
    "env -C other git -c alias.z='!git -C child p' z" 2
  wrapper_cd_case "same splice, canonical leaf, stays allowed" \
    "env -C other git -c alias.z='!git -C child s' z" 0
fi

TOPLEVEL="$TEST_TMPDIR/toplevel"
nested_repo "$TOPLEVEL/outer"
nested_repo "$TOPLEVEL/outer/child"
mkdir -p "$TOPLEVEL/outer/sub/child"
nested_repo "$TOPLEVEL/canon"
nested_repo "$TOPLEVEL/canon/child"
mkdir -p "$TOPLEVEL/canon/sub"

if [[ -d "$TOPLEVEL/outer/child/.git" ]]; then
  git -C "$TOPLEVEL/outer" config alias.a '!git -C child a'
  git -C "$TOPLEVEL/outer/child" config alias.a $'commit --allow-empty -m "bypass $b"'
  git -C "$TOPLEVEL/canon" config alias.a '!git -C child a'
  git -C "$TOPLEVEL/canon/child" config alias.a 'commit -F -'
  for spec in \
    "outer/sub|2|! body resolves from the outer repo top level, not the subdir" \
    "canon/sub|0|same shape, canonical grandchild commit (allowed)"; do
    IFS='|' read -r sub want label <<<"$spec"
    MSYS_NO_PATHCONV=1 jq -n --arg c "git a" --arg d "$TOPLEVEL/$sub" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
    assert_exit "$label" "$want" $?
  done
fi

SYMDIR="$TEST_TMPDIR/symlink"
mkdir -p "$SYMDIR/base"
nested_repo "$SYMDIR/target"
mkdir -p "$SYMDIR/target/child"
MSYS=winsymlinks:nativestrict ln -s "$SYMDIR/target/child" "$SYMDIR/base/link" 2>/dev/null
sym_top=""
if [[ -L "$SYMDIR/base/link" ]]; then
  sym_top=$(git -C "$SYMDIR/base/link/.." rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
fi
if [[ -n "$sym_top" ]] && [[ "$(cd -P "$SYMDIR/target" && pwd -P)" == "$(cd -P "$sym_top" && pwd -P)" ]]; then
  git -C "$SYMDIR/target" config alias.a $'commit --allow-empty -m "bypass $b"'
  git -C "$SYMDIR/target" config alias.c 'commit -F -'
  for spec in "git -C link/.. a|2|symlinked parent: guard follows git into the link target" \
    "git -C link/.. c|0|symlinked parent: canonical commit there is allowed"; do
    IFS='|' read -r cmd want label <<<"$spec"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$cmd" --arg d "$SYMDIR/base" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
    assert_exit "$label" "$want" $?
  done
else
  echo "ok: symlinked-parent fixture skipped (this platform's git does not resolve link/.. through the symlink)"
  PASS=$((PASS + 1))
fi

DOTS="$TEST_TMPDIR/dots"
nested_repo "$DOTS"
mkdir -p "$DOTS/sub"

if [[ -d "$DOTS/.git" ]]; then
  git -C "$DOTS" config alias.selfdeep '!git -C ./././. selfdeep'
  git -C "$DOTS" config alias.livedot '!git -C . realdot'
  git -C "$DOTS" config alias.realdot $'commit --allow-empty -m "bypass $b"'
  git -C "$DOTS" config alias.up '!git -C sub/.. realup'
  git -C "$DOTS" config alias.realup $'commit --allow-empty -m "bypass $b"'
  git -C "$DOTS" config alias.upcanon '!git -C sub/.. canonup'
  git -C "$DOTS" config alias.canonup 'commit -F -'
  for spec in \
    "git selfdeep|0|-C ./././. collapses to a cycle (no . cancelling needed)" \
    "git livedot|2|-C . hop still reaches a real commit -m" \
    "git up|2|-C sub/.. reaches commit -m (not lexically shortcut)" \
    "git upcanon|0|-C sub/.. canonical commit stays allowed (no blanket .. refusal)"; do
    IFS='|' read -r cmd want label <<<"$spec"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$cmd" --arg d "$DOTS" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
    rc=$?
    ((rc == 124)) && bad "$label: the hook HUNG — no verdict inside the ${HANG_GUARD_SECS}s hang guard" && continue
    assert_exit "$label" "$want" "$rc"
  done
fi

TRAIL="$TEST_TMPDIR/trailing"
nested_repo "$TRAIL/cur"
nested_repo "$TRAIL/safe"

if [[ -d "$TRAIL/cur/.git" && -d "$TRAIL/safe/.git" ]]; then
  git -C "$TRAIL/cur" config alias.b $'commit --allow-empty -m "bypass $b"'
  for spec in \
    "git commit -C HEAD|0|commit -C HEAD is --reuse-message, not a directory" \
    "git -C $TRAIL/safe commit -F -|0|a real leading -C global still resolves"; do
    IFS='|' read -r cmd want label <<<"$spec"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$cmd" --arg d "$TRAIL/cur" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
    rc=$?
    ((rc == 124)) && bad "$label: the hook HUNG — no verdict inside the ${HANG_GUARD_SECS}s hang guard" && continue
    assert_exit "$label" "$want" "$rc"
  done
fi

GLOB="$TEST_TMPDIR/globals"
mkdir -p "$GLOB/outside"
nested_repo "$GLOB/repo"

if [[ -d "$GLOB/repo/.git" ]]; then
  for spec in \
    "!git commit -F -|0|--git-dir/--work-tree: canonical commit through a ! alias is allowed" \
    "!git commit -m \\\"x \$y\\\"|2|--git-dir/--work-tree: an expanding -m through a ! alias still blocks"; do
    IFS='|' read -r body want label <<<"$spec"
    MSYS_NO_PATHCONV=1 jq -n \
      --arg c "git --git-dir=$GLOB/repo/.git --work-tree=$GLOB/repo -c alias.a=\"$body\" a" \
      --arg d "$GLOB/outside" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
    rc=$?
    ((rc == 124)) && bad "$label: the hook HUNG — no verdict inside the ${HANG_GUARD_SECS}s hang guard" && continue
    assert_exit "$label" "$want" "$rc"
  done

  git -C "$GLOB/repo" config alias.b $'commit --allow-empty -m "x $y"'
  MSYS_NO_PATHCONV=1 jq -n \
    --arg c "git --git-dir=$GLOB/repo/.git --work-tree=$GLOB/repo -c alias.a=b a" \
    --arg d "$GLOB/outside" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  if ((rc == 124)); then
    bad "persisted lookup with locating globals: the hook HUNG"
  else
    assert_exit "persisted lookup replays --git-dir/--work-tree (blocks multi-line -m via alias chain)" 2 "$rc"
  fi
fi

CHOKE="$TEST_TMPDIR/choke"
mkdir -p "$CHOKE/outside"
nested_repo "$CHOKE/repo"
if [[ -d "$CHOKE/repo/.git" ]]; then
  git -C "$CHOKE/repo" config alias.a b
  git -C "$CHOKE/repo" config alias.b $'commit --allow-empty -m "x $y"'
  choke_run() {
    local label="$1" cmd="$2" want="$3" rc
    MSYS_NO_PATHCONV=1 jq -n --arg c "$cmd" --arg d "$CHOKE/outside" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
    rc=$?
    ((rc == 124)) && bad "$label: HUNG" && return
    assert_exit "$label" "$want" "$rc"
  }
  choke_run "#1553: persisted chain under locating globals (blocked)" \
    "git --git-dir=$CHOKE/repo/.git --work-tree=$CHOKE/repo --git-dir=$CHOKE/repo/.git a" 2
  choke_run "R8-2: inline alias into persisted multi-line -m (blocked)" \
    "git --git-dir=$CHOKE/repo/.git --work-tree=$CHOKE/repo -c alias.a=b a" 2
  choke_run "R8-3: ! body establishes repo via -C, canonical -F - (allowed)" \
    "git -c alias.a='!git -C $CHOKE/repo commit --allow-empty -F -' a" 0
  choke_run "R8-3 twin: same shape with multi-line -m (blocked)" \
    "git -c alias.a='!git -C $CHOKE/repo commit --allow-empty -m \"x \$y\"' a" 2
  choke_run "F3: --git-dir/--work-tree ! alias to canonical commit (allowed)" \
    "git --git-dir=$CHOKE/repo/.git --work-tree=$CHOKE/repo -c alias.a='!git commit -F -' a" 0
  choke_run "F3 twin: same outer shape with multi-line -m in body (blocked)" \
    "git --git-dir=$CHOKE/repo/.git --work-tree=$CHOKE/repo -c alias.a='!git commit -m \"x \$y\"' a" 2
fi

LAUNCH="$TEST_TMPDIR/launchdir"
launch_tree() {
  nested_repo "$1/work"
  nested_repo "$1/work/child"
  nested_repo "$1/work/sub/child"
  mkdir -p "$1/out"
  nested_repo "$1/out/child"
  git -C "$1/out/child" config alias.p "$2"
  git -C "$1/work/child" config alias.p "$3"
  git -C "$1/work/sub/child" config alias.p "$4"
}
launch_tree "$LAUNCH/a" $'commit --allow-empty -m "bypass $b"' 'commit -F -' $'commit --allow-empty -m "bypass $b"'
launch_tree "$LAUNCH/b" 'commit -F -' $'commit --allow-empty -m "bypass $b"' 'commit -F -'

if [[ -d "$LAUNCH/a/out/child/.git" && -d "$LAUNCH/b/out/child/.git" ]]; then
  launch_body='!unset GIT_DIR GIT_WORK_TREE; git -C child p'
  for spec in \
    "a|out|2|caller outside the work tree: ! body resolves the CALLER's child repo" \
    "b|out|0|caller outside: canonical commit in the caller's child repo is allowed" \
    "a|work/sub|0|caller inside the work tree: ! body still starts at the top level" \
    "b|work/sub|2|caller inside: top-level child's commit -m still blocks"; do
    IFS='|' read -r tree sub want label <<<"$spec"
    MSYS_NO_PATHCONV=1 jq -n \
      --arg c "git --git-dir=$LAUNCH/$tree/work/.git --work-tree=$LAUNCH/$tree/work -c alias.a='$launch_body' a" \
      --arg d "$LAUNCH/$tree/$sub" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
    rc=$?
    ((rc == 124)) && bad "$label: the hook HUNG — no verdict inside the ${HANG_GUARD_SECS}s hang guard" && continue
    assert_exit "$label" "$want" "$rc"
  done
fi

run_pwsh() {
  local label="$1" command="$2" expected="$3"
  expect "$label" "$expected" --tool PowerShell --command "$command"
}
run_pwsh "PS: canonical here-string | git commit -F - (allowed)" \
  "$(printf '%s\n%s\n%s' "@'" "feat: x" "'@ | git commit -F -")" 0
run_pwsh "PS: git commit -m @' here-string with \$ and a backtick (allowed)" \
  "$(printf '%s\n%s\n%s' "git commit -m @'" "feat: x \`y\` \$z" "'@")" 0
run_pwsh "PS: git commit -m @\" here-string (blocked — uninspectable, expanding)" \
  "$(printf '%s\n%s\n%s' "git commit -m @\"" "feat: x" "\"@")" 2
run_pwsh "PS: git commit -m single-line literal (allowed)" \
  "git commit -m 'feat: x'" 0
run_pwsh "PS: single-quoted -m with backticks and \$ (allowed)" \
  "git commit -m 'fix: rename \`foo\` and \$total'" 0
run_pwsh "PS: doubled quote in a single-quoted -m (allowed)" \
  "git commit -m 'it''s \$5'" 0
run_pwsh "PS: multi-line double-quoted plain -m (allowed)" \
  "git commit -m \"feat: x${NL}${NL}body\"" 0
run_pwsh "PS: double-quoted -m with backtick escapes (blocked, #6464)" \
  "git commit -m \"fix: rename \`foo\` and \`bar\` to \`new\` for \`\$total\"" 2
run_pwsh "PS: double-quoted -m with a \$ (blocked)" \
  "git commit -m \"has \$x\"" 2
run_pwsh "PS: git commit --amend (allowed — exempt)" "git commit --amend" 0
run_pwsh "PS: git status (allowed — not a commit)" "git status" 0

PS_UNPARSABLE_BACKTICK="$(printf 'git commit -m x `\n --cleanup=verbatim')"
PS_UNPARSABLE_HERESTRING="$(printf '%s\n%s\n%s' "@'" "body" "'X ; git commit -m sneaky")"
PS_UNPARSABLE_EXPANDABLE_HERESTRING="$(printf '%s\n%s\n%s' "git commit -m @\"" "msg \$(Get-Date)" "\"@")"
run_pwsh "PS: backtick-continued commit (deferred — classifier rc 2)" \
  "$PS_UNPARSABLE_BACKTICK" 0
run_pwsh "PS: unbalanced here-string hiding a -m commit (deferred — classifier rc 2)" \
  "$PS_UNPARSABLE_HERESTRING" 0
run_pwsh "PS: expandable here-string -m value carrying a subexpression (blocked: read as written)" \
  "$PS_UNPARSABLE_EXPANDABLE_HERESTRING" 2
# `""` inside a double-quoted span is an escaped quote, so the span goes on.
# shellcheck disable=SC2016  # the PowerShell `$env:` text must reach the guard literally
run_pwsh "PS: -m with an escaped \"\" before a \$ (blocked)" \
  'git commit -m "say ""hi"" $env:USERNAME"' 2
run_pwsh "PS: -m with an escaped \"\" and nothing expanding (allowed)" \
  'git commit -m "say ""hi"" there"' 0

run_pwsh "PS: a commented here-string opener is refused here, not deferred (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output x # @\"" "git commit -m x" "\"@ fine\"")" 2
run_pwsh "PS: the @' spelling of the commented opener (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output x # @'" "git commit -m x" "'@ fine'")" 2
run_pwsh "PS: a commented opener behind a {} construct is refused (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output {x} # @\"" "git commit -m x" "\"@ fine\"")" 2
run_pwsh "PS: a commented opener behind an iex is refused (blocked)" \
  "$(printf '%s\n%s\n%s' "iex a; Write-Output x # @\"" "git commit -m x" "\"@ fine\"")" 2
run_pwsh "PS: a commented opener behind a {} with no git in it (blocked, accepted over-block)" \
  "$(printf '%s\n%s\n%s' "Write-Output {x} # @\"" "hello" "\"@")" 2
run_pwsh "PS: a # inside a quoted string before a real opener (blocked, accepted over-block)" \
  "$(printf '%s\n%s\n%s' "Write-Output \"#1\" @\"" "hello" "\"@")" 2
run_pwsh "PS: a here-string body containing a # (allowed)" \
  "$(printf '%s\n%s\n%s' "Write-Output @'" "release # 1" "'@")" 0
run_pwsh "PS: a trailing comment on an ordinary commit (allowed)" "git commit -m x # ok" 0

run_pwsh "PS: a quote on a confirmed opener prefix is refused here, not deferred (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output \"x\" @\"" "git commit -m x" "\"@")" 2
run_pwsh "PS: a backslash on a confirmed opener prefix is refused here, not deferred (blocked)" \
  "$(printf '%s\n%s\n%s' "Write-Output C:\\x @\"" "git commit -m x" "\"@")" 2
run_pwsh "PS: a <# earlier than a confirmed opener is refused here, not deferred (blocked)" \
  "$(printf '%s\n%s\n%s\n%s' "<# hi" "Write-Output @\"" "git commit -m x" "\"@")" 2
run_pwsh "PS: a bare CR is refused here, not deferred (blocked)" \
  $'Write-Output hi\rgit commit -m x' 2
run_pwsh "PS: CRLF canonical verbatim commit here-string (allowed)" \
  "$(printf '%s\r\n%s\r\n%s' "@'" "fix: subject" "'@ | git commit -F -")" 0

run_sibling() {
  local label="$1" sibling="$2" command="$3"
  guard_invoke --hook "$HOOK_DIR/$sibling.sh" --tool PowerShell --command "$command" --merge-stderr
  assert_exit "$label" 2 "$GUARD_RC"
  assert_contains "$label: for the unparsable reason" "$GUARD_OUT" "cannot be parsed with confidence"
}
for sibling in block-dangerous-git block-no-verify; do
  run_sibling "PS: backtick-continued commit still blocked by $sibling" \
    "$sibling" "$PS_UNPARSABLE_BACKTICK"
  run_sibling "PS: unbalanced here-string commit still blocked by $sibling" \
    "$sibling" "$PS_UNPARSABLE_HERESTRING"
  run_sibling "PS: expandable here-string -m commit still blocked by $sibling" \
    "$sibling" "$PS_UNPARSABLE_EXPANDABLE_HERESTRING"
done

for command in "$PS_UNPARSABLE_BACKTICK" "$PS_UNPARSABLE_HERESTRING"; do
  for hook in block-noncanonical-commit block-dangerous-git block-no-verify; do
    env CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ENABLED=false \
      CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_ENABLED=false \
      bash "$HOOK_DIR/$hook.sh" <<<"$(pwsh_command_json "$command")" >/dev/null 2>&1
    assert_exit "residual: $hook allows the rc-2 commit with both siblings disabled" 0 "$?"
  done
done

# The PowerShell block message shows the here-string form, not a Bash heredoc.
# shellcheck disable=SC2016  # literal command text the guard reads
psout=$(bash "$HOOK" <<<"$(pwsh_command_json 'git commit -m "has $x"')" 2>&1)
assert_contains "PS block message shows the here-string form" "$psout" "'@ | git commit -F -"
assert_absent "PS block message omits the Bash heredoc" "$psout" "<<'EOF'"

nul_rc=0
bash "$HOOK" <<<"$(jq -n '{tool_name:"Bash",tool_input:{command:("git commit -m ok" + ([0]|implode))}}')" >/dev/null 2>&1 || nul_rc=$?
assert_exit "NUL in command (blocked)" 2 "$nul_rc"

PARSE_CREATIONS=7
PARSE_EXECVE=2
strace_census() {
  local log="$TEST_TMPDIR/strace.log"
  CENSUS_RC=0
  env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR= \
    strace -f -e trace=clone,clone3,fork,vfork,execve -o "$log" \
    bash "$HOOK_DIR/run-guards.sh" "$2" <<<"$1" >/dev/null 2>&1 || CENSUS_RC=$?
  CENSUS_CREATIONS=$(grep -E '(clone3?|v?fork)\(' "$log" | grep -v CLONE_THREAD | grep -cE '= [0-9]+$|<unfinished \.\.\.>$')
  CENSUS_EXECVE=$(grep -cE '(execve\(|<\.\.\. execve resumed>).* = 0$' "$log")
}
guard_share() {
  local payload noop_cre noop_exe
  payload="$(command_json "$1")"
  strace_census "$payload" "$TEST_TMPDIR/noop-guard.sh"
  noop_cre=$CENSUS_CREATIONS
  noop_exe=$CENSUS_EXECVE
  strace_census "$payload" block-noncanonical-commit.sh
  SHARE_RC=$CENSUS_RC
  SHARE_CREATIONS=$((CENSUS_CREATIONS - noop_cre))
  SHARE_EXECVE=$((CENSUS_EXECVE - noop_exe))
}
if command -v strace >/dev/null 2>&1 && strace -o /dev/null -e trace=execve true 2>/dev/null; then
  printf '#!/usr/bin/env bash\nexit 0\n' >"$TEST_TMPDIR/noop-guard.sh"

  guard_share 'git status --short'
  benign_creations=$SHARE_CREATIONS
  assert_exit "strace: dispatched benign command exits 0" 0 "$SHARE_RC"
  assert_eq "strace: guard's own process creations on a benign Bash call are one parse" "$PARSE_CREATIONS" "$SHARE_CREATIONS"
  assert_eq "strace: guard's own execve count on a benign Bash call is one parse" "$PARSE_EXECVE" "$SHARE_EXECVE"

  guard_share "git commit -m 'feat: x'"
  assert_exit "strace: dispatched single-line -m exits 0" 0 "$SHARE_RC"
  assert_eq "strace: a single-line -m creates no more processes than a benign call" \
    "$benign_creations" "$SHARE_CREATIONS"

  guard_share "git commit -m \"feat: x \$body\""
  assert_exit "strace: dispatched multi-line -m still blocks under the tracer" 2 "$SHARE_RC"
  assert_eq "strace: a blocked multi-line -m is two creations over benign (the sequencer probe only)" \
    $((benign_creations + 2)) "$SHARE_CREATIONS"
  assert_eq "strace: a blocked multi-line -m is one execve over the parse (git rev-parse)" \
    $((PARSE_EXECVE + 1)) "$SHARE_EXECVE"

  guard_share "git -c alias.y='!git status' y"
  alias_creations=$SHARE_CREATIONS
  assert_exit "strace: dispatched benign ! alias exits 0" 0 "$SHARE_RC"

  guard_share "git -c alias.y='!git status' y --short -- ."
  assert_exit "strace: dispatched ! alias with trailing args exits 0" 0 "$SHARE_RC"
  assert_eq "strace: trailing ! alias arguments add no process creations" \
    "$alias_creations" "$SHARE_CREATIONS"
else
  echo "ok: process-creation pins skipped (no working strace on this host)"
fi

expect_both "dispatched parity: an expanding -m blocks" 2 \
  --command "git commit -m \"feat: x \$body\""
expect_both "dispatched parity: single-line -m allowed" 0 \
  --command "git commit -m 'feat: x'"
expect_both "dispatched parity: bare git commit allowed" 0 --command "git commit"
expect_both "dispatched parity: \$'…' multi-line decodes and passes" 0 \
  --command "git commit -m \$'feat: x\nbody'"
expect_both "dispatched parity: PowerShell double-quoted -m with a backtick blocks" 2 \
  --tool PowerShell --lib lib/powershell/ps-command.sh \
  --command "git commit -m \"fix: \`foo\`\""
expect_both "dispatched parity: PowerShell canonical -F - allowed" 0 \
  --tool PowerShell --lib lib/powershell/ps-command.sh \
  --command "$(printf '%s\n%s\n%s' "@'" "feat: x" "'@ | git commit -F -")"

PREPO="$TEST_TMPDIR/personal-layer"
git init -q -b main "$PREPO"
git -C "$PREPO" config core.excludesFile "$TEST_TMPDIR/no-global-excludes"
mkdir -p "$PREPO/docs/conventions"
printf '%s\n' "subject_pattern: '^[A-Z]+-[0-9]+: .+'" >"$PREPO/docs/conventions/source-control.local.yaml"
printf '%s\n' 'docs/conventions/**/*.local.*' >"$PREPO/.gitignore"
assert_eq "personal layer: the fixture's pattern resolves" '^[A-Z]+-[0-9]+: .+' \
  "$(sh "$HOOK_DIR/resolve-convention-pattern.sh" "$PREPO" subject_pattern 2>/dev/null)"
expect "personal layer: canonical -F - with an off-pattern subject allowed (content is not this guard's)" 0 \
  --command $'git commit -F - <<\'EOF\'\njunk subject\nEOF' --cwd "$PREPO" -- "CLAUDE_PROJECT_DIR=$PREPO"
expect "personal layer: an expanding -m with an on-pattern subject still blocked" 2 \
  --command "git commit -m \"ABC-1: x \$body\"" --cwd "$PREPO" -- "CLAUDE_PROJECT_DIR=$PREPO"

report
