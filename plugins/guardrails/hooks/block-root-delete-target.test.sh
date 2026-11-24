#!/usr/bin/env bash
# Contract test for block-root-delete-target.sh (guardrails plugin), part a of 6:
# sections 1 to 2b, less the nesting and size-budget cases of section 1 and the
# python and node heredoc cases of section 2, which are part f. The parts are block-root-delete-target.test.sh and
# block-root-delete-target-b.test.sh to -f.test.sh; block-root-delete-target-fixtures.sh
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

expect_both 'rm -rf "\\" blocks' 2 --command 'rm -rf "\\"'
expect_both 'rm -rf \\ blocks' 2 --command 'rm -rf \\'
expect_both 'rm -rf / blocks' 2 --command 'rm -rf /'
expect_both 'a shell here-doc after a substitution here-doc blocks' 2 --command $'X=$(true <<A\nx\nA\n) bash <<A\nrm -rf /\nA'
expect_both 'a shell here-doc after a body-nested here-doc blocks' 2 --command $'cat <<E\n$(cat <<F\nf\nF\n)\nE\nbash <<G\nrm -rf /\nG'
expect_both 'a shell here-doc beside a redirect-only one and a joined body blocks' 2 --command $'<<A\nz\nA\nbash <<A\nrm -rf /\nA\ncat <<A\nx\\\ny\nA'
expect_both 'a shell here-doc beside a redirect-only one and a pattern here-doc blocks' 2 --command $'<<A\nz\nA\nbash <<A\nrm -rf /\nA\necho @(cat <<B\nb\nB\n)'
expect_both 'a shell here-doc inside a command-start !(…) blocks' 2 --command $'!(bash <<A\nrm -rf /\nA\n)'
expect_both 'a shell here-doc beside a harmless one is allowed' 0 --command $'cat <<A\ndocs\nA\nbash <<B\necho hi\nB'
guard_invoke --command $'bash <<\'EOF\'\necho "`the form check (x)`"\nEOF'
assert_exit "a shell here-doc shfmt rejects is refused" 2 "$GUARD_RC"
assert_contains "the refusal names the guard" "$GUARD_ERR" "block-root-delete-target"
assert_contains "the refusal says the text was lifted" "$GUARD_ERR" "lifted"
expect_both 'rm -rf /* blocks' 2 --command 'rm -rf /*'
expect_both 'rm -rf "//" blocks' 2 --command 'rm -rf "//"'

expect_both 'rm -r / blocks' 2 --command 'rm -r /'
expect_both 'rm --recursive / blocks' 2 --command 'rm --recursive /'
expect_both 'rm -Rf / blocks (capital R)' 2 --command 'rm -Rf /'
expect_both 'rm -rf -- / blocks (end of options)' 2 --command 'rm -rf -- /'

expect_both 'rm -rf ~ blocks' 2 --command 'rm -rf ~'
expect_both 'rm -rf $HOME blocks' 2 --command 'rm -rf $HOME'
expect_both 'rm -rf "$HOME" blocks' 2 --command 'rm -rf "$HOME"'
expect_both 'rm -rf ${HOME} blocks' 2 --command 'rm -rf ${HOME}'

expect_both 'rm -rf C:\ blocks' 2 --command 'rm -rf C:\'
expect_both 'rm -rf c:/ blocks' 2 --command 'rm -rf c:/'
expect_both 'rm -rf C: blocks' 2 --command 'rm -rf C:'
expect_both 'rm -rf /c blocks (MSYS drive root)' 2 --command 'rm -rf /c'
expect_both 'rm -rf /c/* blocks' 2 --command 'rm -rf /c/*'
expect_both 'rm -rf /mnt/c blocks (WSL drive root)' 2 --command 'rm -rf /mnt/c'
expect_both 'rm -rf /cygdrive/c blocks' 2 --command 'rm -rf /cygdrive/c'

expect_both 'sudo rm -rf / blocks' 2 --command 'sudo rm -rf /'
expect_both 'env rm -rf / blocks' 2 --command 'env rm -rf /'
expect_both '/bin/rm -rf / blocks' 2 --command '/bin/rm -rf /'
expect_both 'rm.exe -rf / blocks' 2 --command 'rm.exe -rf /'
expect_both '\rm -rf / blocks (quote-escaped name)' 2 --command '\rm -rf /'

expect_both 'cd foo && rm -rf / blocks' 2 --command 'cd foo && rm -rf /'

expect_both 'brace group blocks' 2 --command '{ rm -rf /; }'
expect_both 'if/then blocks' 2 --command 'if true; then rm -rf /; fi'
expect_both 'if/else blocks' 2 --command 'if false; then :; else rm -rf /; fi'
expect_both 'if/elif blocks' 2 --command 'if false; then :; elif rm -rf /; then :; fi'
expect_both 'while/do blocks' 2 --command 'while :; do rm -rf /; done'
expect_both 'until blocks' 2 --command 'until rm -rf /; do :; done'
expect_both 'for/do blocks' 2 --command 'for d in a b; do rm -rf /; done'
expect_both 'negation blocks' 2 --command '! rm -rf /'
expect_both 'function definition blocks' 2 --command 'f() { rm -rf /; }; f'
expect_both 'function keyword definition blocks' 2 --command 'function f { rm -rf /; }; f'
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

expect_both 'rm -rf ./ok / blocks on the second operand' 2 --command 'rm -rf ./ok /'

expect_both 'rm -rf --no-preserve-root ./x blocks' 2 --command 'rm -rf --no-preserve-root ./x'

expect_both 'rm -rf /*/ blocks' 2 --command 'rm -rf /*/'
expect_both 'rm -rf /./* blocks' 2 --command 'rm -rf /./*'
expect_both 'rm -rf /.[!.]* blocks (dotfile idiom)' 2 --command 'rm -rf /.[!.]*'
expect_both 'rm -rf ~/./* blocks' 2 --command 'rm -rf ~/./*'
expect_both 'rm -rf /c/*/ blocks' 2 --command 'rm -rf /c/*/'
expect_both 'rm -rf /. blocks' 2 --command 'rm -rf /.'
expect_both 'rm -rf /.. blocks' 2 --command 'rm -rf /..'

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
expect_both 'nice --adj rm -rf /* blocks' 2 --command 'nice --adj rm -rf /*'
expect_both 'ionice --cl rm -rf /* blocks' 2 --command 'ionice --cl rm -rf /*'
expect_both 'env --ch rm -rf /* blocks' 2 --command 'env --ch rm -rf /*'
expect_both 'stdbuf --ou rm -rf /* blocks' 2 --command 'stdbuf --ou rm -rf /*'
expect_both 'timeout --k 1 rm -rf /* blocks' 2 --command 'timeout --k 1 rm -rf /*'
expect_both 'nice --adj 5 ls / allowed' 0 --command 'nice --adj 5 ls /'
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

