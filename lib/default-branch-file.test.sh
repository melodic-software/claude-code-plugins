#!/usr/bin/env bash
# Tests for lib/default-branch-file.sh: the file comes from origin's default branch by SHA, never from the
# working tree or a local branch named origin/HEAD, and a missing file or unreadable branch is an exit code.
# Run directly: bash lib/default-branch-file.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/default-branch-file.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: [$2], actual: [$3]"; fi
}

g() { git -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false "$@"; }

# A clone of a local bare origin whose main commits docs/conventions/explainer-video.yaml and style.css.
dir="$TEST_TMPDIR/repo"
mkdir -p "$dir/work/docs/conventions"
g init -q -b main "$dir/work"
printf 'stitcher: ffmpeg\n' >"$dir/work/docs/conventions/explainer-video.yaml"
printf 'body{}\n' >"$dir/work/style.css"
g -C "$dir/work" add -A
g -C "$dir/work" commit -q -m fixture
g init -q --bare -b main "$dir/origin.git"
g -C "$dir/work" remote add origin "$dir/origin.git"
g -C "$dir/work" push -q origin main
repo="$dir/work"

run() { CLAUDE_PROJECT_DIR="$repo" bash "$SCRIPT" "$@" 2>/dev/null; }
code() {
  CLAUDE_PROJECT_DIR="$repo" bash "$SCRIPT" "$@" >/dev/null 2>&1
  echo $?
}

assert_eq "the team file is read from the default branch" "stitcher: ffmpeg" "$(run --plugin explainer-video)"
assert_eq "a repository path is read from the default branch" "body{}" "$(run --path style.css)"

# The branch's own edits and a local branch named origin/HEAD never change what is read.
g -C "$repo" checkout -q -b origin/HEAD
printf 'stitcher: ./evil {inputs} {out}\n' >"$repo/docs/conventions/explainer-video.yaml"
g -C "$repo" commit -q -am branch
assert_eq "a local branch named origin/HEAD does not shadow the default branch" \
  "stitcher: ffmpeg" "$(run --plugin explainer-video)"
printf 'body{content:"x"}\n' >"$repo/style.css"
assert_eq "the working tree's copy never applies" "body{}" "$(run --path style.css)"

assert_eq "a file the default branch lacks exits 1" 1 "$(code --path missing.css)"
sha="$(g -C "$repo" rev-parse refs/remotes/origin/main)"
last() { CLAUDE_PROJECT_DIR="$repo" bash "$SCRIPT" "$@" 2>&1 >/dev/null | tail -n 1; }
assert_eq "a missing file still names the commit read" \
  "default-branch-file: missing.css at origin/main, commit $sha" "$(last --path missing.css)"

# A fetch that fails reads the last fetched copy and says so. Origin's main moves to a commit whose tree
# names a blob origin does not have: ls-remote still answers, but the fetch cannot send the commit, so
# refs/remotes/origin/main stays on the last fetched one on every git version.
tree="$(printf '100644 blob %s\tx\n' 1111111111111111111111111111111111111111 | g -C "$dir/origin.git" mktree --missing)"
next="$(g -C "$dir/origin.git" commit-tree "$tree" -p "$sha" -m next)"
g -C "$dir/origin.git" update-ref refs/heads/main "$next"
assert_eq "a failed fetch reads the last fetched copy" "body{}" "$(run --path style.css)"
assert_eq "a failed fetch is named as possibly stale" \
  "default-branch-file: style.css at origin/main, commit $sha; the fetch failed, so the last fetched copy may be stale" \
  "$(last --path style.css)"
assert_eq "a parent step in --path exits 2" 2 "$(code --path ../style.css)"
assert_eq "an absolute --path exits 2" 2 "$(code --path /etc/passwd)"
assert_eq "no arguments exit 2" 2 "$(code)"
g -C "$repo" remote remove origin
assert_eq "no origin exits 2" 2 "$(code --plugin explainer-video)"

((FAILED == 0)) || {
  printf '%d failed\n' "$FAILED" >&2
  exit 1
}
printf 'all passed\n'
