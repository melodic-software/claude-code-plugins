#!/usr/bin/env bash
# Contract tests for the javascript-format lint entry (git-hooks/lint.sh): the
# resolved lint command reports, never rewrites; a finding blocks only on a line
# the change adds; output becomes repo-relative "<path>:<line>: <message>"; a
# linter that fails without a parseable finding fails closed; --worktree checks
# uncommitted changes; a .claude/ecosystems/ record never runs.
# Expected values are Biome's documented output, pinned against Biome 2.6.7:
# `biome lint --reporter=concise` prints "<mark> <path>:<line>:<col>: <category>:
# <message>", an unused variable is lint/correctness/noUnusedVariables, and a
# config Biome cannot parse prints "<path>/biome.json:<line>:<col> parse" lines,
# which must not read as a finding.
# Set BIOME_TEST_BIN to a native Biome binary; else `biome` on PATH is used.
# test-scope: plugins/javascript-format/git-hooks/entries.json plugins/javascript-format/git-hooks/adapters.sh
# test-scope: plugins/javascript-format/lib/git-hooks/check-lib.sh plugins/javascript-format/lib/git-hooks/resolve-tool.sh
# shellcheck disable=SC2016 # record commands are literal text
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT BIOME_CONFIG_PATH

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/lint.sh"
REAL_BIOME="${BIOME_TEST_BIN:-$(command -v biome)}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REAL_HOME="$HOME"
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
record() { # <body>: commit .claude/ecosystems/typescript.yaml
  mkdir -p "$REPO/.claude/ecosystems"
  printf '%s\n' "$1" >"$REPO/.claude/ecosystems/typescript.yaml"
  git -C "$REPO" add .claude/ecosystems/typescript.yaml
  git -C "$REPO" commit -q -m record --no-verify
}

BIN="$WORK/bin"
mkdir -p "$BIN"
# A stand-in a record could name: one finding per file. No hook may call it.
cat >"$BIN/stublint" <<'EOF'
#!/bin/sh
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

HINT='javascript-format: fix the findings biome reported above.'
UNUSED='lint/correctness/noUnusedVariables: This variable unusedVar is unused.'

if [[ -z "$REAL_BIOME" ]]; then
  echo "SKIP: biome not on PATH and BIOME_TEST_BIN unset -- the Biome adapter tests skipped"
else
  printf '#!/bin/sh\nHOME="%s" exec "%s" "$@"\n' "$REAL_HOME" "$REAL_BIOME" >"$BIN/biome"
  chmod +x "$BIN/biome"

  new_repo
  printf 'export const seed = 1;\n\nconst unusedVar = 1;\n' >"$REPO/seed.ts"
  git -C "$REPO" add seed.ts
  expect "a finding on an added line blocks, naming that line without Biome's severity mark" "1||seed.ts:3: $UNUSED
$HINT" "$(check "$REPO")"

  new_repo
  for i in $(seq 1 24); do printf 'export let v%s = 1;\n' "$i"; done >"$REPO/seed.ts"
  git -C "$REPO" add seed.ts
  git -C "$REPO" commit -q -m many --no-verify
  printf 'const unusedVar = 1;\n' >>"$REPO/seed.ts"
  git -C "$REPO" add seed.ts
  expect "among 24 older findings, a finding on the added 25th line still blocks" "1||seed.ts:25: $UNUSED
$HINT" "$(check "$REPO")"

  new_repo
  mkdir -p "$REPO/pkg/sub"
  printf '{ "root": false, "extends": "//" }\n' >"$REPO/pkg/biome.json"
  printf '{}\n' >"$REPO/biome.json"
  printf 'const unusedVar = 1;\n' >"$REPO/pkg/sub/n.ts"
  git -C "$REPO" add pkg
  expect "a nested file's finding names its repo-relative path" "1||pkg/sub/n.ts:1: $UNUSED
