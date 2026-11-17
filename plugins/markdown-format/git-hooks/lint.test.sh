#!/usr/bin/env bash
# test-scope: plugins/markdown-format/git-hooks/entries.json plugins/markdown-format/git-hooks/adapters.sh plugins/markdown-format/git-hooks/markdown-gates.sh
# test-scope: plugins/markdown-format/lib/git-hooks/check-lib.sh plugins/markdown-format/lib/git-hooks/resolve-tool.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT CLAUDE_PLUGIN_DATA

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/lint.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
REAL_MD="$(command -v markdownlint-cli2 || true)"
[[ -n "$REAL_MD" ]] || REAL_MD="$(cd "$PLUGIN/../.." && pwd)/node_modules/.bin/markdownlint-cli2"
if [[ ! -x "$REAL_MD" ]] || ! command -v node >/dev/null 2>&1; then
  echo "SKIP: markdownlint-cli2 or node not found -- lint entry tests skipped"
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

DEFAULT_CFG='{ "config": { "default": true, "MD013": false } }'
n=0
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  if [[ "${1:-}" != NONE ]]; then
    printf '%s\n' "${1:-$DEFAULT_CFG}" >"$REPO/.markdownlint-cli2.jsonc"
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

HINT='markdown-format: fix the findings markdownlint-cli2 reported above, or adjust the repository markdownlint config.'
HTML='a.md:3: MD033/no-inline-html Inline HTML [Element: b]'
RAW="$(printf '# T\n\ntext')"

new_repo
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a finding on an added line blocks, naming that line" "1||$HTML
$HINT" "$(check "$REPO")"

new_repo
printf '# T\n\ntrailing   \n' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a finding with a column becomes path:line: rule message" "1||a.md:3: MD009/no-trailing-spaces Trailing spaces [Expected: 0 or 2; Actual: 3]
$HINT" "$(check "$REPO")"
expect "lint never rewrites the work tree" "$(printf '# T\n\ntrailing   ')" "$(cat "$REPO/a.md")"
expect "lint never rewrites the index" "$(printf '# T\n\ntrailing   ')" "$(git -C "$REPO" show :a.md)"
expect "lint prints nothing on stdout: no file is listed as rewritten" "" "$(cd "$REPO" && bash "$CHECK" 2>/dev/null)"

new_repo '{ "fix": true, "config": { "default": true, "MD013": false } }'
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
check "$REPO" >/dev/null
expect "a config with fix: true does not make lint rewrite the work tree" "$RAW" "$(cat "$REPO/a.md")"
expect "a config with fix: true does not make lint rewrite the index" "$RAW" "$(git -C "$REPO" show :a.md)"
check "$REPO" --worktree >/dev/null
expect "--worktree under fix: true leaves the file as written" "$RAW" "$(cat "$REPO/a.md")"

new_repo
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
mkdir -p "$WORK/fail-sed"
# shellcheck disable=SC2016 # $* expands when the shim runs
printf '#!/bin/sh\ncase " $* " in\n*"MD[0-9]"*) echo "sed: fatal error: internal error" >&2; exit 2 ;;\nesac\nexec %s "$@"\n' \
  "$(command -v sed)" >"$WORK/fail-sed/sed"
chmod +x "$WORK/fail-sed/sed"
out="$(cd "$REPO" && PATH="$WORK/fail-sed:$PATH" bash "$CHECK" 2>&1)"
expect "a sed that fails while reading the markdownlint findings fails the commit" \
  "1|sed: fatal error: internal error
lint.sh: sed exited 2 while reading the markdownlint findings, so this change was not fully checked; fix that failure, then commit again" "$?|$out"

new_repo
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
git -C "$REPO" commit -q -m old --no-verify
printf '# T\n\n<b>x</b>\n\nmore\n' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a finding on a line the commit did not add does not block" "0||" "$(check "$REPO")"

new_repo
printf '# T\n\ntext\n' >"$REPO/a.md"
git -C "$REPO" add a.md
printf '# T\n\ntext\n\n<b>x</b>\n' >"$REPO/a.md"
expect "a partly staged file is linted as staged: its unstaged finding does not block" "0||" "$(check "$REPO")"
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
printf '# T\n\ntext\n' >"$REPO/a.md"
expect "a staged finding blocks even when the work tree has since dropped it" "1||$HTML
$HINT" "$(check "$REPO")"

