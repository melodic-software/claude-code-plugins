#!/usr/bin/env bash
# Contract tests for lib/git-hooks/check-lib.sh against real git repositories:
# the staged and worktree file sets, changed-line ranges, the partly staged
# test, the checks.skipmissing key reaching a hook through `git -c`, agent and
# human missing-tool messages, the pre-push range with its fallbacks, set -e
# tolerance, and a bash 3.2 syntax lint. Expected values come from the
# check-placement contract's runtime table.
# test-scope: lib/git-hooks/check-lib.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/check-lib.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1: want [$2] got [$3]"; fi
}

n=0
new_repo() {
  n=$((n + 1))
  local r="$WORK/r$n"
  git init -q -b main "$r"
  git -C "$r" config user.name t
  git -C "$r" config user.email t@example.invalid
  REPO="$r"
}

# in_repo <repo> <event> <snippet> [args...]: source the lib in <repo> and run <snippet>.
in_repo() {
  local repo="$1" event="$2" snippet="$3"
  shift 3
  (cd "$repo" && bash -c ". '$LIB'; checks_init $event \"\$@\" || exit 9; $snippet" checks "$@")
}

nul_list() { tr '\0' '\n'; }

# --- file set and changed lines -------------------------------------------------
new_repo; R="$REPO"
printf 'one\ntwo\nthree\n' >"$R/a.txt"
printf 'keep\n' >"$R/gone.txt"
git -C "$R" add a.txt gone.txt
git -C "$R" commit -q -m seed
printf 'one\nTWO\nthree\nfour\n' >"$R/a.txt"
printf 'new\n' >"$R/b c.md"
git -C "$R" rm -q gone.txt
git -C "$R" add a.txt "b c.md"
expect "pre-commit files: added and modified, not deleted" $'a.txt\nb c.md' "$(in_repo "$R" pre-commit 'checks_files' | nul_list)"
expect "pre-commit ranges: one line per added hunk, a path with a space" \
  $'a.txt\t2\t2\na.txt\t4\t4\nb c.md\t1\t1' \
  "$(in_repo "$R" pre-commit 'checks_changed_lines; cat "$CHECKS_TMP/ranges"')"
expect "filter keeps a finding on a changed line only" \
  'a.txt:4: x' \
  "$(in_repo "$R" pre-commit 'checks_changed_lines; printf "a.txt:1: x\na.txt:4: x\nother:4: x\n" | checks_filter_findings')"

# --- partly-staged --------------------------------------------------------------
printf 'one\nTWO\nthree\nfour\nfive\n' >"$R/a.txt"
expect "partly-staged: a file with unstaged changes is detected" yes \
  "$(in_repo "$R" pre-commit 'checks_partly_staged a.txt && echo yes || echo no')"
expect "partly-staged: a fully staged file is not" no \
  "$(in_repo "$R" pre-commit 'checks_partly_staged "b c.md" && echo yes || echo no')"

# --- worktree mode --------------------------------------------------------------
printf 'loose\n' >"$R/untracked.txt"
expect "worktree files: tracked changes against HEAD plus untracked" $'a.txt\nb c.md\nuntracked.txt' \
  "$(in_repo "$R" pre-commit 'checks_files' --worktree | nul_list | sort)"
expect "worktree ranges: the unstaged line counts, an untracked file is whole" \
  $'a.txt\t2\t2\na.txt\t4\t5\nb c.md\t1\t1\nuntracked.txt\t1\t2147483647' \
  "$(in_repo "$R" pre-commit 'checks_changed_lines; cat "$CHECKS_TMP/ranges"' --worktree)"

new_repo; U="$REPO"
printf 'first\n' >"$U/x.txt"
git -C "$U" add x.txt
expect "pre-commit on an unborn branch sees the first file" $'x.txt\t1\t1' \
  "$(in_repo "$U" pre-commit 'checks_changed_lines; cat "$CHECKS_TMP/ranges"')"
expect "worktree mode on an unborn branch sees the first file" 'x.txt' \
  "$(in_repo "$U" pre-commit 'checks_files' --worktree | nul_list | sort -u)"

# --- missing tool and skip-propagation ------------------------------------------
new_repo; H="$REPO"
cat >"$H/.git/hooks/pre-commit" <<EOF
#!/usr/bin/env bash
. '$LIB'
checks_init pre-commit "\$@" || exit 0
checks_require_tool nosuchtool-xyz "cargo install nosuchtool-xyz"
echo "ran past the tool check" >&2
exit 0
EOF
chmod +x "$H/.git/hooks/pre-commit"
printf 'x\n' >"$H/x.txt"
git -C "$H" add x.txt

out="$(CLAUDECODE=1 git -C "$H" commit -q -m one 2>&1)"
rc=$?
expect "agent: a missing tool fails the commit" 1 "$rc"
expect "agent: the failure names the install command and the skip key" \
  $'FAIL: nosuchtool-xyz missing. Install: cargo install nosuchtool-xyz\nTo skip only while nosuchtool-xyz is missing: git -c checks.skipmissing=nosuchtool-xyz commit ...' \
  "$out"

out="$(AI_AGENT=codex git -C "$H" commit -q -m one 2>&1)"
expect "agent: AI_AGENT also marks an agent" 1 "$?"

