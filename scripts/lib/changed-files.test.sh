#!/usr/bin/env bash
# Unit tests for scripts/lib/changed-files.sh. Each scenario builds a throwaway
# git repo outside the checkout, commits a base tree, commits a change, and
# asserts what the shared resolver reports.
#
# The NUL-safety cases are the reason this suite exists rather than leaning on
# the four calling gates' own suites. A pathname Git C-quotes under the default
# core.quotePath is exactly the input that made check-changed-skills.sh and
# check-docs-only.sh diverge from the two portability scanners (#2914, finding
# 1), and no caller suite exercised it -- the divergence was found by reading,
# not by a red test. Asserting it here means the invariant now has one owner and
# one failing test if it is ever dropped again.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SELF_DIR/.." && pwd)"
# shellcheck source=changed-files.sh
. "$SELF_DIR/changed-files.sh"
# shellcheck source=../test-git-helpers.sh
. "$SCRIPTS_DIR/test-git-helpers.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

# mk_repo -> prints the path of a fresh repo with one committed base tree.
mk_repo() {
  local dir
  dir="$(mktemp -d)"
  git_init_test_repo "$dir" >/dev/null || return 1
  mkdir -p "$dir/plugins/p1/skills/alpha" "$dir/docs"
  printf 'seed\n' >"$dir/plugins/p1/skills/alpha/SKILL.md"
  printf 'seed\n' >"$dir/docs/README.md"
  printf 'seed\n' >"$dir/keep.sh"
  git_test_config "$dir" add -A >/dev/null
  git_test_config "$dir" commit -qm base >/dev/null
  printf '%s' "$dir"
}

# run_into <repo> <out-array-name> <args...> — source-level call inside <repo>.
# `changed_files::into` assigns through a nameref, so it must run in a shell
# whose cwd is the fixture; a subshell would lose the array.
run_into() {
  local repo="$1"
  shift
  local prev="$PWD"
  cd "$repo" || return 1
  local rc=0
  changed_files::into "$@" || rc=$?
  cd "$prev" || return 1
  return "$rc"
}

# --- verify_base ----------------------------------------------------------

repo="$(mk_repo)"
if (cd "$repo" && changed_files::verify_base HEAD); then
  ok "verify_base accepts a resolvable ref"
else
  fail "verify_base rejected HEAD"
fi
if (cd "$repo" && changed_files::verify_base definitely-not-a-ref 2>/dev/null); then
  fail "verify_base accepted a bogus ref"
else
  ok "verify_base rejects a bogus ref"
fi
# A ref that resolves to a TREE rather than a commit must not pass: the callers
# feed the result to `git diff <base>`, which needs a commit.
if (cd "$repo" && changed_files::verify_base "HEAD^{tree}" 2>/dev/null); then
  fail "verify_base accepted a tree-ish"
else
  ok "verify_base rejects a non-commit ref"
fi
rm -rf "$repo"

# --- resolve_base ---------------------------------------------------------

repo="$(mk_repo)"
# The fixture's default branch resolves bare, with no origin/ remote present, so
# the candidate ladder must fall past origin/main to the local branch.
if (
  cd "$repo" || exit 1
  b=""
  changed_files::resolve_base b && [[ "$b" == "main" || "$b" == "master" ]]
); then
  ok "resolve_base falls through to a local default branch"
else
  fail "resolve_base did not fall through to main/master"
fi
# Every rung of the ladder must be a REAL commit, never a name handed back
# unverified for `git diff` to reject a moment later.
if (
  cd "$repo" || exit 1
  b=""
  changed_files::resolve_base b && changed_files::verify_base "$b"
); then
  ok "resolve_base only returns a resolvable ref"
else
  fail "resolve_base returned an unresolvable ref"
fi
# A repo with no main/master and no origin/ has nothing to fall back to.
bare="$(mktemp -d)"
git_init_test_repo "$bare" >/dev/null
printf 'seed\n' >"$bare/f.txt"
git_test_config "$bare" add -A >/dev/null
git_test_config "$bare" commit -qm base >/dev/null
git_test_config "$bare" branch -m not-a-default >/dev/null
if (
  cd "$bare" || exit 1
  b=""
  changed_files::resolve_base b
); then
  fail "resolve_base invented a base with no candidate present"
else
  ok "resolve_base fails when no candidate ref resolves"
fi
rm -rf "$bare"
rm -rf "$repo"

# --- into: basic selection ------------------------------------------------

