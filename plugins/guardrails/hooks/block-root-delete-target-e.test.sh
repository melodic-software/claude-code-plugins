#!/usr/bin/env bash
# Contract test for block-root-delete-target.sh (guardrails plugin), part e of 5:
# sections 5 to 7. The parts are block-root-delete-target.test.sh and
# block-root-delete-target-b.test.sh to -e.test.sh; block-root-delete-target-fixtures.sh
# holds what they share.
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash JSON on
# stdin, asserts on exit code (2 = blocked, 0 = allowed). Self-contained, with
# no host-repo assertion library.
#
# The core table runs through expect_both, so every verdict is asserted twice:
# once with the guard alone, and once under hooks/run-guards.sh. A guard that
# decides one way by itself and another under the dispatcher is a failure here
# rather than a blind spot.
#
# The guard is NOT host-gated, so no case forces OSTYPE: a recursive delete of
# `/`, of `~`, of `$HOME`, or with --no-preserve-root is unrecoverable on every
# host this plugin runs on, and CI is Linux.
#
# File-wide, and deliberate: every command string below is a LITERAL the guard
# must read exactly as an operator wrote it. `$HOME` and `${HOME}` are matched
# as text, because the guard never evaluates an expansion (SC2016), and `\\` is
# a real pair of backslashes rather than an escaped quote (SC1003). Expanding
# either here would test something other than what the guard sees.
# shellcheck disable=SC2016,SC1003

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
RDT_AB=""
trap 'rm -rf "$TEST_TMPDIR" "$RDT_AB"' EXIT
# shellcheck source=block-root-delete-target-fixtures.sh
source "$HOOK_DIR/block-root-delete-target-fixtures.sh"
rdt_allowed_roots_fixture
rdt_worktree_fixture

# --- 5. Fail-closed inputs ---------------------------------------------------
rc=0
bash "$HOOK" </dev/null >/dev/null 2>&1 || rc=$?
assert_exit "empty stdin is a skip, not a block" 0 "$rc"

expect "a stdin body that is not JSON fails closed" 2 --payload 'not json'

# JSON whose fields jq cannot read gets past the stdin read above and is
# refused by the field read. A NUL in a command with no delete is refused there
# too, before the `rm` prefilter could wave it through.
expect "a payload whose fields jq cannot read fails closed" 2 \
  --payload '{"tool_name":"Bash","tool_input":"rm -rf build"}'
assert_eq "unreadable fields: the refusal says why" \
  "BLOCKED: the hook payload could not be parsed." "$GUARD_ERR"
assert_eq "unreadable fields: nothing on stdout" "" "$GUARD_OUT"
expect_both "a NUL byte in a command with no delete fails closed" 2 \
  --payload "$(jq -n '{tool_name:"Bash",tool_input:{command:"ls\u0000 -la"}}')"
assert_eq "NUL byte: the refusal says why" \
  "BLOCKED: the payload carries a NUL byte. Reissue the call without it." "$GUARD_ERR"

rc=0
bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{}}' >/dev/null 2>&1 || rc=$?
assert_exit "payload with no command is a skip" 0 "$rc"

# `X=build && rm -rf "$X"` deletes `build`, so it is judged as `build`, but
# only when the assignment is a statement that runs before every use and
# nothing after it can change NAME.
expect_both 'X=build && rm -rf "$X" allowed' 0 "${RDT_CWD[@]}" --command 'X=build && rm -rf "$X"'
expect_both 'X=build; rm -rf "$X/" allowed' 0 "${RDT_CWD[@]}" --command 'X=build; rm -rf "$X/"'
expect_both "X='build' && rm -rf \"\$X/out\" allowed" 0 "${RDT_CWD[@]}" --command "X='build' && rm -rf \"\$X/out\""
expect_both 'a literal on its own line, then the delete, allowed' 0 "${RDT_CWD[@]}" \
  --command $'X=build\nrm -rf "$X"'
# Unquoted and braced uses take the literal too (#7413).
expect_both 'X=build && rm -rf $X allowed (unquoted)' 0 "${RDT_CWD[@]}" --command 'X=build && rm -rf $X'
expect_both 'X=build; rm -rf $X/ allowed (unquoted)' 0 "${RDT_CWD[@]}" --command 'X=build; rm -rf $X/'
expect_both 'X="build" && rm -rf "${X}" allowed (braced)' 0 "${RDT_CWD[@]}" \
  --command 'X="build" && rm -rf "${X}"'
expect_both 'X=build; rm -rf ${X}/out allowed (braced, unquoted)' 0 "${RDT_CWD[@]}" \
  --command 'X=build; rm -rf ${X}/out'
# An unbound `$S/x` or `${X}x` is not a bare variable and is allowed with or
# without a binding, so the rows that decide whether NAME binds delete the bare
# `$S` or `${S}`: bound, it is the literal; unbound, it blocks.
expect_both 'X=build; rm -rf ${X} allowed (braced, unquoted, bare)' 0 "${RDT_CWD[@]}" \
  --command 'X=build; rm -rf ${X}'
expect_both 'a scratch literal, unquoted through mkdir and rm, allowed' 0 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; mkdir -p $S/run; rm -rf $S'
expect "attended: an unquoted operand is allowed, not asked" 0 "${RDT_CWD[@]}" \
  --command 'X=build && rm -rf $X' -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_eq "attended: an unquoted operand carries no decision" "" \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
# Outside that shape nothing binds, and the variable blocks as a bare variable.
expect_both 'X=build && rm -rf "$X"/ blocks (suffix outside the quotes)' 2 "${RDT_CWD[@]}" \
  --command 'X=build && rm -rf "$X"/'
expect_both 'X=build && rm -rf ${X}x $X blocks (a longer word)' 2 "${RDT_CWD[@]}" --command 'X=build && rm -rf ${X}x $X'
expect_both 'X=build && rm -rf ${X:-/} blocks (an operator)' 2 "${RDT_CWD[@]}" --command 'X=build && rm -rf ${X:-/}'
expect_both 'two literals, then rm -rf "$A" "$B" blocks' 2 "${RDT_CWD[@]}" \
  --command "A=build B='dist' && rm -rf \"\$A\" \"\$B/x\""
expect_both 'readonly, then the literal, blocks' 2 "${RDT_CWD[@]}" --command 'readonly X=/etc; X=build; rm -rf "$X"'
expect_both 'export NAME=literal && rm blocks' 2 "${RDT_CWD[@]}" --command 'export X=build && rm -rf "$X"'
expect_both 'a second variable in the delete blocks' 2 "${RDT_CWD[@]}" --command 'X=build && rm -rf "$X" "$Y"'
expect_both 'a second delete of the bound variable allowed (#9779)' 0 "${RDT_CWD[@]}" \
  --command 'X=build && rm -rf "$X" && rm -rf "$X"'
