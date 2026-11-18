#!/usr/bin/env bash
# test-scope: plugins/bash-format/.claude-plugin/plugin.json plugins/bash-format/git-hooks/lint.sh
# test-scope: plugins/bash-format/git-hooks/entries.json plugins/bash-format/git-hooks/adapters.sh
# test-scope: plugins/bash-format/lib/git-hooks/check-lib.sh plugins/bash-format/lib/git-hooks/resolve-tool.sh
# shellcheck disable=SC2016 # fixtures hold literal shell text, not expansions
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/lint-full.sh"
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not on PATH -- lint-full tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
expect() {
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

SHEBANG='#!/usr/bin/env bash'
HINT='bash-format: fix the findings above, or adjust the repository .shellcheckrc.'
n=0
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  printf '# ShellCheck settings of the repository\n' >"$REPO/.shellcheckrc"
  printf '%s\necho seed\n' "$SHEBANG" >"$REPO/seed.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m seed --no-verify
  BASE="$(git -C "$REPO" rev-parse HEAD)"
}
big() {
  {
    printf '%s\n' "$SHEBANG"
    for ((i = 1; i <= $2; i++)); do printf 'echo %s\n' "$i"; done
    [[ -z "${3:-}" ]] || printf '%s\n' "$3"
  } >"$1"
}
line2() {
  awk -v t="$2" 'NR == 2 { $0 = t } 1' "$1" >"$1.new" && mv "$1.new" "$1"
}
commit() {
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m change --no-verify
}
push() {
  local out tip
  tip="$(git -C "$1" rev-parse HEAD)"
  out="$(cd "$1" && printf 'refs/heads/main %s refs/heads/main %s\n' "$tip" "$BASE" |
    PATH="${2:+$2:}$PATH" SC_STUB_LOG="$WORK/sc.log" bash "$CHECK" origin "$WORK/remote.git" 2>&1)"
  printf '%s|%s' "$?" "$out"
}

mkdir -p "$WORK/sc-stub"
cat >"$WORK/sc-stub/shellcheck" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then
  printf 'ShellCheck - shell script analysis tool\nversion: %s\n' "${SC_STUB_VERSION:-0.11.0}"
  exit 0
fi
printf '%s\n' "$*" >>"$SC_STUB_LOG"
while [[ $# -gt 0 && "$1" != -- ]]; do shift; done
shift
rc=0
for f in "$@"; do
  grep -q 'stub: finding' "$f" || continue
  printf '%s:2:1: warning: stub finding [SC2154]\n' "$f"
  rc=1
done
exit "$rc"
STUB
chmod +x "$WORK/sc-stub/shellcheck"
stub() {
  : >"$WORK/sc.log"
  printf '%s|%s' "$(push "$1" "$WORK/sc-stub")" "$(sort "$WORK/sc.log")"
}

new_repo
big "$REPO/big.sh" 2000
printf '%s\necho small\n' "$SHEBANG" >"$REPO/small.sh"
commit
expect "a pushed script over 2,000 lines gets one full-analysis run; a small one is not re-run" \
  "0||-x -f gcc -S warning -- big.sh" "$(stub "$REPO")"

new_repo
big "$REPO/big.sh" 2000
commit
BASE="$(git -C "$REPO" rev-parse HEAD)"
printf 'echo more\n' >>"$REPO/seed.sh"
commit
expect "a script over 2,000 lines the push does not change is not checked" "0||" "$(stub "$REPO")"
line2 "$REPO/big.sh" 'echo changed'
commit
line2 "$REPO/big.sh" 'echo "stub: finding"'
expect "a work tree finding the pushed tip lacks does not block: the tip is linted" "0||-x -f gcc -S warning -- big.sh" "$(stub "$REPO")"
git -C "$REPO" commit -q -am finding --no-verify
line2 "$REPO/big.sh" 'echo fixed'
expect "a pushed finding the work tree has fixed still blocks: the tip is linted" "1|big.sh:2: warning: stub finding [SC2154]
$HINT|-x -f gcc -S warning -- big.sh" "$(stub "$REPO")"

new_repo
big "$REPO/big.sh" 2000
line2 "$REPO/big.sh" 'echo "stub: finding"'
commit
BASE="$(git -C "$REPO" rev-parse HEAD)"
printf 'echo last\n' >>"$REPO/big.sh"
commit
expect "a finding on a line the push does not add does not block" "0||-x -f gcc -S warning -- big.sh" "$(stub "$REPO")"

new_repo
mkdir -p "$REPO/x" "$REPO/y"
big "$REPO/x/big.sh" 2000
line2 "$REPO/x/big.sh" 'echo "stub: finding"'
cp "$REPO/x/big.sh" "$REPO/y/big.sh"
commit
expect "identical pushed copies in two directories are linted once, and the finding blocks under each path" \
  "1|x/big.sh:2: warning: stub finding [SC2154]
y/big.sh:2: warning: stub finding [SC2154]
$HINT|--norc --extended-analysis=false -s bash -f gcc -S info -
-x -f gcc -S warning -- x/big.sh" "$(stub "$REPO")"
expect "with a ShellCheck older than 0.10 the pre-commit entry ran full analysis, so nothing runs again" \
  "0||" "$(SC_STUB_VERSION=0.9.0 stub "$REPO")"

expect "--resolve names the adapter" "bash-format	lint	adapter:shellcheck	shellcheck	yes	config .shellcheckrc; binary shellcheck on PATH" \
  "$(cd "$REPO" && PATH="$WORK/sc-stub:$PATH" bash "$CHECK" --resolve </dev/null 2>&1 | cut -f1-6)"

if ! command -v shellcheck >/dev/null 2>&1 ||
  ! [[ "$(shellcheck --version)" =~ version:\ ([0-9]+)\.([0-9]+) ]] ||
  ((BASH_REMATCH[1] == 0 && BASH_REMATCH[2] < 10)); then
  echo "SKIP: ShellCheck 0.10 or later not on PATH -- dataflow cases skipped"
else
  new_repo
  big "$REPO/big.sh" 2000 'f() {
  echo "x"
  return $?
}
f'
  git -C "$REPO" add big.sh
  out="$(cd "$REPO" && bash "$HERE/lint.sh" 2>&1)"
  expect "control: the pre-commit lint entry passes the script over 2,000 lines without dataflow analysis" "0|" "$?|$out"
  git -C "$REPO" commit -q -m big --no-verify
  expect "a dataflow-only finding (SC2320, \$? after echo) in a pushed script over 2,000 lines blocks the push" \
    "1|big.sh:2004: warning: This \$? refers to echo/printf, not a previous command. Assign to variable to avoid it being overwritten. [SC2320]
$HINT" "$(push "$REPO")"

  new_repo
  printf '%s\nv=1\n' "$SHEBANG" >"$REPO/vars.sh"
  big "$REPO/big.sh" 2000 '# shellcheck source=vars.sh
. ./vars.sh
echo "$v"'
  commit
  printf 'echo unpushed\n' >>"$REPO/big.sh"
  rm "$REPO/vars.sh"
  expect "a work tree that differs from the pushed tip: the tip is linted in a checkout of it, its sourced file found" \
    "0|" "$(push "$REPO")"
fi

echo "lint-full: $PASS passed, $FAIL failed"
((FAIL == 0))
