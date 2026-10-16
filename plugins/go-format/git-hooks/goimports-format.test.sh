#!/usr/bin/env bash
# Contract tests for the go-format pre-commit entry (git-hooks/goimports-format.sh):
# staged Go files are rewritten and re-staged, a partly staged one is refused
# untouched, a file goimports cannot parse blocks the commit naming its line, a
# generated file and an installed copy are left alone, --worktree parses without
# rewriting, a missing goimports follows the skip-key rule, and the plugin's own
# vendored installer wires the entry so `git commit` runs it.
# Expected values are goimports' documented behavior: it adds a missing import
# ("fmt" for a fmt.Println call), removes an unused one, groups the module's own
# imports after third-party ones under -local; the parse-error line is the line
# of the fixture's broken call, counted by hand.
# test-scope: plugins/go-format/git-hooks/entries.json plugins/go-format/lib/git-hooks/check-lib.sh plugins/go-format/lib/git-hooks/install.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/goimports-format.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
if ! command -v goimports >/dev/null 2>&1; then
  echo "SKIP: goimports not on PATH -- goimports-format tests skipped"
  exit 0
fi

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
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  printf 'package seed\n' >"$REPO/seed.go"
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

NEEDS_IMPORT=$'package main\n\nfunc main() {\n\tfmt.Println("hi")\n}\n'
WITH_IMPORT=$'package main\n\nimport "fmt"\n\nfunc main() {\n\tfmt.Println("hi")\n}'
BROKEN=$'package main\n\nfunc main() {\n\tfmt.Println("hi"\n}\n'
TAIL='go-format: goimports could not process the files above.'

new_repo
printf '%s' "$NEEDS_IMPORT" >"$REPO/a.go"
git -C "$REPO" add a.go
expect "a staged file missing an import is rewritten, listed on stdout, and exits 0" "0|a.go|" "$(check "$REPO")"
expect "the rewrite is in the work tree" "$WITH_IMPORT" "$(cat "$REPO/a.go")"
expect "the rewrite is re-staged: the index holds the new bytes" "$WITH_IMPORT" "$(git -C "$REPO" show :a.go)"
expect "re-staged: no unstaged change remains" "" "$(git -C "$REPO" diff --name-only)"

new_repo
printf 'package main\n\nimport "fmt"\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/a.go"
git -C "$REPO" add a.go
expect "an already formatted file passes with nothing printed" "0||" "$(check "$REPO")"

new_repo
printf 'package main\n\nimport (\n\t"fmt"\n\t"os"\n)\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/a.go"
git -C "$REPO" add a.go
check "$REPO" >/dev/null
staged_src="$(git -C "$REPO" show :a.go)"
expect "an unused import is removed at commit and the used one stays" "no yes" \
  "$([[ "$staged_src" == *'"os"'* ]] && echo yes || echo no) $([[ "$staged_src" == *'"fmt"'* ]] && echo yes || echo no)"

new_repo
printf '%s' "$NEEDS_IMPORT" >"$REPO/a.go"
git -C "$REPO" add a.go
printf '%s\n// unstaged\n' "$NEEDS_IMPORT" >"$REPO/a.go"
expect "a partly staged file is refused with the contract line" "1||a.go: partly staged; format it or stage it fully, then commit" "$(check "$REPO")"
expect "a refused file is left byte for byte" "$(printf '%s\n// unstaged' "$NEEDS_IMPORT")" "$(cat "$REPO/a.go")"
expect "a refused file's index entry is left byte for byte" "$(printf '%s' "$NEEDS_IMPORT")" "$(git -C "$REPO" show :a.go)"

new_repo
printf '%s' "$NEEDS_IMPORT" >"$REPO/a.go"
printf 'notes\n' >"$REPO/notes.md"
git -C "$REPO" add a.go notes.md
printf 'notes\nmore unstaged\n' >"$REPO/notes.md"
expect "a partly staged file that is not Go does not refuse the commit" "0|a.go|" "$(check "$REPO")"