expect_both 'a glob after the variable blocks' 2 "${RDT_CWD[@]}" --command 'X=build && rm -rf $X*'
expect_both 'a comment after the delete allowed (#9779)' 0 "${RDT_CWD[@]}" --command 'X=build &&rm -rf "$X" # c'
expect_both 'a comment naming $X unquoted allowed' 0 "${RDT_CWD[@]}" --command 'X=build &&rm -rf "$X" # $X'
expect_both 'a comment naming $X inside a longer word blocks' 2 "${RDT_CWD[@]}" --command 'X=build &&rm -rf "$X" # a$X'
expect_both 'a line continuation before the separator blocks' 2 "${RDT_CWD[@]}" \
  --command $'X=build\\\n&& rm -rf "$X"'
expect_both 'a group around the literal blocks' 2 "${RDT_CWD[@]}" --command '{ X=build; } && rm -rf "$X"'
expect_both 'a literal with a space blocks' 2 "${RDT_CWD[@]}" --command 'X=a b && rm -rf "$X"'
expect_both 'a name the shell sets blocks' 2 "${RDT_CWD[@]}" --command 'PWD=build; rm -rf "$PWD"'
expect_both 'a name zsh ties to PATH blocks' 2 "${RDT_CWD[@]}" --command 'path=build && rm -rf "$path"'
expect_both 'a name that can set a variable, as the literal, blocks' 2 "${RDT_CWD[@]}" \
  --command 'X=export && rm -rf "$X"'
expect_both 'a literal rm reads as an option blocks' 2 "${RDT_CWD[@]}" \
  --command 'X=--no-preserve-root && rm -rf "$X" build'
expect_both 'a longer name beside the bound one blocks' 2 "${RDT_CWD[@]}" --command 'X=build && rm -rf "$X" $XY'
expect "attended: the exact shape is allowed, not asked" 0 "${RDT_CWD[@]}" \
  --command 'X=build && rm -rf "$X"' -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_eq "attended: the exact shape carries no decision" "" \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
for rdt_cmd in 'X=build && rm -rf "$X" "$Y"' '{ X=build; } && rm -rf "$X"' 'X=build & rm -rf "$X"' \
  'X=$(pwd) && rm -rf "$X"' 'X=a b && rm -rf "$X"'; do
  expect "attended: outside the shape asks: $rdt_cmd" 0 "${RDT_CWD[@]}" \
    --command "$rdt_cmd" -- CLAUDE_CODE_SESSION_ATTENDED=1
  assert_eq "attended: outside the shape, the decision is ask: $rdt_cmd" ask \
    "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
done
# #9779: the literal binds across later statements that cannot change it.
expect_both 'a literal several statements before the delete allowed' 0 "${RDT_CWD[@]}" \
  --command 'S=build; mkdir -p "$S/x"; git status; rm -rf "$S"'
expect_both 'a temp scratch literal used, then deleted, allowed' 0 "${RDT_CWD[@]}" \
  --command $'S=/tmp/rdt-scratch\nmkdir -p "$S/a" && touch "$S/a/f"\nls "$S" | wc -l\nrm -rf "$S"'
expect_both 'a temp scratch literal deleted inside a subshell allowed' 0 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch && (cd "$S" && ls) && rm -rf "$S"'
# Still blocked: a literal outside the allowed roots, a value the command can
# change before the delete, and an assignment that does not run first.
expect_both 'a literal outside the tree, several statements before, blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/etc; ls "$S"; rm -rf "$S"'
expect_both 'a later reassignment to a root blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; mkdir -p "$S"; S=/; rm -rf "$S"'
expect_both 'an unquoted use of the name elsewhere allowed (#7413)' 0 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; echo $S; rm -rf "$S"'
expect_both 'a substituted value blocks' 2 "${RDT_CWD[@]}" --command 'S=$(pwd); rm -rf $S'
expect_both 'a copy of the bound name blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; T=$S; rm -rf $T'
expect_both 'a later reassignment from an expansion blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; S=$HOME; rm -rf $S'
expect_both 'an unassigned unquoted name after a statement blocks' 2 "${RDT_CWD[@]}" \
  --command 'true; rm -rf ${S}'
expect_both 'an IFS assignment before the literal blocks' 2 "${RDT_CWD[@]}" \
  --command 'IFS=/; S=/tmp/rdt-scratch; rm -rf $S'
expect_both 'the name inside a longer quoted word blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; echo "at $S"; rm -rf "$S"'
expect_both 'arithmetic on the name blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; (( S = 1 )); rm -rf "$S"'
expect_both 'let on the name blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; let S=1; rm -rf "$S"'
expect_both 'a {NAME}> redirection blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; exec {S}>/dev/null; rm -rf "$S"'
expect_both 'getopts on the name blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; getopts a S; rm -rf "$S"'
# zsh setters that write no `NAME=`.
expect_both 'a zsh foreach on the name blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; foreach S (/); end; rm -rf "$S"'
expect_both 'a zsh vared on the name blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; vared S; rm -rf "$S"'
expect_both 'a zsh print -v on the name blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; print -v S /; rm -rf "$S"'
expect_both 'a zsh zparseopts on the name blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; zparseopts -A S x:; rm -rf "$S"'
expect_both 'a ${NAME:=} default blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; unused="${S:=/}"; rm -rf "$S"'
# #7413: an assignment after plain statements joined by `;` or newline binds,
# since nothing before it can skip it.
expect_both 'an assignment after another statement allowed' 0 "${RDT_CWD[@]}" \
  --command 'mkdir -p /tmp/rdt-scratch; S=/tmp/rdt-scratch; rm -rf "$S"'
expect_both 'the second of two literals, used unquoted, allowed' 0 "${RDT_CWD[@]}" \
  --command 'R=/tmp/rdt-a; S=/tmp/rdt-scratch; rm -rf $S'
expect_both 'an assignment on a later line, then &&, allowed' 0 "${RDT_CWD[@]}" \
  --command $'mkdir -p /tmp/rdt-scratch\nS=/tmp/rdt-scratch && rm -rf ${S}'
expect_both 'a later literal outside the tree blocks' 2 "${RDT_CWD[@]}" \
  --command 'true; S=/etc; rm -rf $S'
