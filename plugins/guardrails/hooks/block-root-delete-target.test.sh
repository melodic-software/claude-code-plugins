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

# An operand that normalizes to EMPTY is not a root, and a recursive delete
# with no operand at all has nothing to match.
expect_both 'rm -rf "" allowed' 0 --command 'rm -rf ""'
expect_both 'rm -rf allowed (no operand)' 0 --command 'rm -rf'

# A trailing segment that carries a NAME stops the reduction, so these stay
# ordinary relative or nested deletes rather than roots.
expect_both 'rm -rf /tmp* allowed' 0 --command 'rm -rf /tmp*'
expect_both 'rm -rf ~/proj* allowed' 0 --command 'rm -rf ~/proj*'
expect_both 'rm -rf /c/dev/* allowed' 0 --command 'rm -rf /c/dev/*'
expect_both 'rm -rf /_ allowed (a directory named _)' 0 --command 'rm -rf /_'
expect_both 'rm -rf * allowed (cwd-relative, a declared gap)' 0 --command 'rm -rf *'
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
# An empty operand from a QUOTED span is not a dropped backslash, through eval
# as anywhere else, so the restore must key on provenance rather than emptiness.
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

report
