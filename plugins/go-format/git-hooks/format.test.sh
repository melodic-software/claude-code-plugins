#!/usr/bin/env bash
# Contract tests for the go-format pre-commit format entry (git-hooks/format.sh):
# staged Go files are formatted and re-staged, only formatting and import
# ordering run (no import is added or removed), a partly staged file is refused
# untouched, a file goimports cannot parse blocks the commit naming its line, a
# generated file and an installed copy are left alone, --worktree parses without
# rewriting, a missing goimports follows the skip-key rule, a go record is never
# run, file names never reach a shell as text, and the plugin's own vendored
# installer wires the entry so `git commit` runs it.
# Expected values are goimports' documented -format-only behavior (`goimports -h`:
# "don't fix imports and only format ... imports are grouped into sections"):
# gofmt spacing, imports sorted, the module's own imports grouped after
# third-party ones under -local, an unused import kept and a missing one not
# added; the parse-error line is the line of the fixture's broken call, counted
# by hand.
# test-scope: plugins/go-format/git-hooks/entries.json plugins/go-format/git-hooks/adapters.sh
# test-scope: plugins/go-format/lib/git-hooks/check-lib.sh plugins/go-format/lib/git-hooks/install.mjs
# test-scope: plugins/go-format/lib/git-hooks/resolve-tool.sh plugins/go-format/.claude-plugin/plugin.json
# shellcheck disable=SC2016 # record commands are literal text
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/format.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
if ! command -v goimports >/dev/null 2>&1; then
  echo "SKIP: goimports not on PATH -- format entry tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# HOME moves so no user-global record (~/.claude/ecosystems) reaches a case. A
# version-manager shim reads HOME, so link the binaries it resolves to first.
mkdir -p "$WORK/tools"
for t in goimports go node; do
  real="$(mise which "$t" 2>/dev/null)" || real=""
  [[ -x "$real" ]] || real="$(command -v "$t" 2>/dev/null)" || continue
  ln -s "$real" "$WORK/tools/$t"
done
export PATH="$WORK/tools:$PATH"
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
  out="$(cd "$repo" && PATH="${BIN:+$BIN:}$PATH" bash "$CHECK" "$@" 2>"$WORK/stderr")"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$WORK/stderr")"
}

UNFORMATTED=$'package main\n\nimport (\n\t"os"\n\t"fmt"\n)\n\nfunc main() {  fmt.Println("hi", os.Args) }\n'
FORMATTED=$'package main\n\nimport (\n\t"fmt"\n\t"os"\n)\n\nfunc main() { fmt.Println("hi", os.Args) }'
BROKEN=$'package main\n\nfunc main() {\n\tfmt.Println("hi"\n}\n'
TAIL='go-format: goimports could not process the files above.'

new_repo
printf '%s' "$UNFORMATTED" >"$REPO/a.go"
git -C "$REPO" add a.go
expect "a staged unformatted file is rewritten, listed on stdout, and exits 0" "0|a.go|" "$(check "$REPO")"
expect "the rewrite is in the work tree: imports sorted, spacing gofmt'd" "$FORMATTED" "$(cat "$REPO/a.go")"
expect "the rewrite is re-staged: the index holds the new bytes" "$FORMATTED" "$(git -C "$REPO" show :a.go)"
expect "re-staged: no unstaged change remains" "" "$(git -C "$REPO" diff --name-only)"

new_repo
printf '%s\n' "$FORMATTED" >"$REPO/a.go"
git -C "$REPO" add a.go
expect "an already formatted file passes with nothing printed" "0||" "$(check "$REPO")"

# Format only: goimports' import fixing is a lint fix, so it never runs.
new_repo
printf 'package main\n\nimport (\n\t"os"\n\t"fmt"\n)\n\nfunc main() {  fmt.Println(strings.ToUpper("hi")) }\n' >"$REPO/a.go"
git -C "$REPO" add a.go
check "$REPO" >/dev/null
staged_src="$(git -C "$REPO" show :a.go)"
expect "format only: the unused import stays, the missing one is not added, and the file is formatted" \
  $'package main\n\nimport (\n\t"fmt"\n\t"os"\n)\n\nfunc main() { fmt.Println(strings.ToUpper("hi")) }' "$staged_src"

new_repo
printf '%s' "$UNFORMATTED" >"$REPO/a.go"
git -C "$REPO" add a.go
printf '%s\n// unstaged\n' "$UNFORMATTED" >"$REPO/a.go"
expect "a partly staged file is refused with the contract line" "1||a.go: partly staged; format it or stage it fully, then commit" "$(check "$REPO")"
expect "a refused file is left byte for byte" "$(printf '%s\n// unstaged' "$UNFORMATTED")" "$(cat "$REPO/a.go")"
expect "a refused file's index entry is left byte for byte" "$(printf '%s' "$UNFORMATTED")" "$(git -C "$REPO" show :a.go)"

