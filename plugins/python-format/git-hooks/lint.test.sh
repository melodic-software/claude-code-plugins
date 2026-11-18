#!/usr/bin/env bash
# Expected values are Ruff's documented output: F821 is "Undefined name".
# test-scope: plugins/python-format/git-hooks/entries.json plugins/python-format/git-hooks/adapters.sh
# test-scope: plugins/python-format/lib/git-hooks/check-lib.sh plugins/python-format/lib/git-hooks/resolve-tool.sh
# shellcheck disable=SC2016 # record commands are literal text
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/lint.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1 HOME="$WORK/home"
mkdir -p "$HOME"

PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

n=0
new_repo() { # [ruff.toml body; "NONE" for no config]
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  if [[ "${1:-}" != NONE ]]; then
    printf '%s\n' "${1:-line-length = 88}" >"$REPO/ruff.toml"
  fi
  printf 'seed = 1\n' >"$REPO/seed.py"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m seed --no-verify
}
record() { # <body>: commit .claude/ecosystems/python.yaml
  mkdir -p "$REPO/.claude/ecosystems"
  printf '%s\n' "$1" >"$REPO/.claude/ecosystems/python.yaml"
  git -C "$REPO" add .claude/ecosystems/python.yaml
  git -C "$REPO" commit -q -m record --no-verify
}

BIN="$WORK/bin"
mkdir -p "$BIN"
cat >"$BIN/stublint" <<'EOF'
#!/bin/sh
if [ "$1" = --crash ]; then
  echo 'stublint: config error' >&2
  exit 2
fi
for a in "$@"; do printf '%s/%s:2:5: X1 bad thing\n' "$PWD" "$a"; done
exit 1
EOF
chmod +x "$BIN/stublint"

check() { # <repo> [args...] -> "<rc>|<stdout>|<stderr>"
  local repo="$1" out rc
  shift
  out="$(cd "$repo" && PATH="$BIN:$PATH" bash "$CHECK" "$@" 2>"$WORK/stderr")"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$WORK/stderr")"
}

HINT='python-format: fix the findings ruff reported above.'

if ! command -v ruff >/dev/null 2>&1; then
  echo "SKIP: ruff not on PATH -- the ruff adapter tests skipped"
else
  new_repo
  printf 'seed = 1\n\nprint(undefined_name)\n' >"$REPO/seed.py"
  git -C "$REPO" add seed.py
  expect "a finding on an added line blocks, naming that line" "1||seed.py:3: F821 Undefined name \`undefined_name\`
$HINT" "$(check "$REPO")"

  new_repo
  printf 'import os\nx=1\n' >"$REPO/a.py"
  git -C "$REPO" add a.py
  check "$REPO" >/dev/null
  expect "lint rewrites nothing: no fix, no format" "$(printf 'import os\nx=1')" "$(cat "$REPO/a.py")"
  expect "lint stages nothing new" "$(printf 'import os\nx=1')" "$(git -C "$REPO" show :a.py)"

  new_repo
  printf 'x=1\n' >"$REPO/a.py"
  git -C "$REPO" add a.py
  printf 'x=1\ny=2\n' >"$REPO/a.py"
  expect "a partly staged file is refused: lint reads the work tree" "1||a.py: partly staged; lint checks the work tree, so stage it fully, then commit" "$(check "$REPO")"

  new_repo
  printf 'x=1\n' >"$REPO/a.py"
  git -C "$REPO" add a.py
  printf 'line-length = 100\n' >"$REPO/ruff.toml"
  expect "a Ruff config edited after staging refuses the commit" "1||ruff.toml: config differs between the index and the work tree; stage it or restore it, then commit" "$(check "$REPO")"

  new_repo 'extend-exclude = ["gen"]'
  printf 'x=1\nprint(undefined_name)\n' >"$REPO/gone.py"
  git -C "$REPO" add gone.py
  rm "$REPO/gone.py"
  expect "staged then deleted from the work tree: the staged finding still blocks" "1||gone.py:2: F821 Undefined name \`undefined_name\`
$HINT" "$(check "$REPO")"
  expect "staged then deleted: the file is not recreated" "no" "$([[ -e "$REPO/gone.py" ]] && echo yes || echo no)"
  git -C "$REPO" rm -q --cached gone.py
  mkdir -p "$REPO/gen"
  printf 'print(undefined_name)\n' >"$REPO/gen/g.py"
  git -C "$REPO" add gen/g.py
  rm -r "$REPO/gen"
  expect "staged then deleted: the config's excludes still hold" "0||" "$(check "$REPO")"
  git -C "$REPO" rm -q --cached gen/g.py
  ln -s missing.py "$REPO/link.py"
  git -C "$REPO" add link.py
  rm "$REPO/link.py"
  expect "staged then deleted: a staged symlink is not checked" "0||" "$(check "$REPO")"

  new_repo
  printf 'print(undefined_name)\n' >"$REPO/seed.py"
  git -C "$REPO" add seed.py
  git -C "$REPO" commit -q -m old --no-verify
  printf 'print(undefined_name)\n\nok = 2\n' >"$REPO/seed.py"
  git -C "$REPO" add seed.py
  expect "a finding on a line the commit did not add does not block" "0||" "$(check "$REPO")"

  new_repo
  printf 'x=1\nprint(undefined_name)\n' >"$REPO/a.py"
  expect "--worktree: an uncommitted finding blocks and nothing is rewritten" "1||a.py:2: F821 Undefined name \`undefined_name\`
$HINT" "$(check "$REPO" --worktree)"
  expect "--worktree: the file keeps its bytes" "$(printf 'x=1\nprint(undefined_name)')" "$(cat "$REPO/a.py")"
  printf 'print(undefined_name)\n' >"$REPO/a.py"
  expect "--worktree: an untracked file is checked whole" "1||a.py:1: F821 Undefined name \`undefined_name\`
$HINT" "$(check "$REPO" --worktree)"
  rm "$REPO/a.py"
  expect "--worktree: no uncommitted change passes" "0||" "$(check "$REPO" --worktree)"

  new_repo NONE
  printf 'print(undefined_name)\n' >"$REPO/a.py"
  git -C "$REPO" add a.py
  expect "no Ruff config and no record: nothing runs and the entry passes" "0||" "$(check "$REPO")"

fi

new_repo
record 'globs: ["*.py"]
lint-cmd: "stublint <files>"'
printf 'a = 1\nb = 2\n' >"$REPO/a.py"
git -C "$REPO" add a.py
if command -v ruff >/dev/null 2>&1; then
  expect "with a record and a Ruff config, Ruff lints and the record's linter never runs" "0||" "$(check "$REPO")"
fi
CRASH="$WORK/crash"
mkdir -p "$CRASH"
printf '#!/bin/sh\necho "ruff: config error" >&2\nexit 2\n' >"$CRASH/ruff"
chmod +x "$CRASH/ruff"
out="$(cd "$REPO" && PATH="$CRASH:$PATH" bash "$CHECK" 2>&1)"
expect "the adapter's linter exiting non-zero with no parseable finding fails closed, showing its output" "1|python-format: ruff exited 2 and reported no <path>:<line> finding, so the change was not checked:
ruff: config error" "$?|$out"

new_repo NONE
record 'globs: ["*.py"]
lint-cmd: "stublint <files>"'
printf 'a = 1\nb = 2\n' >"$REPO/a.py"
git -C "$REPO" add a.py
expect "a record with no Ruff config runs nothing at commit" "0||" "$(check "$REPO")"

echo "lint: $PASS passed, $FAIL failed"
((FAIL == 0))
