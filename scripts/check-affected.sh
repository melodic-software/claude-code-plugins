#!/usr/bin/env bash
# Run the diff-scoped lint checks CI runs, over what this branch changed, before
# a push spends a CI round on them. One entrypoint, so a person, an agent and the
# pre-push hook (.claude/hooks/check-affected-pre-push.sh) all run the same set.
#
#   scripts/check-affected.sh                 the lint checks
#   scripts/check-affected.sh --tests         ... and scripts/affected-tests.sh --run
#   scripts/check-affected.sh --base <ref>    diff against <ref> (default: origin/main)
#   scripts/check-affected.sh --no-fetch      skip refreshing <ref> before the
#                                             stale-base check
#   scripts/check-affected.sh --uncommitted   check the work tree as the commit
#                                             it would make (default base: HEAD)
#
# --uncommitted is for a run that commits through an API from the files on
# disk rather than in the checkout, such as the issue lane: it commits the work
# tree, untracked files and file modes included, through a temporary index and
# object directory, checks that commit out in a scratch repository, and runs
# the checks there. Nothing is written under .git, so the checkout's HEAD,
# index and worktree list stay as they are. With CHECK_AFFECTED_SCRIPT_EXEC_BIT=1
# (the issue lane's patch run) that commit makes each new or changed .sh or #!
# file executable, as apply-patch will.
#
# Each check calls the script or tool CI calls; none restates a check's logic.
# The changed set is <merge-base of HEAD and the base>..HEAD, committed work
# only, because that is what a push sends. The checks read the working tree,
# so when a changed file has uncommitted edits every check SKIPs rather than
# judge content the push would not send; CI checks the pushed commit.
#
#   - markdown:            markdownlint-cli2 on changed .md
#   - shellcheck:          shellcheck --rcfile .shellcheckrc on changed .sh/.bash
#   - shell-portability:   scripts/check-shell-portability.sh <merge-base>
#   - exec-bit:            a changed file starting with #! is 100755 in the index
#   - changelog-fragments: scripts/check-changelog-fragments.sh --check and
#                          --check-required <base>
#   - stale-base-overlap:  scripts/check-stale-base-overlap.sh --check <base>
#   - validate-plugins:    scripts/validate-plugins.sh --only <touched plugins>
#   - ruff:                scripts/run-ruff.sh check on changed .py
#   - typos:               typos --config _typos.toml on the changed files
#   - spoke-plugin-root:   scripts/check-spoke-plugin-root.sh --check
#   - plugin-options-docs: python3 scripts/sync-plugin-options-docs.py --check
#   - changelog-parity:    scripts/check-changelog-parity.sh in the --check,
#                          --check-bump, --check-preserved and --check-order
#                          modes the pull_request run uses
#   - changed-skills:      scripts/check-changed-skills.sh <base>, when a skill
#                          file changed
#   - tests (--tests):     scripts/affected-tests.sh --run --base <base>
#
# Every hygiene gate the CI jobs run that this does not is printed as
# `CI only: <gate>`. scripts/check-affected-gates.txt lists each gate with how it
# is covered, and scripts/check-affected-gates.test.sh fails when a gate in
# the workflow's hygiene jobs is in neither column.
#
# Code runs from the tree holding this script, and the files checked are that
# tree's too, whatever the working directory, unless CHECK_DATA_ROOT names
# another tree. The pre-push hook runs a merge-base copy of this script with
# CHECK_DATA_ROOT naming the branch tree, so the two differ: then every check
# script runs from the copy with CHECK_DATA_ROOT passed on, markdownlint
# reads only the copy's configs (a branch config can load a custom rule, which
# is code), and checks that run the branch's own code skip: --tests, changed-skills, and the
# validate-plugins steps that report `SKIP` themselves.
#
# CI is still the gate that decides: this covers the diff-scoped LINT tier and
# the plugin and skill contract checks above, not CI's whole-repo scanners, and
# it does not widen shellcheck to the files that
# source a changed library the way CI's lint-shell job does.
#
# A missing tool, a failed fetch, or a check that exits 2 (could not run) is a
# SKIP with its reason, never a failure. Exit 0 every check passed or skipped;
# 1 a check failed, with each failure and its reproduce command on stderr; 2
# usage or a git state the changed set cannot be read from, an empty changed
# set while HEAD is not the base among them. That is the
# check-script family contract stated in README.md.
set -uo pipefail

