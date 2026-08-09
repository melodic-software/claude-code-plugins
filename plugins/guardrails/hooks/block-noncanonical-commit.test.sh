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
# NARROWED (0.20.0, #2021): only a `-m` whose message ACTUALLY carries a newline
# blocks — that is the cross-shell mangling hazard. Single-line `-m`, bare
# `git commit`, and repeated single-line `-m` paragraphs all pass. `NL` embeds a
# real newline where the fixture's own quoting cannot use the $'…' spelling.
NL=$'\n'
run "git commit -m multi-line (blocked)" "git commit -m 'feat: x${NL}body'" 2
run "git commit -m multi-line via \$'…' (blocked — tokenizer decodes ANSI-C)" \
  "git commit -m \$'feat: x\nbody'" 2
run "git commit -m single-line (allowed — no newline, no mangling hazard)" \
  "git commit -m 'feat: x'" 0
run "git commit -am multi-line (bundled cluster, blocked)" "git commit -am 'feat: x${NL}body'" 2
run "git commit -am single-line (allowed)" "git commit -am 'feat: x'" 0
run "git commit -m<attached> multi-line (blocked)" "git commit -m'feat: x${NL}body'" 2
run "git commit --message=<attached> multi-line (blocked)" \
  "git commit --message='feat: x${NL}body'" 2
run "git commit --message <separated> multi-line (blocked)" \
  "git commit --message 'feat: x${NL}body'" 2
run "git commit --message <separated> single-line (allowed)" \
  "git commit --message 'feat: x'" 0
# git's parse-options accepts any UNIQUE prefix of a long option, and --message
# is git commit's only m-initial long option, so every prefix from --m up to
# one letter short of the full spelling parses as --message (verified on git
# 2.55) — the abbreviated spellings must hit the same gate in both the
# =-attached and the separated form.
run "git commit --mess=<abbreviated attached> multi-line (blocked)" \
  "git commit --mess='feat: x${NL}body'" 2
run "git commit --mess=<abbreviated attached> single-line (allowed)" \
  "git commit --mess='feat: x'" 0
run "git commit --mess <abbreviated separated> multi-line (blocked)" \
  "git commit --mess 'feat: x${NL}body'" 2
run "git commit --mess <abbreviated separated> single-line (allowed)" \
  "git commit --mess 'feat: x'" 0
run "git commit --m=<shortest abbreviation> multi-line (blocked)" \
  "git commit --m='feat: x${NL}body'" 2
run "git commit --m=<shortest abbreviation> single-line (allowed)" \
  "git commit --m='feat: x'" 0
run "git commit --m <shortest abbreviation, separated> multi-line (blocked)" \
  "git commit --m 'feat: x${NL}body'" 2
run "git commit --m <shortest abbreviation, separated> single-line (allowed)" \
  "git commit --m 'feat: x'" 0
run "git commit -m multi-line with --trailer (still blocked — trailer is not the mechanic)" \
  "git commit -m 'feat: x${NL}body' --trailer 'Co-Authored-By: X <x@y.z>'" 2
run "repeated single-line -m (allowed — git itself joins the paragraphs)" \
  "git commit -m 'feat: x' -m 'body'" 0
run "bare git commit (no -m, allowed — opens EDITOR, no mangling hazard)" "git commit" 0
run "git commit -a (no message source, allowed)" "git commit -a" 0

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
# commit, so exempting it unconditionally would let a multi-line `--no-edit -m`
# straight past.
run "git commit --no-edit -m multi-line (blocked — --no-edit is not an amend)" \
  "git commit --no-edit -m 'subject${NL}body'" 2
run "git commit --amend (allowed)" "git commit --amend" 0
run "git commit --amend -m multi-line (allowed — amending is exempt)" \
  "git commit --amend -m 'subject${NL}body'" 0
run "git commit -C HEAD (allowed)" "git commit -C HEAD" 0
run "git commit --reuse-message=HEAD (allowed)" "git commit --reuse-message=HEAD" 0
run "git commit --fixup HEAD (allowed)" "git commit --fixup HEAD" 0
run "git commit --squash=HEAD (allowed)" "git commit --squash=HEAD" 0
run "git commit -F msg.txt (path, allowed)" "git commit -F msg.txt" 0
run "git commit --file=msg.txt (path, allowed)" "git commit --file=msg.txt" 0

# --- top-level git options must not be confused with commit options ----------
# `-c` BEFORE the subcommand is config; only after `commit` is it --reedit.
run "git -c user.name=x commit -m multi-line (config, still blocked)" \
  "git -c user.name=x commit -m 'feat: x${NL}body'" 2
run "git -c user.name=x commit -F - (config, allowed)" \
  "git -c user.name=x commit -F -" 0

# --- inline git aliases are expanded before the subcommand verdict -----------
# `git -c alias.c=commit c -m x` commits. Without expansion the subcommand reads
# as `c`, not `commit`, and the guard waves the whole thing through. Blocked
# terminals carry a REAL newline in the `-m` message (the narrowed hazard);
# expansions embed it inside double quotes, since the alias splitter does not
# decode \$'…'.
run "inline git alias to a multi-line commit -m (blocked)" \
  "git -c alias.c=commit c -m 'bypass${NL}body'" 2
run "inline git alias carrying a multi-line -m in the expansion (blocked)" \
  "git -c alias.ci='commit -m \"x${NL}y\"' ci" 2
run "inline shell alias (leading !) to a multi-line commit -m (blocked)" \
  "git -c alias.sh='!git commit -m \"x${NL}y\"' sh" 2
run "inline git alias to a single-line commit -m (allowed)" \
  "git -c alias.c=commit c -m bypass" 0
run "inline git alias to a canonical commit (allowed)" \
  "git -c alias.c=commit c -F -" 0
run "inline alias to an unrelated subcommand (allowed)" \
  "git -c alias.st=status st" 0
# git applies the LAST -c value for a key; taking the first would let a decoy
# earlier value expanding to a harmless subcommand mask the real one.
run "last inline alias value wins (blocked)" \
  "git -c alias.c=status -c alias.c=commit c -m 'x${NL}y'" 2
run "last inline alias value wins (allowed when the last is harmless)" \
  "git -c alias.c=commit -c alias.c=status c -m 'x${NL}y'" 0

# --- #964: git chains aliases — re-expansion recurses to the commit -----------
# git expands an alias whose first word is itself an alias, so a non-canonical
# commit reached through a SECOND hop must still block. Command-line globals ride
# into each hop (so a second-hop --config-env alias is refused by shape), and the
# recursion stops on git's own alias-loop.
run "#964 case C: two-hop inline chain to a multi-line commit -m (blocked)" \
  "git -c alias.c=x -c alias.x='commit -m \"bypass${NL}b\"' c" 2
