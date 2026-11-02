#!/usr/bin/env bash
# Run the diff-scoped lint checks CI runs, over what this branch changed, before
# a push spends a CI round on them. One entrypoint, so a person, an agent and the
# pre-push hook (.claude/hooks/check-affected-pre-push.sh) all run the same set.
#
#   scripts/check-affected.sh                 the lint checks
#   scripts/check-affected.sh --tests         ... and scripts/affected-tests.sh --run
#   scripts/check-affected.sh --jobs N        run up to N selected shell suites at
#                                             once (default: $CHECK_AFFECTED_JOBS,
#                                             else one less than the core count,
#                                             at most 8 and at most one per 2 GiB
#                                             of free memory)
#   scripts/check-affected.sh --budget S      time the selected shell suites against
#                                             an S-second budget (default:
#                                             $CHECK_AFFECTED_BUDGET, else 120); a
#                                             suite over its share is a warning,
#                                             not a failure
#                                             (scripts/run-plugin-tests.sh BUDGET)
#   scripts/check-affected.sh --base <ref>    diff against <ref> (default: origin/main)
#   scripts/check-affected.sh --no-fetch      skip refreshing <ref> before the
#                                             run resolves it to a commit
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
# file executable, as apply-patch will. --tests runs the suites from this tree,
# whose work tree holds the same edits, not the scratch one, which has no
# node_modules.
#
# Each check calls the script or tool CI calls; none restates a check's logic
# but machine-specific-paths, whose entry script is in ci-workflows, not here:
# it repeats that script's scan and exemptions over the same patterns file.
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
#   - comment-hygiene:     scripts/check-comment-hygiene.sh <merge-base> on the
#                          changed files, which runs the pinned ci-workflows
#                          action's own patterns library over their comments
#   - machine-specific-paths: the check-machine-paths composite's scan, git grep
#                          of each regex body in the guardrails plugin's
#                          machine-path-patterns.sh, on the changed files
#   - spoke-plugin-root:   scripts/check-spoke-plugin-root.sh --check
#   - plugin-options-docs: python3 scripts/sync-plugin-options-docs.py --check
#   - changelog-parity:    scripts/check-changelog-parity.sh in the --check,
#                          --check-bump, --check-preserved and --check-order
#                          modes the pull_request run uses
#   - changed-skills:      scripts/check-changed-skills.sh <base>, when a skill
#                          file changed; without --tests it sets
#                          CHECK_SKILL_SKIP_SCRIPT_TESTS=1, so the skills'
#                          scripts/*.test.sh are left to the test tier
#   - tests (--tests):     scripts/affected-tests.sh --run --jobs <N>
#                          --budget <S> --base <base>, after
#                          scripts/setup-env.sh --node installs any missing or
#                          stale locked npm packages, then the selected Node
#                          suites of scripts/outside-node-packages.txt through
#                          scripts/run-outside-node-suites.sh --paths; any
#                          other selected suite left unrun makes tests a SKIP
#
# validate-plugins, changed-skills and tests are the slow checks; they run last,
# and only when every other check passed. When one of those failed they are
# SKIPs naming that, so a static finding is reported at once.
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
# reads the copy's configs plus each branch config the copy proves is data (a
# branch config can load a custom rule, which is code, so any other is refused),
# and checks that run the branch's own code skip: --tests, changed-skills, and the
# validate-plugins steps that report `SKIP` themselves. plugin-options-docs
# skips when the branch changes its generator, whose output the copy's older
# generator would reject.
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
  echo "usage: $(basename "$0") [--tests] [--jobs N] [--budget S] [--base <ref>] [--no-fetch] [--uncommitted]" >&2
  exit 2
}

