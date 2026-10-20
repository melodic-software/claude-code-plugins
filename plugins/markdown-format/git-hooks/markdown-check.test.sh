#!/usr/bin/env bash
# Contract tests for the markdown-format pre-commit entry (git-hooks/markdown-check.sh):
# staged Markdown files are rewritten and re-staged, a partly staged one is refused
# untouched, a finding blocks only on a line the commit adds, only a file a
# markdownlint config governs is touched, a config that can run repository code is
# skipped until the user approves its content state, --worktree reports without rewriting, a missing markdownlint-cli2
# follows the skip-key rule, and the plugin's own vendored installer wires the
# entry so `git commit` runs it.
# Expected values are markdownlint's documented rules: a file must end with a single
# newline (MD047) and an extra blank line goes (MD012), both fixable; inline HTML
# is MD033/no-inline-html and has no fix.
# test-scope: plugins/markdown-format/git-hooks/entries.json plugins/markdown-format/git-hooks/markdown-gates.sh plugins/markdown-format/lib/git-hooks/check-lib.sh plugins/markdown-format/lib/git-hooks/install.mjs plugins/markdown-format/.claude-plugin/plugin.json
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT CLAUDE_PLUGIN_DATA

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/markdown-check.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
# The real binary: PATH, else the repository's own locked install.
REAL_MD="$(command -v markdownlint-cli2 || true)"
[[ -n "$REAL_MD" ]] || REAL_MD="$(cd "$PLUGIN/../.." && pwd)/node_modules/.bin/markdownlint-cli2"
if [[ ! -x "$REAL_MD" ]] || ! command -v node >/dev/null 2>&1; then
  echo "SKIP: markdownlint-cli2 or node not found -- markdown-check tests skipped"
  exit 0
fi
PATH="${REAL_MD%/*}:$PATH"
export PATH

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
new_repo() { # [config file name and body as "name=body"; "NONE" for no config]
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  if [[ "${1:-}" != NONE ]]; then
    printf '{ "config": { "default": true, "MD013": false } }\n' >"$REPO/.markdownlint-cli2.jsonc"
  fi
  printf '# Seed\n' >"$REPO/seed.md"
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

# Expected bytes carry a trailing "x" so command substitution cannot strip the
# final newline MD047 adds.
FIXED=$'# T\n\ntext\n'
HINT='markdown-format: fix the findings above, or adjust the repository markdownlint config.'
HTML='a.md:3: MD033/no-inline-html Inline HTML [Element: b]'

new_repo
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a staged file with no final newline is rewritten, listed on stdout, and exits 0" "0|a.md|" "$(check "$REPO")"
expect "the rewrite is in the work tree" "${FIXED}x" "$(
  cat "$REPO/a.md"
  printf x
)"
expect "the rewrite is re-staged: the index holds the fixed bytes" "${FIXED}x" "$(
  git -C "$REPO" show :a.md
  printf x
)"
expect "re-staged: no unstaged change remains" "" "$(git -C "$REPO" diff --name-only)"

new_repo
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
printf '# T\n\ntext\n\nmore unstaged\n' >"$REPO/a.md"
expect "a partly staged file is refused with the contract line" "1||a.md: partly staged; format it or stage it fully, then commit" "$(check "$REPO")"
expect "a refused file is left byte for byte" "$(printf '# T\n\ntext\n\nmore unstaged')" "$(cat "$REPO/a.md")"
expect "a refused file's index entry is left byte for byte" "# T" "$(git -C "$REPO" show :a.md | sed -n 1p)"

# markdownlint-cli2 reads its config from the work tree; the commit holds the index's.
DRIFT='config differs between the index and the work tree; stage it or restore it, then commit'
new_repo
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
rm "$REPO/.markdownlint-cli2.jsonc"
expect "a markdownlint config deleted from the work tree refuses the commit, naming it" "1||.markdownlint-cli2.jsonc: $DRIFT" "$(check "$REPO")"
expect "the refused file is left as it was" "$(printf '# T\n\ntext')" "$(cat "$REPO/a.md")"