run "#964 H1: inline first hop, --config-env second hop (blocked by shape)" \
  "git -c alias.c=x --config-env=alias.x=AV c" 2 "AV=commit"
run "#964 three-hop inline chain to a multi-line commit -m (blocked)" \
  "git -c alias.a=b -c alias.b=c -c alias.c='commit -m \"bypass${NL}b\"' a" 2
run "#964 .command-spelled second hop to a multi-line commit -m (blocked)" \
  "git -c alias.c=x -c alias.x.command='commit -m \"bypass${NL}b\"' c" 2
# Benign controls — a two-hop chain to the canonical -F - form still ALLOWS, and
# an alias cycle terminates (git's alias-loop stop) and allows without hanging.
run "#964 benign two-hop chain to canonical commit -F - (allowed)" \
  "git -c alias.c=x -c alias.x='commit -F -' c" 0
run "#964 alias cycle terminates and allows (no hang)" \
  "git -c alias.a=b -c alias.b=a a" 0
# A `!` shell alias runs in a NEW git process whose alias-loop guard starts
# empty, so a body that re-invokes a name from the outer chain is re-expanded
# there — the reparse must not inherit the outer chain's seen-set.
run "#964 shell-alias body re-invoking the outer chain name (blocked)" \
  "git -c alias.a='!git -c alias.a=\"commit --allow-empty -m \\\"bypass${NL}b\\\"\" a' a" 2
run "#964 shell-alias re-invocation, canonical -F - twin (allowed)" \
  "git -c alias.a='!git -c alias.a=\"commit -F -\" a' a" 0

# --- alias-chain traversal stays proportional to the chain's LENGTH ------------
# Each hop re-checks BOTH alias spellings, so re-expansion branches 2x per hop
# unless equivalent states collapse: before the traversal bounds an 8-hop chain
# defining both spellings cost 14.6s here (each leaf forked a `git config`), and
# every further hop doubled it.
#
# The BOUNDEDNESS claim is carried by the EXIT CODES, not by a clock. A 20-hop
# dual-spelling chain exiting 0 proves the walk stayed inside the hook's
# HOOK_ALIAS_WORK_MAX re-expansion cap, because a collapse regression overruns
# that cap and exits 2 naming the ceiling — which the divergent case below
# asserts directly. The hook states the same principle where it sets that cap —
# "The ceiling counts ANALYSES rather than seconds, because a wall clock is
# host- and command-length-dependent."
#
# A wall-clock ceiling here contradicted that and flaked on a loaded host: the
# divergent-spelling case (the slowest of these, because exhausting the budget is
# the point) measured 26.9s against the old 30s ceiling on Windows Git Bash
# (2026-08-09), so ordinary background load turned a correctly-bounded walk into
# a bogus "traversal is not bounded" failure. `timeout` therefore survives only
# as a HANG GUARD, so a non-terminating regression fails the suite instead of
# wedging it — set an order of magnitude clear of that measured worst case, well
# out of reach of load noise. It is not an assertion, and nothing below reads a
# non-timeout as evidence of boundedness.
HANG_GUARD_SECS=300

# run_guarded <label> <command> <expected-exit>: `timeout` reports 124 when the
# hang guard fires, which must read as the hang it is rather than as an
# unexpected exit code. cwd is pinned to a directory that is no repository, so
# an in-progress merge/rebase wherever the suite happens to run cannot silently
# exempt the blocked cases — the guard exempts a live sequencer by design, and an
# ambient one turns these into assertions about the wrong thing.
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

# alias_chain <hops> <terminal> [diverge] — an N-hop chain where every hop
# defines both `alias.aN` and `alias.aN.command`. They expand identically by
# default (equivalent states, collapsed by memoization); `diverge` gives each
# spelling its own trailing word so no two analysis paths share a state and only
# the traversal budget can stop the walk.
alias_chain() {
  local n="$1" terminal="$2" mode="${3:-same}" cmd="git" i
  for ((i = 1; i < n; i++)); do
    if [[ "$mode" == diverge ]]; then
      cmd+=" -c alias.a$i='a$((i + 1)) --x$i' -c alias.a$i.command='a$((i + 1)) --y$i'"
    else
      cmd+=" -c alias.a$i=a$((i + 1)) -c alias.a$i.command=a$((i + 1))"
    fi
  done
  printf '%s' "$cmd -c alias.a$n='$terminal' -c alias.a$n.command='$terminal' a1"
}

# The SAFE terminal is the demanding case: it exhausts the whole tree rather than
# exiting on the first path that reaches a commit. Exiting 0 is what proves the
# walk stayed inside the re-expansion cap — before the bounds this shape did not
# finish at all, and a collapse regression puts it over the cap, where it exits 2
# naming the ceiling instead of 0.
run_guarded "traversal: 20-hop dual-spelling chain to a canonical commit (allowed, bounded)" \
  "$(alias_chain 20 'commit -F -')" 0
# Coverage is not what the collapse trades away: the same depth still reaches the
# non-canonical commit and blocks. (The walk exits on the first path that finds
# the commit, so this one asserts reach.)
run_guarded "traversal: 20-hop dual-spelling chain to a multi-line commit -m (blocked, bounded)" \
  "$(alias_chain 20 "commit -m \"bypass${NL}b\"")" 2
# A long chain that does NOT branch (one spelling per hop) must stay allowed —
# the budget bounds branching, not depth. Hang-guarded too: a regression that
# made this one branch would otherwise wedge the suite rather than fail it.
run_guarded "traversal: 60-hop single-spelling chain to a canonical commit (allowed)" \
  "$(
    cmd="git"
    for ((i = 1; i < 60; i++)); do cmd+=" -c alias.a$i=a$((i + 1))"; done
    printf '%s' "$cmd -c alias.a60='commit -F -' a1"
  )" 0
# Divergent spellings defeat state collapse, so the budget is what stops the walk:
# fail CLOSED rather than stall the hook. Exit 2 plus the message asserted just
# below is the whole boundedness claim — no clock is involved.
run_guarded "traversal: divergent-spelling chain exhausts the budget (blocked, bounded)" \
  "$(alias_chain 12 status diverge)" 2