expect_both 'echo "$(rm -rf /)" blocks' 2 --command 'echo "$(rm -rf /)"'
expect_both 'echo $(rm -rf /) blocks' 2 --command 'echo $(rm -rf /)'
expect_both 'backtick substitution blocks' 2 --command 'echo `rm -rf /`'
expect_both 'nested substitution blocks' 2 --command 'echo "$(echo "$(rm -rf /)")"'
expect_both 'substitution with --no-preserve-root blocks' 2 \
  --command 'echo "$(rm -rf --no-preserve-root /)"'
expect_both 'substitution in an assignment blocks' 2 --command 'x="$(rm -rf ~)"'

expect_both 'quoted paren inside a substitution body blocks' 2 \
  --command "echo \"\$(printf '%s\n' ')'; rm -rf --no-preserve-root /)\""
expect_both 'quoted paren then a root operand blocks' 2 \
  --command "echo \"\$(printf ')'; rm -rf /)\""

expect_both 'substitution nested 3 deep is still parsed' 2 \
  --command 'echo "$(echo "$(echo "$(rm -rf /)")")"'

# `eval` runs its arguments in THIS shell, so the child-shell unwrap never
# applies to it: there is no -c and no new process.
expect_both 'eval "rm -rf /" blocks' 2 --command 'eval "rm -rf /"'
expect_both 'eval rm -rf / blocks (unquoted)' 2 --command 'eval rm -rf /'
expect_both 'nested eval blocks' 2 --command 'eval "eval \"rm -rf /\""'
expect_both 'eval with an ordinary delete allowed' 0 --command 'eval "rm -rf ./build"'
expect_both 'eval rm -rf \ blocks (dangling backslash through eval)' 2 --command 'eval rm -rf \'
expect_both 'eval "rm -rf" \ blocks' 2 --command 'eval "rm -rf" \'
expect_both 'eval rm -rf "\\" blocks' 2 --command 'eval rm -rf "\\"'
expect_both "eval 'rm -rf \\' blocks" 2 --command "eval 'rm -rf \\'"

expect_both 'bash -c rm -rf / blocks' 2 --command 'bash -c "rm -rf /"'
expect_both 'sh -c rm -rf / blocks' 2 --command "sh -c 'rm -rf /'"
expect_both 'bash -lc rm -rf / blocks' 2 --command 'bash -lc "rm -rf /"'
expect_both 'sudo bash -c rm -rf / blocks' 2 --command 'sudo bash -c "rm -rf /"'
expect_both 'wsl rm -rf / blocks' 2 --command 'wsl rm -rf /'
expect_both 'wsl.exe -e rm -rf / blocks' 2 --command 'wsl.exe -e rm -rf /'
expect_both 'wsl -d Ubuntu -- sudo rm -rf / blocks' 2 --command 'wsl -d Ubuntu -- sudo rm -rf /'
expect_both 'wsl ls / allowed' 0 --command 'wsl ls /'

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
expect_both 'su with two -c, the second a delete, blocks' 2 --command "su bob -c true -c 'rm -rf /*'"
expect_both 'su -w -c -c blocks' 2 --command "su -w -c -c 'rm -rf /*'"
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

expect_both "runuser -c rm -rf / blocks" 2 --command "runuser -c 'rm -rf /'"
expect_both 'taskset 1 rm -rf / blocks' 2 --command 'taskset 1 rm -rf /'
expect_both 'runuser bob -c rm -rf / blocks' 2 --command "runuser bob -c 'rm -rf /'"
expect_both 'runuser - bob -c rm -rf / blocks' 2 --command "runuser - bob -c 'rm -rf /'"
expect_both 'runuser -lc rm -rf / blocks' 2 --command "runuser -lc 'rm -rf /'"
expect_both 'runuser --command= rm -rf / blocks' 2 --command "runuser --command='rm -rf /'"
expect_both 'runuser --session-c rm -rf / blocks' 2 --command "runuser --session-c 'rm -rf /'"
expect_both '/usr/sbin/runuser -c rm -rf / blocks' 2 --command "/usr/sbin/runuser -c 'rm -rf /'"
expect_both 'RUNUSER.exe -c rm -rf / blocks' 2 --command "RUNUSER.exe -c 'rm -rf /'"
expect_both 'sudo runuser -c rm -rf / blocks' 2 --command "sudo runuser -c 'rm -rf /'"
expect_both 'nice -n 5 runuser -c rm -rf / blocks' 2 --command "nice -n 5 runuser -c 'rm -rf /'"
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
expect_both 'runuser -u bob rm -- -rf /* blocks (permuted)' 2 --command 'runuser -u bob rm -- -rf /*'
expect_both 'runuser rm -u bob -- -rf /* blocks (permuted)' 2 --command 'runuser rm -u bob -- -rf /*'
expect_both 'runuser -mu cluster blocks' 2 --command 'runuser -mu bob -- rm -rf /'
expect_both 'runuser --u bob blocks (abbreviated --user)' 2 --command 'runuser --u bob -- rm -rf /'
expect_both 'runuser --us=bob blocks' 2 --command 'runuser --us=bob -- rm -rf /'
expect_both 'POSIXLY_CORRECT runuser rm --recursive blocks' 2 \
  --command 'POSIXLY_CORRECT=1 runuser -u bob rm --recursive --force /*'
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
expect_both 'flock -- /tmp/l -c blocks' 2 --command "flock -- /tmp/l -c 'rm -rf /*'"
expect_both 'flock -n -- /tmp/l --command blocks' 2 --command "flock -n -- /tmp/l --command 'rm -rf /*'"
expect_both 'flock -- /tmp/l -c ls allowed' 0 --command "flock -- /tmp/l -c 'ls /'"
expect_both 'flock --wa 5 blocks' 2 --command 'flock --wa 5 /tmp/l rm -rf /*'
expect_both 'flock --tim 5 blocks' 2 --command 'flock --tim 5 /tmp/l rm -rf /*'
expect_both 'nsenter --ta 1 blocks' 2 --command 'nsenter --ta 1 rm -rf /*'
expect_both 'unshare --roo /mnt blocks' 2 --command 'unshare --roo /mnt rm -rf /*'
expect_both 'numactl --memb 0 blocks' 2 --command 'numactl --memb 0 rm -rf /*'
expect_both 'chroot --user a:b / blocks' 2 --command 'chroot --user a:b / rm -rf /*'
expect_both 'chrt --sched-r 5 -d 0 blocks' 2 --command 'chrt --sched-r 5 -d 0 rm -rf /*'
expect_both 'nsenter --ta 1 ls / allowed' 0 --command 'nsenter --ta 1 ls /'
expect_both 'nsenter --ta rm -rf / blocks (plain reading)' 2 --command 'nsenter --ta rm -rf /'
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
expect_both 'chroot / rm -rf / blocks' 2 --command 'chroot / rm -rf /'
expect_both 'chroot /mnt rm -rf / blocks (known overblock)' 2 --command 'chroot /mnt rm -rf /'
expect_both 'chroot --userspec bob:bob /mnt rm -rf / blocks' 2 --command 'chroot --userspec bob:bob /mnt rm -rf /'
expect_both 'chroot -- / rm -rf / blocks' 2 --command 'chroot -- / rm -rf /'
expect_both 'the whole launcher family stacked blocks' 2 \
  --command 'flock /tmp/l chrt 5 unshare nsenter -t 1 chroot / numactl -l taskset 1 runuser -u bob -- rm -rf /'

