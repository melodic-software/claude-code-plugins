#!/usr/bin/env bash
# Expected values pinned against Biome 2.6.7: `check --write --linter-enabled=false`
# formats and sorts imports and applies no lint fix, so a `let` useConst would
# rewrite stays `let` (https://biomejs.dev/reference/cli/#biome-check).
# BIOME_TEST_BIN names a native Biome binary; else `biome` on PATH is used.
# test-scope: plugins/javascript-format/git-hooks/entries.json plugins/javascript-format/git-hooks/adapters.sh
# test-scope: plugins/javascript-format/lib/git-hooks/check-lib.sh plugins/javascript-format/lib/git-hooks/install.mjs
# test-scope: plugins/javascript-format/lib/git-hooks/resolve-tool.sh
# test-scope: plugins/javascript-format/.claude-plugin/plugin.json
# test-scope: plugins/javascript-format/git-hooks/lint.sh
# shellcheck disable=SC2016 # record commands are literal text
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT BIOME_CONFIG_PATH

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/format.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
REAL_BIOME="${BIOME_TEST_BIN:-$(command -v biome)}"
if [[ -z "$REAL_BIOME" ]]; then
  echo "SKIP: biome not on PATH and BIOME_TEST_BIN unset -- format tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REAL_HOME="$HOME"
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1 HOME="$WORK/home"
mkdir -p "$HOME"

BIN="$WORK/bin"
mkdir -p "$BIN"
printf '#!/bin/sh\nHOME="%s" PATH="%s" exec "%s" "$@"\n' "$REAL_HOME" "$PATH" "$REAL_BIOME" >"$BIN/biome"
chmod +x "$BIN/biome"
cat >"$BIN/stubfmt" <<EOF
#!/bin/sh
for a in "\$@"; do
  printf '%s\n' "\$a" >>"$WORK/stub.log"
  printf 'formatted\n' >"\$a"
done
EOF
chmod +x "$BIN/stubfmt"

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
new_repo() { # [biome.json body; "NONE" for no config]
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  local cfg='{}'
  [[ -z "${1:-}" ]] || cfg="$1"
  if [[ "$cfg" != NONE ]]; then
    printf '%s\n' "$cfg" >"$REPO/biome.json"
  fi
  printf 'export const seed = 1;\n' >"$REPO/seed.ts"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m seed --no-verify
}
record() {
  mkdir -p "$REPO/.claude/ecosystems"
  printf '%s\n' "$1" >"$REPO/.claude/ecosystems/typescript.yaml"
  git -C "$REPO" add .claude/ecosystems/typescript.yaml
  git -C "$REPO" commit -q -m record --no-verify
}

check() { # <repo> [args...] -> "<rc>|<stdout>|<stderr>"
  local repo="$1" out rc
  shift
  out="$(cd "$repo" && PATH="$BIN:$PATH" bash "$CHECK" "$@" 2>"$WORK/stderr")"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$WORK/stderr")"
}

new_repo
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
expect "a staged unformatted file is rewritten, listed on stdout, and exits 0" "0|a.ts|" "$(check "$REPO")"
expect "the rewrite is in the work tree" "export const a = 1;" "$(cat "$REPO/a.ts")"
expect "the rewrite is re-staged: the index holds the formatted bytes" "export const a = 1;" "$(git -C "$REPO" show :a.ts)"
expect "re-staged: no unstaged change remains" "" "$(git -C "$REPO" diff --name-only)"

new_repo
printf '{"b":2,"a":1}\n' >"$REPO/data.json"
git -C "$REPO" add data.json
expect "a staged JSON file is rewritten" "0|data.json|" "$(check "$REPO")"
expect "the JSON is laid out the way Biome formats it" "$(printf '{ "b": 2, "a": 1 }')" "$(cat "$REPO/data.json")"

new_repo
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
printf 'export const a=1\nexport const b=2\n' >"$REPO/a.ts"
expect "a partly staged file is refused with the contract line" "1||a.ts: partly staged; format it or stage it fully, then commit" "$(check "$REPO")"
expect "a refused file is left byte for byte" "$(printf 'export const a=1\nexport const b=2')" "$(cat "$REPO/a.ts")"
expect "a refused file's index entry is left byte for byte" "export const a=1" "$(git -C "$REPO" show :a.ts)"

# Biome reads its config from the work tree; the commit holds the index's.
DRIFT='config differs between the index and the work tree; stage it or restore it, then commit'
new_repo
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
rm "$REPO/biome.json"
expect "a Biome config deleted from the work tree refuses the commit, naming it" "1||biome.json: $DRIFT" "$(check "$REPO")"
expect "the refused file is left as it was" "export const a=1" "$(cat "$REPO/a.ts")"

