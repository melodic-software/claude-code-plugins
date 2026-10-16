#!/usr/bin/env bash
# Contract tests for the biome-format pre-commit entry (git-hooks/biome-check.sh):
# staged JavaScript, TypeScript and JSON files are rewritten and re-staged, a
# partly staged one is refused untouched, a finding blocks only on a line the
# commit adds, only a file a Biome config governs is touched, --worktree reports
# without rewriting, a missing biome follows the skip-key rule, and the plugin's
# own vendored installer wires the entry so `git commit` runs it.
# Expected values are Biome's documented output: `x=1` formats to `x = 1;`, an
# unused variable is lint/correctness/noUnusedVariables, an unused import is an
# unsafe fix that `--write` leaves alone, and imports sort by source.
# test-scope: plugins/biome-format/git-hooks/entries.json plugins/biome-format/lib/git-hooks/check-lib.sh plugins/biome-format/lib/git-hooks/install.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CLAUDECODE AI_AGENT BIOME_CONFIG_PATH

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/biome-check.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
if ! command -v biome >/dev/null 2>&1; then
  echo "SKIP: biome not on PATH -- biome-check tests skipped"
  exit 0
fi
REAL_BIOME="$(command -v biome)"

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

check() { # <repo> [args...] -> "<rc>|<stdout>|<stderr>"
  local repo="$1" out rc
  shift
  out="$(cd "$repo" && bash "$CHECK" "$@" 2>"$WORK/stderr")"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$WORK/stderr")"
}

HINT='biome-format: fix the findings above, or adjust the repository Biome config.'

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

new_repo
printf 'export const a=1\n' >"$REPO/a.ts"
printf 'notes\n' >"$REPO/notes.md"
git -C "$REPO" add a.ts notes.md
printf 'notes\nmore unstaged\n' >"$REPO/notes.md"
expect "a partly staged file that is not Biome's does not refuse the commit" "0|a.ts|" "$(check "$REPO")"

new_repo
printf 'export const seed = 1;\n\nconst unusedVar = 1;\n' >"$REPO/seed.ts"
git -C "$REPO" add seed.ts
expect "a finding on an added line blocks, naming that line" "1||seed.ts:3: lint/correctness/noUnusedVariables: This variable unusedVar is unused.
$HINT" "$(check "$REPO")"

new_repo
printf 'const unusedVar = 1;\n' >"$REPO/seed.ts"
git -C "$REPO" add seed.ts
git -C "$REPO" commit -q -m old --no-verify
printf 'const unusedVar = 1;\n\nexport const ok = 2;\n' >"$REPO/seed.ts"
git -C "$REPO" add seed.ts
expect "a finding on a line the commit did not add does not block" "0||" "$(check "$REPO")"

new_repo
printf 'import { b } from "./b";\nimport { a } from "./a";\nexport { a, b };\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
expect "a safe fix is applied at commit: the imports sort" "0|a.ts|" "$(check "$REPO")"
expect "the sorted imports are staged" "$(printf 'import { a } from "./a";\nimport { b } from "./b";')" "$(git -C "$REPO" show :a.ts | head -2)"

new_repo
printf 'import { a } from "./a";\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
expect "an unused import is reported, not deleted: its fix is unsafe" "1||a.ts:1: lint/correctness/noUnusedImports: This import is unused.
$HINT" "$(check "$REPO")"
expect "the unused import keeps its bytes" 'import { a } from "./a";' "$(cat "$REPO/a.ts")"

new_repo NONE
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
expect "no Biome config: the file is not touched and the check passes" "0||" "$(check "$REPO")"
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
expect "a file the config ignores is left alone" "0||" "$(check "$REPO")"
expect "an ignored file keeps its bytes" "export const g=1" "$(cat "$REPO/gen/g.ts")"

new_repo
mkdir -p "$REPO/.githooks/biome-format"
printf 'export const a=1\n' >"$REPO/.githooks/biome-format/copy.ts"
git -C "$REPO" add -f .githooks/biome-format/copy.ts
expect "an installed copy under .githooks/ is skipped" "0||" "$(check "$REPO")"

new_repo
printf 'const = ;\n' >"$REPO/seed.ts"
git -C "$REPO" add seed.ts
out="$(check "$REPO")"
expect "a file that does not parse blocks the commit" "1" "${out%%|*}"
first="${out#1||}"
expect "the parse error names its line" "seed.ts:1: parse: Expected an identifier, an array pattern, or an object pattern but instead found '='." "${first%%$'\n'*}"

new_repo '{ not json'
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
out="$(check "$REPO")"
expect "a config Biome cannot read fails the commit" "1" "${out%%|*}"
first="${out#1||}"
expect "the failure says Biome broke" "biome-format: biome failed:" "${first%%$'\n'*}"

new_repo
EXT="$WORK/external-cfg"
mkdir -p "$EXT"
printf '{ "javascript": { "formatter": { "quoteStyle": "single" } } }\n' >"$EXT/biome.json"
printf 'export const s = "hi";\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
(cd "$REPO" && BIOME_CONFIG_PATH="$EXT" bash "$CHECK") >/dev/null 2>&1
expect "BIOME_CONFIG_PATH does not swap the repository config" 'export const s = "hi";' "$(cat "$REPO/a.ts")"

