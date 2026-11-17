#!/usr/bin/env bash
# test-scope: plugins/markdown-format/git-hooks/entries.json plugins/markdown-format/git-hooks/adapters.sh plugins/markdown-format/git-hooks/markdown-gates.sh
# test-scope: plugins/markdown-format/lib/git-hooks/check-lib.sh plugins/markdown-format/lib/git-hooks/install.mjs plugins/markdown-format/lib/git-hooks/resolve-tool.sh
# shellcheck disable=SC2016 # record commands are literal text
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT CLAUDE_PLUGIN_DATA

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/format.sh"
LINT="$HERE/lint.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
REAL_MD="$(command -v markdownlint-cli2 || true)"
[[ -n "$REAL_MD" ]] || REAL_MD="$(cd "$PLUGIN/../.." && pwd)/node_modules/.bin/markdownlint-cli2"
if [[ ! -x "$REAL_MD" ]] || ! command -v node >/dev/null 2>&1; then
  echo "SKIP: markdownlint-cli2 or node not found -- format entry tests skipped"
  exit 0
fi
PATH="${REAL_MD%/*}:$PATH"
export PATH

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

n=0
new_repo() {
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

check() {
  local repo="$1" out rc
  shift
  out="$(cd "$repo" && bash "$CHECK" "$@" 2>"$WORK/stderr")"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$WORK/stderr")"
}

FIXED=$'# T\n\ntext\n'
RAW="$(printf '# T\n\ntext')"

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

DRIFT='config differs between the index and the work tree; stage it or restore it, then commit'
new_repo
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
rm "$REPO/.markdownlint-cli2.jsonc"
expect "a markdownlint config deleted from the work tree refuses the commit, naming it" "1||.markdownlint-cli2.jsonc: $DRIFT" "$(check "$REPO")"
expect "the refused file is left as it was" "$RAW" "$(cat "$REPO/a.md")"

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
expect "an unfixable finding is not reported and does not fail the format entry" "0||" "$(check "$REPO")"
expect "the file with only an unfixable finding keeps its bytes" "$(printf '# T\n\n<b>x</b>')" "$(cat "$REPO/a.md")"

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
expect "no markdownlint config: the file is not touched and the entry passes" "0||" "$(check "$REPO")"
expect "no markdownlint config: bytes are as written" "$RAW" "$(cat "$REPO/a.md")"

new_repo NONE
mkdir -p "$REPO/docs/deep"
printf '{ "default": true }\n' >"$REPO/docs/.markdownlint.json"
printf '# T\n\ntext' >"$REPO/docs/deep/b.md"
printf '# T\n\ntext' >"$REPO/c.md"
git -C "$REPO" add docs/deep/b.md c.md
expect "a nested config opts in only its subtree" "0|docs/deep/b.md|" "$(check "$REPO")"
expect "a file outside the nested config keeps its bytes" "$RAW" "$(cat "$REPO/c.md")"

new_repo
printf '{ "ignores": ["gen/**"] }\n' >"$REPO/.markdownlint-cli2.jsonc"
mkdir -p "$REPO/gen"
printf '# T\n\ntext' >"$REPO/gen/g.md"
git -C "$REPO" add .markdownlint-cli2.jsonc gen/g.md
expect "a file the markdownlint config ignores is left alone" "0||" "$(check "$REPO")"
expect "an ignored file keeps its bytes" "$RAW" "$(cat "$REPO/gen/g.md")"

new_repo
printf '# T\n\ntext' >"$REPO/gone.md"
git -C "$REPO" add gone.md
rm "$REPO/gone.md"
expect "staged then deleted from the work tree: nothing is rewritten and the entry passes" "0||" "$(check "$REPO")"
expect "staged then deleted: the file is not recreated" "no" "$([[ -e "$REPO/gone.md" ]] && echo yes || echo no)"

new_repo
printf '# T\n\ntext' >"$REPO/x.md"
printf '# T\n\ntext' >"$REPO/[x].md"
printf '# T\n\ntext' >"$REPO/#h.md"
printf '# T\n\ntext' >"$REPO/-d.md"
git -C "$REPO" --literal-pathspecs add -- '[x].md' '#h.md' '-d.md'
expect "names holding [ ], a leading # and a leading - are each rewritten as themselves" "0|#h.md
-d.md
[x].md|" "$(check "$REPO")"
expect "the unstaged x.md a [x] glob would match keeps its bytes" "$RAW" "$(cat "$REPO/x.md")"

new_repo
printf '{ "globs": ["b.md"], "config": { "default": true, "MD013": false } }\n' >"$REPO/.markdownlint-cli2.jsonc"
git -C "$REPO" add .markdownlint-cli2.jsonc
git -C "$REPO" commit -q -m cfg --no-verify
printf '# T\n\ntext' >"$REPO/a.md"
printf '# B\n\ntext' >"$REPO/b.md"
git -C "$REPO" add a.md
expect "a config with globs: only the staged file is rewritten" "0|a.md|" "$(check "$REPO")"
expect "a config with globs: the unstaged file it names keeps its bytes" "$(printf '# B\n\ntextx')" "$(
  cat "$REPO/b.md"
  printf x
)"

