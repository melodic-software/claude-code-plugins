#!/usr/bin/env bash
# Contract tests for the ruff-format pre-commit entry (git-hooks/ruff-check.sh):
# staged Python files are rewritten and re-staged, a partly staged one is refused
# untouched, a finding blocks only on a line the commit adds, only a file a Ruff
# config governs is touched, --worktree reports without rewriting, a missing ruff
# follows the skip-key rule, and the plugin's own vendored installer wires the
# entry so `git commit` runs it.
# Expected values are Ruff's documented output: `x=1` formats to `x = 1`, F821 is
# "Undefined name", a safe F401 fix deletes the unused import.
# test-scope: plugins/ruff-format/git-hooks/entries.json plugins/ruff-format/lib/git-hooks/check-lib.sh plugins/ruff-format/lib/git-hooks/install.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/ruff-check.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
if ! command -v ruff >/dev/null 2>&1; then
  echo "SKIP: ruff not on PATH -- ruff-check tests skipped"
  exit 0
fi
REAL_RUFF="$(command -v ruff)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

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

check() { # <repo> [args...] -> "<rc>|<stdout>|<stderr>"
  local repo="$1" out rc
  shift
  out="$(cd "$repo" && bash "$CHECK" "$@" 2>"$WORK/stderr")"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$WORK/stderr")"
}

HINT='ruff-format: fix the findings above, or adjust the repository Ruff config.'

new_repo
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
expect "a staged unformatted file is rewritten, listed on stdout, and exits 0" "0|a.py|" "$(check "$REPO")"
expect "the rewrite is in the work tree" "x = 1" "$(cat "$REPO/a.py")"
expect "the rewrite is re-staged: the index holds the formatted bytes" "x = 1" "$(git -C "$REPO" show :a.py)"
expect "re-staged: no unstaged change remains" "" "$(git -C "$REPO" diff --name-only)"

new_repo
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
printf 'x=1\ny=2\n' >"$REPO/a.py"
expect "a partly staged file is refused with the contract line" "1||a.py: partly staged; format it or stage it fully, then commit" "$(check "$REPO")"
expect "a refused file is left byte for byte" "$(printf 'x=1\ny=2')" "$(cat "$REPO/a.py")"
expect "a refused file's index entry is left byte for byte" "x=1" "$(git -C "$REPO" show :a.py)"

new_repo
printf 'x=1\n' >"$REPO/a.py"
printf 'notes\n' >"$REPO/notes.md"
git -C "$REPO" add a.py notes.md
printf 'notes\nmore unstaged\n' >"$REPO/notes.md"
expect "a partly staged file that is not Python does not refuse the commit" "0|a.py|" "$(check "$REPO")"

new_repo
printf 'seed = 1\n\nprint(undefined_name)\n' >"$REPO/seed.py"
git -C "$REPO" add seed.py
expect "a finding on an added line blocks, naming that line" "1||seed.py:3: F821 Undefined name \`undefined_name\`
$HINT" "$(check "$REPO")"

new_repo
printf 'print(undefined_name)\n' >"$REPO/seed.py"
git -C "$REPO" add seed.py
git -C "$REPO" commit -q -m old --no-verify
printf 'print(undefined_name)\n\nok = 2\n' >"$REPO/seed.py"
git -C "$REPO" add seed.py
expect "a finding on a line the commit did not add does not block" "0||" "$(check "$REPO")"

new_repo
printf 'import os\nprint(1)\n' >"$REPO/a.py"
git -C "$REPO" add a.py
expect "a safe fix is applied at commit: the unused import goes" "0|a.py|" "$(check "$REPO")"
expect "the safe fix is staged" "print(1)" "$(git -C "$REPO" show :a.py)"

new_repo $'unsafe-fixes = true\nlint.select = ["E712"]'
printf 'x = 1\nif x == True:\n    pass\n' >"$REPO/a.py"
git -C "$REPO" add a.py
check "$REPO" >/dev/null
expect "an unsafe fix is not applied even when the config enables unsafe-fixes" "if x == True:" "$(sed -n 2p "$REPO/a.py")"

new_repo NONE
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
expect "no Ruff config: the file is not touched and the check passes" "0||" "$(check "$REPO")"
expect "no Ruff config: bytes are as written" "x=1" "$(cat "$REPO/a.py")"

