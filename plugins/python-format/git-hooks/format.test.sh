#!/usr/bin/env bash
# Expected values are Ruff's documented behavior: `x=1` formats to `x = 1`, and
# the I001 fix sorts `import sys` after `import os`.
# test-scope: plugins/python-format/git-hooks/entries.json plugins/python-format/git-hooks/adapters.sh
# test-scope: plugins/python-format/lib/git-hooks/check-lib.sh plugins/python-format/lib/git-hooks/install.mjs
# test-scope: plugins/python-format/lib/git-hooks/resolve-tool.sh
# shellcheck disable=SC2016 # record commands are literal text
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/format.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"

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

check() { # <repo> [args...] -> "<rc>|<stdout>|<stderr>"
  local repo="$1" out rc
  shift
  out="$(cd "$repo" && PATH="$BIN:$PATH" bash "$CHECK" "$@" 2>"$WORK/stderr")"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$WORK/stderr")"
}

BIN="$WORK/bin"
mkdir -p "$BIN"
cat >"$BIN/stubfmt" <<EOF
#!/bin/sh
for a in "\$@"; do
  printf '%s\n' "\$a" >>"$WORK/stub.log"
  printf 'formatted\n' >"\$a"
done
EOF
chmod +x "$BIN/stubfmt"
STUBRUFF="$WORK/stubruff"
mkdir -p "$STUBRUFF"
cat >"$STUBRUFF/ruff" <<EOF
#!/bin/sh
sub="\$1"
while [ \$# -gt 0 ] && [ "\$1" != -- ]; do shift; done
shift
for a in "\$@"; do printf '%s %s\n' "\$sub" "\$a" >>"$WORK/ruff.log"; done
EOF
chmod +x "$STUBRUFF/ruff"

new_repo
printf 'x=1\n' >"$REPO/a.py"
printf 'x=1\n' >"$REPO/b c.py"
printf 'x=1\n' >"$REPO/-d.py"
git -C "$REPO" add -- a.py "b c.py" -d.py
out="$(cd "$REPO" && PATH="$STUBRUFF:$PATH" bash "$CHECK" 2>&1)"
expect "staged paths with a space and a leading dash reach ruff as arguments" "0|" "$?|$out"
expect "import sorting then formatting run, each over exactly the staged paths" "check ./-d.py
check a.py
check b c.py
format ./-d.py
format a.py
format b c.py" "$(cat "$WORK/ruff.log")"

if ! command -v ruff >/dev/null 2>&1; then
  echo "SKIP: ruff not on PATH -- the remaining format tests skipped"
  echo "format: $PASS passed, $FAIL failed"
  exit $((FAIL != 0))
fi
REAL_RUFF="$(command -v ruff)"

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

DRIFT='config differs between the index and the work tree; stage it or restore it, then commit'
new_repo NONE
printf 'line-length = 88\n' >"$REPO/.ruff.toml"
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add .ruff.toml a.py
rm "$REPO/.ruff.toml"
expect "a Ruff config staged then deleted refuses the commit, naming it" "1||.ruff.toml: $DRIFT" "$(check "$REPO")"
expect "the refused file is left as it was" "x=1" "$(cat "$REPO/a.py")"

new_repo
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
printf 'line-length = 100\n' >"$REPO/ruff.toml"
expect "a Ruff config edited after staging refuses the commit" "1||ruff.toml: $DRIFT" "$(check "$REPO")"
expect "the refused file is left as it was" "x=1" "$(cat "$REPO/a.py")"

new_repo NONE
mkdir -p "$REPO/pkg"
printf '[tool.ruff]\n' >"$REPO/pkg/pyproject.toml"
printf 'x=1\n' >"$REPO/pkg/a.py"
git -C "$REPO" add pkg/pyproject.toml pkg/a.py
printf '[tool.ruff]\nline-length = 70\n' >"$REPO/pkg/pyproject.toml"
expect "a drifted pyproject.toml holding [tool.ruff] refuses" "1||pkg/pyproject.toml: $DRIFT" "$(check "$REPO")"

new_repo
printf '[project]\nname = "t"\n' >"$REPO/pyproject.toml"
git -C "$REPO" add pyproject.toml
printf '[project]\nname = "u"\n' >"$REPO/pyproject.toml"
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
expect "a drifted pyproject.toml with no [tool.ruff] on either side does not refuse" "0|a.py|" "$(check "$REPO")"

new_repo
mkdir -p "$REPO/other"
printf 'line-length = 88\n' >"$REPO/other/ruff.toml"
git -C "$REPO" add other/ruff.toml
printf 'line-length = 99\n' >"$REPO/other/ruff.toml"
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
expect "a drifted config above no staged file does not refuse the commit" "0|a.py|" "$(check "$REPO")"

new_repo 'lint.select = ["I", "F"]'
printf 'import sys\nimport os\n\nimport json\nprint(os, sys)\nif x == True:\n    pass\n' >"$REPO/a.py"
git -C "$REPO" add a.py
check "$REPO" >/dev/null
expect "selected import rules sort the imports; an unused import and other fixable findings stay" "import json
import os
import sys

print(os, sys)
if x == True:
    pass" "$(cat "$REPO/a.py")"
new_repo 'lint.select = ["F"]'
printf 'import sys\nimport os\n\nprint(os, sys)\n' >"$REPO/a.py"
git -C "$REPO" add a.py
expect "a config that does not select the import rules leaves import order alone" "0||" "$(check "$REPO")"
expect "imports keep their order" "import sys" "$(head -1 "$REPO/a.py")"

new_repo NONE
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
expect "no Ruff config and no record: the file is not touched and the entry passes" "0||" "$(check "$REPO")"
expect "no Ruff config: bytes are as written" "x=1" "$(cat "$REPO/a.py")"

new_repo NONE
printf '[project]\nname = "t"\n' >"$REPO/pyproject.toml"
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
expect "pyproject.toml without [tool.ruff] does not opt in" "0||" "$(check "$REPO")"
printf '[tool.ruff]\nline-length = 88\n' >"$REPO/pyproject.toml"
mkdir -p "$REPO/pkg/sub"
printf 'y=2\n' >"$REPO/pkg/sub/b.py"
git -C "$REPO" add pyproject.toml pkg/sub/b.py
expect "pyproject.toml with [tool.ruff] above a nested file opts it in" "0|a.py
pkg/sub/b.py|" "$(check "$REPO")"

new_repo 'extend-exclude = ["gen"]'
mkdir -p "$REPO/gen"
printf 'x=1\n' >"$REPO/gen/g.py"
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add gen/g.py a.py
expect "a file the config excludes is left alone" "0|a.py|" "$(check "$REPO")"
expect "an excluded file keeps its bytes" "x=1" "$(cat "$REPO/gen/g.py")"

new_repo
mkdir -p "$REPO/.githooks/python-format"
printf 'x=1\n' >"$REPO/.githooks/python-format/copy.py"
git -C "$REPO" add -f .githooks/python-format/copy.py
expect "an installed copy under .githooks/ is skipped" "0||" "$(check "$REPO")"
mkdir -p "$REPO/sub/.githooks"
printf 'x=1\n' >"$REPO/sub/.githooks/hook.py"
git -C "$REPO" add -f sub/.githooks/hook.py
expect "a file under a nested .githooks/ is formatted" "0|sub/.githooks/hook.py|" "$(check "$REPO")"

new_repo
printf 'x=1\n' >"$REPO/a.py"
expect "--worktree: the format entry rewrites nothing and passes" "0||" "$(check "$REPO" --worktree)"
expect "--worktree: the file keeps its bytes" "x=1" "$(cat "$REPO/a.py")"

NORUFF="$WORK/noruff"
mkdir -p "$NORUFF"
for t in git bash sed awk cat mktemp rm dirname grep tr sh head; do
  ln -s "$(command -v "$t")" "$NORUFF/$t"
done
new_repo
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NORUFF" bash "$CHECK" 2>&1)"
expect "missing ruff: an agent fails with the install command and the skip key" \
  "1|FAIL: ruff missing. Install: pip install ruff, or another method at https://docs.astral.sh/ruff/installation/
To skip only while ruff is missing: git -c checks.skipmissing=ruff commit ..." "$?|$out"
out="$(cd "$REPO" && PATH="$NORUFF" bash "$CHECK" 2>&1)"
expect "missing ruff: a person gets a notice and exit 0" "0|NOTICE: ruff missing, so this check did not run. Install: pip install ruff, or another method at https://docs.astral.sh/ruff/installation/" "$?|$out"
git -C "$REPO" config checks.skipmissing ruff
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NORUFF" bash "$CHECK" 2>&1)"
expect "missing ruff named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: ruff (missing)" "$?|$out"

new_repo
mkdir -p "$REPO/.venv/bin"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_RUFF" >"$REPO/.venv/bin/ruff"
chmod +x "$REPO/.venv/bin/ruff"
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NORUFF" bash "$CHECK" 2>&1)"
expect "ruff found in the repo's .venv when PATH has none" "0|a.py" "$?|$out"

new_repo
record 'globs: ["*.py"]
fix-cmd: "stubfmt <files>"'
printf 'x=1\n' >"$REPO/a.py"
name='$(touch marker);b.py'
printf 'x=1\n' >"$REPO/$name"
git -C "$REPO" add -- a.py "$name"
: >"$WORK/stub.log"
expect "with a record and a Ruff config, Ruff formats and the record command never runs" "0|$name
a.py|" "$(check "$REPO")"
expect "the record command was not called" "" "$(cat "$WORK/stub.log")"
expect "the index holds Ruff's bytes" "x = 1" "$(git -C "$REPO" show :a.py)"
expect "a crafted file name reached Ruff as data and ran nothing" "no" "$([[ -e "$REPO/marker" ]] && echo yes || echo no)"

new_repo NONE
record 'globs: ["*.py"]
fix-cmd: "stubfmt <files>"'
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
expect "a record with no Ruff config runs nothing at commit" "0||" "$(check "$REPO")"
expect "the file stays as written" "x=1" "$(cat "$REPO/a.py")"
expect "--resolve says the record is not run by hooks and names what runs it" "python-format	format	none		n/a	no Ruff config; the python record is not run by hooks; /toolchain:lint and /toolchain:check run it" "$(cd "$REPO" && bash "$CHECK" --resolve)"

new_repo NONE
mkdir -p "$REPO/src/pkg" "$REPO/scripts" "$REPO/.venv/bin"
printf '[project]\nname = "demo"\n\n[tool.ruff.lint]\nselect = ["E"]\n' >"$REPO/pyproject.toml"
printf 'line-length = 100\n' >"$REPO/src/ruff.toml"
printf '[project]\nname = "pkg"\n' >"$REPO/src/pkg/pyproject.toml"
printf 'x = 1\n' >"$REPO/src/pkg/mod.py"
printf 'print(1)\n' >"$REPO/scripts/run.py"
printf '#!/bin/sh\nexit 0\n' >"$REPO/.venv/bin/ruff"
chmod +x "$REPO/.venv/bin/ruff"
expect "--resolve <path> names the closest governing config and the venv binary, per file" "python-format	format	adapter:ruff	ruff	yes	config src/ruff.toml; binary .venv/bin/ruff
python-format	format	adapter:ruff	ruff	yes	config pyproject.toml; binary .venv/bin/ruff" "$(cd "$REPO" && bash "$CHECK" --resolve src/pkg/mod.py scripts/run.py)"
new_repo NONE
printf '[project]\nname = "t"\n' >"$REPO/pyproject.toml"
expect "--resolve with nothing resolved says why the adapter did not opt in" "python-format	format	none		n/a	no Ruff config: pyproject.toml has no [tool.ruff] section" "$(cd "$REPO" && bash "$CHECK" --resolve)"

new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs both entries" '[{"entry":"format","status":"installed"},{"entry":"lint","status":"installed"}]' "$status"
expect "the installed format copy carries the stamp on line 2" yes \
  "$(grep -qE '^# python-format format sha256:[0-9a-f]{64}$' < <(sed -n 2p "$REPO/.git/hooks/python-format/format.sh") && echo yes)"
printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
git -C "$REPO" commit -q -m format >/dev/null 2>&1
expect "git commit runs the entries and succeeds" "0" "$?"
expect "the commit holds the formatted bytes" "x = 1" "$(git -C "$REPO" show HEAD:a.py)"
expect "the work tree matches the commit" "" "$(git -C "$REPO" status --porcelain)"
printf 'x = 1\nprint(undefined_name)\n' >"$REPO/a.py"
git -C "$REPO" add a.py
err="$(git -C "$REPO" commit -q -m finding 2>&1)"
expect "git commit fails on a finding on an added line" "1" "$?"
expect "the commit failure names the line" "a.py:2: F821 Undefined name \`undefined_name\`" "$(printf '%s\n' "$err" | head -1)"
expect "verify reports both entries ok after the install" "ok	format
ok	lint" "$(node "$INSTALL" verify --repo "$REPO")"

echo "format: $PASS passed, $FAIL failed"
((FAIL == 0))