budgetout=$(timeout "$HANG_GUARD_SECS" bash "$HOOK" <<<"$(command_json "$(alias_chain 12 status diverge)")" 2>&1)
assert_contains "traversal: budget block names the re-expansion ceiling" \
  "$budgetout" "re-expansions"

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
run "inline alias, uppercase subcommand (blocked)" "git -c alias.c=commit C -m 'x${NL}y'" 2
run "inline alias, uppercase alias key (blocked)" "git -c alias.C=commit c -m 'x${NL}y'" 2
run "inline alias, uppercase both, to canonical form (allowed)" "git -c alias.C=commit C -F -" 0

# --- `alias.<sub>.command` subkey is an alias definition too ------------------
# git reads the `alias.<sub>.command` subkey as the alias (`git -c alias.c.command=commit
# c -m x` commits non-canonically); the guard classifies that spelling inline and by shape.
run "inline .command-subkey alias to a multi-line commit -m (blocked)" "git -c alias.c.command=commit c -m 'bypass${NL}b'" 2
run "config-env .command-subkey alias for the invoked sub (blocked by shape)" "git --config-env=alias.c.command=AV c" 2
run ".command-subkey alias, case-folded key (blocked)" "git -c alias.C.command=commit c -m 'x${NL}y'" 2
# A non-`command` alias subkey is not an alias to git, so it must not be blocked.
run "non-command alias subkey is not an alias (allowed)" "git -c alias.c.nope=commit c -m 'bypass${NL}b'" 0
# MAX-DANGER UNION: which spelling git runs when both are set is version-dependent, so a
# benign value in one spelling must never mask a commit alias in the other — the guard
# blocks if EITHER spelling commits non-canonically, and allows only when BOTH are benign.
run "commit plain masked by a benign .command (blocked by union)" "git -c alias.c=commit -c alias.c.command=status c -m 'x${NL}y'" 2
run "commit .command masked by a benign plain (blocked by union)" "git -c alias.c=status -c alias.c.command=commit c -m 'x${NL}y'" 2
run "commit plain, benign .command decoy first (blocked by union)" "git -c alias.c.command=status -c alias.c=commit c -m 'x${NL}y'" 2
run "both spellings benign non-commit (allowed)" "git -c alias.c=status -c alias.c.command=log c" 0
# Union on the --config-env shape path: an env spelling refuses even when the sibling
# inline spelling is benign (both command-line orders).
run "env plain spelling refuses despite a benign inline .command (blocked)" "git --config-env=alias.c=AV -c alias.c.command=status c" 2
run "env .command spelling refuses despite a benign inline plain (blocked)" "git --config-env=alias.c.command=AV -c alias.c=status c" 2

# --- other subcommands are untouched -----------------------------------------
run "git log (allowed)" "git log --oneline -5" 0
run "git push (allowed)" "git push origin main" 0
run "non-git command (allowed)" "echo git commit -m 'no${NL}pe'" 0

# --- prose containing the anti-pattern is not a false positive ---------------
run "quoted mention in a heredoc body (allowed)" \
  "git commit -F - <<'EOF'
docs: explain why git commit -m 'x' is wrong
EOF" 0

# --- shell -c wrappers are re-parsed -----------------------------------------
run "bash -lc wrapped multi-line -m (blocked)" "bash -lc \"git commit -m 'feat: x${NL}body'\"" 2
run "bash -lc wrapped -F - (allowed)" "bash -lc 'git commit -F -'" 0

# --- control operators: a later segment is still checked ---------------------
run "second segment carries a multi-line -m (blocked)" "git add -A && git commit -m 'x${NL}y'" 2

# --- kill switch and allow-list ----------------------------------------------
run "kill switch disables the guard" "git commit -m 'feat: x${NL}body'" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ENABLED=false
run "allow-list message-flag permits a multi-line -m" "git commit -m 'feat: x${NL}body'" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW=message-flag
run "unrelated allow token does not permit a multi-line -m" "git commit -m 'feat: x${NL}body'" 2 \
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
  MSYS_NO_PATHCONV=1 jq -n --arg c "git commit -m 'merge${NL}fix'" --arg d "$SEQ" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    bash "$HOOK" >/dev/null 2>&1
  rc=$?
  assert_exit "in-progress merge is exempt (even with a multi-line -m)" 0 "$rc"

  rm -f "$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git commit -m 'not a${NL}merge'" --arg d "$SEQ" \
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
  MSYS_NO_PATHCONV=1 jq -n --arg c "git -C $SEQ commit -m 'merge${NL}fix'" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:"/"}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "git -C honors the target repo's in-progress merge" 0 $?

  rm -f "$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git -C $SEQ commit -m 'not a${NL}merge'" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:"/"}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "git -C with no sequencer state in the target repo is blocked" 2 $?
fi

# --- explicit --git-dir names the repo whose sequencer state matters ---------
if [[ -d "$GITDIR" ]]; then
  : >"$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git --git-dir=$GITDIR --work-tree=$SEQ commit -m 'x${NL}y'" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:"/"}' |
    bash "$HOOK" >/dev/null 2>&1
  assert_exit "--git-dir honors that repo's in-progress merge" 0 $?

  rm -f "$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git --git-dir=$GITDIR --work-tree=$SEQ commit -m 'x${NL}y'" \
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
  # The $'…' spelling keeps each spec single-line; the hook's tokenizer decodes
  # it to a real newline in the -m message (the narrowed blocking hazard).
  for spec in "git c -m \$'bypass\nb':2" "git c -F -:0"; do
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
  for spec in "git c -m \$'bypass\nb':2" "git c -F -:0"; do
    cmd="${spec%:*}"
    want="${spec##*:}"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$cmd" --arg d "$PCHAIN" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      bash "$HOOK" >/dev/null 2>&1
    assert_exit "persisted alias chain: $cmd" "$want" $?
  done

  # A dual-spelling INLINE chain whose last hop names the PERSISTED alias, so the
  # walk crosses from collapsed inline states into the config lookup. The two
  # mechanics only meet here: the persisted branch is reached once per state, and
  # the collapse must not drop it just because the inline hops above it converged.
  mixed="git"
  for ((i = 1; i < 12; i++)); do mixed+=" -c alias.a$i=a$((i + 1)) -c alias.a$i.command=a$((i + 1))"; done
  mixed+=" -c alias.a12=c -c alias.a12.command=c a1"
  for spec in "-m \$'bypass\nb':2" "-F -:0"; do
    args="${spec%:*}"
    want="${spec##*:}"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$mixed $args" --arg d "$PCHAIN" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
    assert_exit "inline dual-spelling chain into a persisted alias: git … a1 $args" "$want" $?
  done
fi

