#!/usr/bin/env bash
# Contract test for block-root-delete-target.sh (guardrails plugin), part f of 6:
# the nesting and size-budget cases of section 1 and the python and node heredoc
# cases of section 2. The parts are block-root-delete-target.test.sh and
# block-root-delete-target-b.test.sh to -f.test.sh;
# block-root-delete-target-fixtures.sh holds what they share.
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash JSON on
# stdin, asserts on exit code (2 = blocked, 0 = allowed). Self-contained, with
# no host-repo assertion library.
#
# The core table runs through expect_both, so every verdict is asserted twice:
# once with the guard alone, and once under hooks/run-guards.sh.
#
# File-wide, and deliberate: every command string below is a LITERAL the guard
# must read exactly as an operator wrote it. `$HOME` is matched as text, because
# the guard never evaluates an expansion (SC2016), and `\\` is a real pair of
# backslashes rather than an escaped quote (SC1003).
# shellcheck disable=SC2016,SC1003

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# shellcheck source=block-root-delete-target-fixtures.sh
source "$HOOK_DIR/block-root-delete-target-fixtures.sh"

# --- 1. MUST FIRE: nesting and size budgets ----------------------------------
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

# --- 2. MUST NOT FIRE: python and node programs on a quoted heredoc ----------
# A python or node program fed on a quoted heredoc is not shell text: bash
# expands nothing in the body, Python 3 has no backtick syntax and a JS backtick
# is a template literal. A backtick or `$(` span in its strings is still read,
# but only tokenized when a deleter name starts a word in it or it holds a `$`,
# so prose like "the form check (x)" no longer reaches shfmt and is refused.
expect_both "python heredoc with prose in a backtick span after assignments allowed" 0 --command $'W=wt; F=docs/x.md; python3 -I - <<\'EOF\'\nimport pathlib\np = pathlib.Path("docs/x.md")\ns = p.read_text()\nold = "- Save awaits `the schedule check before the form check (Reviewer 1\'s race fix)`.\\n"\nnew = "- Save awaits the schedule check.\\n"\nassert old in s\np.write_text(s.replace(old, new))\nEOF\ngh pr view 1'
expect_both "node heredoc with prose in a template literal allowed" 0 --command $'node - <<\'EOF\'\nconst fs = require("fs");\nconst s = `the schedule check before the form check (Reviewer 1\'s race fix)`;\nconsole.log(s);\nEOF'
expect_both "python heredoc with prose in a dollar-paren string allowed" 0 --command $'python3 - <<\'EOF\'\nprint("cost $(the form check (draft))")\nEOF'
expect_both "python heredoc after cd with prose in a backtick span allowed" 0 --command $'cd "$HOME/wt" && python3 - <<\'EOF\'\nold = "- Save awaits `the schedule check before the form check (Reviewer 1\'s race fix)`.\\n"\nprint(old)\nEOF'
expect_both "python heredoc on a later line with prose in a backtick span allowed" 0 --command $'cd sub\npython3 - <<\'EOF\'\nold = "- Save awaits `the schedule check before the form check (Reviewer 1\'s race fix)`.\\n"\nprint(old)\nEOF\ngh pr view 1'
expect_both "python heredoc with a span holding no deleter substring allowed" 0 --command $'W=wt; F=docs/x.md; python3 -I - <<\'EOF\'\nold = "- Save awaits `the schedule check (Reviewer 1\'s race fix)`.\\n"\nprint(old)\nEOF\ngh pr view 1'
expect_both "versioned python with flags and prose in a backtick span allowed" 0 --command $'python3.12 -B -u - <<\'EOF\'\nprint("`the form check (x)`")\nEOF'
expect_both "bare nodejs with prose in a template literal allowed" 0 --command $'nodejs <<"EOF"\nconsole.log(`the form check (x)`);\nEOF'
# A shell, a pipe into one, perl, ruby or an unquoted delimiter still runs the
# span, and a python or node program can hand a string to a shell through a
# variable the interpreter reading never follows, so each of these still blocks.
expect_both "python heredoc piped into sh blocks" 2 --command $'python3 - <<\'EOF\' | sh\nprint("`rm -rf /`")\nEOF'
expect_both "perl heredoc with a backticked rm blocks" 2 --command $'perl - <<\'EOF\'\nprint `rm -rf /`;\nEOF'
expect_both "ruby heredoc with a backticked rm blocks" 2 --command $'ruby - <<\'EOF\'\nputs `rm -rf /`\nEOF'
expect_both "unquoted python heredoc with a backticked rm blocks" 2 --command $'python3 - <<EOF\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc handing a backticked rm to os.system through a variable blocks" 2 --command $'python3 - <<\'EOF\'\nimport os\ncmd = "echo `rm -rf /`"\nos.system(cmd)\nEOF'
expect_both "python heredoc handing a dollar-paren rm to a shell through concatenation blocks" 2 --command $'python3 - <<\'EOF\'\nimport subprocess\nsubprocess.run("echo " + "$(rm -rf /)", shell=True)\nEOF'
expect_both "python heredoc handing a backticked rm to asyncio blocks" 2 --command $'python3 - <<\'EOF\'\nimport asyncio\nasyncio.run(asyncio.create_subprocess_shell("echo `rm -rf /`"))\nEOF'
expect_both "node heredoc handing a dollar-paren rm to execSync through a variable blocks" 2 --command $'node - <<\'EOF\'\nconst { execSync } = require("child_process");\nconst c = "echo $(rm -rf /)";\nexecSync(c);\nEOF'
expect_both "python heredoc handing a backslashed rm to os.system blocks" 2 --command $'python3 - <<\'EOF\'\nimport os\ncmd = "echo `\\rm -rf /`"\nos.system(cmd)\nEOF'
# Output piped to a shell around a compound, or a body that reaches a shell or
# another program's stdin.
expect_both "python heredoc in a brace group piped into sh blocks" 2 --command $'{\npython3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF\n} | sh'
expect_both "python heredoc in an if piped into sh blocks" 2 --command $'if true; then\npython3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF\nfi | sh'
expect_both "python heredoc after exec into a sh process substitution blocks" 2 --command $'exec > >(sh)\npython3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc behind a clobber into bash -c blocks" 2 --command $'bash -c sh >|python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc behind a clobber into sh -s blocks" 2 --command $'sh -s >|python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc behind an escaped semicolon blocks" 2 --command $'bash -s \\; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python -c running its stdin heredoc blocks" 2 --command $'python3 -Ic \'import os,sys; os.system(sys.stdin.read())\' <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "node --eval running its stdin heredoc blocks" 2 --command $'node --eval \'require("child_process").execSync(require("fs").readFileSync(0, "utf8"))\' - <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "python heredoc reading a second heredoc on fd 3 blocks" 2 --command $'python3 - <<\'A\' 3<<\'B\'\nimport os\nos.system(os.fdopen(3).read())\nA\necho `rm -rf /`\nB'
# The interpreter name rebound or resolved elsewhere earlier in the command.
expect_both "python heredoc after python3 redefined as a function blocks" 2 --command $'python3() { bash; }; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "node heredoc after node redefined as a function blocks" 2 --command $'node() { bash; }; node - <<\'EOF\'\nconsole.log("`rm -rf /`")\nEOF'
expect_both "python heredoc with a PATH prefix blocks" 2 --command $'PATH=/opt/evil:$PATH python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc after a PATH assignment blocks" 2 --command $'PATH=/opt/evil; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc after hash -p blocks" 2 --command $'hash -p /bin/sh python3; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc after a copy over python3 blocks" 2 --command $'cp /bin/sh ~/bin/python3; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc after an alias blocks" 2 --command $'shopt -s expand_aliases\nalias python3=bash\npython3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc after eval blocks" 2 --command $'eval "$x"; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc after a dot source blocks" 2 --command $'. ./defs.sh; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
# Only `python3 [no-argument flags] [-]` and `node [-]` qualify: a path, a
# launcher, a prefix assignment, an option taking an argument, a script, a
# suffix after the delimiter or an opener inside a substitution is scanned as
# before.
expect_both "./python3 heredoc blocks" 2 --command $'./python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "env python3 heredoc blocks" 2 --command $'env python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "sudo python3 heredoc blocks" 2 --command $'sudo python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python3 heredoc with a prefix assignment blocks" 2 --command $'FOO=1 python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python3 -m heredoc blocks" 2 --command $'python3 -m x <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python3 -X heredoc blocks" 2 --command $'python3 -X dev - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python3 -W heredoc blocks" 2 --command $'python3 -W error - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python3 script heredoc blocks" 2 --command $'python3 run.py <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "node -e heredoc blocks" 2 --command $'node -e 1 <<\'EOF\'\nconsole.log("`rm -rf /`")\nEOF'
expect_both "node -p heredoc blocks" 2 --command $'node -p 1 <<\'EOF\'\nconsole.log("`rm -rf /`")\nEOF'
expect_both "node -r heredoc blocks" 2 --command $'node -r x <<\'EOF\'\nconsole.log("`rm -rf /`")\nEOF'
expect_both "node script heredoc blocks" 2 --command $'node run.js <<\'EOF\'\nconsole.log("`rm -rf /`")\nEOF'
expect_both "python heredoc with a list operator after the delimiter blocks" 2 --command $'python3 - <<\'EOF\' && true\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc inside a substitution blocks" 2 --command $'x=$(python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF\n)'
# The interpreter reading of literals is unchanged.
expect_both "python heredoc calling os.system on a literal rm blocks" 2 --command $'python3 - <<\'EOF\'\nimport os\nos.system(\'rm -rf /\')\nEOF'
expect_both "python heredoc removing the root tree before a trailing command blocks" 2 --command $'W=x; F=y; python3 - <<\'EOF\'\nimport shutil\nshutil.rmtree(\'/\')\nEOF\ngh pr view 1'
expect_both "node heredoc running a template-literal rm blocks" 2 --command $'node - <<\'EOF\'\nrequire("child_process").execSync(`rm -rf /`);\nEOF'
# The same prose span in every shape the narrowing does not cover is still
# tokenized as before, and shfmt still refuses it. These pin that fallback,
# which the shapes above cannot: their span starts with `rm`, so it would be
# tokenized either way.
rdt_py=$'print("`the form check (x)`")\nEOF'
rdt_js=$'console.log(`the form check (x)`);\nEOF'
expect_both "prose span: ./python3 still tokenized" 2 --command $'./python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: env python3 still tokenized" 2 --command $'env python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: sudo python3 still tokenized" 2 --command $'sudo python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: prefix assignment still tokenized" 2 --command $'FOO=1 python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: python3 -m still tokenized" 2 --command $'python3 -m x <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: python3 -X still tokenized" 2 --command $'python3 -X dev - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: python3 -W still tokenized" 2 --command $'python3 -W error - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: python3 -c still tokenized" 2 --command $'python3 -c x <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: python3 script still tokenized" 2 --command $'python3 run.py <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: node -e still tokenized" 2 --command $'node -e 1 <<\'EOF\'\n'"$rdt_js"
expect_both "prose span: node -p still tokenized" 2 --command $'node -p 1 <<\'EOF\'\n'"$rdt_js"
expect_both "prose span: node -r still tokenized" 2 --command $'node -r x <<\'EOF\'\n'"$rdt_js"
expect_both "prose span: node script still tokenized" 2 --command $'node run.js <<\'EOF\'\n'"$rdt_js"
expect_both "prose span: perl still tokenized" 2 --command $'perl - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: ruby still tokenized" 2 --command $'ruby - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: bash still tokenized" 2 --command $'bash <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: list operator after the delimiter still tokenized" 2 --command $'python3 - <<\'EOF\' && true\n'"$rdt_py"
expect_both "prose span: pipe after the delimiter still tokenized" 2 --command $'python3 - <<\'EOF\' | sh\n'"$rdt_py"
expect_both "prose span: opener inside a substitution still tokenized" 2 --command $'x=$(python3 - <<\'EOF\'\n'"$rdt_py"$'\n)'
expect_both "prose span: unquoted delimiter still tokenized" 2 --command $'python3 - <<EOF\n'"$rdt_py"
expect_both "prose span: second opener on the line still tokenized" 2 --command $'python3 - <<\'A\' 3<<\'B\'\nprint("`the form check (x)`")\nA\nb\nB'
expect_both "prose span: backslash before the interpreter still tokenized" 2 --command $'echo a\\ b; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: input redirection before the interpreter still tokenized" 2 --command $'true <f; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: output redirection before the interpreter still tokenized" 2 --command $'true >f; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: open brace before the interpreter still tokenized" 2 --command $'echo a{; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: close brace before the interpreter still tokenized" 2 --command $'echo a}; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: open paren before the interpreter still tokenized" 2 --command $'echo "("; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: close paren before the interpreter still tokenized" 2 --command $'echo ")"; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: PATH before the interpreter still tokenized" 2 --command $'PATH=/opt/x; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: interpreter word before python still tokenized" 2 --command $'echo python3; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: interpreter word before node still tokenized" 2 --command $'echo node; node - <<\'EOF\'\n'"$rdt_js"
expect_both "prose span: hash before the interpreter still tokenized" 2 --command $'hash -r; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: exec before the interpreter still tokenized" 2 --command $'exec bash; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: reserved word before the interpreter still tokenized" 2 --command $'while false; do :; done; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: alias before the interpreter still tokenized" 2 --command $'alias x=y; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: eval before the interpreter still tokenized" 2 --command $'eval true; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: dot source before the interpreter still tokenized" 2 --command $'. ./defs.sh; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span holding a dollar sign still tokenized" 2 --command $'python3 - <<\'EOF\'\nprint("`the form check ($x)`")\nEOF'
# A shell rebuilds a word before it runs it: it joins adjacent quoted pieces,
# drops backslashes and backslash-newlines, and a printf or echo -e piped into
# a shell decodes escapes. Each span below spells its delete that way and is
# handed to a shell through a variable, so the gate must tokenize it.
rdt_pa=$'python3 - <<\'EOF\'\nimport os\ncmd = '
rdt_pz=$'\nos.system(cmd)\nEOF'
rdt_ja=$'node - <<\'EOF\'\nconst { execSync } = require("child_process");\nconst c = '
rdt_jz=$';\nexecSync(c);\nEOF'
expect_both "python span joining a double-quoted empty piece into rm blocks" 2 --command "$rdt_pa"'"echo `r""m -rf / form`"'"$rdt_pz"
expect_both "python span joining a single-quoted piece into rm blocks" 2 --command "$rdt_pa"$'"echo `\'r\'m -rf / form`"'"$rdt_pz"
expect_both "python span with a backslash inside rm blocks" 2 --command "$rdt_pa"'"echo `r\m -rf / form`"'"$rdt_pz"
expect_both "python span with a backslash-newline inside rm blocks" 2 --command "$rdt_pa"$'"""echo `r\\\nm -rf / form`"""'"$rdt_pz"
expect_both "python span with a quoted piece after a line break blocks" 2 --command "$rdt_pa"$'"""echo `true\n\'r\'m -rf / form`"""'"$rdt_pz"
expect_both "python dollar-paren span joining a quoted piece into rm blocks" 2 --command "$rdt_pa"$'"echo $(r\'\'m -rf / form)"'"$rdt_pz"
expect_both "python span piping a printf octal escape into sh blocks" 2 --command "$rdt_pa"$'r"echo `printf \'r\\155 -rf / form\' | sh`"'"$rdt_pz"
expect_both "python span piping an echo -e hex escape into bash blocks" 2 --command "$rdt_pa"$'r"echo `echo -e \'r\\x6d -rf / form\' | bash`"'"$rdt_pz" # portability-ok: payload text fed to the guard, never run
expect_both "python span with an ANSI-C quoted piece blocks" 2 --command "$rdt_pa"$'"echo `$\'r\'m -rf / form`"'"$rdt_pz"
expect_both "node span joining an empty quoted piece into rm blocks" 2 --command "$rdt_ja"$'"echo `r\'\'m -rf / form`"'"$rdt_jz"
expect_both "node span joining a single-quoted piece into rm blocks" 2 --command "$rdt_ja"$'"echo `\'r\'m -rf / form`"'"$rdt_jz"
expect_both "node span with a backslash inside rm blocks" 2 --command "$rdt_ja"'"echo `r\m -rf / form`"'"$rdt_jz"
expect_both "node span with a backslash-newline inside rm blocks" 2 --command "$rdt_ja"$'"echo `r\\\nm -rf / form`"'"$rdt_jz"
expect_both "node span with a quoted piece after a line break blocks" 2 --command "$rdt_ja"$'`echo \\`true\n\'r\'m -rf / form\\``'"$rdt_jz"
expect_both "node dollar-paren span joining a quoted piece into rm blocks" 2 --command "$rdt_ja"$'"echo $(r\'\'m -rf / form)"'"$rdt_jz"
expect_both "node span piping a printf octal escape into sh blocks" 2 --command "$rdt_ja"$'"echo `printf \'r\\155 -rf / form\' | sh`"'"$rdt_jz"
expect_both "node span piping an echo -e hex escape into bash blocks" 2 --command "$rdt_ja"$'"echo `echo -e \'r\\x6d -rf / form\' | bash`"'"$rdt_jz" # portability-ok: payload text fed to the guard, never run
expect_both "node span with an ANSI-C quoted piece blocks" 2 --command "$rdt_ja"$'"echo `$\'r\'m -rf / form`"'"$rdt_jz"
# Every other way a shell builds or feeds a word sends the span to the
# tokenizer too: a brace, glob, tilde, history or extglob character, a pipe or
# redirection, a backslash other than a \n, \t or \r that ends a word, or an
# interpreter, shell or eval word.
# Each prose twin below fails shfmt once tokenized, which pins the routing.
rdt_pp=$'python3 - <<\'EOF\'\nprint("`the form check (x) '
rdt_pq=$'`")\nEOF'
rdt_jp=$'node - <<\'EOF\'\nconsole.log(`the form check (x) '
rdt_jq=$'`);\nEOF'
expect_both "prose span with a brace still tokenized" 2 --command "$rdt_pp"'{a,b}'"$rdt_pq"
expect_both "prose span with a bracket still tokenized" 2 --command "$rdt_pp"'a[1]'"$rdt_pq"
expect_both "prose span with a star still tokenized" 2 --command "$rdt_pp"'a*'"$rdt_pq"
expect_both "prose span with a question mark still tokenized" 2 --command "$rdt_pp"'a?'"$rdt_pq"
expect_both "prose span with a tilde still tokenized" 2 --command "$rdt_pp"'~a'"$rdt_pq"
expect_both "prose span with a bang still tokenized" 2 --command "$rdt_pp"'a!'"$rdt_pq"
expect_both "prose span with an at sign still tokenized" 2 --command "$rdt_pp"'a@b'"$rdt_pq"
expect_both "prose span with a caret still tokenized" 2 --command "$rdt_pp"'a^b'"$rdt_pq"
expect_both "prose span with a pipe still tokenized" 2 --command "$rdt_pp"'a | b'"$rdt_pq"
expect_both "prose span with a less-than still tokenized" 2 --command "$rdt_pp"'a <b'"$rdt_pq"
expect_both "prose span with a greater-than still tokenized" 2 --command "$rdt_pp"'a >b'"$rdt_pq"
expect_both "prose span with another backslash escape still tokenized" 2 --command "$rdt_pp"'a\q'"$rdt_pq"
expect_both "prose span naming sh still tokenized" 2 --command "$rdt_pp"'via sh'"$rdt_pq"
expect_both "prose span naming eval still tokenized" 2 --command "$rdt_pp"'via eval'"$rdt_pq"
expect_both "prose span with a quote-split stem still tokenized" 2 --command "$rdt_pp"'r""m'"$rdt_pq"
expect_both "node prose span with a brace still tokenized" 2 --command "$rdt_jp"'{a,b}'"$rdt_jq"
expect_both "node prose span with a question mark still tokenized" 2 --command "$rdt_jp"'a?'"$rdt_jq"
expect_both "node prose span with another backslash escape still tokenized" 2 --command "$rdt_jp"'a\q'"$rdt_jq"
expect_both "node prose span with a quote-split stem still tokenized" 2 --command "$rdt_jp"$'r\'\'m'"$rdt_jq"
expect_both "prose span with a tab escape still tokenized" 2 --command "$rdt_pp"'a\tb'"$rdt_pq"
expect_both "node prose span with a newline escape still tokenized" 2 --command "$rdt_jp"'a\nb'"$rdt_jq"
expect_both "prose span naming python3 still tokenized" 2 --command "$rdt_pp"'via python3'"$rdt_pq"
expect_both "node prose span naming node still tokenized" 2 --command "$rdt_jp"'via node'"$rdt_jq"
# A nested interpreter decodes `\t` or `\n` itself, so a span running one
# with that escape before its delete is tokenized and reaches the interpreter
# lane.
expect_both "python span running python3 -c with a tab escape before rm blocks" 2 --command $'python3 <<\'EOF\'\nimport subprocess\nc = r"""echo `python3 -c \'import os;os.system("\\trm -rf /")\'`"""\nsubprocess.run(c, shell=True)\nEOF'
expect_both "python span running python3 -c with a newline escape before rm blocks" 2 --command $'python3 <<\'EOF\'\nimport subprocess\nc = r"""echo `python3 -c \'import os;os.system("true\\nrm -rf /")\'`"""\nsubprocess.run(c, shell=True)\nEOF'
expect_both "python span running node -e with a tab escape before rm blocks" 2 --command $'python3 <<\'EOF\'\nimport subprocess\nc = r"""echo `node -e \'require("child_process").execSync("\\trm -rf /")\'`"""\nsubprocess.run(c, shell=True)\nEOF'
expect_both "python span running ruby -e with a tab escape before rm blocks" 2 --command $'python3 <<\'EOF\'\nimport subprocess\nc = r"""echo `ruby -e \'system("\\trm -rf /")\'`"""\nsubprocess.run(c, shell=True)\nEOF'
expect_both "node span running perl -e with a tab escape before rm blocks" 2 --command $'node <<\'EOF\'\nconst c = "echo `perl -e \'system qq(\\trm -rf /)\'`";\nrequire(\'child_process\').execSync(c);\nEOF'
expect_both "python comment span running python3 -c with a tab escape before rm blocks" 2 --command $'python3 <<\'EOF\'\n# see `python3 -c "import os; os.system(\'\\trm -rf /\')"`\nprint(1)\nEOF'
# The earlier text is read with its quotes removed too, so a name split by
# quotes there still keeps the full scan.
expect_both "prose span: quote-split interpreter word before python still tokenized" 2 --command $'cp /bin/sh ~/bin/py\'\'thon3; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: quote-split interpreter word before node still tokenized" 2 --command $'echo no""de; node - <<\'EOF\'\n'"$rdt_js"
expect_both "prose span: quote-split PATH before the interpreter still tokenized" 2 --command $'PA\'\'TH=/opt/x; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: quote-split hash before the interpreter still tokenized" 2 --command $'ha\'\'sh -r; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: ANSI-C split hash before the interpreter still tokenized" 2 --command $'ha$\'\'sh -r; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: quote-split exec before the interpreter still tokenized" 2 --command $'ex""ec bash; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: quote-split eval before the interpreter still tokenized" 2 --command $'e\'\'val true; python3 - <<\'EOF\'\n'"$rdt_py"
# A tab-stripping opener qualifies. The payload's carriage returns are removed
# before the guard reads the command, so a CRLF opener reads as an LF one.
expect_both "python heredoc with a tab-stripping opener and prose in a backtick span allowed" 0 --command $'python3 - <<-\'EOF\'\nprint("`the form check (x)`")\n\tEOF'
expect_both "python heredoc with a tab-stripping opener and a backticked rm blocks" 2 --command $'python3 - <<-\'EOF\'\nprint("`rm -rf /`")\n\tEOF'
expect_both "python heredoc with a CRLF opener and prose in a backtick span allowed" 0 --command $'python3 - <<\'EOF\'\r\nprint("`the form check (x)`")\r\nEOF\r'
expect_both "python heredoc with a CRLF opener and a backticked rm blocks" 2 --command $'python3 - <<\'EOF\'\r\nprint("`rm -rf /`")\r\nEOF\r'

rdt_finish