# Still blocked: anything before the assignment that can skip it, run it
# elsewhere or hide it, a prefix assignment, and a use before it.
for rdt_cmd in 'false && S=/tmp/rdt-scratch; rm -rf $S' 'true || S=/tmp/rdt-scratch; rm -rf $S' \
  'echo | S=/tmp/rdt-scratch; rm -rf $S' 'true & S=/tmp/rdt-scratch; rm -rf $S' \
  $'if false; then\nS=/tmp/rdt-scratch\nfi\nrm -rf $S' $'while false; do\nS=/tmp/rdt-scratch\ndone\nrm -rf $S' \
  '(S=/tmp/rdt-scratch); rm -rf $S' $'(\nS=/tmp/rdt-scratch\n)\nrm -rf $S' \
  $'{ true\nS=/tmp/rdt-scratch; }\nrm -rf $S' '! true; S=/tmp/rdt-scratch; rm -rf $S' \
  $'cat <<EOF\nS=/tmp/rdt-scratch\nEOF\nrm -rf $S' $'true # ; S=/tmp/rdt-scratch\nrm -rf $S' \
  $'echo \'a\nS=/tmp/rdt-scratch\'\nrm -rf $S' $'echo \\\nS=/tmp/rdt-scratch; rm -rf $S' \
  $'true ||\nS=/tmp/rdt-scratch && rm -rf $S' $'true |\nS=/tmp/rdt-scratch; rm -rf $S' \
  'S=/tmp/rdt-scratch true; rm -rf $S' 'rm -rf $S; S=/tmp/rdt-scratch' \
  'rm -rf $S/x; S=/tmp/rdt-scratch; rm -rf $S'; do
  expect_both "outside the later-binding shape blocks: $rdt_cmd" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done
expect_both 'the bound name in a child shell blocks' 2 "${RDT_CWD[@]}" \
  --command "S=/tmp/rdt-scratch; ls \"\$S\"; sh -c 'rm -rf \"\$S\"'"
expect_both 'a different variable beside the bound one blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; mkdir -p "$S"; rm -rf "$T"'
# A builtin spelled through quotes, an escape, an expansion or a glob still
# reads as itself to bash, so any of those characters outside the bound words
# drops the binding.
expect_both 'a quoted-apart printf -v blocks' 2 "${RDT_CWD[@]}" \
  --command $'S=/tmp/rdt-scratch; pri\'\'ntf -v S %s /; rm -rf "$S"'
expect_both 'an escaped read blocks' 2 "${RDT_CWD[@]}" \
  --command $'S=/tmp/rdt-scratch; rea\\d S < f; rm -rf "$S"'
expect_both 'a builtin name built from a variable blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; P=pri; ${P}ntf -v S %s /; rm -rf "$S"'
expect_both 'a quoted dot command blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; "." ./f; rm -rf "$S"'
expect_both 'a globbed builtin name blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; builtin pri?tf -v S %s /; rm -rf "$S"'
expect_both 'an arithmetic subscript on the name blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; a[S++]=x; rm -rf "$S"'
expect_both 'a literal built from another variable blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=build; P=$S/probe; rm -rf $P'
# A later statement that may change the variable drops the binding.
expect_both 'a reassignment behind || blocks' 2 "${RDT_CWD[@]}" --command 'X=build; true || X=/; rm -rf "$X"'
expect_both 'a guarded first assignment blocks' 2 "${RDT_CWD[@]}" --command 'X=/; true || X=build; rm -rf "$X"'
expect_both 'read NAME blocks' 2 "${RDT_CWD[@]}" --command 'X=build; read X; rm -rf "$X"'
expect_both 'unset NAME blocks' 2 "${RDT_CWD[@]}" --command 'X=build; unset X; rm -rf "$X/"'
expect_both 'for NAME blocks' 2 "${RDT_CWD[@]}" --command 'X=build; for X in a b; do :; done; rm -rf "$X"'
expect_both 'printf -v NAME blocks' 2 "${RDT_CWD[@]}" --command "X=build; printf -v X '%s' /; rm -rf \"\$X\""
expect_both 'export NAME=... blocks' 2 "${RDT_CWD[@]}" --command 'X=build; export X=/; rm -rf "$X"'
expect_both 'eval blocks' 2 "${RDT_CWD[@]}" --command 'X=build; eval "$C"; rm -rf "$X"'
expect_both 'a function definition blocks' 2 "${RDT_CWD[@]}" --command 'X=build; f() { X=/; }; f; rm -rf "$X"'
expect_both 'an assignment inside if/then blocks' 2 "${RDT_CWD[@]}" --command 'if true; then X=build; fi; rm -rf "$X"'
expect_both 'an assignment in a subshell blocks' 2 "${RDT_CWD[@]}" --command '(X=build); rm -rf "$X"'
expect_both 'NAME= inside quotes elsewhere blocks' 2 "${RDT_CWD[@]}" --command 'X=build; echo "X=/"; rm -rf "$X"'
expect_both 'a value from a substitution blocks' 2 "${RDT_CWD[@]}" --command 'D=$(mktemp -d); rm -rf "$D"'
# Every arm still reads the literal, and only that exact shape is read.
expect_both 'X=/ && rm -rf "$X" blocks (root)' 2 "${RDT_CWD[@]}" --command 'X=/ && rm -rf "$X"'
expect_both 'X=/etc && rm -rf "$X" blocks (outside the tree)' 2 "${RDT_CWD[@]}" --command 'X=/etc && rm -rf "$X"'
expect_both 'X=build | rm -rf "$X" blocks (another shell)' 2 "${RDT_CWD[@]}" --command 'X=build | rm -rf "$X"'
expect_both 'X=build & rm -rf "$X" blocks (another shell)' 2 "${RDT_CWD[@]}" --command 'X=build & rm -rf "$X"'
expect_both 'X=build || rm -rf "$X" blocks' 2 "${RDT_CWD[@]}" --command 'X=build || rm -rf "$X"'
expect_both 'a reassignment from a substitution between them blocks' 2 "${RDT_CWD[@]}" \
  --command 'X=build && X=$(pwd) && rm -rf "$X"'
expect_both 'X=$(pwd) && rm -rf "$X" blocks' 2 "${RDT_CWD[@]}" --command 'X=$(pwd) && rm -rf "$X"'
expect_both 'X=~ && rm -rf "$X" blocks (tilde expands)' 2 "${RDT_CWD[@]}" --command 'X=~ && rm -rf "$X"'
expect_both 'X=build rm -rf "$X" blocks (prefix assignment expands too late)' 2 "${RDT_CWD[@]}" \
  --command 'X=build rm -rf "$X"'
expect_both 'X=build && bash -c rm -rf "$X" blocks (a child shell does not inherit X)' 2 "${RDT_CWD[@]}" \
  --command "X=build && bash -c 'rm -rf \"\$X\"'"
expect_both 'X=build && rm -rf "$Y" blocks (a different variable)' 2 "${RDT_CWD[@]}" --command 'X=build && rm -rf "$Y"'
expect_both 'X=build && rm -rf "$XY" blocks (a longer name)' 2 "${RDT_CWD[@]}" --command 'X=build && rm -rf "$XY"'
expect_both 'a literal beside a substitution blocks (the tokenizer splits on its parentheses)' 2 "${RDT_CWD[@]}" \
  --command 'X=build Y=$(pwd) && rm -rf "$X"'
expect_both 'the non-literal one beside it still blocks' 2 "${RDT_CWD[@]}" \
  --command 'X=build Y=$(pwd) && rm -rf "$Y"'

