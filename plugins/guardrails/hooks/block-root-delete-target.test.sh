#!/usr/bin/env bash
# Contract test for block-root-delete-target.sh (guardrails plugin).
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

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-root-delete-target.sh"
GUARD_UNDER_TEST="$HOOK"
TEST_TMPDIR="$(mktemp -d)"
RDT_AB=""
trap 'rm -rf "$TEST_TMPDIR" "$RDT_AB"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
# An interactive session exports CLAUDE_CODE_SESSION_ATTENDED=1, which turns a
# refusal into an ask (refuse.sh). Every case below asserts the deny unless it
# sets the flag itself.
unset CLAUDE_CODE_SESSION_ATTENDED

# --- 1. MUST FIRE: the operand normalizes to a filesystem root ----------------
# The measured gap this guard closes. `rm -rf "\\"` passed all eight guards of
# the Bash dispatcher at rc 0, because no guard inspected the TARGET of a
# recursive delete at all.
expect_both 'rm -rf "\\" blocks' 2 --command 'rm -rf "\\"'
expect_both 'rm -rf \\ blocks' 2 --command 'rm -rf \\'
expect_both 'rm -rf / blocks' 2 --command 'rm -rf /'
expect_both 'rm -rf /* blocks' 2 --command 'rm -rf /*'
expect_both 'rm -rf "//" blocks' 2 --command 'rm -rf "//"'

# Recursion spelled every way the flag parser must recognize.
expect_both 'rm -r / blocks' 2 --command 'rm -r /'
expect_both 'rm --recursive / blocks' 2 --command 'rm --recursive /'
expect_both 'rm -Rf / blocks (capital R)' 2 --command 'rm -Rf /'
expect_both 'rm -rf -- / blocks (end of options)' 2 --command 'rm -rf -- /'

# Home, in the spellings the tokenizer hands over verbatim. Detection never
# evaluates an expansion, so `$HOME` is matched as the literal it is written as.
expect_both 'rm -rf ~ blocks' 2 --command 'rm -rf ~'
expect_both 'rm -rf $HOME blocks' 2 --command 'rm -rf $HOME'
expect_both 'rm -rf "$HOME" blocks' 2 --command 'rm -rf "$HOME"'
expect_both 'rm -rf ${HOME} blocks' 2 --command 'rm -rf ${HOME}'

# Windows and MSYS drive roots. `C:\` arrives from the tokenizer as `C:`,
# because the backslash is a bash escape; `C:/` keeps its slash. Both normalize
# to the same drive root.
expect_both 'rm -rf C:\ blocks' 2 --command 'rm -rf C:\'
expect_both 'rm -rf c:/ blocks' 2 --command 'rm -rf c:/'
expect_both 'rm -rf C: blocks' 2 --command 'rm -rf C:'
expect_both 'rm -rf /c blocks (MSYS drive root)' 2 --command 'rm -rf /c'
expect_both 'rm -rf /c/* blocks' 2 --command 'rm -rf /c/*'
expect_both 'rm -rf /mnt/c blocks (WSL drive root)' 2 --command 'rm -rf /mnt/c'
expect_both 'rm -rf /cygdrive/c blocks' 2 --command 'rm -rf /cygdrive/c'

# Command-word resolution: a launcher, a path-qualified name, an .exe suffix
# and a quote-escaped name all resolve to the same `rm`.
expect_both 'sudo rm -rf / blocks' 2 --command 'sudo rm -rf /'
expect_both 'env rm -rf / blocks' 2 --command 'env rm -rf /'
expect_both '/bin/rm -rf / blocks' 2 --command '/bin/rm -rf /'
expect_both 'rm.exe -rf / blocks' 2 --command 'rm.exe -rf /'
expect_both '\rm -rf / blocks (quote-escaped name)' 2 --command '\rm -rf /'

# A later segment of a compound command is inspected on its own.
expect_both 'cd foo && rm -rf / blocks' 2 --command 'cd foo && rm -rf /'

# A RESERVED WORD ahead of `rm` is not the command word. The tokenizer splits on
# `;`, `&`, `|`, `(` and `)`, so a compound command hands the callback a segment
# that OPENS with one: `{ rm -rf /`, `then rm -rf /`, and every loop body as
# `do rm -rf /`. Read as a command word, each of those waved the segment through.
expect_both 'brace group blocks' 2 --command '{ rm -rf /; }'
expect_both 'if/then blocks' 2 --command 'if true; then rm -rf /; fi'
expect_both 'if/else blocks' 2 --command 'if false; then :; else rm -rf /; fi'
expect_both 'if/elif blocks' 2 --command 'if false; then :; elif rm -rf /; then :; fi'
expect_both 'while/do blocks' 2 --command 'while :; do rm -rf /; done'
expect_both 'until blocks' 2 --command 'until rm -rf /; do :; done'
expect_both 'for/do blocks' 2 --command 'for d in a b; do rm -rf /; done'
expect_both 'negation blocks' 2 --command '! rm -rf /'
# `f()` needs no arm of its own: `(` is a segment separator, so the name has
# already closed its own segment and `{` is what opens the body. `function`
# does, because it and the name it introduces are both argv words of the body's
# segment.
expect_both 'function definition blocks' 2 --command 'f() { rm -rf /; }; f'
expect_both 'function keyword definition blocks' 2 --command 'function f { rm -rf /; }; f'
# These three already blocked before the reserved-word walk existed, because
# `(` and `)` are segment separators and `time` is a launcher. Pinned so they
# stay that way.
expect_both 'subshell blocks' 2 --command '(rm -rf /)'
expect_both 'spaced subshell blocks' 2 --command '( rm -rf / )'
expect_both 'case arm blocks' 2 --command 'case x in x) rm -rf / ;; esac'
expect_both 'time rm -rf / blocks' 2 --command 'time rm -rf /'
# `coproc [NAME] command`, and bash takes the NAME only ahead of a COMPOUND
# command. Ahead of a SIMPLE one the first word IS the command, so stepping over
# any identifier that merely had a word after it swallowed the real command
# word and let a child shell through.
expect_both 'coproc blocks' 2 --command 'coproc rm -rf --no-preserve-root /'
expect_both 'coproc brace group blocks' 2 --command 'coproc { rm -rf /; }'
expect_both 'coproc NAME brace group blocks' 2 --command 'coproc shredder { rm -rf /; }'
expect_both 'coproc bash -c blocks' 2 --command "coproc bash -c 'rm -rf /'"
expect_both 'coproc eval blocks' 2 --command 'coproc eval "rm -rf /"'
expect_both 'coproc su -c blocks' 2 --command "coproc su -c 'rm -rf /'"

# Any operand may be the root, not only the first.
expect_both 'rm -rf ./ok / blocks on the second operand' 2 --command 'rm -rf ./ok /'

# --no-preserve-root is refused whatever the operand: the flag exists only to
# defeat the one protection coreutils ships for this mistake.
expect_both 'rm -rf --no-preserve-root ./x blocks' 2 --command 'rm -rf --no-preserve-root ./x'

# A trailing segment that carries no NAME leaves the operand rooted where it
# started, so every one of these still names a root. Stripping one glob suffix
# was not enough: `/*/` keeps a trailing slash, `/./*` keeps a dot segment, and
# `/.[!.]*` is the ordinary dotfile idiom.
expect_both 'rm -rf /*/ blocks' 2 --command 'rm -rf /*/'
expect_both 'rm -rf /./* blocks' 2 --command 'rm -rf /./*'
expect_both 'rm -rf /.[!.]* blocks (dotfile idiom)' 2 --command 'rm -rf /.[!.]*'
expect_both 'rm -rf ~/./* blocks' 2 --command 'rm -rf ~/./*'
expect_both 'rm -rf /c/*/ blocks' 2 --command 'rm -rf /c/*/'
expect_both 'rm -rf /. blocks' 2 --command 'rm -rf /.'
expect_both 'rm -rf /.. blocks' 2 --command 'rm -rf /..'

# A launcher option that takes its own operand must not swallow the command
# word. `sudo -u bob rm` puts `bob` where a naive skip reads the command.
expect_both 'sudo -u bob rm -rf / blocks' 2 --command 'sudo -u bob rm -rf /'
expect_both 'env -u FOO rm -rf / blocks' 2 --command 'env -u FOO rm -rf /'
expect_both 'timeout 60 rm -rf / blocks' 2 --command 'timeout 60 rm -rf /'
# `--` ends options, not the duration; a word that cannot be a duration is the
# command word.
expect_both 'timeout -- 5 rm -rf / blocks' 2 --command 'timeout -- 5 rm -rf /'
expect_both 'timeout -- rm -rf / blocks' 2 --command 'timeout -- rm -rf /'
# The duration after `--` is read in strtod's shape: space, a sign, inf.
expect_both 'timeout -- +5 rm -rf /* blocks' 2 --command 'timeout -- +5 rm -rf /*'
expect_both "timeout -- ' 5' rm -rf /* blocks" 2 --command "timeout -- ' 5' rm -rf /*"
expect_both 'timeout -- inf rm -rf /* blocks' 2 --command 'timeout -- inf rm -rf /*'
expect_both 'timeout --k 1 5 rm -rf /* blocks (abbreviated --kill-after)' 2 --command 'timeout --k 1 5 rm -rf /*'
# The prefix reading is judged beside the plain one, never instead of it, so a
# launcher this guard already walked keeps every refusal it had.
expect_both 'nice --adj rm -rf /* blocks' 2 --command 'nice --adj rm -rf /*'
expect_both 'ionice --cl rm -rf /* blocks' 2 --command 'ionice --cl rm -rf /*'
expect_both 'env --ch rm -rf /* blocks' 2 --command 'env --ch rm -rf /*'
expect_both 'stdbuf --ou rm -rf /* blocks' 2 --command 'stdbuf --ou rm -rf /*'
expect_both 'timeout --k 1 rm -rf /* blocks' 2 --command 'timeout --k 1 rm -rf /*'
expect_both 'nice --adj 5 ls / allowed' 0 --command 'nice --adj 5 ls /'
# Both readings are judged for EVERY segment: an earlier segment spending some
# shared budget, or many abbreviations in one segment, must not leave a later
# delete judged on the plain reading alone.
rdt_wa=""
for ((rdt_d = 0; rdt_d < 17; rdt_d++)); do rdt_wa+="--wa 1 "; done
expect_both 'abbreviations in earlier segments do not spend the later check' 2 \
  --command 'flock --wa 1 --wa 1 --wa 1 --wa 1 --wa 1 f true; flock --wa 1 f rm -rf /*'
expect_both 'repeated timeout --si segments still check the last' 2 \
  --command 'timeout --si KILL 5 true; timeout --si KILL 5 true; timeout --si KILL 5 true; timeout --si KILL 5 true; timeout --si KILL 5 true; timeout --si KILL 5 rm -rf /*'
expect_both '17 abbreviations in one segment blocks' 2 --command "flock ${rdt_wa}f rm -rf /*"
expect_both '17 abbreviations in one segment blocks on C:\' 2 --command "flock ${rdt_wa}f rm -rf C:\\"
expect_both 'dangling backslash after abbreviation segments blocks' 2 \
  --command 'flock --wa 1 --wa 1 --wa 1 --wa 1 --wa 1 f true; flock --wa 1 f rm -rf \'
expect_both '17 abbreviations with an ordinary delete allowed' 0 --command "flock ${rdt_wa}f rm -rf ./build"
rdt_ok20=""
for ((rdt_d = 0; rdt_d < 20; rdt_d++)); do rdt_ok20+="timeout 5 true; "; done
expect_both 'twenty ordinary timeout segments then an ordinary delete allowed' 0 --command "${rdt_ok20}rm -rf ./build"
# Past the cap on resolved walks the guard REFUSES rather than judging one
# reading only; the limit is far above any command a person writes.
rdt_cap=""
for ((rdt_d = 0; rdt_d < 260; rdt_d++)); do rdt_cap+="flock --wa 1 f true; "; done
guard_invoke --command "${rdt_cap}rm -rf ./build"
assert_exit "past the abbreviation cap the guard refuses" 2 "$GUARD_RC"
assert_contains "the refusal names the abbreviation cap" "$GUARD_ERR" "too many command segments with abbreviated launcher options"
expect_both 'timeout -- 5 ls / allowed' 0 --command 'timeout -- 5 ls /'
expect_both 'nice -n 10 rm -rf / blocks' 2 --command 'nice -n 10 rm -rf /'
expect_both 'nohup rm -rf / blocks' 2 --command 'nohup rm -rf /'
expect_both 'stdbuf -o L rm -rf / blocks' 2 --command 'stdbuf -o L rm -rf /'
expect_both 'time -f FMT rm -rf / blocks' 2 --command '/usr/bin/time -f FMT rm -rf /'
expect_both 'exec -a foo rm -rf / blocks' 2 --command 'exec -a foo rm -rf /'
# The LONG spelling of an operand-taking option moves the command word exactly
# as the short one does, so every short form listed carries its long alias.
# `--opt=value` carries its own operand and consumes no following word.
expect_both 'sudo --user root rm -rf / blocks' 2 --command 'sudo --user root rm -rf /'
expect_both 'sudo --user=root rm -rf / blocks' 2 --command 'sudo --user=root rm -rf /'
expect_both 'env --chdir /tmp rm -rf / blocks' 2 --command 'env --chdir /tmp rm -rf /'
expect_both 'nice --adjustment 5 rm -rf / blocks' 2 --command 'nice --adjustment 5 rm -rf /'
expect_both 'ionice --class 2 rm -rf / blocks' 2 --command 'ionice --class 2 rm -rf /'
expect_both 'stdbuf --output L rm -rf / blocks' 2 --command 'stdbuf --output L rm -rf /'
# GNU env's `-S` is not an option argument to step over: env SPLITS the operand
# and RUNS it, so it is re-parsed as the command it is.
expect_both 'env -S rm -rf / blocks' 2 --command "env -S 'rm -rf /'"
expect_both 'env --split-string rm -rf / blocks' 2 --command "env --split-string 'rm -rf /'"
expect_both 'env --split-string= rm -rf / blocks' 2 --command "env --split-string='rm -rf /'"

# A command substitution RUNS before the word it builds is used, so the shell
# executes the inner command whatever the outer one is. The tokenizer keeps a
# substitution inside the enclosing word, so its body is scanned separately.
expect_both 'echo "$(rm -rf /)" blocks' 2 --command 'echo "$(rm -rf /)"'
expect_both 'echo $(rm -rf /) blocks' 2 --command 'echo $(rm -rf /)'
expect_both 'backtick substitution blocks' 2 --command 'echo `rm -rf /`'
expect_both 'nested substitution blocks' 2 --command 'echo "$(echo "$(rm -rf /)")"'
expect_both 'substitution with --no-preserve-root blocks' 2 \
  --command 'echo "$(rm -rf --no-preserve-root /)"'
expect_both 'substitution in an assignment blocks' 2 --command 'x="$(rm -rf ~)"'

# The scan honors QUOTING when it looks for the END of a body too, so a `)`
# sitting inside a quoted span is not the terminator. Reading raw characters cut
# the body off at that paren and lost the delete standing behind it.
expect_both 'quoted paren inside a substitution body blocks' 2 \
  --command "echo \"\$(printf '%s\n' ')'; rm -rf --no-preserve-root /)\""
expect_both 'quoted paren then a root operand blocks' 2 \
  --command "echo \"\$(printf ')'; rm -rf /)\""

# Nesting is capped, and the cap REFUSES rather than allows: the abort boundary
# is fail-OPEN, so a scanner that ran out of room would answer allow on exactly
# the payload built to exhaust it. The innermost command here is harmless, so
# the cap is the only thing that can refuse this one.
rdt_deep=""
for ((rdt_d = 0; rdt_d < 40; rdt_d++)); do rdt_deep="\$($rdt_deep"; done
rdt_deep="${rdt_deep}echo rm"
for ((rdt_d = 0; rdt_d < 40; rdt_d++)); do rdt_deep="$rdt_deep)"; done
expect_both 'substitution nested 40 deep is refused' 2 --command "$rdt_deep"