new_repo
mkdir -p "$REPO/pkg"
printf '{}\n' >"$REPO/pkg/biome.jsonc"
git -C "$REPO" add pkg/biome.jsonc
git -C "$REPO" commit -q -m config --no-verify
printf 'export const a=1\n' >"$REPO/pkg/a.ts"
git -C "$REPO" add pkg/a.ts
printf '{ "formatter": { "enabled": false } }\n' >"$REPO/pkg/biome.jsonc"
expect "a nested Biome config edited after staging refuses the commit" "1||pkg/biome.jsonc: $DRIFT" "$(check "$REPO")"
printf 'export const b=2\n' >"$REPO/b.ts"
git -C "$REPO" reset -q pkg/a.ts
git -C "$REPO" add b.ts
expect "a drifted config above no staged file does not refuse the commit" "0|b.ts|" "$(check "$REPO")"

new_repo
printf 'export const a=1\n' >"$REPO/a.ts"
printf 'notes\n' >"$REPO/notes.md"
git -C "$REPO" add a.ts notes.md
printf 'notes\nmore unstaged\n' >"$REPO/notes.md"
expect "a partly staged file that is not Biome's does not refuse the commit" "0|a.ts|" "$(check "$REPO")"

new_repo
printf 'import { b } from "./b";\nimport { a } from "./a";\nexport { a, b };\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
expect "the imports sort at commit" "0|a.ts|" "$(check "$REPO")"
expect "the sorted imports are staged" "$(printf 'import { a } from "./a";\nimport { b } from "./b";')" "$(git -C "$REPO" show :a.ts | head -2)"

new_repo '{ "assist": { "actions": { "source": { "organizeImports": "off" } } } }'
printf 'import { b } from "./b";\nimport { a } from "./a";\nexport { a, b };\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
check "$REPO" >/dev/null
expect "an assist action the config turns off stays off: imports keep their order" 'import { b } from "./b";' "$(git -C "$REPO" show :a.ts | head -1)"

new_repo
printf 'let x=1\nexport { x };\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
check "$REPO" >/dev/null
expect "no lint fix at commit: a let useConst would rewrite stays let, formatted" "$(printf 'let x = 1;\n\nexport { x };')" "$(git -C "$REPO" show :a.ts)"

new_repo
printf 'import { a } from "./a";\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
check "$REPO" >/dev/null
expect "an unused import is not deleted" 'import { a } from "./a";' "$(cat "$REPO/a.ts")"

new_repo NONE
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
expect "no Biome config and no record: the file is not touched and the entry passes" "0||" "$(check "$REPO")"
expect "no Biome config: bytes are as written" "export const a=1" "$(cat "$REPO/a.ts")"

new_repo NONE
printf '{}\n' >"$REPO/.biome.json"
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
expect "a hidden .biome.json does not opt in (older Biome would not load it)" "0||" "$(check "$REPO")"
expect "a hidden .biome.json: bytes are as written" "export const a=1" "$(cat "$REPO/a.ts")"

new_repo NONE
mkdir -p "$REPO/pkg/sub"
printf '{}\n' >"$REPO/pkg/biome.jsonc"
printf 'export const r=1\n' >"$REPO/r.ts"
printf 'export const b=2\n' >"$REPO/pkg/sub/b.ts"
git -C "$REPO" add r.ts pkg/sub/b.ts
expect "a config above a nested file opts only that file in" "0|pkg/sub/b.ts|" "$(check "$REPO")"
expect "the file outside the config keeps its bytes" "export const r=1" "$(cat "$REPO/r.ts")"
expect "the nested file is formatted" "export const b = 2;" "$(cat "$REPO/pkg/sub/b.ts")"

new_repo NONE
mkdir -p "$REPO/pkg/sub"
printf '{ "formatter": { "indentStyle": "space", "indentWidth": 2 } }\n' >"$REPO/biome.json"
printf '{ "root": false, "extends": "//", "formatter": { "indentWidth": 8 } }\n' >"$REPO/pkg/biome.json"
printf 'export function f() { return 1 }\n' >"$REPO/pkg/sub/f.ts"
git -C "$REPO" add biome.json pkg/biome.json pkg/sub/f.ts
check "$REPO" >/dev/null
expect "the topmost config runs the nested one: a nested file formats under both" "$(printf 'export function f() {\n        return 1;\n}')" "$(cat "$REPO/pkg/sub/f.ts")"

new_repo '{ "files": { "includes": ["**", "!**/gen/**"] } }'
mkdir -p "$REPO/gen"
printf 'export const g=1\n' >"$REPO/gen/g.ts"
git -C "$REPO" add gen/g.ts
check "$REPO" >/dev/null
expect "a file the config ignores keeps its bytes" "export const g=1" "$(cat "$REPO/gen/g.ts")"