# Anything in the command that can set a variable out of sight drops every
# binding. Each of these once read X as `build` while the shell deleted /etc.
expect_both 'declare -n beside the literal blocks' 2 "${RDT_CWD[@]}" \
  --command 'X=build; declare -n R=X; R=/etc; rm -rf "$X"'
expect_both 'a DEBUG trap beside the literal blocks' 2 "${RDT_CWD[@]}" \
  --command 'X=build; trap ": ; X=/etc" DEBUG; rm -rf "$X"'
expect_both 'printf -vNAME beside the literal blocks' 2 "${RDT_CWD[@]}" \
  --command 'X=build; printf -vX /etc; rm -rf "$X"'
expect_both 'command eval beside the literal blocks' 2 "${RDT_CWD[@]}" \
  --command 'X=build; command eval ": ; X=/etc"; rm -rf "$X"'
expect_both 'builtin eval beside the literal blocks' 2 "${RDT_CWD[@]}" \
  --command 'X=build; builtin eval ": ; X=/etc"; rm -rf "$X"'
expect_both 'read <<< beside the literal blocks' 2 "${RDT_CWD[@]}" \
  --command 'X=build; read X <<< /etc; rm -rf "$X"'
expect_both 'IFS beside the literal blocks (an unquoted operand splits)' 2 "${RDT_CWD[@]}" \
  --command 'X=a/etc IFS=a && rm -rf $X'
expect_both 'IFS set before the literal blocks' 2 "${RDT_CWD[@]}" --command 'IFS=a; X=a/etc; rm -rf $X'

# An assignment that does not run first in this shell is no binding: a line
# that goes on through ||, | or \ (past a comment), a subshell, a substitution,
# a group or a branch. Each of these once read HOME as `build`.
expect_both 'an assignment after a || line end blocks' 2 "${RDT_CWD[@]}" \
  --command $'true ||\nHOME=build && rm -rf "$HOME"'
expect_both 'an assignment after a | line end blocks' 2 "${RDT_CWD[@]}" \
  --command $'true |\nHOME=build && rm -rf "$HOME"'
expect_both 'an assignment after a continued line blocks' 2 "${RDT_CWD[@]}" \
  --command $'true || \\\nHOME=build && rm -rf "$HOME"'
expect_both 'an assignment after || and a comment blocks' 2 "${RDT_CWD[@]}" \
  --command $'true || # c\nHOME=build && rm -rf "$HOME"'
expect_both 'an assignment after || and a quoted # blocks' 2 "${RDT_CWD[@]}" \
  --command $'echo "x\n#" ||\nHOME=build && rm -rf "$HOME"'
expect_both 'an assignment inside ( ) blocks' 2 "${RDT_CWD[@]}" \
  --command '(true; HOME=build) && rm -rf "$HOME"'
expect_both 'an assignment inside ( ) after a quoted ) blocks' 2 "${RDT_CWD[@]}" \
  --command 'echo ")"; (true; HOME=build) && rm -rf "$HOME"'
expect_both 'an assignment inside $( ) blocks' 2 "${RDT_CWD[@]}" \
  --command 'echo $(true; X=build) && rm -rf "$X"'
expect_both 'an assignment inside backticks blocks' 2 "${RDT_CWD[@]}" \
  --command 'echo `true; HOME=build` && rm -rf "$HOME"'
expect_both 'an assignment continued into a pipe blocks' 2 "${RDT_CWD[@]}" \
  --command $'HOME=build \\\n| rm -rf "$HOME"'
expect_both 'a comment line before the literal blocks' 2 "${RDT_CWD[@]}" \
  --command $'# clean the build\nX=build\nrm -rf "$X"'
expect_both 'a plain statement line before the literal allowed (#7413)' 0 "${RDT_CWD[@]}" \
  --command $'true\nX=build && rm -rf "$X"'

# --- 5c. An attended session asks instead of denying (refuse.sh) ---------------
# An ask is the verdict on the WHOLE command: any segment that denies, and any
# budget the reading runs past, denies the call, alone and through the row.
RDT_MANY=""
for ((rdt_i = 1; rdt_i <= 600; rdt_i++)); do RDT_MANY+=" a$rdt_i"; done
RDT_CDS=""
for ((rdt_i = 1; rdt_i <= 40; rdt_i++)); do RDT_CDS+="; cd x"; done
expect_both 'attended: a bare variable, then a delete past the target budget, denies' 2 "${RDT_CWD[@]}" \
  --command "rm -rf \"\$X\"; rm -rf$RDT_MANY" -- CLAUDE_CODE_SESSION_ATTENDED=1
expect_both 'attended: a root, then a delete past the target budget, denies' 2 "${RDT_CWD[@]}" \
  --command "rm -rf /; rm -rf$RDT_MANY" -- CLAUDE_CODE_SESSION_ATTENDED=1
expect_both 'attended: a root, then more directory changes than the budget, denies' 2 "${RDT_CWD[@]}" \
  --command "rm -rf /$RDT_CDS; rm -rf x" -- CLAUDE_CODE_SESSION_ATTENDED=1
expect 'attended: an operand past the brace budget denies before expanding' 2 "${RDT_CWD[@]}" \
  --command "rm -rf ${rdt_br}x" -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_contains 'attended: the brace budget refusal names its bound' "$GUARD_ERR" "too large to expand in time"
expect "attended: two asking segments ask once" 0 "${RDT_CWD[@]}" \
  --command 'rm -rf "$X"; rm -rf /etc/foo' -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_eq "attended: two asking segments: the decision is ask" ask \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
assert_contains "attended: the reason names the bare variable" \
  "$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$GUARD_OUT")" "bare variable ('\$X')"
assert_contains "attended: the reason names the outside-tree delete" \
  "$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$GUARD_OUT")" "recursive delete of '/etc/foo'"
expect "attended, dispatched: two asking segments ask once" 0 --via dispatched "${RDT_CWD[@]}" \
  --command 'rm -rf "$X"; rm -rf /etc/foo' -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_contains "attended, dispatched: the reason names both segments" \
  "$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$GUARD_OUT")" "/etc/foo"
expect "attended: rm -rf / exits 0 to ask" 0 --command 'rm -rf /' -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_eq "attended: the decision is ask" ask \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
assert_contains "attended: the reason names the root" \
  "$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$GUARD_OUT")" \
  "BLOCKED: recursive delete of a filesystem root (normalizes to '/')."
expect "attended: a bare variable asks" 0 --command 'rm -rf "$X"' -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_eq "attended: bare variable decision is ask" ask \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
expect "attended: a target outside the tree asks" 0 "${RDT_CWD[@]}" --command 'rm -rf /etc/x' -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_eq "attended: outside-tree decision is ask" ask \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
expect "attended=0: rm -rf / denies" 2 --command 'rm -rf /' -- CLAUDE_CODE_SESSION_ATTENDED=0
assert_eq "attended=0: no document" "" "$GUARD_OUT"
expect "attended unset: rm -rf / denies" 2 --command 'rm -rf /'
# A command the guard cannot finish reading names nothing a person could judge.
expect "attended: a command over the length cap still denies" 2 \
  --command "rm -rf $(printf 'x%.0s' {1..16400})" -- CLAUDE_CODE_SESSION_ATTENDED=1