# The depth cap bounds the NESTING, not the WORK. The tokenizer splits on
# unquoted `(`, `)` and `;`, so a payload at the command ceiling nested to just
# under the depth cap yields as many segments as a flat one AND a body to
# re-tokenize per level. It ran for 40 s alone and 48 s under the dispatcher,
# against a 60 s hook timeout, and a hook the harness cancels on that timeout is
# cancelled WITHOUT a block: the slow path failed OPEN. A MAX_COMMAND_LEN budget
# over the SUBSTITUTION BODIES, spent before the top-level parse, is what bounds
# it. `timeout 20` is the backstop, and it is the only timing assertion here: a
# hang reads as rc 124 rather than as a pass, while a wall-clock threshold on a
# shared CI shard measures the shard rather than the guard. The bound is set
# against a HANG, not against the refusal's own cost, which is about 5 s here;
# 20 keeps room for a loaded shard while still catching the fail-open shape
# this pin exists for.
rdt_pad=""
while ((${#rdt_pad} < 15900)); do rdt_pad+="rm -rf ./x; "; done
rdt_big=""
for ((rdt_d = 0; rdt_d < 32; rdt_d++)); do rdt_big="\$($rdt_big"; done
rdt_big="${rdt_big}${rdt_pad}"
for ((rdt_d = 0; rdt_d < 32; rdt_d++)); do rdt_big="$rdt_big)"; done
rdt_payload="$(command_json "$rdt_big")"
# command_json passes the command to a native jq without MSYS_NO_PATHCONV, so
# its round trip is checked: Git Bash would rewrite a `NAME=/path` argument.
assert_eq "the 16 KB payload carries its command verbatim" "$rdt_big" "$(jq -r .tool_input.command <<<"$rdt_payload")"

for rdt_via in direct dispatched; do
  if [[ "$rdt_via" == direct ]]; then
    rdt_argv=(bash "$HOOK")
  else
    rdt_argv=(bash "$GUARD_DISPATCH" "$HOOK")
  fi
  rdt_rc=0
  rdt_err="$(timeout 20 "${rdt_argv[@]}" <<<"$rdt_payload" 2>&1 >/dev/null)" || rdt_rc=$?
  assert_exit "a 16 KB 32-deep payload is refused ($rdt_via)" 2 "$rdt_rc"
  assert_contains "the refusal names the tokenizing budget ($rdt_via)" \
    "$rdt_err" "substitution bodies exceed MAX_COMMAND_LEN in total"
done
# The budget counts SUBSTITUTION BODIES ONLY. Charging the command's own length
# against it too refused any command past about half the ceiling that carried
# one ordinary substitution, while leaving a flat command just under the ceiling
# alone, which is a size limit on the wrong thing.
rdt_ok=""
while ((${#rdt_ok} < 8180)); do rdt_ok+="echo ok; "; done
expect_both 'a long benign command with one rm-bearing body is allowed' 0 \
  --command "${rdt_ok}\$(echo rm)"

# SIBLING bodies cannot exhaust this budget by construction: each one's text
# sits in the command, and the command has its own ceiling. 900 of them total
# 13,500 characters of body text and are allowed. 1,300 total 19,500, which no
# command under MAX_COMMAND_LEN can hold, so that payload is refused by the
# COMMAND ceiling instead, and the message is pinned to keep the difference
# visible. One arm each: the budget is internal to the guard, so the dispatcher
# cannot decide it differently, and both payloads are slow to build.
rdt_sib() {
  local n="$1" s="echo " k
  for ((k = 0; k < n; k++)); do s+="\$(echo rm 1234567)"; done
  printf '%s' "$s"
}
expect '900 sibling rm-bearing bodies are allowed' 0 --command "$(rdt_sib 900)"
guard_invoke --command "$(rdt_sib 1300)"
assert_exit "1300 sibling rm-bearing bodies are refused" 2 "$GUARD_RC"
assert_contains "1300 siblings are refused by the COMMAND ceiling, not the body budget" \
  "$GUARD_ERR" "the command is too long to parse"

# Launcher, child-shell and eval nesting is recursion in the guard. Unbounded,
# 120 nested runusers exhausted bash's stack inside the block's telemetry, so
# the BLOCKED message printed and the process still exited 0, and deeper ones
# died on SIGSEGV. Past MAX_SEGMENT_DEPTH the guard refuses, and nested evals
# are charged to the tokenizing budget so they refuse fast rather than
# outrunning the hook timeout.
rdt_rep() {
  local s="" k
  for ((k = 0; k < $2; k++)); do s+="$1"; done
  printf '%s' "$s"
}
expect_both 'runuser -u nested 120 deep is refused' 2 --command "$(rdt_rep 'runuser -u bob -- ' 120)rm -rf /"
expect_both 'runuser -u nested 900 deep is refused' 2 --command "$(rdt_rep 'runuser -u bob -- ' 900)rm -rf /"
expect_both 'su -s /bin/su nested 300 deep is refused' 2 \
  --command "$(rdt_rep 'su root -s /bin/su -- ' 300)root -s /bin/rm -- -rf /"
# rdt_timed <label> <want> <command>: one case, alone and dispatched, each under
# a `timeout 20` backstop. A slow path reads as rc 124 rather than as a pass,
# because a hook the harness cancels on its timeout is cancelled WITHOUT a block.
rdt_timed() {
  local label="$1" want="$2" payload via rc
  local -a argv
  payload="$(command_json "$3")"
  assert_eq "$label (payload verbatim)" "$3" "$(jq -r .tool_input.command <<<"$payload")"
  for via in direct dispatched; do
    if [[ "$via" == direct ]]; then
      argv=(bash "$HOOK")
    else
      argv=(bash "$GUARD_DISPATCH" "$HOOK")
    fi
    rc=0
    timeout 20 "${argv[@]}" <<<"$payload" >/dev/null 2>&1 || rc=$?
    assert_exit "$label ($via)" "$want" "$rc"
  done
}
rdt_timed 'flock/eval nested 700 deep is refused inside the timeout' 2 "$(rdt_rep 'flock --wa 1 f eval ' 700)rm -rf /"
# runuser with both -u and a non-shell -s is judged two ways at every level, so
# the readings double per level below the depth cap. Every judged segment is
# counted, and past the budget the guard refuses inside the timeout.
rdt_timed 'runuser -u -s env nested 20 deep is refused' 2 "$(rdt_rep 'runuser -u x -s env -- ' 20)rm -rf ./x"
rdt_timed 'runuser -u -s env nested 25 deep is refused' 2 "$(rdt_rep 'runuser -u x -s env -- ' 25)rm -rf ./x"
rdt_timed 'runuser -u -s env nested 25 deep with a root delete blocks' 2 \
  "$(rdt_rep 'runuser -u x -s env -- ' 25)rm -rf /"
rdt_timed 'six-level mixed nesting with an ordinary delete allowed' 0 \
  "sudo -u bob bash -c \"runuser -u x -- sh -c 'su root -c \\\"eval nice timeout 5 rm -rf ./build\\\"'\""
expect_both 'moderate launcher nesting with an ordinary delete allowed' 0 \
  --command "sudo nice timeout 5 runuser -u bob -- bash -c 'rm -rf ./build'"
expect_both 'moderate launcher nesting with a root delete blocks' 2 \
  --command "sudo nice timeout 5 runuser -u bob -- bash -c 'rm -rf /'"

expect_both 'substitution nested 3 deep is still parsed' 2 \
  --command 'echo "$(echo "$(echo "$(rm -rf /)")")"'

# `eval` runs its arguments in THIS shell, so the child-shell unwrap never
# applies to it: there is no -c and no new process.
expect_both 'eval "rm -rf /" blocks' 2 --command 'eval "rm -rf /"'
expect_both 'eval rm -rf / blocks (unquoted)' 2 --command 'eval rm -rf /'
expect_both 'nested eval blocks' 2 --command 'eval "eval \"rm -rf /\""'
expect_both 'eval with an ordinary delete allowed' 0 --command 'eval "rm -rf ./build"'
# eval's arguments are joined by TEXT, and an operand a trailing backslash
# produced arrives EMPTY, so the join must restore the literal `\` from that
# word's quoting provenance or the operand vanishes on the way into the
# re-parse and `eval rm -rf \` passes.
expect_both 'eval rm -rf \ blocks (dangling backslash through eval)' 2 --command 'eval rm -rf \'
expect_both 'eval "rm -rf" \ blocks' 2 --command 'eval "rm -rf" \'
expect_both 'eval rm -rf "\\" blocks' 2 --command 'eval rm -rf "\\"'
expect_both "eval 'rm -rf \\' blocks" 2 --command "eval 'rm -rf \\'"

# A child shell runs its operand as a full command, so the operand is re-parsed
# with the same tokenizer, exactly as block-no-verify does for `git`.
expect_both 'bash -c rm -rf / blocks' 2 --command 'bash -c "rm -rf /"'
expect_both 'sh -c rm -rf / blocks' 2 --command "sh -c 'rm -rf /'"
expect_both 'bash -lc rm -rf / blocks' 2 --command 'bash -lc "rm -rf /"'
expect_both 'sudo bash -c rm -rf / blocks' 2 --command 'sudo bash -c "rm -rf /"'
expect_both 'wsl rm -rf / blocks' 2 --command 'wsl rm -rf /'
expect_both 'wsl.exe -e rm -rf / blocks' 2 --command 'wsl.exe -e rm -rf /'
expect_both 'wsl -d Ubuntu -- sudo rm -rf / blocks' 2 --command 'wsl -d Ubuntu -- sudo rm -rf /'
expect_both 'wsl ls / allowed' 0 --command 'wsl ls /'

# `su` runs its operand through the target user's shell, so one process is every
# command inside it too. Its grammar is not a shell's: the operand follows the
# FLAG, and a user name may sit ahead of it.
expect_both 'su -c rm -rf / blocks' 2 --command "su -c 'rm -rf /'"
expect_both 'su bob -c rm -rf / blocks' 2 --command "su bob -c 'rm -rf /'"
expect_both 'su - bob -c rm -rf / blocks' 2 --command "su - bob -c 'rm -rf /'"
expect_both 'su -lc rm -rf / blocks (short cluster)' 2 --command "su -lc 'rm -rf /'"
expect_both 'su --command= rm -rf / blocks' 2 --command "su --command='rm -rf /'"
expect_both 'su --session-command rm -rf / blocks' 2 --command "su --session-command 'rm -rf /'"
# getopt_long takes any unambiguous prefix of a long option, so an abbreviated
# `--command` or `--session-command` carries the operand exactly as the full
# name does.
expect_both 'su --comm rm -rf / blocks (abbreviated --command)' 2 --command "su --comm 'rm -rf /'"
expect_both 'su --c= rm -rf / blocks' 2 --command "su --c='rm -rf /'"
# EVERY word after a -c-like word is parsed, not only the first: su runs the
# last -c, and a -c-looking word may be another option's operand.
expect_both 'su with two -c, the second a delete, blocks' 2 --command "su bob -c true -c 'rm -rf /*'"
expect_both 'su -w -c -c blocks' 2 --command "su -w -c -c 'rm -rf /*'"
# An operand attached to -c arrives inside the same word.
expect_both "su -c'rm -rf /' blocks (attached operand)" 2 --command "su -c'rm -rf /'"
expect_both "runuser -lc'rm -rf /' blocks (attached operand)" 2 --command "runuser -lc'rm -rf /'"
expect_both "su -c'ls /' allowed (attached benign operand)" 0 --command "su -c'ls /'"
# A shell reads `-c -- '…'` as `-c '…'`.
expect_both 'su -c -- blocks' 2 --command "su bob -- -c -- 'rm -rf /*'"
expect_both 'runuser -c -- blocks' 2 --command "runuser bob -- -c -- 'rm -rf /*'"
# A -c operand of exactly `--` makes su build `sh -c -- CMD`, so CMD is the
# word after it, in every spelling of the option.
expect_both 'su --com=-- blocks' 2 --command "su root --com=-- 'rm -rf /*'"
expect_both 'su -c-- blocks' 2 --command "su root -c-- 'rm -rf /*'"
expect_both 'su --session-command=-- blocks' 2 --command "su root --session-command=-- 'rm -rf /*'"
expect_both 'runuser --command=-- blocks' 2 --command "runuser root --command=-- 'rm -rf /*'"
expect_both 'runuser -c -- operand blocks' 2 --command "runuser root -c -- 'rm -rf /*'"
expect_both 'su --com=-- ls allowed' 0 --command "su root --com=-- 'ls /'"
# -s / --shell naming a program that is not a shell runs that program with the
# words after the user, so the program is the command.
expect_both 'su -s /bin/rm blocks' 2 --command 'su root -s /bin/rm -- -rf /*'
expect_both 'runuser -s /bin/rm blocks' 2 --command 'runuser bob -s /bin/rm -- -rf /*'
expect_both 'runuser --shell=/bin/rm blocks' 2 --command 'runuser --shell=/bin/rm bob -- -rf /*'
expect_both 'runuser -s/bin/rm blocks (attached)' 2 --command 'runuser -s/bin/rm root -- -rf /*'
expect_both 'su -s /bin/bash -c ls allowed' 0 --command "su root -s /bin/bash -c 'ls /'"

# The launcher family. Each of these moves the command word exactly as `sudo`
# and `nice` do, so the real command is found behind its options and its own
# positional argument.
expect_both "runuser -c rm -rf / blocks" 2 --command "runuser -c 'rm -rf /'"
expect_both 'taskset 1 rm -rf / blocks' 2 --command 'taskset 1 rm -rf /'
# runuser WITHOUT -u is su's grammar: the operand follows -c, a user may sit
# ahead of it, and short clusters and abbreviated long names carry it too.
expect_both 'runuser bob -c rm -rf / blocks' 2 --command "runuser bob -c 'rm -rf /'"
expect_both 'runuser - bob -c rm -rf / blocks' 2 --command "runuser - bob -c 'rm -rf /'"
expect_both 'runuser -lc rm -rf / blocks' 2 --command "runuser -lc 'rm -rf /'"
expect_both 'runuser --command= rm -rf / blocks' 2 --command "runuser --command='rm -rf /'"
expect_both 'runuser --session-c rm -rf / blocks' 2 --command "runuser --session-c 'rm -rf /'"
expect_both '/usr/sbin/runuser -c rm -rf / blocks' 2 --command "/usr/sbin/runuser -c 'rm -rf /'"
expect_both 'RUNUSER.exe -c rm -rf / blocks' 2 --command "RUNUSER.exe -c 'rm -rf /'"
expect_both 'sudo runuser -c rm -rf / blocks' 2 --command "sudo runuser -c 'rm -rf /'"
expect_both 'nice -n 5 runuser -c rm -rf / blocks' 2 --command "nice -n 5 runuser -c 'rm -rf /'"
# A -u hidden inside another option's operand is not -u, so these stay su form.
expect_both 'runuser -lc with a -u inside the operand blocks' 2 --command "runuser -lc '-u x; rm -rf /'"
expect_both 'runuser --whitelist-environment -u,PATH -c blocks' 2 \
  --command "runuser --whitelist-environment -u,PATH bob -c 'rm -rf /'"
expect_both 'runuser -w -u,PATH -c blocks' 2 --command "runuser -w -u,PATH bob -c 'rm -rf /'"
expect_both 'runuser --white -u,PATH -c blocks' 2 --command "runuser --white -u,PATH bob -c 'rm -rf /'"
# runuser's getopt PERMUTES and takes the LAST of a repeated option, so every
# -c operand is judged, and an option operand is never mistaken for an option.
expect_both 'runuser two -c, the second a delete, blocks' 2 --command "runuser bob -c true -c 'rm -rf /*'"
expect_both 'runuser --command then --session-command blocks' 2 \
  --command "runuser bob --command=true --session-command 'rm -rf /*'"
expect_both 'runuser -wc then -c blocks' 2 --command "runuser bob -wc -c 'rm -rf /*'"
expect_both 'runuser --whitelist-environment -c then -c blocks' 2 \
  --command "runuser bob --whitelist-environment -c -c 'rm -rf /*'"
expect_both 'runuser --white -u then -c blocks' 2 --command "runuser bob --white -u -c 'rm -rf /*'"
expect_both 'runuser --sess -u then -c blocks' 2 --command "runuser bob --sess -u -c 'rm -rf /*'"
expect_both 'runuser --comm with a -u inside the operand blocks' 2 --command "runuser bob --comm '-u; rm -rf /'"
expect_both 'runuser --sess with a -u inside the operand blocks' 2 --command "runuser --sess '-u x; rm -rf /'"
# runuser WITH -u is a launcher: its non-option words are the command, wherever
# the options sit among them, and the first -- ends the options.
expect_both 'runuser -u bob rm -- -rf /* blocks (permuted)' 2 --command 'runuser -u bob rm -- -rf /*'
expect_both 'runuser rm -u bob -- -rf /* blocks (permuted)' 2 --command 'runuser rm -u bob -- -rf /*'
expect_both 'runuser -mu cluster blocks' 2 --command 'runuser -mu bob -- rm -rf /'
expect_both 'runuser --u bob blocks (abbreviated --user)' 2 --command 'runuser --u bob -- rm -rf /'
expect_both 'runuser --us=bob blocks' 2 --command 'runuser --us=bob -- rm -rf /'
# An unknown long option is kept as a non-option, which also reads the words
# right when POSIXLY_CORRECT stops getopt at the first non-option.
expect_both 'POSIXLY_CORRECT runuser rm --recursive blocks' 2 \
  --command 'POSIXLY_CORRECT=1 runuser -u bob rm --recursive --force /*'
# A word runuser rejects is never the command word.
expect_both 'runuser -u root --foo rm blocks' 2 --command 'runuser -u root --foo rm -rf /*'
expect_both 'runuser -u root -x rm blocks' 2 --command 'runuser -u root -x rm -rf /*'
expect_both 'runuser -u bob -- flock -- /tmp/l -c blocks' 2 --command "runuser -u bob -- flock -- /tmp/l -c 'rm -rf /*'"
expect_both 'runuser -u bob -- rm -rf / blocks' 2 --command 'runuser -u bob -- rm -rf /'
expect_both 'runuser -u bob rm -rf / blocks' 2 --command 'runuser -u bob rm -rf /'
expect_both 'runuser --user bob -- rm -rf / blocks' 2 --command 'runuser --user bob -- rm -rf /'
expect_both 'runuser --user=bob -- rm -rf / blocks' 2 --command 'runuser --user=bob -- rm -rf /'
expect_both 'runuser -ubob -- rm -rf / blocks' 2 --command 'runuser -ubob -- rm -rf /'
expect_both 'runuser -u bob -G wheel -w PATH -- rm -rf / blocks' 2 \
  --command 'runuser -u bob -G wheel -w PATH -- rm -rf /'
expect_both 'runuser -u bob -- bash -c rm -rf / blocks' 2 --command "runuser -u bob -- bash -c 'rm -rf /'"
expect_both 'sudo runuser -u bob -- rm -rf / blocks' 2 --command 'sudo runuser -u bob -- rm -rf /'
# taskset takes a mask (or a cpu list under -c) ahead of the command.
expect_both 'taskset 0x3 rm -rf / blocks' 2 --command 'taskset 0x3 rm -rf /'
expect_both 'taskset -c 0 rm -rf / blocks' 2 --command 'taskset -c 0 rm -rf /'
expect_both 'taskset --cpu-list 0-3 rm -rf / blocks' 2 --command 'taskset --cpu-list 0-3 rm -rf /'
expect_both 'taskset -ac 0 rm -rf / blocks' 2 --command 'taskset -ac 0 rm -rf /'
expect_both 'taskset -- 1 rm -rf / blocks' 2 --command 'taskset -- 1 rm -rf /'
expect_both "'taskset' 1 rm -rf / blocks" 2 --command "'taskset' 1 rm -rf /"
expect_both 'TASKSET.EXE 1 rm -rf / blocks' 2 --command 'TASKSET.EXE 1 rm -rf /'
expect_both 'taskset 1 rm -rf C:\ blocks' 2 --command 'taskset 1 rm -rf C:\'
expect_both 'taskset 1 rm -rf \ blocks (dangling backslash)' 2 --command 'taskset 1 rm -rf \'
expect_both 'env -u X taskset -c 0 rm -rf / blocks' 2 --command 'env -u X taskset -c 0 rm -rf /'
expect_both 'timeout 5 taskset 1 rm -rf / blocks' 2 --command 'timeout 5 taskset 1 rm -rf /'
expect_both 'taskset 1 bash -c rm -rf / blocks' 2 --command "taskset 1 bash -c 'rm -rf /'"
expect_both 'substitution through taskset blocks' 2 --command 'echo "$(taskset 1 rm -rf /)"'
expect_both 'env -S through taskset blocks' 2 --command "env -S 'taskset 1 rm -rf /'"
# chrt takes a priority only when the word is all digits; otherwise the word
# is the command. `chrt -r rm` is an invocation chrt itself rejects (rr needs a
# priority), refused by decision (#4681, section 4c).
expect_both 'chrt 10 rm -rf / blocks' 2 --command 'chrt 10 rm -rf /'
expect_both 'chrt --fifo 10 rm -rf / blocks' 2 --command 'chrt --fifo 10 rm -rf /'
expect_both 'chrt -o rm -rf / blocks (no priority)' 2 --command 'chrt -o rm -rf /'
expect_both 'chrt -r rm -rf / blocks' 2 --command 'chrt -r rm -rf /'
expect_both 'chrt -d -T 1000 -P 2000 -D 2000 0 rm -rf / blocks' 2 --command 'chrt -d -T 1000 -P 2000 -D 2000 0 rm -rf /'
expect_both 'chrt -- 5 rm -rf / blocks' 2 --command 'chrt -- 5 rm -rf /'
# flock takes a lock file, and runs -c / --command through a shell.
expect_both 'flock /tmp/l rm -rf / blocks' 2 --command 'flock /tmp/l rm -rf /'
expect_both 'flock -w 5 /tmp/l rm -rf / blocks' 2 --command 'flock -w 5 /tmp/l rm -rf /'
expect_both 'flock -x /tmp/l -c rm -rf / blocks' 2 --command "flock -x /tmp/l -c 'rm -rf /'"
expect_both 'flock /tmp/l --command rm -rf / blocks' 2 --command "flock /tmp/l --command 'rm -rf /'"
expect_both 'flock -c rm -rf / blocks (no file)' 2 --command "flock -c 'rm -rf /'"
expect_both 'flock -- /tmp/l rm -rf / blocks' 2 --command 'flock -- /tmp/l rm -rf /'
# With --fd there is no lock file, so the first positional is the command.
expect_both 'flock --fd 9 rm -rf / blocks' 2 --command 'flock --fd 9 rm -rf /'
expect_both 'flock --fd=9 rm -rf / blocks' 2 --command 'flock --fd=9 rm -rf /'
# -c / --command right after the lock file counts after `--` too.
expect_both 'flock -- /tmp/l -c blocks' 2 --command "flock -- /tmp/l -c 'rm -rf /*'"
expect_both 'flock -n -- /tmp/l --command blocks' 2 --command "flock -n -- /tmp/l --command 'rm -rf /*'"
expect_both 'flock -- /tmp/l -c ls allowed' 0 --command "flock -- /tmp/l -c 'ls /'"
# An abbreviated long option takes its operand as the full name does.
expect_both 'flock --wa 5 blocks' 2 --command 'flock --wa 5 /tmp/l rm -rf /*'
expect_both 'flock --tim 5 blocks' 2 --command 'flock --tim 5 /tmp/l rm -rf /*'
expect_both 'nsenter --ta 1 blocks' 2 --command 'nsenter --ta 1 rm -rf /*'
expect_both 'unshare --roo /mnt blocks' 2 --command 'unshare --roo /mnt rm -rf /*'
expect_both 'numactl --memb 0 blocks' 2 --command 'numactl --memb 0 rm -rf /*'
expect_both 'chroot --user a:b / blocks' 2 --command 'chroot --user a:b / rm -rf /*'
expect_both 'chrt --sched-r 5 -d 0 blocks' 2 --command 'chrt --sched-r 5 -d 0 rm -rf /*'
expect_both 'nsenter --ta 1 ls / allowed' 0 --command 'nsenter --ta 1 ls /'
expect_both 'nsenter --ta rm -rf / blocks (plain reading)' 2 --command 'nsenter --ta rm -rf /'
# A short cluster ending in an operand-taking letter takes the next word, as
# getopt reads it, in the resolved reading.
expect_both 'flock -nw 1 blocks' 2 --command 'flock -nw 1 /tmp/l rm -rf /'
expect_both 'chrt -dT 1000 0 blocks' 2 --command 'chrt -dT 1000 0 rm -rf /'
expect_both 'unshare -fR /mnt blocks' 2 --command 'unshare -fR /mnt rm -rf /'
expect_both 'flock -xw 5 blocks' 2 --command 'flock -xw 5 /tmp/l rm -rf /*'
expect_both 'nsenter -at 1 blocks' 2 --command 'nsenter -at 1 rm -rf /*'
expect_both 'numactl -lN 0 blocks' 2 --command 'numactl -lN 0 rm -rf /*'
expect_both 'flock -nw 1 ls allowed' 0 --command 'flock -nw 1 /tmp/l ls /'
# unshare, nsenter and numactl take no positional; only their operand-taking
# options consume a word.
expect_both 'unshare rm -rf / blocks' 2 --command 'unshare rm -rf /'
expect_both 'unshare --mount --pid --fork rm -rf / blocks' 2 --command 'unshare --mount --pid --fork rm -rf /'
expect_both 'unshare -S 0 -G 0 rm -rf / blocks' 2 --command 'unshare -S 0 -G 0 rm -rf /'
expect_both 'unshare -R /mnt rm -rf / blocks' 2 --command 'unshare -R /mnt rm -rf /'
expect_both 'nsenter -t 1 -m rm -rf / blocks' 2 --command 'nsenter -t 1 -m rm -rf /'
expect_both 'nsenter --target 1 --mount rm -rf / blocks' 2 --command 'nsenter --target 1 --mount rm -rf /'
expect_both 'nsenter -t1 -m rm -rf / blocks' 2 --command 'nsenter -t1 -m rm -rf /'
expect_both 'numactl -i all rm -rf / blocks' 2 --command 'numactl -i all rm -rf /'
expect_both 'numactl --interleave=all rm -rf / blocks' 2 --command 'numactl --interleave=all rm -rf /'
expect_both 'numactl --cpunodebind 0 rm -rf / blocks' 2 --command 'numactl --cpunodebind 0 rm -rf /'
# chroot takes NEWROOT. `chroot /mnt rm -rf /` deletes /mnt on the host (and
# anything bind-mounted in it) rather than the host root, and is refused by
# decision (#4681, section 4c).
expect_both 'chroot / rm -rf / blocks' 2 --command 'chroot / rm -rf /'
expect_both 'chroot /mnt rm -rf / blocks (known overblock)' 2 --command 'chroot /mnt rm -rf /'
expect_both 'chroot --userspec bob:bob /mnt rm -rf / blocks' 2 --command 'chroot --userspec bob:bob /mnt rm -rf /'
expect_both 'chroot -- / rm -rf / blocks' 2 --command 'chroot -- / rm -rf /'
# Launchers stack.
expect_both 'the whole launcher family stacked blocks' 2 \
  --command 'flock /tmp/l chrt 5 unshare nsenter -t 1 chroot / numactl -l taskset 1 runuser -u bob -- rm -rf /'

# The command word is compared case-insensitively, so the substring prefilter
# in front of the parse must be too. On the Windows host this guard was written
# for, the filesystem and PATH lookup are case-insensitive and `RM` runs rm.
expect_both 'RM -rf / blocks (upper case)' 2 --command 'RM -rf /'
expect_both 'Rm.exe -rf C:\ blocks (mixed case)' 2 --command 'Rm.exe -rf C:\'
expect_both 'busybox rm -rf / blocks' 2 --command 'busybox rm -rf /'
# The `.exe` suffix is spelled in any case on that filesystem too, so the strip
# runs AFTER the fold. Stripping first left `rm.EXE` reading as `rm.exe`.
expect_both 'rm.EXE -rf / blocks' 2 --command 'rm.EXE -rf /'
expect_both 'RM.exe -rf / blocks' 2 --command 'RM.exe -rf /'
expect_both '/bin/RM.EXE -rf / blocks' 2 --command '/bin/RM.EXE -rf /'

# A DANGLING trailing backslash is the incident string minus its quotes. Bash
# passes a literal `\` when one ends the input, and MSYS resolves it to the
# current drive root. The tokenizer has no character left to emit, so the
# operand arrives empty and only its quoting provenance separates it from
# `rm -rf ""`.
expect_both 'rm -rf \ blocks (dangling backslash)' 2 --command 'rm -rf \'
expect_both 'rm -rf $(quoted backslash) blocks' 2 --command "rm -rf '\\'"

# coreutils accepts any unambiguous long-option prefix.
expect_both 'rm --r -f / blocks (abbreviated --recursive)' 2 --command 'rm --r -f /'
expect_both 'rm --rec -f / blocks' 2 --command 'rm --rec -f /'
expect_both 'rm -rf --no-p ./x blocks (abbreviated --no-preserve-root)' 2 --command 'rm -rf --no-p ./x'

# A UNC share root is the same class of loss as a drive root.
expect_both 'rm -rf //server/share blocks' 2 --command 'rm -rf //server/share'
# Single-quoted, because an UNQUOTED backslash-backslash-server form is not a
# UNC path to bash at all: the escapes collapse it to `\servershare`, and that
# is what rm would receive. The quoted spelling is the one that reaches the
# share, and both verdicts are pinned so the difference stays deliberate.
# portability-ok: a literal backslash pair inside a UNC path, not a grep -E escape
expect_both 'quoted UNC share root blocks' 2 --command "rm -rf '\\\\server\\share'"
# portability-ok: a literal backslash pair inside a UNC path, not a grep -E escape
expect_both 'unquoted UNC-looking path allowed (its escapes collapse)' 0 --command 'rm -rf \\server\share'

# --- 2. MUST NOT FIRE --------------------------------------------------------
# Quoted prose keeps `rm` INSIDE one word, so the command word is `git` or
# `echo` and the guard never reaches its flag parse. That falls out of command
# word resolution rather than a special case for message text.
expect_both 'git commit -m "rm -rf /" allowed' 0 --command 'git commit -m "rm -rf /"'
expect_both 'echo "rm -rf /" allowed' 0 --command 'echo "rm -rf /"'
expect_both 'echo rm allowed' 0 --command 'echo rm'

# Ordinary recursive deletes under the working tree: the whole point of the
# narrow trigger is that these stay untouched.
expect_both 'rm -rf ./build dist allowed' 0 --command 'rm -rf ./build dist'
expect_both 'rm -rf build/ allowed' 0 --command 'rm -rf build/'
expect_both 'rm -rf /tmp/x allowed' 0 --command 'rm -rf /tmp/x'
expect_both 'rm -rf "$TMPDIR/x" allowed' 0 --command 'rm -rf "$TMPDIR/x"'
expect_both 'rm -rf ~/.cache/foo allowed' 0 --command 'rm -rf ~/.cache/foo'
expect_both 'rm -rf $HOME/x allowed' 0 --command 'rm -rf $HOME/x'
# The path segments here are deliberately generic: the repo's machine-specific
# paths gate reads a drive letter followed by a well-known machine root as a
# leaked local path, and the assertion is about depth, not about the name.
expect_both 'rm -rf C:/build/x allowed' 0 --command 'rm -rf C:/build/x'
expect_both 'rm -rf /c/build/x allowed' 0 --command 'rm -rf /c/build/x'

# No recursion flag: the fire conditions never open.
expect_both 'rm -f /file allowed' 0 --command 'rm -f /file'
expect_both 'rm / allowed (no recursion)' 0 --command 'rm /'

# A recursive delete with no operand at all has nothing to match. An EMPTY
# operand is refused; see section 2b.
expect_both 'rm -rf allowed (no operand)' 0 --command 'rm -rf'

# A trailing segment that carries a NAME stops the reduction, so these stay
# ordinary relative or nested deletes rather than roots.
expect_both 'rm -rf /tmp* allowed' 0 --command 'rm -rf /tmp*'
expect_both 'rm -rf ~/proj* allowed' 0 --command 'rm -rf ~/proj*'
expect_both 'rm -rf /c/dev/* allowed' 0 --command 'rm -rf /c/dev/*'
expect_both 'rm -rf /_ allowed (a directory named _)' 0 --command 'rm -rf /_'
expect_both 'rm -rf * allowed (cwd-relative, no payload cwd)' 0 --command 'rm -rf *'
# A glob glued to a NAME is an ordinary prefix match, not the root it sits in.
expect_both 'rm -rf /c* allowed' 0 --command 'rm -rf /c*'
expect_both 'rm -rf ~* allowed' 0 --command 'rm -rf ~*'
# A child shell whose operand is an ordinary delete stays allowed.
expect_both 'bash -c rm -rf ./build allowed' 0 --command 'bash -c "rm -rf ./build"'
# A launcher whose real command is not rm stays allowed.
expect_both 'sudo -u bob ls / allowed' 0 --command 'sudo -u bob ls /'
# A path UNDER a UNC share is not the share root.
expect_both 'rm -rf //server/share/dir allowed' 0 --command 'rm -rf //server/share/dir'
# An arithmetic expansion is not a command substitution and carries no command.
expect_both 'arithmetic expansion allowed' 0 --command 'echo "$((1 + 2))"'
expect_both 'arithmetic inside a substitution allowed' 0 --command 'echo "$(echo $((1 + 2)))"'
# A SINGLE-quoted span performs no expansion at all, and inside a double-quoted
# one a backslash escapes the `$` and the backtick, so none of these four is a
# substitution: the text is printed and nothing runs. Reading raw characters
# called all four a substitution and refused a command that deletes nothing.
expect_both "single-quoted substitution text allowed" 0 --command "echo '\$(rm -rf /)'"
expect_both 'escaped dollar-paren allowed' 0 --command 'echo "\$(rm -rf /)"'
expect_both "single-quoted backtick text allowed" 0 --command "echo '\`rm -rf /\`'"
expect_both 'escaped backtick allowed' 0 --command 'echo "\`rm -rf /\`"'
# A heredoc whose delimiter is quoted is inert text: bash expands nothing in its
# body, so a backticked delete quoted there as an example runs nothing (#6625).
expect_both "quoted heredoc body with backticked rm allowed" 0 --command $'cat <<\'EOF\'\nnote: `rm -rf /`\nEOF'
expect_both 'double-quoted heredoc delimiter allowed' 0 --command $'cat <<"EOF"\nnote: `rm -rf /`\nEOF'
expect_both 'backslashed heredoc delimiter allowed' 0 --command $'cat <<\\EOF\nnote: $(rm -rf /)\nEOF'
expect_both "tab-stripped quoted heredoc allowed" 0 --command $'cat <<-\'EOF\'\n\tnote: `rm -rf /`\n\tEOF'
expect_both "quoted heredoc fed to gh pr create allowed" 0 --command $'gh pr create --title "fix: x" --body-file - <<\'EOF\'\nRun `rm -rf /` never.\nEOF'
# A quoted body is still stdin: a shell reading it, a pipe into one, or a
# substitution whose output a shell runs executes the text, so a substitution
# in such a body still blocks.
expect_both "quoted heredoc fed to bash blocks" 2 --command $'bash <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc piped into sh blocks" 2 --command $'cat <<\'EOF\' | sh\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc run through bash -c blocks" 2 --command $'bash -c "$(cat <<\'EOF\'\necho `rm -rf /`\nEOF\n)"'
expect_both "quoted heredoc fed to git blocks" 2 --command $'git x <<\'EOF\'\necho `rm -rf /`\nEOF'
# The skip holds only for the whole command: a compound opened on an earlier
# line, a pipe after the body, a reader redefined earlier, a file tee wrote and
# then ran, or a delimiter word with quote-removal edge cases all still block.
expect_both "quoted heredoc inside a brace group piped into sh blocks" 2 --command $'{\ncat <<\'EOF\'\necho `rm -rf /`\nEOF\n} | sh'
expect_both "quoted heredoc inside a loop piped into bash blocks" 2 --command $'for i in 1; do\ncat <<\'EOF\'\necho `rm -rf /`\nEOF\ndone | bash'
expect_both "quoted heredoc fed to a redefined cat blocks" 2 --command $'cat() { sh; }\ncat <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc fed to a backslash-continued shell blocks" 2 --command $'sh -s \\\ncat <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc written by tee blocks" 2 --command $'tee /tmp/x.sh <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "escaped quote in a heredoc delimiter blocks" 2 --command $'cat <<"E\\"F"\nbody\nE"F\necho `rm -rf /`'
expect_both "ansi-c heredoc delimiter blocks" 2 --command $'cat <<$\'EOF\'\nbody\nEOF\necho `rm -rf /`'
expect_both "heredoc opener inside a comment blocks" 2 --command $'cat # <<\'EOF\'\necho "$(rm -rf /)"'
expect_both "trailing comment on a quoted heredoc opener allowed" 0 --command $'gh pr create --body-file - <<\'EOF\' # see $1\nRun `rm -rf /` never.\nEOF'
expect_both "quoted heredoc fed to gh issue comment allowed" 0 --command $'gh issue comment 1 --body-file - <<\'EOF\'\nRun `rm -rf /` never.\nEOF\n'
# `git commit -F -` and `git tag -F -` read the body as a message, and git
# ignores an alias that hides a built-in command, so their one-line form is data.
expect_both "quoted heredoc fed to git commit -F - allowed" 0 --command $'git commit -F - <<\'EOF\'\nfix: x\n\nRun `rm -rf /` never.\nEOF'
expect_both "quoted heredoc fed to git tag -F - allowed" 0 --command $'git tag -F - v1.0.0 <<\'EOF\'\nRun `rm -rf /` never.\nEOF'
# A global option ahead of the subcommand can define or reach an alias, another
# subcommand or an unknown alias can be `!sh`, and only `-F -` names stdin, so
# each of these is still scanned. So is the form whose opener sits on a later
# line, a pipe after the opener, and a `cat` redirected into a file.
expect_both "quoted heredoc fed to git -c commit -F - blocks" 2 --command $'git -c alias.x=y commit -F - <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc fed to git -C commit -F - blocks" 2 --command $'git -C /tmp commit -F - <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc fed to an unknown git alias with -F - blocks" 2 --command $'git ci -F - <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc fed to git notes add -F - blocks" 2 --command $'git notes add -F - <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc fed to git commit with -F - after -- blocks" 2 --command $'git commit -- -F - <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc fed to git commit with -F - inside quotes blocks" 2 --command $'git commit "a -F - b" <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc fed to git commit --file=- blocks" 2 --command $'git commit --file=- <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc opener on a later line of git commit -F - blocks" 2 --command $'git commit -F - --trailer "Refs: #1" \\\n<<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc fed to git commit -F - piped into sh blocks" 2 --command $'git commit -F - <<\'EOF\' | sh\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc written by a redirected cat blocks" 2 --command $'cat > /tmp/x.sh <<\'EOF\'\necho `rm -rf /`\nEOF'
# An unquoted delimiter's body IS expanded, so its substitutions still run.
expect_both 'unquoted heredoc body with backticked rm blocks' 2 --command $'cat <<EOF\nnote: `rm -rf /`\nEOF'
expect_both "unquoted heredoc ahead of a quoted one on the same line blocks" 2 --command $'cat <<A <<\'B\'\n`rm -rf /`\nA\ninert\nB'
expect_both "backticked rm after a quoted heredoc ends blocks" 2 --command $'cat <<\'EOF\'\nnote\nEOF\necho `rm -rf /`'
expect_both 'arithmetic shift is not a heredoc opener' 2 --command $'echo $((1<<2))\necho `rm -rf /`'
expect_both 'here-string is not a heredoc opener' 2 --command $'cat <<<x\necho `rm -rf /`'
# A live substitution nested three deep whose innermost command is harmless is
# parsed all the way down and still allowed, so the depth cap is not a blanket.
expect_both 'benign 3-deep substitution allowed' 0 --command 'echo "$(echo "$(echo rm)")"'
# `coproc NAME <simple command>` is not the NAME form at all: bash runs a
# command named `shredder` and hands it the rest, so this names no `rm`.
expect_both 'coproc NAME ahead of a simple command allowed' 0 --command 'coproc shredder rm -rf /'
expect_both 'coproc NAME with an ordinary delete allowed' 0 --command 'coproc shredder rm -rf ./build'
# GNU env's -S operand is a COMMAND, split and run, not an opaque argument.
expect_both 'env -S with an ordinary command allowed' 0 --command "env -S 'ls /'"
expect_both 'env -S with an ordinary delete allowed' 0 --command "env -S 'rm -rf ./build'"
expect_both 'sudo --user root ls / allowed' 0 --command 'sudo --user root ls /'
# A substitution whose inner delete is ordinary stays allowed.
expect_both 'substitution with an ordinary delete allowed' 0 --command 'echo "$(rm -rf ./build)"'
# A long option that is not a prefix of either recognized name.
expect_both 'rm --force / allowed (no recursion)' 0 --command 'rm --force /'
expect_both 'rm --dir / allowed (no recursion)' 0 --command 'rm --dir /'

# A command word that merely ENDS in rm, or takes rm as a subcommand, is not rm.
expect_both 'perm -rf / allowed' 0 --command 'perm -rf /'
expect_both 'rmdir / allowed' 0 --command 'rmdir /'
expect_both 'git rm -rf src allowed (command word is git)' 0 --command 'git rm -rf src'

# A recursive READ of the root is not a delete.
expect_both 'ls -R / allowed' 0 --command 'ls -R /'

# The command-word arms must not widen the guard. A reserved word ahead of an
# ORDINARY delete, a `su` whose operand is ordinary or absent, and a case-folded
# `rm.EXE` under the working tree all stay allowed.
expect_both 'brace group with an ordinary delete allowed' 0 --command '{ rm -rf ./build; }'
expect_both 'if/then with an ordinary delete allowed' 0 --command 'if true; then rm -rf ./build; fi'
expect_both 'su -c with an ordinary delete allowed' 0 --command "su -c 'rm -rf ./build'"
expect_both 'su with no -c allowed' 0 --command 'su bob ls /'
# `--s` is ambiguous (session-command, shell, supp-group), so su rejects it.
expect_both 'su --s ambiguous prefix allowed' 0 --command "su --s 'rm -rf /'"
expect_both 'rm.EXE under the tree allowed' 0 --command 'rm.EXE -rf ./build'
# An empty operand from a QUOTED span is not a dropped backslash, so the eval
# restore keys on provenance rather than emptiness. eval joins its words to
# `rm -rf ` with no operand at all, which deletes nothing.
expect_both 'eval rm -rf "" allowed' 0 --command 'eval rm -rf ""'

# The launcher family must not widen the guard either: a launcher whose real
# command is benign, or an ordinary delete, stays allowed, and so does a form
# that launches nothing at all.
expect_both 'taskset 1 rm -rf ./build allowed' 0 --command 'taskset 1 rm -rf ./build'
expect_both 'taskset -p 1234 allowed (launches nothing)' 0 --command 'taskset -p 1234'
expect_both 'taskset -cp 0 1234 allowed' 0 --command 'taskset -cp 0 1234'
expect_both 'runuser -u bob -- ls / allowed' 0 --command 'runuser -u bob -- ls /'
expect_both 'runuser -u bob -- rm -rf ./build allowed' 0 --command 'runuser -u bob -- rm -rf ./build'
expect_both 'runuser -c with an ordinary delete allowed' 0 --command "runuser -c 'rm -rf ./build'"
expect_both 'runuser -l bob allowed' 0 --command 'runuser -l bob'
expect_both 'chrt 5 ls / allowed' 0 --command 'chrt 5 ls /'
expect_both 'chrt -p 5 1234 allowed' 0 --command 'chrt -p 5 1234'
expect_both 'flock /tmp/l rm -rf ./build allowed' 0 --command 'flock /tmp/l rm -rf ./build'
expect_both 'flock -x 9 allowed' 0 --command 'flock -x 9'
expect_both 'flock --fd 9 ls / allowed' 0 --command 'flock --fd 9 ls /'
expect_both 'unshare ls / allowed' 0 --command 'unshare ls /'
expect_both 'nsenter -t 1 -m ls / allowed' 0 --command 'nsenter -t 1 -m ls /'
expect_both 'chroot /mnt ls / allowed' 0 --command 'chroot /mnt ls /'
expect_both 'numactl -i all ls / allowed' 0 --command 'numactl -i all ls /'
expect_both 'echo of the launcher names allowed' 0 --command 'echo runuser taskset chrt flock unshare nsenter chroot numactl'
expect_both 'git commit -m quoting runuser allowed' 0 --command "git commit -m \"runuser -c 'rm -rf /'\""

# --- 2b. Empty operands, bare variables, and targets outside the tree ---------
# The empty-operand and bare-variable arms need no payload cwd. The outside-tree
# arm does: every case above carries none, which is what keeps each of them at
# its verdict, and section 2c re-runs a subset of them WITH one.
rdt_skips=0
rdt_skip() {
  echo "skip: $*"
  rdt_skips=$((rdt_skips + 1))
}

expect_both 'rm -rf "" blocks (empty operand)' 2 --command 'rm -rf ""'
expect_both "rm -rf '' blocks (empty operand)" 2 --command "rm -rf ''"
expect_both 'rm -rf "" build blocks' 2 --command 'rm -rf "" build'
expect_both 'an empty operand inside a substitution blocks' 2 --command 'echo "$(rm -rf "")"'

expect_both 'rm -rf $X blocks (bare variable)' 2 --command 'rm -rf $X'
expect_both 'rm -rf ${X} blocks' 2 --command 'rm -rf ${X}'
expect_both 'rm -rf "$X" blocks' 2 --command 'rm -rf "$X"'
expect_both 'rm -rf "$X/" blocks' 2 --command 'rm -rf "$X/"'
expect_both 'rm -rf "$X/*" blocks' 2 --command 'rm -rf "$X/*"'
expect_both 'rm -rf "$X"/* blocks' 2 --command 'rm -rf "$X"/*'
expect_both 'rm -rf "$1" blocks (positional parameter)' 2 --command 'rm -rf "$1"'
expect_both 'rm -rf "$@" blocks (special parameter)' 2 --command 'rm -rf "$@"'
expect_both 'rm -rf "${1}" blocks' 2 --command 'rm -rf "${1}"'
expect_both 'rm -rf "${X:-}" blocks (default operator)' 2 --command 'rm -rf "${X:-}"'
expect_both 'rm -rf "${X-/tmp/y}" blocks' 2 --command 'rm -rf "${X-/tmp/y}"'
expect_both 'rm -rf "${X:+y}" blocks (alternative operator)' 2 --command 'rm -rf "${X:+y}"'
expect_both 'rm -rf "${X:=y}" blocks (assign operator)' 2 --command 'rm -rf "${X:=y}"'
expect_both 'sudo rm -rf $X blocks' 2 --command 'sudo rm -rf $X'
# Declared overblock: the tokenizer's provenance cannot tell a single-quoted
# `$X` (a literal name) from a double-quoted one.
expect_both "rm -rf '\$X' blocks (declared overblock)" 2 --command "rm -rf '\$X'"
expect_both 'rm -rf "$X/build" allowed' 0 --command 'rm -rf "$X/build"'
expect_both 'rm -rf "${X:?}/" allowed (SC2115 idiom)' 0 --command 'rm -rf "${X:?}/"'
# Only `${NAME:?...}` aborts on an empty value as well as an unset one, so it
# is the one whole-operand `${...}` form that passes. Every other form, and an
# operand built from expansions alone, is refused.
expect_both 'rm -rf "${X:?unset}/" allowed' 0 --command 'rm -rf "${X:?unset}/"'
expect_both 'rm -rf "${X?}" blocks (empty passes ?)' 2 --command 'rm -rf "${X?}"'
expect_both 'rm -rf "${X?}/"* blocks' 2 --command 'rm -rf "${X?}/"*'
expect_both 'rm -rf "${X%/}" blocks' 2 --command 'rm -rf "${X%/}"'
expect_both 'rm -rf "${!X}" blocks' 2 --command 'rm -rf "${!X}"'
expect_both 'rm -rf "${X:1}" blocks' 2 --command 'rm -rf "${X:1}"'
expect_both 'rm -rf "$X$Y" blocks (expansions only)' 2 --command 'rm -rf "$X$Y"'
expect_both 'rm -rf "${X:?}${Y}" blocks' 2 --command 'rm -rf "${X:?}${Y}"'

# The tree cases pass the checkout's own toplevel as the payload cwd and use
# relative operands, so an allow is proof of the TREE arm only if the checkout
# is not itself under a temp root. That premise is asserted, not assumed.
RDT_TOP=$(git -C "$HOOK_DIR" rev-parse --show-toplevel 2>/dev/null)
RDT_TOP="${RDT_TOP//$'\r'/}"
assert_contains "the suite runs from a git checkout (toplevel found)" "$RDT_TOP" "/"
rdt_phys() { # fixture check only: a physical, long-name, lower-case spelling
  local p="${1//\\//}" q
  q=$(realpath -m -- "$p" 2>/dev/null) && p="$q"
  if command -v cygpath >/dev/null 2>&1; then
    q=$(cygpath -l -m -- "$p" 2>/dev/null) && p="$q"
  fi
  printf '%s' "${p,,}"
}
rdt_top_in_temp=no
rdt_top_p=$(rdt_phys "$RDT_TOP")
for rdt_t in "${TMPDIR:-}" "${TMP:-}" "${TEMP:-}" /tmp /var/tmp; do
  [[ -n "$rdt_t" && -d "$rdt_t" ]] || continue
  rdt_tp=$(rdt_phys "$rdt_t")
  [[ "$rdt_top_p" == "$rdt_tp" || "$rdt_top_p" == "$rdt_tp"/* ]] && rdt_top_in_temp=yes
done
assert_eq "the checkout toplevel is outside every temp root" no "$rdt_top_in_temp"
RDT_CWD=(--cwd "$RDT_TOP")

# rdt_pl <command> <cwd> [scratchpad_dir]: a payload with the harness's
# optional fields. MSYS_NO_PATHCONV keeps Git Bash from rewriting an argument
# shaped like a POSIX path (`/x`, `NAME=/x`) for a native jq.
rdt_pl() {
  if (($# > 2)); then
    MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$2" --arg s "$3" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,scratchpad_dir:$s}'
  else
    MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}'
  fi
}

# A `${...}` whose operator holds a slash, followed by nameless segments
# (`/`, `/*`, `/.`), is still a bare variable: with X unset each of these
# reaches `/`. The trailing segments are stripped outside the braces only.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "bare variable: $rdt_cmd blocks" 2 --command "$rdt_cmd"
  expect_both "bare variable: $rdt_cmd blocks with a cwd" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
rm -rf "${X:-/}"/*
rm -rf "${X:-/}/*"
rm -rf "${X%/}"/*
rm -rf "${X%/}/*"
rm -rf "${X:-/}/"
rm -rf "${X%/}/"
rm -rf "${X:-/}/."
rm -rf "${X//a/b}"/*
rm -rf "${X:-${Y:-/}}"/*
rm -rf "${X:-${Y:-/}}/*"
rm -rf "${X:-${Y}}"/*
rm -rf "${X:-/}"*
rm -rf ${X:-/}*
rm -rf "${X:-/}"?*
rm -rf "${X:-/}"[a-z]*
rm -rf "${X:-/}"*/
rm -rf "${X:-/}".*
rm -rf "${A:-${B:-${C:-/}}}"*
rm -rf "${X:-$HOME}"*
rm -rf "$X"*
rm -rf ${X}*
EOF
# `:?` aborts on an unset or empty X whatever its message word holds.
expect_both 'bare variable: "${X:?${Y}}"/* allowed' 0 --command 'rm -rf "${X:?${Y}}"/*'
expect_both 'bare variable: "${X:?${Y}}"/* allowed with a cwd' 0 "${RDT_CWD[@]}" --command 'rm -rf "${X:?${Y}}"/*'
expect_both 'bare variable: "${X:?/}"/* allowed' 0 --command 'rm -rf "${X:?/}"/*'
expect_both 'bare variable: "${X:?/}"/* allowed with a cwd' 0 "${RDT_CWD[@]}" --command 'rm -rf "${X:?/}"/*'
# A `${` that never closes is refused; bash rejects it.
expect_both "bare variable: an unclosed \${ blocks" 2 --command "rm -rf '\${X:-/'/*"
# Bash passes `${...}` through brace expansion whole, and its first `}` ends
# it, so `${X:-{a,b}}` leaves a literal `}` behind. A segment holding no
# letter, digit or underscore names nothing to this guard (`rm -rf /}` is a
# root), so the operand reads as bare and is refused, the conservative side.
expect_both 'bare variable: ${X:-{a,b}}/* blocks' 2 --command 'rm -rf ${X:-{a,b}}/*'
# A glob or dots after the expansion name nothing, so `"${X:-/}"*` with X unset
# is `/*`. A remainder that names something goes on past the expansion.
expect_both 'bare variable: "${X:?}"* allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf "${X:?}"*'
expect_both 'bare variable: "$X"-build allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf "$X"-build'
expect_both 'bare variable: "${X}"_old* allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf "${X}"_old*'
expect_both 'bare variable: "${X:?}/*" allowed' 0 --command 'rm -rf "${X:?}/*"'
expect_both 'bare variable: "${X:?}/*" allowed with a cwd' 0 "${RDT_CWD[@]}" --command 'rm -rf "${X:?}/*"'
expect_both 'bare variable: "$X/build" allowed with a cwd' 0 "${RDT_CWD[@]}" --command 'rm -rf "$X/build"'

# A NUL byte in `cwd` or `scratchpad_dir` refuses only a recursive delete this
# arm must judge; any other command is not affected. A NUL in the command itself
# still refuses every call (section 5).
rdt_nul_pl() { # <command> <field>: a payload whose <field> holds a NUL byte
  MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$RDT_TOP" --arg f "$2" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d} + {($f): ($d + "\u0000x")}'
}
expect_both 'nul cwd: ls allowed' 0 --payload "$(rdt_nul_pl 'ls -la' cwd)"
expect_both 'nul cwd: a command with rm in its text but no delete allowed' 0 --payload "$(rdt_nul_pl 'npm run format' cwd)"
expect_both 'nul cwd: rm -rf build refused' 2 --payload "$(rdt_nul_pl 'rm -rf build' cwd)"
expect_both 'nul scratchpad: ls allowed' 0 --payload "$(rdt_nul_pl 'ls -la' scratchpad_dir)"
expect_both 'nul scratchpad: rm -rf build refused' 2 --payload "$(rdt_nul_pl 'rm -rf build' scratchpad_dir)"
guard_invoke --payload "$(rdt_nul_pl 'rm -rf build' cwd)"
assert_contains "nul cwd: the refusal names the NUL field" "$GUARD_ERR" "NUL byte"

expect_both 'tree: rm -rf build allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf build'
expect_both 'tree: rm -rf ./a/b allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf ./a/b'
expect_both 'tree: rm -rf .work/some-slug/x allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf .work/some-slug/x'
expect_both 'tree: an absolute path inside the checkout allowed' 0 "${RDT_CWD[@]}" --command "rm -rf '$RDT_TOP/x'"
expect_both 'tree: rm -rf * allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf *'
expect_both 'tree: rm -rf ./* allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf ./*'
expect_both 'tree: a .. that stays inside allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf plugins/../build'
expect_both 'tree: a quoted ~ is a literal relative name, allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf "~/x"'
expect_both 'tree: a cwd in backslash form allowed' 0 --cwd "${RDT_TOP//\//\\}" --command 'rm -rf build'
expect_both 'tree: rm -rf ../../.. blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf ../../..'
expect_both 'tree: a sibling of the checkout blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf ../rdt-sibling'
expect_both 'tree: ../* blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf ../*'
expect_both 'tree: an absolute path outside tree and temp blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf /opt/nonexistent-rdt/x'
expect_both 'tree: ~/Documents/x blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf ~/Documents/x'
expect_both 'tree: $HOME/x blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf $HOME/x'
expect_both 'tree: "${HOME}/x" blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf "${HOME}/x"'
expect_both 'tree: a delete through a launcher blocks' 2 "${RDT_CWD[@]}" --command 'sudo -u bob rm -rf /opt/nonexistent-rdt/x'
expect_both 'tree: a delete in a child shell blocks' 2 "${RDT_CWD[@]}" --command "bash -c 'rm -rf ../rdt-sibling'"
# A literal cd adds a directory the delete may run from, and a relative operand
# must stay inside from every one of them.
expect_both 'tree: cd / && rm -rf * blocks' 2 "${RDT_CWD[@]}" --command 'cd / && rm -rf *'
expect_both 'tree: cd / && rm -rf build blocks' 2 "${RDT_CWD[@]}" --command 'cd / && rm -rf build'
expect_both 'tree: cd -P / then a delete blocks' 2 "${RDT_CWD[@]}" --command 'cd -P /; rm -rf build'
expect_both 'tree: pushd / then a delete blocks' 2 "${RDT_CWD[@]}" --command 'pushd / && rm -rf build'
expect_both 'tree: a bare cd goes home, then a delete blocks' 2 "${RDT_CWD[@]}" --command 'cd && rm -rf build'
expect_both 'tree: cd inside a child shell blocks' 2 "${RDT_CWD[@]}" --command "bash -c 'cd / && rm -rf *'"
expect_both 'tree: env -C / blocks' 2 "${RDT_CWD[@]}" --command 'env -C / rm -rf build'
expect_both 'tree: env --chdir=/ blocks' 2 "${RDT_CWD[@]}" --command 'env --chdir=/ rm -rf build'
expect_both 'tree: sudo -D / blocks' 2 "${RDT_CWD[@]}" --command 'sudo -D / rm -rf build'
# The substitution scan runs before the main parse, so a delete inside a
# substitution is judged against every directory the whole command visits.
expect_both 'tree: a substitution sees a later cd' 2 "${RDT_CWD[@]}" --command 'cd / && echo "$(rm -rf *)"'
expect_both 'tree: a cd after the delete does not move it' 0 "${RDT_CWD[@]}" --command 'rm -rf build && cd ..'
expect_both 'tree: cd into the checkout then a relative delete allowed' 0 "${RDT_CWD[@]}" \
  --command "cd '$RDT_TOP' && rm -rf .work/x"
# Declared overblock: from the ORIGINAL directory `../x` is outside the tree,
# and the guard does not assume the cd succeeded.
expect_both 'tree: cd into a subdirectory then ../x blocks (declared overblock)' 2 "${RDT_CWD[@]}" \
  --command 'cd plugins && rm -rf ../x'
# The same overblock for a cd inside a subshell, which cannot move the parent.
expect_both 'tree: a subshell cd .. then a delete blocks (declared overblock)' 2 "${RDT_CWD[@]}" \
  --command '(cd ..) ; rm -rf build'
# The same overblock for a launcher's directory, which applies only to the
# command it launches.
expect_both 'tree: env -C on another command then a delete blocks (declared overblock)' 2 "${RDT_CWD[@]}" \
  --command 'env -C /opt true; rm -rf build'
# CDPATH can send a relative cd anywhere the command itself names, so a
# relative delete after such a cd is refused rather than guessed; a cd spelled
# with ./ ignores CDPATH and is still followed. A non-literal cd "$d" still
# leaves the delete alone.
expect_both 'cdpath: an inline CDPATH prefix refuses a later relative delete' 2 "${RDT_CWD[@]}" \
  --command 'CDPATH=/c cd Windows && rm -rf x'
expect_both 'cdpath: an inline CDPATH=/ prefix refuses a later relative delete' 2 "${RDT_CWD[@]}" \
  --command 'CDPATH=/ cd c && rm -rf x'
expect_both 'cdpath: an inline prefix refuses from a temp cwd too' 2 --cwd "$TEST_TMPDIR" \
  --command 'CDPATH=/ cd c && rm -rf x'
# Every relative operand after that cd, whatever the list operator and
# whatever the operand's shape.
# Each string must reach the guard VERBATIM. Git Bash rewrites a native
# program's argument shaped `NAME=/path` into a Windows path, so a plain
# `jq -n --arg c 'CDPATH=/ cd c && ...'` hands the guard
# `CDPATH=C:/Program Files/Git/ cd c && ...`, whose command word is
# `Files/Git/` and which holds no cd at all. The payload builders here pass
# MSYS_NO_PATHCONV=1 to jq, and the round trip is asserted so a builder that
# lost it would fail here rather than test a different command.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  assert_eq "cdpath: the payload carries '$rdt_cmd' verbatim" "$rdt_cmd" \
    "$(rdt_pl "$rdt_cmd" "$RDT_TOP" | jq -r .tool_input.command)"
  expect_both "cdpath: $rdt_cmd blocks" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
  expect_both "cdpath: $rdt_cmd blocks from a temp cwd" 2 --cwd "$TEST_TMPDIR" --command "$rdt_cmd"
done <<'EOF'
CDPATH=/ cd c && rm -rf Users
CDPATH=/ cd c && rm -rf Users/
CDPATH=/ cd c && rm -rf ./Users/
CDPATH=/c cd Windows && rm -rf System32/
CDPATH=/ cd c ; rm -rf Users
CDPATH=/ cd c || rm -rf Users
CDPATH=/ cd c && rm -rf Us*/
export CDPATH=/; cd c && rm -rf Users
EOF
expect_both 'cdpath: a CDPATH assignment segment refuses a later relative delete' 2 "${RDT_CWD[@]}" \
  --command 'CDPATH=/c ; cd Windows && rm -rf x'
expect_both 'cdpath: export CDPATH refuses a later relative delete' 2 "${RDT_CWD[@]}" \
  --command 'export CDPATH=/c; cd Windows && rm -rf x'
expect_both 'cdpath: env CDPATH through a child shell refuses' 2 "${RDT_CWD[@]}" \
  --command "env CDPATH=/c bash -c 'cd Windows && rm -rf x'"
expect_both 'cdpath: cd ./sub ignores CDPATH, so the delete is judged' 2 "${RDT_CWD[@]}" \
  --command 'CDPATH=/opt cd ./sub && rm -rf ../y'
expect_both 'cdpath: an absolute delete after it is still judged, and allowed in the tree' 0 "${RDT_CWD[@]}" \
  --command "CDPATH=/c ; cd Windows && rm -rf '$RDT_TOP/x'"
expect_both 'cdpath: a non-literal cd still leaves a relative delete alone' 0 "${RDT_CWD[@]}" \
  --command 'cd "$d" && rm -rf x'

# Brace expansion runs before rm sees its argv, so each alternative is judged
# as its own operand, through the root, bare-variable and outside-tree arms.
expect_both 'brace: {/c,x} blocks (a drive root, no cwd needed)' 2 --command 'rm -rf {/c,x}'
expect_both 'brace: {/,x} blocks' 2 --command 'rm -rf {/,x}'
expect_both 'brace: {~,x} blocks' 2 --command 'rm -rf {~,x}'
expect_both 'brace: {$X,y} blocks (bare variable)' 2 --command 'rm -rf {$X,y}'
expect_both 'brace: an absolute alternative outside blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf {/opt/rdt-x,x}'
expect_both 'brace: a drive alternative blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf {C:/Windows,x}'
expect_both 'brace: an empty alternative before a slash blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf {,/}opt/rdt-x'
expect_both 'brace: .. climbing out through an alternative blocks' 2 "${RDT_CWD[@]}" \
  --command 'rm -rf x{/../../../../..,}/Windows'
expect_both 'brace: {..,x}/y blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf {..,x}/y'
expect_both 'brace: nested alternatives are expanded' 2 "${RDT_CWD[@]}" --command 'rm -rf {a,{c,/opt/rdt-d}}'
expect_both 'brace: inside the tree allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf {a,b}/x a{b,c}d {a,b{c,d}}'
expect_both 'brace: no comma stays literal, allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf x{a}'
expect_both 'brace: quoted braces are literal, allowed' 0 "${RDT_CWD[@]}" --command "rm -rf '{/,x}'"
expect_both 'brace: {a,b} with no cwd allowed' 0 --command 'rm -rf {a,b}'
expect_both 'brace: a sequence is refused' 2 "${RDT_CWD[@]}" --command 'rm -rf x{1..3}'
expect_both 'brace: a letter sequence is refused' 2 "${RDT_CWD[@]}" --command 'rm -rf x{a..c}'
expect_both 'brace: more than 64 expansions is refused' 2 "${RDT_CWD[@]}" \
  --command 'rm -rf {a,b}{c,d}{e,f}{g,h}{i,j}{k,l}{m,n}'
expect_both 'brace: a partly quoted brace is refused' 2 "${RDT_CWD[@]}" --command 'rm -rf "a"{/,x}'
expect_both 'brace: "$X"/{a,b} is refused as partly quoted' 2 "${RDT_CWD[@]}" --command 'rm -rf "$X"/{a,b}'
expect_both 'brace: $X/{a,b} unquoted is left alone like $X/build' 0 "${RDT_CWD[@]}" --command 'rm -rf $X/{a,b}'
expect_both 'brace: inside a substitution blocks' 2 --command 'echo $(rm -rf {/,x})'
guard_invoke "${RDT_CWD[@]}" --command 'rm -rf x{1..3}'
assert_contains "the brace refusal names its form" "$GUARD_ERR" "brace expansion"
# A .. after the first glob component cannot be judged by the directory in
# front of the glob, so it is refused.
expect_both 'glob: .. after a glob blocks' 2 "${RDT_CWD[@]}" \
  --command 'rm -rf .git/*/../../../../../../../../../../../../../../Windows/Temp2'
expect_both 'glob: */.. climbing out blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf */../../../x'
expect_both 'glob: .. inside a glob component blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf .g?t/../../x'
expect_both 'glob: .. before the glob stays judged, inside the tree allowed' 0 "${RDT_CWD[@]}" \
  --command 'rm -rf plugins/../plugins/*/build'
# The judgment is time-bounded in the parse too, but only once this arm has
# work: a command with nothing to judge is never timed, so a slow but harmless
# parse (the 900 sibling bodies above, near twelve seconds on a loaded runner)
# behaves as it does without the arm. Pinned in the source, since no payload
# under MAX_COMMAND_LEN parses that slowly on a fast host.
assert_contains "the deadline is twenty-five seconds" "$(grep -n '^RDT_DEADLINE=' "$HOOK")" "RDT_DEADLINE=25"
assert_contains "the whole-run ceiling is fifty seconds" "$(grep -n '^RDT_DEADLINE_ABS=' "$HOOK")" "RDT_DEADLINE_ABS=50"
assert_contains "the parse callback checks the deadline only once the arm has work" \
  "$(sed -n '/^rdt_check_segment() {/,/^}/p' "$HOOK")" "((RDT_T0 >= 0)) && rdt_deadline"
# Every directory a cd reaches is judged against the PAYLOAD cwd's tree, never
# a tree of its own. The stub git answers every directory as its own toplevel,
# so a per-directory tree would allow this delete in the home directory.
mkdir -p "$TEST_TMPDIR/bin-git-any"
printf '#!/usr/bin/env bash\nd=.\nwhile (($#)); do [[ "$1" == -C ]] && { d="$2"; shift; }; shift; done\nprintf "%%s\\n" "$d"\n' \
  >"$TEST_TMPDIR/bin-git-any/git"
chmod +x "$TEST_TMPDIR/bin-git-any/git"
expect_both 'tree: a cd into another repository is judged against the cwd tree' 2 "${RDT_CWD[@]}" \
  --command 'cd ~ && rm -rf rdt-x' -- "PATH=$TEST_TMPDIR/bin-git-any:$PATH"
expect_both 'tree: the stub still allows the cwd tree itself' 0 "${RDT_CWD[@]}" \
  --command 'rm -rf build' -- "PATH=$TEST_TMPDIR/bin-git-any:$PATH"

# Temp roots: strictly under one is allowed, the root itself and its glob are not.
expect_both 'temp: a path under /tmp allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf /tmp/rdt-x'
expect_both 'temp: a glob under a /tmp subdirectory allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf /tmp/rdt-sub/*'
expect_both 'temp: the suite scratch directory allowed' 0 "${RDT_CWD[@]}" --command "rm -rf '$TEST_TMPDIR/x'"
expect_both 'temp: /tmp itself blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf /tmp'
expect_both 'temp: /tmp/* blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf /tmp/*'

# The scratchpad counts only when it sits strictly under a temp root, so one
# outside temp (here, nonexistent under /opt) is ignored. Inside temp, the
# scratchpad itself and its glob are still refused ahead of the temp arm.
RDT_SP=/opt/rdt-scratch-1
expect_both 'scratchpad: one outside temp is ignored' 2 --payload "$(rdt_pl "rm -rf $RDT_SP/x" "$RDT_TOP" "$RDT_SP")"
expect_both 'scratchpad: one outside temp is ignored (no tree)' 2 --payload "$(rdt_pl "rm -rf $RDT_SP/x" / "$RDT_SP")"
RDT_SPT="$TEST_TMPDIR/rdt-scratch"
expect_both 'scratchpad: a path under it allowed' 0 --payload "$(rdt_pl "rm -rf '$RDT_SPT/x'" "$RDT_TOP" "$RDT_SPT")"
expect_both 'scratchpad: a glob under a subdirectory allowed' 0 --payload "$(rdt_pl "rm -rf '$RDT_SPT/sub/'*" "$RDT_TOP" "$RDT_SPT")"
expect_both 'scratchpad: the scratchpad itself blocks' 2 --payload "$(rdt_pl "rm -rf '$RDT_SPT'" "$RDT_TOP" "$RDT_SPT")"
expect_both 'scratchpad: its glob blocks' 2 --payload "$(rdt_pl "rm -rf '$RDT_SPT/'*" "$RDT_TOP" "$RDT_SPT")"
expect_both 'scratchpad: in backslash form, itself blocks' 2 --payload "$(rdt_pl "rm -rf '$RDT_SPT'" "$RDT_TOP" "${RDT_SPT//\//\\}")"

# A cwd outside any git work tree: only temp and the scratchpad are allowed.
expect_both 'no tree: a relative operand blocks' 2 --cwd / --command 'rm -rf build'
expect_both 'no tree: a temp path allowed' 0 --cwd / --command 'rm -rf /tmp/rdt-x'
expect_both 'no tree: a scratchpad path allowed' 0 --payload "$(rdt_pl "rm -rf '$RDT_SPT/x'" / "$RDT_SPT")"
expect_both 'no tree: a relative cwd skips the arm' 0 --cwd 'relative/dir' --command 'rm -rf ../../x'

# A glob or brace is judged by the literal directory in front of it: outside
# the allowed roots, it is refused whatever it would match.
expect_both 'glob: a glob before the last component outside blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf /opt/*/x'
expect_both 'glob: a ? in a middle component blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf /opt/rdt-hom?/.claude'
expect_both 'glob: a bracket in a middle component blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf /op[t]/rdt/.claude'
expect_both 'glob: a brace blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf /opt/{a,b}'
expect_both 'glob: a brace in a middle component blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf /opt/{a,b}/.claude'
expect_both 'glob: a glob under a HOME prefix blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf ~/rdt-*/x'
expect_both 'glob: a glob inside the tree allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf plugins/*/build'
expect_both 'glob: a brace inside the tree allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf {a,b}/x'
expect_both 'glob: a glob deeper under a temp root allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf /tmp/rdt-*/x'
expect_both '~user blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf ~rdtnosuchuser/.claude'
expect_both '~+ is the working directory, allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf ~+/x'
expect_both 'a \\?\ device path is read as its drive path' 2 "${RDT_CWD[@]}" --command "rm -rf '\\\\?\\C:\\rdt-x'"

# What the guard cannot place, it leaves alone.
expect_both 'defer: an expansion other than HOME' 0 "${RDT_CWD[@]}" --command 'rm -rf "$X/build"'
expect_both 'defer: a drive-relative path' 0 "${RDT_CWD[@]}" --command 'rm -rf C:rel'
expect_both 'defer: relative after cd "$d"' 0 "${RDT_CWD[@]}" --command 'cd "$d" && rm -rf ../x'
expect_both 'defer: relative after cd -' 0 "${RDT_CWD[@]}" --command 'cd - && rm -rf ../x'
expect_both 'defer: relative after popd' 0 "${RDT_CWD[@]}" --command 'popd && rm -rf ../x'
expect_both 'defer: relative after pushd +1' 0 "${RDT_CWD[@]}" --command 'pushd +1 && rm -rf ../x'
expect_both 'defer: relative inside a su login shell' 0 "${RDT_CWD[@]}" --command "su - bob -c 'rm -rf ../x'"
expect_both 'defer: relative through sudo -i' 0 "${RDT_CWD[@]}" --command 'sudo -i rm -rf ../x'
expect_both 'defer: an absolute path is still judged after cd "$d"' 2 "${RDT_CWD[@]}" \
  --command 'cd "$d" && rm -rf /opt/nonexistent-rdt/x'

# Each new refusal names its own form and carries a Fix line.
guard_invoke --command 'rm -rf ""'
assert_exit "empty operand exits 2" 2 "$GUARD_RC"
assert_contains "empty operand names its form" "$GUARD_ERR" "an empty operand"
assert_contains "empty operand carries a Fix line" "$GUARD_ERR" "Fix:"
guard_invoke --command 'rm -rf "$X"'
assert_exit "bare variable exits 2" 2 "$GUARD_RC"
assert_contains "bare variable names its form" "$GUARD_ERR" "a bare variable"
assert_contains "bare variable carries a Fix line" "$GUARD_ERR" "Fix:"
guard_invoke "${RDT_CWD[@]}" --command 'rm -rf /opt/nonexistent-rdt/x'
assert_exit "outside tree exits 2" 2 "$GUARD_RC"
assert_contains "outside tree names its form" "$GUARD_ERR" "outside the working tree"
assert_contains "outside tree carries a Fix line" "$GUARD_ERR" "Fix:"
assert_contains "outside tree sends scratch work under the working tree" "$GUARD_ERR" \
  "put scratch work under the working tree, for example a gitignored .work/"
assert_absent "outside tree no longer sends scratch work to the session scratchpad" "$GUARD_ERR" \
  "put scratch work in the session scratchpad"

# A git that fails leaves the origin with no tree, so the failure lands on the
# refusal side rather than allowing everything.
mkdir -p "$TEST_TMPDIR/bin-git"
printf '#!/usr/bin/env bash\nexit 128\n' >"$TEST_TMPDIR/bin-git/git"
chmod +x "$TEST_TMPDIR/bin-git/git"
expect_both 'git failing: a relative operand blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf build' \
  -- "PATH=$TEST_TMPDIR/bin-git:$PATH"
expect_both 'git failing: a temp path allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf /tmp/rdt-x' \
  -- "PATH=$TEST_TMPDIR/bin-git:$PATH"

# A trailing slash makes rm follow a symlink named last, so such an operand is
# resolved whole: `link/` and a `*/` glob that matches a link are judged by
# where the link points. Without the slash the link itself is the target.
# On Git Bash `winsymlinks:lnk` makes a shortcut the runtime reads as a
# symlink; its default mode copies instead. The dangling link is made first,
# so where `ln -s` would copy it fails or makes no link and the group is
# skipped before anything is copied. The links are unlinked, never recursed.
rdt_ln="$TEST_TMPDIR/links"
mkdir -p "$rdt_ln"
if MSYS=winsymlinks:lnk ln -s /opt/rdt-link-target "$rdt_ln/dang" 2>/dev/null && [[ -L "$rdt_ln/dang" ]]; then
  expect_both 'symlink: link/ to a path outside blocks' 2 "${RDT_CWD[@]}" --command "rm -rf '$rdt_ln/dang/'"
  expect_both 'symlink: link/. to a path outside blocks' 2 "${RDT_CWD[@]}" --command "rm -rf '$rdt_ln/dang/.'"
  expect_both 'symlink: the link itself under temp allowed' 0 "${RDT_CWD[@]}" --command "rm -rf '$rdt_ln/dang'"
  # The same link reached through a brace or a glob, from the link's own
  # directory as cwd (under temp, outside any tree).
  expect_both 'symlink: {link,x}/ blocks' 2 --cwd "$rdt_ln" --command 'rm -rf {dang,x}/'
  expect_both 'symlink: link{,}/ blocks' 2 --cwd "$rdt_ln" --command 'rm -rf dang{,}/'
  expect_both 'symlink: */../link/ blocks' 2 --cwd "$rdt_ln" --command 'rm -rf */../dang/'
  expect_both 'symlink: a brace to the link inside a substitution blocks' 2 --cwd "$rdt_ln" \
    --command 'echo $(rm -rf {dang,x}/)'
  expect_both 'symlink: a plain relative name beside the link allowed' 0 --cwd "$rdt_ln" --command 'rm -rf x'
  if MSYS=winsymlinks:lnk ln -s "$RDT_TOP/.." "$rdt_ln/up" 2>/dev/null && [[ -L "$rdt_ln/up" ]]; then
    expect_both 'symlink: */ matching a link to outside blocks' 2 "${RDT_CWD[@]}" --command "rm -rf '$rdt_ln/'*/"
    expect_both 'symlink: * without the slash allowed (links are removed, not followed)' 0 "${RDT_CWD[@]}" \
      --command "rm -rf '$rdt_ln/'*"
    # A glob before the last component is expanded, so a directory it passes
    # through that is a link is judged by where it points.
    expect_both 'symlink: */* through a link to outside blocks' 2 --cwd "$rdt_ln" --command 'rm -rf */*'
    expect_both 'symlink: u*/x through a link to outside blocks' 2 --cwd "$rdt_ln" --command 'rm -rf u*/x'
    rm -f "$rdt_ln/up"
    # A glob MATCH is a literal path: a `$` or a bracket in its name is not
    # read again as an expansion or a glob. And a glob that matches nothing
    # reaches rm as its own literal text, which is judged as a path too.
    rdt_h3="$TEST_TMPDIR/h3"
    mkdir -p "$rdt_h3/q\$" "$rdt_h3/[b]"
    if MSYS=winsymlinks:lnk ln -s "$RDT_TOP/.." "$rdt_h3/q\$/k" 2>/dev/null &&
      MSYS=winsymlinks:lnk ln -s "$RDT_TOP/.." "$rdt_h3/[b]/k" 2>/dev/null; then
      expect_both 'literal match: a $ in a matched name is not an expansion' 2 --cwd "$rdt_h3" --command 'rm -rf q?/k/'
      expect_both 'literal match: a bracket in a matched name is not globbed again' 2 --cwd "$rdt_h3" \
        --command 'rm -rf ?b?/k/'
      expect_both 'literal match: an unmatched glob is judged as its literal path' 2 --cwd "$rdt_h3" \
        --command 'rm -rf [b]/k/'
      expect_both 'literal match: the same names without the slash allowed' 0 --cwd "$rdt_h3" --command 'rm -rf q?/k'
      # A cd whose target globs is followed to its one match, as a literal
      # directory; a quoted target is literal to begin with.
      expect_both 'cd glob: cd q? follows its one match' 2 --cwd "$rdt_h3" --command 'cd q? && rm -rf k/'
      expect_both 'cd glob: a quoted bracket target is literal' 2 --cwd "$rdt_h3" --command "cd '[b]' && rm -rf k/"
      expect_both 'cd glob: the link itself after cd q? allowed' 0 --cwd "$rdt_h3" --command 'cd q? && rm -rf k'
      rm -f "$rdt_h3/q\$/k" "$rdt_h3/[b]/k"
    else
      rdt_skip "ln -s made no link inside a literal-named directory (7 cases)"
    fi
  else
    rdt_skip "ln -s made no link to an existing directory (11 cases)"
  fi
  rm -f "$rdt_ln/dang"
else
  rdt_skip "ln -s makes no real symlink on this host (19 cases)"
fi

# rdt_ms_payload <label> <want> <budget ms> <payload>: one direct run, its
# verdict and its elapsed time both asserted, then the dispatched run under a
# 20 s backstop.
rdt_ms_payload() {
  local t0 ms rc=0
  t0=${EPOCHREALTIME/./}
  timeout 20 bash "$HOOK" <<<"$4" >/dev/null 2>&1 || rc=$?
  ms=$(((${EPOCHREALTIME/./} - t0) / 1000))
  echo "timing: $1 took ${ms} ms"
  assert_exit "$1 (direct)" "$2" "$rc"
  if ((ms < $3)); then ok "$1 finishes under $3 ms (${ms} ms)"; else bad "$1 took ${ms} ms, budget $3 ms"; fi
  rc=0
  timeout 20 bash "$GUARD_DISPATCH" "$HOOK" <<<"$4" >/dev/null 2>&1 || rc=$?
  assert_exit "$1 (dispatched)" "$2" "$rc"
}
# A glob before the last component is expanded one component at a time, and
# past 256 matches in total the guard refuses at once instead of listing the
# whole tree.
mkdir -p "$TEST_TMPDIR/wide/d"{01..20}/e{01..20}
rdt_ms_payload 'a wide glob tree is refused at the match cap' 2 8000 \
  "$(rdt_pl "rm -rf '$TEST_TMPDIR/wide'/*/*/x" "$RDT_TOP")"
expect_both 'a narrow glob in the same tree allowed' 0 "${RDT_CWD[@]}" --command "rm -rf '$TEST_TMPDIR/wide/d01'/*/x"
# A trailing `*/` reads names before testing any entry, and past 256 refuses:
# a stat per entry over a large temp directory outran the hook timeout.
mkdir -p "$TEST_TMPDIR/wide2"
for ((rdt_d = 0; rdt_d < 300; rdt_d++)); do : >"$TEST_TMPDIR/wide2/f$rdt_d"; done
rdt_ms_payload 'a trailing */ over 300 entries is refused at the cap' 2 15000 \
  "$(rdt_pl "rm -rf '$TEST_TMPDIR/wide2'/*/" "$RDT_TOP")"
expect_both 'a trailing */ over a few entries under temp allowed' 0 "${RDT_CWD[@]}" \
  --command "rm -rf '$TEST_TMPDIR/wide/d01'/*/"
guard_invoke "${RDT_CWD[@]}" --command "rm -rf '$TEST_TMPDIR/wide2'/*/"
assert_contains 'the glob-cap refusal names the entry cap' "$GUARD_ERR" "more than 256 directory entries"
# A batch resolver that runs out of time refuses. A stand-in `timeout` that
# answers 124, the code GNU timeout gives when it kills the command, stands
# for a realpath that ran past the time left.
mkdir -p "$TEST_TMPDIR/bin-to"
printf '#!/usr/bin/env bash\nexit 124\n' >"$TEST_TMPDIR/bin-to/timeout"
chmod +x "$TEST_TMPDIR/bin-to/timeout"
guard_invoke "${RDT_CWD[@]}" --command 'rm -rf ./build' -- "PATH=$TEST_TMPDIR/bin-to:$PATH"
assert_exit 'a resolver that runs out of time refuses' 2 "$GUARD_RC"
assert_contains 'the timeout refusal names the time bound' "$GUARD_ERR" "ran out of time"
# With no `timeout` (stock macOS) the batch call cannot be cut short. An
# exported `command` that reports `timeout` missing sends the guard down that
# branch, with the 124 stand-in above still first on PATH: the if-branch would
# refuse, so an allow here proves the no-timeout branch ran and judged. That
# branch must also check the deadline AFTER the call, which is pinned in the
# source because a real call cannot be made to hang on demand.
rdt_nocmd="BASH_FUNC_command%%=() { [[ \"\${1-} \${2-}\" == \"-v timeout\" ]] && return 1; builtin command \"\$@\"; }"
guard_invoke "${RDT_CWD[@]}" --command 'rm -rf ./build' -- "PATH=$TEST_TMPDIR/bin-to:$PATH" "$rdt_nocmd"
assert_exit 'with no timeout an ordinary delete in the tree is allowed' 0 "$GUARD_RC"
guard_invoke "${RDT_CWD[@]}" --command 'rm -rf ../../x' -- "PATH=$TEST_TMPDIR/bin-to:$PATH" "$rdt_nocmd"
assert_exit 'with no timeout an escape from the tree still blocks' 2 "$GUARD_RC"
# The git toplevel lookup is bounded the same way: a stand-in `timeout` that
# answers 124 for git alone, and runs the real `timeout` for everything else,
# stands for a git that stalled. A 70 s git stall had carried the guard past
# the 60 s hook timeout, which fails open.
rdt_real_to="$(type -P timeout)"
if [[ -n "$rdt_real_to" ]]; then
  mkdir -p "$TEST_TMPDIR/bin-tog"
  printf '#!/usr/bin/env bash\n[[ "${2-}" == git ]] && exit 124\nexec %q "$@"\n' "$rdt_real_to" >"$TEST_TMPDIR/bin-tog/timeout"
  chmod +x "$TEST_TMPDIR/bin-tog/timeout"
  guard_invoke "${RDT_CWD[@]}" --command 'rm -rf ./build' -- "PATH=$TEST_TMPDIR/bin-tog:$PATH"
  assert_exit 'a git lookup that runs out of time refuses' 2 "$GUARD_RC"
  assert_contains 'the git timeout refusal names the time bound' "$GUARD_ERR" "ran out of time"
else
  rdt_skip "no timeout on PATH to wrap (2 cases)"
fi
rdt_nt="$(sed -n '/^rdt_lines_to() {/,/^}/p' "$HOOK")"
assert_contains 'with no timeout the deadline is checked after the batch call' \
  "$(grep -A1 -F '__rb_out=$("$@" 2>/dev/null) || __rb_rc=$?' <<<"$rdt_nt")" "rdt_deadline"
rdt_sys=""
for rdt_t in C:/Windows /usr; do
  [[ -d "$rdt_t" ]] && rdt_sys="$rdt_t" && break
done
if [[ -n "$rdt_sys" ]]; then
  rdt_ms_payload "a deep glob over $rdt_sys is refused in time" 2 8000 \
    "$(rdt_pl "rm -rf $rdt_sys/*/*/*/x" "$RDT_TOP")"
else
  rdt_skip "no C:/Windows or /usr to glob over (3 cases)"
fi
# A word full of braces is refused before the expander walks it.
rdt_br=""
for ((rdt_d = 0; rdt_d < 3000; rdt_d++)); do rdt_br+='{'; done
rdt_ms_payload 'an operand of 3000 braces is refused in time' 2 8000 "$(rdt_pl "rm -rf ${rdt_br}x" "$RDT_TOP")"
guard_invoke "${RDT_CWD[@]}" --command "rm -rf ${rdt_br}x"
assert_contains "the brace-count refusal names its form" "$GUARD_ERR" "brace expansion"
# A long run of nameless segments behind a `${X}`. A rescan per segment took
# over 30 s at 2 KB, past the hook timeout, and the harness cancels a hook
# there without a block, so the later `rm -rf ~` in the same command would
# have run unjudged. An operand longer than PATH_MAX (4096) is refused before
# any scan, and one just under it is stripped in one pass.
rdt_sl=""
for ((rdt_d = 0; rdt_d < 8000; rdt_d++)); do rdt_sl+='/*'; done
rdt_ms_payload 'a ${X} operand of 8000 nameless segments is refused in time' 2 8000 \
  "$(rdt_pl "rm -rf \"\${X}${rdt_sl}\"; rm -rf ~" "")"
rdt_ms_payload 'the same operand with a cwd is refused in time' 2 8000 \
  "$(rdt_pl "rm -rf \"\${X}${rdt_sl}\"; rm -rf ~" "$RDT_TOP")"
guard_invoke --command "rm -rf \"a${rdt_sl}\""
assert_exit 'an operand longer than PATH_MAX is refused' 2 "$GUARD_RC"
assert_contains 'the refusal names the operand length' "$GUARD_ERR" "an operand of "
rdt_ms_payload 'a ${X} operand just under PATH_MAX is refused in time' 2 8000 \
  "$(rdt_pl "rm -rf \"\${X}${rdt_sl:0:4090}\"; rm -rf ~" "$RDT_TOP")"
# Deeper than 128 components is refused unscanned: resolving one lookup per
# component took realpath 90 s over 2,000 of them. 128 deep is still judged.
rdt_dp=""
for ((rdt_d = 0; rdt_d < 128; rdt_d++)); do rdt_dp+='/x'; done
rdt_ms_payload 'an operand 128 components deep in the tree is allowed in time' 0 15000 \
  "$(rdt_pl "rm -rf \"build${rdt_dp}\"" "$RDT_TOP")"
guard_invoke "${RDT_CWD[@]}" --command "rm -rf \"build${rdt_dp}/x\""
assert_exit 'an operand 129 components deep is refused' 2 "$GUARD_RC"
assert_contains 'the refusal names the separator count' "$GUARD_ERR" "path separators"
rdt_ms_payload 'a 4 KB glob operand of 2,000 components is refused in time' 2 8000 \
  "$(rdt_pl "rm -rf \"build${rdt_sl:0:4090}\"" "$RDT_TOP")"
expect_both 'an operand of 129 braces is refused' 2 --command "rm -rf ${rdt_br:0:129}x"
expect_both 'an operand of 3 braces allowed' 0 --command "rm -rf ${rdt_br:0:3}x"
# A glob before the last component over real directories under temp allowed.
mkdir -p "$TEST_TMPDIR/g4ok/real"
expect_both 'glob: */x over real directories under temp allowed' 0 --cwd "$TEST_TMPDIR/g4ok" --command 'rm -rf */x'
expect_both 'glob: */* over real directories under temp allowed' 0 --cwd "$TEST_TMPDIR/g4ok" --command 'rm -rf */*'
# A cd to a glob with exactly one match follows it; none or several leaves
# the directory unknown, and a relative delete after it is refused.
mkdir -p "$TEST_TMPDIR/g4cd/real" "$TEST_TMPDIR/g4cd/rea2" "$TEST_TMPDIR/g4cd/solo"
expect_both 'cd glob: one match is followed, a delete under it allowed' 0 --cwd "$TEST_TMPDIR/g4cd" \
  --command 'cd sol* && rm -rf x'
expect_both 'cd glob: one match is followed, an escape from it blocks' 2 --cwd "$TEST_TMPDIR/g4cd" \
  --command 'cd sol* && rm -rf ../../../../../../../../../../x'
expect_both 'cd glob: several matches refuse a relative delete' 2 --cwd "$TEST_TMPDIR/g4cd" \
  --command 'cd rea? && rm -rf x'
expect_both 'cd glob: no match refuses a relative delete' 2 --cwd "$TEST_TMPDIR/g4cd" --command 'cd zz? && rm -rf x'
expect_both 'cd glob: an absolute target with no match refuses' 2 "${RDT_CWD[@]}" \
  --command 'cd /opt/rdt-nomatc[h] && rm -rf x'
expect_both 'cd glob: an absolute delete after it is still judged' 0 "${RDT_CWD[@]}" \
  --command "cd /opt/rdt-nomatc[h] && rm -rf '$RDT_TOP/x'"

# An unexpected error inside the judgment refuses rather than exiting 1, which
# the abort boundary would pass. The exported function stands in for any such
# error: it shadows a builtin the judgment calls and reads an unset variable.
expect_both 'an error inside the judgment refuses' 2 "${RDT_CWD[@]}" --command 'rm -rf build' \
  -- 'BASH_FUNC_mapfile%%=() { : "$RDT_NO_SUCH_VARIABLE"; }'

# A host with no `realpath -m` (BSD, macOS) takes the lexical fallback.
rdt_realpath=$(command -v realpath || true)
if [[ -n "$rdt_realpath" ]]; then
  mkdir -p "$TEST_TMPDIR/bin-rp"
  printf '#!/usr/bin/env bash\n[[ "${1-}" == -m ]] && exit 1\nexec %q "$@"\n' "$rdt_realpath" >"$TEST_TMPDIR/bin-rp/realpath"
  chmod +x "$TEST_TMPDIR/bin-rp/realpath"
  rdt_rp=(-- "PATH=$TEST_TMPDIR/bin-rp:$PATH")
  expect_both 'no realpath -m: a relative operand allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf build' "${rdt_rp[@]}"
  expect_both 'no realpath -m: an escape blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf ../rdt-sibling' "${rdt_rp[@]}"
  expect_both 'no realpath -m: a temp path allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf /tmp/rdt-x' "${rdt_rp[@]}"
  expect_both 'no realpath -m: /tmp itself blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf /tmp' "${rdt_rp[@]}"
  expect_both 'no realpath -m: the scratchpad arm allows' 0 \
    --payload "$(rdt_pl "rm -rf '$RDT_SPT/x'" "$RDT_TOP" "$RDT_SPT")" "${rdt_rp[@]}"
  expect_both 'no realpath -m: the scratchpad itself blocks' 2 \
    --payload "$(rdt_pl "rm -rf '$RDT_SPT'" "$RDT_TOP" "$RDT_SPT")" "${rdt_rp[@]}"
else
  rdt_skip "no realpath on PATH, so the no-realpath -m stub cannot wrap one (6 cases)"
fi

# Windows: a short (8.3) and a long spelling of one scratchpad are the same
# directory, and so are the /tmp mount and the drive path it maps to.
case "${OSTYPE:-}" in
msys* | cygwin* | win32)
  mkdir -p "$TEST_TMPDIR/RdtScratchpadLongName"
  rdt_long=$(cygpath -l -m -- "$TEST_TMPDIR/RdtScratchpadLongName")
  rdt_short=$(cygpath -s -m -- "$rdt_long")
  if [[ -n "$rdt_short" && "$rdt_short" != "$rdt_long" ]]; then
    expect_both '8.3: the short spelling of a long-named scratchpad blocks' 2 \
      --payload "$(rdt_pl "rm -rf '$rdt_short'" "$RDT_TOP" "$rdt_long")"
    expect_both '8.3: the long spelling of a short-named scratchpad blocks' 2 \
      --payload "$(rdt_pl "rm -rf '$rdt_long'" "$RDT_TOP" "$rdt_short")"
    expect_both '8.3: under the short spelling allowed' 0 \
      --payload "$(rdt_pl "rm -rf '$rdt_short/x'" "$RDT_TOP" "$rdt_long")"
  else
    rdt_skip "this volume generates no 8.3 short names (3 cases)"
  fi
  rdt_tmp_alias="/tmp/${TEST_TMPDIR##*/}/RdtScratchpadLongName"
  if [[ -d "$rdt_tmp_alias" && "$rdt_tmp_alias" -ef "$rdt_long" ]]; then
    expect_both 'mount alias: the /tmp spelling of the scratchpad blocks' 2 \
      --payload "$(rdt_pl "rm -rf $rdt_tmp_alias" "$RDT_TOP" "$rdt_long")"
    expect_both 'mount alias: under the /tmp spelling allowed' 0 \
      --payload "$(rdt_pl "rm -rf $rdt_tmp_alias/x" "$RDT_TOP" "$rdt_long")"
  else
    rdt_skip "the suite scratch directory is not reachable under /tmp (2 cases)"
  fi
  ;;
*) rdt_skip "8.3 and /tmp mount cases need a Windows host (5 cases)" ;;
esac

# The judgment is batched: one realpath and one git per distinct directory, so
# a command at the length ceiling finishes well inside the hook timeout, and a
# chain of cd lines past the origin cap refuses rather than growing without
# bound.
rdt_timed_payload() { # <label> <want> <payload>
  local via rc
  local -a argv
  for via in direct dispatched; do
    if [[ "$via" == direct ]]; then argv=(bash "$HOOK"); else argv=(bash "$GUARD_DISPATCH" "$HOOK"); fi
    rc=0
    timeout 20 "${argv[@]}" <<<"$3" >/dev/null 2>&1 || rc=$?
    assert_exit "$1 ($via)" "$2" "$rc"
  done
}
rdt_many="rm -rf"
for ((rdt_d = 0; rdt_d < 500; rdt_d++)); do rdt_many+=" d$rdt_d/x"; done
rdt_timed_payload '500 distinct in-tree targets are allowed in time' 0 "$(rdt_pl "$rdt_many" "$RDT_TOP")"
rdt_many="rm -rf"
for ((rdt_d = 0; ${#rdt_many} < 15900; rdt_d++)); do rdt_many+=" d$rdt_d/x"; done
rdt_timed_payload 'a 16 KB delete of distinct targets is refused at the target cap' 2 "$(rdt_pl "$rdt_many" "$RDT_TOP")"
# The shape that outran the hook timeout: 31 directory changes times 126 deep
# operands, the last one outside. Past 512 directory-and-target pairs the guard
# refuses at once, and the time is asserted, not just the verdict.
rdt_big=""
for ((rdt_d = 0; rdt_d < 31; rdt_d++)); do rdt_big+="cd '$RDT_TOP/nx$rdt_d'; "; done
rdt_big+="rm -rf"
for ((rdt_d = 0; rdt_d < 125; rdt_d++)); do rdt_big+=" a$rdt_d/b/c/d/e/f/g/h"; done
rdt_big+=" C:/Windows/x"
rdt_t0=${EPOCHREALTIME/./}
guard_invoke --payload "$(rdt_pl "$rdt_big" "$RDT_TOP")"
rdt_ms=$(((${EPOCHREALTIME/./} - rdt_t0) / 1000))
assert_exit "31 cd lines x 126 deep operands is refused" 2 "$GUARD_RC"
assert_contains "the refusal names the target cap" "$GUARD_ERR" "too many recursive delete targets"
echo "timing: the cap case took ${rdt_ms} ms"
if ((rdt_ms < 15000)); then
  ok "the cap case refuses well under the hook timeout (${rdt_ms} ms)"
else
  bad "the cap case took ${rdt_ms} ms"
fi
rdt_timed_payload 'the cap case under the dispatcher is refused in time' 2 "$(rdt_pl "$rdt_big" "$RDT_TOP")"
# An operand carrying a newline cannot be resolved faithfully, so it refuses.
expect_both 'an operand with a newline blocks' 2 "${RDT_CWD[@]}" --command $'rm -rf "a\nb"'
rdt_cds=""
for ((rdt_d = 0; rdt_d < 40; rdt_d++)); do rdt_cds+="cd d$rdt_d && "; done
rdt_timed_payload 'a chain of 40 relative cd lines is refused in time' 2 "$(rdt_pl "${rdt_cds}rm -rf x" "$RDT_TOP")"
guard_invoke --payload "$(rdt_pl "${rdt_cds}rm -rf x" "$RDT_TOP")"
assert_contains "the cd chain refusal names the directory cap" "$GUARD_ERR" "too many directory changes"
# An unmapped drive never exists, so a walk up to the nearest existing
# directory must stop at its root rather than spin until the hook timeout.
case "${OSTYPE:-}" in
msys* | cygwin* | win32)
  rdt_free=""
  for rdt_l in Q R S T U V W X Y Z; do
    [[ -e "$rdt_l:/" ]] || {
      rdt_free="$rdt_l"
      break
    }
  done
  if [[ -n "$rdt_free" ]]; then
    rdt_timed_payload 'an unmapped drive target is refused in time' 2 "$(rdt_pl "rm -rf $rdt_free:/rdt-x" "$RDT_TOP")"
    rdt_timed_payload 'a cd to an unmapped drive then a delete is refused in time' 2 \
      "$(rdt_pl "cd $rdt_free:/ && rm -rf x" "$RDT_TOP")"
  else
    rdt_skip "every drive letter Q to Z is mapped (2 cases)"
  fi
  ;;
*) rdt_skip "unmapped drive cases need a Windows host (2 cases)" ;;
esac

# --- 2c. The allow corpus again, with a payload cwd ---------------------------
# A subset of section 2 re-run from the checkout toplevel. The expected flips
# are the targets outside the tree and temp: HOME, a drive, a root-level glob,
# a UNC path, and a `~name` prefix. Everything under the tree, under temp, or
# unplaceable keeps its allow.
while IFS='|' read -r rdt_want rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "with cwd: $rdt_cmd" "$rdt_want" "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
0|rm -rf ./build dist
0|rm -rf build/
0|rm -rf /tmp/x
0|rm -rf "$TMPDIR/x"
2|rm -rf ~/.cache/foo
2|rm -rf $HOME/x
2|rm -rf C:/build/x
2|rm -rf /c/build/x
2|rm -rf /tmp*
2|rm -rf ~/proj*
2|rm -rf /c/dev/*
2|rm -rf /_
0|rm -rf *
2|rm -rf /c*
2|rm -rf ~*
2|rm -rf //server/share/dir
0|bash -c "rm -rf ./build"
0|eval "rm -rf ./build"
0|echo "$(rm -rf ./build)"
0|env -S 'rm -rf ./build'
0|taskset 1 rm -rf ./build
0|flock /tmp/l rm -rf ./build
0|rm.EXE -rf ./build
0|su -c 'rm -rf ./build'
0|runuser -u bob -- rm -rf ./build
0|coproc shredder rm -rf ./build
0|{ rm -rf ./build; }
0|rm -f /file
0|git rm -rf src
0|rm -rf
EOF
# The escapes collapse to `\servershare`, a root-level name outside the tree.
# portability-ok: a literal backslash pair in a command string fed to the guard, not a grep -E escape
expect_both 'with cwd: rm -rf \\server\share' 2 "${RDT_CWD[@]}" --command 'rm -rf \\server\share'

# --- 2d. block_root_delete_target_allowed_roots -------------------------------
# A user-owned userConfig key adds roots on the temp-root rule. The fixture sits
# under the checkout's gitignored .work, outside every temp root, and every case
# runs from cwd `/`, outside any tree, so only the key can let a delete through:
# each allow is paired with the same command blocking while the key is unset.
# HOME is a fake directory beside the roots.
mkdir -p "$RDT_TOP/.work"
RDT_AB=$(mktemp -d "$RDT_TOP/.work/rdt-allowed-roots.XXXXXX")
RDT_AR="$RDT_AB/root"
RDT_AR2="$RDT_AB/root2"
RDT_AL="$RDT_AB/linkroot"
RDT_AO="$RDT_AB/elsewhere"
RDT_AH="$RDT_AB/home"
mkdir -p "$RDT_AR/child" "$RDT_AR2/child" "$RDT_AL/child" "$RDT_AO/x" "$RDT_AH" "$RDT_AB/root-x/child"
RDT_KEY=CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ALLOWED_ROOTS
# rdt_ar <label> <want> <command> [roots [home]]: the command from `/`, HOME a
# fake directory, the key set to <roots> when one is given.
rdt_ar() {
  local -a env=("HOME=${5:-$RDT_AH}")
  [[ -z "${4:-}" ]] || env+=("$RDT_KEY=$4")
  expect_both "allowed roots: $1" "$2" --cwd / --command "$3" -- "${env[@]}"
}

rdt_ar 'unset key: a path under the root blocks' 2 "rm -rf '$RDT_AR/child'"
rdt_ar 'a path under the root allowed' 0 "rm -rf '$RDT_AR/child'" "$RDT_AR"
rdt_ar 'a deeper nonexistent path allowed' 0 "rm -rf '$RDT_AR/a/b/c'" "$RDT_AR"
rdt_ar 'unset key: a glob below a subdirectory blocks' 2 "rm -rf '$RDT_AR/child'/*"
rdt_ar 'a glob below a subdirectory allowed' 0 "rm -rf '$RDT_AR/child'/*" "$RDT_AR"
rdt_ar 'unset key: */x under the root blocks' 2 "rm -rf '$RDT_AR'/*/x"
rdt_ar '*/x under the root allowed' 0 "rm -rf '$RDT_AR'/*/x" "$RDT_AR"
rdt_ar 'unset key: a second root blocks' 2 "rm -rf '$RDT_AR2/child'"
rdt_ar 'a second root alone blocks the first root' 2 "rm -rf '$RDT_AR/child'" "$RDT_AR2"
rdt_ar 'a second comma-separated root allowed' 0 "rm -rf '$RDT_AR2/child'" "$RDT_AR,$RDT_AR2"
rdt_ar 'the first of two roots allowed' 0 "rm -rf '$RDT_AR/child'" "$RDT_AR,$RDT_AR2"
rdt_ar 'entries are trimmed' 0 "rm -rf '$RDT_AR2/child'" " $RDT_AR , $RDT_AR2 "
if MSYS=winsymlinks:lnk ln -s "$RDT_AR" "$RDT_AB/rootlink" 2>/dev/null && [[ -L "$RDT_AB/rootlink" ]]; then
  rdt_ar 'a symlinked root compares by real path' 0 "rm -rf '$RDT_AR/child'" "$RDT_AB/rootlink"
  rdt_ar 'a path through a symlinked root' 0 "rm -rf '$RDT_AB/rootlink/child'" "$RDT_AR"
  rdt_ar 'a symlinked root itself blocks' 2 "rm -rf '$RDT_AB/rootlink'" "$RDT_AB/rootlink"
else
  rdt_skip "ln -s makes no real symlink on this host (3 cases)"
fi

# Refused whatever is listed: the root, its glob, siblings, and every earlier
# refusal in the guard.
rdt_ar 'the root itself blocks' 2 "rm -rf '$RDT_AR'" "$RDT_AR"
rdt_ar 'the root with a trailing slash blocks' 2 "rm -rf '$RDT_AR/'" "$RDT_AR"
rdt_ar 'the root dot blocks' 2 "rm -rf '$RDT_AR/.'" "$RDT_AR"
rdt_ar 'the root glob blocks' 2 "rm -rf '$RDT_AR'/*" "$RDT_AR"
rdt_ar 'a child reached back to the root blocks' 2 "rm -rf '$RDT_AR/child/..'" "$RDT_AR"
rdt_ar 'a name-prefix sibling blocks' 2 "rm -rf '$RDT_AR-x/child'" "$RDT_AR"
rdt_ar 'a .. escape to a sibling blocks' 2 "rm -rf '$RDT_AR/../elsewhere'" "$RDT_AR"
rdt_ar 'a .. escape through a child blocks' 2 "rm -rf '$RDT_AR/child/../../elsewhere/x'" "$RDT_AR"
rdt_ar 'a sibling directory blocks' 2 "rm -rf '$RDT_AO/x'" "$RDT_AR"
rdt_ar 'rm -rf / blocks' 2 'rm -rf /' "$RDT_AR"
rdt_ar 'rm -rf ~ blocks' 2 'rm -rf ~' "$RDT_AR"
rdt_ar "rm -rf '\$HOME' blocks" 2 "rm -rf '\$HOME'" "$RDT_AR"
rdt_ar 'rm -rf "$HOME" blocks' 2 'rm -rf "$HOME"' "$RDT_AR"
rdt_ar 'rm -rf ${HOME} blocks' 2 'rm -rf ${HOME}' "$RDT_AR"
rdt_ar 'rm -rf ~/x blocks' 2 'rm -rf ~/x' "$RDT_AR"
rdt_ar '--no-preserve-root under the root blocks' 2 "rm -rf --no-preserve-root '$RDT_AR/child'" "$RDT_AR"
rdt_ar 'an empty operand blocks' 2 'rm -rf ""' "$RDT_AR"
rdt_ar 'a bare variable blocks' 2 'rm -rf $X' "$RDT_AR"
rdt_ar 'a bare variable beside an allowed path blocks' 2 "rm -rf '$RDT_AR/child' \$X" "$RDT_AR"
rdt_ar 'a root beside an allowed path blocks' 2 "rm -rf '$RDT_AR/child' /" "$RDT_AR"
rdt_ar 'a path outside beside an allowed one blocks' 2 "rm -rf '$RDT_AR/child' '$RDT_AO/x'" "$RDT_AR"
rdt_ar 'a drive root blocks' 2 'rm -rf C:/' "$RDT_AR"
rdt_ar 'a UNC share root blocks' 2 'rm -rf //server/share' "$RDT_AR"
rdt_ar 'a child shell outside the root blocks' 2 "bash -c 'rm -rf $RDT_AO/x'" "$RDT_AR"
rdt_ar 'a child shell under the root allowed' 0 "bash -c 'rm -rf $RDT_AR/child'" "$RDT_AR"
rdt_ar 'a cd out of the root then a relative delete blocks' 2 "cd '$RDT_AO' && rm -rf x" "$RDT_AR"

# HOME inside or above a listed root is never deletable through it.
rdt_ar 'HOME under the root blocks' 2 "rm -rf '$RDT_AR/h'" "$RDT_AR" "$RDT_AR/h"
rdt_ar 'a directory holding HOME blocks' 2 "rm -rf '$RDT_AR/h'" "$RDT_AR" "$RDT_AR/h/deep"
rdt_ar 'the root as HOME grants nothing' 2 "rm -rf '$RDT_AR/child'" "$RDT_AR" "$RDT_AR"
rdt_ar 'a sibling of HOME under a listed root allowed' 0 "rm -rf '$RDT_AR/child'" "$RDT_AR" "$RDT_AR/h"

# A symlink inside a root that points outside is judged by where it points.
if MSYS=winsymlinks:lnk ln -s "$RDT_AO" "$RDT_AL/link" 2>/dev/null && [[ -L "$RDT_AL/link" ]]; then
  rdt_ar 'a real directory beside the link allowed' 0 "rm -rf '$RDT_AL/child'" "$RDT_AL"
  rdt_ar 'the link itself is unlinked, allowed' 0 "rm -rf '$RDT_AL/link'" "$RDT_AL"
  rdt_ar 'link/ out of the root blocks' 2 "rm -rf '$RDT_AL/link/'" "$RDT_AL"
  rdt_ar 'link/. out of the root blocks' 2 "rm -rf '$RDT_AL/link/.'" "$RDT_AL"
  rdt_ar 'a path through the link blocks' 2 "rm -rf '$RDT_AL/link/x'" "$RDT_AL"
  rdt_ar 'a */ glob matching the link blocks' 2 "rm -rf '$RDT_AL'/*/" "$RDT_AL"
  rdt_ar 'a */x glob through the link blocks' 2 "rm -rf '$RDT_AL'/*/x" "$RDT_AL"
  rdt_ar 'a cd into the link then a relative delete blocks' 2 "cd '$RDT_AL/link' && rm -rf x" "$RDT_AL"
else
  rdt_skip "ln -s makes no real symlink on this host (8 cases)"
fi

# An entry that grants nothing is ignored; the rest of the list still works.
# The relative entry drops a drive prefix (Windows toplevel is `D:/...`) or a
# leading slash, so it is relative on every host.
rdt_rel="$RDT_AR"
if [[ "$rdt_rel" =~ ^[A-Za-z]:/ ]]; then rdt_rel="${rdt_rel:3}"; else rdt_rel="${rdt_rel#/}"; fi
rdt_ar 'a relative root grants nothing' 2 "rm -rf '$RDT_AR/child'" "$rdt_rel"
rdt_ar "the root '/' grants nothing" 2 "rm -rf '$RDT_AR/child'" /
# The guard drops `/` even where it maps to the Git install directory, which /opt lies under.
rdt_ar "the root '/' does not allow a top-level path" 2 'rm -rf /opt/rdt-allowed-x/y' /
rdt_ar 'an empty entry grants nothing' 2 "rm -rf '$RDT_AR/child'" ","
rdt_ar 'a root equal to HOME grants nothing' 2 "rm -rf '$RDT_AH/x'" "$RDT_AH"
rdt_ar 'HOME with a trailing slash grants nothing' 2 "rm -rf '$RDT_AH/x'" "$RDT_AH/"
rdt_ar 'a root holding HOME still refuses HOME itself' 2 "rm -rf '$RDT_AH'" "$RDT_AB"
rdt_ar 'a root holding HOME allows a sibling of HOME' 0 "rm -rf '$RDT_AO/x'" "$RDT_AB"
rdt_ar 'a trailing line break grants nothing' 2 "rm -rf '$RDT_AR/child'" "$RDT_AR"$'\n'
rdt_ar 'a leading line break grants nothing' 2 "rm -rf '$RDT_AR/child'" $'\n'"$RDT_AR"
rdt_ar 'a line break entry beside a good one is skipped' 0 "rm -rf '$RDT_AR2/child'" "$RDT_AR"$'\n'",$RDT_AR2"
rdt_ar 'a .. root grants nothing' 2 "rm -rf '$RDT_AR/child'" "$RDT_AR/../root"
rdt_ar 'a .. root above the fixture grants nothing' 2 "rm -rf '$RDT_AO/x'" "$RDT_AR/.."
rdt_ar 'a * prefix entry does not reach below a matching child' 2 "rm -rf '$RDT_AR/child'" "$RDT_AB/ro*"
rdt_ar 'a bare * root grants nothing' 2 "rm -rf '$RDT_AR/child'" "$RDT_AB/*"
rdt_ar 'a ? root grants nothing' 2 "rm -rf '$RDT_AR/child'" "$RDT_AB/roo?"
rdt_ar 'a [ root grants nothing' 2 "rm -rf '$RDT_AR/child'" "$RDT_AB/roo[t]"
rdt_ar 'a UNC root grants nothing' 2 "rm -rf '$RDT_AR/child'" '//server/share'
rdt_ar 'a relative entry beside a good one is skipped' 0 "rm -rf '$RDT_AR/child'" "rel/root,$RDT_AR"
rdt_ar 'a .. entry beside a good one is skipped' 0 "rm -rf '$RDT_AR2/child'" "$RDT_AR/../root,$RDT_AR2"
rdt_ar 'a * entry beside a good one is skipped' 0 "rm -rf '$RDT_AR2/child'" "$RDT_AB/*,$RDT_AR2"
rdt_ar 'a root entry does not allow its sibling by prefix' 2 "rm -rf '$RDT_AB/root2/child'" "$RDT_AB/roo"

# A name-prefix entry (one trailing `*` after a literal name) allows a direct
# child of its directory whose name extends the prefix, and nothing else: the
# directory, the bare prefix, a sibling, a deeper path, a glob, a `..` and a
# symlink named like a child all stay refused (#6542).
RDT_PP="$RDT_AB/wt"
RDT_PX="$RDT_PP/.tmp-*"
mkdir -p "$RDT_PP/.tmp-6527/sub" "$RDT_PP/other-worktree" "$RDT_PP/.tmp-"
rdt_ar 'prefix: unset key, a matching child blocks' 2 "rm -rf '$RDT_PP/.tmp-6527'"
rdt_ar 'prefix: a matching child allowed' 0 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_PX"
rdt_ar 'prefix: a matching child with a trailing slash allowed' 0 "rm -rf '$RDT_PP/.tmp-6527/'" "$RDT_PX"
rdt_ar 'prefix: a nonexistent matching child allowed' 0 "rm -rf '$RDT_PP/.tmp-new'" "$RDT_PX"
rdt_ar 'prefix: beside a directory entry allowed' 0 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_AR,$RDT_PX"
rdt_ar 'prefix: the directory itself blocks' 2 "rm -rf '$RDT_PP'" "$RDT_PX"
rdt_ar 'prefix: a sibling worktree blocks' 2 "rm -rf '$RDT_PP/other-worktree'" "$RDT_PX"
rdt_ar 'prefix: the bare prefix blocks' 2 "rm -rf '$RDT_PP/.tmp-'" "$RDT_PX"
rdt_ar 'prefix: a path below a matching child blocks' 2 "rm -rf '$RDT_PP/.tmp-6527/sub'" "$RDT_PX"
rdt_ar 'prefix: a matching child .. blocks' 2 "rm -rf '$RDT_PP/.tmp-6527/..'" "$RDT_PX"
rdt_ar 'prefix: a nested .tmp-x/../.. blocks' 2 "rm -rf '$RDT_PP/.tmp-6527/../..'" "$RDT_PX"
rdt_ar 'prefix: a .. escape to a sibling blocks' 2 "rm -rf '$RDT_PP/.tmp-6527/../other-worktree'" "$RDT_PX"
rdt_ar 'prefix: a trailing dot after the bare prefix blocks' 2 "rm -rf '$RDT_PP/.tmp-.'" "$RDT_PX"
rdt_ar 'prefix: a matching name with a trailing dot blocks' 2 "rm -rf '$RDT_PP/.tmp-6527.'" "$RDT_PX"
rdt_ar 'prefix: a matching name with a trailing space blocks' 2 "rm -rf '$RDT_PP/.tmp-6527 '" "$RDT_PX"
rdt_ar 'prefix: a nonexistent child/ blocks' 2 "rm -rf '$RDT_PP/.tmp-new/'" "$RDT_PX"
rdt_ar 'prefix: a nonexistent child/. blocks' 2 "rm -rf '$RDT_PP/.tmp-new/.'" "$RDT_PX"
rdt_ar 'prefix: a link made in the same command, then link/, blocks' 2 "ln -s '$RDT_AO' '$RDT_PP/.tmp-made' && rm -rf '$RDT_PP/.tmp-made/'" "$RDT_PX"
rdt_ar 'prefix: the glob of the prefix blocks' 2 "rm -rf '$RDT_PP'/.tmp-*" "$RDT_PX"
rdt_ar 'prefix: the glob of the directory blocks' 2 "rm -rf '$RDT_PP'/*" "$RDT_PX"
rdt_ar 'prefix: a glob below a matching child blocks' 2 "rm -rf '$RDT_PP/.tmp-6527'/*" "$RDT_PX"
rdt_ar 'prefix: a path outside blocks' 2 "rm -rf '$RDT_AO/x'" "$RDT_PX"
rdt_ar 'prefix: rm -rf / blocks' 2 'rm -rf /' "$RDT_PX"
rdt_ar 'prefix: a prefix under HOME grants nothing' 2 "rm -rf '$RDT_AH/.tmp-x'" "$RDT_AH/.tmp-*"
rdt_ar 'prefix: a root-level prefix grants nothing' 2 'rm -rf /.tmp-rdt-x' '/.tmp-*'
rdt_ar "prefix: a directory that resolves to '/' grants nothing" 2 'rm -rf /.tmp-rdt-x' '/./.tmp-*'
rdt_ar 'prefix: an empty name grants nothing' 2 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_PP/*"
rdt_ar 'prefix: a second glob character grants nothing' 2 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_PP/.tmp-?*"
rdt_ar 'prefix: a glob in the directory grants nothing' 2 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_AB/w*/.tmp-*"
rdt_ar 'prefix: a .. in the directory grants nothing' 2 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_PP/../wt/.tmp-*"
rdt_ar 'prefix: a plain entry is not a prefix' 2 "rm -rf '$RDT_PP/.tmp-6527'" "$RDT_PP/.tmp-"
rdt_ar 'prefix: a VAR= prefix in the command grants nothing' 2 "$RDT_KEY='$RDT_PX' rm -rf '$RDT_PP/.tmp-6527'"
rdt_arp_pfx() { # <label> <want> <command>
  expect_both "allowed roots: PS prefix: $1" "$2" --tool PowerShell --cwd / --command "$3" -- "HOME=$RDT_AH" "$RDT_KEY=$RDT_PX"
}
rdt_arp_pfx 'Remove-Item on a matching child allowed' 0 "Remove-Item -Recurse -Force '$RDT_PP/.tmp-6527'"
rdt_arp_pfx 'Remove-Item on a sibling worktree blocks' 2 "Remove-Item -Recurse -Force '$RDT_PP/other-worktree'"
rdt_arp_pfx 'Remove-Item on a trailing-dot name blocks' 2 "Remove-Item -Recurse -Force '$RDT_PP/.tmp-6527.'"
if MSYS=winsymlinks:lnk ln -s "$RDT_AO" "$RDT_PP/.tmp-link" 2>/dev/null && [[ -L "$RDT_PP/.tmp-link" ]]; then
  rdt_ar 'prefix: a matching symlink out of the tree blocks' 2 "rm -rf '$RDT_PP/.tmp-link'" "$RDT_PX"
  rdt_ar 'prefix: a matching symlink/ out of the tree blocks' 2 "rm -rf '$RDT_PP/.tmp-link/'" "$RDT_PX"
  rdt_ar 'prefix: a path through a matching symlink blocks' 2 "rm -rf '$RDT_PP/.tmp-link/x'" "$RDT_PX"
  rdt_ar 'prefix: a matching symlink with a trailing dot blocks' 2 "rm -rf '$RDT_PP/.tmp-link.'" "$RDT_PX"
else
  rdt_skip "ln -s makes no real symlink on this host (4 cases)"
fi
# The user's own spelling on Windows: a drive-form entry, an MSYS-form operand.
if command -v cygpath >/dev/null 2>&1; then
  rdt_ar 'prefix: a drive-form entry allows an MSYS-form child' 0 "rm -rf '$RDT_PP/.tmp-6527'" "$(cygpath -m "$RDT_PP")/.tmp-*"
  rdt_ar 'prefix: a drive-form entry still blocks its directory' 2 "rm -rf '$RDT_PP'" "$(cygpath -m "$RDT_PP")/.tmp-*"
else
  rdt_skip "no cygpath on this host (2 cases)"
fi

# A segment entry (`<dir>/*/<name>`) allows a path strictly under <name> one
# directory level below <dir>, and nothing else: <name> itself, a sibling of
# it, a deeper level and a symlink stay refused, and a `*` that is not one
# whole segment, or a second `*`, grants nothing.
RDT_SR="$RDT_AB/wtroot"
RDT_SX="$RDT_SR/*/.work"
mkdir -p "$RDT_SR/wt-a/.work/tmp/sub" "$RDT_SR/wt-a/src" "$RDT_SR/wt-a/b/.work/tmp" "$RDT_SR/.work/tmp"
rdt_ar 'segment: unset key, a path under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp'"
rdt_ar 'segment: a path under .work allowed' 0 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_SX"
rdt_ar 'segment: a deeper path under .work allowed' 0 "rm -rf '$RDT_SR/wt-a/.work/tmp/sub'" "$RDT_SX"
rdt_ar 'segment: a nonexistent path under .work allowed' 0 "rm -rf '$RDT_SR/wt-new/.work/tmp'" "$RDT_SX"
rdt_ar 'segment: a glob below .work/tmp allowed' 0 "rm -rf '$RDT_SR/wt-a/.work/tmp'/*" "$RDT_SX"
rdt_ar 'segment: beside a directory entry allowed' 0 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_AR,$RDT_SX"
rdt_ar 'segment: a sibling of .work blocks' 2 "rm -rf '$RDT_SR/wt-a/src'" "$RDT_SX"
rdt_ar 'segment: .work itself blocks' 2 "rm -rf '$RDT_SR/wt-a/.work'" "$RDT_SX"
rdt_ar 'segment: .work with a trailing slash blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/'" "$RDT_SX"
rdt_ar 'segment: the glob of .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work'/*" "$RDT_SX"
rdt_ar 'segment: two levels under the directory blocks' 2 "rm -rf '$RDT_SR/wt-a/b/.work/tmp'" "$RDT_SX"
rdt_ar 'segment: zero levels under the directory blocks' 2 "rm -rf '$RDT_SR/.work/tmp'" "$RDT_SX"
rdt_ar 'segment: the one-level directory blocks' 2 "rm -rf '$RDT_SR/wt-a'" "$RDT_SX"
rdt_ar 'segment: the directory itself blocks' 2 "rm -rf '$RDT_SR'" "$RDT_SX"
rdt_ar 'segment: a .. escape to a sibling blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/../src'" "$RDT_SX"
rdt_ar 'segment: a one-level name ending in a dot blocks' 2 "rm -rf '$RDT_SR/.../.work/tmp'" "$RDT_SX"
rdt_ar 'segment: a dots-only name under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/...'" "$RDT_SX"
rdt_ar 'segment: a space-only name under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/ '" "$RDT_SX"
rdt_ar 'segment: a name ending in a dot under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp.'" "$RDT_SX"
rdt_ar 'segment: a nonexistent child/ under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/new/'" "$RDT_SX"
rdt_ar 'segment: a path outside blocks' 2 "rm -rf '$RDT_AO/x'" "$RDT_SX"
rdt_ar 'segment: a * inside a segment grants nothing' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_SR/wt-*/.work"
rdt_ar 'segment: a * inside the name grants nothing' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_SR/*/.wor*"
rdt_ar 'segment: two * segments grant nothing' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_AB/*/*/.work"
rdt_ar 'segment: a * before a two-part tail grants nothing' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_SR/*/.work/tmp"
rdt_ar 'segment: a .. in the directory grants nothing' 2 "rm -rf '$RDT_SR/wt-a/.work/tmp'" "$RDT_SR/../wtroot/*/.work"
rdt_ar 'segment: HOME as the directory grants nothing' 2 "rm -rf '$RDT_AH/x/.work/y'" "$RDT_AH/*/.work"
rdt_ar 'segment: a root-level directory grants nothing' 2 'rm -rf /rdt-x/.work/y' '/*/.work'
# A glob before the last component that matches nothing is judged by the
# literal directory in front of it, with what it deletes two levels below:
# .work itself is then enough, and the one-level directory still is not.
rdt_ar 'segment: an unmatched */x below .work allowed' 0 "rm -rf '$RDT_SR/wt-a/.work'/*/x" "$RDT_SX"
rdt_ar 'segment: an unmatched */x below the one-level directory blocks' 2 "rm -rf '$RDT_SR/wt-a'/*/x" "$RDT_SX"
if MSYS=winsymlinks:lnk ln -s "$RDT_AO" "$RDT_SR/wt-a/.work/link" 2>/dev/null && [[ -L "$RDT_SR/wt-a/.work/link" ]]; then
  rdt_ar 'segment: a symlink under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/link'" "$RDT_SX"
  rdt_ar 'segment: a path through a symlink under .work blocks' 2 "rm -rf '$RDT_SR/wt-a/.work/link/x'" "$RDT_SX"
else
  rdt_skip "ln -s makes no real symlink on this host (2 cases)"
fi

# A per-machine pair under one fake HOME: a worktree-root name prefix and a
# home .work directory. The intended targets pass; the worktree root, a sibling
# worktree, .work itself and HOME stay refused.
RDT_WH="$RDT_AB/wthome"
RDT_WK="$RDT_WH/worktrees/.tmp-*,$RDT_WH/.work"
mkdir -p "$RDT_WH/worktrees/.tmp-x" "$RDT_WH/worktrees/other" "$RDT_WH/.work/x"
rdt_ar 'pair: a .tmp- worktree child allowed' 0 "rm -rf '$RDT_WH/worktrees/.tmp-x'" "$RDT_WK" "$RDT_WH"
rdt_ar 'pair: a path under HOME .work allowed' 0 "rm -rf '$RDT_WH/.work/x'" "$RDT_WK" "$RDT_WH"
rdt_ar 'pair: the worktree root blocks' 2 "rm -rf '$RDT_WH/worktrees'" "$RDT_WK" "$RDT_WH"
rdt_ar 'pair: a sibling worktree blocks' 2 "rm -rf '$RDT_WH/worktrees/other'" "$RDT_WK" "$RDT_WH"
rdt_ar 'pair: .work itself blocks' 2 "rm -rf '$RDT_WH/.work'" "$RDT_WK" "$RDT_WH"
rdt_ar 'pair: HOME blocks' 2 "rm -rf '$RDT_WH'" "$RDT_WK" "$RDT_WH"

# The key is read from the hook's own environment only. Naming it in the
# command text, as a prefix, an env launcher or an export, grants nothing.
rdt_ar 'a VAR= prefix in the command grants nothing' 2 "$RDT_KEY='$RDT_AR' rm -rf '$RDT_AR/child'"
rdt_ar 'an env launcher in the command grants nothing' 2 "env $RDT_KEY='$RDT_AR' rm -rf '$RDT_AR/child'"
rdt_ar 'an export in the command grants nothing' 2 "export $RDT_KEY='$RDT_AR'; rm -rf '$RDT_AR/child'"
rdt_ar 'a VAR= segment in the command grants nothing' 2 "$RDT_KEY='$RDT_AR'; rm -rf '$RDT_AR/child'"
rdt_ar 'a prefix cannot widen the listed roots' 2 "$RDT_KEY='$RDT_AR,$RDT_AO' rm -rf '$RDT_AO/x'" "$RDT_AR"

# The block message names the key and says the agent cannot set it.
guard_invoke --cwd / --command "rm -rf '$RDT_AO/x'" -- "HOME=$RDT_AH" "$RDT_KEY=$RDT_AR"
assert_exit 'allowed roots: a delete outside every root blocks' 2 "$GUARD_RC"
assert_contains 'allowed roots: the message names the key' "$GUARD_ERR" 'block_root_delete_target_allowed_roots'
assert_contains 'allowed roots: the message says only the user can set it' "$GUARD_ERR" 'only the user can'
assert_contains 'allowed roots: the message forbids a retry with another tool' "$GUARD_ERR" 'do not retry the delete with another tool (find -delete, rmtree, git clean)'

# PowerShell judges the same targets through the same arm.
rdt_arp() { # <label> <want> <command> [roots]
  local -a env=("HOME=$RDT_AH")
  [[ -z "${4:-}" ]] || env+=("$RDT_KEY=$4")
  expect_both "allowed roots: PS $1" "$2" --tool PowerShell --cwd / --command "$3" -- "${env[@]}"
}
rdt_arp 'unset key: Remove-Item under the root blocks' 2 "Remove-Item -Recurse -Force '$RDT_AR/child'"
rdt_arp 'Remove-Item under the root allowed' 0 "Remove-Item -Recurse -Force '$RDT_AR/child'" "$RDT_AR"
rdt_arp 'Remove-Item -LiteralPath under the root allowed' 0 "Remove-Item -LiteralPath '$RDT_AR/child' -Recurse" "$RDT_AR"
rdt_arp 'Remove-Item outside the root blocks' 2 "Remove-Item -Recurse -Force '$RDT_AO/x'" "$RDT_AR"
rdt_arp 'Remove-Item on the root itself blocks' 2 "Remove-Item -Recurse -Force '$RDT_AR'" "$RDT_AR"
rdt_arp 'Remove-Item on a sibling by prefix blocks' 2 "Remove-Item -Recurse -Force '$RDT_AR-x/child'" "$RDT_AR"
rdt_arp 'Remove-Item on a .. escape blocks' 2 "Remove-Item -Recurse -Force '$RDT_AR/../elsewhere'" "$RDT_AR"
rdt_arp 'Remove-Item on a drive root blocks' 2 'Remove-Item -Recurse -Force C:\' "$RDT_AR"
rdt_arp 'Remove-Item on $env:USERPROFILE blocks' 2 'Remove-Item -Recurse -Force $env:USERPROFILE' "$RDT_AR"
rdt_arp 'a $env: assignment in the command grants nothing' 2 "\$env:$RDT_KEY = '$RDT_AR'; Remove-Item -Recurse '$RDT_AR/child'"

# --- 2e. Protected trees (#9751) ----------------------------------------------
# Judged ahead of every root the outside-tree arm allows: the working tree, a
# temp root, the scratchpad and a listed root alike. Every fixture outside the
# checkout sits under the suite's temp directory, where the same delete passes
# without the arm, and each refusal is paired with an allow beside it.
expect_both 'protected: rm -rf .git blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf .git'
expect_both 'protected: rm -rf ./.git/ blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf ./.git/'
expect_both 'protected: the glob straight inside .git blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf .git/*'
expect_both 'protected: a dot glob that matches .git blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf .*'
expect_both 'protected: the toplevel itself blocks' 2 "${RDT_CWD[@]}" --command "rm -rf '$RDT_TOP'"
expect_both 'protected: the toplevel as . blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf .'
expect_both 'protected: the toplevel as .. from a subdirectory blocks' 2 --cwd "$RDT_TOP/plugins" --command 'rm -rf ..'
expect_both 'protected: PS Remove-Item on .git blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'Remove-Item -Recurse -Force .git'
expect_both 'protected: a subdirectory of the toplevel allowed' 0 "${RDT_CWD[@]}" \
  --command 'rm -rf plugins/rdt-nonexistent/build'
expect_both 'protected: a path named under .git allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf .git/rdt-nonexistent-x'
expect_both 'protected: the toplevel glob leaves .git, allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf *'
# A glob matches dot names on PowerShell, and in bash once dotglob is on.
expect_both 'protected: PS Remove-Item * from the toplevel blocks (its * matches .git)' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'Remove-Item -Recurse -Force *'
expect_both 'protected: dotglob then rm -rf * blocks' 2 "${RDT_CWD[@]}" --command 'shopt -s dotglob; rm -rf *'
expect_both 'protected: GLOBIGNORE then rm -rf * blocks' 2 "${RDT_CWD[@]}" --command 'GLOBIGNORE=x; rm -rf *'
# A case-insensitive filesystem removes .git through .GIT.
expect_both 'protected: rm -rf .GIT blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf .GIT'
# Win32 trims a trailing dot or space, so `.git.` names `.git` there.
case "${OSTYPE:-}" in
msys* | cygwin* | win32)
  expect_both 'protected: PS Remove-Item on .git. blocks' 2 \
    --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse -Force '.git.'"
  ;;
*) rdt_skip "a trailing-dot name is trimmed only on Windows (1 case)" ;;
esac

# A directory holding a .git is refused under temp too; a path inside it is
# not, and a symlink to it is unlinked, not followed.
mkdir -p "$TEST_TMPDIR/rdt-clone/.git" "$TEST_TMPDIR/rdt-clone/build"
expect_both 'protected: a throwaway clone under temp blocks' 2 "${RDT_CWD[@]}" \
  --command "rm -rf '$TEST_TMPDIR/rdt-clone'"
expect_both 'protected: a path inside that clone allowed' 0 "${RDT_CWD[@]}" \
  --command "rm -rf '$TEST_TMPDIR/rdt-clone/build'"
if MSYS=winsymlinks:lnk ln -s "$TEST_TMPDIR/rdt-clone" "$TEST_TMPDIR/rdt-clone-link" 2>/dev/null &&
  [[ -L "$TEST_TMPDIR/rdt-clone-link" ]]; then
  expect_both 'protected: a link to the clone is unlinked, allowed' 0 "${RDT_CWD[@]}" \
    --command "rm -rf '$TEST_TMPDIR/rdt-clone-link'"
  expect_both 'protected: link/ to the clone blocks' 2 "${RDT_CWD[@]}" \
    --command "rm -rf '$TEST_TMPDIR/rdt-clone-link/'"
else
  rdt_skip "ln -s makes no real symlink on this host (2 cases)"
fi

# Registered worktrees, from a registry built by hand the way git writes it,
# with a stub git that answers the given worktree as the toplevel. The guard
# reads <common dir>/worktrees/*/gitdir itself, so a root whose .git file is
# gone, one recorded by a relative path, a dot-named one and a directory
# holding one are refused, not only a root that holds its .git file.
RDT_WF="$TEST_TMPDIR/rdt-wt"
RDT_WR="$RDT_WF/main/.git/worktrees"
mkdir -p "$RDT_WR/wt1" "$RDT_WR/nogit" "$RDT_WR/wt2" "$RDT_WR/.tmp-7" "$RDT_WR/wt3" \
  "$RDT_WF/wt1/build" "$RDT_WF/wt-nogit" "$RDT_WF/rel/wt2" "$RDT_WF/.tmp-7" "$RDT_WF/holder/wt3" "$RDT_WF/other"
printf '%s\n' "$RDT_WF/wt1/.git" >"$RDT_WR/wt1/gitdir"
printf '../..\n' >"$RDT_WR/wt1/commondir"
printf 'gitdir: %s\n' "$RDT_WR/wt1" >"$RDT_WF/wt1/.git"
printf '%s\n' "$RDT_WF/wt-nogit/.git" >"$RDT_WR/nogit/gitdir"
printf '../../../../rel/wt2/.git\n' >"$RDT_WR/wt2/gitdir"
printf '%s\n' "$RDT_WF/.tmp-7/.git" >"$RDT_WR/.tmp-7/gitdir"
printf '%s\n' "$RDT_WF/holder/wt3/.git" >"$RDT_WR/wt3/gitdir"
mkdir -p "$TEST_TMPDIR/bin-git-top"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$RDT_STUB_TOP"\n' >"$TEST_TMPDIR/bin-git-top/git"
chmod +x "$TEST_TMPDIR/bin-git-top/git"
rdt_wt() { # <label> <want> <command> [toplevel]: run from that worktree, which the stub answers
  local top="${4:-$RDT_WF/main}"
  expect_both "protected: worktrees: $1" "$2" --cwd "$top" --command "$3" \
    -- "PATH=$TEST_TMPDIR/bin-git-top:$PATH" "RDT_STUB_TOP=$top"
}
rdt_wt 'a linked worktree root blocks' 2 "rm -rf '$RDT_WF/wt1'"
rdt_wt 'a registered root with no .git file blocks' 2 "rm -rf '$RDT_WF/wt-nogit'"
rdt_wt 'a root recorded by a relative path blocks' 2 "rm -rf '$RDT_WF/rel/wt2'"
rdt_wt 'a dot-named worktree blocks' 2 "rm -rf '$RDT_WF/.tmp-7'"
rdt_wt 'a directory holding a worktree root blocks' 2 "rm -rf '$RDT_WF/holder'"
rdt_wt 'a glob whose matches hold worktree roots blocks' 2 "rm -rf '$RDT_WF'/*"
rdt_wt 'the main worktree, the toplevel, blocks' 2 "rm -rf '$RDT_WF/main'"
rdt_wt 'a path under a worktree allowed' 0 "rm -rf '$RDT_WF/wt1/build'"
rdt_wt 'an unregistered sibling under temp allowed' 0 "rm -rf '$RDT_WF/other'"
rdt_wt 'from a linked worktree: the main root blocks' 2 "rm -rf '$RDT_WF/main'" "$RDT_WF/wt1"
rdt_wt 'from a linked worktree: a root with no .git file blocks' 2 "rm -rf '$RDT_WF/wt-nogit'" "$RDT_WF/wt1"
rdt_wt 'from a linked worktree: its own build allowed' 0 'rm -rf build' "$RDT_WF/wt1"

# Claude Code's temp tree, <base>/<project>/<session>/scratchpad. The payload
# scratchpad names the base: another session's scratchpad and every level that
# holds one are refused, and this session's scratchpad keeps its rules.
RDT_CB="$TEST_TMPDIR/claude-rdt"
RDT_OWN="$RDT_CB/-proj/sess-a/scratchpad"
RDT_OTH="$RDT_CB/-proj/sess-b/scratchpad"
mkdir -p "$RDT_OWN/x" "$RDT_OTH/x" "$RDT_CB/-proj/sess-b/tasks"
rdt_sp() { # <label> <want> <command>: from the checkout, with this session's scratchpad
  expect_both "protected: scratchpads: $1" "$2" --payload "$(rdt_pl "$3" "$RDT_TOP" "$RDT_OWN")"
}
rdt_sp "another session's scratchpad blocks" 2 "rm -rf '$RDT_OTH'"
rdt_sp "a path in another session's scratchpad blocks" 2 "rm -rf '$RDT_OTH/x'"
rdt_sp "another session's directory blocks" 2 "rm -rf '$RDT_CB/-proj/sess-b'"
rdt_sp "this session's directory blocks" 2 "rm -rf '$RDT_CB/-proj/sess-a'"
rdt_sp 'a project directory blocks' 2 "rm -rf '$RDT_CB/-proj'"
rdt_sp 'the base blocks' 2 "rm -rf '$RDT_CB'"
rdt_sp 'a glob over the sessions blocks' 2 "rm -rf '$RDT_CB/-proj/'*"
rdt_sp "a path in this session's scratchpad allowed" 0 "rm -rf '$RDT_OWN/x'"
rdt_sp "this session's scratchpad itself still blocks" 2 "rm -rf '$RDT_OWN'"
rdt_sp "another session's directory that is not its scratchpad allowed" 0 "rm -rf '$RDT_CB/-proj/sess-b/tasks'"
expect_both 'protected: scratchpads: with no payload scratchpad, that base is a plain temp path' 0 "${RDT_CWD[@]}" \
  --command "rm -rf '$RDT_OTH'"
# TMPDIR pointed at the base: the caller's own temp files there pass, and
# another session's scratchpad is still refused.
expect_both 'protected: scratchpads: TMPDIR at the base, a temp file there allowed' 0 \
  --payload "$(rdt_pl "rm -rf '$RDT_CB/rdt-own-tmp'" "$RDT_TOP" "$RDT_OWN")" -- "TMPDIR=$RDT_CB"
expect_both "protected: scratchpads: TMPDIR at the base, another session's scratchpad blocks" 2 \
  --payload "$(rdt_pl "rm -rf '$RDT_OTH'" "$RDT_TOP" "$RDT_OWN")" -- "TMPDIR=$RDT_CB"
# Without a payload scratchpad the base is <temp root>/claude-<uid>
# (<temp root>/claude on Windows); TMPDIR names a fixture temp root here.
RDT_TR="$TEST_TMPDIR/rdt-tmproot"
rdt_cn="claude-$UID"
case "${OSTYPE:-}" in
msys* | cygwin* | win32) rdt_cn=claude ;;
*) ;;
esac
mkdir -p "$RDT_TR/$rdt_cn/-p/s/scratchpad" "$RDT_TR/other"
expect_both "protected: scratchpads: one under <temp root>/$rdt_cn blocks" 2 "${RDT_CWD[@]}" \
  --command "rm -rf '$RDT_TR/$rdt_cn/-p/s/scratchpad'" -- "TMPDIR=$RDT_TR"