repo="$(mk_repo)"
base="$(git -C "$repo" rev-parse HEAD)"
printf 'changed\n' >"$repo/plugins/p1/skills/alpha/SKILL.md"
printf 'changed\n' >"$repo/docs/README.md"
git_test_config "$repo" add -A >/dev/null
git_test_config "$repo" commit -qm change >/dev/null

paths=()
if run_into "$repo" paths "$base" -- && ((${#paths[@]} == 2)); then
  ok "into reports every changed path with no pathspec"
else
  fail "into reported ${#paths[@]} paths, expected 2"
fi

paths=()
if run_into "$repo" paths "$base" -- 'plugins/' &&
  ((${#paths[@]} == 1)) && [[ "${paths[0]}" == "plugins/p1/skills/alpha/SKILL.md" ]]; then
  ok "into honours a pathspec"
else
  fail "into pathspec filtering returned: ${paths[*]-<none>}"
fi
rm -rf "$repo"

# --- into: deletions ------------------------------------------------------

repo="$(mk_repo)"
base="$(git -C "$repo" rev-parse HEAD)"
git_test_config "$repo" rm -q keep.sh >/dev/null
git_test_config "$repo" commit -qm delete >/dev/null

paths=()
run_into "$repo" paths "$base" --
if ((${#paths[@]} == 0)); then
  ok "into drops deleted paths by default (--diff-filter=d)"
else
  fail "into kept a deleted path by default: ${paths[*]}"
fi

paths=()
run_into "$repo" paths "$base" --include-deleted --
if ((${#paths[@]} == 1)) && [[ "${paths[0]}" == "keep.sh" ]]; then
  ok "into keeps deleted paths under --include-deleted"
else
  fail "into --include-deleted returned: ${paths[*]-<none>}"
fi
rm -rf "$repo"

# --- into: NUL safety (the divergence this extraction closed) -------------

repo="$(mk_repo)"
base="$(git -C "$repo" rev-parse HEAD)"
# A non-ASCII pathname is C-quoted by `git diff --name-only` under the default
# core.quotePath. Read line-wise it arrives wrapped in double quotes with its
# high bytes spelled as octal escapes, so it fails every suffix test a caller
# applies; read NUL-delimited it arrives as the real name.
quoted_name='café.sh'
printf 'seed\n' >"$repo/$quoted_name"
git_test_config "$repo" add -A >/dev/null
git_test_config "$repo" commit -qm unicode >/dev/null

paths=()
run_into "$repo" paths "$base" --
if ((${#paths[@]} == 1)) && [[ "${paths[0]}" == "$quoted_name" ]]; then
  ok "into returns a C-quotable pathname verbatim"
else
  fail "into mangled a C-quotable pathname: ${paths[*]-<none>}"
fi
# Prove the fixture is a real regression guard: the shape being replaced does
# mangle this name, so the assertion above is discriminating rather than vacuous.
line_wise="$(git -C "$repo" diff --name-only "$base")"
if [[ "$line_wise" != "$quoted_name" ]]; then
  ok "the line-wise read this helper replaced does mangle that name (guard is live)"
else
  fail "line-wise read did not mangle the name — core.quotePath may be off, weakening the guard above"
fi
rm -rf "$repo"

# A pathname containing a literal newline is the case NO line-wise read can
# survive, quoting or not.
repo="$(mk_repo)"
base="$(git -C "$repo" rev-parse HEAD)"
nl_name="$(printf 'two\nlines.sh')"
printf 'seed\n' >"$repo/$nl_name"
git_test_config "$repo" add -A >/dev/null
git_test_config "$repo" commit -qm newline >/dev/null
paths=()
run_into "$repo" paths "$base" --
if ((${#paths[@]} == 1)) && [[ "${paths[0]}" == "$nl_name" ]]; then
  ok "into returns a pathname containing a newline verbatim"
else
  fail "into split a pathname containing a newline: ${#paths[@]} entries"
fi
rm -rf "$repo"

# --- into: failure is loud, never an empty change set ---------------------

repo="$(mk_repo)"
paths=(sentinel)
if run_into "$repo" paths no-such-base -- 2>/dev/null; then
  fail "into succeeded against an unresolvable base"
else
  ok "into fails against an unresolvable base rather than reporting nothing"
fi
paths=()
if run_into "$repo" paths HEAD --bogus-flag 2>/dev/null; then
  fail "into accepted an unknown option"
else
  ok "into rejects an unknown option"
fi
rm -rf "$repo"

# --- summary --------------------------------------------------------------

echo
echo "passed: $PASS  failed: $FAIL"
((FAIL == 0)) || exit 1