expect "attended, dispatched: rm -rf / asks too" 0 --via dispatched \
  --command 'rm -rf /' -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_eq "attended, dispatched: the merged decision is ask" ask \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
expect "attended, dispatched: an outside-tree delete asks (decided in the judgment subshell)" 0 --via dispatched \
  "${RDT_CWD[@]}" --command 'rm -rf /etc/x' -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_eq "attended, dispatched: outside-tree decision is ask" ask \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
# Attended but unwatched: the ask would wait on a prompt nobody answers, so the
# guard denies and names the command for a person to run later (refuse.sh).
expect_both "unwatched: an outside-tree delete denies instead of asking" 2 "${RDT_CWD[@]}" \
  --command 'rm -rf /etc/x' -- CLAUDE_CODE_SESSION_ATTENDED=1 GUARDRAILS_SESSION_UNWATCHED=1
expect "unwatched: an outside-tree delete denies, alone" 2 "${RDT_CWD[@]}" \
  --command 'rm -rf /etc/x' -- CLAUDE_CODE_SESSION_ATTENDED=1 GUARDRAILS_SESSION_UNWATCHED=1
assert_eq "unwatched: no ask document" "" "$GUARD_OUT"
assert_contains "unwatched: the reason names the target" "$GUARD_ERR" "recursive delete of '/etc/x'"
assert_contains "unwatched: the reason says to leave it for later" "$GUARD_ERR" "Leave it for a person to run later"
assert_contains "unwatched: the reason names the command" "$GUARD_ERR" $'report this command:\nrm -rf /etc/x'
expect_both "unwatched: rm -rf / denies instead of asking" 2 \
  --command 'rm -rf /' -- CLAUDE_CODE_SESSION_ATTENDED=1 GUARDRAILS_SESSION_UNWATCHED=1
expect "unwatched=0: an attended outside-tree delete still asks" 0 "${RDT_CWD[@]}" \
  --command 'rm -rf /etc/x' -- CLAUDE_CODE_SESSION_ATTENDED=1 GUARDRAILS_SESSION_UNWATCHED=0
assert_eq "unwatched=0: the decision is ask" ask \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"

# --- 5d. Guards stay on in auto mode -------------------------------------------
expect_both "auto mode: rm -rf / still blocks" 2 \
  --payload '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"},"permission_mode":"auto"}'