expect_both 'protected: scratchpads: a sibling under that temp root allowed' 0 "${RDT_CWD[@]}" \
  --command "rm -rf '$RDT_TR/other'" -- "TMPDIR=$RDT_TR"

# ~/.claude, from HOME, here a fake one under temp.
RDT_HF="$TEST_TMPDIR/rdt-home"
mkdir -p "$RDT_HF/.claude/projects" "$RDT_HF/other"
rdt_hc() { # <label> <want> <command>
  expect_both "protected: ~/.claude: $1" "$2" "${RDT_CWD[@]}" --command "$3" -- "HOME=$RDT_HF"
}
rdt_hc 'the directory blocks' 2 "rm -rf '$RDT_HF/.claude'"
rdt_hc 'a path under it blocks' 2 "rm -rf '$RDT_HF/.claude/projects'"
rdt_hc 'the ~ spelling blocks' 2 'rm -rf ~/.claude/projects'
rdt_hc 'a dot glob over HOME blocks' 2 "rm -rf '$RDT_HF/'.*"
rdt_hc 'a sibling under HOME allowed' 0 "rm -rf '$RDT_HF/other'"
rdt_hc 'a plain glob over HOME skips the dot name, allowed' 0 "rm -rf '$RDT_HF/'*"

# block_root_delete_target_protected_trees, read from the hook's environment.
RDT_PK=CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_PROTECTED_TREES
RDT_KP="$TEST_TMPDIR/rdt-keep"
mkdir -p "$RDT_KP/data/x" "$RDT_KP/scratch"
rdt_pt() { # <label> <want> <command> [trees]
  local -a env=()
  [[ -z "${4:-}" ]] || env+=("$RDT_PK=$4")
  expect_both "protected: listed trees: $1" "$2" "${RDT_CWD[@]}" --command "$3" -- ${env[@]+"${env[@]}"}
}
rdt_pt 'unset key: the tree under temp allowed' 0 "rm -rf '$RDT_KP/data'"
rdt_pt 'a listed tree blocks' 2 "rm -rf '$RDT_KP/data'" "$RDT_KP/data"
rdt_pt 'a path under a listed tree blocks' 2 "rm -rf '$RDT_KP/data/x'" "$RDT_KP/data"
rdt_pt 'a directory holding a listed tree blocks' 2 "rm -rf '$RDT_KP'" "$RDT_KP/data"
rdt_pt 'a glob whose matches reach a listed tree blocks' 2 "rm -rf '$RDT_KP/'*" "$RDT_KP/data"
rdt_pt 'a sibling of a listed tree allowed' 0 "rm -rf '$RDT_KP/scratch'" "$RDT_KP/data"
rdt_pt 'the second of two trimmed entries blocks' 2 "rm -rf '$RDT_KP/scratch'" " $RDT_KP/data , $RDT_KP/scratch "
rdt_pt 'a listed tree inside the working tree blocks' 2 'rm -rf .work/rdt-keep-x/y' "$RDT_TOP/.work/rdt-keep-x"
rdt_pt 'a relative entry protects nothing' 0 "rm -rf '$RDT_KP/data'" 'rel/data'
rdt_pt 'a .. entry protects nothing' 0 "rm -rf '$RDT_KP/data'" "$RDT_KP/scratch/../data"
rdt_pt 'a glob entry protects nothing' 0 "rm -rf '$RDT_KP/data'" "$RDT_KP/da*"
rdt_pt 'a bad entry beside a good one is skipped' 2 "rm -rf '$RDT_KP/data'" "rel/x,$RDT_KP/data"
rdt_pt "the root '/' protects nothing" 0 'rm -rf build' /
rdt_pt 'emptying the key in the command lifts nothing' 2 "$RDT_PK= rm -rf '$RDT_KP/data'" "$RDT_KP/data"
# Under an allowed root too: the same delete passes in section 2d.
expect_both 'protected: listed trees: a listed tree under an allowed root blocks' 2 --cwd / \
  --command "rm -rf '$RDT_AR/child'" -- "HOME=$RDT_AH" "$RDT_KEY=$RDT_AR" "$RDT_PK=$RDT_AR/child"

