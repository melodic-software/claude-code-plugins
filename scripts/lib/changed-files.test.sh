#!/usr/bin/env bash
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SELF_DIR/.." && pwd)"
# shellcheck source=changed-files.sh
. "$SELF_DIR/changed-files.sh"
# shellcheck source=../test-git-helpers.sh
. "$SCRIPTS_DIR/test-git-helpers.sh"

# shellcheck source=test-harness.sh
. "$SELF_DIR/test-harness.sh"

mk_repo() {
  local dir
  dir="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
  git_init_test_repo "$dir" >/dev/null || return 1
  mkdir -p "$dir/plugins/p1/skills/alpha" "$dir/docs"
  printf 'seed\n' >"$dir/plugins/p1/skills/alpha/SKILL.md"
  printf 'seed\n' >"$dir/docs/README.md"
  printf 'seed\n' >"$dir/keep.sh"
  git_test_config "$dir" add -A >/dev/null
  git_test_config "$dir" commit -qm base >/dev/null
  printf '%s' "$dir"
}

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
if (cd "$repo" && changed_files::verify_base "HEAD^{tree}" 2>/dev/null); then
  fail "verify_base accepted a tree-ish"
else
  ok "verify_base rejects a non-commit ref"
fi
rm -rf "$repo"

repo="$(mk_repo)"
if (
  cd "$repo" || exit 1
  b=""
  changed_files::resolve_base b && [[ "$b" == "main" || "$b" == "master" ]]
); then
  ok "resolve_base falls through to a local default branch"
else
  fail "resolve_base did not fall through to main/master"
fi
if (
  cd "$repo" || exit 1
  b=""
  changed_files::resolve_base b && changed_files::verify_base "$b"
); then
  ok "resolve_base only returns a resolvable ref"
else
  fail "resolve_base returned an unresolvable ref"
fi
bare="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
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
  ok "into honors a pathspec"
else
  fail "into pathspec filtering returned: ${paths[*]-<none>}"
fi
rm -rf "$repo"

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

repo="$(mk_repo)"
base="$(git -C "$repo" rev-parse HEAD)"
git_test_config "$repo" mv keep.sh moved.sh >/dev/null
git_test_config "$repo" commit -qm move >/dev/null

paths=()
run_into "$repo" paths "$base" --include-deleted --
if ((${#paths[@]} == 1)) && [[ "${paths[0]}" == "moved.sh" ]]; then
  ok "into collapses a byte-identical move to its destination by default"
else
  fail "into default rename handling returned: ${paths[*]-<none>}"
fi

paths=()
run_into "$repo" paths "$base" --include-deleted --no-renames --
if ((${#paths[@]} == 2)) && [[ "${paths[0]}" == "keep.sh" && "${paths[1]}" == "moved.sh" ]]; then
  ok "into reports both sides of a move under --no-renames"
else
  fail "into --no-renames returned: ${paths[*]-<none>}"
fi

git_test_config "$repo" config diff.renames false >/dev/null
paths=()
run_into "$repo" paths "$base" --include-deleted --
if ((${#paths[@]} == 2)); then
  ok "diff.renames=false does split a move by default (the fixture is discriminating)"
else
  fail "diff.renames=false fixture did not split the move: ${paths[*]-<none>}"
fi

paths=()
run_into "$repo" paths "$base" --include-deleted --find-renames --
if ((${#paths[@]} == 1)) && [[ "${paths[0]}" == "moved.sh" ]]; then
  ok "into --find-renames collapses a move even under diff.renames=false"
else
  fail "into --find-renames returned: ${paths[*]-<none>}"
fi
rm -rf "$repo"

repo="$(mk_repo)"
base="$(git -C "$repo" rev-parse HEAD)"
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
line_wise="$(git -C "$repo" diff --name-only "$base")"
if [[ "$line_wise" != "$quoted_name" ]]; then
  ok "the line-wise read this helper replaced does mangle that name (guard is live)"
else
  fail "line-wise read did not mangle the name — core.quotePath may be off, weakening the guard above"
fi
rm -rf "$repo"

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

repo="$(mk_repo)"
base_sha="$(git -C "$repo" rev-parse HEAD)"
printf 'changed\n' >"$repo/docs/README.md"
git_test_config "$repo" add -A >/dev/null
git_test_config "$repo" commit -qm change >/dev/null

for victim in base filter tmp path; do
  if (
    cd "$repo" || exit 1
    unset -v "$victim"
    declare -a "$victim"
    changed_files::into "$victim" "$base_sha" -- >/dev/null 2>&1 || exit 1
    count=0
    eval "count=\${#${victim}[@]}"
    [[ "$count" == "1" ]]
  ); then
    ok "an out-array named '$victim' receives the change set"
  else
    fail "an out-array named '$victim' did not receive the change set (internal local shadows it)"
  fi
done
rm -rf "$repo"

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

test_harness::report
