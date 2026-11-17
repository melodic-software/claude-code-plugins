#!/usr/bin/env bash
# Contract tests for lib/git-hooks/resolve-tool.sh: the order a concern
# resolves in (the bound record, then the plugin's adapter, then nothing), the
# record layers, the approval rule for repository-sourced records, how files
# reach a command, and how lint output becomes repo-relative findings.
# test-scope: lib/git-hooks/resolve-tool.sh lib/yaml-subset.awk
# shellcheck disable=SC2016 # record commands and expected scripts are literal text
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RT="$HERE/resolve-tool.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1
export HOME="$WORK/home"
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

# A stand-in tool: appends one line per argument it receives to its log, and
# rewrites each file it is handed to the word "formatted".
BIN="$WORK/bin"
mkdir -p "$BIN"
cat >"$BIN/stubfmt" <<EOF
#!/bin/sh
for a in "\$@"; do
  printf '%s\n' "\$a" >>"$WORK/stub.log"
  case "\$a" in -*) ;; *) printf 'formatted\n' >"\$a" ;; esac
done
EOF
chmod +x "$BIN/stubfmt"
PATH="$BIN:$PATH"

# The plugin side of the resolver: one id, one adapter gated on demo.cfg.
RT_PLUGIN=demo
RT_IDS=demo
# shellcheck disable=SC2329  # called by name from the resolver
rt_adapter() { # <concern> <file> <root>
  [[ -f "$3/demo.cfg" ]] || return 1
  RT_ADAPTER=demofmt
  RT_TOOL=stubfmt
  RT_BIN=stubfmt
  RT_DIR="$3"
  RT_INSTALL="install stubfmt"
  case "$1" in
  format) RT_SCRIPT='stubfmt --adapter "$@"' ;;
  *) RT_SCRIPT='stubfmt --adapter-lint "$@"' ;;
  esac
}
# shellcheck disable=SC2329  # called by name from the resolver
rt_adapter_in_repo() { # <concern> <root>
  [[ -f "$2/demo.cfg" ]] || return 1
  RT_ADAPTER=demofmt
  RT_TOOL=stubfmt
  RT_BIN=stubfmt
}
# shellcheck source=resolve-tool.sh
. "$RT"