# The refusal says what the tree is, carries a Fix line, and asks when attended.
guard_invoke "${RDT_CWD[@]}" --command 'rm -rf .git'
assert_exit 'protected: a .git delete exits 2' 2 "$GUARD_RC"
assert_contains 'protected: the message names what it removes' "$GUARD_ERR" 'a .git.'
assert_contains 'protected: the message names the class' "$GUARD_ERR" 'A protected tree is refused'
assert_contains 'protected: the message carries a Fix line' "$GUARD_ERR" 'Fix:'
guard_invoke "${RDT_CWD[@]}" --command "rm -rf '$RDT_KP/data'" -- "$RDT_PK=$RDT_KP/data"
assert_contains 'protected: a listed tree names the key' "$GUARD_ERR" 'a tree in block_root_delete_target_protected_trees'
expect 'protected: attended, a .git delete asks' 0 "${RDT_CWD[@]}" --command 'rm -rf .git' \
  -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_eq 'protected: attended, the decision is ask' ask \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"

# --- 2f. find deletes (#9752) -------------------------------------------------
# A find whose expression deletes (-delete, or an -exec, -execdir, -ok or
# -okdir whose command word is rm, rmdir or unlink) has each start point judged
# as an operand of a recursive rm. Every form runs against a root, HOME, a path
# outside the allowed roots and a path strictly inside the tree.
RDT_FIND_FORMS=(
  'find TGT -delete'
  "find -L TGT -name '*.o' -type f -delete"
  'find TGT -type d -name build -exec rm -rf {} +'
  'find TGT -execdir rm -f {} \;'
  "find TGT -ok /bin/rm {} ';'"
  'find TGT -okdir unlink {} \;'
  'find TGT -depth -type d -empty -exec rmdir {} +'
)
rdt_find() { # <label> <want> <start point> [guard_invoke option ...]: every form
  local label="$1" want="$2" t="$3" f c
  shift 3
  for f in "${RDT_FIND_FORMS[@]}"; do
    c="${f//TGT/$t}"
    expect_both "find: $label: $c" "$want" --command "$c" "$@"
  done
}
rdt_find 'a root blocks' 2 /
rdt_find 'HOME blocks' 2 '$HOME'
rdt_find 'outside the tree blocks' 2 /opt/nonexistent-rdt/x "${RDT_CWD[@]}"
rdt_find 'inside the tree allowed' 0 plugins/rdt-nonexistent "${RDT_CWD[@]}"
expect_both 'find: find ~ -delete blocks' 2 --command 'find ~ -delete'
expect_both 'find: a path under HOME blocks with a cwd' 2 "${RDT_CWD[@]}" --command 'find ~/Documents/x -delete'
expect_both 'find: a path under /tmp allowed' 0 "${RDT_CWD[@]}" --command 'find /tmp/rdt-x -delete'
expect_both 'find: /tmp itself blocks' 2 "${RDT_CWD[@]}" --command 'find /tmp -name rdt-x -delete'
expect_both 'find: a path under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "find '$RDT_SPT/x' -exec rm -rf {} +" "$RDT_TOP" "$RDT_SPT")"
expect_both 'find: the scratchpad itself blocks' 2 \
  --payload "$(rdt_pl "find '$RDT_SPT' -name x -delete" "$RDT_TOP" "$RDT_SPT")"
