#!/usr/bin/env bash
# Self-contained contract tests for scope-code-files.sh (throwaway git repos
# under mktemp; never touches the enclosing repository).
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
# The cloud proxy injects url.*.insteadOf rewrites through GIT_CONFIG_*; they
# are irrelevant to local fixtures, but a stray GIT_CONFIG_COUNT with missing
# pairs makes git refuse to run at all.
for v in $(env | sed -n 's/^\(GIT_CONFIG_[A-Z_0-9]*\)=.*/\1/p'); do unset "$v"; done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/scope-code-files.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_equal() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "contains: $3" "$2" ;; esac }
assert_absent() { case "$2" in *"$3"*) fail "$1" "absent: $3" "$2" ;; *) pass "$1" ;; esac }

mkrepo() {
  local dir="$1"
  git init -q -b main "$dir"
  git -C "$dir" config user.email t@example.com
  git -C "$dir" config user.name t
  git -C "$dir" config commit.gpgsign false
}
commit_all() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }

# 1. Not a git repository.
plain="$TEST_TMPDIR/plain"
mkdir -p "$plain"
(cd "$plain" && bash "$SCRIPT" >/dev/null 2>&1)
rc=$?
assert_equal "exit 1 outside a git repository" "1" "$rc"

# 2. Clean tree on main, no origin: whole repository, code files only.
r2="$TEST_TMPDIR/r2"
mkrepo "$r2"
printf 'x=1\n' >"$r2/a.sh"
printf 'hi\n' >"$r2/README.md"
printf 'y=2\n' >"$r2/b.py"
commit_all "$r2" init
out=$(cd "$r2" && bash "$SCRIPT")
assert_equal "clean tree on main resolves to the repository rung" "rung=repository base=main files=2" "$(printf '%s\n' "$out" | head -1)"
assert_contains "repository rung lists a.sh" "$out" "a.sh"
assert_contains "repository rung lists b.py" "$out" "b.py"
assert_absent "repository rung excludes README.md" "$out" "README.md"

# 3. Dirty tree: uncommitted rung, only code files, rename emits the new path.
printf 'x=2\n' >"$r2/a.sh"
printf 'more\n' >>"$r2/README.md"
printf 'z=3\n' >"$r2/new.ts"
git -C "$r2" mv b.py c.py
out=$(cd "$r2" && bash "$SCRIPT")
assert_equal "dirty tree resolves to the uncommitted rung" "rung=uncommitted base=none files=3" "$(printf '%s\n' "$out" | head -1)"
assert_contains "uncommitted rung lists the modified a.sh" "$out" "a.sh"
assert_contains "uncommitted rung lists the untracked new.ts" "$out" "new.ts"
assert_contains "uncommitted rung lists the rename's new path" "$out" "c.py"
assert_absent "uncommitted rung omits the rename's old path" "$out" "b.py"
assert_absent "uncommitted rung excludes README.md" "$out" "README.md"
git -C "$r2" checkout -q -- . 2>/dev/null
git -C "$r2" reset -q --hard
git -C "$r2" clean -qfd

# 4. Feature branch ahead of an origin/HEAD base, clean: branch rung, base from origin.
origin="$TEST_TMPDIR/origin.git"
git init -q --bare -b main "$origin"
git -C "$r2" remote add origin "$origin"
git -C "$r2" push -q origin main
git -C "$r2" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$r2" checkout -q -b feature
printf 'w=4\n' >"$r2/feat.cs"
printf 'doc\n' >"$r2/NOTES.md"
commit_all "$r2" feat
out=$(cd "$r2" && bash "$SCRIPT")
assert_equal "branch ahead of origin/HEAD resolves to the branch rung" "rung=branch base=origin/main files=1" "$(printf '%s\n' "$out" | head -1)"
assert_contains "branch rung lists the committed feat.cs" "$out" "feat.cs"
assert_absent "branch rung excludes the committed NOTES.md" "$out" "NOTES.md"
assert_absent "branch rung excludes files unchanged since the merge-base" "$out" "a.sh"

# 5. Docs-only branch: the rung exists with zero files; it must not widen.
git -C "$r2" checkout -q main
git -C "$r2" checkout -q -b docs
printf 'only docs\n' >"$r2/GUIDE.md"
commit_all "$r2" docs
out=$(cd "$r2" && bash "$SCRIPT")
assert_equal "docs-only branch stays on the branch rung with zero files" "rung=branch base=origin/main files=0" "$(printf '%s\n' "$out" | head -1)"
assert_equal "docs-only branch prints no paths" "1" "$(printf '%s\n' "$out" | grep -c .)"

# 6. --base override and --max cap.
out=$(cd "$r2" && git checkout -q feature && bash "$SCRIPT" --base main --max 1)
assert_equal "--base main is honoured" "rung=branch base=main files=1" "$(printf '%s\n' "$out" | head -1)"
out=$(cd "$r2" && git checkout -q main && bash "$SCRIPT" --max 1)
assert_equal "--max caps the listing but not the count" "rung=repository base=origin/main files=2" "$(printf '%s\n' "$out" | head -1)"
assert_equal "--max 1 prints exactly one path" "2" "$(printf '%s\n' "$out" | grep -c .)"

# 6b. A new directory and the grammar-only extensions. Default porcelain output
# collapses an untracked directory to `?? dir/`, which no extension matches.
mkdir -p "$r2/newdir/deeper"
printf 'x = 1\n' >"$r2/newdir/deeper/fresh.py"
printf 'export const a = 1;\n' >"$r2/newdir/mod.mjs"
printf 'notes\n' >"$r2/newdir/README.md"
out=$(cd "$r2" && bash "$SCRIPT")
assert_equal "an untracked directory lists its code files" "rung=uncommitted base=none files=2" "$(printf '%s\n' "$out" | head -1)"
assert_contains "the nested new file is listed" "$out" "newdir/deeper/fresh.py"
assert_contains "a .mjs file counts as code" "$out" "newdir/mod.mjs"
assert_absent "the untracked directory's markdown is excluded" "$out" "README.md"
rm -rf "$r2/newdir"

# 7. Usage errors.
(cd "$r2" && bash "$SCRIPT" --max notanumber >/dev/null 2>&1)
assert_equal "bad --max exits 2" "2" "$?"
(cd "$r2" && bash "$SCRIPT" --bogus >/dev/null 2>&1)
assert_equal "unknown flag exits 2" "2" "$?"

# 8. Determinism.
a=$(cd "$r2" && bash "$SCRIPT" | md5sum)
b=$(cd "$r2" && bash "$SCRIPT" | md5sum)
assert_equal "output is deterministic" "$a" "$b"

if [[ "$FAILED" -eq 0 ]]; then printf '\nall passed\n'; else
  printf '\n%d failed\n' "$FAILED"
  exit 1
fi