usage() {
  echo "usage: $(basename "$0") [--tests] [--base <ref>] [--no-fetch] [--uncommitted]" >&2
  exit 2
}

run_tests=0
fetch=1
uncommitted=0
base=
while (($#)); do
  case "$1" in
  --tests) run_tests=1 ;;
  --no-fetch) fetch=0 ;;
  --uncommitted) uncommitted=1 ;;
  --base)
    [[ $# -ge 2 && -n "$2" ]] || usage
    base="$2"
    shift
    ;;
  -h | --help) usage ;;
  *) usage ;;
  esac
  shift
done

tools="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)" || exit 2
top="$(git -C "${CHECK_DATA_ROOT:-$tools}" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "check-affected: ${CHECK_DATA_ROOT:-$tools} is not inside a git work tree" >&2
  exit 2
}
cd "$top" || exit 2

if ((uncommitted)); then
  # The scratch repository has no remote, so the base is fetched and resolved
  # to a commit here, and the inner run gets that commit and --no-fetch.
  if [[ -z "$base" ]]; then
    base=HEAD
  elif ((fetch)) && [[ "$base" == */* ]]; then
    git fetch --quiet "${base%%/*}" "${base#*/}" 2>/dev/null || export CHECK_AFFECTED_FETCH_FAILED=1
  fi
  base="$(git rev-parse --verify --quiet "$base^{commit}")" || {
    echo "check-affected: cannot resolve the base to a commit" >&2
    exit 2
  }
  # Nothing is written under .git, which the lane's sandbox can make read-only:
  # new objects go to $snap/objects, and the commit is checked out in a scratch
  # repository whose alternates borrow every other object from this one.
  snap="$(mktemp -d)" || exit 2
  trap 'rm -rf "$snap"' EXIT
  objects="$(cd "$(git rev-parse --git-common-dir)/objects" && pwd -P)" || exit 2
  index="$(git rev-parse --git-path index)" || exit 2
  shallow="$(git rev-parse --git-path shallow)" || exit 2
  [[ ! -f "$index" ]] || cp "$index" "$snap/index" || exit 2
  mkdir "$snap/objects" || exit 2
  export GIT_INDEX_FILE="$snap/index" GIT_OBJECT_DIRECTORY="$snap/objects" GIT_ALTERNATE_OBJECT_DIRECTORIES="$objects"
  # The lane's sandbox masks dotfiles with /dev/null, a device git will not
  # add, so only files, symlinks, repositories and deletions are staged.
  # An empty pathspec would make add -A stage everything, so none means no add.
  paths=()
  while IFS= read -r -d '' f; do
    if [[ -f "$f" || -L "$f" || -d "$f" || ! -e "$f" ]]; then paths+=("$f"); fi
  done < <(git ls-files -z --modified --others --exclude-standard)
  if ((${#paths[@]})); then
    printf '%s\0' "${paths[@]}" | git add -A --pathspec-from-file=- --pathspec-file-nul || exit 2
    # An issue lane's patch is committed by apply-patch, which makes each new
    # or changed .sh or #! file executable, so the snapshot does the same.
    if [[ ${CHECK_AFFECTED_SCRIPT_EXEC_BIT:-} == 1 ]]; then
      for f in "${paths[@]}"; do
        [[ -f "$f" && ! -L "$f" ]] || continue
        if [[ "$f" == *.sh || "$(head -c 2 -- "$f")" == '#!' ]]; then git update-index --chmod=+x -- "$f" || exit 2; fi
      done
    fi
  fi
  tree="$(git write-tree)" || exit 2
  # No edits: the snapshot is HEAD itself, so a clean tree is HEAD at its base.
  if [[ "$tree" == "$(git rev-parse "HEAD^{tree}")" ]]; then
    commit="$(git rev-parse HEAD)" || exit 2
  else
    commit="$(git -c user.name=check-affected -c user.email=check-affected@localhost \
      commit-tree "$tree" -p HEAD -m 'check-affected: uncommitted work')" || exit 2
  fi
  unset GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
  git -c init.defaultBranch=snapshot init --quiet --template= "$snap/tree" || exit 2
  printf '%s\n' "$snap/objects" "$objects" >"$snap/tree/.git/objects/info/alternates" || exit 2
  # A shallow clone's boundary, so history walks stop where the clone does.
  [[ ! -f "$shallow" ]] || cp "$shallow" "$snap/tree/.git/shallow" || exit 2
  git -C "$snap/tree" -c core.hooksPath=/dev/null checkout --quiet --detach "$commit" || exit 2
  args=(--base "$base" --no-fetch)
  ((run_tests)) && args+=(--tests)
  rc=0
  CHECK_DATA_ROOT="$snap/tree" bash "$tools/scripts/check-affected.sh" "${args[@]}" || rc=$?
  exit "$rc"
fi
base="${base:-origin/main}"
foreign=0
if [[ "$(pwd -P)" != "$tools" ]]; then
  foreign=1
  export CHECK_DATA_ROOT="$PWD"
  # uvx would otherwise read a uv.toml or [tool.uv] index from the checked tree.
  export UV_NO_CONFIG=1
fi

gates_file="$tools/scripts/check-affected-gates.txt"
declare -a passed=() skipped=() failed=()
out="$(mktemp)" || exit 2
trap 'rm -f "$out" "$out.failures"' EXIT

skip() { skipped+=("$1 ($2)"); }

# run_check <name> <reproduce-command> <command...>: a 2 from a check script
# means it could not look, which is a skip; 127 is a tool that is not there.
run_check() {
  local name="$1" repro="$2" rc=0
  shift 2
  "$@" >"$out" 2>&1 || rc=$?
  # A check that skips part of itself says so on a `SKIP <part> (<why>)` line.
  local line
  while IFS= read -r line; do
    skip "$name: ${line#SKIP }" "reported by the check"
  done < <(grep '^SKIP ' "$out")
  case "$rc" in
  0) passed+=("$name") ;;
  2 | 127) skip "$name" "could not run, exit $rc: $(tail -n 1 "$out")" ;;
  *)
    failed+=("$name")
    {
      printf '\nFAIL %s (exit %s). Reproduce: %s\n' "$name" "$rc" "$repro"
      tail -n 15 "$out"
    } >>"$out.failures"
    ;;
  esac
}

# A remote-tracking base is refreshed first, so the stale-base check compares
# against the tip a merge would land on. A failed fetch skips that check only.
fetched=1
[[ -z "${CHECK_AFFECTED_FETCH_FAILED-}" ]] || fetched=0
if ((fetch)) && [[ "$base" == */* ]]; then
  git fetch --quiet "${base%%/*}" "${base#*/}" 2>/dev/null || fetched=0
fi

merge_base="$(git merge-base HEAD "$base" 2>/dev/null)" || {
  echo "check-affected: cannot compute the merge-base of HEAD and $base" >&2
  exit 2
}
# Deleted paths still select their plugin for validate-plugins, as in CI; the
# file linters get only paths that exist.
if ! all_raw="$(git diff --name-only "$merge_base" HEAD)" ||
  ! changed_raw="$(git diff --name-only --diff-filter=d "$merge_base" HEAD)"; then
  echo "check-affected: git diff against $merge_base failed" >&2
  exit 2
fi
mapfile -t changed <<<"$changed_raw"
[[ -n "${changed[0]-}" ]] || changed=()
# Nothing changed is a pass only when HEAD is the base; otherwise the run read
# the wrong tree or range, and passing would check nothing.
if [[ -z "$all_raw" && "$(git rev-list --count "$base...HEAD")" != 0 ]]; then
  echo "check-affected: no changed files in $top since $merge_base, yet HEAD is not $base, so nothing would be checked. Run the check-affected.sh inside the tree you mean to check, or name that tree in CHECK_DATA_ROOT." >&2
  exit 2
fi

if ((${#changed[@]})) && ! git diff --quiet HEAD -- "${changed[@]}"; then
  echo "check-affected: SKIP every check (uncommitted edits to changed files; the checks read the working tree, a push sends HEAD, and CI checks the pushed commit). Commit or stash them, then rerun." >&2
  exit 0
fi

declare -a md=() sh=() py=() shebang=() plugins=()
skill_touched=0
for f in ${changed[@]+"${changed[@]}"}; do
  case "$f" in
  *.md) md+=("$f") ;;
  *.sh | *.bash) sh+=("$f") ;;
  *.py) py+=("$f") ;;
  *) ;;
  esac
  [[ -f "$f" && "$(head -c 2 "$f")" == '#!' ]] && shebang+=("$f")
done
while IFS= read -r f; do
  case "$f" in
  plugins/*/*)
    p="${f#plugins/}"
    p="${p%%/*}"
    [[ -d "plugins/$p" && " ${plugins[*]-} " != *" $p "* ]] && plugins+=("$p")
    [[ "$f" == plugins/*/skills/* ]] && skill_touched=1
    ;;
  *) ;;
  esac
done <<<"$all_raw"

if ((${#md[@]} == 0)); then
  skip markdown "no changed .md"
elif ! command -v markdownlint-cli2 >/dev/null 2>&1; then
  skip markdown "markdownlint-cli2 not installed"
elif ((foreign)); then
  # Lint HEAD's copy of each file beside only the tooling tree's configs.
  markdown_staged() {
    local stage f rc=0
    stage="$(mktemp -d)" || return 2
    while IFS= read -r f; do
      mkdir -p "$stage/${f%/*}" && cp "$tools/$f" "$stage/$f" || rc=2
    done < <(cd "$tools" && find . -name node_modules -prune -o -name .git -prune -o -name '.markdownlint*' -type f -print)
    for f in "${md[@]}"; do
      mkdir -p "$stage/$(dirname "$f")" && git show "HEAD:$f" >"$stage/$f" || rc=2
    done
    ((rc)) || (cd "$stage" && markdownlint-cli2 --config .markdownlint-cli2.jsonc "${md[@]}") || rc=$?
    rm -rf "$stage"
    return "$rc"
  }
  run_check markdown "markdownlint-cli2 --config .markdownlint-cli2.jsonc ${md[*]}" markdown_staged
else
  run_check markdown "markdownlint-cli2 --config .markdownlint-cli2.jsonc ${md[*]}" \
    markdownlint-cli2 --config .markdownlint-cli2.jsonc "${md[@]}"
fi

if ((${#sh[@]} == 0)); then
  skip shellcheck "no changed shell"
elif ! command -v shellcheck >/dev/null 2>&1; then
  skip shellcheck "shellcheck not installed"
else
  run_check shellcheck "shellcheck --rcfile .shellcheckrc ${sh[*]}" \
    shellcheck --rcfile "$tools/.shellcheckrc" "${sh[@]}"
fi

run_check shell-portability "scripts/check-shell-portability.sh $merge_base" \
  "$tools/scripts/check-shell-portability.sh" "$merge_base"

exec_bit() {
  local f mode bad=0
  for f in ${shebang[@]+"${shebang[@]}"}; do
    mode="$(git ls-files -s -- "$f" | cut -d' ' -f1)"
    [[ -z "$mode" || "$mode" == 100755 ]] && continue
    echo "$f starts with #! but is $mode in the index; run: git update-index --chmod=+x $f"
    bad=1
  done
  return "$bad"
}
run_check exec-bit "git ls-files -s -- <file> for each changed #! file" exec_bit

frag() {
  "$tools/scripts/check-changelog-fragments.sh" --check &&
    "$tools/scripts/check-changelog-fragments.sh" --check-required "$base"
}
run_check changelog-fragments \
  "scripts/check-changelog-fragments.sh --check && scripts/check-changelog-fragments.sh --check-required $base" frag

if ((fetched)); then
  run_check stale-base-overlap "scripts/check-stale-base-overlap.sh --check $base" \
    "$tools/scripts/check-stale-base-overlap.sh" --check "$base"
else
  skip stale-base-overlap "git fetch of $base failed"
fi

if ((${#plugins[@]} == 0)); then
  skip validate-plugins "no plugin changed"
elif ! command -v claude >/dev/null 2>&1; then
  skip validate-plugins "claude CLI not installed"
else
  run_check validate-plugins "scripts/validate-plugins.sh --only \"${plugins[*]}\"" \
    "$tools/scripts/validate-plugins.sh" --only "${plugins[*]}"
fi

if ((${#py[@]} == 0)); then
  skip ruff "no changed .py"
else
  run_check ruff "scripts/run-ruff.sh check ${py[*]}" "$tools/scripts/run-ruff.sh" check "${py[@]}"
fi

# typos: the exclusions mirror the `exclude:` input of the workflow's typos step
# (scripts/check-affected-gates.test.sh holds them to it). Any non-zero exit is
# a finding, never run_check's "could not run" 2; a missing binary was skipped
# above. The config is the copy's, else the checked tree's (a copy made by the
# pre-push hook carries none).
typos_check() {
  typos --config "$1" --force-exclude \
    --exclude 'plugins/*/skills/*/vendor/**' \
    --exclude 'plugins/*/tools/*/vendor/**' \
    --exclude 'plugins/testing/skills/audit/evals/judge-calibration/cases/**' \
    -- "${changed[@]}" || return 1
}
typos_config="$tools/_typos.toml"
[[ -f "$typos_config" ]] || typos_config="$PWD/_typos.toml"
if ((${#changed[@]} == 0)); then
  skip typos "no changed files"
elif ! command -v typos >/dev/null 2>&1; then
  skip typos "typos not installed"
elif [[ ! -f "$typos_config" ]]; then
  skip typos "no _typos.toml"
else
  run_check typos "typos --config _typos.toml ${changed[*]}" typos_check "$typos_config"
fi

run_check spoke-plugin-root "scripts/check-spoke-plugin-root.sh --check" \
  "$tools/scripts/check-spoke-plugin-root.sh" --check

run_check plugin-options-docs "python3 scripts/sync-plugin-options-docs.py --check" \
  python3 "$tools/scripts/sync-plugin-options-docs.py" --check

# The modes the pull_request run of the changelog-parity gates uses. The bump
# check's collision findings are advisory there too: a branch only behind its
# base trips them, and the merge queue enforces them.
parity() {
  local p="$tools/scripts/check-changelog-parity.sh"
  "$p" --check &&
    CHANGELOG_PARITY_COLLISIONS=advisory "$p" --check-bump "$base" &&
    "$p" --check-preserved "$base" &&
    "$p" --check-order
}
run_check changelog-parity \
  "scripts/check-changelog-parity.sh --check; CHANGELOG_PARITY_COLLISIONS=advisory scripts/check-changelog-parity.sh --check-bump $base; scripts/check-changelog-parity.sh --check-preserved $base; scripts/check-changelog-parity.sh --check-order" \
  parity

if ((!skill_touched)); then
  skip changed-skills "no changed skill file"
elif ((foreign)); then
  skip changed-skills "runs the checked tree's own skill-quality code"
else
  run_check changed-skills "scripts/check-changed-skills.sh $base" \
    "$tools/scripts/check-changed-skills.sh" "$base"
fi

if ((run_tests && foreign)); then
  skip tests "runs the checked tree's own test code"
elif ((run_tests)); then
  # affected-tests exits 3 when it ran every shell suite but selected suites of
  # another ecosystem it does not run; those are CI's, so that is a pass here.
  affected() {
    local rc=0
    "$tools/scripts/affected-tests.sh" --run --base "$base" || rc=$?
    ((rc == 3)) && return 0
    return "$rc"
  }
  run_check tests "scripts/affected-tests.sh --run --base $base" affected
fi

for s in ${skipped[@]+"${skipped[@]}"}; do echo "check-affected: SKIP $s" >&2; done
# Every hygiene gate CI runs that this runner does not, so none is left out
# silently. The same file is what check-affected-gates.test.sh holds to the
# workflow.
if [[ -f "$gates_file" ]]; then
  while read -r gate kind reason; do
    [[ "$kind" == ci-only ]] && echo "check-affected: CI only: $gate ($reason)" >&2
  done < <(grep -v '^[[:space:]]*\(#\|$\)' "$gates_file")
else
  echo "check-affected: SKIP the CI-only list ($gates_file is missing)" >&2
fi
if ((${#failed[@]})); then
  cat "$out.failures" >&2
  printf '\ncheck-affected: %d failed (%s), %d passed, %d skipped. Diff: %s..HEAD\n' \
    "${#failed[@]}" "${failed[*]}" "${#passed[@]}" "${#skipped[@]}" "$merge_base" >&2
  exit 1
fi
printf 'check-affected: %d passed, %d skipped over %d changed files since %s\n' \
  "${#passed[@]}" "${#skipped[@]}" "${#changed[@]}" "$merge_base"