rdt_ar 'find: unset key, a start point under the root blocks' 2 "find '$RDT_AR/child' -delete"
rdt_ar 'find: a start point under the root allowed' 0 "find '$RDT_AR/child' -delete" "$RDT_AR"
rdt_ar 'find: -exec rm under the root allowed' 0 "find '$RDT_AR/child' -name x -exec rm -rf {} +" "$RDT_AR"
rdt_ar 'find: the root itself blocks' 2 "find '$RDT_AR' -name x -delete" "$RDT_AR"
rdt_ar 'find: a start point outside the root blocks' 2 "find '$RDT_AO/x' -delete" "$RDT_AR"

# find descends into .git, so a find delete started at the toplevel is refused
# as a directory holding a .git whatever its filters; one started below passes.
expect_both 'find: . from the toplevel blocks' 2 "${RDT_CWD[@]}" --command "find . -name '*.pyc' -delete"
expect_both 'find: no start point from the toplevel is . and blocks' 2 "${RDT_CWD[@]}" \
  --command "find -name '*.pyc' -delete"
expect_both 'find: no start point from a subdirectory allowed' 0 --cwd "$RDT_TOP/plugins" \
  --command "find -name '*.pyc' -delete"
expect_both 'find: a .git start point blocks' 2 "${RDT_CWD[@]}" --command 'find .git -name x -exec rm {} +'
# GNU reads a first primary spelled -f... as the expression, so `.` is judged
# though BSD reads it as -f and a start point.
expect_both 'find: -fstype first still judges . from the toplevel' 2 "${RDT_CWD[@]}" \
  --command 'find -fstype ext4 -delete'
# With -files0-from GNU reads the start points from a file (a declared gap),
# so its reading adds no `.`; the BSD reading's names lie inside the tree.
expect_both 'find: -files0-from judges no . from the toplevel' 0 "${RDT_CWD[@]}" \
  --command 'find -files0-from list -delete'
# Under -H, -L or -follow find follows a start point that is a symlink, so it
# is judged by where it points; without them the link itself is the target.
if MSYS=winsymlinks:lnk ln -s /opt/rdt-link-target "$TEST_TMPDIR/rdt-find-link" 2>/dev/null &&
  [[ -L "$TEST_TMPDIR/rdt-find-link" ]]; then
  expect_both 'find: a link start point under temp, not followed, allowed' 0 "${RDT_CWD[@]}" \
    --command "find '$TEST_TMPDIR/rdt-find-link' -delete"
  expect_both 'find: -H follows a link start point outside, blocks' 2 "${RDT_CWD[@]}" \
    --command "find -H '$TEST_TMPDIR/rdt-find-link' -exec rm -rf {} +"
  expect_both 'find: -L follows it, blocks' 2 "${RDT_CWD[@]}" \
    --command "find -L '$TEST_TMPDIR/rdt-find-link' -delete"
  expect_both 'find: -follow follows it, blocks' 2 "${RDT_CWD[@]}" \
    --command "find '$TEST_TMPDIR/rdt-find-link' -follow -delete"
  # From a subdirectory, so the `.` the GNU reading adds is allowed.
  expect_both 'find: a BSD -xL cluster follows it, blocks' 2 --cwd "$RDT_TOP/plugins" \
    --command "find -xL '$TEST_TMPDIR/rdt-find-link' -delete"
  expect_both 'find: a BSD -x cluster does not follow it, allowed' 0 --cwd "$RDT_TOP/plugins" \
    --command "find -x '$TEST_TMPDIR/rdt-find-link' -delete"
  rm -f "$TEST_TMPDIR/rdt-find-link"
else
  rdt_skip "ln -s makes no real symlink on this host (6 cases)"
fi

# Leading options of either reading, a later start point, an action before
# -delete, and a find reached through a launcher, a child shell or a
# substitution.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "find: $rdt_cmd blocks" 2 --command "$rdt_cmd"
done <<'EOF'
find -H -P / -delete
find -D tree / -delete
find -O3 / -delete
find -- / -delete
find -x / -delete
find -dx -f / -name x -delete
find -sf/ -delete
find build / -delete
find / -exec echo {} \; -delete
/usr/bin/find / -delete
sudo find / -delete
bash -c 'find / -exec rm -rf {} +'
echo "$(find / -delete)"
EOF

# A find that does not delete, a deleter's name that is not an action's command
# word, a -delete inside an action's command, and the mechanism as quoted prose.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "find: $rdt_cmd allowed" 0 --command "$rdt_cmd"
  expect_both "find: $rdt_cmd allowed with a cwd" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
find / -name rm -type f
find / -exec grep -l rm {} +
find / -exec echo -delete {} +
git commit -m "find / -delete"
git commit -m "find / -exec rm -rf {} +"
echo 'find ~ -okdir unlink {} \;'
EOF

guard_invoke "${RDT_CWD[@]}" --command 'find /opt/nonexistent-rdt/x -delete'
assert_exit 'find: outside the tree exits 2' 2 "$GUARD_RC"
assert_contains 'find: the refusal names the start point' "$GUARD_ERR" "the operand '/opt/nonexistent-rdt/x'"
guard_invoke "${RDT_CWD[@]}" --command "find . -name '*.pyc' -delete"
assert_contains 'find: the toplevel refusal names the .git it holds' "$GUARD_ERR" 'a directory holding a .git'

# --- 2g. pipeline-fed deletes (#9754) -----------------------------------------
# xargs or parallel running a recursive delete takes its targets from the items
# it reads. A confined listing (a find without -printf or -exec, git ls-files),
# through line filters at most, has its targets judged as a recursive rm's; any
# other source is refused. Every form runs against a root, HOME, a path outside
# the allowed roots and a path strictly inside the tree.
RDT_PIPE_FORMS=(
  'find TGT -type f | xargs rm -rf'
  'find TGT -print0 | xargs -0 rm -rf --'
  "find TGT -name '*.o' | grep -v keep | sort -u | xargs -n 1 rm -rf"
  'find TGT -type d | head -n 5 | xargs -I{} rm -rf {}'
  'find TGT | xargs sudo rm -rf'
  'find TGT | parallel rm -rf'
  "find TGT | parallel -j 4 'rm -rf {}'"
)
rdt_pipe() { # <label> <want> <start point> [guard_invoke option ...]: every form
  local label="$1" want="$2" t="$3" f c
  shift 3
  for f in "${RDT_PIPE_FORMS[@]}"; do
    c="${f//TGT/$t}"
    expect_both "pipe: $label: $c" "$want" --command "$c" "$@"
  done
}
rdt_pipe 'a root blocks' 2 /
rdt_pipe 'HOME blocks' 2 '$HOME'
rdt_pipe 'outside the tree blocks' 2 /opt/nonexistent-rdt/x "${RDT_CWD[@]}"
rdt_pipe 'inside the tree allowed' 0 plugins/rdt-nonexistent "${RDT_CWD[@]}"
expect_both 'pipe: find ~ blocks' 2 --command 'find ~ -type f | xargs rm -rf'
expect_both 'pipe: a find under /tmp allowed' 0 "${RDT_CWD[@]}" --command 'find /tmp/rdt-x -type f | xargs rm -rf'
expect_both 'pipe: a find under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "find '$RDT_SPT/x' -type f | xargs rm -rf" "$RDT_TOP" "$RDT_SPT")"
expect_both 'pipe: a find of the scratchpad itself blocks' 2 \
  --payload "$(rdt_pl "find '$RDT_SPT' -name x | xargs rm -rf" "$RDT_TOP" "$RDT_SPT")"
rdt_ar 'pipe: unset key, a find under the root blocks' 2 "find '$RDT_AR/child' -type f | xargs rm -rf"
rdt_ar 'pipe: a find under the root allowed' 0 "find '$RDT_AR/child' -type f | xargs rm -rf" "$RDT_AR"
rdt_ar 'pipe: a find of the root itself blocks' 2 "find '$RDT_AR' -name x | xargs rm -rf" "$RDT_AR"
expect_both 'pipe: a find from the toplevel blocks' 2 "${RDT_CWD[@]}" --command "find . -name '*.pyc' | xargs rm -rf"
expect_both 'pipe: a find run from another directory is judged from there' 2 "${RDT_CWD[@]}" \
  --command 'find build -type f | env -C /opt xargs rm -rf'