# The command word is compared case-insensitively, so the substring prefilter
# in front of the parse must be too. On the Windows host this guard was written
# for, the filesystem and PATH lookup are case-insensitive and `RM` runs rm.
expect_both 'RM -rf / blocks (upper case)' 2 --command 'RM -rf /'
expect_both 'Rm.exe -rf C:\ blocks (mixed case)' 2 --command 'Rm.exe -rf C:\'
expect_both 'busybox rm -rf / blocks' 2 --command 'busybox rm -rf /'
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

expect_both 'rm -rf //server/share blocks' 2 --command 'rm -rf //server/share'
# Single-quoted, because an UNQUOTED backslash-backslash-server form is not a
# UNC path to bash at all: the escapes collapse it to `\servershare`, and that
# is what rm would receive. The quoted spelling is the one that reaches the
# share, and both verdicts are pinned so the difference stays deliberate.
# portability-ok: a literal backslash pair inside a UNC path, not a grep -E escape
expect_both 'quoted UNC share root blocks' 2 --command "rm -rf '\\\\server\\share'"
# portability-ok: a literal backslash pair inside a UNC path, not a grep -E escape
expect_both 'unquoted UNC-looking path allowed (its escapes collapse)' 0 --command 'rm -rf \\server\share'

expect_both 'git commit -m "rm -rf /" allowed' 0 --command 'git commit -m "rm -rf /"'
expect_both 'echo "rm -rf /" allowed' 0 --command 'echo "rm -rf /"'
expect_both 'echo rm allowed' 0 --command 'echo rm'

expect_both 'rm -rf ./build dist allowed' 0 --command 'rm -rf ./build dist'
expect_both 'rm -rf build/ allowed' 0 --command 'rm -rf build/'
expect_both 'rm -rf /tmp/x allowed' 0 --command 'rm -rf /tmp/x'
expect_both 'rm -rf "$TMPDIR/x" allowed' 0 --command 'rm -rf "$TMPDIR/x"'
expect_both 'rm -rf ~/.cache/foo allowed' 0 --command 'rm -rf ~/.cache/foo'
expect_both 'rm -rf $HOME/x allowed' 0 --command 'rm -rf $HOME/x'
expect_both 'rm -rf C:/build/x allowed' 0 --command 'rm -rf C:/build/x'
expect_both 'rm -rf /c/build/x allowed' 0 --command 'rm -rf /c/build/x'

expect_both 'rm -f /file allowed' 0 --command 'rm -f /file'
expect_both 'rm / allowed (no recursion)' 0 --command 'rm /'

expect_both 'rm -rf allowed (no operand)' 0 --command 'rm -rf'

expect_both 'rm -rf /tmp* allowed' 0 --command 'rm -rf /tmp*'
expect_both 'rm -rf ~/proj* allowed' 0 --command 'rm -rf ~/proj*'
expect_both 'rm -rf /c/dev/* allowed' 0 --command 'rm -rf /c/dev/*'
expect_both 'rm -rf /_ allowed (a directory named _)' 0 --command 'rm -rf /_'
expect_both 'rm -rf * allowed (cwd-relative, no payload cwd)' 0 --command 'rm -rf *'
expect_both 'rm -rf /c* allowed' 0 --command 'rm -rf /c*'
expect_both 'rm -rf ~* allowed' 0 --command 'rm -rf ~*'
expect_both 'bash -c rm -rf ./build allowed' 0 --command 'bash -c "rm -rf ./build"'
expect_both 'sudo -u bob ls / allowed' 0 --command 'sudo -u bob ls /'
expect_both 'rm -rf //server/share/dir allowed' 0 --command 'rm -rf //server/share/dir'
# An arithmetic expansion is not a command substitution and carries no command.
expect_both 'arithmetic expansion allowed' 0 --command 'echo "$((1 + 2))"'
expect_both 'arithmetic inside a substitution allowed' 0 --command 'echo "$(echo $((1 + 2)))"'
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
expect_both "quoted heredoc fed to bash blocks" 2 --command $'bash <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc piped into sh blocks" 2 --command $'cat <<\'EOF\' | sh\necho `rm -rf /`\nEOF'
expect_both "quoted heredoc run through bash -c blocks" 2 --command $'bash -c "$(cat <<\'EOF\'\necho `rm -rf /`\nEOF\n)"'
expect_both "quoted heredoc fed to git blocks" 2 --command $'git x <<\'EOF\'\necho `rm -rf /`\nEOF'
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
# Bash re-reads `((…) )` and `$((…) )` as nested subshells, so their redirections are real.
expect_both "here-string inside a ((…) ) subshell blocks" 2 --command "((bash <<< 'rm -rf ~') )"
expect_both "here-string inside a \$((…) ) substitution blocks" 2 --command "echo \$((bash <<< 'rm -rf ~') )"
# A `))` inside backticks does not end the ((…) ) text.
expect_both "here-string in a ((…) ) holding a backticked )) blocks" 2 --command "((\`:))\`; bash <<< 'rm -rf ~') )"
expect_both "here-string in a \$((…) ) holding a backticked )) blocks" 2 --command "echo \$((\`:))\`; bash <<< 'rm -rf ~') )"
expect_both 'benign 3-deep substitution allowed' 0 --command 'echo "$(echo "$(echo rm)")"'
# `coproc NAME <simple command>` is not the NAME form at all: bash runs a
# command named `shredder` and hands it the rest, so this names no `rm`.
expect_both 'coproc NAME ahead of a simple command allowed' 0 --command 'coproc shredder rm -rf /'
expect_both 'coproc NAME with an ordinary delete allowed' 0 --command 'coproc shredder rm -rf ./build'
# GNU env's -S operand is a COMMAND, split and run, not an opaque argument.
expect_both 'env -S with an ordinary command allowed' 0 --command "env -S 'ls /'"
expect_both 'env -S with an ordinary delete allowed' 0 --command "env -S 'rm -rf ./build'"
expect_both 'sudo --user root ls / allowed' 0 --command 'sudo --user root ls /'
expect_both 'substitution with an ordinary delete allowed' 0 --command 'echo "$(rm -rf ./build)"'
expect_both 'rm --force / allowed (no recursion)' 0 --command 'rm --force /'
expect_both 'rm --dir / allowed (no recursion)' 0 --command 'rm --dir /'