new_repo NONE
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "no markdownlint config: nothing runs and the entry passes" "0||" "$(check "$REPO")"

new_repo
printf '{ "ignores": ["gen/**"] }\n' >"$REPO/.markdownlint-cli2.jsonc"
git -C "$REPO" add .markdownlint-cli2.jsonc
git -C "$REPO" commit -q -m cfg --no-verify
mkdir -p "$REPO/gen" "$REPO/docs/deep"
printf '# T\n\n<b>x</b>\n' >"$REPO/gen/g.md"
printf '{ "default": true, "MD013": false, "MD041": false }\n' >"$REPO/docs/.markdownlint.json"
printf 'text\n\n<b>x</b>' >"$REPO/docs/deep/gone.md"
git -C "$REPO" add gen/g.md docs/.markdownlint.json docs/deep/gone.md
rm -r "$REPO/gen" "$REPO/docs/deep"
expect "staged then deleted from the work tree: the staged findings block under the nested config, ignores hold, nothing rewritten" "1||docs/deep/gone.md:3: MD033/no-inline-html Inline HTML [Element: b]
docs/deep/gone.md:3: MD047/single-trailing-newline Files should end with a single newline character
$HINT" "$(check "$REPO")"
expect "staged then deleted: the file is not recreated" "no" "$([[ -e "$REPO/docs/deep/gone.md" ]] && echo yes || echo no)"
git -C "$REPO" rm -q --cached gen/g.md docs/deep/gone.md
ln -s missing.md "$REPO/link.md"
git -C "$REPO" add link.md
rm "$REPO/link.md"
expect "staged then deleted: a staged symlink is not checked" "0||" "$(check "$REPO")"

new_repo
printf '# T\n\n<b>x</b>\n' >"$REPO/[x].md"
printf '# T\n\n<b>x</b>\n' >"$REPO/#h.md"
printf '# T\n\n<b>x</b>\n' >"$REPO/-d.md"
printf '# T\n\ntext\n' >"$REPO/x.md"
git -C "$REPO" --literal-pathspecs add -- '[x].md' '#h.md' '-d.md' x.md
expect "names holding [ ], a leading # and a leading - are each linted as themselves" "1||-d.md:3: MD033/no-inline-html Inline HTML [Element: b]
[x].md:3: MD033/no-inline-html Inline HTML [Element: b]
#h.md:3: MD033/no-inline-html Inline HTML [Element: b]
$HINT" "$(check "$REPO")"

new_repo
mkdir -p "$REPO/node_modules/.bin" "$WORK/stub$n"
printf '#!/bin/sh\necho "markdownlint-cli2 v0" >&2\necho "something odd happened" >&2\nexit 1\n' >"$WORK/stub$n/markdownlint-cli2"
chmod +x "$WORK/stub$n/markdownlint-cli2"
printf '# T\n\ntext\n' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a run that exits 1 with no parseable finding fails closed and shows the output" \
  "1||markdown-format: markdownlint-cli2 exited 1 and reported no <path>:<line> finding, so the change was not checked:
markdownlint-cli2 v0
something odd happened" "$(PATH="$WORK/stub$n:$PATH" check "$REPO")"
printf '#!/bin/sh\necho "Error: Unable to use configuration file" >&2\nexit 2\n' >"$WORK/stub$n/markdownlint-cli2"
expect "a run that exits 2 is a tool failure, its output shown" \
  "1||markdown-format: markdownlint-cli2 failed:
Error: Unable to use configuration file" "$(PATH="$WORK/stub$n:$PATH" check "$REPO")"