out="$(CLAUDECODE=1 git -C "$H" -c checks.skipmissing='other, nosuchtool-xyz' commit -q -m one 2>&1)"
rc=$?
expect "skip-propagation: git -c checks.skipmissing reaches the hook and skips" "0 SKIPPED: nosuchtool-xyz (missing)" "$rc $out"

out="$(CLAUDECODE=1 git -C "$H" -c checks.skipmissing=nosuchtool commit -q -m two --allow-empty 2>&1)"
expect "skip-propagation: the key matches whole names only" 1 "$?"

out="$(git -C "$H" commit -q -m three --allow-empty 2>&1)"
rc=$?
expect "human: a missing tool is a one-line notice and the commit goes through" \
  "0 NOTICE: nosuchtool-xyz missing, so this check did not run. Install: cargo install nosuchtool-xyz" "$rc $out"

expect "set -e: an unset skip key does not abort a sourcing script" "not listed" \
  "$(cd "$H" && bash -e -c ". '$LIB'; checks_skip_listed typos || echo 'not listed'")"
expect "set -e: a present tool passes under errexit" "present" \
  "$(cd "$H" && bash -e -c ". '$LIB'; checks_init pre-commit; checks_require_tool git x; echo present")"

# --- pre-push ranges -------------------------------------------------------------
REMOTE="$WORK/remote.git"
git init -q --bare -b main "$REMOTE"
new_repo; P="$REPO"
printf 'base\n' >"$P/f.txt"
git -C "$P" add f.txt
git -C "$P" commit -q -m base
git -C "$P" remote add origin "$REMOTE"
git -C "$P" push -q origin main 2>/dev/null
git -C "$P" fetch -q origin
base_sha="$(git -C "$P" rev-parse HEAD)"
git -C "$P" switch -q -c topic
printf 'base\nmore\n' >"$P/f.txt"
git -C "$P" commit -q -am more
topic_sha="$(git -C "$P" rev-parse HEAD)"
zero=0000000000000000000000000000000000000000

expect "pre-push: an existing remote branch ranges from the remote sha" "$base_sha $topic_sha" \
  "$(printf 'refs/heads/topic %s refs/heads/topic %s\n' "$topic_sha" "$base_sha" | in_repo "$P" pre-push 'cat "$CHECKS_TMP/push-ranges"' origin url)"
expect "pre-push: a deletion is skipped" "" \
  "$(printf '(delete) %s refs/heads/old %s\n' "$zero" "$base_sha" | in_repo "$P" pre-push 'cat "$CHECKS_TMP/push-ranges"' origin url)"

git -C "$P" remote set-head origin main >/dev/null
expect "pre-push: a new branch starts at its merge-base with <remote>/HEAD" "$base_sha $topic_sha" \
  "$(printf 'refs/heads/topic %s refs/heads/topic %s\n' "$topic_sha" "$zero" | in_repo "$P" pre-push 'cat "$CHECKS_TMP/push-ranges"' origin url)"
expect "pre-push: the range's changed lines" $'f.txt\t2\t2' \
  "$(printf 'refs/heads/topic %s refs/heads/topic %s\n' "$topic_sha" "$zero" | in_repo "$P" pre-push 'checks_changed_lines; cat "$CHECKS_TMP/ranges"' origin url)"

git -C "$P" remote set-head origin -d >/dev/null
expect "pre-push: without <remote>/HEAD, ls-remote --symref finds the default branch" "$base_sha $topic_sha" \
  "$(printf 'refs/heads/topic %s refs/heads/topic %s\n' "$topic_sha" "$zero" | in_repo "$P" pre-push 'cat "$CHECKS_TMP/push-ranges"' origin url)"

git -C "$P" remote add nowhere "$WORK/missing.git"
out="$(printf 'refs/heads/topic %s refs/heads/topic %s\n' "$topic_sha" "$zero" | in_repo "$P" pre-push 'cat "$CHECKS_TMP/push-ranges"; echo "rc=$?"' nowhere url 2>&1)"
expect "pre-push: no default branch skips the ref with a notice, never aborting" \
  $'NOTICE: no default branch found for nowhere, so refs/heads/topic was not checked.\nrc=0' "$out"

git -C "$P" branch -q -u origin/main
expect "pre-push: no stdin ranges the branch against its upstream" "$base_sha $topic_sha" \
  "$(in_repo "$P" pre-push 'cat "$CHECKS_TMP/push-ranges"' origin url </dev/null)"

# --- bash 3.2 syntax lint ---------------------------------------------------------
# Constructs newer than bash 3.2 (macOS /bin/bash). Comments are skipped.
lint_32() {
  grep -nE '^[^#]*(declare -A|local -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)|;;&|\|&|&>>|\[\[ -v |local -n|declare -n|coproc|wait -n|\$\{[A-Za-z_]+\[-1\]\})' "$1"
}
for f in "$LIB" "$HERE/../../plugins/typos-format/git-hooks/typos-check.sh"; do
  [[ -f "$f" ]] || continue
  hits="$(lint_32 "$f")"
  expect "bash 3.2 syntax: $(basename "$f") uses nothing newer" "" "$hits"
done
expect "bash 3.2 lint catches what it guards" yes \
  "$(printf 'declare -A m=()\n' >"$WORK/bad.sh" && lint_32 "$WORK/bad.sh" >/dev/null && echo yes)"
expect "function names are POSIX-safe (no ::)" "" "$(grep -nE '^[a-z_]+::' "$LIB")"

echo "check-lib: $PASS passed, $FAIL failed"
((FAIL == 0))