expect_both 'perm -rf / allowed' 0 --command 'perm -rf /'
expect_both 'rmdir / allowed' 0 --command 'rmdir /'
expect_both 'git rm -rf src allowed (command word is git)' 0 --command 'git rm -rf src'

expect_both 'ls -R / allowed' 0 --command 'ls -R /'

expect_both 'brace group with an ordinary delete allowed' 0 --command '{ rm -rf ./build; }'
expect_both 'if/then with an ordinary delete allowed' 0 --command 'if true; then rm -rf ./build; fi'
expect_both 'su -c with an ordinary delete allowed' 0 --command "su -c 'rm -rf ./build'"
expect_both 'su with no -c allowed' 0 --command 'su bob ls /'
# `--s` is ambiguous (session-command, shell, supp-group), so su rejects it.
expect_both 'su --s ambiguous prefix allowed' 0 --command "su --s 'rm -rf /'"
expect_both 'rm.EXE under the tree allowed' 0 --command 'rm.EXE -rf ./build'
expect_both 'eval rm -rf "" allowed' 0 --command 'eval rm -rf ""'

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
expect_both "rm -rf '\$X' blocks (declared overblock)" 2 --command "rm -rf '\$X'"
expect_both 'rm -rf "$X/build" allowed' 0 --command 'rm -rf "$X/build"'
expect_both 'rm -rf "${X:?}/" allowed (SC2115 idiom)' 0 --command 'rm -rf "${X:?}/"'
expect_both 'rm -rf "${X:?unset}/" allowed' 0 --command 'rm -rf "${X:?unset}/"'
expect_both 'rm -rf "${X?}" blocks (empty passes ?)' 2 --command 'rm -rf "${X?}"'
expect_both 'rm -rf "${X?}/"* blocks' 2 --command 'rm -rf "${X?}/"*'
expect_both 'rm -rf "${X%/}" blocks' 2 --command 'rm -rf "${X%/}"'
expect_both 'rm -rf "${!X}" blocks' 2 --command 'rm -rf "${!X}"'
expect_both 'rm -rf "${X:1}" blocks' 2 --command 'rm -rf "${X:1}"'
expect_both 'rm -rf "$X$Y" blocks (expansions only)' 2 --command 'rm -rf "$X$Y"'
expect_both 'rm -rf "${X:?}${Y}" blocks' 2 --command 'rm -rf "${X:?}${Y}"'

