#!/usr/bin/env bash
# shellcheck disable=SC2016,SC1003

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# shellcheck source=block-root-delete-target-fixtures.sh
source "$HOOK_DIR/block-root-delete-target-fixtures.sh"

rdt_deep=""
for ((rdt_d = 0; rdt_d < 40; rdt_d++)); do rdt_deep="\$($rdt_deep"; done
rdt_deep="${rdt_deep}echo rm"
for ((rdt_d = 0; rdt_d < 40; rdt_d++)); do rdt_deep="$rdt_deep)"; done
expect_both 'substitution nested 40 deep is refused' 2 --command "$rdt_deep"

rdt_pad=""
while ((${#rdt_pad} < 15900)); do rdt_pad+="rm -rf ./x; "; done
rdt_big=""
for ((rdt_d = 0; rdt_d < 32; rdt_d++)); do rdt_big="\$($rdt_big"; done
rdt_big="${rdt_big}${rdt_pad}"
for ((rdt_d = 0; rdt_d < 32; rdt_d++)); do rdt_big="$rdt_big)"; done
rdt_payload="$(command_json "$rdt_big")"
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
rdt_ok=""
while ((${#rdt_ok} < 8180)); do rdt_ok+="echo ok; "; done
expect_both 'a long benign command with one rm-bearing body is allowed' 0 \
  --command "${rdt_ok}\$(echo rm)"

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

expect_both 'runuser -u nested 120 deep is refused' 2 --command "$(rdt_rep 'runuser -u bob -- ' 120)rm -rf /"
expect_both 'runuser -u nested 900 deep is refused' 2 --command "$(rdt_rep 'runuser -u bob -- ' 900)rm -rf /"
expect_both 'su -s /bin/su nested 300 deep is refused' 2 \
  --command "$(rdt_rep 'su root -s /bin/su -- ' 300)root -s /bin/rm -- -rf /"
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

expect_both "python heredoc with prose in a backtick span after assignments allowed" 0 --command $'W=wt; F=docs/x.md; python3 -I - <<\'EOF\'\nimport pathlib\np = pathlib.Path("docs/x.md")\ns = p.read_text()\nold = "- Save awaits `the schedule check before the form check (Reviewer 1\'s race fix)`.\\n"\nnew = "- Save awaits the schedule check.\\n"\nassert old in s\np.write_text(s.replace(old, new))\nEOF\ngh pr view 1'
expect_both "node heredoc with prose in a template literal allowed" 0 --command $'node - <<\'EOF\'\nconst fs = require("fs");\nconst s = `the schedule check before the form check (Reviewer 1\'s race fix)`;\nconsole.log(s);\nEOF'
expect_both "python heredoc with prose in a dollar-paren string allowed" 0 --command $'python3 - <<\'EOF\'\nprint("cost $(the form check (draft))")\nEOF'
expect_both "python heredoc after cd with prose in a backtick span allowed" 0 --command $'cd "$HOME/wt" && python3 - <<\'EOF\'\nold = "- Save awaits `the schedule check before the form check (Reviewer 1\'s race fix)`.\\n"\nprint(old)\nEOF'
expect_both "python heredoc on a later line with prose in a backtick span allowed" 0 --command $'cd sub\npython3 - <<\'EOF\'\nold = "- Save awaits `the schedule check before the form check (Reviewer 1\'s race fix)`.\\n"\nprint(old)\nEOF\ngh pr view 1'
expect_both "python heredoc with a span holding no deleter substring allowed" 0 --command $'W=wt; F=docs/x.md; python3 -I - <<\'EOF\'\nold = "- Save awaits `the schedule check (Reviewer 1\'s race fix)`.\\n"\nprint(old)\nEOF\ngh pr view 1'
expect_both "versioned python with flags and prose in a backtick span allowed" 0 --command $'python3.12 -B -u - <<\'EOF\'\nprint("`the form check (x)`")\nEOF'
expect_both "bare nodejs with prose in a template literal allowed" 0 --command $'nodejs <<"EOF"\nconsole.log(`the form check (x)`);\nEOF'
expect_both "python heredoc piped into sh blocks" 2 --command $'python3 - <<\'EOF\' | sh\nprint("`rm -rf /`")\nEOF'
expect_both "perl heredoc with a backticked rm blocks" 2 --command $'perl - <<\'EOF\'\nprint `rm -rf /`;\nEOF'
expect_both "ruby heredoc with a backticked rm blocks" 2 --command $'ruby - <<\'EOF\'\nputs `rm -rf /`\nEOF'
expect_both "unquoted python heredoc with a backticked rm blocks" 2 --command $'python3 - <<EOF\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc handing a backticked rm to os.system through a variable blocks" 2 --command $'python3 - <<\'EOF\'\nimport os\ncmd = "echo `rm -rf /`"\nos.system(cmd)\nEOF'
expect_both "python heredoc handing a dollar-paren rm to a shell through concatenation blocks" 2 --command $'python3 - <<\'EOF\'\nimport subprocess\nsubprocess.run("echo " + "$(rm -rf /)", shell=True)\nEOF'
expect_both "python heredoc handing a backticked rm to asyncio blocks" 2 --command $'python3 - <<\'EOF\'\nimport asyncio\nasyncio.run(asyncio.create_subprocess_shell("echo `rm -rf /`"))\nEOF'
expect_both "node heredoc handing a dollar-paren rm to execSync through a variable blocks" 2 --command $'node - <<\'EOF\'\nconst { execSync } = require("child_process");\nconst c = "echo $(rm -rf /)";\nexecSync(c);\nEOF'
expect_both "python heredoc handing a backslashed rm to os.system blocks" 2 --command $'python3 - <<\'EOF\'\nimport os\ncmd = "echo `\\rm -rf /`"\nos.system(cmd)\nEOF'
expect_both "python heredoc in a brace group piped into sh blocks" 2 --command $'{\npython3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF\n} | sh'
expect_both "python heredoc in an if piped into sh blocks" 2 --command $'if true; then\npython3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF\nfi | sh'
expect_both "python heredoc after exec into a sh process substitution blocks" 2 --command $'exec > >(sh)\npython3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc behind a clobber into bash -c blocks" 2 --command $'bash -c sh >|python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc behind a clobber into sh -s blocks" 2 --command $'sh -s >|python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc behind an escaped semicolon blocks" 2 --command $'bash -s \\; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python -c running its stdin heredoc blocks" 2 --command $'python3 -Ic \'import os,sys; os.system(sys.stdin.read())\' <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "node --eval running its stdin heredoc blocks" 2 --command $'node --eval \'require("child_process").execSync(require("fs").readFileSync(0, "utf8"))\' - <<\'EOF\'\necho `rm -rf /`\nEOF'
expect_both "python heredoc reading a second heredoc on fd 3 blocks" 2 --command $'python3 - <<\'A\' 3<<\'B\'\nimport os\nos.system(os.fdopen(3).read())\nA\necho `rm -rf /`\nB'
expect_both "python heredoc after python3 redefined as a function blocks" 2 --command $'python3() { bash; }; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "node heredoc after node redefined as a function blocks" 2 --command $'node() { bash; }; node - <<\'EOF\'\nconsole.log("`rm -rf /`")\nEOF'
expect_both "python heredoc with a PATH prefix blocks" 2 --command $'PATH=/opt/evil:$PATH python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc after a PATH assignment blocks" 2 --command $'PATH=/opt/evil; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc after hash -p blocks" 2 --command $'hash -p /bin/sh python3; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc after a copy over python3 blocks" 2 --command $'cp /bin/sh ~/bin/python3; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc after an alias blocks" 2 --command $'shopt -s expand_aliases\nalias python3=bash\npython3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc after eval blocks" 2 --command $'eval "$x"; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
expect_both "python heredoc after a dot source blocks" 2 --command $'. ./defs.sh; python3 - <<\'EOF\'\nprint("`rm -rf /`")\nEOF'
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
expect_both "python heredoc calling os.system on a literal rm blocks" 2 --command $'python3 - <<\'EOF\'\nimport os\nos.system(\'rm -rf /\')\nEOF'
expect_both "python heredoc removing the root tree before a trailing command blocks" 2 --command $'W=x; F=y; python3 - <<\'EOF\'\nimport shutil\nshutil.rmtree(\'/\')\nEOF\ngh pr view 1'
expect_both "node heredoc running a template-literal rm blocks" 2 --command $'node - <<\'EOF\'\nrequire("child_process").execSync(`rm -rf /`);\nEOF'
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
expect_both "python span running python3 -c with a tab escape before rm blocks" 2 --command $'python3 <<\'EOF\'\nimport subprocess\nc = r"""echo `python3 -c \'import os;os.system("\\trm -rf /")\'`"""\nsubprocess.run(c, shell=True)\nEOF'
expect_both "python span running python3 -c with a newline escape before rm blocks" 2 --command $'python3 <<\'EOF\'\nimport subprocess\nc = r"""echo `python3 -c \'import os;os.system("true\\nrm -rf /")\'`"""\nsubprocess.run(c, shell=True)\nEOF'
expect_both "python span running node -e with a tab escape before rm blocks" 2 --command $'python3 <<\'EOF\'\nimport subprocess\nc = r"""echo `node -e \'require("child_process").execSync("\\trm -rf /")\'`"""\nsubprocess.run(c, shell=True)\nEOF'
expect_both "python span running ruby -e with a tab escape before rm blocks" 2 --command $'python3 <<\'EOF\'\nimport subprocess\nc = r"""echo `ruby -e \'system("\\trm -rf /")\'`"""\nsubprocess.run(c, shell=True)\nEOF'
expect_both "node span running perl -e with a tab escape before rm blocks" 2 --command $'node <<\'EOF\'\nconst c = "echo `perl -e \'system qq(\\trm -rf /)\'`";\nrequire(\'child_process\').execSync(c);\nEOF'
expect_both "python comment span running python3 -c with a tab escape before rm blocks" 2 --command $'python3 <<\'EOF\'\n# see `python3 -c "import os; os.system(\'\\trm -rf /\')"`\nprint(1)\nEOF'
expect_both "prose span: quote-split interpreter word before python still tokenized" 2 --command $'cp /bin/sh ~/bin/py\'\'thon3; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: quote-split interpreter word before node still tokenized" 2 --command $'echo no""de; node - <<\'EOF\'\n'"$rdt_js"
expect_both "prose span: quote-split PATH before the interpreter still tokenized" 2 --command $'PA\'\'TH=/opt/x; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: quote-split hash before the interpreter still tokenized" 2 --command $'ha\'\'sh -r; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: ANSI-C split hash before the interpreter still tokenized" 2 --command $'ha$\'\'sh -r; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: quote-split exec before the interpreter still tokenized" 2 --command $'ex""ec bash; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "prose span: quote-split eval before the interpreter still tokenized" 2 --command $'e\'\'val true; python3 - <<\'EOF\'\n'"$rdt_py"
expect_both "python heredoc with a tab-stripping opener and prose in a backtick span allowed" 0 --command $'python3 - <<-\'EOF\'\nprint("`the form check (x)`")\n\tEOF'
expect_both "python heredoc with a tab-stripping opener and a backticked rm blocks" 2 --command $'python3 - <<-\'EOF\'\nprint("`rm -rf /`")\n\tEOF'
expect_both "python heredoc with a CRLF opener and prose in a backtick span allowed" 0 --command $'python3 - <<\'EOF\'\r\nprint("`the form check (x)`")\r\nEOF\r'
expect_both "python heredoc with a CRLF opener and a backticked rm blocks" 2 --command $'python3 - <<\'EOF\'\r\nprint("`rm -rf /`")\r\nEOF\r'

rdt_finish