new_repo
printf '%s' "$BROKEN" >"$REPO/bad.go"
printf '%s' "$NEEDS_IMPORT" >"$REPO/good.go"
git -C "$REPO" add bad.go good.go
expect "a file goimports cannot parse blocks, naming its line; the other file is still rewritten" "1|good.go|bad.go:4: missing ',' before newline in argument list
bad.go:5: expected operand, found '}'
$TAIL" "$(check "$REPO")"
expect "the unparseable file keeps its bytes" "$(printf '%s' "$BROKEN")" "$(cat "$REPO/bad.go")"
expect "the file that parsed is re-staged despite the failure" "$WITH_IMPORT" "$(git -C "$REPO" show :good.go)"

new_repo
mkdir -p "$REPO/pkg"
printf '// first\n%s' "$BROKEN" >"$REPO/pkg/old.go"
git -C "$REPO" add pkg/old.go
git -C "$REPO" commit -q -m old --no-verify
printf '// changed\n%s' "$BROKEN" >"$REPO/pkg/old.go"
git -C "$REPO" add pkg/old.go
expect "a file that does not parse blocks wherever the error sits, even off the added lines" "1||pkg/old.go:5: missing ',' before newline in argument list
pkg/old.go:6: expected operand, found '}'
$TAIL" "$(check "$REPO")"

new_repo
printf '// Code generated by protoc-gen-go. DO NOT EDIT.\n%s' "$NEEDS_IMPORT" >"$REPO/gen.go"
printf '// Copyright 2026 Example Corp.\n\n/*\nBlock header.\n*/\n\n// Code generated by "stringer -type Op"; DO NOT EDIT.\n%s' "$NEEDS_IMPORT" >"$REPO/gen2.go"
printf '\xEF\xBB\xBF// Code generated by x. DO NOT EDIT.\r\n%s' "$NEEDS_IMPORT" >"$REPO/gen3.go"
cp "$REPO/gen.go" "$WORK/gen.before"
cp "$REPO/gen2.go" "$WORK/gen2.before"
cp "$REPO/gen3.go" "$WORK/gen3.before"
git -C "$REPO" add gen.go gen2.go gen3.go
expect "files carrying the generated marker are skipped, even behind a header, a block comment, a BOM and CRLF" "0||" "$(check "$REPO")"
expect "a generated file keeps its bytes" "yes" "$(cmp -s "$REPO/gen.go" "$WORK/gen.before" && cmp -s "$REPO/gen2.go" "$WORK/gen2.before" && cmp -s "$REPO/gen3.go" "$WORK/gen3.before" && echo yes)"

new_repo
printf 'package main\n\n// Code generated by protoc-gen-go. DO NOT EDIT.\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/late.go"
git -C "$REPO" add late.go
expect "the marker after the package clause is not a generated file" "0|late.go|" "$(check "$REPO")"

new_repo
mkdir -p "$REPO/.githooks/go-format"
printf '%s' "$NEEDS_IMPORT" >"$REPO/.githooks/go-format/copy.go"
git -C "$REPO" add -f .githooks/go-format/copy.go
expect "an installed copy under .githooks/ is skipped" "0||" "$(check "$REPO")"

new_repo
printf 'x=1\n' >"$REPO/data.txt"
git -C "$REPO" add data.txt
expect "a staged file that is not Go is ignored" "0||" "$(check "$REPO")"

new_repo
printf 'module example.com/localtest\n\ngo 1.23\n' >"$REPO/go.mod"
mkdir -p "$REPO/internal/pkg"
printf 'package pkg\n\nfunc Hello() string { return "hi" }\n' >"$REPO/internal/pkg/pkg.go"
printf 'package main\n\nimport (\n\t"example.com/localtest/internal/pkg"\n\t"fmt"\n\t"github.com/pkg/errors"\n)\n\nfunc main() {\n\tfmt.Println(pkg.Hello())\n\t_ = errors.New("x")\n}\n' >"$REPO/main.go"
git -C "$REPO" add go.mod internal main.go
if command -v go >/dev/null 2>&1; then
  check "$REPO" >/dev/null
  grouped="$(cat "$REPO/main.go")"
  expect "the module's own imports get their own group after third-party ones (-local from go.mod)" yes \
    "$([[ "$grouped" == *$'"github.com/pkg/errors"\n\n\t"example.com/localtest/internal/pkg"'* ]] && echo yes)"