new_repo
mkdir -p "$WORK/stub$n"
printf '#!/bin/sh\necho "Error: Unable to use configuration file" >&2\nexit 2\n' >"$WORK/stub$n/markdownlint-cli2"
chmod +x "$WORK/stub$n/markdownlint-cli2"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "a run that exits 2 fails the format entry, its output shown" \
  "1||markdown-format: markdownlint-cli2 failed:
Error: Unable to use configuration file" "$(PATH="$WORK/stub$n:$PATH" check "$REPO")"

new_repo
mkdir -p "$REPO/.claude/ecosystems" "$WORK/bin$n"
printf '#!/bin/sh\n: >"%s/record-ran"\n' "$WORK" >"$WORK/bin$n/stubfmt"
chmod +x "$WORK/bin$n/stubfmt"
printf 'globs: ["*.md"]\nfix-cmd: "stubfmt <files>"\nlint-cmd: "stubfmt <files>"\n' >"$REPO/.claude/ecosystems/markdown.yaml"
git -C "$REPO" add .claude
git -C "$REPO" commit -q -m record --no-verify
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "with a record and a markdownlint config, the adapter formats" "0|a.md|" "$(PATH="$WORK/bin$n:$PATH" check "$REPO")"
expect "the record command was not called" "no" "$([[ -e "$WORK/record-ran" ]] && echo yes || echo no)"
expect "--resolve names the adapter and says the record is not run by hooks" \
  "markdown-format	format	adapter:markdownlint-cli2	markdownlint-cli2	yes	config .markdownlint-cli2.jsonc; binary markdownlint-cli2 on PATH; the markdown record is not run by hooks; /toolchain:lint and /toolchain:check run it" \
  "$(cd "$REPO" && sh "$CHECK" --resolve)"

new_repo NONE
expect "--resolve with no config says why nothing resolved" "markdown-format	format	none		n/a	no markdownlint config" \
  "$(cd "$REPO" && sh "$CHECK" --resolve)"
mkdir -p "$REPO/docs" "$REPO/tools"
printf '{ "default": true }\n' >"$REPO/docs/.markdownlint.json"
printf '{ "customRules": ["./rule.cjs"] }\n' >"$REPO/tools/.markdownlint-cli2.jsonc"
git -C "$REPO" add docs tools
expect "--resolve finds a nested config in the repository" \
  "markdown-format	format	adapter:markdownlint-cli2	markdownlint-cli2	yes	config docs/.markdownlint.json; binary markdownlint-cli2 on PATH" \
  "$(cd "$REPO" && sh "$CHECK" --resolve)"
expect "--resolve <path> names each file's nearest config, or the trust verdict that holds it back" \
  "markdown-format	format	adapter:markdownlint-cli2	markdownlint-cli2	yes	config docs/.markdownlint.json; binary markdownlint-cli2 on PATH
markdown-format	format	none		n/a	config tools/.markdownlint-cli2.jsonc can run repository code and is not approved
markdown-format	format	none		n/a	no markdownlint config" \
  "$(cd "$REPO" && sh "$CHECK" --resolve docs/a.md tools/b.md c.md)"

new_repo NONE
printf 'module.exports = {};\n' >"$REPO/helper.cjs"
printf 'const h = require("./helper.cjs");\nmodule.exports = { config: { default: true, MD013: false } };\n' >"$REPO/.markdownlint-cli2.cjs"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m config --no-verify
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
expect "unapproved executable config, agent commit: silent, exit 0" "0||" "$(CLAUDECODE=1 check "$REPO")"
expect "an unapproved config never runs: the file keeps its bytes" "$RAW" "$(cat "$REPO/a.md")"
marker="$(cd "$REPO" && bash "$LINT" 2>&1 >/dev/null | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
mkdir -p "$marker"
expect "an approved state is rewritten" "0|a.md|" "$(check "$REPO")"
expect "the approved rewrite landed" "${FIXED}x" "$(
  cat "$REPO/a.md"
  printf x
)"
printf '// unreviewed revision\n' >>"$REPO/helper.cjs"
printf '# T\n\ntext' >"$REPO/b.md"
git -C "$REPO" add b.md
expect "a changed module the config requires revokes the approval" "0||$RAW" "$(check "$REPO")$(cat "$REPO/b.md")"

