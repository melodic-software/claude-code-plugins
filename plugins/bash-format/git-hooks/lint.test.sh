#!/usr/bin/env bash
# test-scope: plugins/bash-format/.claude-plugin/plugin.json
# test-scope: plugins/bash-format/git-hooks/entries.json plugins/bash-format/git-hooks/adapters.sh
# test-scope: plugins/bash-format/lib/git-hooks/check-lib.sh plugins/bash-format/lib/git-hooks/resolve-tool.sh
# shellcheck disable=SC2016 # fixtures hold literal shell text, not expansions
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/lint.sh"
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not on PATH -- lint tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

# shellcheck source=bash-format-test-helpers.sh
source "$HERE/bash-format-test-helpers.sh"

EC=$'[*.sh]\nindent_style = space\nindent_size = 2'
n=0
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  printf '%s\n' "$EC" >"$REPO/.editorconfig"
  if [[ "${1:-}" != NONE ]]; then
    printf '%s\n' "${1:-# ShellCheck settings of the repository}" >"$REPO/.shellcheckrc"
  fi
  printf '#!/usr/bin/env bash\necho seed\n' >"$REPO/seed.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m seed --no-verify
}

SHEBANG='#!/usr/bin/env bash'
TABBED="$SHEBANG"$'\nif true; then\n\techo hi\nfi'
SPACED="$SHEBANG"$'\nif true; then\n  echo hi\nfi'
HINT='bash-format: fix the findings above, or adjust the repository .shellcheckrc.'

mkdir -p "$WORK/sc-stub"
cat >"$WORK/sc-stub/shellcheck" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then
  printf 'ShellCheck - shell script analysis tool\nversion: %s\n' "${SC_STUB_VERSION:-0.11.0}"
  exit 0