# --- 5e. Parity with the retired user-level destructive-removal engine (#9770) --
# Every decision case of that engine's suite (dotfiles 59c12fd^,
# tools/claude-hooks/test-block-destructive-removal.py: 150 deny and 59 defer,
# 207 distinct), replayed in order from the git toplevel with the engine's
# verdict in each label. The engine is already retired (dotfiles 59c12fd), so
# these cases are the record of what it decided. Where this guard differs, the
# comment above the case says which side is right and why (#9770).
# Home roots are assembled from pieces so the source holds no literal user path.
RDT_EP_UH="/home/""user"
RDT_EP_MH="/Users/""user"
RDT_EP_WH='C:\''Users\user'
expect_both $'engine parity 1 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf /'
expect_both $'engine parity 2 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf /*'
expect_both $'engine parity 3 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf ~'
expect_both $'engine parity 4 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf ~/'
expect_both $'engine parity 5 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf ~/*'
expect_both $'engine parity 6 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -fr ~'
expect_both $'engine parity 7 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -r -f ~'
expect_both $'engine parity 8 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -f -r ~/*'
expect_both $'engine parity 9 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm --recursive --force ~/*'
expect_both $'engine parity 10 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm --force --recursive /*'
expect_both $'engine parity 11 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -R -f ~'
expect_both $'engine parity 12 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm --recursive -f ~'
expect_both $'engine parity 13 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf $HOME'
expect_both $'engine parity 14 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf "$HOME"'
expect_both $'engine parity 15 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf ${HOME}/*'
expect_both $'engine parity 16 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'/bin/rm -rf ~'
expect_both $'engine parity 17 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'cd /tmp && rm -rf ~'
# old expectation wrong: bash never expands %NAME%: a literal relative name inside the tree
expect_both $'engine parity 18 (Bash, engine deny)' 0 "${RDT_CWD[@]}" --command $'rm -rf %USERPROFILE%'
expect_both $'engine parity 19 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -Rf ~'
expect_both $'engine parity 20 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -RF /'
expect_both $'engine parity 21 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -r ~'
expect_both $'engine parity 22 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm --recursive ~'
expect_both $'engine parity 23 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf "~"'
expect_both $'engine parity 24 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'sudo rm -rf ~'
expect_both $'engine parity 25 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'command rm -rf /'
expect_both $'engine parity 26 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'\\rm -rf ~'
expect_both $'engine parity 27 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'\'rm\' -rf ~'
expect_both $'engine parity 28 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'time rm -rf ~'
expect_both $'engine parity 29 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'/usr/local/bin/rm -rf ~'
expect_both $'engine parity 30 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf /root'
expect_both $'engine parity 31 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf ~root'
expect_both $'engine parity 32 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf '"$RDT_EP_UH"
expect_both $'engine parity 33 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf '"$RDT_EP_MH"
expect_both $'engine parity 34 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force ~'
expect_both $'engine parity 35 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force "$env:USERPROFILE\\*"'
expect_both $'engine parity 36 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force $HOME'
expect_both $'engine parity 37 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'rm -Recurse -Force ~'
expect_both $'engine parity 38 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'ri -r -For ~\\*'
expect_both $'engine parity 39 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Rec -For $HOME'
expect_both $'engine parity 40 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'del -Recurse -Force C:\\*'
expect_both $'engine parity 41 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force '"$RDT_EP_WH"
expect_both $'engine parity 42 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force "'"$RDT_EP_WH"$'"'
expect_both $'engine parity 43 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force '"$RDT_EP_WH"$'\\'
expect_both $'engine parity 44 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force ${env:USERPROFILE}'
expect_both $'engine parity 45 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse ~'
expect_both $'engine parity 46 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse D:\\'
expect_both $'engine parity 47 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf //'
expect_both $'engine parity 48 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf ///'
expect_both $'engine parity 49 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf ~//'
expect_both $'engine parity 50 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf {~,/}'
expect_both $'engine parity 51 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf ~/{,.*}'
expect_both $'engine parity 52 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf ~/$(whoami)'
expect_both $'engine parity 53 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'eval "rm -rf ~"'
expect_both $'engine parity 54 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'sh -c "rm -rf ~"'
expect_both $'engine parity 55 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'bash -c "rm -rf /"'
expect_both $'engine parity 56 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse:$true -Force ~'
expect_both $'engine parity 57 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse:$true -Force $HOME'
expect_both $'engine parity 58 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse:$true -Force C:\\'
expect_both $'engine parity 59 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -rec:$true C:\\'
expect_both $'engine parity 60 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'ri -Recurse:$true $HOME'
expect_both $'engine parity 61 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force -Path:C:\\'
expect_both $'engine parity 62 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force -LiteralPath:$HOME'
expect_both $'engine parity 63 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force -Path:~'
expect_both $'engine parity 64 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'eval rm -rf ~'
expect_both $'engine parity 65 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'eval rm -rf ~/*'
expect_both $'engine parity 66 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'sh -cx "rm -rf ~"'
expect_both $'engine parity 67 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'bash -xc "rm -rf /"'
expect_both $'engine parity 68 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf {~,{/}}'
expect_both $'engine parity 69 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf {~,x{y,z}}'
expect_both $'engine parity 70 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf {a,b,~}'
expect_both $'engine parity 71 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force C:\\\\'
expect_both $'engine parity 72 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force C:\\/'
expect_both $'engine parity 73 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force C:\\\\\\\\'
expect_both $'engine parity 74 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf ~ ";"'
expect_both $'engine parity 75 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf "a;b" ~'
expect_both $'engine parity 76 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf ~ "|"'
expect_both $'engine parity 77 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'eval "true; rm -rf ~"'
expect_both $'engine parity 78 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'eval eval eval eval "rm -rf ~"'
expect_both $'engine parity 79 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'$SHELL -c "rm -rf ~"'
expect_both 'engine parity 79 companion: $SHELL -c "ls ~" is left alone' 0 "${RDT_CWD[@]}" --command '$SHELL -c "ls ~"'
expect_both 'engine parity 79 companion: $SHELL -c of an in-tree delete is left alone' 0 "${RDT_CWD[@]}" \
  --command '$SHELL -c "rm -rf build"'
expect_both $'engine parity 80 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'"$SHELL" -c "rm -rf ~"'
expect_both 'engine parity 80 companion: "$SHELL" -c of an in-tree delete is left alone' 0 "${RDT_CWD[@]}" \
  --command '"$SHELL" -c "rm -rf build"'
expect_both $'engine parity 81 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force -Path:\'C:\\\''
expect_both $'engine parity 82 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force -LiteralPath:"C:\\"'
expect_both $'engine parity 83 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force -Path:"$HOME"'
expect_both $'engine parity 84 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'env -i rm -rf ~'
expect_both $'engine parity 85 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'env -u PATH rm -rf ~'
expect_both $'engine parity 86 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'nice -n 10 rm -rf ~'
expect_both $'engine parity 87 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'ionice -c 3 rm -rf ~'
expect_both $'engine parity 88 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'stdbuf -o 0 rm -rf ~'
expect_both $'engine parity 89 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'doas -n rm -rf ~'
expect_both $'engine parity 90 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'setsid -w rm -rf ~'
expect_both $'engine parity 91 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'setsid --wait rm -rf ~'
expect_both $'engine parity 92 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'timeout 60 rm -rf ~'
expect_both $'engine parity 93 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'timeout 60s rm -rf ~'
expect_both $'engine parity 94 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'timeout 1.5h rm -rf ~'
expect_both $'engine parity 95 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'timeout -k 30s 60s rm -rf ~'
expect_both $'engine parity 96 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'timeout --foreground 60s rm -rf ~'
expect_both $'engine parity 97 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'nice -n 10 timeout 60s rm -rf ~'
expect_both $'engine parity 98 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf /c'
expect_both $'engine parity 99 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf /c/'
expect_both $'engine parity 100 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf /cygdrive/c'
expect_both $'engine parity 101 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf /c/Users/someone'
expect_both $'engine parity 102 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf \\\n~'
expect_both $'engine parity 103 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -rf \\\n/'
expect_both $'engine parity 104 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm -r\\\nf ~'
expect_both $'engine parity 105 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'sudo rm -rf \\\n'"$RDT_EP_UH"
expect_both $'engine parity 106 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force `\n~'
expect_both $'engine parity 107 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse `\n-Force '"$RDT_EP_WH"
expect_both $'engine parity 108 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'cmd /c rd /s /q '"$RDT_EP_WH"
expect_both $'engine parity 109 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'cmd /c "rd /s /q '"$RDT_EP_WH"$'"'
expect_both $'engine parity 110 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'cmd.exe /c rd /s /q '"$RDT_EP_WH"
expect_both $'engine parity 111 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'cmd /c rd /s/q '"$RDT_EP_WH"
expect_both $'engine parity 112 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'cmd /k del /s /q %USERPROFILE%'
expect_both 'engine parity 112 companion: cmd /c del /q of one file is left alone' 0 "${RDT_CWD[@]}" --tool PowerShell \
  --command 'cmd /c del /q build\x.txt'
expect_both 'engine parity 112 companion: cmd /c del /s under a named %NAME% subpath is left alone' 0 "${RDT_CWD[@]}" \
  --tool PowerShell --command 'cmd /c del /s /q %USERPROFILE%\proj'
expect_both 'engine parity 112 companion: cmd /c del /as reads /a attributes, not /s' 0 "${RDT_CWD[@]}" --tool PowerShell \
  --command 'cmd /c del /as /q %USERPROFILE%'
expect_both 'engine parity 112 companion: cmd /c del /qs reads the run-together /s, blocks' 2 "${RDT_CWD[@]}" \
  --tool PowerShell --command 'cmd /c del /qs %USERPROFILE%'
expect_both 'engine parity 112 companion: cmd /c del /q/s blocks' 2 "${RDT_CWD[@]}" --tool PowerShell \
  --command 'cmd /c del /q/s %USERPROFILE%'
expect_both 'engine parity 112 companion: cmd /k del /fs /q blocks' 2 "${RDT_CWD[@]}" --tool PowerShell \
  --command 'cmd /k del /fs /q %USERPROFILE%'
expect_both 'engine parity 112 companion: cmd /c del /ahs reads /a attributes, not /s' 0 "${RDT_CWD[@]}" \
  --tool PowerShell --command 'cmd /c del /ahs /q %USERPROFILE%'
expect_both 'engine parity 112 companion: cmd /c del /a:s reads /a attributes, not /s' 0 "${RDT_CWD[@]}" \
  --tool PowerShell --command 'cmd /c del /a:s /q %USERPROFILE%'
expect_both 'engine parity 112 companion: Bash cmd /c del /s /q %USERPROFILE% blocks' 2 "${RDT_CWD[@]}" \
  --command 'cmd /c del /s /q %USERPROFILE%'
expect_both 'engine parity 112 companion: Bash cmd /c "erase /s /q %USERPROFILE%" blocks' 2 "${RDT_CWD[@]}" \
  --command 'cmd /c "erase /s /q %USERPROFILE%"'
expect_both 'engine parity 112 companion: Bash cmd /c del /q of one file is left alone' 0 "${RDT_CWD[@]}" \
  --command 'cmd /c del /q build\x.txt'
expect_both $'engine parity 113 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'cmd /c rd /s /q C:\\'
# old expectation wrong: bash removes the backslashes, so cmd gets the drive-relative C:Usersname
expect_both $'engine parity 114 (Bash, engine deny)' 0 "${RDT_CWD[@]}" --command $'cmd /c rd /s /q '"$RDT_EP_WH"
expect_both $'engine parity 115 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'cmd /c rd /s /q /c/Users/someone'
expect_both $'engine parity 116 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'powershell -c "Remove-Item -Recurse -Force ~"'
expect_both $'engine parity 117 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'powershell.exe -Command "Remove-Item -Recurse -Force ~"'
expect_both $'engine parity 118 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'pwsh -Command "Remove-Item -Recurse -Force ~"'
expect_both $'engine parity 119 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'pwsh -c "rm -r -for $HOME"'
expect_both $'engine parity 120 (PowerShell, engine deny)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'bash -c "rm -rf ~"'
expect_both 'engine parity 120 companion: PS bash -c "ls ~" is left alone' 0 "${RDT_CWD[@]}" --tool PowerShell \
  --command 'bash -c "ls ~"'
expect_both 'engine parity 120 companion: PS bash -c of an in-tree delete is left alone' 0 "${RDT_CWD[@]}" --tool PowerShell \
  --command 'bash -c "rm -rf build"'
expect_both 'engine parity 120 companion: PS bash -c shred, a Bash-lane word, blocks' 2 "${RDT_CWD[@]}" --tool PowerShell \
  --command "bash -c 'shred -u x; rm -rf ~'"
expect_both 'engine parity 120 companion: PS wsl rm -rf ~ blocks' 2 "${RDT_CWD[@]}" --tool PowerShell \
  --command 'wsl rm -rf ~'
expect_both 'engine parity 120 companion: PS wsl ls ~ is left alone' 0 "${RDT_CWD[@]}" --tool PowerShell \
  --command 'wsl ls ~'
expect_both 'engine parity 120 companion: Start-Process bash with a quoted -c text blocks' 2 "${RDT_CWD[@]}" \
  --tool PowerShell --command "Start-Process bash -ArgumentList '-c \"rm -rf ~\"'"
# old expectation wrong: a single-quoted -c text is a string literal; nothing runs
expect_both $'engine parity 121 (PowerShell, engine deny)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'cmd /c "powershell -c \'Remove-Item -Recurse ~\'"'
expect_both $'engine parity 122 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'rm.exe -rf ~'
# old expectation wrong: the escaped quotes are part of the path, a relative name that cannot exist on Windows
expect_both $'engine parity 123 (PowerShell, engine deny)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force `"~`"'
# old expectation wrong: the escaped quotes are part of the path, a relative name that cannot exist on Windows
expect_both $'engine parity 124 (PowerShell, engine deny)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force `"'"$RDT_EP_WH"$'`"'
# old expectation wrong: the escaped quotes are part of the path, a relative name that cannot exist on Windows
expect_both $'engine parity 125 (PowerShell, engine deny)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'ri -Recurse -Force `"$HOME`"'
expect_both $'engine parity 126 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'echo $\'it\\\'s\' ; rm -rf ~'
# a parse error: bash runs nothing, and the command reader refuses the call
# as it refuses any text shfmt cannot parse, which is the engine's verdict too
expect_both $'engine parity 127 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'echo \'unterminated ; rm -rf ~'
# a parse error: bash runs nothing, and the command reader refuses the call
# as it refuses any text shfmt cannot parse, which is the engine's verdict too
expect_both $'engine parity 128 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'echo "unterminated && rm -rf /'
# old expectation wrong: a parse error: PowerShell runs nothing
expect_both $'engine parity 129 (PowerShell, engine deny)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'Write-Host \'oops ; Remove-Item -Recurse -Force ~'
expect_both $'engine parity 130 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs rm -rf ~'
expect_both $'engine parity 131 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs rm -rf /'
expect_both $'engine parity 132 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs rm -rf $HOME'
expect_both $'engine parity 133 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs rm.exe -rf ~'
expect_both $'engine parity 134 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'sudo xargs rm -rf ~'
expect_both $'engine parity 135 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs -n 1 rm -rf ~'
expect_both $'engine parity 136 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs -I {} rm -rf ~'
expect_both $'engine parity 137 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs -P 4 rm -rf ~'
expect_both $'engine parity 138 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs -a list.txt rm -rf ~'
expect_both $'engine parity 139 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs -d , -L 1 rm -rf ~'
expect_both $'engine parity 140 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs -n1 rm -rf ~'
expect_both $'engine parity 141 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs -I{} rm -rf ~'
expect_both $'engine parity 142 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs -r rm -rf ~'
expect_both $'engine parity 143 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs -0 rm -rf ~'
expect_both $'engine parity 144 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs -t rm -rf ~'
expect_both $'engine parity 145 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs -rt rm -rf /'
expect_both $'engine parity 146 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs --replace rm -rf ~'
expect_both $'engine parity 147 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs --replace={} rm -rf ~'
expect_both $'engine parity 148 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs --max-lines rm -rf ~'
expect_both $'engine parity 149 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs --max-args=1 rm -rf ~'
expect_both $'engine parity 150 (Bash, engine deny)' 2 "${RDT_CWD[@]}" --command $'xargs --max-args 1 rm -rf ~'
expect_both $'engine parity 151 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm file.txt'
expect_both $'engine parity 152 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -f file.txt'
expect_both $'engine parity 153 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -r ./build'
expect_both $'engine parity 154 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf ./node_modules'
# plugin stricter, kept: a target outside the session's allowed roots
expect_both $'engine parity 155 (Bash, engine allow)' 2 "${RDT_CWD[@]}" --command $'rm -rf ~/projects/build'
expect_both $'engine parity 156 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'git rm -rf .'
expect_both $'engine parity 157 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'echo rm -rf ~'
expect_both $'engine parity 158 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'ls -la ~'
expect_both $'engine parity 159 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf /tmp/scratch'
expect_both $'engine parity 160 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'grep -rf pattern ~'
# plugin stricter, kept: a relative operand is judged from every directory the command may run it from
expect_both $'engine parity 161 (Bash, engine allow)' 2 "${RDT_CWD[@]}" --command $'cd / && rm -rf build'
expect_both $'engine parity 162 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf build && cp x ~'
expect_both $'engine parity 163 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf node_modules; ls ~'
expect_both $'engine parity 164 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf dist || echo failed; cd ~'
# plugin stricter, kept: a target outside the session's allowed roots
expect_both $'engine parity 165 (Bash, engine allow)' 2 "${RDT_CWD[@]}" --command $'rm -rf '"$RDT_EP_UH"$'/projects'
expect_both $'engine parity 166 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force .\\dist'
expect_both $'engine parity 167 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item ~'
expect_both $'engine parity 168 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'Get-ChildItem ~'
# plugin stricter, kept: a target outside the session's allowed roots
expect_both $'engine parity 169 (PowerShell, engine allow)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force '"$RDT_EP_WH"$'\\projects\\build' # portability-ok: a Windows path, not a regex \\b
expect_both $'engine parity 170 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force @params'
expect_both $'engine parity 171 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf $(echo ~)'
expect_both $'engine parity 172 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf $(echo /*)'
# plugin stricter, kept: a find delete, which the engine did not read
expect_both $'engine parity 173 (Bash, engine allow)' 2 "${RDT_CWD[@]}" --command $'find / -delete'
# plugin stricter, kept: a find delete, which the engine did not read
expect_both $'engine parity 174 (Bash, engine allow)' 2 "${RDT_CWD[@]}" --command $'find ~ -delete'
expect_both $'engine parity 175 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf build/{a,b}'
expect_both $'engine parity 176 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf ./$(date)'
expect_both $'engine parity 177 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'bash -c "ls ~"'
expect_both $'engine parity 178 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'sh -c "echo hi"'
expect_both $'engine parity 179 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse:$false ~'
expect_both $'engine parity 180 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force -Path:.\\dist'
# plugin stricter, kept: a pipeline removal of what the listing names
expect_both $'engine parity 181 (PowerShell, engine allow)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'Get-ChildItem -Force C:\\ | Remove-Item -Recurse -Force'
expect_both $'engine parity 182 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf {a,b}'
expect_both $'engine parity 183 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'eval ls ~'
expect_both $'engine parity 184 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'sh -cx "echo hi"'
expect_both $'engine parity 185 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf a//b'
expect_both $'engine parity 186 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf .//dist'
expect_both $'engine parity 187 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf "./my;dir"'
expect_both $'engine parity 188 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'echo "a; rm -rf ~"'
expect_both $'engine parity 189 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'Remove-Item -Recurse -Force -Path:\'.\\dist\''
expect_both $'engine parity 190 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf build \\\ndist'
expect_both $'engine parity 191 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'rm -rf \\\n./node_modules'
expect_both $'engine parity 192 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'cmd /c dir C:\\'
expect_both $'engine parity 193 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'cmd /c rd /s /q .\\dist'
expect_both $'engine parity 194 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'cmd /c rd '"$RDT_EP_WH"
expect_both $'engine parity 195 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'cmd /c del /q '"$RDT_EP_WH"$'\\notes.txt'
expect_both $'engine parity 196 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'cmd /c echo rd /s /q '"$RDT_EP_WH"
expect_both $'engine parity 197 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'powershell -Command "Get-ChildItem ~"'
# plugin stricter, kept: the value is not UTF-16LE text, refused as a decoder sink
expect_both $'engine parity 198 (PowerShell, engine allow)' 2 "${RDT_CWD[@]}" --tool PowerShell --command $'powershell -EncodedCommand cm0gLXJmIH4='
expect_both $'engine parity 199 (PowerShell, engine allow)' 0 "${RDT_CWD[@]}" --tool PowerShell --command $'Write-Host `"~`"'
expect_both $'engine parity 200 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'echo "unbalanced quote here'
expect_both $'engine parity 201 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'echo \'oops ; ls ~'
expect_both $'engine parity 202 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'xargs grep foo'
# plugin stricter, kept: xargs items arrive on stdin, so the target cannot be placed
expect_both $'engine parity 203 (Bash, engine allow)' 2 "${RDT_CWD[@]}" --command $'xargs rm -rf build'
# plugin stricter, kept: xargs items arrive on stdin, so the target cannot be placed
expect_both $'engine parity 204 (Bash, engine allow)' 2 "${RDT_CWD[@]}" --command $'xargs -n 1 rm -rf ./dist'
# plugin stricter, kept: xargs items arrive on stdin, so the target cannot be placed
expect_both $'engine parity 205 (Bash, engine allow)' 2 "${RDT_CWD[@]}" --command $'xargs -I {} rm -rf '"$RDT_EP_UH"$'/projects/{}'
expect_both $'engine parity 206 (Bash, engine allow)' 0 "${RDT_CWD[@]}" --command $'xargs ls ~'
# plugin stricter, kept: a listing of the git toplevel piped into a delete
expect_both $'engine parity 207 (Bash, engine allow)' 2 "${RDT_CWD[@]}" --command $'find . -name \'*.tmp\' | xargs rm -rf'
# The dangerous spellings the cases the engine misread were aiming at.
expect_both 'engine parity companion: rm -rf "$USERPROFILE" blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf "$USERPROFILE"'
expect_both 'engine parity companion: cmd /c rd /s /q with a quoted profile path blocks' 2 "${RDT_CWD[@]}" \
  --command "cmd /c rd /s /q '$RDT_EP_WH'"
expect_both 'engine parity companion: PS Remove-Item -Recurse "~" blocks' 2 "${RDT_CWD[@]}" --tool PowerShell \
  --command 'Remove-Item -Recurse -Force "~"'
expect_both 'engine parity companion: cmd /c powershell -c unquoted blocks' 2 "${RDT_CWD[@]}" --tool PowerShell \
  --command 'cmd /c "powershell -c Remove-Item -Recurse ~"'
expect_both 'engine parity companion: cmd /c powershell -c of an in-tree delete is left alone' 0 "${RDT_CWD[@]}" \
  --tool PowerShell --command 'cmd /c "powershell -c Remove-Item -Recurse build"'
expect_both 'engine parity companion: a cmd /c statement after & is judged' 2 "${RDT_CWD[@]}" --tool PowerShell \
  --command 'cmd /c "echo x & rd /s /q C:\"'
expect_both 'engine parity companion: a balanced rm -rf ~ after echo blocks' 2 "${RDT_CWD[@]}" \
  --command "echo 'terminated' ; rm -rf ~"

# --- 6. Kill switch ----------------------------------------------------------
expect "kill switch disables the guard" 0 --command 'rm -rf /' \
  -- "CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ENABLED=false"

# --- 7. The guard installs no exit-time handler of its own --------------------
# abort-boundary.sh owns that slot for every guard in this plugin; a second one
# in the guard would run after it and could change the status the boundary
# settled. abort-boundary.test.sh asserts the same property across the whole
# set, and this pins it for this file on its own.
own_traps="$(grep -n 'trap' "$HOOK" | grep -Ei 'trap[^#]*(EXIT|[[:space:]]0[[:space:]]*$)' || true)"
assert_eq "the guard installs no exit-time handler of its own" "" "$own_traps"

rdt_finish