new_repo
mkdir -p "$REPO/.githooks/javascript-format"
printf 'export const a=1\n' >"$REPO/.githooks/javascript-format/copy.ts"
git -C "$REPO" add -f .githooks/javascript-format/copy.ts
expect "an installed copy under .githooks/ is skipped" "0||" "$(check "$REPO")"
mkdir -p "$REPO/pkg/.githooks"
printf 'export const n=1\n' >"$REPO/pkg/.githooks/n.ts"
git -C "$REPO" add -f pkg/.githooks/n.ts
expect "only the root .githooks/ is skipped: a nested .githooks/ file is formatted" "0|pkg/.githooks/n.ts||export const n = 1;" "$(check "$REPO")|$(cat "$REPO/pkg/.githooks/n.ts")"

new_repo
printf 'export const a=1\n' >"$REPO/gone.ts"
git -C "$REPO" add gone.ts
rm "$REPO/gone.ts"
expect "staged then deleted from the work tree: nothing is rewritten" "0||" "$(check "$REPO")"
expect "staged then deleted: the file is not recreated" "no" "$([[ -e "$REPO/gone.ts" ]] && echo yes || echo no)"

new_repo
EXT="$WORK/external-cfg"
mkdir -p "$EXT"
printf '{ "javascript": { "formatter": { "quoteStyle": "single" } } }\n' >"$EXT/biome.json"
printf 'export const s = "hi";\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
(cd "$REPO" && BIOME_CONFIG_PATH="$EXT" PATH="$BIN:$PATH" bash "$CHECK") >/dev/null 2>&1
expect "BIOME_CONFIG_PATH does not swap the repository config" 'export const s = "hi";' "$(cat "$REPO/a.ts")"

new_repo
printf 'export const a=1\n' >"$REPO/a.ts"
expect "--worktree: the format entry rewrites nothing and passes" "0||" "$(check "$REPO" --worktree)"
expect "--worktree: the file keeps its bytes" "export const a=1" "$(cat "$REPO/a.ts")"

# A PATH with the tools the script runs, git and no biome.
NOBIOME="$WORK/nobiome"
mkdir -p "$NOBIOME"
for t in git bash sh sed awk cat mktemp rm dirname grep tr env head; do
  ln -s "$(command -v "$t")" "$NOBIOME/$t"
done
INSTALL_HINT="npm i -D @biomejs/biome, or another method at https://biomejs.dev/guides/getting-started/"
new_repo
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOBIOME" bash "$CHECK" 2>&1)"
expect "missing biome: an agent fails with the install command and the skip key" \
  "1|FAIL: biome missing. Install: $INSTALL_HINT
To skip only while biome is missing: git -c checks.skipmissing=biome commit ..." "$?|$out"
out="$(cd "$REPO" && PATH="$NOBIOME" bash "$CHECK" 2>&1)"
expect "missing biome: a person gets a notice and exit 0" "0|NOTICE: biome missing, so this check did not run. Install: $INSTALL_HINT" "$?|$out"
git -C "$REPO" config checks.skipmissing biome
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOBIOME" bash "$CHECK" 2>&1)"
expect "missing biome named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: biome (missing)" "$?|$out"
git -C "$REPO" config --unset checks.skipmissing
git -C "$REPO" reset -q
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOBIOME" bash "$CHECK" 2>&1)"
expect "missing biome with nothing of Biome's staged: an agent is not failed" "0|" "$?|$out"

new_repo
mkdir -p "$REPO/node_modules/.bin"
cp "$BIN/biome" "$REPO/node_modules/.bin/biome"
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOBIOME" bash "$CHECK" 2>&1)"
expect "biome found in the repo's node_modules/.bin when PATH has none" "0|a.ts" "$?|$out"

new_repo NONE
mkdir -p "$REPO/pkg/node_modules/.bin"
cp "$BIN/biome" "$REPO/pkg/node_modules/.bin/biome"
printf '{}\n' >"$REPO/pkg/biome.json"
printf 'export const a=1\n' >"$REPO/pkg/a.ts"
git -C "$REPO" add pkg/a.ts
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOBIOME" bash "$CHECK" 2>&1)"
expect "biome found in the governing config directory's node_modules/.bin" "0|pkg/a.ts" "$?|$out"

# A node_modules the repository commits is never run, even when it shadows the
# biome on PATH.
new_repo
mkdir -p "$REPO/node_modules/.bin"
printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$WORK/committed-ran" >"$REPO/node_modules/.bin/biome"
chmod +x "$REPO/node_modules/.bin/biome"
git -C "$REPO" add node_modules/.bin/biome
git -C "$REPO" commit -q -m vendored --no-verify
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$BIN:$PATH" bash "$CHECK" 2>&1)"
expect "a committed node_modules/.bin/biome is passed over for the one on PATH" "0|a.ts" "$?|$out"
expect "the committed biome never ran" no "$([[ -e "$WORK/committed-ran" ]] && echo yes || echo no)"