# git ls-files lists names strictly under the directory it runs from.
expect_both 'pipe: git ls-files inside the tree allowed' 0 "${RDT_CWD[@]}" --command 'git ls-files -z | xargs -0 rm -rf'
expect_both 'pipe: git ls-files from a subdirectory allowed' 0 --cwd "$RDT_TOP/plugins" \
  --command 'git ls-files --others --exclude-standard | grep -v keep | xargs rm -rf'
expect_both 'pipe: git ls-files with no tree blocks' 2 --cwd / --command 'git ls-files | xargs rm -rf'
expect_both 'pipe: git ls-files after a cd outside blocks' 2 "${RDT_CWD[@]}" \
  --command 'cd /opt && git ls-files | xargs rm -rf'
# parallel's ::: items are its targets.
expect_both 'pipe: parallel items inside the tree allowed' 0 "${RDT_CWD[@]}" \
  --command 'parallel rm -rf {} ::: plugins/rdt-nonexistent build/rdt-x'
expect_both 'pipe: parallel items outside the tree block' 2 "${RDT_CWD[@]}" \
  --command 'parallel rm -rf {} ::: build/rdt-x /opt/nonexistent-rdt/x'
# Items on the line replace stdin; a file source beside them does not.
expect_both 'pipe: parallel items with an unread pipe allowed' 0 "${RDT_CWD[@]}" \
  --command 'cat list | parallel rm -rf {} ::: build/rdt-x'
expect_both 'pipe: parallel items beside a file source block' 2 "${RDT_CWD[@]}" \
  --command 'parallel rm -rf {} ::: build/rdt-x :::: list'

# A listing that is not confined, a file or a stdin no listing feeds, a filter
# that can rewrite a line, and a listing the tokenizer splits out of order.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "pipe: $rdt_cmd blocks" 2 --command "$rdt_cmd"
  expect_both "pipe: $rdt_cmd blocks with a cwd" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
cat list | xargs rm -rf
cat list | xargs -0 rm -r
xargs rm -rf
xargs rm -rf < list
find build | xargs rm -rf < list
xargs -a list rm -rf
xargs --arg-file=list rm -rf
xargs -0a list rm -rf
grep -l x src | xargs rm -rf
find build | sed 's,^,/,' | xargs rm -rf
find build | grep -o x | xargs rm -rf
find build | cut -c1 | xargs rm -rf
find build -printf '/\n' | xargs rm -rf
find build -fprintf /dev/stdout '/\n' | xargs rm -rf
find build -ls | xargs rm -rf
find build -exec echo / \; | xargs rm -rf
git ls-files --format=/ | xargs rm -rf
git ls-files --form=/ | xargs rm -rf
git -C /opt ls-files | xargs rm -rf
sudo find build | xargs rm -rf
find build; cat list | xargs rm -rf
{ cat list; find build; } | xargs rm -rf
cat list $(find build) | xargs rm -rf
find build | (cat list; cat) | xargs rm -rf
find build | xargs -I{} sh -c 'rm -rf {}' < list
cat list | xargs -I{} sh -c 'rm -rf {}'
cat list | sudo xargs rm -rf
cat list | bash -c 'xargs rm -rf'
cat list | bash -c 'find build; xargs rm -rf'
echo "$(cat list | xargs rm -rf)"
find build | xargs rm -rf /
cat list | parallel rm -rf
parallel rm -rf
parallel rm -rf :::: list
parallel -a list rm -rf
find build | parallel --arg-sep ,, rm -rf ,, x
parallel rm -rf ::: /
parallel 'rm -rf {}' ::: /
parallel -j 2 rm -rf ::: /
parallel ::: 'rm -rf /'
parallel -j 2 ::: 'rm -rf /'
EOF

# A command that does not delete recursively, and the mechanism as quoted prose.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "pipe: $rdt_cmd allowed" 0 --command "$rdt_cmd"
  expect_both "pipe: $rdt_cmd allowed with a cwd" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
git commit -m "cat list | xargs rm -rf"
git commit -m "find / | xargs rm -rf"
echo 'parallel rm -rf ::: /'
cat list | xargs grep -l rm
cat list | xargs rm -f
find / -name x | xargs echo rm -rf /
parallel echo ::: rm-rf-nothing
EOF

guard_invoke --command 'cat list | xargs rm -rf'
assert_exit 'pipe: an unconfined listing exits 2' 2 "$GUARD_RC"
assert_contains 'pipe: the refusal names the cause' "$GUARD_ERR" 'no confined listing produced'
guard_invoke "${RDT_CWD[@]}" --command 'find /opt/nonexistent-rdt/x -type f | xargs rm -rf'
assert_contains 'pipe: the refusal names the start point' "$GUARD_ERR" "the operand '/opt/nonexistent-rdt/x'"
guard_invoke --cwd / --command 'git ls-files | xargs rm -rf'
assert_contains 'pipe: the refusal names the git ls-files entry' "$GUARD_ERR" "the operand '(a file git ls-files lists)'"
expect 'pipe: attended, an unconfined listing asks' 0 --command 'cat list | xargs rm -rf' \
  -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_eq 'pipe: attended, the decision is ask' ask \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"

# --- 2h. rsync deletes (#9756) -------------------------------------------------
# A --del, --delete or --delete-<mode> option deletes in the destination, the
# last operand; --remove-source-files deletes from the sources before it. Each
# is judged as a recursive rm operand. Every form runs against a root, HOME, a
# path outside the allowed roots and a path strictly inside the tree.
RDT_RSYNC_FORMS=(
  'rsync -a --delete src/ TGT'
  'rsync -a --del src/ TGT'
  'rsync -av --delete-after src/ TGT'
  'rsync -a --delete-excluded --exclude=.cache src/ TGT'
  'rsync -ae ssh --delete-before src/ TGT'
  'rsync -a src/ TGT --delete'
  'sudo rsync -a --delete src/ TGT'
  'rsync -a --remove-source-files TGT build/rdt-out'
  'rsync -a --remove-source-files build/rdt-x TGT/ build/rdt-out'
)
rdt_rsync() { # <label> <want> <target> [guard_invoke option ...]: every form
  local label="$1" want="$2" t="$3" f c
  shift 3
  for f in "${RDT_RSYNC_FORMS[@]}"; do
    c="${f//TGT/$t}"
    expect_both "rsync: $label: $c" "$want" --command "$c" "$@"
  done
}
rdt_rsync 'a root blocks' 2 /
rdt_rsync 'HOME blocks' 2 '$HOME'
rdt_rsync 'outside the tree blocks' 2 /opt/nonexistent-rdt/x "${RDT_CWD[@]}"
rdt_rsync 'inside the tree allowed' 0 plugins/rdt-nonexistent "${RDT_CWD[@]}"
expect_both 'rsync: a delete into ~ blocks' 2 --command 'rsync -a --delete src/ ~'
expect_both 'rsync: a drive root is judged, not read as a host' 2 --command 'rsync -a --delete src/ C:/'
expect_both 'rsync: a delete under /tmp allowed' 0 "${RDT_CWD[@]}" --command 'rsync -a --delete src/ /tmp/rdt-x'
expect_both 'rsync: a delete under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "rsync -a --delete src/ '$RDT_SPT/x'" "$RDT_TOP" "$RDT_SPT")"
expect_both 'rsync: a delete into the scratchpad itself blocks' 2 \
  --payload "$(rdt_pl "rsync -a --delete src/ '$RDT_SPT'" "$RDT_TOP" "$RDT_SPT")"
rdt_ar 'rsync: unset key, a delete under the root blocks' 2 "rsync -a --delete src/ '$RDT_AR/child'"
rdt_ar 'rsync: a delete under the root allowed' 0 "rsync -a --delete src/ '$RDT_AR/child'" "$RDT_AR"
rdt_ar 'rsync: a delete into the root itself blocks' 2 "rsync -a --delete src/ '$RDT_AR'" "$RDT_AR"
rdt_ar 'rsync: moved sources under the root allowed' 0 "rsync -a --remove-source-files '$RDT_AR/child' build/rdt-out" "$RDT_AR"
expect_both 'rsync: a delete into the toplevel blocks' 2 "${RDT_CWD[@]}" --command 'rsync -a --delete src/ .'
expect_both 'rsync: a cd outside before the delete blocks' 2 "${RDT_CWD[@]}" \
  --command 'cd /opt && rsync -a --delete src/ x'
# The items xargs appends are the rsync's operands.
expect_both 'rsync: xargs fed by a confined listing allowed' 0 "${RDT_CWD[@]}" \
  --command 'find build -type d | xargs rsync -a --delete src/'
expect_both 'rsync: xargs fed by an unconfined listing blocks' 2 "${RDT_CWD[@]}" \
  --command 'cat list | xargs rsync -a --delete src/'

# An rsync that deletes nothing, a remote target, an option's argument, and
# the mechanism as quoted prose.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "rsync: $rdt_cmd allowed" 0 --command "$rdt_cmd"
  expect_both "rsync: $rdt_cmd allowed with a cwd" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
rsync -a src/ /opt/nonexistent-rdt/x
rsync -a --delay-updates src/ /
rsync --delete /
rsync -a --remove-source-files --exclude /opt build/rdt-x build/rdt-out
rsync -a -T /opt --remove-source-files build/rdt-x build/rdt-out
rsync -ae /opt/ssh --remove-source-files build/rdt-x build/rdt-out
git commit -m "rsync -a --delete src/ /"
echo 'rsync --remove-source-files / build/rdt-out'
EOF

# A remote operand is left alone. Run from / (no tree), where the same word
# read as a local relative path would be refused.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "rsync: remote, $rdt_cmd allowed" 0 --cwd / --command "$rdt_cmd"
done <<'EOF'
rsync -a --delete src/ host:/
rsync -a --delete src/ user@host:dir
rsync -a --delete src/ rsync://host/module/
rsync -a --remove-source-files host:/ /tmp/rdt-out
EOF

# A brace, a glob or an expansion that can change which word is last or read
# as a host.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "rsync: $rdt_cmd blocks" 2 --command "$rdt_cmd"
done <<'EOF'
rsync -a --delete {src/,/}
rsync -a --delete src/ / {,}
rsync -a --delete src/ "${HOME:-x}"
rsync -a --delete src/ {h:,/}
rsync -a --delete src/ ~ --time-limit 60
rsync -a --delete src/ ~ --zl 3
rsync -a --remove-sent-files / /tmp/rdt-out
echo "$(rsync -a --del src/ /)"
parallel ::: 'rsync -a --del src/ /'
EOF

guard_invoke "${RDT_CWD[@]}" --command 'rsync -a --delete src/ /opt/nonexistent-rdt/x'
assert_exit 'rsync: an outside destination exits 2' 2 "$GUARD_RC"
assert_contains 'rsync: the refusal names the destination' "$GUARD_ERR" "the operand '/opt/nonexistent-rdt/x'"

# --- 2i. robocopy deletes (#9758) ----------------------------------------------
# /MIR or /PURGE deletes in the destination, the second operand; /MOVE or /MOV
# deletes from the source, the first. Each is judged as a recursive rm operand,
# from the Bash and the PowerShell tool. Every form runs against a root, HOME,
# a path outside the allowed roots and a path strictly inside the tree.
RDT_ROBOCOPY_FORMS=(
  'robocopy src TGT /MIR'
  'robocopy src TGT /mir /R:2 /W:5'
  'robocopy src TGT /E /PURGE'
  'robocopy src TGT //MIR'
  'robocopy /MIR src TGT'
  'robocopy src TGT a.txt /XF a.tmp b.tmp /MIR'
  'robocopy.exe src TGT /MIR /LOG:build/rdt.log'
  'robocopy TGT build/rdt-out /MOVE'
  'robocopy TGT build/rdt-out /E /MOV'
)
rdt_robocopy() { # <label> <want> <target> [guard_invoke option ...]: every form, both tools
  local label="$1" want="$2" t="$3" f c
  shift 3
  for f in "${RDT_ROBOCOPY_FORMS[@]}"; do
    c="${f//TGT/$t}"
    expect_both "robocopy: $label: $c" "$want" --command "$c" "$@"
    expect_both "robocopy: PS $label: $c" "$want" --tool PowerShell --command "$c" "$@"
  done
}
rdt_robocopy 'a root blocks' 2 /
rdt_robocopy 'HOME blocks' 2 '$HOME'
rdt_robocopy 'outside the tree blocks' 2 /opt/nonexistent-rdt/x "${RDT_CWD[@]}"
rdt_robocopy 'inside the tree allowed' 0 plugins/rdt-nonexistent "${RDT_CWD[@]}"
expect_both 'robocopy: PS a mirror into a drive root blocks' 2 \
  --tool PowerShell --command 'robocopy src C:\ /MIR'
expect_both 'robocopy: PS a mirror outside the tree blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'robocopy src D:\rdt-x\y /PURGE'
expect_both 'robocopy: PS cmd /c robocopy into a drive root blocks' 2 \
  --tool PowerShell --command 'cmd /c robocopy src C:\ /MIR'
expect_both 'robocopy: PS cmd /c robocopy inside the tree allowed' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'cmd /c "robocopy src build\rdt-out /MIR"'
expect_both 'robocopy: a mirror under /tmp allowed' 0 "${RDT_CWD[@]}" --command 'robocopy src /tmp/rdt-x /MIR'
expect_both 'robocopy: a mirror under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "robocopy src '$RDT_SPT/x' /MIR" "$RDT_TOP" "$RDT_SPT")"
expect_both 'robocopy: a mirror into the scratchpad itself blocks' 2 \
  --payload "$(rdt_pl "robocopy src '$RDT_SPT' /MIR" "$RDT_TOP" "$RDT_SPT")"
rdt_ar 'robocopy: unset key, a mirror under the root blocks' 2 "robocopy src '$RDT_AR/child' /MIR"
rdt_ar 'robocopy: a mirror under the root allowed' 0 "robocopy src '$RDT_AR/child' /MIR" "$RDT_AR"
rdt_ar 'robocopy: a mirror into the root itself blocks' 2 "robocopy src '$RDT_AR' /MIR" "$RDT_AR"
rdt_ar 'robocopy: a move from under the root allowed' 0 "robocopy '$RDT_AR/child' build/rdt-out /MOVE" "$RDT_AR"
expect_both 'robocopy: PS a mirror under an allowed root allowed' 0 --tool PowerShell --cwd / \
  --command "robocopy src '$RDT_AR/child' /MIR" -- "HOME=$RDT_AH" "$RDT_KEY=$RDT_AR"
expect_both 'robocopy: a mirror into the toplevel blocks' 2 "${RDT_CWD[@]}" --command 'robocopy src . /MIR'
# The items xargs appends are the robocopy's operands.
expect_both 'robocopy: xargs fed by an unconfined listing blocks' 2 "${RDT_CWD[@]}" \
  --command 'cat list | xargs robocopy src /MIR'

# A robocopy that deletes nothing, a side it does not delete from, a /XF list
# entry, a fully quoted glob, and the mechanism as quoted prose.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: $rdt_cmd allowed" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
  expect_both "robocopy: PS $rdt_cmd allowed" 0 --tool PowerShell "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
robocopy src /opt/nonexistent-rdt/x /E
robocopy /opt/nonexistent-rdt/x build/rdt-out /MIR
robocopy build/rdt-x /opt/nonexistent-rdt/x /MOVE
robocopy src build/rdt-out /XF / /MIR
robocopy '/opt/nonexistent-rdt/*' build/rdt-out /MIR
git commit -m "robocopy src / /MIR"
echo 'robocopy / build/rdt-out /MOVE'
EOF

# From the Bash tool a brace or a glob can change which word is the source or
# the destination, so every operand is judged; a substitution body is judged.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: $rdt_cmd blocks" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
robocopy /opt/nonexistent-rdt/* build/rdt-out /MIR
robocopy {src,/} /MIR
robocopy $UNSET src / /MIR
robocopy "$@" /MIR
robocopy src / -MIR
echo "$(robocopy src / /MIR)"
EOF

# From the Bash tool MSYS rewrites a single-slash one-letter word to that
# drive's root, so `/e` is an operand there and never the /E option; from the
# PowerShell tool it is the option, and the robocopy names no destination.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: $rdt_cmd blocks" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
robocopy src /e /MIR
robocopy src /S /PURGE
robocopy src /x /e /MIR
robocopy /e build/rdt-out /MOVE
EOF
expect_both 'robocopy: PS robocopy src /e /MIR allowed' 0 --tool PowerShell "${RDT_CWD[@]}" \
  --command 'robocopy src /e /MIR'

# A prefix that turns MSYS path conversion off for the robocopy makes `/e` the
# /E option again, so the destination is the word after the source. A bare
# assignment in its own segment is not exported, and an exclusion list that
# does not cover the word leaves it converted.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: $rdt_cmd blocks" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
MSYS_NO_PATHCONV=1 robocopy /e empty /opt/nonexistent-rdt/x /MIR
MSYS2_ARG_CONV_EXCL='*' robocopy /e empty /opt/nonexistent-rdt/x /MIR
MSYS2_ARG_CONV_EXCL='--x;/e' robocopy /e empty /opt/nonexistent-rdt/x /MIR
env MSYS_NO_PATHCONV=1 robocopy /e empty /opt/nonexistent-rdt/x /MIR
MSYS_NO_PATHCONV=1; robocopy src /e /MIR
MSYS2_ARG_CONV_EXCL=--x robocopy src /e /MIR
MSYS2_ARG_CONV_EXCL= robocopy src /e /MIR
EOF

# A suppressor value that expands at run time, or an env option that can drop
# the suppressor before robocopy starts, leaves the conversion state unknown,
# so every operand is judged, each single-slash one-letter word included.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: $rdt_cmd blocks" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
MSYS2_ARG_CONV_EXCL=$X robocopy /e empty /opt/nonexistent-rdt/x /MIR
MSYS_NO_PATHCONV=1 env -u MSYS_NO_PATHCONV robocopy /e /opt/nonexistent-rdt/x empty /MIR
MSYS_NO_PATHCONV=1 env -i robocopy /e /opt/nonexistent-rdt/x empty /MIR
EOF
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: $rdt_cmd allowed" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
MSYS_NO_PATHCONV=1 robocopy src /e /MIR
MSYS2_ARG_CONV_EXCL='*' robocopy src /e /MIR
MSYS_NO_PATHCONV=1 robocopy /e empty build/rdt-out /MIR
EOF

# From the PowerShell tool an array, an unset variable or a grouping can
# change which word is the destination, and `--%` is dropped before robocopy
# sees its arguments.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "robocopy: PS $rdt_cmd blocks" 2 --tool PowerShell "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
robocopy --% src C:\ /MIR
robocopy $null src C:\ /MIR
robocopy $pair /MIR
robocopy (Get-Pair) /MIR
EOF

guard_invoke "${RDT_CWD[@]}" --command 'robocopy src /opt/nonexistent-rdt/x /MIR'
assert_exit 'robocopy: an outside destination exits 2' 2 "$GUARD_RC"
assert_contains 'robocopy: the refusal names the destination' "$GUARD_ERR" "the operand '/opt/nonexistent-rdt/x'"

# --- 2j. git worktree remove --force (#9760) ---------------------------------
# -f or --force removes the worktree's directory even when it holds changes.
# Its <worktree> operand is judged as a recursive rm operand, and so is every
# registered worktree root whose path ends in it. Every form runs against a
# root, HOME, a path outside the allowed roots and a path inside the tree.
RDT_GWT_FORMS=(
  'git worktree remove --force TGT'
  'git worktree remove -f TGT'
  'git worktree remove -f -f TGT'
  'git worktree remove TGT --force'
  'git worktree remove --forc -- TGT'
  'git -c core.x=1 --no-pager worktree remove -ff TGT'
)
rdt_gwt() { # <label> <want> <target> [guard_invoke option ...]: every form
  local label="$1" want="$2" t="$3" f c
  shift 3
  for f in "${RDT_GWT_FORMS[@]}"; do
    c="${f//TGT/$t}"
    expect_both "git worktree: $label: $c" "$want" --command "$c" "$@"
  done
}
rdt_gwt 'a root blocks' 2 /
rdt_gwt 'HOME blocks' 2 '$HOME'
rdt_gwt '~ blocks' 2 '~'
rdt_gwt 'outside the tree blocks' 2 /opt/nonexistent-rdt/x "${RDT_CWD[@]}"
rdt_gwt 'inside the tree allowed' 0 build/rdt-wt-nonexistent "${RDT_CWD[@]}"
expect_both 'git worktree: the toplevel blocks' 2 "${RDT_CWD[@]}" --command 'git worktree remove --force .'
expect_both 'git worktree: under /tmp allowed' 0 "${RDT_CWD[@]}" --command 'git worktree remove --force /tmp/rdt-wt-x'
expect_both 'git worktree: under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "git worktree remove --force '$RDT_SPT/wt'" "$RDT_TOP" "$RDT_SPT")"
expect_both 'git worktree: the scratchpad itself blocks' 2 \
  --payload "$(rdt_pl "git worktree remove --force '$RDT_SPT'" "$RDT_TOP" "$RDT_SPT")"
rdt_ar 'git worktree: unset key, under the root blocks' 2 "git worktree remove --force '$RDT_AR/child'"
rdt_ar 'git worktree: under the root allowed' 0 "git worktree remove --force '$RDT_AR/child'" "$RDT_AR"
rdt_ar 'git worktree: the root itself blocks' 2 "git worktree remove --force '$RDT_AR'" "$RDT_AR"

# Without a force flag git refuses an unclean worktree; other subcommands, and
# the mechanism as quoted prose, delete nothing.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "git worktree: $rdt_cmd allowed" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
git worktree remove /opt/nonexistent-rdt/x
git worktree add /opt/nonexistent-rdt/x
git worktree list
git worktree prune
git commit -m "git worktree remove --force /"
git commit -m 'drop it' -m "git worktree remove --force ~"
echo 'git worktree remove --force /'
EOF

# Launchers, child shells, substitutions, braces, and a relative name under
# an option that selects another repository.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "git worktree: $rdt_cmd blocks" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
sudo git worktree remove --force /
bash -c 'git worktree remove --force ~'
echo "$(git worktree remove --force /)"
git worktree remove --force {build/rdt-x,/}
git -C /opt/nonexistent-rdt worktree remove --force wt
git --git-dir=/opt/nonexistent-rdt/.git worktree remove --force wt
GIT_DIR=/opt/nonexistent-rdt/.git git worktree remove --force wt
env GIT_DIR=/opt/nonexistent-rdt/.git git worktree remove --force wt
X=wt; git -C /opt/nonexistent-rdt worktree remove --force "$X"
cd /opt/nonexistent-rdt && git worktree remove --force wt
cat list | xargs git worktree remove --force
EOF

# Registered worktrees, on the fixture of section 2e: under the suite's temp
# directory a linked worktree is strictly under a temp root, so removing it
# passes, by path or by its trailing name; the toplevel, a directory holding a
# worktree, and the worktree the session runs in stay refused.
rdt_wt 'git worktree remove of a linked worktree allowed' 0 "git worktree remove --force '$RDT_WF/wt1'"
rdt_wt 'git worktree remove by trailing name allowed' 0 'git worktree remove --force wt1'
rdt_wt 'git worktree remove of the toplevel blocks' 2 "git worktree remove --force '$RDT_WF/main'"
rdt_wt 'git worktree remove of a directory holding one blocks' 2 "git worktree remove --force '$RDT_WF/holder'"
rdt_wt 'from a linked worktree: git worktree remove of itself blocks' 2 \
  "git worktree remove --force '$RDT_WF/wt1'" "$RDT_WF/wt1"
rdt_wt 'from a linked worktree: git worktree remove of itself by name blocks' 2 \
  'git worktree remove --force wt1' "$RDT_WF/wt1"

# Outside every temp root (the checkout's .work), a registered worktree stays
# protected, a trailing name included and one inside the toplevel too, until
# an allowed root other than the toplevel holds it.
RDT_GW="$RDT_AB/gwt"
mkdir -p "$RDT_GW/main/.git/worktrees/n1" "$RDT_GW/main/.git/worktrees/n2" "$RDT_GW/n1" "$RDT_GW/main/n2"
printf '%s\n' "$RDT_GW/n1/.git" >"$RDT_GW/main/.git/worktrees/n1/gitdir"
printf 'gitdir: %s\n' "$RDT_GW/main/.git/worktrees/n1" >"$RDT_GW/n1/.git"
printf '%s\n' "$RDT_GW/main/n2/.git" >"$RDT_GW/main/.git/worktrees/n2/gitdir"
printf 'gitdir: %s\n' "$RDT_GW/main/.git/worktrees/n2" >"$RDT_GW/main/n2/.git"
rdt_gw() { # <label> <want> <command> [roots]: from the fixture's main worktree
  local -a env=("PATH=$TEST_TMPDIR/bin-git-top:$PATH" "RDT_STUB_TOP=$RDT_GW/main" "HOME=$RDT_AH")
  [[ -z "${4:-}" ]] || env+=("$RDT_KEY=$4")
  expect_both "git worktree: $1" "$2" --cwd "$RDT_GW/main" --command "$3" -- "${env[@]}"
}
rdt_gw 'a worktree outside temp blocks' 2 "git worktree remove --force '$RDT_GW/n1'"
rdt_gw 'a worktree outside temp by trailing name blocks' 2 'git worktree remove --force n1'
rdt_gw 'a worktree outside temp by a trailing glob blocks' 2 'git worktree remove --force n*'
rdt_gw 'a worktree inside the toplevel blocks' 2 'git worktree remove --force n2'
rdt_gw 'a worktree under an allowed root allowed' 0 "git worktree remove --force '$RDT_GW/n1'" "$RDT_GW"
rdt_gw 'a worktree under an allowed root by trailing name allowed' 0 'git worktree remove --force n1' "$RDT_GW"

guard_invoke "${RDT_CWD[@]}" --command 'git worktree remove --force /opt/nonexistent-rdt/x'
assert_exit 'git worktree: an outside worktree exits 2' 2 "$GUARD_RC"
assert_contains 'git worktree: the refusal names the worktree' "$GUARD_ERR" "the operand '/opt/nonexistent-rdt/x'"

# --- 2k. interpreter deletes (#9762) ------------------------------------------
# The program a python -c, node -e, perl -e or ruby -e runs, or one it reads
# from a heredoc or a here-string, is read for its deleter calls and for the
# commands it runs. A literal path is judged as a recursive rm operand. Every
# form runs against a root, HOME, `~`, a path outside the allowed roots and a
# path strictly inside the tree.
RDT_IX_FORMS=()
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] && RDT_IX_FORMS+=("$rdt_cmd")
done <<'EOF'
python3 -c "import shutil; shutil.rmtree('TGT')"
python -Bc "import shutil; shutil.rmtree('TGT', ignore_errors=True)"
python3 -c "import os; os.remove('TGT')"
node -e "require('fs').rmSync('TGT', { recursive: true, force: true })"
node --eval "const fs = require('fs'); fs.rmSync(\"TGT\", { recursive: true })"
perl -MFile::Path=rmtree -e "rmtree('TGT')"
perl -MFile::Path=remove_tree -le "remove_tree 'TGT' or die"
ruby -rfileutils -e "FileUtils.rm_rf('TGT')"
ruby -rfileutils -e "FileUtils.rm_rf 'TGT'"
python3 -c "import subprocess; subprocess.run(['rm', '-rf', 'TGT'], check=True)"
python3 -c "import os; os.system('rm -rf TGT')"
node -e "require('child_process').execSync('rm -rf TGT')"
node -e "require('child_process').spawnSync('rm', ['-rf', 'TGT'])"
ruby -e "system('rm', '-rf', 'TGT')"
perl -e "system 'rm -rf TGT'"
sudo python3 -c "import shutil; shutil.rmtree('TGT')"
bash -c "python3 -c \"import shutil; shutil.rmtree('TGT')\""
EOF
RDT_IX_FORMS+=(
  $'python3 - <<"EOF"\nimport shutil\nshutil.rmtree("TGT")\nEOF'
  $'node <<EOF\nrequire("fs").rmSync("TGT", { recursive: true })\nEOF'
  $'cat <<A\nprint(1)\nA\nruby -rfileutils - <<B\nFileUtils.rm_rf("TGT")\nB'
  "python3 <<< \"import shutil; shutil.rmtree('TGT')\""
)
rdt_ix() { # <label> <want> <target> [guard_invoke option ...]: every form
  local label="$1" want="$2" t="$3" f c
  shift 3
  for f in "${RDT_IX_FORMS[@]}"; do
    c="${f//TGT/$t}"
    expect_both "interpreter: $label: $c" "$want" --command "$c" "$@"
  done
}
rdt_ix 'a root blocks' 2 /
rdt_ix 'HOME blocks' 2 '$HOME'
rdt_ix '~ blocks' 2 '~'
rdt_ix 'outside the tree blocks' 2 /opt/nonexistent-rdt/x "${RDT_CWD[@]}"
rdt_ix 'inside the tree allowed' 0 plugins/rdt-nonexistent "${RDT_CWD[@]}"
expect_both 'interpreter: a delete under /tmp allowed' 0 "${RDT_CWD[@]}" \
  --command "python3 -c \"import shutil; shutil.rmtree('/tmp/rdt-x')\""
expect_both 'interpreter: a delete under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "python3 -c \"import shutil; shutil.rmtree('$RDT_SPT/x')\"" "$RDT_TOP" "$RDT_SPT")"
expect_both 'interpreter: the scratchpad itself blocks' 2 \
  --payload "$(rdt_pl "python3 -c \"import shutil; shutil.rmtree('$RDT_SPT')\"" "$RDT_TOP" "$RDT_SPT")"
rdt_ar 'interpreter: unset key, a delete under the root blocks' 2 \
  "node -e \"require('fs').rmSync('$RDT_AR/child', { recursive: true })\""
rdt_ar 'interpreter: a delete under the root allowed' 0 \
  "node -e \"require('fs').rmSync('$RDT_AR/child', { recursive: true })\"" "$RDT_AR"
rdt_ar 'interpreter: a delete of the root itself blocks' 2 \
  "ruby -rfileutils -e \"FileUtils.rm_rf('$RDT_AR')\"" "$RDT_AR"
expect_both 'interpreter: a delete of the toplevel blocks' 2 "${RDT_CWD[@]}" \
  --command "python3 -c \"import shutil; shutil.rmtree('.')\""

# The mechanism as quoted prose, a deleter named inside a string or a comment
# of the code, a command that deletes nothing, a script file, a module, and a
# heredoc that is data for a script or belongs to another command.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "interpreter: $rdt_cmd allowed" 0 --command "$rdt_cmd"
  expect_both "interpreter: $rdt_cmd allowed with a cwd" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
git commit -m "python3 -c 'import shutil; shutil.rmtree(\"/\")'"
git commit -m 'fix' -m "node -e \"require('fs').rmSync('/', { recursive: true })\""
echo 'ruby -rfileutils -e "FileUtils.rm_rf(\"/\")"'
python3 -c "print('never call shutil.rmtree(\"/\")')"
python3 -c "import shutil  # shutil.rmtree('/')"
node -e "/* require('fs').rmSync('/') */ console.log(1)"
perl -e "print 'rmtree(\"/\")'"
python3 -c "import os; print(os.remove)"
python3 -c "import os; os.system('ls /')"
node -e "require('child_process').execSync('git status')"
python3 -c "import shutil; shutil.rmtree('build/rdt-x')"
python3 -m shutil rmtree /
python3 script.py --rmtree /
perl -pi -e 's/rmtree/remove_tree/' lib/rdt-x.pm
node -e "require('fs').rmSync('build/rdt-x',{recursive:true}); console.log('a/b'.replace(/\//g,'_'))"
EOF
rdt_ix_n=0
for rdt_cmd in \
  $'cat <<"EOF"\nimport shutil; shutil.rmtree("/")\nEOF' \
  $'python3 script.py <<"EOF"\nimport shutil; shutil.rmtree("/")\nEOF' \
  $'cat <<A\nimport shutil; shutil.rmtree("/")\nA\npython3 - <<B\nprint(1)\nB'; do
  rdt_ix_n=$((rdt_ix_n + 1))
  expect_both "interpreter: a heredoc no interpreter reads as its program ($rdt_ix_n) allowed" 0 \
    "${RDT_CWD[@]}" --command "$rdt_cmd"
done

# A path the code computes cannot be placed, so the call is refused: an
# argument, an expression, an interpolated string, a list element, a `$` the
# shell may have expanded, and a command built from one. A substitution body
# is read too. So is a deleter, a backtick, a ruby %x or a perl qx after a
# comment character that a `/` regex literal on its line may hold (`/\//`,
# `/\/*/`, `/#/`, `/\#/`).
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "interpreter: $rdt_cmd blocks" 2 --command "$rdt_cmd"
done <<'EOF'
python3 -c "import shutil, sys; shutil.rmtree(sys.argv[1])" build
python3 -c "import shutil, os; shutil.rmtree(os.path.expanduser('~'))"
python3 -c "import shutil; shutil.rmtree(f'{d}/build')"
python3 -c 'import shutil; shutil.rmtree("$X/build")'
node -e "require('fs').rmSync(process.argv[1], { recursive: true })" build
ruby -rfileutils -e "FileUtils.rm_rf(ARGV[0])" build
ruby -rfileutils -e "FileUtils.rm_rf ARGV"
perl -MFile::Path=rmtree -e "rmtree(\$ARGV[0])" build
python3 -c "import subprocess, sys; subprocess.run(['rm', '-rf', sys.argv[1]])" build
python3 -c "import os; os.system(f'rm -rf {d}')"
ruby -e 'system("rm -rf #{ARGV[0]}")' build
perl -e 'system("rm -rf $ARGV[0]")' build
perl -e 'my $o = qx(rm -rf /);'
ruby -e 'puts %x(rm -rf /)'
ruby -e 'puts `rm -rf /`'
echo "$(python3 -c "import shutil; shutil.rmtree('/')")"
python3 -c 'import os; os.system("rm\t-rf\t~")'
python3 -c 'import os; os.system("find \x2f -delete")'
python3 -BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBc "import shutil; shutil.rmtree('/')"
perl -e 'unlink for "/opt/nonexistent-rdt/x/f"'
perl -nle unlink
ruby -rfileutils -e "FileUtils.rm_rf({'/opt/nonexistent-rdt/x'=>1}.keys)"
perl -MFile::Path -Fe -e 'BEGIN{rmtree("/")}'
node -e "'a/b'.replace(/\//g,'_'); require('fs').rmSync('/',{recursive:true})"
node -e "'a/b'.replace(/\/*/g,''); require('fs').rmSync('/'); /* */"
ruby -rfileutils -e "x =~ /#/; FileUtils.rm_rf('/')"
perl -MFile::Path=rmtree -e '$x =~ /\#/; rmtree("/")'
ruby -e 'x =~ /#/; `rm -rf /`'
ruby -e 'x =~ /#/; %x(rm -rf /)'
perl -e '$x =~ /\#/; `rm -rf /`'
perl -e '$x =~ /\#/; qx(rm -rf /)'
EOF

