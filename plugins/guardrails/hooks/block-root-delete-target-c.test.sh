#!/usr/bin/env bash
# Contract test for block-root-delete-target.sh (guardrails plugin), part c of 5:
# sections 2k to 2n. The parts are block-root-delete-target.test.sh and
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

rdt_finish
