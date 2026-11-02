#!/usr/bin/env bash
# Contract test for block-root-delete-target.sh (guardrails plugin), part d of 5:
# sections 2o to 4c. The parts are block-root-delete-target.test.sh and
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
# shellcheck source=block-root-delete-target-fixtures.sh
source "$HOOK_DIR/block-root-delete-target-fixtures.sh"
rdt_allowed_roots_fixture
rdt_worktree_fixture

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
expect_both 'PS single-quoted $ name with a trailing \ still blocks (bare variable)' 2 \
  --tool PowerShell --command "Remove-Item -Recurse '\$X\\'"
expect_both 'PS unquoted $env:TEMP still blocks (bare variable)' 2 \
  --tool PowerShell --command 'Remove-Item -Recurse $env:TEMP'
# Stay quiet: a word whose every `$` is literal names a path of that name, which
# pwsh 7 cannot even resolve (`'$env:TEMP'`: "Cannot find drive '$env'"), so it
# is not also read as an expansion.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "PS literal \$ is not read as an expansion: $rdt_cmd" 0 \
    --tool PowerShell --command "$rdt_cmd"
  expect_both "PS literal \$ is not read as an expansion, with cwd: $rdt_cmd" 0 \
    --tool PowerShell "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
Remove-Item -Recurse '$env:TEMP'
Remove-Item -Recurse '$env:TMP'
Remove-Item -Recurse '$env:SystemDrive\'
Remove-Item -Recurse `$env:TEMP
Remove-Item -Recurse '$HOME\x'
Remove-Item -Recurse '$(x)'
cmd /c rd /s /q '$env:TEMP'
EOF
# An expanding outer string expands a `$` before the inner single quotes are
# read, so each such target inside one is still judged as an expansion.
while IFS= read -r rdt_cmd; do
  [[ -n "$rdt_cmd" ]] || continue
  expect_both "PS literal \$ inside an expanding outer string still blocks: $rdt_cmd" 2 \
    --tool PowerShell "${RDT_CWD[@]}" --command "$rdt_cmd"
done <<'EOF'
pwsh -c "Remove-Item -Recurse '$env:TEMP'"
pwsh -c "Remove-Item -Recurse '$env:SystemDrive\'"
pwsh -c "Remove-Item -Recurse `$env:TEMP"
pwsh -c "Remove-Item -Recurse '$HOME\x'"
pwsh -c "Remove-Item -Recurse '$(x)'"
pwsh -c "cmd /c rd /s /q '$env:TEMP'"
iex "Remove-Item -Recurse '$HOME\.ssh'"
Start-Process pwsh -ArgumentList "-c Remove-Item -Recurse '$env:SystemDrive\'"
EOF
# A block comment, a here-string or a typographic quote can put the walk out of
# step with PowerShell's quoting, so a literal `$` is then also read as an
# expansion.
expect_both 'PS a block comment around an expanding string keeps the expansion reading' 2 \
  --tool PowerShell "${RDT_CWD[@]}" \
  --command "<# \" #> iex \"echo; Remove-Item -Recurse '\$env:SystemDrive\\' \" <# \" #>"
expect_both 'PS a here-string keeps the expansion reading' 2 \
  --tool PowerShell "${RDT_CWD[@]}" \
  --command $'iex @"\n# "\nRemove-Item -Recurse \'$env:TEMP\'\n"@'
expect_both 'PS a typographic double quote keeps the expansion reading' 2 \
  --tool PowerShell "${RDT_CWD[@]}" \
  --command "iex "$'\xe2\x80\x9c'"echo; Remove-Item -Recurse '\$env:SystemDrive\\' "$'\xe2\x80\x9d'
# A `$( ... )` inside a double-quoted string is a full script, so a `"` in it
# does not close the string as the walk reads it.
expect_both 'PS a quote inside a $( ) subexpression keeps the expansion reading' 2 \
  --tool PowerShell "${RDT_CWD[@]}" \
  --command $'iex "$(\'"\'.Length) #\'\nRemove-Item -Recurse \'$env:SystemDrive\\\'\n" #"'
# A `${name}` inside a double-quoted string reads its name to the first `}`, so
# a `"` in it does not close the string as the walk reads it.
expect_both 'PS a quote inside a ${ } braced name keeps the expansion reading' 2 \
  --tool PowerShell "${RDT_CWD[@]}" \
  --command $'iex "${a"}; Remove-Item -Recurse \'$env:SystemDrive\\\'"'
# Nested text has lost the outer string's escapes, so a quoting form can appear
# in it that the command itself does not hold; nested text keeps the expansion
# reading.
expect_both 'PS an escaped block comment inside an expanding string keeps the expansion reading' 2 \
  --tool PowerShell "${RDT_CWD[@]}" \
  --command $'iex "<`# `" #> iex `"echo; Remove-Item -Recurse \'`$env:SystemDrive\\\' `" <`# `" #>"'
expect_both 'PS an escaped typographic quote inside an expanding string keeps the expansion reading' 2 \
  --tool PowerShell "${RDT_CWD[@]}" \
  --command $'iex "iex `u{201C}echo; Remove-Item -Recurse \'`$env:SystemDrive\\\' `u{201D}"'
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

rdt_finish