# A ruby delete that holds none of the other prefilter words, a program read
# from /dev/stdin, an unquoted heredoc whose backslash-newline bash removes,
# and a heredoc judged from where its interpreter ran, not after a later `cd -`.
expect_both 'interpreter: ruby Dir.delete outside the tree blocks' 2 "${RDT_CWD[@]}" \
  --command 'ruby -e '\''Dir.delete("/opt/nonexistent-rdt/x")'\'''
expect_both 'interpreter: a program read from /dev/stdin blocks' 2 \
  --command $'python3 /dev/stdin <<"EOF"\nimport shutil; shutil.rmtree("/")\nEOF'
expect_both 'interpreter: an unquoted heredoc with a backslash-newline blocks' 2 \
  --command $'python3 - <<EOF\nimport shutil; shutil.rm\\\ntree("/")\nEOF'
expect_both 'interpreter: a heredoc before a later cd - blocks' 2 "${RDT_CWD[@]}" \
  --command $'python3 - <<"EOF"\nimport shutil; shutil.rmtree("..")\nEOF\ncd -'
# The items xargs hands an interpreter are its argv, not targets.
expect_both 'interpreter: xargs into python with a literal path inside the tree allowed' 0 "${RDT_CWD[@]}" \
  --command "ls | xargs python3 -c \"import shutil; shutil.rmtree('build/rdt-x')\""

guard_invoke --command "python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1])' build"
assert_exit 'interpreter: a computed path exits 2' 2 "$GUARD_RC"
assert_contains 'interpreter: the refusal names the expression' "$GUARD_ERR" 'the path given as sys.argv[1]'
guard_invoke "${RDT_CWD[@]}" --command "python3 -c \"import shutil; shutil.rmtree('/opt/nonexistent-rdt/x')\""
assert_exit 'interpreter: an outside path exits 2' 2 "$GUARD_RC"
assert_contains 'interpreter: the refusal names the path' "$GUARD_ERR" "the operand '/opt/nonexistent-rdt/x'"

# --- 2l. decoder sinks (#9763) ------------------------------------------------
# A decoder feeding an execution sink is refused outright, whatever the decoded
# text targets. Every form runs with a payload that decodes to a delete of a
# root, of HOME, of a path outside the allowed roots and of a path strictly
# inside the tree: B64 is that delete in base64, HEX in hex. The guard decodes
# nothing; the payloads only make each case read as the delete it hides.
RDT_DS_FORMS=()
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] && RDT_DS_FORMS+=("$rdt_cmd")
done <<'EOF'
echo B64 | base64 -d | sh
echo B64 | base64 --decode | bash
printf %s B64 | base64 -D | zsh
base64 -d <<< B64 | bash -s
echo B64 | base64 -di | sudo bash
echo B64 | base64 -d | tee /tmp/rdt-x | sh
echo B64 | base64 -d | cat | sh
echo B64 | base64 -d | tr -d '\r' | sh
echo B64 | base64 -d | head -c 999 | bash
echo B64 | base64 -id | sh
echo B64 | base64 -d | sh -c sh
echo B64 | base64 -d | bash -c 'cat | sh'
echo B64 | base64 -d | bash /dev/fd/0
true; `echo B64 | base64 -d`
python3 -c "import os; os.system('echo B64 | base64 -d | sh')"
echo B64 | base32 -d | sh
echo B64 | basenc --base64 -d | sh
echo B64 | base64 -d | source /dev/stdin
echo HEX | xxd -r -p | sh
xxd -r -p <<< HEX | bash
eval "$(echo B64 | base64 -d)"
eval $(echo B64 | base64 -d)
eval "`echo B64 | base64 -d`"
eval `echo B64 | base64 -d`
eval "$(echo HEX | xxd -r -p)"
bash -c "$(echo B64 | base64 -d)"
sh -c "$(base64 -d <<< B64)"
bash -c $(echo B64 | base64 -d)
bash <(echo B64 | base64 -d)
source <(echo B64 | base64 -d)
. <(echo HEX | xxd -r -p)
$(echo B64 | base64 -d)
`echo B64 | base64 -d`
bash <<< "$(echo B64 | base64 -d)"
echo "$(echo B64 | base64 -d | sh)"
EOF
rdt_ds() { # <label> <want> <base64 payload> <hex payload> [guard_invoke option ...]: every form
  local label="$1" want="$2" b="$3" h="$4" f c
  shift 4
  for f in "${RDT_DS_FORMS[@]}"; do
    c="${f//B64/$b}"
    c="${c//HEX/$h}"
    expect_both "decoder sink: $label: $c" "$want" --command "$c" "$@"
  done
}
rdt_ds 'rm -rf / blocks' 2 cm0gLXJmIC8= 726d202d7266202f
rdt_ds 'rm -rf $HOME blocks' 2 cm0gLXJmICRIT01F 726d202d72662024484f4d45
rdt_ds 'rm -rf outside the tree blocks' 2 cm0gLXJmIC9vcHQveA== 726d202d7266202f6f70742f78 "${RDT_CWD[@]}"
rdt_ds 'rm -rf inside the tree blocks too' 2 cm0gLXJmIGJ1aWxk 726d202d7266206275696c64 "${RDT_CWD[@]}"

# Decoded text written to a file strictly inside the tree, the scratchpad or an
# allowed root is data, and so is decoded text a pager shows.
expect_both 'decoder sink: decoded to a file inside the tree allowed' 0 "${RDT_CWD[@]}" \
  --command 'echo cm0gLXJmIC8= | base64 -d > build/rdt-x.sh'
expect_both 'decoder sink: decoded to a file under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "echo cm0gLXJmIC8= | base64 -d > '$RDT_SPT/x.sh'" "$RDT_TOP" "$RDT_SPT")"
rdt_ar 'decoder sink: decoded to a file under the root allowed' 0 \
  "echo cm0gLXJmIC8= | base64 -d > '$RDT_AR/child/x.sh'" "$RDT_AR"
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "decoder sink: $rdt_cmd allowed" 0 --command "$rdt_cmd"
  expect_both "decoder sink: $rdt_cmd allowed with a cwd" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
base64 -d build/rdt-x.b64 > build/rdt-x.bin
base64 --decode build/rdt-x.b64 >> build/rdt-x.bin
base64 -d -o build/rdt-x.bin build/rdt-x.b64
xxd -r build/rdt-x.hex build/rdt-x.bin
xxd -r -p build/rdt-x.hex > build/rdt-x.bin
base64 -d build/rdt-x.b64 | less
echo cm0gLXJmIC8= | base64 -d | more
base64 -d build/rdt-x.b64 > build/rdt-x.sh && bash build/rdt-x.sh
base64 -d build/rdt-x.b64 | bash build/rdt-x.sh
base64 -w0 build/rdt-x.bin
x=$(echo cm0gLXJmIC8= | base64 -d); echo "$x"
git commit -m "echo cm0gLXJmIC8= | base64 -d | sh"
git commit -m 'eval "$(echo cm0gLXJmIC8= | base64 -d)"'
echo 'bash <(xxd -r -p build/rdt-x.hex)'
EOF

# PowerShell: [Convert]::FromBase64String reaching Invoke-Expression.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "decoder sink: PS $rdt_cmd blocks" 2 --tool PowerShell --command "$rdt_cmd"
done <<'EOF'
iex ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('cm0gLXJmIC8=')))
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('cm0gLXJmIC8=')) | iex
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b)) | Invoke-Expression
Invoke-Expression ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($b)))
iex $([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('cm0gLXJmIC8=')))
EOF
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "decoder sink: PS $rdt_cmd allowed" 0 --tool PowerShell "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
[IO.File]::WriteAllBytes('build\rdt-x.bin', [Convert]::FromBase64String($b))
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) | Out-File build\rdt-x.ps1
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) | more
git commit -m "iex ([Convert]::FromBase64String('cm0gLXJmIC8='))"
Write-Output 'iex ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)))'
EOF

expect_both 'decoder sink: an attended session is denied too' 2 \
  --command 'echo cm0gLXJmIC8= | base64 -d | sh' -- CLAUDE_CODE_SESSION_ATTENDED=1
guard_invoke --command 'echo cm0gLXJmIC8= | base64 -d | sh'
assert_exit 'decoder sink: a decoder piped into sh exits 2' 2 "$GUARD_RC"
assert_contains 'decoder sink: the refusal names the mechanism' "$GUARD_ERR" 'decoded text'