run_tests=0
# The selected suites run through run-plugin-tests.sh's job pool, which keeps
# the suites in scripts/run-plugin-tests-serial.txt off the parallel group.
# One less than the core count: on a 4-vCPU runner, 3 is the proven ceiling
# (scripts/affected-tests.sh, #3694). At most 8: past 8 the wall time is the
# longest suite's (#10534), and on a host where several sessions run suites at
# once, 23 jobs failed suites that passed at 4 and 6 (#10719). At most one per
# 2 GiB of free memory: a browser suite needs about that (8 planning surface
# jobs peaked at 15 GiB and the kernel killed chrome at the session slice's
# cap). Free memory is MemAvailable, or less where a cgroup above this shell
# caps it: its memory.max less memory.current, inactive file cache counted free.
# Every ancestor is read: a cgroup whose parent does not delegate the memory
# controller has no memory.* files, yet the parent's cap still applies to it.
mem_free_kib() {
  local free dir="${CHECK_AFFECTED_CGROUP_DIR:-/sys/fs/cgroup$(sed -n 's/^0:://p' /proc/self/cgroup 2>/dev/null)}" max cur inactive
  free="$(awk '/^MemAvailable:/ { print $2 }' "${CHECK_AFFECTED_MEMINFO:-/proc/meminfo}" 2>/dev/null)"
  [[ "$free" =~ ^[0-9]+$ ]] || return 1
  while [[ -n "$dir" ]]; do
    if [[ -r "$dir/memory.max" && -r "$dir/memory.current" ]]; then
      max="$(<"$dir/memory.max")" cur="$(<"$dir/memory.current")"
      inactive="$(awk '$1 == "inactive_file" { print $2 }' "$dir/memory.stat" 2>/dev/null)"
      if [[ "$max" =~ ^[0-9]+$ && "$cur" =~ ^[0-9]+$ ]]; then
        cur=$(((max - cur + ${inactive:-0}) / 1024))
        ((cur >= free)) || free=$((cur > 0 ? cur : 0))
      fi
    fi
    [[ "${dir%/*}" != "$dir" ]] || break
    dir="${dir%/*}"
  done
  echo "$free"
}
cores="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
[[ "$cores" =~ ^[1-9][0-9]*$ ]] || cores=2
jobs=$((cores > 1 ? cores - 1 : 1))
((jobs <= 8)) || jobs=8
if free_kib="$(mem_free_kib)"; then
  mem_jobs=$((free_kib / (2 * 1024 * 1024)))
  ((mem_jobs >= 1)) || mem_jobs=1
  ((jobs <= mem_jobs)) || jobs=$mem_jobs