$HINT" "$(check "$REPO")"

  new_repo NONE
  mkdir -p "$REPO/pkg/sub"
  printf '{}\n' >"$REPO/pkg/biome.json"
  printf 'const unusedVar = 1;\n' >"$REPO/pkg/sub/n.ts"
  git -C "$REPO" add pkg
  expect "a finding under a nested topmost config names its repo-relative path" "1||pkg/sub/n.ts:1: $UNUSED
$HINT" "$(check "$REPO")"

  new_repo
  printf 'let x=1\nimport { b } from "./b";\nimport { a } from "./a";\nexport { a, b, x };\n' >"$REPO/a.ts"
  git -C "$REPO" add a.ts
  check "$REPO" >/dev/null
  expect "lint rewrites nothing: no fix, no format, no import sort" "$(printf 'let x=1\nimport { b } from "./b";\nimport { a } from "./a";\nexport { a, b, x };')" "$(cat "$REPO/a.ts")"
  expect "lint stages nothing new" "let x=1" "$(git -C "$REPO" show :a.ts | head -1)"

  new_repo
  printf 'export const a = 1;\n' >"$REPO/a.ts"
  git -C "$REPO" add a.ts
  printf 'export const a = 1;\nexport const b = 2;\n' >"$REPO/a.ts"
  expect "a partly staged file is refused: lint reads the work tree" "1||a.ts: partly staged; lint checks the work tree, so stage it fully, then commit" "$(check "$REPO")"

  new_repo
  printf 'export const a = 1;\n' >"$REPO/a.ts"
  git -C "$REPO" add a.ts
  printf '{ "linter": { "enabled": false } }\n' >"$REPO/biome.json"
  expect "a Biome config edited after staging refuses the commit" "1||biome.json: config differs between the index and the work tree; stage it or restore it, then commit" "$(check "$REPO")"

  new_repo '{ "files": { "includes": ["**", "!**/gen/**"] } }'
  mkdir -p "$REPO/pkg/sub"
  printf '{ "root": false, "extends": "//" }\n' >"$REPO/pkg/biome.json"
  printf 'export const a=1\nconst unusedVar = 1;\n' >"$REPO/pkg/sub/gone.ts"
  git -C "$REPO" add pkg/biome.json pkg/sub/gone.ts
  rm -r "$REPO/pkg/sub"
  expect "staged then deleted from the work tree: the staged finding still blocks" "1||pkg/sub/gone.ts:2: $UNUSED
$HINT" "$(check "$REPO")"
  expect "staged then deleted: the file is not recreated" "no" "$([[ -e "$REPO/pkg/sub/gone.ts" ]] && echo yes || echo no)"
  git -C "$REPO" rm -q --cached pkg/sub/gone.ts
  mkdir -p "$REPO/gen"
  printf 'const unusedVar = 1;\n' >"$REPO/gen/g.ts"
  git -C "$REPO" add gen/g.ts
  rm -r "$REPO/gen"
  expect "staged then deleted: the config's includes still hold" "0||" "$(check "$REPO")"
  git -C "$REPO" rm -q --cached gen/g.ts
  printf '{ "vcs": { "enabled": true, "clientKind": "git", "useIgnoreFile": true } }\n' >"$REPO/biome.json"
  printf 'vendor/\n' >"$REPO/.gitignore"
  git -C "$REPO" add biome.json .gitignore
  mkdir -p "$REPO/vendor"
  printf 'const unusedVar = 1;\n' >"$REPO/vendor/v.ts"
  printf 'const unusedVar = 1;\n' >"$REPO/kept.ts"
  git -C "$REPO" add -f vendor/v.ts
  git -C "$REPO" add kept.ts
  rm -r "$REPO/vendor" "$REPO/kept.ts"
  expect "staged then deleted: with vcs.useIgnoreFile the .gitignore holds and the rest is checked" "1||kept.ts:1: $UNUSED