new_repo NONE
mkdir -p "$REPO/docs"
printf '{ "default": true }\n' >"$REPO/docs/.markdownlint.json"
printf '# T\n\ntext' >"$REPO/docs/a.md"
printf '# U\n\ntext' >"$REPO/b.md"
git -C "$REPO" add docs b.md
printf '{ "default": false }\n' >"$REPO/docs/.markdownlint.json"
expect "a nested markdownlint config edited after staging refuses the commit" "1||docs/.markdownlint.json: $DRIFT" "$(check "$REPO")"
git -C "$REPO" reset -q docs/a.md
expect "a drifted config above no staged file does not refuse the commit" "0||" "$(check "$REPO")"

new_repo
printf '# T\n\ntext' >"$REPO/a.md"
printf 'notes\n' >"$REPO/notes.txt"
git -C "$REPO" add a.md notes.txt
printf 'notes\nmore unstaged\n' >"$REPO/notes.txt"
expect "a partly staged file that is not Markdown does not refuse the commit" "0|a.md|" "$(check "$REPO")"

new_repo
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a finding on an added line blocks, naming that line" "1||$HTML
$HINT" "$(check "$REPO")"

new_repo
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
git -C "$REPO" commit -q -m old --no-verify
printf '# T\n\n<b>x</b>\n\nmore\n' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a finding on a line the commit did not add does not block" "0||" "$(check "$REPO")"

new_repo
printf '# T\n\ntext\n\n\n\nend\n' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "extra blank lines are removed at commit" "0|a.md|" "$(check "$REPO")"
expect "the index holds one blank line between the paragraphs" "$(printf '# T\n\ntext\n\nend')" "$(git -C "$REPO" show :a.md)"

new_repo
printf '# T\n\ntext' >"$REPO/a.mdc"
git -C "$REPO" add a.mdc
expect "a .mdc file is rewritten like a .md file" "0|a.mdc|" "$(check "$REPO")"

new_repo NONE
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "no markdownlint config: the file is not touched and the check passes" "0||" "$(check "$REPO")"
expect "no markdownlint config: bytes are as written" "$(printf '# T\n\ntext')" "$(cat "$REPO/a.md")"

new_repo NONE
mkdir -p "$REPO/docs/deep"
printf '{ "default": true }\n' >"$REPO/docs/.markdownlint.json"
printf '# T\n\ntext' >"$REPO/docs/deep/b.md"
printf '# T\n\ntext' >"$REPO/c.md"
git -C "$REPO" add docs/deep/b.md c.md
expect "a nested config opts in only its subtree" "0|docs/deep/b.md|" "$(check "$REPO")"
expect "a file outside the nested config keeps its bytes" "$(printf '# T\n\ntext')" "$(cat "$REPO/c.md")"

new_repo
printf '{ "ignores": ["gen/**"] }\n' >"$REPO/.markdownlint-cli2.jsonc"
mkdir -p "$REPO/gen"
printf '# T\n\ntext' >"$REPO/gen/g.md"
git -C "$REPO" add .markdownlint-cli2.jsonc gen/g.md
expect "a file the markdownlint config ignores is left alone" "0||" "$(check "$REPO")"
expect "an ignored file keeps its bytes" "$(printf '# T\n\ntext')" "$(cat "$REPO/gen/g.md")"
git -C "$REPO" rm -q --cached gen/g.md
rm -r "$REPO/gen"
mkdir -p "$REPO/gen" "$REPO/docs/deep"
printf '# T\n\n<b>x</b>\n' >"$REPO/gen/g.md"
printf '{ "default": true, "MD013": false, "MD041": false }\n' >"$REPO/docs/.markdownlint.json"
printf 'text\n\n<b>x</b>' >"$REPO/docs/deep/gone.md"
git -C "$REPO" add gen/g.md docs/.markdownlint.json docs/deep/gone.md
rm -r "$REPO/gen" "$REPO/docs/deep"
# Nothing can be fixed in place, so the fixable MD047 is reported too; MD041
# stays off, as the nested config says.
expect "staged then deleted from the work tree: the staged findings block under the nested config, ignores hold, nothing rewritten" "1||docs/deep/gone.md:3: MD033/no-inline-html Inline HTML [Element: b]
docs/deep/gone.md:3: MD047/single-trailing-newline Files should end with a single newline character
$HINT" "$(check "$REPO")"
expect "staged then deleted: the file is not recreated" "no" "$([[ -e "$REPO/docs/deep/gone.md" ]] && echo yes || echo no)"
expect "staged then deleted: the index keeps its unfixed bytes" "$(printf 'text\n\n<b>x</b>')x" "$(
  git -C "$REPO" show :docs/deep/gone.md
  printf x
)"
git -C "$REPO" rm -q --cached gen/g.md docs/deep/gone.md
ln -s missing.md "$REPO/link.md"
git -C "$REPO" add link.md
rm "$REPO/link.md"
expect "staged then deleted: a staged symlink is not checked" "0||" "$(check "$REPO")"