# --- alias traversal's per-analysis FORK cost, pinned by SPAWN COUNT ----------
# HOOK_ALIAS_WORK_MAX bounds the COUNT of analyses, not the cost of each one. The
# hook names its own cost centre outright, in persisted_alias's docblock — the
# lookup "forks a `git config`, by far the costliest step on the re-expansion" —
# so a regression that stays inside the budget while forking MORE `git config`
# per analysis passes every exit-code assertion above unnoticed. That is the hole
# this section closes.
#
# The pin COUNTS SPAWNS, never seconds, for the reason the hook gives where it
# sets that cap ("a wall clock is host- and command-length-dependent"). Measured here
# on Windows Git Bash (2026-08-09) while the box ran other agents: the SAME
# 10-hop chain took 33s and 9s in one sitting, and the 20-hop chain came in
# FASTER than the 10-hop one — while every spawn tally was bit-identical on every
# repeat. A count is exact and load-invariant; any ratio over those clocks is
# noise.
#
# Only the PERSISTED branch forks, so these fixtures — not the inline chains
# earlier in this file — are where the cost lives, and a persisted chain is the
# only shape that gives one fork PER HOP for the linear ceilings below.
# An inline HOP is free: it sets inline_alias_handled and skips the config
# lookup, and effective_dir is pure string composition. Measured with the shim
# below, the 20-hop dual-spelling and 60-hop single-spelling inline chains to
# `commit -F -` cost ZERO spawns. But an inline chain is not uniformly free —
# its TERMINAL subcommand has no inline definition, so the walk still pays one
# persisted_alias lookup for it: a 12-hop divergent chain to `status` costs 1,
# as does the dual-spelling chain's blocked `commit -m` variant.
# That single fork is not nothing — it moves 1 -> 40 under the same cache
# regression this section pins. The inline cases are still the wrong fixtures
# here, not because they cannot move, but because one fork cannot express a
# per-hop ceiling, and because none of them carries a spawn assertion.
#
# The shim LOGS AND DELEGATES. This hook genuinely needs git to answer, so a
# log-only stub would change the very verdicts being measured. The real binary is
# resolved HERE, before PATH is rewritten, and baked into the script — calling
# plain `git` inside the shim would re-enter the shim through its own PATH entry
# and recurse. Every case below asserts the shimmed exit code equals the
# unshimmed one, so a perturbing shim fails the suite instead of quietly
# invalidating the tally.
FORK_REAL_GIT="$(command -v git)"
FORK_SHIM="$TEST_TMPDIR/git-shim"
FORK_LOG="$TEST_TMPDIR/git-spawn-log"
mkdir -p "$FORK_SHIM"
if [[ -n "$FORK_REAL_GIT" ]]; then
  # Unquoted delimiter so the real binary path is baked in at build time; every
  # other expansion is escaped and resolves when the shim RUNS.
  cat >"$FORK_SHIM/git" <<SHIM
#!/usr/bin/env bash
printf 'x\n' >>"\${BNC_GIT_SPAWN_LOG:-/dev/null}"
exec '$FORK_REAL_GIT' "\$@"
SHIM
  chmod +x "$FORK_SHIM/git"
fi

# fork_chain_repo <dir> <hops> — a repo whose git CONFIG holds a linear chain
# f1 -> f2 -> … -> fN -> `commit -F -`, plus `d -> status` as a terminal for the
# divergent case. Persisted rather than inline: the config lookup is the fork
# being counted.
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

# Sets SPAWN_RC and SPAWN_COUNT. A FUNCTION setting globals, deliberately NOT a
# command substitution — a subshell would strand both.
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
# Sets PLAIN_RC — the identical payload with the shim off PATH, so the parity
# assertions compare like with like.
run_unshimmed() {
  MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$2" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
  PLAIN_RC=$?
}

if [[ -n "$FORK_REAL_GIT" && -d "$FORK10/.git" && -d "$FORK20/.git" ]]; then
  # A divergent INLINE chain whose last hop names a PERSISTED alias. Each path
  # carries its own trailing word, so no two analysis states collapse and the
  # walk runs until the re-expansion budget stops it (exit 2) — and every one of
  # those admitted analyses arrives at the same (directory, subcommand) config
  # lookup. The per-(dir, sub) cache is the only thing standing between this
  # shape and one fork per analysis, which is exactly the regression class the
  # budget cannot see.
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

  # A zero tally means the shim never ran, which would make every ceiling below
  # pass vacuously — the silent-skip shape this suite otherwise guards against.
  # Guarded on BOTH shapes, not just one: the divergent case carries the load-
  # bearing ceiling, and it can go vacuous on its own. If `alias.d` ever falls out
  # of the fixture, or the chain stops reaching it, the walk still exhausts the
  # budget and still exits 2 while forking far below the ceiling — measured at 1,
  # the terminal `alias.status` lookup alone — and a `1 <= 16` ceiling would
  # report green over a fixture that had quietly stopped testing anything. Two is
  # the measured floor: `alias.d`, then `alias.status`.
  if ((FORKS_10 > 0)); then
    ok "fork pin: git shim active (${FORKS_10} git spawns on the 10-hop persisted chain)"
  else
    bad "fork pin: the git shim never fired — the ceilings below cannot discriminate"
  fi
  if ((FORKS_DIV >= 2)); then
    ok "fork pin: the divergent chain reaches its persisted lookups (${FORKS_DIV} git spawns)"
  else
    bad "fork pin: the divergent chain forked ${FORKS_DIV} times — it never reached a persisted lookup, so its ceiling below is vacuous"
  fi

  # DEPTH: doubling the hops must at most double the forks. Each hop resolves a
  # distinct alias name and the lookup is cached per (directory, subcommand), so
  # the walk pays one `git config` per hop and nothing per path. Measured 10 and
  # 20, identical on three repeats each. The +2 allowance lets one added
  # constant-cost probe through while any per-hop growth still fails.
  if ((FORKS_20 <= 2 * FORKS_10 + 2)); then
    ok "fork pin: forks scale linearly in hops (${FORKS_10} at 10 hops, ${FORKS_20} at 20)"
  else
    bad "fork pin: per-hop fork cost grew with depth — ${FORKS_10} forks at 10 hops but ${FORKS_20} at 20"
  fi

  # ABSOLUTE, on the 20-hop chain: measured 20, ceiling 30. Half again the
  # measured value absorbs a constant-cost probe or two; a SECOND fork per hop
  # lands on 40 and fails.
  if ((FORKS_20 <= 30)); then
    ok "fork pin: 20-hop persisted chain stays under 30 forks (${FORKS_20})"
  else
    bad "fork pin: 20-hop persisted chain forked ${FORKS_20} times, over the 30 ceiling"
  fi

  # BRANCHING, the discriminating one: measured 2 spawns at 8 divergent hops —
  # the two distinct names the walk resolves (`alias.d`, then `alias.status`) —
  # and 2 again at 12 hops, so the tally is invariant to branching depth. With
  # the per-(dir, sub) cache removed from persisted_alias, the SAME command forked
  # 83 times for the same exit 2 (measured 2026-08-09), because each admitted
  # analysis repeats the lookup; the only bound left is HOOK_ALIAS_WORK_MAX = 128.
  # A ceiling of 16 sits five times below that regression and eight times above
  # the measured value. Verified by running this very section against that
  # modified copy: it fails here, and only here.
  if ((FORKS_DIV <= 16)); then
    ok "fork pin: divergent walk forks per distinct lookup, not per analysis (${FORKS_DIV})"
  else
    bad "fork pin: divergent walk forked ${FORKS_DIV} times, over the 16 ceiling — the per-analysis lookup cache is gone"
  fi