fi
printf '%s\n' "$*" >>"$SC_STUB_LOG.argv"
len=0
dfa_off=""
for a in "$0" "$@"; do
  len=$((len + ${#a} + 1))
  [[ "$a" == --extended-analysis=false ]] && dfa_off=1
done
if ((len > 32767)); then
  echo "shellcheck: Argument list too long" >&2
  exit 126
fi
if [[ "${!#}" == - ]]; then
  stdin="$(cat)"
  [[ -n "$dfa_off" ]] && printf -- '-:%s\n' "$(($(wc -l <<<"$stdin")))" >>"$SC_STUB_LOG.dfa-off"
  [[ "$stdin" == *'stub: finding'* ]] || exit 0
  echo '-:2:1: warning: stub finding [SC2154]'
  exit 1
fi
while [[ $# -gt 0 && "$1" != -- ]]; do shift; done
if [[ -n "$dfa_off" && $# -gt 0 ]]; then
  printf '%s\n' "${@:2}" >>"$SC_STUB_LOG.dfa-off"
fi
shift
echo -- >>"$SC_STUB_LOG"
rc=0
for f in "$@"; do
  printf '%s\n' "$f" >>"$SC_STUB_LOG"
  case "$f" in
  *-broken.sh) rc=2 ;;
  *-mute.sh)
    echo "stub: internal confusion"
    ((rc < 1)) && rc=1
    ;;
  *)
    if [[ "$f" == *-finding.sh ]] || grep -q 'stub: finding' "$f"; then
      printf '%s:2:1: warning: stub finding [SC2154]\n' "$f"
      ((rc < 1)) && rc=1
    fi
    ;;
  esac
done
exit "$rc"
STUB
chmod +x "$WORK/sc-stub/shellcheck"
sc_stub() {
  : >"$WORK/sc.log"
  : >"$WORK/sc.log.dfa-off"
  : >"$WORK/sc.log.argv"
  local out
  out="$(cd "$1" && SC_STUB_LOG="$WORK/sc.log" PATH="$WORK/sc-stub:$PATH" bash "$CHECK" 2>&1)"
  printf '%s|%s' "$?" "$out"
}
# 250 paths of about 150 characters: about 37,000 in all, past the cap, while
# each path stays under Windows' 260-character MAX_PATH once a temp dir prefixes it.
LONG="$(printf 'd%.0s' {1..60})/$(printf 'f%.0s' {1..80})"
new_repo
mkdir -p "$REPO/${LONG%/*}"
for i in {1..250}; do
  printf '#!/bin/bash\necho ok %s\n' "$i" >"$REPO/$LONG-$i.sh"
done
git -C "$REPO" add -A
expect "many long staged paths: the hook passes" "0|" "$(sc_stub "$REPO")"
expect "many long staged paths: shellcheck ran in more than one call" yes \
  "$( (($(grep -cx -- -- "$WORK/sc.log") > 1)) && echo yes)"
expect "many long staged paths: each path reached shellcheck exactly once" \
  "$(git -C "$REPO" diff --cached --name-only | sort)" "$(grep -vx -- -- "$WORK/sc.log" | sort)"
printf '%s\necho a\n' "$SHEBANG" >"$REPO/a-finding.sh"
printf '%s\necho z\n' "$SHEBANG" >"$REPO/z-finding.sh"
git -C "$REPO" add a-finding.sh z-finding.sh
expect "a finding from the first batch and one from the last both block" "1|a-finding.sh:2: warning: stub finding [SC2154]
z-finding.sh:2: warning: stub finding [SC2154]
$HINT" "$(sc_stub "$REPO")"
git -C "$REPO" rm -q --cached a-finding.sh z-finding.sh
rm "$REPO/a-finding.sh" "$REPO/z-finding.sh"
printf '%s\necho broken\n' "$SHEBANG" >"$REPO/a-broken.sh"
git -C "$REPO" add a-broken.sh
out="$(sc_stub "$REPO")"
expect "a first batch's status above 1 still blocks after a later batch passes" \
  "1|bash-format: shellcheck failed:" "${out%%$'\n'*}"

new_repo
for f in a b c d e f g h; do
  printf '%s\necho %s\n' "$SHEBANG" "$f" >"$REPO/$f.sh"
done
printf '%s\necho broken\n' "$SHEBANG" >"$REPO/z-broken.sh"
git -C "$REPO" add -A
out="$(sc_stub "$REPO")"
expect "one parallel lane's status above 1 fails the hook though every other lane passes" \
  "1|bash-format: shellcheck failed:" "${out%%$'\n'*}"
rm "$REPO/z-broken.sh"
printf '%s\necho z\n' "$SHEBANG" >"$REPO/z-finding.sh"
git -C "$REPO" add -A
expect "one parallel lane's finding blocks though every other lane passes" "1|z-finding.sh:2: warning: stub finding [SC2154]
$HINT" "$(sc_stub "$REPO")"

new_repo
{
  printf '%s\n' "$SHEBANG"
  for i in {1..2000}; do printf 'echo %s\n' "$i"; done
} >"$REPO/big.sh"
head -n 2000 "$REPO/big.sh" >"$REPO/edge.sh"
printf '%s\necho small\n' "$SHEBANG" >"$REPO/small.sh"
git -C "$REPO" add big.sh edge.sh small.sh
expect "over 2,000 lines: only that script is linted without dataflow analysis" "0||big.sh" \
  "$(sc_stub "$REPO")|$(cat "$WORK/sc.log.dfa-off")"
expect "over 2,000 lines: every script is still linted once" "big.sh
edge.sh
small.sh" "$(grep -vx -- -- "$WORK/sc.log" | sort)"
expect "over 2,000 lines with a ShellCheck older than 0.10: full analysis, no flag it would reject" "0||" \
  "$(SC_STUB_VERSION=0.9.0 sc_stub "$REPO")|$(cat "$WORK/sc.log.dfa-off")"
git -C "$REPO" commit -q -m big --no-verify
printf 'echo staged\n' >>"$REPO/big.sh"
git -C "$REPO" add big.sh
printf 'echo unstaged\n' >>"$REPO/big.sh"
expect "partly staged over 2,000 lines: linted from the index without dataflow analysis" "0||-:2002" \
  "$(sc_stub "$REPO")|$(cat "$WORK/sc.log.dfa-off")"
expect "partly staged over 2,000 lines: the index call carries the flag" "-x -f gcc -S warning --extended-analysis=false -" \
  "$(grep -- ' -$' "$WORK/sc.log.argv")"

new_repo
mkdir -p "$REPO/x" "$REPO/y"
{
  printf '%s\n' "$SHEBANG"
  for i in {1..2000}; do printf 'echo %s\n' "$i"; done
} >"$REPO/x/big.sh"
cp "$REPO/x/big.sh" "$REPO/y/big.sh"
git -C "$REPO" add x/big.sh y/big.sh
expect "copies over 2,000 lines in two directories: the source probe and the lint run without dataflow analysis" "0||-:2001
x/big.sh" "$(sc_stub "$REPO")|$(cat "$WORK/sc.log.dfa-off")"
expect "copies over 2,000 lines in two directories: the source probe carries the flag" \
  "--norc --extended-analysis=false -s bash -f gcc -S info -" "$(grep -- '^--norc' "$WORK/sc.log.argv")"

new_repo
printf '%s\necho m\n' "$SHEBANG" >"$REPO/a-mute.sh"
git -C "$REPO" add a-mute.sh
expect "exit 1 with no <path>:<line> finding fails closed and shows the output" \
  "1|bash-format: shellcheck exited 1 and reported no <path>:<line> finding, so the change was not checked:
stub: internal confusion" "$(sc_stub "$REPO")"

new_repo
printf '%s\necho d\n' "$SHEBANG" >"$REPO/-x-finding.sh"
git -C "$REPO" add -- -x-finding.sh
expect "a leading-dash name is passed as a path and its finding names it" "1|-x-finding.sh:2: warning: stub finding [SC2154]
$HINT" "$(sc_stub "$REPO")"

new_repo
printf '%s\n: stub: finding\necho before\n' "$SHEBANG" >"$REPO/b-copy.sh"
git -C "$REPO" add b-copy.sh
git -C "$REPO" commit -q -m b --no-verify
for f in a-copy.sh b-copy.sh c-copy.sh; do
  printf '%s\n: stub: finding\necho same\n' "$SHEBANG" >"$REPO/$f"
done
printf '%s\necho other\n' "$SHEBANG" >"$REPO/d-other.sh"
git -C "$REPO" add a-copy.sh b-copy.sh c-copy.sh d-other.sh
expect "identical copies: every copy whose added lines hold the finding reports it" "1|a-copy.sh:2: warning: stub finding [SC2154]
c-copy.sh:2: warning: stub finding [SC2154]
$HINT" "$(sc_stub "$REPO")"
expect "identical copies are linted once, differing content still each" "a-copy.sh
d-other.sh" "$(grep -vx -- -- "$WORK/sc.log" | sort)"

new_repo NONE
printf '%s\necho a\n' "$SHEBANG" >"$REPO/a-finding.sh"
git -C "$REPO" add a-finding.sh
expect "no .shellcheckrc: ShellCheck still runs and its finding blocks" "1|a-finding.sh:2: warning: stub finding [SC2154]
$HINT" "$(sc_stub "$REPO")"
new_repo NONE
mkdir -p "$REPO/pkg" "$REPO/other"
printf 'shell=bash\n' >"$REPO/pkg/.shellcheckrc"
printf '%s\necho p\n' "$SHEBANG" >"$REPO/pkg/p-finding.sh"
printf '%s\necho o\n' "$SHEBANG" >"$REPO/other/o-finding.sh"
git -C "$REPO" add pkg other
expect "scripts with and without an rc above them are both linted" "1|other/o-finding.sh:2: warning: stub finding [SC2154]
pkg/p-finding.sh:2: warning: stub finding [SC2154]
$HINT" "$(sc_stub "$REPO")"

expect "--resolve names the adapter and the first rc it finds" "bash-format	lint	adapter:shellcheck	shellcheck	yes	config pkg/.shellcheckrc; binary shellcheck on PATH" \
  "$(cd "$REPO" && PATH="$WORK/sc-stub:$PATH" bash "$CHECK" --resolve)"
expect "--resolve <path>: one row per file, the governing rc or ShellCheck's defaults" "bash-format	lint	adapter:shellcheck	shellcheck	yes	config pkg/.shellcheckrc; binary shellcheck on PATH
bash-format	lint	adapter:shellcheck	shellcheck	yes	config none (ShellCheck defaults); binary shellcheck on PATH" \
  "$(cd "$REPO" && PATH="$WORK/sc-stub:$PATH" bash "$CHECK" --resolve pkg/p-finding.sh other/o-finding.sh)"
new_repo NONE
mkdir -p "$REPO/.claude/ecosystems"
printf 'globs: ["*.sh"]\nlint-cmd: "stublint <files>"\n' >"$REPO/.claude/ecosystems/bash.yaml"
expect "--resolve with no rc resolves to ShellCheck's defaults, and says hooks never run the bash record" "bash-format	lint	adapter:shellcheck	shellcheck	yes	config none (ShellCheck defaults); binary shellcheck on PATH; the bash record is not run by hooks; /toolchain:lint and /toolchain:check run it" \
  "$(cd "$REPO" && PATH="$WORK/sc-stub:$PATH" bash "$CHECK" --resolve)"

for tool in shellcheck jq node; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP: $tool not on PATH -- the remaining lint tests skipped"
    echo "lint: $PASS passed, $FAIL failed"
    exit $((FAIL > 0))
  fi
done

new_repo
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "a clean staged script passes and is never rewritten" "0||" "$(check "$REPO")"
expect "lint leaves the bytes as written" "$TABBED" "$(cat "$REPO/a.sh")"

DRIFT='config differs between the index and the work tree; stage it or restore it, then commit'
new_repo
mkdir -p "$REPO/pkg"
printf 'disable=SC2154\n' >"$REPO/pkg/.shellcheckrc"
printf '%s\n' "$TABBED" >"$REPO/pkg/a.sh"
git -C "$REPO" add pkg
printf 'disable=SC2034\n' >"$REPO/pkg/.shellcheckrc"
expect "a nested .shellcheckrc edited after staging refuses the commit" "1||pkg/.shellcheckrc: $DRIFT" "$(check "$REPO")"

new_repo
printf '%s\necho staged\n' "$SHEBANG" >"$REPO/a.sh"
git -C "$REPO" add a.sh
printf '%s\necho staged\necho "$undefined_var"\n' "$SHEBANG" >"$REPO/a.sh"
expect "partly staged: a finding only in the unstaged lines does not block" "0||" "$(check "$REPO")"
printf '%s\necho "$undefined_var"\n' "$SHEBANG" >"$REPO/a.sh"
git -C "$REPO" add a.sh
printf '%s\necho fixed\necho unstaged\n' "$SHEBANG" >"$REPO/a.sh"
expect "partly staged: a staged finding blocks though the work tree fixed it" "1||a.sh:2: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(check "$REPO")"

new_repo
printf '%s\necho "$undefined_var"\n' "$SPACED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "a finding on an added line blocks, naming that line" "1||a.sh:5: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(check "$REPO")"

new_repo
mkdir -p "$REPO/bin"
printf '%s\necho "$undefined_var"\n' "$TABBED" >"$REPO/bin/gone.sh"
git -C "$REPO" add bin/gone.sh
rm -r "${REPO:?}/bin"
expect "staged then deleted from the work tree: the staged finding still blocks" "1||bin/gone.sh:5: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(check "$REPO")"
expect "staged then deleted: the script is not recreated" "no" "$([[ -e "$REPO/bin/gone.sh" ]] && echo yes || echo no)"
git -C "$REPO" rm -q --cached bin/gone.sh
ln -s missing.sh "$REPO/link.sh"
git -C "$REPO" add link.sh
rm "$REPO/link.sh"
expect "staged then deleted: a staged symlink is not checked" "0||" "$(check "$REPO")"

new_repo
printf '%s\necho "$undefined_var"\n' "$SHEBANG" >"$REPO/seed.sh"
git -C "$REPO" add seed.sh
git -C "$REPO" commit -q -m old --no-verify
printf '%s\necho "$undefined_var"\necho ok\n' "$SHEBANG" >"$REPO/seed.sh"
git -C "$REPO" add seed.sh
expect "a finding on a line the commit did not add does not block" "0||" "$(check "$REPO")"

new_repo
printf '%s\nif true; then\necho "$undefined_var"\nfi\n' "$SHEBANG" >"$REPO/seed.sh"
git -C "$REPO" add seed.sh
git -C "$REPO" commit -q -m old --no-verify
printf '%s\nif true; then\n  echo "$undefined_var"\nfi\n' "$SHEBANG" >"$REPO/seed.sh"
git -C "$REPO" add seed.sh
expect "a finding on a line the commit only reindented blocks" "1||seed.sh:3: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(check "$REPO")"

new_repo
printf '%s\nunused_variable=1\n' "$SHEBANG" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "a warning-level finding (SC2034) blocks" "1||a.sh:2: warning: unused_variable appears unused. Verify use (or export if used externally). [SC2034]
$HINT" "$(check "$REPO")"

new_repo
printf '%s\necho $1\n' "$SHEBANG" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "an info-level finding (SC2086) does not block" "0||" "$(check "$REPO")"

new_repo
rm "$REPO/.editorconfig"
git -C "$REPO" commit -q -am 'no editorconfig' --no-verify
printf '%s\necho "$undefined_var"\n' "$SHEBANG" >"$REPO/a.sh"
git -C "$REPO" add a.sh
expect "no .editorconfig: ShellCheck still reports" "1||a.sh:2: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(check "$REPO")"

mkdir -p "$WORK/sc-count"
printf '%s\nprintf "%%s\\n" "$*" >>"$SC_COUNT_LOG"\nexec %q "$@"\n' "$SHEBANG" "$(command -v shellcheck)" >"$WORK/sc-count/shellcheck"
chmod +x "$WORK/sc-count/shellcheck"
sc_count() {
  : >"$WORK/count.log"
  local out
  out="$(cd "$1" && SC_COUNT_LOG="$WORK/count.log" PATH="$WORK/sc-count:$PATH" bash "$CHECK" 2>&1)"
  printf '%s|%s' "$?" "$out"
}
linted() {
  grep -c -- "-x .* $1\( \|\$\)" "$WORK/count.log"
}
UNDEF="$SHEBANG"$'\necho "$undefined_var"'

new_repo
mkdir -p "$REPO/x" "$REPO/y"
printf '%s\n' "$UNDEF" >"$REPO/x/a.sh"
printf '%s\n' "$UNDEF" >"$REPO/y/a.sh"
git -C "$REPO" add x y
expect "copies in two directories that source nothing: each copy reports the finding" "1|x/a.sh:2: warning: undefined_var is referenced but not assigned. [SC2154]
y/a.sh:2: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(sc_count "$REPO")"
expect "copies in two directories that source nothing: linted once" "1|0" "$(linted x/a.sh)|$(linted y/a.sh)"

new_repo
mkdir -p "$REPO/pkg"
printf 'disable=SC2154\n' >"$REPO/pkg/.shellcheckrc"
printf '%s\n' "$UNDEF" >"$REPO/a.sh"
printf '%s\n' "$UNDEF" >"$REPO/pkg/a.sh"
git -C "$REPO" add a.sh pkg
expect "a copy under its own .shellcheckrc is linted apart: its rc disables the finding" "1|a.sh:2: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(sc_count "$REPO")"
expect "a copy under its own .shellcheckrc: both copies linted" "1|1" "$(linted a.sh)|$(linted pkg/a.sh)"

new_repo $'source-path=SCRIPTDIR\nexternal-sources=true'
mkdir -p "$REPO/x" "$REPO/y"
printf '%s\nsource helper.sh\necho "$v"\n' "$SHEBANG" >"$REPO/x/a.sh"
printf '%s\nsource helper.sh\necho "$v"\n' "$SHEBANG" >"$REPO/y/a.sh"
printf '# shellcheck shell=bash\nv=1\nexport v\n' >"$REPO/x/helper.sh"
printf '# shellcheck shell=bash\n:\n' >"$REPO/y/helper.sh"
git -C "$REPO" add x/a.sh y/a.sh
expect "copies that source a file from their own directory are linted apart" "1|y/a.sh:3: warning: v is referenced but not assigned. [SC2154]
$HINT" "$(sc_count "$REPO")"

new_repo
mkdir -p "$REPO/x" "$REPO/y"
printf '%s\n# shellcheck disable=SC1091\nif true; then\necho (\nsource helper.sh\n' "$SHEBANG" >"$REPO/x/a.sh"
cp "$REPO/x/a.sh" "$REPO/y/a.sh"
git -C "$REPO" add x y
sc_count "$REPO" >/dev/null
expect "copies the probe cannot read (a parse error, a disabled SC1091) are linted apart" "1|1" "$(linted x/a.sh)|$(linted y/a.sh)"

new_repo
mkdir -p "$REPO/.githooks/bash-format"
printf '%s\necho "$undefined_var"\n' "$SHEBANG" >"$REPO/.githooks/bash-format/copy.sh"
git -C "$REPO" add -f .githooks/bash-format/copy.sh
expect "an installed copy under .githooks/ is skipped" "0||" "$(check "$REPO")"
mkdir -p "$REPO/sub/.githooks"
printf '%s\necho "$undefined_var"\n' "$SHEBANG" >"$REPO/sub/.githooks/own.sh"
git -C "$REPO" add -f sub/.githooks/own.sh
expect "a script under a nested .githooks/ is linted; only the root one is skipped" "1||sub/.githooks/own.sh:2: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(check "$REPO")"

new_repo
printf '%s\necho "$undefined_var"\n' "$TABBED" >"$REPO/a.sh"
expect "--worktree: an uncommitted finding blocks and nothing is rewritten" "1||a.sh:5: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(check "$REPO" --worktree)"
expect "--worktree: the file keeps its bytes" "$TABBED"$'\necho "$undefined_var"' "$(cat "$REPO/a.sh")"
printf '%s\necho "$undefined_var"\n' "$SHEBANG" >"$REPO/a.sh"
expect "--worktree: an untracked file is checked whole" "1||a.sh:2: warning: undefined_var is referenced but not assigned. [SC2154]
$HINT" "$(check "$REPO" --worktree)"
rm "$REPO/a.sh"
expect "--worktree: no uncommitted change passes" "0||" "$(check "$REPO" --worktree)"

merge_repo
expect "merge: the merge is in progress" yes "$([[ -f "$REPO/.git/MERGE_HEAD" ]] && echo yes)"
expect "merge: an inherited script with a finding passes" "0||" "$(check "$REPO")"
merge_repo
printf 'cd /var\n' >>"$REPO/x.sh"
git -C "$REPO" add x.sh
out="$(check "$REPO")"
rest="${out#*|}"
expect "merge: a script the resolution edits blocks, nothing listed" "1|" "${out%%|*}|${rest%%|*}"
expect "merge: the findings include the appended line" yes \
  "$(grep -q '^x\.sh:5: warning: .*\[SC2164\]$' <<<"${rest#*|}" && echo yes)"

mkdir -p "$WORK/no-shellcheck"
for t in git bash sh sed awk cat mktemp rm dirname grep tr head jq; do
  ln -s "$(command -v "$t")" "$WORK/no-shellcheck/$t"
done

SC_INSTALL='see https://github.com/koalaman/shellcheck#installing'
new_repo
printf '%s\n' "$TABBED" >"$REPO/a.sh"
git -C "$REPO" add a.sh
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shellcheck" bash "$CHECK" 2>&1)"
expect "missing shellcheck: an agent fails with the install command" "1" "$?"
expect "missing shellcheck: the message names the tool and the skip key" \
  "FAIL: shellcheck missing. Install: $SC_INSTALL
To skip only while shellcheck is missing: git -c checks.skipmissing=shellcheck commit ..." "$out"
out="$(cd "$REPO" && PATH="$WORK/no-shellcheck" bash "$CHECK" 2>&1)"
expect "missing shellcheck: a person gets a notice and exit 0" "0|NOTICE: shellcheck missing, so this check did not run. Install: $SC_INSTALL" "$?|$out"
git -C "$REPO" config checks.skipmissing shellcheck
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shellcheck" bash "$CHECK" 2>&1)"
expect "missing shellcheck named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: shellcheck (missing)" "$?|$out"
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shellcheck" bash "$CHECK" --worktree 2>&1)"
expect "missing shellcheck named in checks.skipmissing, --worktree: skipped with a line" "0|SKIPPED: shellcheck (missing)" "$?|$out"
git -C "$REPO" config --unset checks.skipmissing
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$WORK/no-shellcheck" bash "$CHECK" --worktree 2>&1)"
expect "missing shellcheck, --worktree: an agent fails as at commit time" \
  "1|FAIL: shellcheck missing. Install: $SC_INSTALL" "$?|${out%%$'\n'*}"

if command -v shellcheck >/dev/null 2>&1; then
  STD="$WORK/standards"
  mkdir -p "$STD" "$WORK/home"
  printf 'disable=SC2154\n' >"$STD/.shellcheckrc"
  UNSET="$SHEBANG"$'\necho "$never_assigned"'
  opt_in() {
    mkdir -p "$REPO/docs/conventions"
    printf 'standards_repository: acme/standards\n' >"$REPO/docs/conventions/source-control.yaml"
  }
  std_check() { HOME="$WORK/home" STANDARDS_DIR="$1" check "$REPO"; }
  new_repo NONE
  opt_in
  printf '%s\n' "$UNSET" >"$REPO/u.sh"
  git -C "$REPO" add -A
  expect "standards default: the standards .shellcheckrc's disable holds" "0||" "$(std_check "$STD")"
  expect "standards default, control: with no standards checkout SC2154 blocks" "1||u.sh:2: warning: never_assigned is referenced but not assigned. [SC2154]
$HINT" "$(std_check "$WORK/nowhere")"
  expect "standards default: --resolve names the standards rc" \
    "bash-format	lint	adapter:shellcheck	shellcheck	yes	config the standards .shellcheckrc; binary shellcheck on PATH" \
    "$(cd "$REPO" && HOME="$WORK/home" STANDARDS_DIR="$STD" bash "$CHECK" --resolve)"
  printf '%s\necho edited\n' "$UNSET" >"$REPO/u.sh"
  expect "standards default: a partly staged script is linted from the index with the standards rc" "0||" "$(std_check "$STD")"
  new_repo '# the repository rc'
  opt_in
  printf '%s\n' "$UNSET" >"$REPO/u.sh"
  git -C "$REPO" add -A
  expect "standards replace: the repository's .shellcheckrc replaces the standards rc whole" "1||u.sh:2: warning: never_assigned is referenced but not assigned. [SC2154]
$HINT" "$(std_check "$STD")"
else
  echo "SKIP: shellcheck not on PATH -- standards rc cases skipped"
fi

echo "lint: $PASS passed, $FAIL failed"
((FAIL == 0))