new_repo
printf '%s' "$UNFORMATTED" >"$REPO/a.go"
printf 'notes\n' >"$REPO/notes.md"
git -C "$REPO" add a.go notes.md
printf 'notes\nmore unstaged\n' >"$REPO/notes.md"
expect "a partly staged file that is not Go does not refuse the commit" "0|a.go|" "$(check "$REPO")"

new_repo
printf '%s' "$BROKEN" >"$REPO/bad.go"
printf '%s' "$UNFORMATTED" >"$REPO/good.go"
git -C "$REPO" add bad.go good.go
expect "a file goimports cannot parse blocks, naming its line; the other file is still rewritten" "1|good.go|bad.go:4: missing ',' before newline in argument list
bad.go:5: expected operand, found '}'
$TAIL" "$(check "$REPO")"
expect "the unparsable file keeps its bytes" "$(printf '%s' "$BROKEN")" "$(cat "$REPO/bad.go")"
expect "the file that parsed is re-staged despite the failure" "$FORMATTED" "$(git -C "$REPO" show :good.go)"

new_repo
mkdir -p "$REPO/pkg"
printf '%s' "$BROKEN" >"$REPO/pkg/gone.go"
printf '%s' "$UNFORMATTED" >"$REPO/fine.go"
git -C "$REPO" add pkg/gone.go fine.go
rm -r "$REPO/pkg" "$REPO/fine.go"
expect "staged then deleted from the work tree: a staged file that does not parse still blocks" "1||pkg/gone.go:4: missing ',' before newline in argument list
pkg/gone.go:5: expected operand, found '}'
$TAIL" "$(check "$REPO")"
expect "staged then deleted: nothing is rewritten or recreated" "no no" \
  "$([[ -e "$REPO/pkg/gone.go" ]] && echo yes || echo no) $([[ -e "$REPO/fine.go" ]] && echo yes || echo no)"
expect "staged then deleted: the index keeps its bytes" "$(printf '%s' "$UNFORMATTED")" "$(git -C "$REPO" show :fine.go)"
git -C "$REPO" rm -q --cached pkg/gone.go
expect "staged then deleted: a file that parses passes with nothing printed" "0||" "$(check "$REPO")"
printf '// Code generated by x. DO NOT EDIT.\n%s' "$BROKEN" >"$REPO/gen.go"
ln -s missing.go "$REPO/link.go"
git -C "$REPO" add gen.go link.go
rm "$REPO/gen.go" "$REPO/link.go"
expect "staged then deleted: a generated file and a symlink are not checked" "0||" "$(check "$REPO")"

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
printf '// Code generated by protoc-gen-go. DO NOT EDIT.\n%s' "$UNFORMATTED" >"$REPO/gen.go"
printf '// Copyright 2026 Example Corp.\n\n/*\nBlock header.\n*/\n\n// Code generated by "stringer -type Op"; DO NOT EDIT.\n%s' "$UNFORMATTED" >"$REPO/gen2.go"
printf '\xEF\xBB\xBF// Code generated by x. DO NOT EDIT.\r\n%s' "$UNFORMATTED" >"$REPO/gen3.go"
cp "$REPO/gen.go" "$WORK/gen.before"
cp "$REPO/gen2.go" "$WORK/gen2.before"
cp "$REPO/gen3.go" "$WORK/gen3.before"
git -C "$REPO" add gen.go gen2.go gen3.go
expect "files carrying the generated marker are skipped, even behind a header, a block comment, a BOM and CRLF" "0||" "$(check "$REPO")"
expect "a generated file keeps its bytes" "yes" "$(cmp -s "$REPO/gen.go" "$WORK/gen.before" && cmp -s "$REPO/gen2.go" "$WORK/gen2.before" && cmp -s "$REPO/gen3.go" "$WORK/gen3.before" && echo yes)"

new_repo
printf 'package main\n\n// Code generated by protoc-gen-go. DO NOT EDIT.\nfunc main() {  fmt.Println("hi") }\n' >"$REPO/late.go"
git -C "$REPO" add late.go
expect "the marker after the package clause is not a generated file" "0|late.go|" "$(check "$REPO")"

new_repo
printf '/* License. */ package main\n\n// Code generated by protoc-gen-go. DO NOT EDIT.\nfunc main() {  fmt.Println("hi") }\n' >"$REPO/inline.go"
git -C "$REPO" add inline.go
expect "a package clause after a block comment on its line ends the header scan" "0|inline.go|" "$(check "$REPO")"