n=0
new_repo() { # a repo with one commit on main and origin/HEAD at it
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  mkdir -p "$REPO/.claude/ecosystems"
  printf 'seed\n' >"$REPO/seed.dm"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m seed --no-verify
  publish
}
publish() { # make the current HEAD the default branch's tip
  git -C "$REPO" update-ref refs/remotes/origin/main HEAD
  git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
record() { # <body> [file]: write and commit a record
  printf '%s\n' "$1" >"$REPO/.claude/ecosystems/${2:-demo.yaml}"
  git -C "$REPO" add -f ".claude/ecosystems/${2:-demo.yaml}"
  git -C "$REPO" commit -q -m record --no-verify
}
resolve() { # <file> <concern> -> "<source>|<script>"
  rt_forget
  rt_resolve "$1" "$2" "$REPO"
  printf '%s|%s' "$RT_SOURCE" "$RT_SCRIPT"
}

FIX='globs: ["*.dm"]
fix-cmd: "stubfmt --record <files>"
lint-cmd: "stubfmt --lint <files>"'

new_repo
record "$FIX"
publish
: >"$REPO/demo.cfg"
expect "a record matching the default branch wins over the adapter" 'record:demo|stubfmt --record "$@"' "$(resolve seed.dm format)"
expect "lint resolves lint-cmd from the same record" 'record:demo|stubfmt --lint "$@"' "$(resolve seed.dm lint)"
rt_resolve "$REPO/seed.dm" format "$REPO"
expect "an absolute path resolves the same" "record:demo" "$RT_SOURCE"
expect "the tool key is the first word's basename" "stubfmt" "$RT_TOOL"

new_repo
: >"$REPO/demo.cfg"
expect "no record: the adapter" 'adapter:demofmt|stubfmt --adapter "$@"' "$(resolve seed.dm format)"
rm "$REPO/demo.cfg"
expect "no record and no adapter config: nothing" "none|" "$(resolve seed.dm format)"

new_repo
record 'globs: ["*.dm"]
fix-cmd: "stubfmt --record <files>"'
publish
: >"$REPO/demo.cfg"
expect "a record with no lint-cmd leaves lint to the adapter" 'adapter:demofmt|stubfmt --adapter-lint "$@"' "$(resolve seed.dm lint)"

new_repo
record 'globs: ["*.dm"]
fix-cmd: "stubfmt --record ."'
publish
: >"$REPO/demo.cfg"
expect "a record command with no <files> is not a hook opt-in: the adapter runs" 'adapter:demofmt|stubfmt --adapter "$@"' "$(resolve seed.dm format)"
rt_forget
rt_resolve seed.dm format "$REPO"
expect "the whole-tree record key is named as the reason" "whole-tree:demo" "$RT_REASON"

new_repo
record 'globs: ["*.other"]
fix-cmd: "stubfmt --record <files>"'
publish
expect "a record whose globs do not match the file does not bind it" "none|" "$(resolve seed.dm format)"

new_repo
record 'enabled: false
globs: ["*.dm"]
fix-cmd: "stubfmt --record <files>"'
publish
: >"$REPO/demo.cfg"
expect "enabled: false turns the concern off, the adapter included" "none|" "$(resolve seed.dm format)"

# Approval: a repository-sourced record runs only when it, and every tracked
# file its command names, matches the default branch, or a per-clone approval
# covers exactly its current bytes.
new_repo
: >"$REPO/demo.cfg"
record "$FIX"
expect "a record committed on a branch and not on the default branch is unapproved" "unapproved|" "$(resolve seed.dm format)"
rt_forget
rt_resolve seed.dm format "$REPO"
expect "an unapproved record does not fall through to the adapter" "unapproved" "$RT_SOURCE"
bash "$RT" --approve demo "$REPO" >/dev/null
expect "after --approve the record runs" 'record:demo|stubfmt --record "$@"' "$(resolve seed.dm format)"
printf '%s\n' 'globs: ["*.dm"]
fix-cmd: "stubfmt --other <files>"' >"$REPO/.claude/ecosystems/demo.yaml"
expect "an approved record edited afterwards is unapproved again" "unapproved|" "$(resolve seed.dm format)"

new_repo
mkdir -p "$REPO/scripts"
printf '#!/bin/sh\nexec stubfmt "$@"\n' >"$REPO/scripts/fmt.sh"
chmod +x "$REPO/scripts/fmt.sh"
git -C "$REPO" add scripts/fmt.sh
record 'globs: ["*.dm"]
fix-cmd: "$REPO_ROOT/scripts/fmt.sh <files>"'
publish
expect "a record and its referenced script matching the default branch run" 'record:demo|$REPO_ROOT/scripts/fmt.sh "$@"' "$(resolve seed.dm format)"
rt_forget
rt_resolve seed.dm format "$REPO"
expect "a path-like first word gives its basename as the tool key" "fmt.sh" "$RT_TOOL"
printf '#!/bin/sh\ntouch "%s/pwned"\n' "$WORK" >"$REPO/scripts/fmt.sh"
expect "a referenced script edited locally makes the record unapproved" "unapproved|" "$(resolve seed.dm format)"
git -C "$REPO" commit -qam evil --no-verify
expect "a referenced script committed on a branch makes the record unapproved" "unapproved|" "$(resolve seed.dm format)"

new_repo
record 'globs: ["*.dm"]
fix-cmd: "stubfmt --config=cfg/fmt.toml <files>"'
publish
mkdir -p "$REPO/cfg"
printf 'x\n' >"$REPO/cfg/fmt.toml"
expect "an untracked file a command names is the user's own and does not unapprove" "record:demo" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"
git -C "$REPO" add cfg/fmt.toml
expect "a --opt=<file> operand git tracks but the default branch lacks unapproves" "unapproved" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"

# Every spelling of a referenced file is compared in git's canonical form,
# resolved against the directory the command runs in.
for spelling in './scripts/fmt.sh' 'scripts//fmt.sh' 'scripts/./fmt.sh'; do
  new_repo
  mkdir -p "$REPO/scripts"
  printf '#!/bin/sh\nexec stubfmt "$@"\n' >"$REPO/scripts/fmt.sh"
  chmod +x "$REPO/scripts/fmt.sh"
  git -C "$REPO" add scripts/fmt.sh
  record 'globs: ["*.dm"]
fix-cmd: "'"$spelling"' <files>"'
  publish
  expect "$spelling: a record matching the default branch runs" "record:demo" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"
  printf '#!/bin/sh\ntouch pwned\n' >"$REPO/scripts/fmt.sh"
  git -C "$REPO" commit -qam evil --no-verify
  expect "$spelling: a branch edit of the referenced script makes the record unapproved" "unapproved" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"
done

new_repo
mkdir -p "$REPO/pkg/tools" "$REPO/tools"
printf 'x\n' >"$REPO/pkg/proj.cfg"
printf 'seed\n' >"$REPO/pkg/a.dm"
printf '#!/bin/sh\nexec stubfmt "$@"\n' >"$REPO/pkg/tools/fmt.sh"
printf '#!/bin/sh\nexec stubfmt "$@"\n' >"$REPO/tools/fmt.sh"
chmod +x "$REPO/pkg/tools/fmt.sh" "$REPO/tools/fmt.sh"
git -C "$REPO" add pkg tools
record 'globs: ["*.dm"]
project-discovery: ["proj.cfg"]
fix-cmd: "tools/fmt.sh <files>"
lint-cmd: "<project-dir>/tools/fmt.sh <files>"'
publish
expect "a command run from a project directory names files relative to it, accepted when they match" "record:demo" "$(resolve pkg/a.dm format >/dev/null; printf '%s' "$RT_SOURCE")"
printf '#!/bin/sh\ntouch pwned\n' >"$REPO/pkg/tools/fmt.sh"
git -C "$REPO" commit -qam evil --no-verify
expect "a branch edit of the project-relative script makes the record unapproved" "unapproved" "$(resolve pkg/a.dm format >/dev/null; printf '%s' "$RT_SOURCE")"
expect "a branch edit of a <project-dir> reference makes the record unapproved" "unapproved" "$(resolve pkg/a.dm lint >/dev/null; printf '%s' "$RT_SOURCE")"
expect "a root file's run directory holds the project directory's changed script, so it is unapproved too" "unapproved" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"

# An indirect command runs code from files it does not name, so every tracked
# file under the run directory that the record's globs do not bind must match
# the default branch too.
new_repo
printf '{"scripts":{"fmt":"stubfmt"}}\n' >"$REPO/package.json"
printf 'fmt:\n\tstubfmt\n' >"$REPO/Makefile"
printf 'notes\n' >"$REPO/notes.txt"
git -C "$REPO" add package.json Makefile notes.txt
record 'globs: ["*.dm"]
fix-cmd: "npm run fmt <files>"
lint-cmd: "make fmt <files>"'
publish
expect "an indirect command whose run directory matches the default branch is accepted" "record:demo" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"
printf 'changed source\n' >"$REPO/seed.dm"
printf 'new source\n' >"$REPO/other.dm"
git -C "$REPO" add seed.dm other.dm
git -C "$REPO" commit -qm "source edits" --no-verify
expect "editing only files the record's globs bind leaves it accepted" "record:demo|record:demo" "$(resolve seed.dm format >/dev/null; printf '%s|' "$RT_SOURCE"; resolve seed.dm lint >/dev/null; printf '%s' "$RT_SOURCE")"
printf '{"scripts":{"fmt":"touch pwned"}}\n' >"$REPO/package.json"
git -C "$REPO" commit -qam "edit the manifest" --no-verify
expect "a package-manager command with its manifest edited on the branch is unapproved" "unapproved" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"
bash "$RT" --approve demo "$REPO" >/dev/null
expect "--approve accepts it" "record:demo" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"
printf 'fmt:\n\ttouch pwned\n' >"$REPO/Makefile"
expect "a make-target command with its Makefile edited is unapproved, the approval included" "unapproved|unapproved" "$(resolve seed.dm format >/dev/null; printf '%s|' "$RT_SOURCE"; resolve seed.dm lint >/dev/null; printf '%s' "$RT_SOURCE")"
git -C "$REPO" checkout -q -- Makefile
expect "with the Makefile restored the approval holds again" "record:demo" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"
git -C "$REPO" rm -q notes.txt
expect "deleting a file the record's globs do not bind unapproves it" "unapproved" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"

# --approve and the repository-level report key each run directory the
# record's globs and project-discovery produce, as the hooks do.
new_repo
mkdir -p "$REPO/pkg/tools" "$REPO/tools"
printf 'x\n' >"$REPO/pkg/proj.cfg"
printf 'seed\n' >"$REPO/pkg/a.dm"
printf '#!/bin/sh\nexec stubfmt "$@"\n' >"$REPO/pkg/tools/fmt.sh"
printf '#!/bin/sh\nexec stubfmt "$@"\n' >"$REPO/tools/fmt.sh"
chmod +x "$REPO/pkg/tools/fmt.sh" "$REPO/tools/fmt.sh"
git -C "$REPO" add pkg tools
record 'globs: ["*.dm"]
project-discovery: ["proj.cfg"]
fix-cmd: "tools/fmt.sh <files>"'
expect "a branch record with project-discovery is unapproved in the project directory" "unapproved" "$(resolve pkg/a.dm format >/dev/null; printf '%s' "$RT_SOURCE")"
rt_forget
expect "the repository-level report says unapproved before approval" "unapproved" "$(rt_print format "$REPO" | cut -f5)"
bash "$RT" --approve demo "$REPO" >/dev/null
expect "--approve covers the project directory's key" "record:demo" "$(resolve pkg/a.dm format >/dev/null; printf '%s' "$RT_SOURCE")"
expect "--approve covers the root's key" "record:demo" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"
rt_forget
expect "the repository-level report reads approved for every run directory" "approved" "$(rt_print format "$REPO" | cut -f5)"
printf '#!/bin/sh\ntouch pwned\n' >"$REPO/tools/fmt.sh"
rt_forget
expect "a change outside the project directory makes the report unapproved and names each directory" "unapproved	pkg: approved; .: unapproved" "$(rt_print format "$REPO" | cut -f5,7)"

# A referenced file counts as the user's own only when git lists it as
# untracked or ignored and no part of its path is a symlink.
new_repo
mkdir -p "$REPO/real"
printf '#!/bin/sh\nexec stubfmt "$@"\n' >"$REPO/real/fmt.sh"
chmod +x "$REPO/real/fmt.sh"
ln -s real "$REPO/link"
git -C "$REPO" add real link
record 'globs: ["*.dm"]
fix-cmd: "link/fmt.sh <files>"'
publish
expect "a script under a tracked symlinked directory needs approval" "unapproved" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"

SUB="$WORK/subsrc$n"
git init -q -b main "$SUB"
printf '#!/bin/sh\nexec stubfmt "$@"\n' >"$SUB/fmt.sh"
chmod +x "$SUB/fmt.sh"
git -C "$SUB" add fmt.sh
git -C "$SUB" -c user.name=t -c user.email=t@example.invalid commit -qm sub --no-verify
new_repo
git -C "$REPO" -c protocol.file.allow=always submodule add -q "$SUB" sub
git -C "$REPO" commit -qm submodule --no-verify
record 'globs: ["*.dm"]
fix-cmd: "sub/fmt.sh <files>"'
publish
printf '#!/bin/sh\ntouch pwned\n' >"$REPO/sub/fmt.sh"
git -C "$REPO/sub" -c user.name=t -c user.email=t@example.invalid commit -qam evil --no-verify
git -C "$REPO" commit -qam "move the gitlink" --no-verify
expect "a script inside a submodule whose gitlink moved on the branch needs approval" "unapproved" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"

new_repo
mkdir -p "$REPO/.tools"
printf '.tools/\n' >"$REPO/.gitignore"
git -C "$REPO" add .gitignore
printf '#!/bin/sh\nexec stubfmt "$@"\n' >"$REPO/.tools/fmt.sh"
printf '#!/bin/sh\nexit 0\n' >"$REPO/mine.sh"
record 'globs: ["*.dm"]
fix-cmd: ".tools/fmt.sh <files>"
lint-cmd: "./mine.sh <files>"'
publish
expect "an ignored user install the command names is the user's own" "record:demo" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"
expect "an untracked user file the command names is the user's own" "record:demo" "$(resolve seed.dm lint >/dev/null; printf '%s' "$RT_SOURCE")"

new_repo
printf '#!/bin/sh\nexit 0\n' >"$WORK/outside-$n.sh"
record 'globs: ["*.dm"]
fix-cmd: "../outside-'"$n"'.sh <files>"'
publish
expect "a referenced path that escapes the repository needs approval, even on the default branch" "unapproved" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"

# Globs: * stays within one directory and **/ spans any number of them.
new_repo
mkdir -p "$REPO/pkg/tests/unit" "$REPO/tests" "$REPO/src/n"
record 'globs: ["**/tests/**/*.dm", "src/*.dm"]
fix-cmd: "stubfmt <files>"'
publish
for f in pkg/tests/unit/x.dm tests/x.dm src/a.dm; do
  expect "glob binds $f" "record:demo" "$(resolve "$f" format >/dev/null; printf '%s' "$RT_SOURCE")"
done
for f in pkg/x.dm src/n/a.dm; do
  expect "glob does not bind $f" "none" "$(resolve "$f" format >/dev/null; printf '%s' "$RT_SOURCE")"
done

# Leading assignments are not the executable.
new_repo
record 'globs: ["*.dm"]
fix-cmd: "FOO=1 BAR=x stubfmt <files>"'
publish
rt_forget
rt_resolve seed.dm format "$REPO"
expect "leading VAR=value words are skipped: the executable is the next word" "stubfmt|stubfmt" "$RT_BIN|$RT_TOOL"

# <project-dir> expands to the directory the command runs in; a placeholder
# the hooks cannot expand refuses the record rather than running it literally.
new_repo
mkdir -p "$REPO/pkg"
printf 'x\n' >"$REPO/pkg/proj.cfg"
printf 'seed\n' >"$REPO/pkg/a.dm"
git -C "$REPO" add pkg
record 'globs: ["*.dm"]
project-discovery: ["proj.cfg"]
fix-cmd: "stubfmt --dir=<project-dir> <files>"'
publish
rt_forget
rt_resolve pkg/a.dm format "$REPO"
: >"$WORK/stub.log"
(cd "$REPO" && rt_run pkg/a.dm)
expect "<project-dir> reaches the command as the project directory" "--dir=$REPO/pkg
a.dm" "$(cat "$WORK/stub.log")"
new_repo
record 'globs: ["*.dm"]
fix-cmd: "stubfmt <solution-or-project-file> <files>"'
publish
expect "<solution-or-project-file> refuses the record" "parse-error" "$(resolve seed.dm format >/dev/null; printf '%s' "$RT_SOURCE")"

new_repo
git -C "$REPO" update-ref -d refs/remotes/origin/HEAD
git -C "$REPO" update-ref -d refs/remotes/origin/main
record "$FIX"
expect "no default branch resolves: a committed record is unapproved" "unapproved|" "$(resolve seed.dm format)"

# Layers: user-global, then the team file, then .local, key by key.
new_repo
printf '%s\n' 'fix-cmd: "stubfmt --local <files>"' >"$REPO/.claude/ecosystems/demo.local.yaml"
expect "an untracked .local layer alone binds globs from no layer, so nothing" "none|" "$(resolve seed.dm format)"
record "$FIX"
publish
expect ".local overrides the team key, and the user's own file needs no approval" 'record:demo|stubfmt --local "$@"' "$(resolve seed.dm format)"
expect "the key .local does not set comes from the team file" 'record:demo|stubfmt --lint "$@"' "$(resolve seed.dm lint)"
git -C "$REPO" add -f .claude/ecosystems/demo.local.yaml
expect "a .local file git tracks is repository content and needs approval" "unapproved|" "$(resolve seed.dm format)"

new_repo
mkdir -p "$HOME/.claude/ecosystems"
printf '%s\n' "$FIX" >"$HOME/.claude/ecosystems/demo.yaml"
git -C "$REPO" update-ref -d refs/remotes/origin/HEAD
expect "a user-global record needs no approval" 'record:demo|stubfmt --record "$@"' "$(resolve seed.dm format)"
rm -r "$HOME/.claude"

new_repo
printf '%s\n' 'globs: ["*.dm"]' 'fix-cmd: |' '  stubfmt <files>' >"$REPO/.claude/ecosystems/demo.yaml"
: >"$REPO/demo.cfg"
expect "a block scalar is a parse error, never a silent fallback" "parse-error|" "$(resolve seed.dm format)"
rt_forget
rt_resolve seed.dm format "$REPO"
expect "the parse error names the file and line" "1" "$(grep -c 'demo.yaml line 2' <<<"$RT_REASON")"

# Running: files reach the command as arguments, never as command text.
new_repo
record "$FIX"
publish
name='$(touch marker);x.dm'
printf 'seed\n' >"$REPO/$name"
printf 'seed\n' >"$REPO/-lead.dm"
rt_resolve "$REPO/seed.dm" format "$REPO"
: >"$WORK/stub.log"
(cd "$REPO" && rt_run "$name" -lead.dm)
expect "a file name holding \$( and ; is never executed" "no" "$([[ -e "$REPO/marker" || -e "$WORK/marker" ]] && echo yes || echo no)"
expect "the tool receives the literal name, and a leading dash as ./" "--record
$name
./-lead.dm" "$(cat "$WORK/stub.log")"
expect "the tool ran on the crafted file" "formatted" "$(cat "$REPO/$name")"

new_repo
mkdir -p "$REPO/scripts"
printf '#!/bin/sh\nprintf "%%s\\n" "$REPO_ROOT" >"%s/root.log"\n' "$WORK" >"$REPO/scripts/env.sh"
chmod +x "$REPO/scripts/env.sh"
git -C "$REPO" add scripts/env.sh
record 'globs: ["*.dm"]
fix-cmd: "$REPO_ROOT/scripts/env.sh <files>"'
publish
rt_forget
rt_resolve seed.dm format "$REPO"
(cd "$REPO" && rt_run seed.dm)
expect "REPO_ROOT is set for the command" "$REPO" "$(cat "$WORK/root.log")"

# rt_print reads records and executes nothing.
new_repo
record 'globs: ["*.dm"]
fix-cmd: "touch '"$WORK"'/print-marker <files>"'
publish
expect "rt_print reports the record and its approval" "demo	format	record:demo	touch	accepted	yes	" "$(rt_print format "$REPO")"
expect "rt_print ran no record command" "no" "$([[ -e "$WORK/print-marker" ]] && echo yes || echo no)"
: >"$REPO/demo.cfg"
expect "rt_print falls to the adapter for a concern the record leaves out" "demo	lint	adapter:demofmt	stubfmt	n/a	yes	" "$(rt_print lint "$REPO")"
record 'enabled: false
globs: ["*.dm"]
fix-cmd: "stubfmt <files>"'
publish
rt_forget
expect "rt_print reports a disabled record as none, not its tool" "demo	format	none		n/a	n/a	disabled:demo" "$(rt_print format "$REPO")"
git -C "$REPO" rm -q .claude/ecosystems/demo.yaml
git -C "$REPO" commit -qm unrecord --no-verify
rt_forget
rm "$REPO/demo.cfg"
expect "rt_print says none when nothing resolves" "demo	lint	none		n/a	n/a	" "$(rt_print lint "$REPO")"

# Lint output becomes repo-relative "<path>:<line>: <message>".
cat >"$BIN/stublint" <<EOF
#!/bin/sh
case "\$1" in
--abs) printf '%s/sub/a.dm:3:7: E1 bad\n' "$WORK/rl" ;;
--rel) printf 'a.dm:4: W2 meh\nsummary line\n' ;;
--crash) echo 'tool crashed' >&2; exit 2 ;;
--clean) exit 0 ;;
esac
exit 1
EOF
chmod +x "$BIN/stublint"
mkdir -p "$WORK/rl/sub"
RT_SCRIPT='stublint --abs "$@"' RT_DIR="$WORK/rl" RT_ROOT="$WORK/rl"
expect "an absolute path is made repo-relative and the column dropped" "sub/a.dm:3: E1 bad" "$(cd "$WORK/rl" && rt_lint sub/a.dm 2>/dev/null)"
RT_SCRIPT='stublint --rel "$@"' RT_DIR="$WORK/rl/sub"
expect "a path relative to the command's directory gains that directory; other lines drop" "sub/a.dm:4: W2 meh" "$(cd "$WORK/rl" && rt_lint sub/a.dm 2>/dev/null)"
RT_SCRIPT='stublint --crash "$@"' RT_DIR="$WORK/rl"
out="$(cd "$WORK/rl" && rt_lint sub/a.dm 2>&1)"
expect "a non-zero exit with no parsed finding fails closed and shows the output" "3|tool crashed" "$?|$(tail -1 <<<"$out")"
RT_SCRIPT='stublint --clean "$@"'
expect "a clean exit passes with no finding" "|0" "$(cd "$WORK/rl" && rt_lint sub/a.dm 2>&1; printf '|%s' "$?")"

echo "resolve-tool: $PASS passed, $FAIL failed"
((FAIL == 0))