else
  echo "SKIP: no go binary on PATH -- -local grouping case skipped"
fi

new_repo
printf '%s' "$NEEDS_IMPORT" >"$REPO/a.go"
expect "--worktree: an untracked file is parsed and nothing is rewritten" "0||" "$(check "$REPO" --worktree)"
expect "--worktree: the file keeps its bytes" "$(printf '%s' "$NEEDS_IMPORT")" "$(cat "$REPO/a.go")"
printf '%s' "$BROKEN" >"$REPO/a.go"
expect "--worktree: an uncommitted file that does not parse blocks" "1||a.go:4: missing ',' before newline in argument list
a.go:5: expected operand, found '}'
$TAIL" "$(check "$REPO" --worktree)"
rm "$REPO/a.go"
expect "--worktree: no uncommitted change passes" "0||" "$(check "$REPO" --worktree)"

# A PATH with the tools the script runs, git and no goimports.
NOGI="$WORK/nogoimports"
mkdir -p "$NOGI"
for t in git bash sed awk cat mktemp rm dirname grep tr; do
  ln -s "$(command -v "$t")" "$NOGI/$t"
done
INSTALL_CMD='go install golang.org/x/tools/cmd/goimports@latest (needs a Go toolchain: https://go.dev/dl/)'
new_repo
printf '%s' "$NEEDS_IMPORT" >"$REPO/a.go"
git -C "$REPO" add a.go
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOGI" bash "$CHECK" 2>&1)"
expect "missing goimports: an agent fails with the install command" "1" "$?"
expect "missing goimports: the message names the tool and the skip key" \
  "FAIL: goimports missing. Install: $INSTALL_CMD
To skip only while goimports is missing: git -c checks.skipmissing=goimports commit ..." "$out"
out="$(cd "$REPO" && PATH="$NOGI" bash "$CHECK" 2>&1)"
expect "missing goimports: a person gets a notice and exit 0" "0|NOTICE: goimports missing, so this check did not run. Install: $INSTALL_CMD" "$?|$out"
git -C "$REPO" config checks.skipmissing goimports
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOGI" bash "$CHECK" 2>&1)"
expect "missing goimports named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: goimports (missing)" "$?|$out"
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOGI" bash "$CHECK" --worktree 2>&1)"
git -C "$REPO" config --unset checks.skipmissing
expect "missing goimports, --worktree: silent" "0|" "$?|$out"

# End to end through the plugin's vendored installer and real commits.
new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"goimports-format","status":"installed"}]' "$status"
expect "the installed copy carries the stamp on line 2" yes \
  "$(grep -qE '^# go-format goimports-format sha256:[0-9a-f]{64}$' <<<"$(sed -n 2p "$REPO/.git/hooks/go-format/goimports-format.sh")" && echo yes)"
printf '%s' "$NEEDS_IMPORT" >"$REPO/a.go"
git -C "$REPO" add a.go
git -C "$REPO" commit -q -m format >/dev/null 2>&1
expect "git commit runs the entry and succeeds" "0" "$?"
expect "the commit holds the rewritten bytes" "$WITH_IMPORT" "$(git -C "$REPO" show HEAD:a.go)"
expect "the work tree matches the commit" "" "$(git -C "$REPO" status --porcelain)"
printf '%s' "$BROKEN" >"$REPO/a.go"
git -C "$REPO" add a.go
err="$(git -C "$REPO" commit -q -m broken 2>&1)"
expect "git commit fails on a file that does not parse" "1" "$?"
expect "the commit failure names the line" "a.go:4: missing ',' before newline in argument list" "$(printf '%s\n' "$err" | head -1)"
expect "verify reports ok after the install" "ok	goimports-format" "$(node "$INSTALL" verify --repo "$REPO")"

echo "goimports-format: $PASS passed, $FAIL failed"
((FAIL == 0))