# A config that can run repository code: skipped until the user approves its
# exact content state, as powershell-format gates CustomRulePath.
GATE_LEAD='markdown-format trust gate: markdownlint-cli2 skipped for files under'
DATA="$WORK/plugin-data"
new_repo NONE
printf 'module.exports = {};\n' >"$REPO/helper.cjs"
printf 'const h = require("./helper.cjs");\nmodule.exports = { config: { default: true, MD013: false } };\n' >"$REPO/.markdownlint-cli2.cjs"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m config --no-verify
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
out="$(cd "$REPO" && CLAUDE_PLUGIN_DATA="$DATA" CLAUDECODE=1 bash "$CHECK" 2>&1)"
expect "unapproved executable config, agent commit: exit 0" "0" "$?"
expect "an agent is told the verdict and never the approval command" \
  "$GATE_LEAD .markdownlint-cli2.cjs; it can run repository code and is not approved. Approval is the user's." "$out"
expect "an unapproved config never runs: the file keeps its bytes" "$(printf '# T\n\ntext')" "$(cat "$REPO/a.md")"
out="$(cd "$REPO" && CLAUDE_PLUGIN_DATA="$DATA" bash "$CHECK" 2>&1)"
marker="$(printf '%s' "$out" | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
expect "the approval store is the git directory even when CLAUDE_PLUGIN_DATA names another" yes \
  "$([[ -n "$marker" && "$marker" == "$REPO"/.git/markdown-format/trust-approvals/md-* ]] && echo yes)"
mkdir -p "$marker"
out="$(cd "$REPO" && CLAUDE_PLUGIN_DATA="$DATA" bash "$CHECK" 2>"$WORK/stderr")"
expect "an approved state is linted and rewritten" "0|a.md|" "$?|$out|$(cat "$WORK/stderr")"
expect "the approved rewrite landed" "${FIXED}x" "$(
  cat "$REPO/a.md"
  printf x
)"
printf '# T\n\n<b>x</b>\n' >"$REPO/gone.md"
git -C "$REPO" add gone.md
rm "$REPO/gone.md"
expect "staged then deleted under an approved config that requires a module: still checked" "1||gone.md:3: MD033/no-inline-html Inline HTML [Element: b]
$HINT" "$(CLAUDE_PLUGIN_DATA="$DATA" check "$REPO")"
git -C "$REPO" rm -q --cached gone.md
printf '// unreviewed revision\n' >>"$REPO/helper.cjs"
printf '# T\n\ntext' >"$REPO/b.md"
git -C "$REPO" add b.md
(cd "$REPO" && CLAUDE_PLUGIN_DATA="$DATA" CLAUDECODE=1 bash "$CHECK" >/dev/null 2>&1)
expect "a changed module the config requires revokes the approval" "$(printf '# T\n\ntext')" "$(cat "$REPO/b.md")"
(cd "$REPO" && bash "$CHECK" >"$WORK/stdout" 2>"$WORK/stderr")
marker="$(sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p" "$WORK/stderr")"
expect "outside a session the approval store is the git directory" yes \
  "$([[ "$marker" == "$REPO"/.git/markdown-format/trust-approvals/md-* ]] && echo yes)"