$HINT" "$(check "$REPO")"
  git -C "$REPO" rm -q --cached vendor/v.ts kept.ts
  ln -s missing.ts "$REPO/link.ts"
  git -C "$REPO" add link.ts
  rm "$REPO/link.ts"
  expect "staged then deleted: a staged symlink is not checked" "0||" "$(check "$REPO")"

  new_repo
  printf 'const unusedVar = 1;\n' >"$REPO/seed.ts"
  git -C "$REPO" add seed.ts
  git -C "$REPO" commit -q -m old --no-verify
  printf 'const unusedVar = 1;\n\nexport const ok = 2;\n' >"$REPO/seed.ts"
  git -C "$REPO" add seed.ts
  expect "a finding on a line the commit did not add does not block" "0||" "$(check "$REPO")"

  new_repo
  printf 'const = ;\n' >"$REPO/seed.ts"
  git -C "$REPO" add seed.ts
  out="$(check "$REPO")"
  expect "a file that does not parse blocks the commit" "1" "${out%%|*}"
  first="${out#1||}"
  expect "the parse error names its line" "seed.ts:1: parse: Expected an identifier, an array pattern, or an object pattern but instead found '='." "${first%%$'\n'*}"

  new_repo '{ not json'
  printf 'export const a = 1;\n' >"$REPO/a.ts"
  git -C "$REPO" add a.ts
  out="$(check "$REPO")"
  expect "a config Biome cannot read fails closed: its parse lines are not findings" "1" "${out%%|*}"
  first="${out#1||}"
  expect "the failure says the linter reported no finding" "javascript-format: biome exited 1 and reported no <path>:<line> finding, so the change was not checked:" "${first%%$'\n'*}"

  new_repo
  printf 'export const a=1\nconst unusedVar = 1;\n' >"$REPO/a.ts"
  expect "--worktree: an uncommitted finding blocks and nothing is rewritten" "1||a.ts:2: $UNUSED
$HINT" "$(check "$REPO" --worktree)"
  expect "--worktree: the file keeps its bytes" "$(printf 'export const a=1\nconst unusedVar = 1;')" "$(cat "$REPO/a.ts")"
  printf 'const unusedVar = 1;\n' >"$REPO/a.ts"
  expect "--worktree: an untracked file is checked whole" "1||a.ts:1: $UNUSED
$HINT" "$(check "$REPO" --worktree)"
  printf 'export const a=1\n' >"$REPO/a.ts"
  expect "--worktree: a layout difference alone is not a finding" "0||" "$(check "$REPO" --worktree)"
  rm "$REPO/a.ts"
  expect "--worktree: no uncommitted change passes" "0||" "$(check "$REPO" --worktree)"

  new_repo NONE
  printf 'const unusedVar = 1;\n' >"$REPO/a.ts"
  git -C "$REPO" add a.ts
  expect "no Biome config and no record: nothing runs and the entry passes" "0||" "$(check "$REPO")"

  new_repo
  record 'globs: ["*.ts"]
lint-cmd: "stublint <files>"'
  printf 'export const a = 1;\nexport const b = 2;\n' >"$REPO/a.ts"
  git -C "$REPO" add a.ts
  expect "with a record and a Biome config, Biome lints and the record's linter never runs" "0||" "$(check "$REPO")"
fi

# The lint-output contract holds on the adapter path with a stand-in biome: a
# linter that fails with no finding fails closed.
new_repo
CRASH="$WORK/crash"
mkdir -p "$CRASH"
printf '#!/bin/sh\necho "biome: config error" >&2\nexit 2\n' >"$CRASH/biome"
chmod +x "$CRASH/biome"
printf 'export const a = 1;\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
out="$(cd "$REPO" && PATH="$CRASH:$PATH" bash "$CHECK" 2>&1)"
expect "the adapter's linter exiting non-zero with no parseable finding fails closed, showing its output" "1|javascript-format: biome exited 2 and reported no <path>:<line> finding, so the change was not checked:
biome: biome: config error" "$?|$out"

new_repo NONE
record 'globs: ["*.ts"]
lint-cmd: "stublint <files>"'
printf 'export const a = 1;\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
expect "a record with no Biome config runs nothing at commit" "0||" "$(check "$REPO")"

echo "lint: $PASS passed, $FAIL failed"
((FAIL == 0))
