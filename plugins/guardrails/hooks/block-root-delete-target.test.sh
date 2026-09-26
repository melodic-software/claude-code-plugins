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
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

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
# priority), refused anyway because underblocking is the costlier mistake.
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
# chroot takes NEWROOT. `chroot /mnt rm -rf /` deletes /mnt on the host rather
# than the host root, and is refused anyway: a known overblock, kept on the
# refusal side.
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
# CDPATH can send a relative cd anywhere the command itself names, so a
# relative delete after such a cd is refused rather than guessed; a cd spelled
# with ./ ignores CDPATH and is still followed. A non-literal cd "$d" still
# leaves the delete alone.
expect_both 'cdpath: an inline CDPATH prefix refuses a later relative delete' 2 "${RDT_CWD[@]}" \
  --command 'CDPATH=/c cd Windows && rm -rf x'
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
# The judgment is time-bounded in the parse too: a command that parses slowly
# refuses rather than outrunning the hook timeout. Pinned in the source, since
# no payload under MAX_COMMAND_LEN parses for twelve seconds on a fast host.
assert_contains "the deadline is twelve seconds" "$(grep -n '^RDT_DEADLINE=' "$HOOK")" "RDT_DEADLINE=12"
assert_contains "the parse callback checks the deadline" \
  "$(sed -n '/^rdt_check_segment() {/,/^}/p' "$HOOK")" "rdt_deadline"
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

# rdt_pl <command> <cwd> [scratchpad_dir]: a payload with the harness's
# optional fields. MSYS_NO_PATHCONV keeps Git Bash from rewriting a POSIX path
# argument for a native jq.
rdt_pl() {
  if (($# > 2)); then
    MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$2" --arg s "$3" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,scratchpad_dir:$s}'
  else
    MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}'
  fi
}
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
  else
    rdt_skip "ln -s made no link to an existing directory (4 cases)"
  fi
  rm -f "$rdt_ln/dang"
else
  rdt_skip "ln -s makes no real symlink on this host (12 cases)"
fi
# A glob before the last component over real directories under temp allowed.
mkdir -p "$TEST_TMPDIR/g4ok/real"
expect_both 'glob: */x over real directories under temp allowed' 0 --cwd "$TEST_TMPDIR/g4ok" --command 'rm -rf */x'
expect_both 'glob: */* over real directories under temp allowed' 0 --cwd "$TEST_TMPDIR/g4ok" --command 'rm -rf */*'

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
2|rm -rf \\server\share
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

# --- 3. The block message ----------------------------------------------------
guard_invoke --command 'rm -rf /'
assert_exit "blocked case exits 2" 2 "$GUARD_RC"
assert_contains "blocked case names the BLOCKED token" "$GUARD_ERR" "BLOCKED:"

# --- 4. Tool gating: the declared PowerShell gap ------------------------------
# Remove-Item -Recurse -Force and `rd /s` are the same hazard through the
# PowerShell tool, and this guard does not cover them: it exits on a non-Bash
# tool_name, which also keeps it out of the PowerShell classifier path entirely.
# Pinned so widening it later is a deliberate change to this line.
expect "PowerShell payload is a declared gap, not a block" 0 \
  --tool PowerShell --command 'Remove-Item -Recurse -Force C:\'

# sudo spellings that stay declared gaps. Reading each one correctly means
# treating the word after it as an operand, which changes how sudo lines the
# guard refuses today are read (`sudo -R rm -rf /` would read `rm` as the
# chroot directory), and this guard only ever adds refusals. Pinned so widening
# any of them later is a deliberate change to these lines.
expect_both 'sudo -R is a declared gap' 0 --command 'sudo -R /mnt rm -rf /'
expect_both 'sudo --chroot is a declared gap' 0 --command 'sudo --chroot /mnt rm -rf /'
expect_both 'sudo -Eu cluster is a declared gap' 0 --command 'sudo -Eu bob rm -rf /'
expect_both 'sudo abbreviated --us is a declared gap' 0 --command 'sudo --us bob rm -rf /'

# --- 5. Fail-closed inputs ---------------------------------------------------
rc=0
bash "$HOOK" </dev/null >/dev/null 2>&1 || rc=$?
assert_exit "empty stdin is a skip, not a block" 0 "$rc"

expect "a stdin body that is not JSON fails closed" 2 --payload 'not json'

rc=0
bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{}}' >/dev/null 2>&1 || rc=$?
assert_exit "payload with no command is a skip" 0 "$rc"

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