else
  echo "ok: alias-traversal fork pin skipped (git unavailable)"
  PASS=$((PASS + 1))
fi

# --- #964: persisted `!` shell-alias hops -------------------------------------
# A persisted shell alias spawns a fresh git process (empty alias-loop guard),
# so a chain that crosses a `!` hop (`alias.sc = !git x2`, `alias.x2 = commit`)
# must still resolve to the commit. A self- or mutually referential persisted
# shell alias (`a = !git a`; `ma = !git mb`, `mb = !git ma`) makes real git
# fork endlessly without ever reaching a subcommand — the hook must terminate
# and allow, not hang.
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
  for spec in "git sc -m \$'bypass\nb':2" "git sc -F -:0" "git a:0" "git ma:0"; do
    cmd="${spec%:*}"
    want="${spec##*:}"
    MSYS_NO_PATHCONV=1 jq -n --arg c "$cmd" --arg d "$PSHELL" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
      bash "$HOOK" >/dev/null 2>&1
    assert_exit "persisted shell-alias hop: $cmd" "$want" $?
  done
fi

# --- the block message names the fix -----------------------------------------
out=$(bash "$HOOK" <<<"$(command_json "git commit -m 'feat: x${NL}body'")" 2>&1)
assert_contains "block message names -F -" "$out" '-F -'
assert_contains "block message names the skill" "$out" '/commit'
assert_contains "block message names the multi-line hazard" "$out" 'multi-line'

# --- persisted `!` hops across NESTED repositories ----------------------------
# One persisted alias text can mean a different hop in each repository it appears
# in: `alias.a = !git -C child a` in a repo AND its child descends one level
# further every time. Keying the shell-alias cycle set on the name and expansion
# alone read the second hop as a self-cycle, so the grandchild's `commit -m` was
# never analyzed while real git committed there. The effective repository is part
# of that key now, and it is composed across `!` reparses rather than restarting
# from the payload cwd.
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
  # Descent to a NON-canonical commit must block; the canonical twin must not.
  git -C "$NESTED/a" config alias.a '!git -C child a'
  git -C "$NESTED/a/child" config alias.a '!git -C child a'
  git -C "$NESTED/a/child/child" config alias.a $'commit --allow-empty -m "bypass\nb"'
  git -C "$NESTED/b" config alias.a '!git -C child a'
  git -C "$NESTED/b/child" config alias.a '!git -C child a'
  git -C "$NESTED/b/child/child" config alias.a 'commit -F -'
  # `-C .` names the directory it already is. Lexical normalization collapses it
  # so the cycle key repeats and the walk stops at once — allow-safe, because real
  # git forks such a chain forever and never reaches a subcommand. Without the
  # normalization this minted a fresh key per hop and ran for 34s.
  git -C "$NESTED/dot" config alias.selfdot '!git -C . selfdot'
  git -C "$NESTED/dot" config alias.viadot '!git -C . realcommit'
  git -C "$NESTED/dot" config alias.realcommit $'commit --allow-empty -m "bypass\nb"'
  # The INLINE `!` site composes the directory too, and a `!` body is reparsed as
  # its own command — the outer `-c` globals do not ride along — so the hop it
  # descends into resolves against PERSISTED config in the child. That crosses
  # inline -> persisted at a directory boundary, which neither branch's own cases
  # reach on their own.
  git -C "$NESTED/a/child" config alias.z2 $'commit --allow-empty -m "bypass\nb"'
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

# --- a WRAPPER's options are not git's globals --------------------------------
# The directory and locating-global parsers used to receive the whole pre-git
# slice, wrapper argv included, and they cannot know which wrapper options take
# a value. In `env -u -C git …`, GNU env's `-u NAME` consumes `-C` as the
# variable to unset and `git` as the command, so git itself gets no `-C` and
# stays put — while a 0-based slice read `-C git` as a relocation into `./git`.
# The guard then inspected `git/child`'s canonical alias and allowed the call
# while real git ran `child`'s `commit -m`. Reproduced from the report.
WRAP="$TEST_TMPDIR/wrapper"
nested_repo "$WRAP/outer"
nested_repo "$WRAP/outer/child"
nested_repo "$WRAP/outer/git"
nested_repo "$WRAP/outer/git/child"
nested_repo "$WRAP/outer/other"
nested_repo "$WRAP/outer/other/child"
nested_repo "$WRAP/outer/has space"

if [[ -d "$WRAP/outer/child/.git" && -d "$WRAP/outer/git/child/.git" ]]; then
  # The repository git ACTUALLY reaches carries the non-canonical commit; the
  # decoy a wrongly-sliced parser would reach carries the canonical one, so a
  # bypass shows up as a wrongly-allowed exit 0.
  git -C "$WRAP/outer/child" config alias.p $'commit --allow-empty -m "bypass\nb"'
  git -C "$WRAP/outer/git/child" config alias.p 'commit -F -'

  # `env -u -C git`: -u consumes `-C` as the variable name, so `git` is the
  # COMMAND and the -C never belonged to git. The guard must still reach
  # `child`'s `commit -m` rather than the decoy under `git/`.
  MSYS_NO_PATHCONV=1 jq -n --arg c "env -u -C git -c alias.a='!git -C child p' a" --arg d "$WRAP/outer" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  ((rc == 124)) && bad "env -u swallows -C: the hook HUNG — no verdict inside the ${HANG_GUARD_SECS}s hang guard"
  ((rc == 124)) || assert_exit "env -u swallows -C, so the wrapper option is not git's -C" 2 "$rc"

  # git's OWN -C must keep working — the fix narrows the slice, it does not
  # stop honouring a relocation git really performs.
  git -C "$WRAP/outer/git/child" config alias.q $'commit --allow-empty -m "bypass\nb"'
  MSYS_NO_PATHCONV=1 jq -n --arg c "git -C git -c alias.a='!git -C child q' a" --arg d "$WRAP/outer" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
  assert_exit "git's own -C still relocates the alias lookup" 2 "$?"