fi
jobs="${CHECK_AFFECTED_JOBS:-$jobs}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || jobs=1
budget="${CHECK_AFFECTED_BUDGET:-120}"
[[ "$budget" =~ ^[1-9][0-9]*$ ]] || budget=120
fetch=1
uncommitted=0
base=
while (($#)); do
  case "$1" in
  --tests) run_tests=1 ;;
  --no-fetch) fetch=0 ;;
  --uncommitted) uncommitted=1 ;;
  --jobs)
    [[ $# -ge 2 ]] || usage
    jobs="$2"
    shift
    ;;
  --jobs=*) jobs="${1#--jobs=}" ;;
  --budget)
    [[ $# -ge 2 ]] || usage
    budget="$2"
    shift
    ;;
  --budget=*) budget="${1#--budget=}" ;;
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
[[ "$jobs" =~ ^[1-9][0-9]*$ && "$budget" =~ ^[1-9][0-9]*$ ]] || usage

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
  args=(--base "$base" --no-fetch --jobs "$jobs" --budget "$budget")
  ((run_tests)) && args+=(--tests)
  # A snapshot of this tree's own work tree is no foreign code, so the inner
  # run's tests run here, where the selector reads the same uncommitted edits.
  own=
  [[ "$(pwd -P)" != "$tools" ]] || own="$tools"
  rc=0
  CHECK_AFFECTED_SNAPSHOT_OF="$own" CHECK_DATA_ROOT="$snap/tree" bash "$tools/scripts/check-affected.sh" "${args[@]}" || rc=$?
  exit "$rc"
fi
base="${base:-origin/main}"
snapshot=0
[[ -z "${CHECK_AFFECTED_SNAPSHOT_OF-}" || "$CHECK_AFFECTED_SNAPSHOT_OF" != "$tools" ]] || snapshot=1
unset CHECK_AFFECTED_SNAPSHOT_OF
foreign=0
if [[ "$(pwd -P)" != "$tools" ]]; then
  foreign=1
  export CHECK_DATA_ROOT="$PWD"
  # uvx would otherwise read a uv.toml or [tool.uv] index from the checked tree.
  export UV_NO_CONFIG=1
else
  # It names this tree, so it says nothing; the test suites build fixture
  # repositories, and an inherited one would point them back here.
  unset CHECK_DATA_ROOT
fi

gates_file="$tools/scripts/check-affected-gates.txt"
declare -a passed=() skipped=() failed=()
out="$(mktemp)" || exit 2
trap 'rm -f "$out" "$out.failures" "$out.patterns" "$out.not-run" "$out.node"' EXIT

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
# Then resolved to a commit once, so every check judges the base the run
# started from: every worktree shares the remote-tracking refs, and another
# session's fetch can move one mid-run. Later drift is CI's and the merge queue's.
base_name="$base"
base="$(git rev-parse --verify --quiet "$base^{commit}")" || {
  echo "check-affected: cannot compute the merge-base of HEAD and $base_name: it names no commit" >&2
  exit 2
}

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
  echo "check-affected: no changed files in $top since $merge_base, yet HEAD is not $base_name, so nothing would be checked. Run the check-affected.sh inside the tree you mean to check, or name that tree in CHECK_DATA_ROOT." >&2
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
  # Lint HEAD's copy of each file beside the tooling tree's configs, overlaid
  # with each markdownlint config the branch changed that the tooling tree's
  # scripts/lib/markdownlint-config-data.mjs proves is data. Any other changed
  # config is refused with a SKIP line saying why, leaving the tooling tree's.
  markdown_staged() {
    local stage f kind mode data rc=0
    stage="$(mktemp -d)" || return 2
    while IFS= read -r f; do
      mkdir -p "$stage/${f%/*}" && cp "$tools/$f" "$stage/$f" || rc=2
    done < <(cd "$tools" && find . -name node_modules -prune -o -name .git -prune -o -name '.markdownlint*' -type f -print)
    for f in ${changed[@]+"${changed[@]}"}; do
      case "${f##*/}" in
      .markdownlint-cli2.jsonc) kind=options ;;
      .markdownlint.jsonc | .markdownlint.json) kind=config ;;
      .markdownlint*)
        echo "SKIP config $f (refused: only .markdownlint-cli2.jsonc, .markdownlint.jsonc and .markdownlint.json are read as data)"
        continue
        ;;
      *) continue ;;
      esac
      mode="$(git ls-tree HEAD -- "$f" | cut -d' ' -f1)"
      if [[ "$mode" != 100644 && "$mode" != 100755 ]]; then
        echo "SKIP config $f (refused: not a regular file)"
      elif data="$(git show "HEAD:$f" | node "$tools/scripts/lib/markdownlint-config-data.mjs" "$kind")"; then
        mkdir -p "$stage/$(dirname "$f")" && printf '%s\n' "$data" >"$stage/$f" || rc=2
      else
        echo "SKIP config $f (refused: ${data:-the data check could not run})"
      fi
    done
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
  skip stale-base-overlap "git fetch of $base_name failed"
fi