# --- 2m. PowerShell deletes behind indirection and pipelines (#9765) ----------
# A delete run through Start-Process, Invoke-Expression, pwsh -Command, a
# decoded -EncodedCommand, a pipeline removal or a .NET delete is judged as the
# delete itself. Every form runs against a drive root, HOME, a path outside the
# allowed roots and a path strictly inside the tree. ENC stands for the form's
# delete passed as -EncodedCommand: rdt_enc builds the base64 of its UTF-16LE
# bytes, so no case runs a delete.
rdt_enc() { # <ascii text>: the -EncodedCommand value that decodes to it
  local s="$1" i
  for ((i = 0; i < ${#s}; i++)); do
    printf '%s\0' "${s:i:1}"
  done | base64 | tr -d '\n'
}
RDT_PSI_FORMS=()
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] && RDT_PSI_FORMS+=("$rdt_cmd")
done <<'EOF'
Start-Process cmd -ArgumentList '/c rd /s /q TGT'
Start-Process -FilePath cmd.exe -ArgumentList '/c','rd /s /q TGT' -Wait
saps pwsh '-NoProfile','-Command','Remove-Item -Recurse -Force TGT'
Start-Process powershell -ArgumentList '-c', 'Remove-Item -Recurse TGT' -NoNewWindow
Invoke-Expression 'Remove-Item -Recurse -Force TGT'
iex "Remove-Item -Recurse TGT"
Invoke-Expression -Command 'ri -r TGT'
'Remove-Item -Recurse TGT' | iex
Write-Output 'Remove-Item -Recurse TGT' | Invoke-Expression
pwsh -Command 'Remove-Item -Recurse -Force TGT'
pwsh -NoProfile -NonInteractive -c "Remove-Item -Recurse TGT"
powershell.exe -ExecutionPolicy Bypass -Command Remove-Item -Recurse TGT
pwsh -Command { Remove-Item -Recurse TGT }
powershell -ep Bypass Remove-Item -Recurse TGT
pwsh -NoProfile -EncodedCommand ENC
powershell -enc ENC
Get-ChildItem TGT | Remove-Item -Recurse -Force
gci -Path TGT -Recurse | Remove-Item
Get-ChildItem -LiteralPath TGT -Filter *.tmp | Where-Object { $_.Length -gt 0 } | Remove-Item
gci TGT | % { $_.Delete() }
Get-ChildItem TGT -Directory | ForEach-Object { $PSItem.Delete($true) }
gci TGT | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
dir TGT | Sort-Object Name | Select-Object -First 5 | rm -r
Get-ChildItem TGT | Remove-Item -Recurse; Write-Output done
[IO.Directory]::Delete('TGT', $true)
[System.IO.Directory]::Delete("TGT", $true)
[IO.File]::Delete('TGT')
(Get-Item TGT).Delete($true)
EOF
rdt_psi() { # <label> <want> <target> [guard_invoke option ...]: every form
  local label="$1" want="$2" t="$3" f c e
  shift 3
  e=$(rdt_enc "Remove-Item -Recurse -Force $t")
  for f in "${RDT_PSI_FORMS[@]}"; do
    c="${f//TGT/"$t"}"
    c="${c//ENC/"$e"}"
    expect_both "PS indirection: $label: $c" "$want" --tool PowerShell --command "$c" "$@"
  done
}
# portability-ok: Windows path strings in test fixtures, not regex/sed constructs
rdt_psi 'a drive root blocks' 2 'C:\'
rdt_psi 'HOME blocks' 2 '$HOME'
rdt_psi 'outside the tree blocks' 2 'D:\rdt-x\y' "${RDT_CWD[@]}"
rdt_psi 'inside the tree allowed' 0 'build\rdt-x' "${RDT_CWD[@]}"

# Strictly inside the scratchpad or an allowed root passes; the root itself,
# and a delete outside every root, do not.
rdt_pspl() { # <command>: a PowerShell payload from the checkout with this session's scratchpad
  MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$RDT_TOP" --arg s "$RDT_SPT" \
    '{tool_name:"PowerShell",tool_input:{command:$c},cwd:$d,scratchpad_dir:$s}'
}
while IFS='|' read -r rdt_want rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  rdt_cmd="${rdt_cmd//SPT/"$RDT_SPT"}"
  rdt_cmd="${rdt_cmd//ENC/"$(rdt_enc "Remove-Item -Recurse '$RDT_SPT/x'")"}"
  expect_both "PS indirection: scratchpad: $rdt_cmd" "$rdt_want" --payload "$(rdt_pspl "$rdt_cmd")"
done <<'EOF'
0|iex "Remove-Item -Recurse 'SPT/x'"
0|Start-Process pwsh -ArgumentList '-c', "Remove-Item -Recurse 'SPT/x'"
0|pwsh -EncodedCommand ENC
0|Get-ChildItem 'SPT/x' | Remove-Item -Recurse
0|[IO.Directory]::Delete('SPT/x', $true)
2|iex "Remove-Item -Recurse 'SPT'"
2|[IO.Directory]::Delete('SPT', $true)
EOF
rdt_arp 'iex Remove-Item under the root allowed' 0 "iex \"Remove-Item -Recurse '$RDT_AR/child'\"" "$RDT_AR"
rdt_arp 'pwsh -Command under the root allowed' 0 "pwsh -Command \"Remove-Item -Recurse '$RDT_AR/child'\"" "$RDT_AR"
rdt_arp '-EncodedCommand under the root allowed' 0 \
  "pwsh -EncodedCommand $(rdt_enc "Remove-Item -Recurse '$RDT_AR/child'")" "$RDT_AR"
rdt_arp 'gci | Remove-Item under the root allowed' 0 "Get-ChildItem '$RDT_AR/child' | Remove-Item -Recurse" "$RDT_AR"
rdt_arp 'gci | % Delete under the root allowed' 0 "gci '$RDT_AR/child' | % { \$_.Delete() }" "$RDT_AR"
rdt_arp '[IO.Directory]::Delete under the root allowed' 0 "[IO.Directory]::Delete('$RDT_AR/child', \$true)" "$RDT_AR"
rdt_arp 'unset key: [IO.Directory]::Delete under the root blocks' 2 "[IO.Directory]::Delete('$RDT_AR/child', \$true)"
rdt_arp 'iex Remove-Item of the root itself blocks' 2 "iex \"Remove-Item -Recurse '$RDT_AR'\"" "$RDT_AR"
rdt_arp 'gci | % Delete outside the root blocks' 2 "gci '$RDT_AO/x' | % { \$_.Delete() }" "$RDT_AR"

# The mechanism as quoted prose, and the same commands doing nothing that deletes.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "PS indirection: $rdt_cmd allowed" 0 --tool PowerShell --command "$rdt_cmd"
  expect_both "PS indirection: $rdt_cmd allowed with a cwd" 0 --tool PowerShell "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
git commit -m "Start-Process cmd '/c rd /s /q C:\'"
git commit -m "iex 'Remove-Item -Recurse C:\'"
git commit -m "pwsh -Command 'Remove-Item -Recurse C:\'"
git commit -m 'powershell -EncodedCommand UgBlAG0AbwB2AGUA'
Write-Output 'gci C:\ | % { $_.Delete() }'
Write-Output "[IO.Directory]::Delete('C:\', `$true)"
Start-Process cmd -ArgumentList '/c dir C:\'
iex 'Get-ChildItem C:\'
pwsh -NoProfile -File ./build.ps1
pwsh -Command 'Get-ChildItem C:\'
gci C:\ | Select-Object Name
Get-ChildItem C:\ | ForEach-Object { $_.Name }
[IO.File]::Exists('C:\x')
EOF

# A removal fed by anything but a listing names no target, and neither does a
# listing a pipe feeds, a grouping, an array or a call as a .NET delete's path,
# or a grouping .Delete() is called on that is not one listing. Every element
# of a listing's comma list is judged, a one-word grouping is read as iex's
# string, and a -WorkingDirectory this guard cannot place leaves the later
# targets judged. An -EncodedCommand it cannot decode is denied, attended or
# not.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "PS indirection: $rdt_cmd blocks" 2 --tool PowerShell "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
$dirs | ForEach-Object { $_.Delete($true) }
Get-Content list.txt | % { $_.Delete() }
'C:\' | Get-ChildItem | Remove-Item -Recurse
gci C:\ -Directory | gci | Remove-Item -Recurse
Get-ChildItem build, C:\ | Remove-Item -Recurse
gci @('C:\') | Remove-Item -Recurse
[IO.Directory]::Delete((Join-Path $a b), $true)
[IO.Directory]::Delete(@('C:\'), $true)
[IO.Directory]::Delete("$(Join-Path C:\ x)\..", $true)
[IO.Directory]::Delete([Environment]::GetFolderPath('UserProfile'), $true)
(Get-Item C:\ | Select-Object -First 1).Delete($true)
(Get-Content list.txt).Delete()
iex ('Remove-Item -Recurse C:\')
Start-Process notepad -WorkingDirectory $env:TEMP; Remove-Item -Recurse ..\..\..
pwsh -WorkingDirectory $x -c Get-Date; Remove-Item -Recurse ..\..
pwsh -EncodedCommand $enc
powershell -enc 'not base64!'
pwsh -EncodedCommand 6QA=
EOF
expect_both 'PS indirection: an unreadable -EncodedCommand is denied when attended' 2 \
  --tool PowerShell --command 'pwsh -EncodedCommand $enc' -- CLAUDE_CODE_SESSION_ATTENDED=1
guard_invoke --tool PowerShell --command 'pwsh -EncodedCommand $enc'
assert_contains 'PS indirection: the refusal names -EncodedCommand' "$GUARD_ERR" '-EncodedCommand'
guard_invoke --tool PowerShell "${RDT_CWD[@]}" --command "Start-Process cmd -ArgumentList '/c rd /s /q D:\\rdt-x\\y'"
assert_exit 'PS indirection: Start-Process of an outside rd /s exits 2' 2 "$GUARD_RC"
assert_contains 'PS indirection: the refusal says the target is outside the tree' "$GUARD_ERR" 'outside the working tree'

# --- 2n. moves and content destroyers (#9767) ----------------------------------
# An mv source, the file a truncate, shred or dd of= destroys, and on the
# PowerShell tool a Move-Item or Clear-Content path or a Set-Content of several
# files are each judged as a recursive rm operand. Every form runs against a
# root, HOME, a path outside the allowed roots and a path strictly inside the
# tree. No case runs the command.
RDT_MV_FORMS=(
  'mv TGT build/rdt-out'
  'mv TGT /dev/null'
  'mv -f build/rdt-x TGT build/rdt-out/'
  'mv -t build/rdt-out TGT'
  'mv --target-directory build/rdt-out TGT'
  'mv -S .bak TGT build/rdt-out'
  'sudo mv -- TGT build/rdt-out'
  'truncate -s 0 TGT'
  'truncate --size 0 TGT'
  'truncate -r build/rdt-ref TGT'
  'shred -u TGT'
  'shred -n 3 -z TGT'
  'dd if=/dev/zero of=TGT bs=1M count=1'
)
RDT_MVP_FORMS=(
  'Move-Item TGT build\rdt-out'
  'Move-Item -Path TGT -Destination build\rdt-out -Force'
  'Move-Item -Destination build\rdt-out TGT'
  'mi -LiteralPath TGT build\rdt-out'
  'move TGT build\rdt-out'
  'mv build\rdt-x, TGT build\rdt-out'
  'Get-ChildItem TGT | Move-Item -Destination build\rdt-out'
  'Clear-Content TGT'
  'clc -Path TGT -Force'
  'gci TGT | Clear-Content'
  'Set-Content -Path TGT, build\rdt-x -Value x'
  'Set-Content build\rdt-x,TGT x'
)
rdt_mv() { # <label> <want> <bash target> <PowerShell target> [guard_invoke option ...]: every form
  local label="$1" want="$2" t="$3" tp="$4" f
  shift 4
  for f in "${RDT_MV_FORMS[@]}"; do
    expect_both "moves: $label: ${f//TGT/$t}" "$want" --command "${f//TGT/$t}" "$@"
  done
  for f in "${RDT_MVP_FORMS[@]}"; do
    expect_both "moves: PS $label: ${f//TGT/$tp}" "$want" --tool PowerShell --command "${f//TGT/"$tp"}" "$@"
  done
}
# portability-ok: Windows path strings in test fixtures, not regex/sed constructs
rdt_mv 'a root blocks' 2 / 'C:\'
rdt_mv 'HOME blocks' 2 '$HOME' '$HOME'
rdt_mv 'outside the tree blocks' 2 /opt/nonexistent-rdt/x 'D:\rdt-x\y' "${RDT_CWD[@]}"
rdt_mv 'inside the tree allowed' 0 plugins/rdt-nonexistent 'build\rdt-x' "${RDT_CWD[@]}"
expect_both 'moves: mv ~ /dev/null blocks' 2 --command 'mv ~ /dev/null'

# Strictly inside the scratchpad or an allowed root passes; the root itself
# does not.
expect_both 'moves: a source under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "mv '$RDT_SPT/x' build/rdt-out" "$RDT_TOP" "$RDT_SPT")"
expect_both 'moves: truncate under the scratchpad allowed' 0 \
  --payload "$(rdt_pl "truncate -s 0 '$RDT_SPT/x.log'" "$RDT_TOP" "$RDT_SPT")"
expect_both 'moves: the scratchpad itself moved away blocks' 2 \
  --payload "$(rdt_pl "mv '$RDT_SPT' build/rdt-out" "$RDT_TOP" "$RDT_SPT")"
while IFS='|' read -r rdt_want rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  rdt_cmd="${rdt_cmd//SPT/"$RDT_SPT"}"
  expect_both "moves: PS scratchpad: $rdt_cmd" "$rdt_want" --payload "$(rdt_pspl "$rdt_cmd")"
done <<'EOF'
0|Move-Item 'SPT/x' build\rdt-out
0|Clear-Content 'SPT/x.log'
2|Move-Item 'SPT' build\rdt-out
EOF
rdt_ar 'moves: unset key, a source under the root blocks' 2 "mv '$RDT_AR/child' '$RDT_AR/moved'"
rdt_ar 'moves: a source under the root allowed' 0 "mv '$RDT_AR/child' '$RDT_AR/moved'" "$RDT_AR"
rdt_ar 'moves: the root itself moved away blocks' 2 "mv '$RDT_AR' '$RDT_AR2/moved'" "$RDT_AR"
rdt_ar 'moves: dd of= under the root allowed' 0 "dd if=/dev/zero of='$RDT_AR/child/x.img' count=1" "$RDT_AR"
rdt_arp 'unset key: Clear-Content under the root blocks' 2 "Clear-Content '$RDT_AR/child/x.txt'"
rdt_arp 'Clear-Content under the root allowed' 0 "Clear-Content '$RDT_AR/child/x.txt'" "$RDT_AR"
rdt_arp 'Move-Item of the root itself blocks' 2 "Move-Item '$RDT_AR' '$RDT_AR2/moved'" "$RDT_AR"

# The mechanism as quoted prose, a move out of the tree, a write to the null
# device, and a Set-Content of one file.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "moves: $rdt_cmd allowed" 0 --command "$rdt_cmd"
  expect_both "moves: $rdt_cmd allowed with a cwd" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
git commit -m "mv ~ /dev/null"
git commit -m "truncate -s 0 /etc/hosts; shred -u /etc/passwd"
echo 'dd if=/dev/zero of=/dev/sda'
mv build/rdt-x build/rdt-out
mv build/rdt-x /opt/nonexistent-rdt/x
mv -t /opt/nonexistent-rdt/x build/rdt-x
mv build/*.o /opt/nonexistent-rdt/x/
truncate -s 0 build/rdt-x.log
shred -n 1 -s 4K build/rdt-x
dd if=/opt/nonexistent-rdt/x of=/dev/null bs=1M
dd if=/dev/zero bs=1M count=1
mvn -q package
find build -name '*.o' | xargs mv -t build/rdt-out
ls *.img | xargs -I{} dd if={} of=/dev/null
EOF
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "moves: PS $rdt_cmd allowed" 0 --tool PowerShell --command "$rdt_cmd"
  expect_both "moves: PS $rdt_cmd allowed with a cwd" 0 --tool PowerShell "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
git commit -m "Move-Item C:\ D:\x"
Write-Output 'Clear-Content C:\x.txt'
git commit -m "Set-Content -Path C:\*.txt -Value x"
Set-Content -Path D:\rdt-x\y.txt -Value x
Set-Content D:\rdt-x\y.txt (Get-Date)
Set-Content (Join-Path $a b) x
'text' | Set-Content D:\rdt-x\y.txt
Move-Item build\rdt-x D:\rdt-x\y
Move-Item -Destination D:\rdt-x\y -Path build\rdt-x
EOF

# A source or file outside the tree, the toplevel or a .git moved away, a last
# word that can become several, an empty or bare-variable target, a feed no
# listing produced, a grouping as a path, a Set-Content of several files, and
# the same commands in a substitution or a child shell.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "moves: $rdt_cmd blocks" 2 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
mv /opt/nonexistent-rdt/x build/rdt-out
mv build/rdt-x /opt/nonexistent-rdt/x build/rdt-out
mv build/rdt-x /opt/nonexistent-rdt/{a,b}
mv --t=build/rdt-out /opt/nonexistent-rdt/x
mv .git build/rdt-git
mv . ../rdt-out
truncate -s 0 /opt/nonexistent-rdt/x
shred -u /opt/nonexistent-rdt/x
dd if=/dev/zero of=/opt/nonexistent-rdt/x
dd if=/dev/zero of=""
mv "$f" build/rdt-out
echo "$(mv ~ /dev/null)"
x="$(shred -u /opt/nonexistent-rdt/x)"
bash -c 'shred -u /opt/nonexistent-rdt/x'
python3 -c "import os; os.system('shred -u /opt/nonexistent-rdt/x')"
cat list | xargs mv -t build/rdt-out
find build/rdt-out -maxdepth 0 | xargs mv build/rdt-x ~
parallel mv build/rdt-x ~ ::: build/rdt-out
parallel ::: 'mv ~ /dev/null'
POSIXLY_CORRECT=1 shred -u build/rdt-x -n /opt/nonexistent-rdt/x
EOF
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "moves: PS $rdt_cmd blocks" 2 --tool PowerShell "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
Move-Item (Get-Item build\rdt-x) build\rdt-out
$files | Move-Item -Destination build\rdt-out
Clear-Content (Join-Path $a b)
Set-Content -Path D:\rdt-x\*.txt -Value x
Set-Content -LiteralPath build\rdt-x, D:\rdt-x\y -Value x
gci D:\rdt-x | % { Set-Content $_.FullName x }
iex 'Move-Item C:\ build\rdt-out'
EOF

guard_invoke "${RDT_CWD[@]}" --command 'mv /opt/nonexistent-rdt/x build/rdt-out'
assert_exit 'moves: an outside source exits 2' 2 "$GUARD_RC"
assert_contains 'moves: the refusal names the source' "$GUARD_ERR" "the operand '/opt/nonexistent-rdt/x'"

# --- 2o. shells and launchers from Bash (#9768) --------------------------------
# A delete run through eval, watch, wsl, cmd /c, a code heredoc or here-string
# a shell reads, or the text echo, printf or cat pipes into a shell is judged
# as the delete itself. Every form runs against a root, HOME, a path outside
# the allowed roots and a path strictly inside the tree. No case runs the
# command.
RDT_SL_FORMS=()
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] && RDT_SL_FORMS+=("$rdt_cmd")
done <<'EOF'
eval rm -rf TGT
eval 'rm -rf TGT'
watch rm -rf TGT
watch -n 5 'rm -rf TGT'
watch --interval 5 -t -- rm -rf TGT
watch -tx -q 3 rm -rf TGT
sudo watch --ex rm -rf TGT
wsl rm -rf TGT
wsl -d Ubuntu -- rm -rf TGT
wsl.exe -e rm -rf TGT
cmd //c rd //s //q TGT
cmd.exe /C rmdir /S TGT
cmd //c 'cd build && rd /s /q TGT'
bash <<< 'rm -rf TGT'
echo 'rm -rf TGT' | sh
echo rm -rf TGT | bash -s
echo -n 'rm -rf TGT' | sh
echo 'true\nrm -rf TGT' | sh
printf '%s\n' 'rm -rf TGT' | sudo bash
echo 'rm -rf TGT' | bash -c sh
cat <<< 'rm -rf TGT' | sh
EOF
RDT_NL=$'\n'
RDT_SL_FORMS+=(
  "bash <<'EOF'${RDT_NL}rm -rf TGT${RDT_NL}EOF"
  "sh -s <<EOF${RDT_NL}rm -rf TGT${RDT_NL}EOF"
  "cat <<'EOF' | sh${RDT_NL}rm -rf TGT${RDT_NL}EOF"
)
rdt_sl() { # <label> <want> <target> [guard_invoke option ...]: every form
  local label="$1" want="$2" t="$3" f
  shift 3
  for f in "${RDT_SL_FORMS[@]}"; do
    expect_both "shells: $label: ${f//TGT/$t}" "$want" --command "${f//TGT/$t}" "$@"
  done
}
rdt_sl 'a root blocks' 2 /
rdt_sl 'HOME blocks' 2 '$HOME'
rdt_sl 'outside the tree blocks' 2 /opt/nonexistent-rdt/x "${RDT_CWD[@]}"
rdt_sl 'inside the tree allowed' 0 build/rdt-x "${RDT_CWD[@]}"
# The README's examples, from a repository.
while IFS='|' read -r rdt_want rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "shells: $rdt_cmd" "$rdt_want" "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
2|watch rm -rf ~
2|cmd //c rd //s //q 'C:\'
2|echo 'rm -rf /opt/x' | sh
0|eval 'rm -rf build/x'
EOF

# Strictly inside the scratchpad or an allowed root passes; the root itself
# does not. The target is quoted, as a real path may hold a space.
RDT_SL_QUOTED_FORMS=(
  "eval \"rm -rf 'TGT'\""
  "watch -n 5 \"rm -rf 'TGT'\""
  "watch -x rm -rf 'TGT'"
  "wsl -- rm -rf 'TGT'"
  "cmd //c rd //s //q 'TGT'"
  "bash <<< \"rm -rf 'TGT'\""
  "echo \"rm -rf 'TGT'\" | sh"
  "bash <<'EOF'${RDT_NL}rm -rf 'TGT'${RDT_NL}EOF"
)
for rdt_f in "${RDT_SL_QUOTED_FORMS[@]}"; do
  expect_both "shells: under the scratchpad allowed: $rdt_f" 0 \
    --payload "$(rdt_pl "${rdt_f//TGT/$RDT_SPT/x}" "$RDT_TOP" "$RDT_SPT")"
  expect_both "shells: the scratchpad itself blocks: $rdt_f" 2 \
    --payload "$(rdt_pl "${rdt_f//TGT/$RDT_SPT}" "$RDT_TOP" "$RDT_SPT")"
  rdt_ar "shells: unset key, under the root blocks: $rdt_f" 2 "${rdt_f//TGT/$RDT_AR/child}"
  rdt_ar "shells: under the root allowed: $rdt_f" 0 "${rdt_f//TGT/$RDT_AR/child}" "$RDT_AR"
  rdt_ar "shells: the root itself blocks: $rdt_f" 2 "${rdt_f//TGT/$RDT_AR}" "$RDT_AR"
done

# The mechanism as quoted prose, a delete with no recursion, and text no
# shell reads as its program.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "shells: $rdt_cmd allowed" 0 --command "$rdt_cmd"
  expect_both "shells: $rdt_cmd allowed with a cwd" 0 "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
git commit -m "eval rm -rf /"
git commit -m "watch -x rm -rf ~"
git commit -m "wsl rm -rf /"
git commit -m "cmd //c rd //s //q C:/"
git commit -m "echo 'rm -rf /' | sh"
git commit -m "bash <<< 'rm -rf /'"
echo 'rm -rf /'
echo 'rm -rf /' > build/rdt-x.sh
echo 'rm -rf /' | less
printf '%s\n' 'rm -rf /' | wc -l
echo 'rm -rf /' | sh build/rdt-x.sh
watch -n 5 ls /
cmd //c rd build/rdt-x
cmd /c 'rd build\rdt-x'
EOF
expect_both 'shells: a heredoc cat writes to the terminal allowed' 0 \
  --command "cat <<'EOF'${RDT_NL}rm -rf /${RDT_NL}EOF"

# A cd inside a heredoc program moves its later relative targets, a confined
# pipeline inside a program is judged by its listing, each statement of a cmd
# line is judged, and a decoder sink inside a program is refused.
expect_both 'shells: a cd inside a heredoc program to a tree directory allowed' 0 "${RDT_CWD[@]}" \
  --command "bash <<'EOF'${RDT_NL}cd build${RDT_NL}rm -rf out${RDT_NL}EOF"
expect_both 'shells: a cd inside a heredoc program out of the tree blocks' 2 "${RDT_CWD[@]}" \
  --command "bash <<'EOF'${RDT_NL}cd /etc${RDT_NL}rm -rf ssh${RDT_NL}EOF${RDT_NL}cd /tmp"
expect_both 'shells: a confined pipeline inside a heredoc program allowed' 0 "${RDT_CWD[@]}" \
  --command "bash <<'EOF'${RDT_NL}find build -name '*.o' | xargs rm -rf${RDT_NL}EOF"
expect_both 'shells: a confined pipeline echo pipes into sh allowed' 0 "${RDT_CWD[@]}" \
  --command "echo \"find build -name '*.o' | xargs rm -rf\" | sh"
expect_both 'shells: a decoder sink inside a heredoc program blocks' 2 \
  --command "bash <<'EOF'${RDT_NL}echo cm0gLXJmIC8= | base64 -d | sh${RDT_NL}EOF"
expect_both 'shells: a decoder sink inside a here-string program blocks' 2 \
  --command "bash <<< 'echo cm0gLXJmIC8= | base64 -d | sh'"
expect_both 'shells: a printf too long to build piped into sh blocks' 2 \
  --command "printf 'rm -rf build/x %s$(rdt_rep x 9000)' y | sh"
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "shells: $rdt_cmd blocks" 2 --command "$rdt_cmd"
done <<'EOF'
cmd.exe /c rd /s/q 'C:\'
cmd //crd //s //q 'C:\'
cmd //c echo x '&&' robocopy src 'C:\' //MIR
EOF

guard_invoke "${RDT_CWD[@]}" --command "echo 'rm -rf /opt/nonexistent-rdt/x' | sh"
assert_exit 'shells: an outside target piped into sh exits 2' 2 "$GUARD_RC"
assert_contains 'shells: the refusal names the target' "$GUARD_ERR" "the operand '/opt/nonexistent-rdt/x'"

# --- 3. The block message ----------------------------------------------------
guard_invoke --command 'rm -rf /'
assert_exit "blocked case exits 2" 2 "$GUARD_RC"
assert_contains "blocked case names the BLOCKED token" "$GUARD_ERR" "BLOCKED:"

# --- 4. PowerShell Remove-Item / rd /s (#4516) --------------------------------
# Same target classes as Bash: root, empty, bare variable, outside-tree.
# JSON on stdin only. The guard must not load the PowerShell classifier.
if grep -nE '^[[:space:]]*source .+ps-command' "$HOOK" || grep -nE '^[^#]*ps::' "$HOOK"; then
  bad "the PowerShell lane sources or calls the classifier"
else
  ok "the PowerShell lane does not source the classifier"
fi

# Root, every spelling the issue names plus the aliases and prefixes.
expect_both 'PS Remove-Item -Recurse -Force C:\ blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse -Force C:\'
expect_both 'PS Remove-Item -r C:/ blocks' 2 \
  --tool PowerShell --command 'Remove-Item -r C:/'
expect_both 'PS Remove-Item -rec C: blocks' 2 \
  --tool PowerShell --command 'Remove-Item -rec C:'
expect_both 'PS ri -r C:\ blocks' 2 \
  --tool PowerShell --command 'ri -r C:\'
expect_both 'PS rm -rf / blocks (bash-in-PS cluster)' 2 \
  --tool PowerShell --command 'rm -rf /'
expect_both 'PS Remove-Item -LiteralPath C:\ -Recurse blocks' 2 \
  --tool PowerShell --command 'Remove-Item -LiteralPath C:\ -Recurse'
expect_both 'PS Remove-Item -Path C:\ -Recurse blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Path C:\ -Recurse'
expect_both 'PS Remove-Item -Recurse / blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse /'
expect_both 'PS Remove-Item -Recurse ~ blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse ~'
expect_both 'PS Remove-Item -Recurse $HOME blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse $HOME'
expect_both 'PS Remove-Item -Recurse /c blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse /c'
expect_both 'PS & Remove-Item -Recurse C:\ blocks' 2 \
  --tool PowerShell --command '& Remove-Item -Recurse C:\'

# Empty operand.
expect_both "PS Remove-Item -Recurse '' blocks" 2 \
  --tool PowerShell --command "Remove-Item -Recurse ''"
expect_both 'PS Remove-Item -Recurse "" blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse ""'
expect_both 'PS Remove-Item -Recurse with no path blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse'

# Bare variable.
expect_both 'PS ri -r $X blocks' 2 \
  --tool PowerShell --command 'ri -r $X'
expect_both 'PS Remove-Item -Recurse $env:X blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse $env:X'
expect_both 'PS Remove-Item -Recurse ${X} blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse ${X}'

# cmd /c rd /s and rmdir /s.
expect_both 'PS cmd /c rd /s /q C:\ blocks' 2 \
  --tool PowerShell --command 'cmd /c rd /s /q C:\'
expect_both 'PS cmd /c rmdir /s C:\ blocks' 2 \
  --tool PowerShell --command 'cmd /c rmdir /s C:\'
expect_both "PS cmd /c 'rd /s /q C:\' blocks" 2 \
  --tool PowerShell --command "cmd /c 'rd /s /q C:\'"
expect_both 'PS cmd.exe /c rd /s C:\ blocks' 2 \
  --tool PowerShell --command 'cmd.exe /c rd /s C:\'
expect_both 'PS rd /s C:\ blocks (cmd grammar on the alias)' 2 \
  --tool PowerShell --command 'rd /s C:\'

# A pipeline target no listing names cannot be named.
expect_both 'PS pipeline Remove-Item -Recurse blocks' 2 \
  --tool PowerShell --command 'Get-Content list.txt | Remove-Item -Recurse'

# Allowed: non-recursive, prose, other verbs.
expect_both 'PS Get-ChildItem C:\ allowed' 0 \
  --tool PowerShell --command 'Get-ChildItem C:\'
expect_both 'PS Remove-Item file (no recurse) allowed' 0 \
  --tool PowerShell --command 'Remove-Item C:\file.txt'
expect_both 'PS Write-Output naming the delete allowed' 0 \
  --tool PowerShell --command "Write-Output 'Remove-Item -Recurse C:\'"
expect_both 'PS cmd /c dir allowed' 0 \
  --tool PowerShell --command 'cmd /c dir C:\'
expect_both 'PS cmd /c rd without /s allowed' 0 \
  --tool PowerShell --command 'cmd /c rd C:\empty'
expect_both 'PS ri file (no -r) allowed' 0 \
  --tool PowerShell --command 'ri C:\file.txt'
expect_both 'PS Get-Process allowed' 0 \
  --tool PowerShell --command 'Get-Process'

# Outside-tree, with a payload cwd, same classes as Bash.
# portability-ok: Windows path string in a test fixture, not a regex/sed construct
expect_both 'PS Remove-Item -Recurse C:\Windows blocks with cwd' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'Remove-Item -Recurse C:\Windows'
expect_both 'PS Remove-Item -Recurse ./build allowed with cwd' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'Remove-Item -Recurse ./build'
expect_both 'PS ri -r $X blocks with cwd' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'ri -r $X'

# A non-Bash, non-PowerShell tool is still a skip.
expect "Write tool is not this guard's lane" 0 --tool Write --command 'Remove-Item -Recurse C:\'

# Kill switch covers the PowerShell lane too.
expect "PS kill switch disables the guard" 0 \
  --tool PowerShell --command 'Remove-Item -Recurse C:\' \
  -- "CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ENABLED=false"

# --- 4a. PowerShell statement boundaries and $env: operands (#4516) ------------
# A statement ends at an unquoted newline (LF, CRLF or a bare CR), `{`, `}`, `(`,
# `)` and `$(`, not only at `; | &`, so a delete after a newline or inside a
# scriptblock or a grouping is judged as a statement of its own. The shared field
# reader drops every CR from the command, so the guard re-reads a PowerShell
# command from the payload to see a bare CR.
# portability-ok: Windows path strings in test fixtures, not regex/sed constructs
for rdt_sep in $'\n' $'\r\n' $'\r'; do
  rdt_nl="LF"
  [[ "$rdt_sep" == $'\r\n' ]] && rdt_nl="CRLF"
  [[ "$rdt_sep" == $'\r' ]] && rdt_nl="bare CR"
  expect_both "PS delete on the line after Get-Location ($rdt_nl) blocks" 2 \
    --tool PowerShell --command "Get-Location${rdt_sep}Remove-Item -Recurse -Force C:\\"
  expect_both "PS delete on the line after a comment ($rdt_nl) blocks" 2 \
    --tool PowerShell --command "# note${rdt_sep}Remove-Item -Recurse -Force C:\\"
  expect_both "PS delete on the last of three lines ($rdt_nl) blocks" 2 \
    --tool PowerShell --command "Get-Location${rdt_sep}Get-ChildItem${rdt_sep}ri -r C:\\"
  expect_both "PS backtick continues the line ($rdt_nl): operand on the next line, allowed" 0 \
    --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse \`${rdt_sep}  ./build"
  expect_both "PS backtick continues the line ($rdt_nl): missing operand still blocks" 2 \
    --tool PowerShell --command "Remove-Item -Recurse \`${rdt_sep}  -Force"
  expect_both "PS two harmless lines ($rdt_nl) allowed" 0 \
    --tool PowerShell --command "Get-Location${rdt_sep}Get-ChildItem C:\\"
  expect_both "PS newline inside a quoted string is inert ($rdt_nl)" 0 \
    --tool PowerShell --command "Write-Output 'a${rdt_sep}Remove-Item -Recurse C:\\'"
  expect_both "PS newline after a pipe keeps the pipeline target ($rdt_nl)" 2 \
    --tool PowerShell --command "Get-Content list.txt |${rdt_sep}Remove-Item -Recurse"
  expect_both "PS newline after a pipe keeps the listing that feeds it ($rdt_nl)" 2 \
    --tool PowerShell --command "Get-ChildItem C:\\ |${rdt_sep}Remove-Item -Recurse"
  expect_both "PS newline after an unquoted comma continues the operand list ($rdt_nl)" 2 \
    --tool PowerShell --command "Remove-Item -Recurse -Path ./x,${rdt_sep}C:\\"
  expect_both "PS newline after a quoted comma ends the statement ($rdt_nl)" 2 \
    --tool PowerShell --command "Write-Output 'a,'${rdt_sep}Remove-Item -Recurse -Force C:\\"
done

# Scriptblocks, groupings and subexpressions.
expect_both 'PS if (...) { delete } blocks' 2 \
  --tool PowerShell --command 'if (Test-Path x) { Remove-Item -Recurse -Force C:\ }'
expect_both 'PS try { delete } catch blocks' 2 \
  --tool PowerShell --command 'try { Remove-Item -Recurse -Force C:\ } catch {}'
expect_both 'PS catch { delete } blocks' 2 \
  --tool PowerShell --command 'try { Get-Item x } catch { Remove-Item -Recurse -Force C:\ }'
expect_both 'PS else { delete } blocks' 2 \
  --tool PowerShell --command 'if ($ok) { Get-Item x } else { Remove-Item -Recurse -Force C:\ }'
expect_both 'PS ForEach-Object { delete } blocks' 2 \
  --tool PowerShell --command 'Get-ChildItem | ForEach-Object { Remove-Item -Recurse -Force C:\ }'
expect_both 'PS foreach loop { delete } blocks' 2 \
  --tool PowerShell --command 'foreach ($d in 1..3) { ri -r C:\ }'
expect_both 'PS & { delete } blocks' 2 \
  --tool PowerShell --command '& { Remove-Item -Recurse -Force C:\ }'
expect_both 'PS Start-Job { delete } blocks' 2 \
  --tool PowerShell --command 'Start-Job { Remove-Item -Recurse -Force C:\ }'
expect_both 'PS function body blocks' 2 \
  --tool PowerShell --command 'function Clear-It { Remove-Item -Recurse -Force C:\ }; Clear-It'
expect_both 'PS multi-line scriptblock blocks' 2 \
  --tool PowerShell --command $'if ($ok) {\n  Get-Location\n  Remove-Item -Recurse -Force C:\\\n}'
expect_both 'PS $(delete) subexpression blocks' 2 \
  --tool PowerShell --command '$(Remove-Item -Recurse -Force C:\)'
expect_both 'PS (delete) grouping blocks' 2 \
  --tool PowerShell --command '(Remove-Item -Recurse -Force C:\)'
expect_both 'PS @(delete) array subexpression blocks' 2 \
  --tool PowerShell --command '@(Remove-Item -Recurse -Force C:\)'
expect_both 'PS scriptblock delete of a bare variable blocks' 2 \
  --tool PowerShell --command 'Get-ChildItem | ForEach-Object { Remove-Item -Recurse -Force $_ }'
# portability-ok: Windows path string in a test fixture, not a regex/sed construct
expect_both 'PS scriptblock delete outside the tree blocks with a cwd' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'if ($ok) { Remove-Item -Recurse C:\Windows }'

# A delete whose target is a grouping stays refused. The `(` opens a nested level
# and its `)` hands the statement back with one placeholder word, so the
# arguments after a grouping still belong to their command. A positional
# grouping is refused with or without -Recurse, as it always was.
expect_both 'PS Remove-Item -Recurse (Join-Path $a b) blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse (Join-Path $a b)'
expect_both 'PS Remove-Item -Recurse $(Join-Path $a b) blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse $(Join-Path $a b)'
expect_both 'PS Remove-Item (Join-Path $a b) without -Recurse blocks (positional grouping, as before)' 2 \
  --tool PowerShell --command 'Remove-Item (Join-Path $a b)'
expect_both 'PS Remove-Item -Recurse -Path (Get-Item x) blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse -Path (Get-Item x)'
expect_both 'PS Remove-Item -Path (Join-Path $a b) -Recurse -Force blocks (arguments after the grouping)' 2 \
  --tool PowerShell --command 'Remove-Item -Path (Join-Path $a b) -Recurse -Force'
expect_both 'PS Remove-Item -Path (Join-Path $env:TEMP x) -Recurse blocks' 2 \
  --tool PowerShell --command 'Remove-Item -Path (Join-Path $env:TEMP x) -Recurse'
expect_both 'PS Remove-Item -Path (multi-line grouping) -Recurse blocks' 2 \
  --tool PowerShell --command $'Remove-Item -Path (\n  Join-Path $a b\n) -Recurse -Force'
expect_both 'PS Remove-Item -Recurse ./build (Get-Item x) blocks (a second, unknown operand)' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse ./build (Get-Item x)'
expect_both 'PS Remove-Item -Recurse "$(Join-Path $a b)" blocks (quoted subexpression)' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse "$(Join-Path $a b)"'
expect_both 'PS Remove-Item -Recurse ./a {x} C:\ blocks (a scriptblock argument does not end the statement)' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse ./a {x} C:\'
expect_both 'PS Remove-Item -Recurse -Path {scriptblock} blocks (its value is not known)' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse -Path {./x}'
expect_both 'PS a mismatched closer still hands the grouping back to Remove-Item' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse (Get-Item {x)}'
expect_both 'PS Remove-Item -Filter {..} -Recurse C:\ blocks (arguments after a scriptblock)' 2 \
  --tool PowerShell --command 'Remove-Item -Filter {*.tmp} -Recurse C:\'
expect_both 'PS if (...) { ... } Remove-Item -Recurse C:\ blocks (a } after if ends the statement)' 2 \
  --tool PowerShell --command 'if ($ok) { Get-Item x } Remove-Item -Recurse -Force C:\'
expect_both 'PS an unbalanced ( before a delete blocks' 2 \
  --tool PowerShell --command 'Get-Item ( ; Remove-Item -Recurse -Force C:\'
expect_both 'PS an unbalanced ) before a delete blocks' 2 \
  --tool PowerShell --command ') Remove-Item -Recurse -Force C:\'
expect_both 'PS a } before a delete blocks' 2 \
  --tool PowerShell --command '} Remove-Item -Recurse -Force C:\'
expect_both 'PS a grouping left open around a delete blocks' 2 \
  --tool PowerShell --command 'Get-Item ( Remove-Item -Recurse -Force C:\'
expect_both 'PS Remove-Item -Recurse -Path ./build -Filter {*.tmp} allowed with a cwd (scriptblock value of -Filter)' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'Remove-Item -Recurse -Path ./build -Filter {*.tmp} -Force'
# Groupings nest to MAX_SUBST_DEPTH and the cap refuses.
rdt_deep32=$(printf '(%.0s' {1..32})
rdt_deep33=$(printf '(%.0s' {1..33})
expect_both 'PS 32 nested groupings allowed' 0 \
  --tool PowerShell --command "Write-Output ${rdt_deep32}x rm"
expect_both 'PS 33 nested groupings refused' 2 \
  --tool PowerShell --command "Write-Output ${rdt_deep33}x rm"

# Controls that stay allowed.
expect_both 'PS Remove-Item -Recurse ./build allowed with a cwd' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'Remove-Item -Recurse ./build'
expect_both 'PS if ($ok) { Write-Output hi } allowed' 0 \
  --tool PowerShell --command 'if ($ok) { Write-Output hi }'
expect_both 'PS scriptblock delete of a relative path allowed with a cwd' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command 'if (Test-Path ./build) { Remove-Item -Recurse ./build }'
expect_both 'PS non-recursive delete in a scriptblock allowed' 0 \
  --tool PowerShell --command 'if ($ok) { Remove-Item C:\file.txt }'
expect_both 'PS quoted braces are inert' 0 \
  --tool PowerShell --command 'Write-Output "{ Remove-Item -Recurse C:\ }"'
expect_both 'PS quoted parentheses are inert' 0 \
  --tool PowerShell --command "Write-Output '(Remove-Item -Recurse C:\\)'"
expect_both 'PS multi-line scriptblock without a delete allowed' 0 \
  --tool PowerShell --command $'foreach ($d in 1..3) {\n  Get-Item $d\n}'

# `$env:NAME` and `${env:NAME}` are read as `$NAME` and `${NAME}`, so each spelling
# gets the answer the Bash lane gives (`rm -rf $X` blocks, `$X/`, `$X/*` block,
# `$X/build` and `${X}/build` pass). Each PowerShell row below runs beside the Bash
# row it mirrors, with and without a cwd. The four rows that allow a subpath
# (`$env:TEMP\build`, `$env:TEMP/build`, `$Env:TEMP\build` and
# `${env:LOCALAPPDATA}\cache\x`) match the Bash lane's `$X/build` and `${X}/build`,
# which are allowed.
while IFS='|' read -r rdt_want rdt_ps rdt_bash; do
  [[ -n "$rdt_ps" ]] || continue
  # The rows write a backslash as `~`.
  rdt_ps=${rdt_ps//\~/\\}
  for rdt_cwd_arm in none cwd; do
    rdt_args=()
    [[ "$rdt_cwd_arm" == cwd ]] && rdt_args=("${RDT_CWD[@]}")
    expect_both "PS Remove-Item -Recurse $rdt_ps is $rdt_want like rm -rf $rdt_bash ($rdt_cwd_arm)" "$rdt_want" \
      --tool PowerShell ${rdt_args[@]+"${rdt_args[@]}"} --command "Remove-Item -Recurse $rdt_ps"
    expect_both "Bash rm -rf $rdt_bash is $rdt_want ($rdt_cwd_arm)" "$rdt_want" \
      ${rdt_args[@]+"${rdt_args[@]}"} --command "rm -rf $rdt_bash"
  done
done <<'EOF'
2|$env:TEMP|$TEMP
2|$env:TEMP~|$TEMP/
2|$env:TEMP/|$TEMP/
2|$env:TEMP~*|$TEMP/*
2|$Env:TEMP|$TEMP
2|${env:TEMP}|${TEMP}
2|${env:TEMP}~|${TEMP}/
2|${env:TEMP}~*|${TEMP}/*
2|$env:TEMP~.|$TEMP/.
2|$env:TEMP~..|$TEMP/..
0|$env:TEMP~build|$TEMP/build
0|$env:TEMP/build|$TEMP/build
0|$Env:TEMP~build|$TEMP/build
0|${env:LOCALAPPDATA}~cache~x|${LOCALAPPDATA}/cache/x
EOF
# `(x86)` is legal inside a PowerShell `${env:...}` name and is no Bash spelling, so
# these two have no Bash row. The `(` inside the braces ends no statement.
expect_both 'PS Remove-Item -Recurse ${env:ProgramFiles(x86)} blocks (bare variable)' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse ${env:ProgramFiles(x86)}'
expect_both 'PS Remove-Item -Recurse ${env:ProgramFiles(x86)}\cache allowed' 0 \
  --tool PowerShell --command 'Remove-Item -Recurse ${env:ProgramFiles(x86)}\cache'

# --- 4a2. A literal `$` in a PowerShell target (#6626) ------------------------
# PowerShell expands nothing inside single quotes, and a backtick-escaped `$` is
# literal anywhere, so such a target is judged as the path it names instead of
# being left alone as an expansion. On Win32 a `::$INDEX_ALLOCATION` (or other
# `:<name>:$<TYPE>`) stream suffix names the file or directory before it, so the
# target is judged as that path. A `$` PowerShell would expand is still left
# alone, and a target made of a `$` name alone is still refused as a bare
# variable.
# portability-ok: Windows path strings in test fixtures, not regex/sed constructs
expect_both 'PS single-quoted outside target holding a $ blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse -Force 'D:\\rdt-x\\a\$b'"
expect_both 'PS ::$INDEX_ALLOCATION suffix on an outside directory blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse -Force 'D:\\rdt-x\\dir::\$INDEX_ALLOCATION'"
expect_both 'PS :$I30:$INDEX_ALLOCATION suffix on an outside directory blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse -Force 'D:\\rdt-x\\dir:\$I30:\$INDEX_ALLOCATION'"
expect_both 'PS backtick-escaped ::`$INDEX_ALLOCATION in double quotes blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse -Force \"D:\\rdt-x\\dir::\`\$INDEX_ALLOCATION\""
expect_both 'PS -LiteralPath with a ::$INDEX_ALLOCATION suffix blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -LiteralPath 'D:\\rdt-x\\dir::\$INDEX_ALLOCATION' -Recurse"
expect_both 'PS cmd /c rd /s on a single-quoted outside target holding a $ blocks' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command "cmd /c 'rd /s /q D:\\rdt-x\\a\$b'"
expect_both 'PS ::$INDEX_ALLOCATION on a drive root blocks with no cwd' 2 \
  --tool PowerShell --command "Remove-Item -Recurse -Force 'C:\\::\$INDEX_ALLOCATION'"
expect_both 'PS a drive letter before ::$INDEX_ALLOCATION blocks as the drive' 2 \
  --tool PowerShell --command "Remove-Item -Recurse -Force 'C::\$INDEX_ALLOCATION'"
expect_both 'PS ::$INDEX_ALLOCATION on a UNC share root blocks with no cwd' 2 \
  --tool PowerShell --command "Remove-Item -Recurse -Force '\\\\srv\\share::\$INDEX_ALLOCATION'" # portability-ok: Windows UNC path string in a test fixture
expect_both 'PS ::$INDEX_ALLOCATION on ~ blocks with no cwd' 2 \
  --tool PowerShell --command "Remove-Item -Recurse -Force '~::\$INDEX_ALLOCATION'"
# The literal-`$` marker byte is one the command does not carry, so a control
# byte in the command (here in a trailing comment) does not turn the reading off.
expect_both 'PS a \002 byte in the command does not turn the literal reading off' 2 \
  --tool PowerShell --command "Remove-Item -Recurse -Force 'C:\\::\$INDEX_ALLOCATION' # "$'\002'
rdt_all_ctl=$'\002\003\004\005\006\007\010\013\014\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037'
expect_both 'PS every marker byte in the command refuses a target holding a $' 2 \
  --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse -Force 'D:\\rdt-x\\a\$b' # $rdt_all_ctl"
expect_both 'PS every marker byte in the command still allows a target with no $' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse -Force './build' # $rdt_all_ctl"
expect_both 'PS -Recurse:'"'"'$false'"'"' is read as not recursive' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse:'\$false' D:\\rdt-x\\y"
expect_both 'PS single-quoted $ name alone still blocks (bare variable)' 2 \
  --tool PowerShell --command "Remove-Item -Recurse '\$X'"
# The literal reading only adds refusals: a target refused before #6626, when
# every `$` was read as an expansion, is refused still.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "PS refused before the literal reading still blocks: $rdt_cmd" 2 \
    --tool PowerShell "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
Remove-Item -Recurse '$env:TEMP'
Remove-Item -Recurse '$env:SystemDrive\'
Remove-Item -Recurse `$env:TEMP
Remove-Item -Recurse '$HOME\x'
Remove-Item -Recurse '$(x)'
cmd /c rd /s /q '$env:TEMP'
EOF
# Stay quiet: a literal `$` or stream suffix on a target inside the tree.
expect_both 'PS single-quoted in-tree target holding a $ allowed' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse -Force './build\$old'"
expect_both 'PS ::$INDEX_ALLOCATION suffix on an in-tree directory allowed' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse -Force './build::\$INDEX_ALLOCATION'"
# Unchanged: a `$` PowerShell expands is an expansion-built target, left alone.
expect_both 'PS double-quoted target with an expanding $ is left alone' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse \"D:\\rdt-x\\\$name\""
expect_both 'PS a literal and an expanding $ in one word is left alone' 0 \
  --tool PowerShell "${RDT_CWD[@]}" --command "Remove-Item -Recurse \"D:\\rdt-x\\\$name\`\$x\""

# --- 4b. Launchers read two ways, and four more launchers (#4685) -----------
# sg re-parses its one command word; setpriv, prlimit and systemd-run step
# over their own options; an abbreviated env --split-string is split; an
# ambiguous nsenter prefix, sudo's -R / --chroot, an operand-taking sudo
# cluster and an abbreviated sudo long option are each judged both as a flag
# and as taking the next word; and su's argv is read with and without
# POSIXLY_CORRECT, which an inherited environment can set. Each row is asserted
# without and with a payload cwd, because the outside-tree arm runs only with
# one.
while IFS='|' read -r rdt_want rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "launcher: $rdt_cmd" "$rdt_want" --command "$rdt_cmd"
  expect_both "launcher: $rdt_cmd, with cwd" "$rdt_want" "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
2|sg root -c 'rm -rf /'
2|sg root 'rm -rf /'
2|sg - root -c 'rm -rf /'
2|sg -l root 'rm -rf /*'
2|setpriv --reuid=0 rm -rf /
2|setpriv --reuid 0 rm -rf /
2|setpriv --reu 0 rm -rf /
2|setpriv --nnp --clear-groups rm -rf /
2|prlimit --nofile=10 rm -rf /
2|prlimit -n rm -rf /
2|prlimit --pid 1 rm -rf /
2|systemd-run rm -rf /
2|systemd-run --uid bob rm -rf /
2|systemd-run --ui bob rm -rf /
2|systemd-run -u x -p A=b rm -rf /
2|systemd-run -tu x rm -rf /
2|systemd-run --scope --user rm -rf /*
2|env --spl='rm -rf /'
2|env --s 'rm -rf /'
2|env -a x rm -rf /
2|env --argv0 x rm -rf /
2|nsenter --t 1 rm -rf /*
2|POSIXLY_CORRECT=1 su -s env x su -s env x rm -rf /
2|su -s env x su -s env x rm -rf /
2|sudo -R /mnt rm -rf /
2|sudo --chroot /mnt rm -rf /
2|sudo -Eu bob rm -rf /
2|sudo --us bob rm -rf /
2|sudo -a x rm -rf /
2|sudo -iu bob rm -rf /
2|sudo -R rm -rf /
2|sudo --chroot rm -rf /
2|sudo -Eu rm -rf /
2|sudo --login rm -rf /
2|sudo -u bob rm -rf /
2|env --split-string='rm -rf /'
2|nsenter --target 1 rm -rf /*
0|sg root -c 'ls /'
0|sg root rm -rf /
0|sg root
0|setpriv --reuid=0 ls
0|prlimit --nofile=10 ls
0|systemd-run ls
0|env --spl='ls /'
0|nsenter --t 1 ls
0|sudo -R /mnt ls
0|sudo -Eu bob ls
0|sudo --us bob ls
0|su -s env x ls
EOF
# `sg root rm -rf /` runs `rm` alone: sg hands only the word after the group
# to `sh -c`. From a cwd, `rm -rf /etc` is outside the tree, through a
# launcher as bare.
expect_both 'launcher: sg root -c rm -rf /etc, with cwd' 2 "${RDT_CWD[@]}" --command "sg root -c 'rm -rf /etc'"
expect_both 'launcher: setpriv --reuid=0 rm -rf /etc, with cwd' 2 "${RDT_CWD[@]}" --command 'setpriv --reuid=0 rm -rf /etc'
expect_both 'launcher: sg - root -c rm -rf ./build from a cwd is not followed' 0 "${RDT_CWD[@]}" \
  --command "sg - root -c 'rm -rf ./build'"

# --- 4c. Launcher lines refused by decision (#4681) --------------------------
# The guard header records why each stays refused: chrt rejects a non-digit
# word after a realtime policy (and runs it under -o / -b / -i / -d / -e from
# util-linux 2.42), runuser rejects a permuted `-rf` unless POSIXLY_CORRECT is
# inherited, and chroot's `/` is host `<dir>` plus whatever is bind-mounted in
# it. Pinned so loosening any of them is a deliberate change to this table.
while IFS='|' read -r rdt_want rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "decided: $rdt_cmd" "$rdt_want" --command "$rdt_cmd"
  expect_both "decided: $rdt_cmd, with cwd" "$rdt_want" "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
2|chrt -r rm -rf /
2|chrt --rr rm -rf /
2|chrt -f rm -rf /
2|chrt rm -rf /
2|chrt -o rm -rf /
2|chrt -b rm -rf /*
2|runuser -u bob rm -rf /
2|runuser -u bob rm -rf /*
2|POSIXLY_CORRECT=1 runuser -u bob rm -rf /
2|chroot /mnt rm -rf /
2|chroot /mnt rm -rf /*
2|chroot /mnt rm -rf --no-preserve-root /
0|chrt -r 5 ls /
0|runuser -u bob -- ls /
0|chroot /mnt ls /
EOF

# A -match regex is text, not a path. It is allowed beside a literal-target delete,
# and a refusal for some other reason never names the regex as a system path.
PS_RX="-match '^[a-z0-9]{8}\.[a-z0-9]{3}\$'"
expect_both 'PS regex pipeline with -LiteralPath $_.FullName delete allowed' 0 --tool PowerShell \
  --command "Get-ChildItem C:\\Temp\\x | Where-Object { \$_.Name $PS_RX } | ForEach-Object { Remove-Item -LiteralPath \$_.FullName -Recurse -Force }"
expect_both 'PS literal safe Remove-Item -Recurse beside the regex allowed' 0 --tool PowerShell \
  --command "Remove-Item -Recurse -Force ./build; Get-ChildItem | Where-Object { \$_.Name $PS_RX }"
guard_invoke --tool PowerShell \
  --command "Remove-Item -Recurse -Force C:\\; Get-ChildItem | Where-Object { \$_.Name $PS_RX }"
assert_exit "PS regex beside a root delete still blocks" 2 "$GUARD_RC"
assert_absent "PS block message does not name the regex as a path" "$GUARD_ERR" '^[a-z0-9]'

# --- 5. Fail-closed inputs ---------------------------------------------------
rc=0
bash "$HOOK" </dev/null >/dev/null 2>&1 || rc=$?
assert_exit "empty stdin is a skip, not a block" 0 "$rc"

expect "a stdin body that is not JSON fails closed" 2 --payload 'not json'

rc=0
bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{}}' >/dev/null 2>&1 || rc=$?
assert_exit "payload with no command is a skip" 0 "$rc"

# `X=build && rm -rf "$X"` deletes `build`, so it is judged as `build`, but
# only when the command opens with `NAME=LITERAL SEP` and nothing after it can
# change NAME.
expect_both 'X=build && rm -rf "$X" allowed' 0 "${RDT_CWD[@]}" --command 'X=build && rm -rf "$X"'
expect_both 'X=build; rm -rf "$X/" allowed' 0 "${RDT_CWD[@]}" --command 'X=build; rm -rf "$X/"'
expect_both "X='build' && rm -rf \"\$X/out\" allowed" 0 "${RDT_CWD[@]}" --command "X='build' && rm -rf \"\$X/out\""
expect_both 'a literal on its own line, then the delete, allowed' 0 "${RDT_CWD[@]}" \
  --command $'X=build\nrm -rf "$X"'
# An unquoted operand binds nothing: an inherited IFS can split `$X` into
# other words, so only the double-quoted forms take the literal.
expect_both 'X=build && rm -rf $X blocks (unquoted)' 2 "${RDT_CWD[@]}" --command 'X=build && rm -rf $X'
expect_both 'X=build; rm -rf $X/ blocks (unquoted)' 2 "${RDT_CWD[@]}" --command 'X=build; rm -rf $X/'
expect_both 'X=build && rm -rf "$X"/ blocks (suffix outside the quotes)' 2 "${RDT_CWD[@]}" \
  --command 'X=build && rm -rf "$X"/'
expect "attended: an unquoted operand asks" 0 "${RDT_CWD[@]}" \
  --command 'X=build && rm -rf $X' -- CLAUDE_CODE_SESSION_ATTENDED=1
assert_eq "attended: an unquoted operand's decision is ask" ask \
  "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$GUARD_OUT")"
# Outside that shape nothing binds, and the variable blocks as a bare variable.
expect_both 'X="build" && rm -rf "${X}" blocks (a braced expansion)' 2 "${RDT_CWD[@]}" \
  --command 'X="build" && rm -rf "${X}"'
expect_both 'two literals, then rm -rf "$A" "$B" blocks' 2 "${RDT_CWD[@]}" \
  --command "A=build B='dist' && rm -rf \"\$A\" \"\$B/x\""
expect_both 'readonly, then the literal, blocks' 2 "${RDT_CWD[@]}" --command 'readonly X=/etc; X=build; rm -rf "$X"'
expect_both 'export NAME=literal && rm blocks' 2 "${RDT_CWD[@]}" --command 'export X=build && rm -rf "$X"'
expect_both 'a second variable in the delete blocks' 2 "${RDT_CWD[@]}" --command 'X=build && rm -rf "$X" "$Y"'
expect_both 'a second delete of the bound variable allowed (#9779)' 0 "${RDT_CWD[@]}" \
  --command 'X=build && rm -rf "$X" && rm -rf "$X"'
expect_both 'a glob after the variable blocks' 2 "${RDT_CWD[@]}" --command 'X=build && rm -rf $X*'
expect_both 'a comment after the delete allowed (#9779)' 0 "${RDT_CWD[@]}" --command 'X=build &&rm -rf "$X" # c'
expect_both 'a comment naming $X unquoted blocks' 2 "${RDT_CWD[@]}" --command 'X=build &&rm -rf "$X" # $X'
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
expect_both 'an unquoted use of the name elsewhere blocks' 2 "${RDT_CWD[@]}" \
  --command 'S=/tmp/rdt-scratch; echo $S; rm -rf "$S"'
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
expect_both 'an assignment after another statement blocks' 2 "${RDT_CWD[@]}" \
  --command 'mkdir -p /tmp/rdt-scratch; S=/tmp/rdt-scratch; rm -rf "$S"'
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
expect_both 'a plain statement line before the literal blocks' 2 "${RDT_CWD[@]}" \
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

# --- 5d. Guards stay on in auto mode -------------------------------------------
expect_both "auto mode: rm -rf / still blocks" 2 \
  --payload '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"},"permission_mode":"auto"}'

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

echo "host-conditional groups skipped: $rdt_skips"
report