fi

# --- a wrapper's chdir is not git's global, but it still MOVES git -------------
# The mirror image of the case above: excluding wrapper argv from git-global
# parsing must not discard a relocation the wrapper really performs. GNU env
# documents `-C, --chdir=DIR` as "change working directory to DIR", so
# `env -C other git a` runs git in `other` and resolves `other`'s alias — a slice
# that starts at the git token cannot see that, and reading the payload cwd's
# alias instead let a non-canonical commit through. Five spellings are covered,
# because one unhandled spelling is the whole bypass again. A chdir inside
# `-S`/`--split-string` is the sixth and is NOT covered: the resolver's
# post-splice restart re-enters outside env's option parsing, which fails open for
# any command on main too — tracked in #1814, not asserted here.
wrapper_cd_case() {
  local label="$1" command="$2" expected="$3" rc
  MSYS_NO_PATHCONV=1 jq -n --arg c "$command" --arg d "$WRAP/outer" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    timeout "$HANG_GUARD_SECS" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  ((rc == 124)) && bad "$label: the hook HUNG — no verdict inside the ${HANG_GUARD_SECS}s hang guard"
  ((rc == 124)) || assert_exit "$label" "$expected" "$rc"
}

if [[ -d "$WRAP/outer/other/.git" ]]; then
  # `other` (where git lands) is non-canonical under `a` and canonical under `k`;
  # the payload cwd `outer` is the reverse. So a dropped chdir shows up as exit 0
  # on `a`, and an over-applied one as exit 2 on `k`.
  git -C "$WRAP/outer/other" config alias.a $'commit --allow-empty -m "bypass\nb"'
  git -C "$WRAP/outer/other" config alias.k 'commit -F -'
  git -C "$WRAP/outer" config alias.a 'commit -F -'
  git -C "$WRAP/outer" config alias.k $'commit --allow-empty -m "bypass\nb"'
  [[ -d "$WRAP/outer/has space/.git" ]] &&
    git -C "$WRAP/outer/has space" config alias.a $'commit --allow-empty -m "bypass\nb"'

  wrapper_cd_case "env -C moves git, so the alias lookup follows" \
    "env -C other git a" 2
  wrapper_cd_case "env --chdir=DIR (attached long form) moves git" \
    "env --chdir=other git a" 2
  wrapper_cd_case "env --chdir DIR (separated long form) moves git" \
    "env --chdir other git a" 2
  wrapper_cd_case "env -CDIR (attached short form) moves git" \
    "env -Cother git a" 2
  # env clusters its short options, so a valueless flag can hide the chdir in the
  # same word: `-vC` is --debug plus --chdir, and an exact `-C` match misses it.
  wrapper_cd_case "env -vC DIR (clustered short form) moves git" \
    "env -vC other git a" 2
  wrapper_cd_case "env -u NAME before the chdir does not consume it" \
    "env -uFOO -C other git a" 2
  # env keeps --chdir in ONE slot, so a repeat is last-wins and a relative
  # operand resolves against the cwd env was invoked from: `-C other -C .` lands
  # in the payload cwd, NOT in `other/.`. Composing them cumulatively would probe
  # a path that does not exist and read no alias at all.
  wrapper_cd_case "repeated env -C is last-wins, not cumulative (lands in cwd)" \
    "env -C other -C . git a" 0
  wrapper_cd_case "repeated env -C is last-wins (lands in the LAST operand)" \
    "env -C . -C other git a" 2
  # Over-correction guard: the chdir must not turn a canonical commit into a
  # block, and it must compose ahead of git's own globals rather than replace them.
  wrapper_cd_case "a canonical commit through the same wrapper stays allowed" \
    "env -C other git k" 0
  # A NAME=value operand ends env's option parsing, so env looks for a command
  # named `-C` and runs nothing. The guard must not read a chdir that never
  # happens — and with no git resolved there is nothing to gate.
  wrapper_cd_case "a NAME=value operand ends option parsing" \
    "env FOO=1 -C other git a" 0
  # sudo relocates through -D/--chdir (its -C is close-from, not a directory).
  wrapper_cd_case "sudo -D moves git, so the alias lookup follows" \
    "sudo -D other git a" 2
  wrapper_cd_case "sudo --chdir=DIR moves git" \
    "sudo --chdir=other git a" 2
  wrapper_cd_case "sudo -DDIR (attached) moves git" \
    "sudo -Dother git a" 2
  # `k` is the non-canonical alias in the payload cwd, so a correctly-ignored
  # `-C 3` blocks; misreading it as a chdir would probe `outer/3`, find no alias
  # there, and allow.
  wrapper_cd_case "sudo -C is close-from, not a chdir" \
    "sudo -C 3 git k" 2

  # The chdir must survive the `-S` restart: env performs it before splitting,
  # and the splice drops every word before the current index, so the recorded
  # directory must not be re-walked NOR lost. (A chdir spelled INSIDE the -S
  # operand is a different, unhandled case — see #1814.)
  wrapper_cd_case "a chdir before -S survives the splice restart" \
    "env -C other -S 'git a'" 2
  # A directory operand containing a space must survive the array round-trip
  # into effective_dir's argv.
  wrapper_cd_case "a wrapper chdir into a directory with a space" \
    "env -C 'has space' git a" 2
  # GNU env refuses `-0` alongside a command outright ("cannot specify --null
  # (-0) with command"), so nothing runs either way; the guard fails closed and
  # the peel still reads the chdir out of the cluster. Pinned so a peel change
  # that swallowed `-0` would surface here.
  wrapper_cd_case "env -0 does not hide the chdir from the peel" \
    "env -0 -C other git a" 2
  wrapper_cd_case "env -vi0C (three-flag cluster) still yields the chdir" \
    "env -vi0C other git a" 2
fi

# --- a wrapper's chdir composes AHEAD of git's own -C, in that order ----------
# env relocates before git starts, so git's own `-C` composes onto the wrapper's
# directory rather than replacing it or being replaced by it. Reversing the two
# would land in `child` relative to the payload cwd, which is not a repository
# at all — and reading no alias there allows. The canonical twin pins the arrival
# point: exit 0 is only reachable from `other/child` itself.
if [[ -d "$WRAP/outer/other/child/.git" ]]; then
  git -C "$WRAP/outer/other/child" config alias.a $'commit --allow-empty -m "bypass\nb"'
  git -C "$WRAP/outer/other/child" config alias.c 'commit -F -'

  wrapper_cd_case "env -C composes ahead of git's own -C" \
    "env -C other git -C child a" 2
  wrapper_cd_case "same composition, canonical leaf, stays allowed" \
    "env -C other git -C child c" 0