assert_contains "the suite runs from a git checkout (toplevel found)" "$RDT_TOP" "/"
rdt_phys() {
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
expect_both 'bare variable: "${X:?}"* allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf "${X:?}"*'
expect_both 'bare variable: "$X"-build blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf "$X"-build'
expect_both 'bare variable: "${X}"_old* blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf "${X}"_old*'
expect_both 'unset suffixed: $S/x blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf $S/x'
expect_both 'unset suffixed: ${S}/x blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf ${S}/x'
expect_both 'unset suffixed: ${X}x blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf ${X}x'
expect_both 'unset suffixed: $S"/x" blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf $S"/x"'
expect_both 'unset suffixed: "$S"/x blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf "$S"/x'
expect_both 'unset suffixed: find $S/x -delete blocks' 2 "${RDT_CWD[@]}" --command 'find $S/x -delete'
expect_both 'unset suffixed: mv $S/x y blocks' 2 "${RDT_CWD[@]}" --command 'mv $S/x y'
expect_both 'unset suffixed: xargs rm -rf $S/x blocks' 2 "${RDT_CWD[@]}" --command 'find build | xargs rm -rf $S/x'
expect_both 'unset suffixed: a blank in the assigned value blocks' 2 "${RDT_CWD[@]}" --command 'S="/ tmp"; rm -rf $S/x'
expect_both 'unset suffixed: a substitution value blocks' 2 "${RDT_CWD[@]}" --command 'S=$(mktemp -d); rm -rf $S/x'
expect_both 'unset suffixed: a value built on an unset name blocks' 2 "${RDT_CWD[@]}" --command 'Q=$U/b; rm -rf $Q/c'
expect_both 'unset suffixed: a loop over a substitution blocks' 2 "${RDT_CWD[@]}" --command 'for f in $(ls); do rm -rf $f/x; done'
expect_both 'unset suffixed: an escaped blank in the value blocks' 2 "${RDT_CWD[@]}" --command 'S=/\ tmp; rm -rf $S/x'
expect_both 'unset suffixed: a quoted blank joined to the value blocks' 2 "${RDT_CWD[@]}" --command 'S=/" "tmp; rm -rf $S/x'
expect_both 'unset suffixed: quote-joined parts of the value block' 2 "${RDT_CWD[@]}" --command "S=\"/\"' 'tmp; rm -rf \$S/x"
expect_both 'unset suffixed: a += append blocks' 2 "${RDT_CWD[@]}" --command "S=/; S+=' tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: a quoted blank in a for list blocks' 2 "${RDT_CWD[@]}" --command 'for v in "/ tmp"; do rm -rf $v/x; done'
expect_both 'unset suffixed: a quoted expansion in a for list blocks' 2 "${RDT_CWD[@]}" --command 'for v in "$@"; do rm -rf $v/x; done'
expect_both 'unset suffixed: an escaped blank in a for list blocks' 2 "${RDT_CWD[@]}" --command 'for v in /\ tmp; do rm -rf $v/x; done'
expect_both 'unset suffixed: printf -v glued to the name blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; printf -vS '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: read -a glued to the name blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; read -aS <f; rm -rf $S/x'
expect_both 'unset suffixed: printf -v with a quoted glued name blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; printf -v\"S\" '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: a quoted glued printf option word blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; printf \"-vS\" '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: read -a with a quoted glued name blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; read -a"S" <f; rm -rf $S/x'
expect_both 'unset suffixed: a quoted glued read option word blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; read '-aS' <f; rm -rf \$S/x"
expect_both 'unset suffixed: printf -v with a quoted separate name blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; printf -v \"S\" '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: printf -v with a glued locale-quoted name blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; printf -v\$\"S\" '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: printf -v with a separate locale-quoted name blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; printf -v \$\"S\" '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: read -a with a locale-quoted name blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; read -a $"S" <f; rm -rf $S/x'
expect_both 'unset suffixed: printf -v with an ANSI-C escaped name blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; printf -v \$'\\x53' '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: printf -v with a glued ANSI-C name blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; printf -v\$'S' '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: a spaced subscript assignment blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; S[ 0 ]="/ tmp"; rm -rf $S/x'
expect_both 'unset suffixed: the name inside a string blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp/x; echo "S[1]"; echo "$(date)"; rm -rf $S/y'
expect_both 'unset suffixed: a quoted printf name with an ANSI-C name blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; pr\"\"intf -v \$'\\x53' '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: a quoted printf name with a locale-quoted name blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; p''rintf -v \$\"S\" '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: a quoted read name with a locale-quoted name blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; re""ad -a $"S" <f; rm -rf $S/x'
expect_both 'unset suffixed: a quoted declare subscript blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; declare "S[0]"="/ tmp"; rm -rf $S/x'
expect_both 'unset suffixed: a declare subscript with a quoted index blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; declare S"[0]"=x; rm -rf $S/x'
expect_both 'unset suffixed: a quoted export assignment blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; export "S=/ tmp"; rm -rf $S/x'
expect_both 'unset suffixed: a quoted readonly assignment blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; readonly "S=/ tmp"; rm -rf $S/x'
expect_both 'unset suffixed: an ANSI-C export assignment blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; export \$'S=/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: a printf name from a default expansion blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; printf -v \${x:-S} '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: a printf name from a brace expansion blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; printf -v {S,} '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: a declare with a quoted name blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; declare "S"="/ tmp"; rm -rf $S/x'
expect_both 'unset suffixed: an export that reads another name stays allowed' 0 "${RDT_CWD[@]}" --command 'S=/tmp/x; export PATH="$PATH:/opt/bin"; echo "$(date)"; rm -rf $S/y'
expect_both 'unset suffixed: ANSI-C quoting with no setter stays allowed' 0 "${RDT_CWD[@]}" --command "S=/tmp/x; echo \$'a\\tb'; echo \"\$(date)\"; rm -rf \$S/y"
expect_both 'unset suffixed: read -r of another name stays allowed for r' 0 "${RDT_CWD[@]}" --command 'r=/tmp/x; read -r line </dev/null; rm -rf $r/y'
expect_both 'unset suffixed: printf -v into another name stays allowed for v' 0 "${RDT_CWD[@]}" --command 'v=/tmp/x; printf -v output hello; rm -rf $v/y'
expect_both 'unset suffixed: a nameref flag after another flag blocks' 2 "${RDT_CWD[@]}" --command 'R="/ tmp"; declare -g -n S=R; rm -rf $S/x'
expect_both 'unset suffixed: a subscript assignment blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; S[0]="/ tmp"; rm -rf $S/x'
expect_both 'unset suffixed: a select list blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; select S in "/ tmp"; do rm -rf $S/x; done'
expect_both 'unset suffixed: a := default blocks without a cwd' 2 --command 'S=; : ${S:=/ tmp}; rm -rf $S/x'
expect_both 'unset suffixed: an exported literal stays allowed' 0 "${RDT_CWD[@]}" --command 'export S=/tmp/x; echo "$(date)"; rm -rf $S/y'
expect_both 'unset suffixed: a printf that only reads the name stays allowed' 0 "${RDT_CWD[@]}" --command "S=/tmp/x; printf '%s\\n' \"\$S\"; rm -rf \$S/y"
expect_both 'unset suffixed: a quoted second for list blocks' 2 "${RDT_CWD[@]}" --command 'for v in a; do :; done; for v in "/ tmp"; do rm -rf $v/x; done'
expect_both 'unset suffixed: a quoted for list after an assignment blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; for S in "/ tmp"; do rm -rf $S/x; done'
expect_both 'unset suffixed: a for over the positionals after an assignment blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; for S; do rm -rf $S/x; done'
expect_both 'unset suffixed: read after an assignment blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; read -r S <f; rm -rf $S/x'
expect_both 'unset suffixed: printf -v after an assignment blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; printf -v S '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: mapfile after an assignment blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; mapfile -t S <f; rm -rf $S/x'
expect_both 'unset suffixed: getopts after an assignment blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; getopts ab S; rm -rf $S/x'
expect_both 'unset suffixed: a nameref after an assignment blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; declare -n S=T; rm -rf $S/x'
expect_both 'unset suffixed: a := default blocks' 2 "${RDT_CWD[@]}" --command 'S=; : ${S:=/ tmp}; rm -rf $S/x'
expect_both 'unset suffixed: a subscripted := default blocks' 2 "${RDT_CWD[@]}" --command 'S=; : ${S[0]:=/ tmp}; rm -rf $S/x'
expect_both 'unset suffixed: a subscripted = default blocks' 2 "${RDT_CWD[@]}" --command 'S=; : ${S[0]=/ tmp}; rm -rf $S/x'
expect_both 'unset suffixed: a nested subscript default blocks' 2 "${RDT_CWD[@]}" --command 'S=; : ${S[a[0]]:=/ tmp}; rm -rf $S/x'
expect_both 'unset suffixed: a printf name split by an expansion blocks' 2 "${RDT_CWD[@]}" --command "S=/tmp; p\${x}rintf -vS '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: a setter named by a variable blocks' 2 "${RDT_CWD[@]}" --command "x=printf; S=/tmp; \$x -vS '/ tmp'; rm -rf \$S/x"
expect_both 'unset suffixed: a nameref to a default expansion blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; d${x}eclare -n R=${y:-S}; R="/ tmp"; rm -rf $S/x'
expect_both 'unset suffixed: an array value blocks' 2 "${RDT_CWD[@]}" --command 'S=(/ tmp); rm -rf $S/x'
expect_both 'unset suffixed: an IFS change blocks' 2 "${RDT_CWD[@]}" --command 'S=a:/:b; IFS=:; rm -rf $S/x'
expect_both 'unset suffixed: eval after an assignment blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; eval "$C"; rm -rf $S/x'
expect_both 'unset suffixed: source after an assignment blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; source f; rm -rf $S/x'
expect_both 'unset suffixed: eval after && blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; true && eval "$C"; rm -rf $S/x'
expect_both 'unset suffixed: eval after then blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; if true; then eval "$C"; fi; rm -rf $S/x'
expect_both 'unset suffixed: a dot source blocks' 2 "${RDT_CWD[@]}" --command 'S=/tmp; . ./f; rm -rf $S/x'
expect_both 'unset suffixed: the word eval as an argument stays allowed' 0 "${RDT_CWD[@]}" --command 'S=/tmp/x; rm -rf $S/y; claude plugin eval . --runs 1'
expect_both 'unset suffixed: a dot argument stays allowed' 0 "${RDT_CWD[@]}" --command 'S=/tmp/x; find . -name z; echo "$(date)"; rm -rf $S/y'
expect_both 'unset suffixed: a read of another name stays allowed' 0 "${RDT_CWD[@]}" --command 'S=/tmp/x; read -r T <f; rm -rf $S/y'
expect_both 'unset suffixed: a name with a for suffix stays allowed' 0 "${RDT_CWD[@]}" --command 'for v2 in "a b"; do :; done; v=/tmp/x; echo "$(date)"; rm -rf $v/y'
expect_both 'unset suffixed: $*/x with an unrelated = blocks' 2 "${RDT_CWD[@]}" --command 'set -- "/ tmp"; rm -rf $*/x --interactive=never'
expect_both 'unset suffixed: a positional opener blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf $1/x'
expect_both 'unset suffixed: a value from a positional blocks' 2 "${RDT_CWD[@]}" --command "bash -c 'S=\$1; rm -rf \$S/x' _ '/ tmp'"
expect_both 'unset suffixed: an indirect value blocks' 2 "${RDT_CWD[@]}" --command 'S=${!R}; rm -rf $S/x'
expect_both 'unset suffixed: a self-reference alone blocks' 2 "${RDT_CWD[@]}" --command 'S=$S/a; rm -rf $S/x'
expect_both 'unset suffixed: a self-reference after a literal allowed' 0 "${RDT_CWD[@]}" --command 'S=/tmp; S=$S/a; echo "$(date)"; rm -rf $S/x'
expect_both 'unset suffixed: bash -c from the PowerShell tool blocks' 2 --tool PowerShell --command "bash -c 'rm -rf \$S/x'"
expect_both 'unset suffixed: a Remove-Item operand on the PowerShell tool stays allowed' 0 --tool PowerShell --command 'Remove-Item -Recurse $env:S/x'
rdt_chain='A='
for _ in {1..30}; do rdt_chain+='$B'; done
rdt_chain+='; B='
for _ in {1..30}; do rdt_chain+='$C'; done
rdt_chain+='; C='
for _ in {1..30}; do rdt_chain+='$D'; done
rdt_chain+='; D='
for _ in {1..30}; do rdt_chain+='$E'; done
rdt_chain+='; E=x; rm -rf $A/x'
expect_both 'unset suffixed: a chain past the call budget blocks' 2 "${RDT_CWD[@]}" --command "$rdt_chain"
expect_both 'unset suffixed: "$S/x" allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf "$S/x"'
expect_both 'unset suffixed: ${HOME}/x allowed' 0 --command 'rm -rf ${HOME}/x'
expect_both 'unset suffixed: $TMPDIR/x allowed' 0 --command 'rm -rf $TMPDIR/x'
expect_both 'unset suffixed: ${S:?}/x allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf ${S:?}/x'
expect_both 'unset suffixed: "${S:?}"/x allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf "${S:?}"/x'
expect_both 'unset suffixed: a name the resolver binds allowed' 0 "${RDT_CWD[@]}" --command 'S=/tmp/x; rm -rf $S/x'
expect_both 'unset suffixed: a literal the resolver cannot bind allowed' 0 "${RDT_CWD[@]}" --command 'S=/tmp/x; echo "$(date)"; rm -rf $S/x'
expect_both 'unset suffixed: a value built on a set name allowed' 0 "${RDT_CWD[@]}" --command 'P=/tmp/a; Q=$P/b; echo "$(date)"; rm -rf $Q/c'
expect_both 'unset suffixed: a loop variable allowed' 0 "${RDT_CWD[@]}" --command 'for v in a b; do rm -rf $v/x; done'
expect_both 'unset suffixed: a loop over unquoted items allowed' 0 "${RDT_CWD[@]}" --command 'for v in $R/a $R/b; do rm -rf $v/x; done'
expect_both 'unset suffixed: a name set in a bash -c program allowed' 0 "${RDT_CWD[@]}" --command "bash -c 'S=/tmp/x; echo x; rm -rf \$S/y'"
expect_both 'bare variable: "${X:?}/*" allowed' 0 --command 'rm -rf "${X:?}/*"'
expect_both 'bare variable: "${X:?}/*" allowed with a cwd' 0 "${RDT_CWD[@]}" --command 'rm -rf "${X:?}/*"'
expect_both 'bare variable: "$X/build" allowed with a cwd' 0 "${RDT_CWD[@]}" --command 'rm -rf "$X/build"'
expect_both 'partial expansion: mktemp value allowed' 0 "${RDT_CWD[@]}" --command 'd="$(mktemp -d)" && touch "$d/a" && rm -rf "${d:?}/a"'
expect_both 'partial expansion: loop variable allowed' 0 "${RDT_CWD[@]}" --command 'for d in a b; do rm -rf "/tmp/rdt-pin/$d"; done'
expect_both 'partial expansion: value set after another command allowed' 0 "${RDT_CWD[@]}" --command 'mkdir -p out && S=/tmp/rdt-pin; rm -rf "$S/x"'

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
expect_both 'tree: cd / && rm -rf * blocks' 2 "${RDT_CWD[@]}" --command 'cd / && rm -rf *'
expect_both 'tree: cd / && rm -rf build blocks' 2 "${RDT_CWD[@]}" --command 'cd / && rm -rf build'
expect_both 'tree: cd -P / then a delete blocks' 2 "${RDT_CWD[@]}" --command 'cd -P /; rm -rf build'
expect_both 'tree: pushd / then a delete blocks' 2 "${RDT_CWD[@]}" --command 'pushd / && rm -rf build'
expect_both 'tree: a bare cd goes home, then a delete blocks' 2 "${RDT_CWD[@]}" --command 'cd && rm -rf build'
expect_both 'tree: cd inside a child shell blocks' 2 "${RDT_CWD[@]}" --command "bash -c 'cd / && rm -rf *'"
expect_both 'tree: env -C / blocks' 2 "${RDT_CWD[@]}" --command 'env -C / rm -rf build'
expect_both 'tree: env --chdir=/ blocks' 2 "${RDT_CWD[@]}" --command 'env --chdir=/ rm -rf build'
expect_both 'tree: sudo -D / blocks' 2 "${RDT_CWD[@]}" --command 'sudo -D / rm -rf build'
expect_both 'tree: a substitution sees a later cd' 2 "${RDT_CWD[@]}" --command 'cd / && echo "$(rm -rf *)"'
expect_both 'tree: a cd after the delete does not move it' 0 "${RDT_CWD[@]}" --command 'rm -rf build && cd ..'
expect_both 'tree: cd into the checkout then a relative delete allowed' 0 "${RDT_CWD[@]}" \
  --command "cd '$RDT_TOP' && rm -rf .work/x"
expect_both 'tree: cd into a subdirectory then ../x blocks (declared overblock)' 2 "${RDT_CWD[@]}" \
  --command 'cd plugins && rm -rf ../x'
expect_both 'tree: a subshell cd .. then a delete blocks (declared overblock)' 2 "${RDT_CWD[@]}" \
  --command '(cd ..) ; rm -rf build'
expect_both 'tree: env -C on another command then a delete blocks (declared overblock)' 2 "${RDT_CWD[@]}" \
  --command 'env -C /opt true; rm -rf build'
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
expect_both 'brace: $X/{a,b} unquoted blocks like $X/build' 2 "${RDT_CWD[@]}" --command 'rm -rf $X/{a,b}'
expect_both 'brace: inside a substitution blocks' 2 --command 'echo $(rm -rf {/,x})'
guard_invoke "${RDT_CWD[@]}" --command 'rm -rf x{1..3}'
assert_contains "the brace refusal names its form" "$GUARD_ERR" "brace expansion"
expect_both 'glob: .. after a glob blocks' 2 "${RDT_CWD[@]}" \
  --command 'rm -rf .git/*/../../../../../../../../../../../../../../Windows/Temp2'
expect_both 'glob: */.. climbing out blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf */../../../x'
expect_both 'glob: .. inside a glob component blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf .g?t/../../x'
expect_both 'glob: .. before the glob stays judged, inside the tree allowed' 0 "${RDT_CWD[@]}" \
  --command 'rm -rf plugins/../plugins/*/build'
assert_contains "the deadline is twenty-five seconds" "$(grep -n '^RDT_DEADLINE=' "$HOOK")" "RDT_DEADLINE=25"
assert_contains "the whole-run ceiling is fifty seconds" "$(grep -n '^RDT_DEADLINE_ABS=' "$HOOK")" "RDT_DEADLINE_ABS=50"
assert_contains "the parse callback checks the deadline only once the arm has work" \
  "$(sed -n '/^rdt_check_segment() {/,/^}/p' "$HOOK")" "((RDT_T0 >= 0)) && rdt_deadline"
mkdir -p "$TEST_TMPDIR/bin-git-any"
printf '#!/usr/bin/env bash\nd=.\nwhile (($#)); do [[ "$1" == -C ]] && { d="$2"; shift; }; shift; done\nprintf "%%s\\n" "$d"\n' \
  >"$TEST_TMPDIR/bin-git-any/git"
chmod +x "$TEST_TMPDIR/bin-git-any/git"
expect_both 'tree: a cd into another repository is judged against the cwd tree' 2 "${RDT_CWD[@]}" \
  --command 'cd ~ && rm -rf rdt-x' -- "PATH=$TEST_TMPDIR/bin-git-any:$PATH"
expect_both 'tree: the stub still allows the cwd tree itself' 0 "${RDT_CWD[@]}" \
  --command 'rm -rf build' -- "PATH=$TEST_TMPDIR/bin-git-any:$PATH"

expect_both 'temp: a path under /tmp allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf /tmp/rdt-x'
expect_both 'temp: a glob under a /tmp subdirectory allowed' 0 "${RDT_CWD[@]}" --command 'rm -rf /tmp/rdt-sub/*'
expect_both 'temp: the suite scratch directory allowed' 0 "${RDT_CWD[@]}" --command "rm -rf '$TEST_TMPDIR/x'"
expect_both 'temp: /tmp itself blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf /tmp'
expect_both 'temp: /tmp/* blocks' 2 "${RDT_CWD[@]}" --command 'rm -rf /tmp/*'

RDT_SP=/opt/rdt-scratch-1
expect_both 'scratchpad: one outside temp is ignored' 2 --payload "$(rdt_pl "rm -rf $RDT_SP/x" "$RDT_TOP" "$RDT_SP")"
expect_both 'scratchpad: one outside temp is ignored (no tree)' 2 --payload "$(rdt_pl "rm -rf $RDT_SP/x" / "$RDT_SP")"
expect_both 'scratchpad: a path under it allowed' 0 --payload "$(rdt_pl "rm -rf '$RDT_SPT/x'" "$RDT_TOP" "$RDT_SPT")"
expect_both 'scratchpad: a glob under a subdirectory allowed' 0 --payload "$(rdt_pl "rm -rf '$RDT_SPT/sub/'*" "$RDT_TOP" "$RDT_SPT")"
expect_both 'scratchpad: the scratchpad itself blocks' 2 --payload "$(rdt_pl "rm -rf '$RDT_SPT'" "$RDT_TOP" "$RDT_SPT")"
expect_both 'scratchpad: its glob blocks' 2 --payload "$(rdt_pl "rm -rf '$RDT_SPT/'*" "$RDT_TOP" "$RDT_SPT")"
expect_both 'scratchpad: in backslash form, itself blocks' 2 --payload "$(rdt_pl "rm -rf '$RDT_SPT'" "$RDT_TOP" "${RDT_SPT//\//\\}")"

expect_both 'no tree: a relative operand blocks' 2 --cwd / --command 'rm -rf build'
expect_both 'no tree: a temp path allowed' 0 --cwd / --command 'rm -rf /tmp/rdt-x'
expect_both 'no tree: a scratchpad path allowed' 0 --payload "$(rdt_pl "rm -rf '$RDT_SPT/x'" / "$RDT_SPT")"
expect_both 'no tree: a relative cwd skips the arm' 0 --cwd 'relative/dir' --command 'rm -rf ../../x'

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
    expect_both 'symlink: */* through a link to outside blocks' 2 --cwd "$rdt_ln" --command 'rm -rf */*'
    expect_both 'symlink: u*/x through a link to outside blocks' 2 --cwd "$rdt_ln" --command 'rm -rf u*/x'
    rm -f "$rdt_ln/up"
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
mkdir -p "$TEST_TMPDIR/wide/d"{01..20}/e{01..20}
rdt_ms_payload 'a wide glob tree is refused at the match cap' 2 8000 \
  "$(rdt_pl "rm -rf '$TEST_TMPDIR/wide'/*/*/x" "$RDT_TOP")"
expect_both 'a narrow glob in the same tree allowed' 0 "${RDT_CWD[@]}" --command "rm -rf '$TEST_TMPDIR/wide/d01'/*/x"
mkdir -p "$TEST_TMPDIR/wide2"
for ((rdt_d = 0; rdt_d < 300; rdt_d++)); do : >"$TEST_TMPDIR/wide2/f$rdt_d"; done
rdt_ms_payload 'a trailing */ over 300 entries is refused at the cap' 2 15000 \
  "$(rdt_pl "rm -rf '$TEST_TMPDIR/wide2'/*/" "$RDT_TOP")"
expect_both 'a trailing */ over a few entries under temp allowed' 0 "${RDT_CWD[@]}" \
  --command "rm -rf '$TEST_TMPDIR/wide/d01'/*/"
guard_invoke "${RDT_CWD[@]}" --command "rm -rf '$TEST_TMPDIR/wide2'/*/"
assert_contains 'the glob-cap refusal names the entry cap' "$GUARD_ERR" "more than 256 directory entries"
for rdt_t in realpath git; do
  mkdir -p "$TEST_TMPDIR/bin-slow-$rdt_t"
  printf '#!/usr/bin/env bash\nexec sleep 60\n' >"$TEST_TMPDIR/bin-slow-$rdt_t/$rdt_t"
  chmod +x "$TEST_TMPDIR/bin-slow-$rdt_t/$rdt_t"
done
guard_invoke "${RDT_CWD[@]}" --command 'rm -rf ./x~1/build' -- "PATH=$TEST_TMPDIR/bin-slow-realpath:$PATH" SECONDS=44
assert_exit 'a resolver that runs out of time refuses' 2 "$GUARD_RC"
assert_contains 'the timeout refusal names the time bound' "$GUARD_ERR" "ran out of time"
guard_invoke "${RDT_CWD[@]}" --command 'rm -rf ./build' -- "PATH=$TEST_TMPDIR/bin-slow-git:$PATH" SECONDS=44
assert_exit 'a git lookup that runs out of time refuses' 2 "$GUARD_RC"
assert_contains 'the git timeout refusal names the time bound' "$GUARD_ERR" "ran out of time"
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
rdt_ms_payload 'an operand of 3000 braces is refused in time' 2 8000 "$(rdt_pl "rm -rf ${rdt_br}x" "$RDT_TOP")"
guard_invoke "${RDT_CWD[@]}" --command "rm -rf ${rdt_br}x"
assert_contains "the brace-count refusal names its form" "$GUARD_ERR" "brace expansion"
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
mkdir -p "$TEST_TMPDIR/g4ok/real"
expect_both 'glob: */x over real directories under temp allowed' 0 --cwd "$TEST_TMPDIR/g4ok" --command 'rm -rf */x'
expect_both 'glob: */* over real directories under temp allowed' 0 --cwd "$TEST_TMPDIR/g4ok" --command 'rm -rf */*'
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

expect_both 'an error inside the judgment refuses' 2 "${RDT_CWD[@]}" --command 'rm -rf build~1' \
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

rdt_timed_payload() {
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
expect_both 'an operand with a newline blocks' 2 "${RDT_CWD[@]}" --command $'rm -rf "a\nb"'
rdt_cds=""
for ((rdt_d = 0; rdt_d < 40; rdt_d++)); do rdt_cds+="cd d$rdt_d && "; done
rdt_timed_payload 'a chain of 40 relative cd lines is refused in time' 2 "$(rdt_pl "${rdt_cds}rm -rf x" "$RDT_TOP")"
guard_invoke --payload "$(rdt_pl "${rdt_cds}rm -rf x" "$RDT_TOP")"
assert_contains "the cd chain refusal names the directory cap" "$GUARD_ERR" "too many directory changes"
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

rdt_finish