new_repo
mkdir -p "$REPO/.githooks/markdown-format"
printf '# T\n\ntext' >"$REPO/.githooks/markdown-format/copy.md"
git -C "$REPO" add -f .githooks/markdown-format/copy.md
expect "an installed copy under .githooks/ is skipped" "0||" "$(check "$REPO")"
mkdir -p "$REPO/docs/.githooks"
printf '# T\n\ntext' >"$REPO/docs/.githooks/notes.md"
git -C "$REPO" add docs/.githooks/notes.md
expect "a .githooks directory below the root is formatted like any other" "0|docs/.githooks/notes.md|" "$(check "$REPO")"

new_repo
printf '# T\n\ntext' >"$REPO/a.md"
expect "--worktree: the format entry rewrites nothing and passes" "0||" "$(check "$REPO" --worktree)"
expect "--worktree: the file keeps its bytes" "$RAW" "$(cat "$REPO/a.md")"

NOMD="$WORK/nomd"
mkdir -p "$NOMD"
for t in git bash sed awk cat mktemp rm dirname grep tr readlink env sh node; do
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
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" 2>&1)"
expect "missing markdownlint-cli2 named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: markdownlint-cli2 (missing)" "$?|$out"
git -C "$REPO" config --unset checks.skipmissing
git -C "$REPO" reset -q
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" 2>&1)"
expect "no Markdown staged: a missing markdownlint-cli2 does not fail the commit" "0|" "$?|$out"

new_repo
mkdir -p "$REPO/node_modules/.bin"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_MD" >"$REPO/node_modules/.bin/markdownlint-cli2"
chmod +x "$REPO/node_modules/.bin/markdownlint-cli2"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" 2>&1)"
expect "markdownlint-cli2 found in the repo's node_modules/.bin when PATH has none" "0|a.md" "$?|$out"
expect "--resolve names the repo-local binary" \
  "markdown-format	format	adapter:markdownlint-cli2	markdownlint-cli2	yes	config .markdownlint-cli2.jsonc; binary node_modules/.bin/markdownlint-cli2" \
  "$(cd "$REPO" && PATH="$NOMD" sh "$CHECK" --resolve)"

new_repo
mkdir -p "$REPO/node_modules/.bin" "$WORK/outside$n"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_MD" >"$WORK/outside$n/markdownlint-cli2"
chmod +x "$WORK/outside$n/markdownlint-cli2"
ln -s "$WORK/outside$n/markdownlint-cli2" "$REPO/node_modules/.bin/markdownlint-cli2"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOMD" bash "$CHECK" 2>&1)"
expect "a node_modules/.bin symlink that escapes the repository is treated as a missing tool" "1|FAIL: markdownlint-cli2 missing." "$?|${out%% Install:*}"
expect "the escaping shim did not run" "$RAW" "$(cat "$REPO/a.md")"

new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs both entries" '[{"entry":"format","status":"installed"},{"entry":"lint","status":"installed"}]' "$status"
expect "the installed format copy carries the stamp on line 2" yes \
  "$(grep -qE '^# markdown-format format sha256:[0-9a-f]{64}$' < <(sed -n 2p "$REPO/.git/hooks/markdown-format/format.sh") && echo yes)"
expect "the adapter, the gates and the resolver are installed beside the scripts" yes \
  "$([[ -f "$REPO/.git/hooks/markdown-format/adapters.sh" && -f "$REPO/.git/hooks/markdown-format/markdown-gates.sh" && -f "$REPO/.git/hooks/markdown-format/resolve-tool.sh" ]] && echo yes)"
printf '# T\n\ntext' >"$REPO/a.md"
git -C "$REPO" add a.md
git -C "$REPO" commit -q -m format >/dev/null 2>&1
expect "git commit runs the entries and succeeds" "0" "$?"
expect "the commit holds the fixed bytes" "${FIXED}x" "$(
  git -C "$REPO" show HEAD:a.md
  printf x
)"
expect "the work tree matches the commit" "" "$(git -C "$REPO" status --porcelain)"
printf '# T\n\n<b>x</b>\n' >"$REPO/a.md"
git -C "$REPO" add a.md
err="$(git -C "$REPO" commit -q -m finding 2>&1)"
expect "git commit fails on a finding on an added line" "1" "$?"
expect "the commit failure names the line" "a.md:3: MD033/no-inline-html Inline HTML [Element: b]" "$(printf '%s\n' "$err" | head -1)"
expect "verify reports both entries ok after the install" "ok	format
ok	lint" "$(node "$INSTALL" verify --repo "$REPO")"

echo "format: $PASS passed, $FAIL failed"
((FAIL == 0))