new_repo
mkdir -p "$REPO/.claude/ecosystems" "$WORK/bin$n"
printf '#!/bin/sh\n: >"%s/record-ran"\n' "$WORK" >"$WORK/bin$n/stublint"
chmod +x "$WORK/bin$n/stublint"
printf 'globs: ["*.md"]\nlint-cmd: "stublint <files>"\n' >"$REPO/.claude/ecosystems/markdown.yaml"
git -C "$REPO" add .claude
git -C "$REPO" commit -q -m record --no-verify
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "with a record, the adapter lints" "1||$HTML
$HINT" "$(PATH="$WORK/bin$n:$PATH" check "$REPO")"
expect "the record command was not called" "no" "$([[ -e "$WORK/record-ran" ]] && echo yes || echo no)"
expect "--resolve lint row names the adapter and the record note" \
  "markdown-format	lint	adapter:markdownlint-cli2	markdownlint-cli2	yes	config .markdownlint-cli2.jsonc; binary markdownlint-cli2 on PATH; the markdown record is not run by hooks; /toolchain:lint and /toolchain:check run it" \
  "$(cd "$REPO" && sh "$CHECK" --resolve)"

# A config that can run repository code: skipped until the user approves its
# exact content state, as powershell-format gates CustomRulePath.
GATE_LEAD='markdown-format trust gate: markdownlint-cli2 skipped for files under'
DATA="$WORK/plugin-data"
new_repo NONE
printf 'module.exports = {};\n' >"$REPO/helper.cjs"
printf 'const h = require("./helper.cjs");\nmodule.exports = { config: { default: true, MD013: false } };\n' >"$REPO/.markdownlint-cli2.cjs"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m config --no-verify
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
out="$(cd "$REPO" && CLAUDE_PLUGIN_DATA="$DATA" CLAUDECODE=1 bash "$CHECK" 2>&1)"
expect "unapproved executable config, agent commit: exit 0" "0" "$?"
expect "an agent is told the verdict and never the approval command" \
  "$GATE_LEAD .markdownlint-cli2.cjs; it can run repository code and is not approved. Approval is the user's." "$out"
out="$(cd "$REPO" && CLAUDE_PLUGIN_DATA="$DATA" bash "$CHECK" 2>&1)"
marker="$(printf '%s' "$out" | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
expect "the approval store is the git directory even when CLAUDE_PLUGIN_DATA names another" yes \
  "$([[ -n "$marker" && "$marker" == "$(cd "$REPO" && pwd -P)"/.git/markdown-format/trust-approvals/md-* ]] && echo yes)"
expect "--worktree prints no trust notice" "0||" "$(check "$REPO" --worktree)"
mkdir -p "$marker"
expect "an approved state is linted" "1||$HTML
$HINT" "$(CLAUDE_PLUGIN_DATA="$DATA" check "$REPO")"
printf '# T\n\n<b>x</b>\n' >"$REPO/gone.md"
git -C "$REPO" add gone.md
rm "$REPO/gone.md"
git -C "$REPO" reset -q a.md
expect "staged then deleted under an approved config that requires a module: still checked" "1||gone.md:3: MD033/no-inline-html Inline HTML [Element: b]
$HINT" "$(check "$REPO")"
git -C "$REPO" rm -q --cached gone.md
git -C "$REPO" add a.md
printf '// unreviewed revision\n' >>"$REPO/helper.cjs"
expect "a changed module the config requires revokes the approval" "0||$GATE_LEAD .markdownlint-cli2.cjs; it can run repository code and is not approved. Approval is the user's." \
  "$(CLAUDECODE=1 check "$REPO")"

new_repo NONE
printf '{ "config": { "default": true }, "customRules": ["./rule.cjs"] }\n' >"$REPO/.markdownlint-cli2.jsonc"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a config naming customRules is gated" \
  "0||$GATE_LEAD .markdownlint-cli2.jsonc; it can run repository code and is not approved. Approval is the user's." \
  "$(CLAUDECODE=1 check "$REPO")"

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
printf '{ "default": false, "MD033": true }\n' >"$REPO/base.json"
printf '{ "extends": "./base.json" }\n' >"$REPO/.markdownlint.json"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m cfg --no-verify
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a config that extends a sibling file lints under the extended rules" "1||$HTML
$HINT" "$(check "$REPO")"

new_repo NONE
printf 'module.exports = { names: ["no-op"], description: "no-op", tags: ["x"], parser: "none", function: () => {} };\n' >"$REPO/rule.cjs"
printf '{ "config": { "default": true, "MD013": false }, "customRules": ["./rule.cjs"] }\n' >"$REPO/.markdownlint-cli2.jsonc"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m cfg --no-verify
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
marker="$(cd "$REPO" && bash "$CHECK" 2>&1 >/dev/null | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
mkdir -p "$marker"
expect "an approved config naming a relative customRules module lints" "1||$HTML
$HINT" "$(check "$REPO")"