new_repo
mkdir -p "$REPO/.githooks/go-format"
printf '%s' "$UNFORMATTED" >"$REPO/.githooks/go-format/copy.go"
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
printf '%s' "$UNFORMATTED" >"$REPO/a.go"
expect "--worktree: an untracked file is parsed and nothing is rewritten" "0||" "$(check "$REPO" --worktree)"
expect "--worktree: the file keeps its bytes" "$(printf '%s' "$UNFORMATTED")" "$(cat "$REPO/a.go")"
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
printf '%s' "$UNFORMATTED" >"$REPO/a.go"
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
expect "missing goimports named in checks.skipmissing, --worktree: skipped with a line" "0|SKIPPED: goimports (missing)" "$?|$out"
git -C "$REPO" config --unset checks.skipmissing
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOGI" bash "$CHECK" --worktree 2>&1)"
expect "missing goimports, --worktree: an agent fails as at commit time" \
  "1|FAIL: goimports missing. Install: $INSTALL_CMD" "$?|${out%%$'\n'*}"

# A go record is never run at commit: goimports formats, and a record command
# that would log its call is never called.
BIN="$WORK/bin"
mkdir -p "$BIN"
printf '#!/bin/sh\necho called >>"%s"\n' "$WORK/stub.log" >"$BIN/stubfmt"
chmod +x "$BIN/stubfmt"
: >"$WORK/stub.log"
new_repo
mkdir -p "$REPO/.claude/ecosystems"
printf 'globs: ["**/*.go"]\nfix-cmd: "stubfmt <files>"\nlint-cmd: "stubfmt <files>"\n' >"$REPO/.claude/ecosystems/go.yaml"
git -C "$REPO" add .claude/ecosystems/go.yaml
git -C "$REPO" commit -q -m record --no-verify
name='$(touch marker).go'
printf '%s' "$UNFORMATTED" >"$REPO/$name"
git -C "$REPO" add -- "$name"
expect "with a go record, goimports formats and the record command never runs" "0|$name|" "$(check "$REPO")"
expect "the record command was not called" "" "$(cat "$WORK/stub.log")"
expect "the index holds goimports' bytes" "$FORMATTED" "$(git -C "$REPO" show ":$name")"
expect "a crafted file name reached goimports as data and ran nothing" "no" "$([[ -e "$REPO/marker" ]] && echo yes || echo no)"
expect "--resolve: goimports, ungated, and the go record is not run by hooks" \
  "go-format	format	adapter:goimports	goimports	yes	no config gate: formats every Go file; the go record is not run by hooks; /toolchain:lint and /toolchain:check run it" \
  "$(cd "$REPO" && bash "$CHECK" --resolve)"

# --resolve <path>: one row per file; a generated file resolves to nothing.
new_repo
printf '%s' "$UNFORMATTED" >"$REPO/a.go"
printf '// Code generated by x. DO NOT EDIT.\n%s' "$UNFORMATTED" >"$REPO/gen.go"
expect "--resolve <path>: one row per file, a generated file resolves to nothing" \
  "go-format	format	adapter:goimports	goimports	yes	no config gate: formats every Go file
go-format	format	none		n/a	generated file" \
  "$(cd "$REPO" && bash "$CHECK" --resolve a.go gen.go)"
expect "--resolve runs nothing: the file keeps its bytes" "$(printf '%s' "$UNFORMATTED")" "$(cat "$REPO/a.go")"

# A decline of the earlier goimports-format entry carries to format.
new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
git -C "$REPO" config checks.go-format.goimports-format.declined true
expect "a decline of the earlier goimports-format entry carries to format" "declined	format" \
  "$(node "$INSTALL" verify --repo "$REPO" | cut -f1,2)"

# End to end through the plugin's vendored installer and real commits.
new_repo
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs the one format entry" '[{"entry":"format","status":"installed"}]' "$status"
expect "the installed copy carries the stamp on line 2" yes \
  "$(grep -qE '^# go-format format sha256:[0-9a-f]{64}$' <<<"$(sed -n 2p "$REPO/.git/hooks/go-format/format.sh")" && echo yes)"
expect "the resolver and the adapter are installed beside the entry" "yes yes" \
  "$([[ -f "$REPO/.git/hooks/go-format/resolve-tool.sh" ]] && echo yes) $([[ -f "$REPO/.git/hooks/go-format/adapters.sh" ]] && echo yes)"
printf '%s' "$UNFORMATTED" >"$REPO/a.go"
git -C "$REPO" add a.go
git -C "$REPO" commit -q -m format >/dev/null 2>&1
expect "git commit runs the entry and succeeds" "0" "$?"
expect "the commit holds the rewritten bytes" "$FORMATTED" "$(git -C "$REPO" show HEAD:a.go)"
expect "the work tree matches the commit" "" "$(git -C "$REPO" status --porcelain)"
printf '%s' "$BROKEN" >"$REPO/a.go"
git -C "$REPO" add a.go
err="$(git -C "$REPO" commit -q -m broken 2>&1)"
expect "git commit fails on a file that does not parse" "1" "$?"
expect "the commit failure names the line" "a.go:4: missing ',' before newline in argument list" "$(printf '%s\n' "$err" | head -1)"
expect "verify reports ok after the install" "ok	format" "$(node "$INSTALL" verify --repo "$REPO")"

echo "format: $PASS passed, $FAIL failed"
((FAIL == 0))