new_repo NONE
printf '{ "config": { "default": true }, "customRules": ["./rule.cjs"] }\n' >"$REPO/.markdownlint-cli2.jsonc"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a config naming customRules is gated" \
  "0||$GATE_LEAD .markdownlint-cli2.jsonc; it can run repository code and is not approved. Approval is the user's." \
  "$(
    cd "$REPO" && CLAUDECODE=1 bash "$CHECK" 2>"$WORK/stderr"
    printf '%s||%s' "$?" "$(cat "$WORK/stderr")"
  )"

new_repo NONE
printf '{ "config": { "default": true }, "ignores": ["a\\\\.md"] }\n' >"$REPO/.markdownlint-cli2.jsonc"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a config with a backslash inside a quoted string is unverifiable, with no approval route" \
  "0||$GATE_LEAD .markdownlint-cli2.jsonc; it cannot be verified free of repository code, so lint stays off." "$(check "$REPO")"

new_repo NONE
printf 'const path = require("path");\nmodule.exports = { config: { default: true } };\n' >"$REPO/.markdownlint-cli2.cjs"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a config that builds paths is unpinnable, with no approval route" \
  "0||$GATE_LEAD .markdownlint-cli2.cjs; it names code through an expression no approval can pin, so lint stays off." "$(check "$REPO")"
expect "an unpinnable config never runs: the file keeps its bytes" "$(printf '# T\n\ntext')" "$(cat "$REPO/a.md")"

new_repo NONE
printf 'module.exports = require("#cfg");\n' >"$REPO/.markdownlint-cli2.cjs"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a config requiring a package.json imports specifier is unpinnable" \
  "0||$GATE_LEAD .markdownlint-cli2.cjs; it names code through an expression no approval can pin, so lint stays off." "$(check "$REPO")"

new_repo NONE
mkdir -p "$REPO/sub"
printf 'module.exports = require("./helper.cjs");\n' >"$REPO/sub/cfg.cjs"
printf 'module.exports = { config: { default: true } };\n' >"$REPO/sub/helper.cjs"
ln -s sub/cfg.cjs "$REPO/.markdownlint-cli2.cjs"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a symlinked code config is unpinnable: its requires resolve from the link target" \
  "0||$GATE_LEAD .markdownlint-cli2.cjs; it names code through an expression no approval can pin, so lint stays off." "$(check "$REPO")"

new_repo NONE
printf '{ "default": true }\n' >"$REPO/.markdownlint.json"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a declarative .markdownlint.json config lints" "0|a.md|" "$(check "$REPO")"

new_repo
mkdir -p "$REPO/.githooks/markdown-format"
printf '# T\n\ntext' >"$REPO/.githooks/markdown-format/copy.md"
git -C "$REPO" add -f .githooks/markdown-format/copy.md
expect "an installed copy under .githooks/ is skipped" "0||" "$(check "$REPO")"

new_repo
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
expect "--worktree: an uncommitted finding blocks and nothing is rewritten" "1||$HTML
$HINT" "$(check "$REPO" --worktree)"
expect "--worktree: the file keeps its bytes" "$(printf '# T\n\n<b>x</b>')" "$(cat "$REPO/a.md")"
printf '# T\n\ntext' >"$REPO/a.md"
expect "--worktree: a fixable difference is reported, not rewritten" "1||a.md:3: MD047/single-trailing-newline Files should end with a single newline character
$HINT" "$(check "$REPO" --worktree)"
expect "--worktree: the file still has no final newline" "$(printf '# T\n\ntext')" "$(cat "$REPO/a.md")"
rm "$REPO/a.md"
expect "--worktree: no uncommitted change passes" "0||" "$(check "$REPO" --worktree)"

# A PATH with the tools the script runs and node, but no markdownlint-cli2.
NOMD="$WORK/nomd"
mkdir -p "$NOMD"
for t in git bash sed awk cat mktemp rm dirname grep tr readlink env sh node; do
  ln -s "$(command -v "$t")" "$NOMD/$t"