fi

# --- the wrapper's chdir composes ONCE, on every recursion path ----------------
# The alias walk recurses two ways, and the chdir must be applied exactly once
# down both. The git-alias splice rebuilds the command line from index 0, so the
# recursive frame re-resolves the SAME wrapper argv — applying it again there
# would compose `other/other` and probe a path that does not exist, which reads
# as "no alias found" and allows the commit. The `!` shell-alias reparse instead
# carries only the alias BODY, which has no wrapper argv, so it must not lose the
# directory the outer hop already reached. Each case has a canonical twin: the
# exit 0 proves the walk arrived at the right repository rather than at nothing.
if [[ -d "$WRAP/outer/other/.git" ]]; then
  nested_repo "$WRAP/outer/other/child"
  nested_repo "$WRAP/outer/other/child/child"
fi

if [[ -d "$WRAP/outer/other/child/child/.git" ]]; then
  git -C "$WRAP/outer/other" config alias.p '!git -C child p'
  git -C "$WRAP/outer/other/child" config alias.p '!git -C child p'
  git -C "$WRAP/outer/other/child/child" config alias.p $'commit --allow-empty -m "bypass\nb"'
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

# --- `!` bodies start at the outer repository's TOP LEVEL ---------------------
# git documents that a shell alias body runs from the top-level directory of the
# repository, NOT from wherever the outer command was invoked. Invoked from
# `<repo>/sub` with `alias.a = !git -C child a`, git reaches `<repo>/child`;
# carrying the subdirectory forward made the guard probe `<repo>/sub/child` and
# miss the nested repository's `commit -m`. The top level comes from git itself
# (`rev-parse --show-toplevel`), so it cannot drift from git's own behavior.
TOPLEVEL="$TEST_TMPDIR/toplevel"
nested_repo "$TOPLEVEL/outer"
nested_repo "$TOPLEVEL/outer/child"
mkdir -p "$TOPLEVEL/outer/sub/child"
nested_repo "$TOPLEVEL/canon"
nested_repo "$TOPLEVEL/canon/child"
mkdir -p "$TOPLEVEL/canon/sub"

if [[ -d "$TOPLEVEL/outer/child/.git" ]]; then
  git -C "$TOPLEVEL/outer" config alias.a '!git -C child a'
  git -C "$TOPLEVEL/outer/child" config alias.a $'commit --allow-empty -m "bypass\nb"'
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

# A symlinked component before `..` means the directory git enters is not the one
# textual cancellation produces. The guard hands the LITERAL path to git rather
# than resolving it, so git's own semantics decide — which differ by platform:
# POSIX resolves `link/..` through the kernel (reaching the link target's parent),
# while Win32 normalizes `..` textually, so Windows git stays in the textual
# parent. The fixture is therefore gated on the platform actually exhibiting it,
# probed directly rather than assumed, so this asserts on Linux/macOS and skips
# loudly on Windows instead of encoding one platform's semantics as the expected
# answer.
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
  git -C "$SYMDIR/target" config alias.a $'commit --allow-empty -m "bypass\nb"'
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

# --- `.` and `..` in composed `-C` paths --------------------------------------
# These are regression cases for the shapes a LEXICAL normalizer used to handle,
# and they pin why there is no longer one. Since composed paths go to git verbatim
# and identity comes from `rev-parse --show-toplevel`:
#   - every `.` spelling (`.`, `./././.`) resolves to the same repository, so the
#     cycle key repeats and a self-rewriting chain stops without a `.`-cancelling
#     pass of our own;
#   - `..` needs no special handling either. Cancelling it lexically was a bypass
#     (a symlinked component makes it wrong), but REFUSING every `..` path would
#     false-block the canonical case below, which is legitimate and must stay
#     allowed. Asking git distinguishes the two.
DOTS="$TEST_TMPDIR/dots"
nested_repo "$DOTS"
mkdir -p "$DOTS/sub"

if [[ -d "$DOTS/.git" ]]; then
  git -C "$DOTS" config alias.selfdeep '!git -C ./././. selfdeep'
  git -C "$DOTS" config alias.livedot '!git -C . realdot'
  git -C "$DOTS" config alias.realdot $'commit --allow-empty -m "bypass\nb"'
  git -C "$DOTS" config alias.up '!git -C sub/.. realup'
  git -C "$DOTS" config alias.realup $'commit --allow-empty -m "bypass\nb"'
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

# --- trailing alias arguments are NOT repository globals ----------------------
# Words after the subcommand belong to that subcommand — or, for an alias, are text
# git APPENDS to the expansion. Resolving the directory from the whole argv read a
# trailing `-C` as a global and inspected the wrong repository, while git started
# the body at the current repo's top level and the `#` threw the appended words
# away. Directory resolution sees only the invocation prefix now.
TRAIL="$TEST_TMPDIR/trailing"
nested_repo "$TRAIL/cur"
nested_repo "$TRAIL/safe"

if [[ -d "$TRAIL/cur/.git" && -d "$TRAIL/safe/.git" ]]; then
  git -C "$TRAIL/cur" config alias.b $'commit --allow-empty -m "bypass\nb"'
  # A trailing `-C` also lands in the commit-argument scan, where `-C` is
  # `--reuse-message` and exempts — so the prefix slice has no independently
  # observable effect on this guard's verdicts today, and there is deliberately no
  # test asserting one. What is pinned is that a post-subcommand `-C` keeps reading
  # as --reuse-message rather than as a directory, so a future change cannot
  # quietly start resolving `HEAD` as a path.
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

# --- locating globals are replayed onto the identity probe --------------------
# `--git-dir` and `--work-tree` locate a repository as surely as `-C` does. Asking
# git for the alias's repository identity WITHOUT replaying them answered "no work
# tree" for a perfectly locatable one, and the fail-closed path then refused a valid
# canonical commit. The blocked twin proves the replay did not just switch the
# fail-closed branch off.
GLOB="$TEST_TMPDIR/globals"
mkdir -p "$GLOB/outside"
nested_repo "$GLOB/repo"