if ((${#py[@]} == 0)); then
  skip ruff "no changed .py"
else
  run_check ruff "scripts/run-ruff.sh check ${py[*]}" "$tools/scripts/run-ruff.sh" check "${py[@]}"
fi

# typos: the exclusions are the `exclude:` input of the checked tree's
# workflow typos step, read as data, so a branch that exempts files is judged
# by its own exemption; no workflow or no globs fails closed. Any non-zero exit
# is a finding, never run_check's "could not run" 2; a missing binary was
# skipped above. The config is the copy's, else the checked tree's (a copy made
# by the pre-push hook carries none).
typos_check() {
  local workflow=.github/workflows/pr-require-checks.yml g
  local -a excludes=()
  if [[ ! -f "$workflow" ]]; then
    echo "typos: $workflow is missing, so its typos step's exclude globs cannot be read"
    return 1
  fi
  # The scan covers only the typos step: its keys sit at the indent of its
  # `id: typos` line, and the first non-blank line indented less ends the step.
  while IFS= read -r g; do excludes+=(--exclude "$g"); done < <(
    awk 'ind { match($0, /^ */); if (NF && RLENGTH < ind) exit }
      /^ *(- )?id: typos$/ { match($0, /^ *(- )?/); ind = RLENGTH; next }
      ind && /^ *exclude: / { sub(/^ *exclude: /, ""); n = split($0, a, " "); for (i = 1; i <= n; i++) print a[i]; exit }' "$workflow"
  )
  if [[ "${excludes[1]-}" == ['>|']* ]]; then
    echo "typos: $workflow writes its typos step's exclude as a YAML block scalar (${excludes[1]}); write the globs on the exclude: line itself"
    return 1
  fi
  if ((${#excludes[@]} == 0)); then
    echo "typos: $workflow has no exclude globs on its typos step (id: typos)"
    return 1
  fi
  typos --config "$1" --force-exclude "${excludes[@]}" -- "${changed[@]}" || return 1
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

# comment-hygiene: the patterns come from the ci-workflows SHA the merge-base's
# workflow pins, fetched on each run; a failed fetch is the script's exit 2, a
# SKIP with its reason. Run through bash, so a copy without the exec bit runs.
if ((${#changed[@]} == 0)); then
  skip comment-hygiene "no changed files"
else
  run_check comment-hygiene "bash scripts/check-comment-hygiene.sh $merge_base ${changed[*]}" \
    bash "$tools/scripts/check-comment-hygiene.sh" "$merge_base" "${changed[@]}"
fi

# machine-specific-paths: the scan the workflow's check-machine-paths composite
# (melodic-software/ci-workflows) runs, over the changed files of the types it
# scans. The regex bodies come from the merge-base's guardrails plugin copy of
# the patterns file the composite sources; no second copy of them is written
# here. The exclusions mirror the `exclude:` input of the workflow's
# machine-paths step, and the types are the composite's default `extensions`
# input, which that step does not override (scripts/check-affected-gates.test.sh
# holds both to the workflow). The boundary, the five scans and the exemptions
# repeat the composite's entry script as read at ci-workflows v0.65.17
# (81a603a6e2b0319428c981bf28f3fe923032afb2); recheck them when the pin moves.
machine_paths_lib=plugins/guardrails/lib/path-detection/machine-path-patterns.sh
machine_paths_excludes=(
  ':(exclude)plugins/guardrails/lib/path-detection/**'
  ':(exclude)plugins/autonomy/skills/setup/evals/fixtures/security-binding/**'
  ':(exclude)plugins/autonomy/skills/setup/scripts/check-security-binding.fixtures.test.manifest.json'
  ':(exclude)plugins/harness-config/skills/audit-permission-state/reference/criteria.md'
  ':(exclude)plugins/harness-config/skills/audit-permission-state/scripts/permission-plane-lint.sh'
  ':(exclude)plugins/harness-config/skills/audit-permission-state/scripts/permission-plane-lint.test.sh'
  ':(exclude)plugins/harness-config/skills/audit-permission-state/scripts/automode-entry-diff.test.sh'
  ':(exclude)plugins/source-control/scripts/worktree-create.test.sh'
)
read -ra machine_paths_types <<<'*.cs *.csproj *.json *.jsonc *.js *.jsx *.md *.props *.ps1 *.psm1 *.py *.sh *.slnx *.targets *.toml *.ts *.tsx *.yaml *.yml'
declare -a machine_paths_files=()
for f in ${changed[@]+"${changed[@]}"}; do
  for g in "${machine_paths_types[@]}"; do
    # shellcheck disable=SC2053 # $g is a glob on purpose.
    if [[ "$f" == $g ]]; then
      # literal, so a name holding * or a leading : is that file alone.
      machine_paths_files+=(":(literal)$f")
      break
    fi
  done
done

# machine_paths_load: defines the HPP_* regex bodies from the merge-base's
# patterns file. Sourcing runs it, and the pre-push hook's TOOLING list does not
# name it, so the branch's own copy is never the one loaded; CI scans with
# ci-workflows' copy, not this tree's, either way.
machine_paths_load() {
  git show "$merge_base:$machine_paths_lib" >"$out.patterns" 2>/dev/null || return 1
  # shellcheck source=../plugins/guardrails/lib/path-detection/machine-path-patterns.sh
  . "$out.patterns" || return 1
  [[ -n "${HPP_WIN_USER_BODY-}" && -n "${HPP_MACOS_USER_BODY-}" && -n "${HPP_LINUX_USER_BODY-}" &&
    -n "${HPP_WIN_REPO_BODY-}" && -n "${HPP_ESCAPED_WIN_REPO_BODY-}" ]]
}

# machine_paths_exempt <pattern> <macos> <content>: 0 when the line holds a
# span and every span is a placeholder, a last segment of punctuation or an
# ellipsis alone (`<user>` never matches), or, under the macOS body, the
# shared folder of /Users ending a sentence. A line with no span is a finding,
# as in CI.
machine_paths_exempt() {
  local span child rest trimmed n=0
  while IFS= read -r span; do
    [[ -n "$span" ]] || continue
    n=$((n + 1))
    child="${span##*[/\\]}"
    rest="$(printf '%s' "$child" | LC_ALL=C tr -d '[:punct:]')" || return 1
    rest="${rest//$'\342\200\246'/}"
    [[ -n "$child" && -z "$rest" ]] && continue
    if [[ "$2" == 1 ]]; then
      trimmed="$(printf '%s\n' "$child" | LC_ALL=C sed 's/[^A-Za-z0-9._-]*$//')" || return 1
      [[ "${trimmed%.}" == Shared ]] && continue
    fi
    return 1
  done < <(printf '%s\n' "$3" | grep -oE -- "$1")
  ((n))
}

# machine_paths_scan <label> <macos> <pattern>: prints each changed line the
# pattern finds that no exemption covers; 0 none, 1 some, 2 git grep failed.
machine_paths_scan() {
  local matches line content rc=0 found=0
  matches="$(git grep -nIE -e "$3" -- "${machine_paths_files[@]}" "${machine_paths_excludes[@]}")" || rc=$?
  ((rc <= 1)) || return 2
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    content="${line#*:*:}"
    if [[ "$content" != "$line" ]]; then
      [[ "$content" == *machine-path:allow* ]] && continue
      machine_paths_exempt "$3" "$2" "$content" && continue
    fi
    echo "$1: $line"
    found=1
  done <<<"$matches"
  return "$found"
}

# machine_paths_check: the composite's five scans, in its order. The
# slash-rooted bodies take its boundary prefix; the Windows ones anchor on the
# drive letter.
machine_paths_check() {
  local boundary i rc found=0 errored=0
  boundary=$'(^|[[:space:]"\'`(=]|file://)'
  local -a labels=("Windows user path" "macOS user path" "Linux user path" "Windows repo path" "Escaped Windows repo path")
  local -a patterns=("$HPP_WIN_USER_BODY" "$boundary$HPP_MACOS_USER_BODY" "$boundary$HPP_LINUX_USER_BODY"
    "$HPP_WIN_REPO_BODY" "$HPP_ESCAPED_WIN_REPO_BODY")
  for i in "${!labels[@]}"; do
    rc=0
    machine_paths_scan "${labels[i]}" "$((i == 1))" "${patterns[i]}" || rc=$?
    case "$rc" in
    0) ;;
    1) found=1 ;;
    *)
      echo "${labels[i]}: git grep failed"
      errored=1
      ;;
    esac
  done
  # A finding outranks a scan that could not run, so one never hides the other.
  if ((found)); then
    echo "Use portable placeholders (<repo-root>, <user>) or relative paths, or mark the line machine-path:allow."
    return 1
  fi
  ((errored)) && return 2
  return 0
}

if ((${#machine_paths_files[@]} == 0)); then
  skip machine-specific-paths "no changed file of a type it scans"
elif ! machine_paths_load; then
  skip machine-specific-paths "no loadable $machine_paths_lib at the merge-base"
else
  run_check machine-specific-paths "scripts/check-affected.sh --base $base" machine_paths_check
fi

run_check spoke-plugin-root "scripts/check-spoke-plugin-root.sh --check" \
  "$tools/scripts/check-spoke-plugin-root.sh" --check

# The generator writes the READMEs, so a copy's older generator fails a branch
# that changes it and regenerates them.
if ((foreign)) && grep -qx scripts/sync-plugin-options-docs.py <<<"$all_raw"; then
  skip plugin-options-docs "the branch changes the generator; CI runs the branch's copy"
else
  run_check plugin-options-docs "python3 scripts/sync-plugin-options-docs.py --check" \
    python3 "$tools/scripts/sync-plugin-options-docs.py" --check
fi

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

# The slow checks (a plugin validation, a skill-quality run, the suites) run only
# when every check above passed: a static finding is already a failed run, and
# its report should not wait minutes on them.
halt=${#failed[@]}
halt_why="a static check failed above"

if ((halt)); then
  skip validate-plugins "$halt_why"
elif ((${#plugins[@]} == 0)); then
  skip validate-plugins "no plugin changed"
elif ! command -v claude >/dev/null 2>&1; then
  skip validate-plugins "claude CLI not installed"
else
  run_check validate-plugins "scripts/validate-plugins.sh --only \"${plugins[*]}\"" \
    "$tools/scripts/validate-plugins.sh" --only "${plugins[*]}"
fi

if ((halt)); then
  skip changed-skills "$halt_why"
elif ((!skill_touched)); then
  skip changed-skills "no changed skill file"
elif ((foreign)); then
  skip changed-skills "runs the checked tree's own skill-quality code"
elif ((run_tests)); then
  run_check changed-skills "scripts/check-changed-skills.sh $base" \
    "$tools/scripts/check-changed-skills.sh" "$base"
else
  # The lint tier leaves each skill's scripts/*.test.sh to --tests and CI's test lanes.
  run_check changed-skills "CHECK_SKILL_SKIP_SCRIPT_TESTS=1 scripts/check-changed-skills.sh $base" \
    env CHECK_SKILL_SKIP_SCRIPT_TESTS=1 "$tools/scripts/check-changed-skills.sh" "$base"
fi

if ((run_tests && halt)); then
  skip tests "$halt_why"
elif ((run_tests && foreign && !snapshot)); then
  skip tests "runs the checked tree's own test code"
elif ((run_tests)); then
  # Suites load the locked npm packages, which a fresh worktree lacks or a
  # lockfile change leaves stale, so setup-env installs them first; it skips a
  # current install. A failed install fails the run and runs no suite; one that
  # could not run (npm or nice missing) is a SKIP, and the suites still run.
  npm_failed=0
  rc=0
  bash "$tools/scripts/setup-env.sh" --node --root "$tools" >"$out" 2>&1 || rc=$?
  if ((rc == 0)); then
    grep '^setup-env: installed' "$out" >&2
  elif ((rc == 2 || rc == 127)); then
    skip npm-deps "could not run, exit $rc: $(tail -n 1 "$out")"
  else
    npm_failed=1
    failed+=(npm-deps)
    {
      printf '\nFAIL npm-deps (exit %s). Reproduce: bash scripts/setup-env.sh --node\n' "$rc"
      tail -n 15 "$out"
    } >>"$out.failures"
  fi
  # affected-tests exits 3 when it ran every shell suite it selected but also
  # selected suites it does not run, which it writes to the --write-not-run
  # file. One under a package of scripts/outside-node-packages.txt runs here as
  # CI's test-node lane runs it, through run-outside-node-suites.sh and the
  # package's own npm test, and a failing one fails tests. A Node suite beside
  # a <stem>.test.sh ran through that wrapper (affected-tests' rule R9), and a
  # path under scripts/outside-node-exclusions.txt is no suite. Any other is
  # left to its own CI lane, so tests is a SKIP counting it, never a pass:
  # exit 2, whose last line run_check puts in the skip.
  affected() {
    local rc=0 s pkg ex t n=0 missing=
    local -a pkgs=() exclusions=() node=() unrun=()
    # Suites run only when the data tree is this tree, so CHECK_DATA_ROOT adds nothing here, and a suite
    # that inherits it points its checkers at the real tree instead of its fixtures.
    # A suite that passes on a loaded host but runs past its share is a warning here.
    env -u CHECK_DATA_ROOT PLUGIN_TEST_SHARE_WARN_ONLY=1 "$tools/scripts/affected-tests.sh" --run --jobs "$jobs" --budget "$budget" --base "$base" --write-not-run "$out.not-run" || rc=$?
    ((rc == 3)) || return "$rc"
    # shellcheck source=lib/read-list.sh
    . "$tools/scripts/lib/read-list.sh" &&
      read_list::into pkgs "$tools/scripts/outside-node-packages.txt" --comments inline &&
      read_list::into exclusions "$tools/scripts/outside-node-exclusions.txt" --comments inline || return 2
    while IFS= read -r s; do
      [[ -n "$s" ]] || continue
      n=$((n + 1))
      for ex in ${exclusions[@]+"${exclusions[@]}"}; do
        [[ "$s" == "$ex"* ]] && continue 2
      done
      for pkg in ${pkgs[@]+"${pkgs[@]}"}; do
        if [[ "$s" == "$pkg"/* ]]; then
          node+=("$s")
          continue 2
        fi
      done
      case "$s" in
      *.test.js | *.test.mjs) [[ -f "${s%.test.*}.test.sh" ]] && continue ;;
      *) ;;
      esac
      unrun+=("$s")
    done <"$out.not-run"
    if ((n == 0)); then
      echo "affected-tests exited 3 but named no unrun suite"
      return 2
    fi
    if ((${#node[@]})); then
      for t in npm jq; do
        command -v "$t" >/dev/null 2>&1 || missing+="${missing:+, }$t"
      done
    fi
    if [[ -n "$missing" ]]; then
      unrun+=("${node[@]}")
    elif ((${#node[@]})); then
      printf '%s\n' "${node[@]}" >"$out.node" || return 2
      bash "$tools/scripts/run-outside-node-suites.sh" --paths "$out.node" || return
    fi
    if ((${#unrun[@]})); then
      printf 'not run here: %s\n' "${unrun[@]}"
      echo "${#unrun[@]} selected suite(s) not run here, left to their own CI lanes${missing:+ ($missing not installed)}"
      return 2
    fi
  }
  if ((npm_failed)); then
    skip tests "npm dependencies did not install"
  else
    run_check tests "scripts/affected-tests.sh --run --jobs $jobs --budget $budget --base $base" affected
  fi
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