done
MDHELP='npm i -D markdownlint-cli2, or another method at https://github.com/DavidAnson/markdownlint-cli2'
new_repo
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" 2>&1)"
expect "missing markdownlint-cli2: an agent fails with the install command" "1" "$?"
expect "missing markdownlint-cli2: the message names the tool and the skip key" \
  "FAIL: markdownlint-cli2 missing. Install: $MDHELP
To skip only while markdownlint-cli2 is missing: git -c checks.skipmissing=markdownlint-cli2 commit ..." "$out"
out="$(cd "$REPO" && PATH="$NOMD" bash "$CHECK" 2>&1)"
expect "missing markdownlint-cli2: a person gets a notice and exit 0" "0|NOTICE: markdownlint-cli2 missing, so this check did not run. Install: $MDHELP" "$?|$out"
git -C "$REPO" config checks.skipmissing markdownlint-cli2
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" 2>&1)"
expect "missing markdownlint-cli2 named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: markdownlint-cli2 (missing)" "$?|$out"
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" --worktree 2>&1)"
expect "missing markdownlint-cli2 named in checks.skipmissing, --worktree: skipped with a line" "0|SKIPPED: markdownlint-cli2 (missing)" "$?|$out"
git -C "$REPO" config --unset checks.skipmissing
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" --worktree 2>&1)"
expect "missing markdownlint-cli2, --worktree: an agent fails as at commit time" \
  "1|FAIL: markdownlint-cli2 missing. Install: $MDHELP" "$?|${out%%$'\n'*}"
git -C "$REPO" reset -q
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" 2>&1)"
expect "no Markdown staged: a missing markdownlint-cli2 does not fail the commit" "0|" "$?|$out"

# markdownlint-cli2 only in the repo's own node_modules/.bin.
new_repo
mkdir -p "$REPO/node_modules/.bin"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_MD" >"$REPO/node_modules/.bin/markdownlint-cli2"
chmod +x "$REPO/node_modules/.bin/markdownlint-cli2"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" 2>&1)"
expect "markdownlint-cli2 found in the repo's node_modules/.bin when PATH has none" "0|a.md" "$?|$out"

# A shim whose symlink leaves the repository is not run.
new_repo
mkdir -p "$REPO/node_modules/.bin" "$WORK/outside$n"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_MD" >"$WORK/outside$n/markdownlint-cli2"
chmod +x "$WORK/outside$n/markdownlint-cli2"
ln -s "$WORK/outside$n/markdownlint-cli2" "$REPO/node_modules/.bin/markdownlint-cli2"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" 2>&1)"
expect "a node_modules/.bin symlink that escapes the repository is rejected" "1" "$?"
expect "the escaping shim is treated as a missing tool" "FAIL: markdownlint-cli2 missing." "${out%% Install:*}"
expect "the escaping shim did not run" "$(printf '# T\n\ntext')" "$(cat "$REPO/a.md")"

# End to end through the plugin's vendored installer and real commits.
new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"markdown-check","status":"installed"}]' "$status"
expect "the installed copy carries the stamp on line 2" yes \
  "$(grep -qE '^# markdown-format markdown-check sha256:[0-9a-f]{64}$' < <(sed -n 2p "$REPO/.git/hooks/markdown-format/markdown-check.sh") && echo yes)"
expect "the gates file is installed beside the script" yes \
  "$([[ -f "$REPO/.git/hooks/markdown-format/markdown-gates.sh" ]] && echo yes)"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
git -C "$REPO" commit -q -m format >/dev/null 2>&1
expect "git commit runs the entry and succeeds" "0" "$?"
expect "the commit holds the fixed bytes" "${FIXED}x" "$(
  git -C "$REPO" show HEAD:a.md
  printf x
)"
expect "the work tree matches the commit" "" "$(git -C "$REPO" status --porcelain)"
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
err="$(git -C "$REPO" commit -q -m finding 2>&1)"
expect "git commit fails on a finding on an added line" "1" "$?"
expect "the commit failure names the line" "$HTML" "$(printf '%s\n' "$err" | head -1)"
expect "verify reports ok after the install" "ok	markdown-check" "$(node "$INSTALL" verify --repo "$REPO")"

echo "markdown-check: $PASS passed, $FAIL failed"
((FAIL == 0))
