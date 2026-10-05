#!/usr/bin/env bash
# Black-box test for transcript_dirs.sh, the scope-to-directory map behind
# /session-flow:find-handoff's transcript scan.
#
# Expected directory names come from the sessions docs rule (every character
# that is not a letter or digit becomes `-`; a name past 200 characters keeps
# its first 200 and gains a hash), written out by hand for each fixture path.
# On Linux and macOS the fixture lives under /tmp so its own prefix is known:
# `/tmp/<x>` encodes to `-tmp-<x>`, macOS's `/private/tmp/<x>` to
# `-private-tmp-<x>`. On Git Bash, MSYS2 and Cygwin the temp dir's Windows form
# (`cygpath -w`) is machine-specific, so that one prefix is encoded with the
# same rule; every suffix below stays hand-written.
# Self-contained; mutates only its own mktemp dir.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_CODE_PROJECT_DIR_NAME

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/transcript_dirs.sh"

case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*) WINHOST=1 ;;
*) WINHOST=0 ;;
esac
if [[ "$WINHOST" -eq 1 ]] && ! command -v cygpath >/dev/null 2>&1; then
  echo "SKIP: a Windows bash without cygpath; the script cannot form Windows paths here"
  exit 0
fi

WORKROOT="$(mktemp -d /tmp/sftdXXXXXXXX)"
trap 'rm -rf "$WORKROOT"' EXIT
T="$(cd "$WORKROOT" && pwd -P)"
if [[ "$WINHOST" -eq 1 ]]; then
  wT="$(cygpath -w "$T")"
  base="$(LC_ALL=C && printf '%s' "${wT//[^A-Za-z0-9]/-}")"
else
  case "$T" in
  /tmp/*) base="-tmp-${T#/tmp/}" ;;
  /private/tmp/*) base="-private-tmp-${T#/private/tmp/}" ;;
  *)
    echo "SKIP: the temp dir resolved outside /tmp ($T)"
    exit 0
    ;;
  esac
  # The POSIX-form cases need the script's cygpath call to fail, so a stub that
  # always exits 1 shadows any cygpath on PATH. The Windows-form case prepends
  # its own stub ahead of this one.
  NOCYG="$T/nocyg"
  mkdir -p "$NOCYG"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$NOCYG/cygpath"
  chmod +x "$NOCYG/cygpath"
  export PATH="$NOCYG:$PATH"
fi
# A recorded cwd is the session's own path: the Windows form on a Windows host.
cwd_of() { if [[ "$WINHOST" -eq 1 ]]; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

fails=0
assert_true() { # assert_true <description> <command...>
  local desc="$1"
  shift
  if "$@"; then printf 'ok   - %s\n' "$desc"; else
    printf 'FAIL - %s\n' "$desc" >&2
    fails=$((fails + 1))
  fi
}

OUT=""
CODE=0
run_in() { # run_in <dir> [args...]; CLAUDE_CONFIG_DIR and HOME come from the caller
  local dir="$1"
  shift
  OUT="$(cd "$dir" && bash "$SUT" "$@" 2>"$T/err")"
  CODE=$?
}
code_is() { [[ "$CODE" -eq "$1" ]]; }
out_is() { [[ "$OUT" == "$1" ]]; }
sorted_out_is() { [[ "$(printf '%s\n' "$OUT" | LC_ALL=C sort)" == "$(printf '%s\n' "$@" | LC_ALL=C sort)" ]]; }
first_line_is() { [[ "${OUT%%$'\n'*}" == "$1" ]]; }
no_file_x() { [[ ! -e "$R1/x" && ! -e "$T/x" && ! -e "$SCRIPT_DIR/x" ]]; }
transcript() { # transcript <dir> <file> <cwd>: one record carrying cwd, JSON-escaped
  mkdir -p "$1"
  printf '{"type":"user","cwd":"%s"}\n' "${3//\\/\\\\}" >"$1/$2"
}

# The repository: a main checkout, a subdirectory, a second worktree, and a
# sibling whose name extends the main checkout's.
R1="$T/repo.main"
R2="$T/wt-two"
mkdir -p "$R1/sub" "$T/repo.main-v2" "$T/plain"
git -C "$R1" init -q
# The names below need git to report the fixture root as the shell sees it.
# Git for Windows prints a drive form (C:/...), so on a Windows host the
# comparison goes through `cygpath -u`.
top="$(git -C "$R1" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
[[ "$WINHOST" -eq 1 && -n "$top" ]] && top="$(cygpath -u "$top")"
if [[ "$top" != "$R1" ]]; then
  echo "SKIP: git reports the fixture root as '$top', not '$R1'"
  exit 0
fi
git -C "$R1" -c user.name=t -c user.email=t@example.invalid -c core.hooksPath=/dev/null commit -q --allow-empty -m init
git -C "$R1" worktree add -q "$R2" 2>/dev/null

CFG="$T/cfg"
S="$CFG/projects"
E1="$S/${base}-repo-main"
E1SUB="$S/${base}-repo-main-sub"
E1V2="$S/${base}-repo-main-v2"
E1ODD="$S/${base}-repo-main-\$(touch x)"
E2="$S/${base}-wt-two"
EPLAIN="$S/${base}-plain"
OTHER="$S/-srv-other-project"
mkdir -p "$E1" "$E2" "$EPLAIN" "$OTHER"
transcript "$E1SUB" a.jsonl "$(cwd_of "$R1/sub")"
transcript "$E1ODD" a.jsonl "$(cwd_of "$R1/odd")"
# The sibling: an older transcript claims the root, the newest one does not.
transcript "$E1V2" old.jsonl "$(cwd_of "$R1")"
touch -t 202001010000 "$E1V2/old.jsonl"
transcript "$E1V2" new.jsonl "$(cwd_of "$T/repo.main-v2")"

export HOME="$T/home"
export CLAUDE_CONFIG_DIR="$CFG"

run_in "$R1" --scope worktree
assert_true 'worktree scope exits 0' code_is 0
assert_true 'worktree scope prints the exact directory, the subdirectory session and the odd name' \
  sorted_out_is "$E1" "$E1SUB" "$E1ODD"
assert_true 'the exact-name directory comes first' first_line_is "$E1"
assert_true "the literal \$(touch x) name created no file" no_file_x

run_in "$R1/sub" --scope worktree
assert_true 'from a subdirectory the scope is still the worktree root' sorted_out_is "$E1" "$E1SUB" "$E1ODD"

BASH_COMPAT=51 run_in "$R1" --scope worktree
assert_true 'under BASH_COMPAT=51 the odd name still prints literally' sorted_out_is "$E1" "$E1SUB" "$E1ODD"
assert_true 'under BASH_COMPAT=51 no file x appears' no_file_x

run_in "$R1" --scope repo
assert_true 'repo scope prints both worktrees' sorted_out_is "$E1" "$E1SUB" "$E1ODD" "$E2"
assert_true 'repo scope lists this worktree first' first_line_is "$E1"

run_in "$R2" --scope repo
assert_true 'repo scope from the second worktree lists it first' first_line_is "$E2"
assert_true 'repo scope from the second worktree prints the same set' sorted_out_is "$E1" "$E1SUB" "$E1ODD" "$E2"

run_in "$R2" --scope worktree
assert_true 'worktree scope in the second worktree prints only its directory' out_is "$E2"

run_in "$R1" --scope all
assert_true 'all scope prints every directory under projects' \
  sorted_out_is "$E1" "$E1SUB" "$E1V2" "$E1ODD" "$E2" "$EPLAIN" "$OTHER"

run_in "$T/plain" --scope worktree
assert_true 'outside a repository, worktree is the current directory' out_is "$EPLAIN"
run_in "$T/plain" --scope repo
assert_true 'outside a repository, repo equals worktree' out_is "$EPLAIN"

# A long root: the stored name is its first 200 characters plus a hash.
a100="$(printf 'a%.0s' {1..100})"
b100="$(printf 'b%.0s' {1..100})"
RL="$T/long/$a100/$b100"
mkdir -p "$RL"
git -C "$RL" init -q
enc_long="${base}-long-${a100}-${b100}"
ELONG="$S/${enc_long:0:200}-1q2w3e"
EDECOY="$S/${enc_long:0:200}-9z8y7x"
transcript "$ELONG" a.jsonl "$(cwd_of "$RL")"
transcript "$EDECOY" a.jsonl "$(cwd_of "$T/long/elsewhere")"
run_in "$RL" --scope worktree
assert_true 'a hash-truncated name whose cwd is the root is kept, a decoy is not' out_is "$ELONG"
rm -rf "$ELONG" "$EDECOY"

# CLAUDE_CONFIG_DIR moves the store; without it the store is under HOME.
HSTORE="$HOME/.claude/projects"
mkdir -p "$HSTORE/${base}-repo-main"
run_in "$R1" --scope worktree
assert_true 'with CLAUDE_CONFIG_DIR set the HOME store is not read' sorted_out_is "$E1" "$E1SUB" "$E1ODD"
unset CLAUDE_CONFIG_DIR
run_in "$R1" --scope worktree
assert_true 'without CLAUDE_CONFIG_DIR the store is under HOME' out_is "$HSTORE/${base}-repo-main"
mkdir -p "$HSTORE/pinned"
CLAUDE_CODE_PROJECT_DIR_NAME=pinned run_in "$R1" --scope worktree
assert_true 'a pinned name without CLAUDE_CONFIG_DIR is ignored' out_is "$HSTORE/${base}-repo-main"
export CLAUDE_CONFIG_DIR="$CFG"

# A pinned project directory name, with CLAUDE_CONFIG_DIR set, is the one directory.
mkdir -p "$S/pinned"
for scope in worktree repo all; do
  CLAUDE_CODE_PROJECT_DIR_NAME=pinned run_in "$R1" --scope "$scope"
  assert_true "a pinned name prints only that directory for --scope $scope" out_is "$S/pinned"
done
CLAUDE_CODE_PROJECT_DIR_NAME='bad/name' run_in "$R1" --scope worktree
assert_true 'an invalid pinned name is ignored' sorted_out_is "$E1" "$E1SUB" "$E1ODD"
rm -rf "$S/pinned"

# Windows form, with git ending its lines in CRLF. On a Windows host the cases
# above already ran through the native cygpath, so the names are the same ones;
# elsewhere a stub cygpath maps /x/y to C:\x\y.
STUB="$T/stub"
mkdir -p "$STUB"
REAL_GIT="$(command -v git)"
# shellcheck disable=SC2016 # the stub body is literal
printf '#!/usr/bin/env bash\n"%s" "$@" | sed "s/\\$/\\r/"\nexit "${PIPESTATUS[0]}"\n' "$REAL_GIT" >"$STUB/git"
chmod +x "$STUB/git"
if [[ "$WINHOST" -eq 1 ]]; then
  PATH="$STUB:$PATH" run_in "$R1" --scope worktree
  assert_true 'with the native cygpath and CRLF git output the Windows-form names print' \
    sorted_out_is "$E1" "$E1SUB" "$E1ODD"
  PATH="$STUB:$PATH" run_in "$R1" --scope repo
  assert_true 'repo scope in Windows form reaches the second worktree' sorted_out_is "$E1" "$E1SUB" "$E1ODD" "$E2"
else
  # shellcheck disable=SC2016 # the stub body is literal
  printf '#!/usr/bin/env bash\n[ "$1" = -w ] || exit 1\np="$2"\nprintf "C:%%s\\n" "${p//\\//\\\\}"\n' >"$STUB/cygpath"
  chmod +x "$STUB/cygpath"
  W1="$S/C-${base}-repo-main"
  W1SUB="$S/C-${base}-repo-main-sub"
  W2="$S/C-${base}-wt-two"
  WT="${T//\//\\}"
  mkdir -p "$W1" "$W2"
  transcript "$W1SUB" a.jsonl "c:${WT}\\repo.main\\sub\\"
  PATH="$STUB:$PATH" run_in "$R1" --scope worktree
  assert_true 'with cygpath and CRLF git output the Windows-form names print' sorted_out_is "$W1" "$W1SUB"
  PATH="$STUB:$PATH" run_in "$R1" --scope repo
  assert_true 'repo scope in Windows form reaches the second worktree' sorted_out_is "$W1" "$W1SUB" "$W2"
  rm -rf "$W1" "$W1SUB" "$W2"
fi

# No Python: exact names only, and one gap line on stderr.
NOPY="$T/nopy"
mkdir -p "$NOPY"
BASH_BIN="$(command -v bash)"
# Wrappers, not symlinks: MSYS copies a symlinked .exe away from the DLLs beside it.
tools=(git tr sed)
[[ "$WINHOST" -eq 1 ]] && tools+=(cygpath)
for tool in "${tools[@]}"; do
  printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$(command -v "$tool")" >"$NOPY/$tool"
  chmod +x "$NOPY/$tool"
done
OUT="$(cd "$R1" && PATH="$NOPY" "$BASH_BIN" "$SUT" --scope worktree 2>"$T/err")"
CODE=$?
assert_true 'without python the script exits 0' code_is 0
assert_true 'without python only the exact-name match prints' out_is "$E1"
assert_true 'without python stderr is one line' [ "$(wc -l <"$T/err")" -eq 1 ]
assert_true 'that line is a gap line' [ "$(grep -c '^gap:' "$T/err")" -eq 1 ]

# Usage.
run_in "$R1" --scope wide
assert_true 'an unknown scope exits 2' code_is 2
run_in "$R1"
assert_true 'a missing --scope exits 2' code_is 2
run_in "$R1" --scope worktree extra
assert_true 'an extra argument exits 2' code_is 2

if [[ "$fails" -gt 0 ]]; then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
echo "transcript_dirs.test.sh: all passed"
