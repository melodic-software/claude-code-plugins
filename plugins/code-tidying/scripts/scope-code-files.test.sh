#!/usr/bin/env bash
# Self-contained contract tests for scope-code-files.sh (throwaway git repos
# under mktemp; never touches the enclosing repository).
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
# The cloud proxy injects url.*.insteadOf rewrites through GIT_CONFIG_*; they
# are irrelevant to local fixtures, but a stray GIT_CONFIG_COUNT with missing
# pairs makes git refuse to run at all.
for v in $(env | sed -n 's/^\(GIT_CONFIG_[A-Z_0-9]*\)=.*/\1/p'); do unset "$v"; done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

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
assert_equal "--base main is honored" "rung=branch base=main files=1" "$(printf '%s\n' "$out" | head -1)"
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

# 9. Characterization: one untracked file per extension in the shared list.
union="$TEST_TMPDIR/union"
mkrepo "$union"
for ext in cs ts tsx mts cts js jsx mjs cjs py pyi sh bash ps1 psm1 go rs java rb lua sql c h cpp hpp yaml yml toml; do
  printf 'x\n' >"$union/f.$ext"
done
printf 'x\n' >"$union/notes.txt"
out=$(cd "$union" && bash "$SCRIPT")
assert_equal "every listed extension is code" "rung=uncommitted base=none files=28" "$(printf '%s\n' "$out" | head -1)"
lines=$'\n'"$out"$'\n'
for ext in cs ts tsx mts cts js jsx mjs cjs py pyi sh bash ps1 psm1 go rs java rb lua sql c h cpp hpp yaml yml toml; do
  assert_contains "characterization: f.$ext listed" "$lines" $'\n'"f.$ext"$'\n'
done
assert_absent "a .txt file is excluded" "$out" "notes.txt"

# 10. An unreadable extension list is named, never an empty match.
lone="$TEST_TMPDIR/lone"
mkdir -p "$lone"
cp "$SCRIPT" "$lone/scope-code-files.sh"
out=$(cd "$union" && bash "$lone/scope-code-files.sh" 2>&1)
assert_equal "a missing extension list exits 4" "4" "$?"
assert_contains "the missing list's path is named" "$out" "$lone/code-extensions.txt"
assert_absent "no rung is reported without the list" "$out" "rung="
assert_absent "only the script's own message is printed" "$out" "No such file"

bo="$TEST_TMPDIR/branch-only"
mkrepo "$bo"
printf 'x=1\n' >"$bo/a.sh"
printf 'y=2\n' >"$bo/b.py"
commit_all "$bo" init
git -C "$bo" checkout -q -b feature
printf 'w=4\n' >"$bo/feat.cs"
printf 'doc\n' >"$bo/NOTES.md"
commit_all "$bo" feat
out=$(cd "$bo" && bash "$SCRIPT" --branch-only --base main)
assert_equal "--branch-only on a clean branch lists the branch's code files" "rung=branch base=main files=1" "$(printf '%s\n' "$out" | head -1)"
assert_contains "--branch-only on a clean branch lists the committed feat.cs" "$out" "feat.cs"
assert_absent "--branch-only excludes the branch's markdown" "$out" "NOTES.md"

printf 'x=2\n' >"$bo/a.sh"
out=$(cd "$bo" && bash "$SCRIPT" --branch-only --base main)
assert_equal "--branch-only on a dirty tree stays on the branch rung and adds the edited file" "rung=branch base=main files=2" "$(printf '%s\n' "$out" | head -1)"
assert_contains "--branch-only on a dirty tree keeps the committed feat.cs" "$out" "feat.cs"
assert_contains "--branch-only on a dirty tree lists the uncommitted a.sh" "$out" "a.sh"
assert_absent "--branch-only on a dirty tree omits the untouched b.py" "$out" "b.py"

printf 'z=3\n' >"$bo/fresh.ts"
printf 'notes\n' >"$bo/fresh.md"
out=$(cd "$bo" && bash "$SCRIPT" --branch-only --base main)
assert_equal "--branch-only counts an untracked code file" "rung=branch base=main files=3" "$(printf '%s\n' "$out" | head -1)"
assert_contains "--branch-only lists the untracked fresh.ts" "$out" "fresh.ts"
assert_absent "--branch-only omits the untracked markdown" "$out" "fresh.md"
mkdir -p "$bo/src" "$bo/lib"
printf 'q=5\n' >"$bo/src/inner.ts"
printf 'r=6\n' >"$bo/lib/other.ts"
out=$(cd "$bo/src" && bash "$SCRIPT" --branch-only --base main)
assert_contains "--branch-only from a subdirectory lists its own untracked file from the root" "$out" "src/inner.ts"
assert_contains "--branch-only from a subdirectory lists an untracked file elsewhere" "$out" "lib/other.ts"
git -C "$bo" checkout -q -- .
rm -rf "${bo:?}/fresh.ts" "${bo:?}/fresh.md" "${bo:?}/src" "${bo:?}/lib"

git -C "$bo" checkout -q -b no-commits main
out=$(cd "$bo" && bash "$SCRIPT" --branch-only --base main)
assert_equal "--branch-only on a branch with no commits of its own reports zero files, never the repository" "rung=branch base=main files=0" "$(printf '%s\n' "$out" | head -1)"
assert_equal "--branch-only with nothing changed prints no paths" "1" "$(printf '%s\n' "$out" | grep -c .)"

err=$(cd "$bo" && bash "$SCRIPT" --branch-only --base no-such-ref 2>&1 >/dev/null)
assert_equal "--branch-only with a base that does not resolve exits 2" "2" "$?"
assert_contains "--branch-only names the base that does not resolve" "$err" "no-such-ref"

if [[ "$FAILED" -eq 0 ]]; then printf '\nall passed\n'; else
  printf '\n%d failed\n' "$FAILED"
  exit 1
fi