new_repo
record 'globs: ["*.ts"]
fix-cmd: "stubfmt <files>"'
printf 'export const a=1\n' >"$REPO/a.ts"
name='$(touch marker);b.ts'
printf 'export const b=1\n' >"$REPO/$name"
git -C "$REPO" add -- a.ts "$name"
: >"$WORK/stub.log"
expect "with a record and a Biome config, Biome formats and the record command never runs" "0|$name
a.ts|" "$(check "$REPO")"
expect "the record command was not called" "" "$(cat "$WORK/stub.log")"
expect "the index holds Biome's bytes" "export const a = 1;" "$(git -C "$REPO" show :a.ts)"
expect "a crafted file name reached Biome as data and ran nothing" "no|export const b = 1;" "$([[ -e "$REPO/marker" ]] && echo yes || echo no)|$(cat "$REPO/$name")"

new_repo NONE
record 'globs: ["*.ts"]
fix-cmd: "stubfmt <files>"'
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
expect "a record with no Biome config runs nothing at commit" "0||" "$(check "$REPO")"
expect "the file stays as written" "export const a=1" "$(cat "$REPO/a.ts")"
expect "--resolve says the record is not run by hooks and names what runs it" "javascript-format	format	none		n/a	no Biome config; the typescript record is not run by hooks; /toolchain:lint and /toolchain:check run it" "$(cd "$REPO" && PATH="$BIN:$PATH" bash "$CHECK" --resolve)"

new_repo NONE
mkdir -p "$REPO/app/src" "$REPO/scripts" "$REPO/app/node_modules/.bin"
printf '{}\n' >"$REPO/app/biome.jsonc"
printf '{ "root": false }\n' >"$REPO/app/src/biome.json"
printf 'export const m = 1;\n' >"$REPO/app/src/mod.ts"
printf 'export const r = 1;\n' >"$REPO/scripts/run.ts"
printf '#!/bin/sh\nexit 0\n' >"$REPO/app/node_modules/.bin/biome"
chmod +x "$REPO/app/node_modules/.bin/biome"
expect "--resolve <path> names the topmost governing config and the local binary, per file" "javascript-format	format	adapter:biome	biome	yes	config app/biome.jsonc; binary app/node_modules/.bin/biome
javascript-format	format	none		n/a	" "$(cd "$REPO" && PATH="$BIN:$PATH" bash "$CHECK" --resolve app/src/mod.ts scripts/run.ts)"
expect "--resolve with no path: an untracked nested config is not found" "javascript-format	format	none		n/a	no Biome config" "$(cd "$REPO" && PATH="$BIN:$PATH" bash "$CHECK" --resolve)"
git -C "$REPO" add app/biome.jsonc
expect "--resolve with no path names a tracked nested config" "javascript-format	format	adapter:biome	biome	yes	config app/biome.jsonc; binary app/node_modules/.bin/biome" "$(cd "$REPO" && PATH="$BIN:$PATH" bash "$CHECK" --resolve)"
new_repo NONE
printf '{}\n' >"$REPO/.biome.json"
expect "--resolve with nothing resolved says why the adapter did not opt in" "javascript-format	format	none		n/a	no Biome config: a hidden .biome.json does not opt in" "$(cd "$REPO" && PATH="$BIN:$PATH" bash "$CHECK" --resolve)"

# End to end through the plugin's vendored installer and real commits.
new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(PATH="$BIN:$PATH" node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs both entries" '[{"entry":"format","status":"installed"},{"entry":"lint","status":"installed"}]' "$status"
expect "the installed format copy carries the stamp on line 2" yes \
  "$(grep -qE '^# javascript-format format sha256:[0-9a-f]{64}$' < <(sed -n 2p "$REPO/.git/hooks/javascript-format/format.sh") && echo yes)"
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
PATH="$BIN:$PATH" git -C "$REPO" commit -q -m format >/dev/null 2>&1
expect "git commit runs the entries and succeeds" "0" "$?"
expect "the commit holds the formatted bytes" "export const a = 1;" "$(git -C "$REPO" show HEAD:a.ts)"
expect "the work tree matches the commit" "" "$(git -C "$REPO" status --porcelain)"
printf 'export const a = 1;\nconst unusedVar = 1;\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
err="$(PATH="$BIN:$PATH" git -C "$REPO" commit -q -m finding 2>&1)"
expect "git commit fails on a finding on an added line" "1" "$?"
expect "the commit failure names the line" "a.ts:2: lint/correctness/noUnusedVariables: This variable unusedVar is unused." "$(printf '%s\n' "$err" | head -1)"
expect "verify reports both entries ok after the install" "ok	format
ok	lint" "$(PATH="$BIN:$PATH" node "$INSTALL" verify --repo "$REPO")"

echo "format: $PASS passed, $FAIL failed"
((FAIL == 0))