new_repo NONE
printf '{ "default": true }\n' >"$REPO/.markdownlint.json"
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a declarative .markdownlint.json config lints" "1||$HTML
$HINT" "$(check "$REPO")"

new_repo
mkdir -p "$REPO/.githooks/markdown-format"
printf '# T\n\n<b>x</b>\n' >"$REPO/.githooks/markdown-format/copy.md"
git -C "$REPO" add -f .githooks/markdown-format/copy.md
expect "an installed copy under .githooks/ is skipped" "0||" "$(check "$REPO")"
mkdir -p "$REPO/docs/.githooks"
printf '# T\n\n<b>x</b>\n' >"$REPO/docs/.githooks/notes.md"
git -C "$REPO" add docs/.githooks/notes.md
expect "a .githooks directory below the root is linted like any other" "1||docs/.githooks/notes.md:3: MD033/no-inline-html Inline HTML [Element: b]
$HINT" "$(check "$REPO")"

new_repo
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
expect "--worktree: an uncommitted finding blocks and nothing is rewritten" "1||$HTML
$HINT" "$(check "$REPO" --worktree)"
expect "--worktree: the file keeps its bytes" "$(printf '# T\n\n<b>x</b>')" "$(cat "$REPO/a.md")"
printf '# T\n\ntext' >"$REPO/a.md"
expect "--worktree: a fixable difference is reported, not rewritten" "1||a.md:3: MD047/single-trailing-newline Files should end with a single newline character
$HINT" "$(check "$REPO" --worktree)"
expect "--worktree: the file still has no final newline" "$RAW" "$(cat "$REPO/a.md")"
rm "$REPO/a.md"
expect "--worktree: no uncommitted change passes" "0||" "$(check "$REPO" --worktree)"

# A PATH with the tools the script runs and node, but no markdownlint-cli2.
NOMD="$WORK/nomd"
mkdir -p "$NOMD"
for t in git bash sed awk cat mktemp rm dirname grep tr readlink env sh node ln mkdir; do
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$t")" >"$NOMD/$t"
  chmod +x "$NOMD/$t"
done
MDHELP='npm i -D markdownlint-cli2, or another method at https://github.com/DavidAnson/markdownlint-cli2'
new_repo
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" 2>&1)"
expect "missing markdownlint-cli2: an agent fails with the install command and the skip key" \
  "1|FAIL: markdownlint-cli2 missing. Install: $MDHELP
To skip only while markdownlint-cli2 is missing: git -c checks.skipmissing=markdownlint-cli2 commit ..." "$?|$out"
out="$(cd "$REPO" && PATH="$NOMD" bash "$CHECK" 2>&1)"
expect "missing markdownlint-cli2: a person gets a notice and exit 0" "0|NOTICE: markdownlint-cli2 missing, so this check did not run. Install: $MDHELP" "$?|$out"
git -C "$REPO" config checks.skipmissing markdownlint-cli2
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" --worktree 2>&1)"
expect "missing markdownlint-cli2 named in checks.skipmissing, --worktree: skipped with a line" "0|SKIPPED: markdownlint-cli2 (missing)" "$?|$out"
git -C "$REPO" config --unset checks.skipmissing
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" --worktree 2>&1)"
expect "missing markdownlint-cli2, --worktree: an agent fails as at commit time" \
  "1|FAIL: markdownlint-cli2 missing. Install: $MDHELP" "$?|${out%%$'\n'*}"

# markdownlint-cli2 only in the repo's own node_modules/.bin.
new_repo
mkdir -p "$REPO/node_modules/.bin"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_MD" >"$REPO/node_modules/.bin/markdownlint-cli2"
chmod +x "$REPO/node_modules/.bin/markdownlint-cli2"
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" 2>&1)"
expect "markdownlint-cli2 found in the repo's node_modules/.bin when PATH has none" "1|$HTML
$HINT" "$?|$out"

echo "lint: $PASS passed, $FAIL failed"
((FAIL == 0))