new_repo
printf 'export const a=1\nconst unusedVar = 1;\n' >"$REPO/a.ts"
expect "--worktree: an uncommitted finding blocks and nothing is rewritten" "1||a.ts:2: lint/correctness/noUnusedVariables: This variable unusedVar is unused.
$HINT" "$(check "$REPO" --worktree)"
expect "--worktree: the file keeps its bytes" "$(printf 'export const a=1\nconst unusedVar = 1;')" "$(cat "$REPO/a.ts")"
printf 'const unusedVar = 1;\n' >"$REPO/a.ts"
expect "--worktree: an untracked file is checked whole" "1||a.ts:1: lint/correctness/noUnusedVariables: This variable unusedVar is unused.
$HINT" "$(check "$REPO" --worktree)"
printf 'export const a=1\n' >"$REPO/a.ts"
expect "--worktree: a layout difference alone is not a finding" "0||" "$(check "$REPO" --worktree)"
rm "$REPO/a.ts"
expect "--worktree: no uncommitted change passes" "0||" "$(check "$REPO" --worktree)"

# A PATH with the tools the script runs, git and no biome.
NOBIOME="$WORK/nobiome"
mkdir -p "$NOBIOME"
for t in git bash sed awk cat mktemp rm dirname grep tr env head; do
  ln -s "$(command -v "$t")" "$NOBIOME/$t"
done
INSTALL_HINT="npm i -D @biomejs/biome, or another method at https://biomejs.dev/guides/getting-started/"
new_repo
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOBIOME" bash "$CHECK" 2>&1)"
expect "missing biome: an agent fails with the install command" "1" "$?"
expect "missing biome: the message names the tool and the skip key" \
  "FAIL: biome missing. Install: $INSTALL_HINT
To skip only while biome is missing: git -c checks.skipmissing=biome commit ..." "$out"
out="$(cd "$REPO" && PATH="$NOBIOME" bash "$CHECK" 2>&1)"
expect "missing biome: a person gets a notice and exit 0" "0|NOTICE: biome missing, so this check did not run. Install: $INSTALL_HINT" "$?|$out"
git -C "$REPO" config checks.skipmissing biome
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOBIOME" bash "$CHECK" 2>&1)"
expect "missing biome named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: biome (missing)" "$?|$out"
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOBIOME" bash "$CHECK" --worktree 2>&1)"
git -C "$REPO" config --unset checks.skipmissing
expect "missing biome, --worktree: silent" "0|" "$?|$out"
git -C "$REPO" reset -q
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOBIOME" bash "$CHECK" 2>&1)"
expect "missing biome with nothing of Biome's staged: an agent is not failed" "0|" "$?|$out"

# biome only in the repo's own node_modules/.bin, and only in a nested one.
new_repo
mkdir -p "$REPO/node_modules/.bin"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_BIOME" >"$REPO/node_modules/.bin/biome"
chmod +x "$REPO/node_modules/.bin/biome"
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOBIOME" bash "$CHECK" 2>&1)"
expect "biome found in the repo's node_modules/.bin when PATH has none" "0|a.ts" "$?|$out"

new_repo NONE
mkdir -p "$REPO/pkg/node_modules/.bin"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_BIOME" >"$REPO/pkg/node_modules/.bin/biome"
chmod +x "$REPO/pkg/node_modules/.bin/biome"
printf '{}\n' >"$REPO/pkg/biome.json"
printf 'export const a=1\n' >"$REPO/pkg/a.ts"
git -C "$REPO" add pkg/a.ts
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOBIOME" bash "$CHECK" 2>&1)"
expect "biome found in the governing config directory's node_modules/.bin" "0|pkg/a.ts" "$?|$out"

# End to end through the plugin's vendored installer and real commits.
new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"biome-check","status":"installed"}]' "$status"
stamp="$(sed -n 2p "$REPO/.git/hooks/biome-format/biome-check.sh")"
expect "the installed copy carries the stamp on line 2" yes \
  "$(grep -qE '^# biome-format biome-check sha256:[0-9a-f]{64}$' <<<"$stamp" && echo yes)"
printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
git -C "$REPO" commit -q -m format >/dev/null 2>&1
expect "git commit runs the entry and succeeds" "0" "$?"
expect "the commit holds the formatted bytes" "export const a = 1;" "$(git -C "$REPO" show HEAD:a.ts)"
expect "the work tree matches the commit" "" "$(git -C "$REPO" status --porcelain)"
printf 'export const a = 1;\nconst unusedVar = 1;\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
err="$(git -C "$REPO" commit -q -m finding 2>&1)"
expect "git commit fails on a finding on an added line" "1" "$?"
expect "the commit failure names the line" "a.ts:2: lint/correctness/noUnusedVariables: This variable unusedVar is unused." "$(printf '%s\n' "$err" | head -1)"
expect "verify reports ok after the install" "ok	biome-check" "$(node "$INSTALL" verify --repo "$REPO")"

echo "biome-check: $PASS passed, $FAIL failed"
((FAIL == 0))