new_repo NONE
printf '[project]\nname = "t"\n' >"$REPO/pyproject.toml"
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
expect "pyproject.toml without [tool.ruff] does not opt in" "0||" "$(check "$REPO")"
printf '[tool.ruff]\nline-length = 88\n' >"$REPO/pyproject.toml"
mkdir -p "$REPO/pkg/sub"
printf 'y=2\n' >"$REPO/pkg/sub/b.py"
git -C "$REPO" add pkg/sub/b.py
expect "pyproject.toml with [tool.ruff] above a nested file opts it in" "0|a.py
pkg/sub/b.py|" "$(check "$REPO")"

new_repo 'extend-exclude = ["gen"]'
mkdir -p "$REPO/gen"
printf 'x=1\n' >"$REPO/gen/g.py"
git -C "$REPO" add gen/g.py
expect "a file the config excludes is left alone" "0||" "$(check "$REPO")"
expect "an excluded file keeps its bytes" "x=1" "$(cat "$REPO/gen/g.py")"

new_repo
mkdir -p "$REPO/.githooks/ruff-format"
printf 'x=1\n' >"$REPO/.githooks/ruff-format/copy.py"
git -C "$REPO" add -f .githooks/ruff-format/copy.py
expect "an installed copy under .githooks/ is skipped" "0||" "$(check "$REPO")"

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

# A PATH with the tools the script runs, git and no ruff.
NORUFF="$WORK/noruff"
mkdir -p "$NORUFF"
for t in git bash sed awk cat mktemp rm dirname grep tr; do
  ln -s "$(command -v "$t")" "$NORUFF/$t"
done
new_repo
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NORUFF" bash "$CHECK" 2>&1)"
expect "missing ruff: an agent fails with the install command" "1" "$?"
expect "missing ruff: the message names the tool and the skip key" \
  "FAIL: ruff missing. Install: pip install ruff, or another method at https://docs.astral.sh/ruff/installation/
To skip only while ruff is missing: git -c checks.skipmissing=ruff commit ..." "$out"
out="$(cd "$REPO" && PATH="$NORUFF" bash "$CHECK" 2>&1)"
expect "missing ruff: a person gets a notice and exit 0" "0|NOTICE: ruff missing, so this check did not run. Install: pip install ruff, or another method at https://docs.astral.sh/ruff/installation/" "$?|$out"
git -C "$REPO" config checks.skipmissing ruff
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NORUFF" bash "$CHECK" 2>&1)"
expect "missing ruff named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: ruff (missing)" "$?|$out"
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NORUFF" bash "$CHECK" --worktree 2>&1)"
git -C "$REPO" config --unset checks.skipmissing
expect "missing ruff, --worktree: silent" "0|" "$?|$out"

# ruff only in the repo's own .venv.
new_repo
mkdir -p "$REPO/.venv/bin"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_RUFF" >"$REPO/.venv/bin/ruff"
chmod +x "$REPO/.venv/bin/ruff"
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NORUFF" bash "$CHECK" 2>&1)"
expect "ruff found in the repo's .venv when PATH has none" "0|a.py" "$?|$out"

# End to end through the plugin's vendored installer and real commits.
new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"ruff-check","status":"installed"}]' "$status"
expect "the installed copy carries the stamp on line 2" yes \
  "$(sed -n 2p "$REPO/.git/hooks/ruff-format/ruff-check.sh" | grep -qE '^# ruff-format ruff-check sha256:[0-9a-f]{64}$' && echo yes)"
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
git -C "$REPO" commit -q -m format >/dev/null 2>&1
expect "git commit runs the entry and succeeds" "0" "$?"
expect "the commit holds the formatted bytes" "x = 1" "$(git -C "$REPO" show HEAD:a.py)"
expect "the work tree matches the commit" "" "$(git -C "$REPO" status --porcelain)"
printf 'x = 1\nprint(undefined_name)\n' >"$REPO/a.py"
git -C "$REPO" add a.py
err="$(git -C "$REPO" commit -q -m finding 2>&1)"
expect "git commit fails on a finding on an added line" "1" "$?"
expect "the commit failure names the line" "a.py:2: F821 Undefined name \`undefined_name\`" "$(printf '%s\n' "$err" | head -1)"
expect "verify reports ok after the install" "ok	ruff-check" "$(node "$INSTALL" verify --repo "$REPO")"

echo "ruff-check: $PASS passed, $FAIL failed"
((FAIL == 0))