if [[ -d "$GLOB/repo/.git" ]]; then
  # The alias body is embedded DOUBLE-quoted in the command so the blocked twin
  # can spell its newline as \$'x\ny' (the tokenizer decodes it in the ! body
  # reparse; a single-quoted embedding would end at the \$' quote instead).
  for spec in \
    "!git commit -F -|0|--git-dir/--work-tree: canonical commit through a ! alias is allowed" \
    "!git commit -m \$'x\ny'|2|--git-dir/--work-tree: multi-line -m through a ! alias still blocks"; do
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
fi

# --- explicit locating globals: a `!` body launches where the CALLER stands ----
# git chdirs a `!` body to the work-tree top level only when the caller's
# directory is INSIDE the effective work tree. With `--git-dir`/`--work-tree`
# and a caller outside that work tree, the body runs in the caller's directory:
# from `<out>`, `git --git-dir <g> --work-tree <w> -c alias.a='!unset GIT_DIR
# GIT_WORK_TREE; git -C child p' a` runs `<out>/child`'s persisted `p`, not
# `<w>/child`'s (verified via `!pwd` on git 2.54.0.windows.1; reported by review
# on 2.43.0). Collapsing to the top level unconditionally probed the benign
# `<w>/child` and allowed while real git committed non-canonically — and its
# mirror twin false-blocked a canonical commit. The inside-the-work-tree pair
# pins the other branch: from `<w>/sub` the same invocation still launches at
# the top level, so the guard must keep resolving `<w>/child` there, not
# `<w>/sub/child`.
LAUNCH="$TEST_TMPDIR/launchdir"
launch_tree() { # <root> <out-child-alias> <work-child-alias> <sub-child-alias>
  nested_repo "$1/work"
  nested_repo "$1/work/child"
  nested_repo "$1/work/sub/child"
  mkdir -p "$1/out"
  nested_repo "$1/out/child"
  git -C "$1/out/child" config alias.p "$2"
  git -C "$1/work/child" config alias.p "$3"
  git -C "$1/work/sub/child" config alias.p "$4"
}
launch_tree "$LAUNCH/a" $'commit --allow-empty -m "bypass\nb"' 'commit -F -' $'commit --allow-empty -m "bypass\nb"'
launch_tree "$LAUNCH/b" 'commit -F -' $'commit --allow-empty -m "bypass\nb"' 'commit -F -'

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

# --- PowerShell tool coverage ------------------------------------------------
# The canonical PowerShell commit form (a here-string piped to `git commit -F -`)
# must be allowed exactly as the Bash `-F -` form is; a here-string `-m` value
# must be blocked (uninspectable, multi-line by construction of the form) while
# a single-line literal `-m` passes; commit-shaped PowerShell the classifier
# cannot parse is DEFERRED here (#1858) and blocked by `block-dangerous-git`,
# asserted below.
run_pwsh() {
  local label="$1" command="$2" expected="$3" rc
  bash "$HOOK" <<<"$(pwsh_command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}
run_pwsh "PS: canonical here-string | git commit -F - (allowed)" \
  "$(printf '%s\n%s\n%s' "@'" "feat: x" "'@ | git commit -F -")" 0
# A here-string `-m` VALUE blanks to a placeholder whose content the guard
# cannot inspect — multi-line by construction of the form — so it fails closed.
run_pwsh "PS: git commit -m here-string (blocked — uninspectable, multi-line by form)" \
  "$(printf '%s\n%s\n%s' "git commit -m @'" "feat: x" "'@")" 2
run_pwsh "PS: git commit -m single-line literal (allowed — no newline)" \
  "git commit -m 'feat: x'" 0
run_pwsh "PS: git commit --amend (allowed — exempt)" "git commit --amend" 0
run_pwsh "PS: git status (allowed — not a commit)" "git status" 0

# Classifier rc 2 (git-shaped unparsable): deferred here, and the deferral is
# only sound while a sibling guard still fail-closes on the SAME input — so each
# case is asserted against both hooks, not just this one.
PS_UNPARSABLE_BACKTICK="$(printf 'git commit -m x `\n --cleanup=verbatim')"
PS_UNPARSABLE_HERESTRING="$(printf '%s\n%s\n%s' "@'" "body" "'X ; git commit -m sneaky")"
run_pwsh "PS: backtick-continued commit (deferred — classifier rc 2)" \
  "$PS_UNPARSABLE_BACKTICK" 0
run_pwsh "PS: unbalanced here-string hiding a -m commit (deferred — classifier rc 2)" \
  "$PS_UNPARSABLE_HERESTRING" 0

# Asserting the exit code alone would stay green if a sibling started blocking
# these for an UNRELATED reason, silently breaking the coupling the deferral
# rests on — so the block reason is asserted from stderr too.
run_sibling() {
  local label="$1" sibling="$2" command="$3" out rc
  out=$(bash "$HOOK_DIR/$sibling.sh" <<<"$(pwsh_command_json "$command")" 2>&1)
  rc=$?
  assert_exit "$label" 2 "$rc"
  assert_contains "$label: for the unparsable reason" "$out" "cannot be parsed with confidence"
}
for sibling in block-dangerous-git block-no-verify; do
  run_sibling "PS: backtick-continued commit still blocked by $sibling" \
    "$sibling" "$PS_UNPARSABLE_BACKTICK"
  run_sibling "PS: unbalanced here-string commit still blocked by $sibling" \
    "$sibling" "$PS_UNPARSABLE_HERESTRING"
done

# The residual this deferral accepts, pinned at exactly its documented width: with
# BOTH sibling kill switches off, the rc-2 commit reaches git unblocked. If a
# future change widens or narrows the exposure, this fails loudly.
for command in "$PS_UNPARSABLE_BACKTICK" "$PS_UNPARSABLE_HERESTRING"; do
  for hook in block-noncanonical-commit block-dangerous-git block-no-verify; do
    env CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ENABLED=false \
      CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_ENABLED=false \
      bash "$HOOK_DIR/$hook.sh" <<<"$(pwsh_command_json "$command")" >/dev/null 2>&1
    assert_exit "residual: $hook allows the rc-2 commit with both siblings disabled" 0 "$?"
  done
done

# The PowerShell block message shows the here-string form, not a Bash heredoc.
# (The blocking fixture is the -m here-string form — single-line -m no longer blocks.)
psout=$(bash "$HOOK" <<<"$(pwsh_command_json "$(printf '%s\n%s\n%s' "git commit -m @'" "feat: x" "'@")")" 2>&1)
assert_contains "PS block message shows the here-string form" "$psout" "'@ | git commit -F -"
assert_absent "PS block message omits the Bash heredoc" "$psout" "<<'EOF'"

echo
echo "passed: $PASS   failed: $FAIL"
((FAIL == 0))
