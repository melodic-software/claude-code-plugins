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
#
# Each check calls the script or tool CI calls; none restates a check's logic.
# The changed set is <merge-base of HEAD and the base>..HEAD, committed work
# only, because that is what a push sends.
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
#   - tests (--tests):     scripts/affected-tests.sh --run --base <base>
#
# CI is still the gate that decides: this covers the diff-scoped LINT tier, not
# CI's whole-repo scanners, and it does not widen shellcheck to the files that
# source a changed library the way CI's lint-shell job does.
#
# A missing tool, a failed fetch, or a check that exits 2 (could not run) is a
# SKIP with its reason, never a failure. Exit 0 every check passed or skipped;
# 1 a check failed, with each failure and its reproduce command on stderr; 2
# usage or a git state the changed set cannot be read from. That is the
# check-script family contract stated in README.md.
set -uo pipefail

usage() {
  echo "usage: $(basename "$0") [--tests] [--base <ref>] [--no-fetch]" >&2
  exit 2
}

run_tests=0
fetch=1
base=origin/main
while (($#)); do
  case "$1" in
  --tests) run_tests=1 ;;
  --no-fetch) fetch=0 ;;
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

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "check-affected: not inside a git work tree" >&2
  exit 2
fi
cd "$(git rev-parse --show-toplevel)" || exit 2

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
if ((fetch)) && [[ "$base" == */* ]]; then
  git fetch --quiet "${base%%/*}" "${base#*/}" 2>/dev/null || fetched=0
fi

merge_base="$(git merge-base HEAD "$base" 2>/dev/null)" || {
  echo "check-affected: cannot compute the merge-base of HEAD and $base" >&2
  exit 2
}
changed_raw="$(git diff --name-only --diff-filter=d "$merge_base" HEAD)" || {
  echo "check-affected: git diff against $merge_base failed" >&2
  exit 2
}
mapfile -t changed <<<"$changed_raw"
[[ -n "${changed[0]-}" ]] || changed=()

declare -a md=() sh=() py=() shebang=() plugins=()
for f in ${changed[@]+"${changed[@]}"}; do
  case "$f" in
  *.md) md+=("$f") ;;
  *.sh | *.bash) sh+=("$f") ;;
  *.py) py+=("$f") ;;
  *) ;;
  esac
  case "$f" in
  plugins/*/*)
    p="${f#plugins/}"
    p="${p%%/*}"
    [[ -d "plugins/$p" && " ${plugins[*]-} " != *" $p "* ]] && plugins+=("$p")
    ;;
  *) ;;
  esac
  [[ -f "$f" && "$(head -c 2 "$f")" == '#!' ]] && shebang+=("$f")
done

if ((${#md[@]} == 0)); then
  skip markdown "no changed .md"
elif ! command -v markdownlint-cli2 >/dev/null 2>&1; then
  skip markdown "markdownlint-cli2 not installed"
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
    shellcheck --rcfile .shellcheckrc "${sh[@]}"
fi

run_check shell-portability "scripts/check-shell-portability.sh $merge_base" \
  scripts/check-shell-portability.sh "$merge_base"

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
  scripts/check-changelog-fragments.sh --check &&
    scripts/check-changelog-fragments.sh --check-required "$base"
}
run_check changelog-fragments \
  "scripts/check-changelog-fragments.sh --check && scripts/check-changelog-fragments.sh --check-required $base" frag

if ((fetched)); then
  run_check stale-base-overlap "scripts/check-stale-base-overlap.sh --check $base" \
    scripts/check-stale-base-overlap.sh --check "$base"
else
  skip stale-base-overlap "git fetch of $base failed"
fi

if ((${#plugins[@]} == 0)); then
  skip validate-plugins "no plugin changed"
elif ! command -v claude >/dev/null 2>&1; then
  skip validate-plugins "claude CLI not installed"
else
  run_check validate-plugins "scripts/validate-plugins.sh --only \"${plugins[*]}\"" \
    scripts/validate-plugins.sh --only "${plugins[*]}"
fi

if ((${#py[@]} == 0)); then
  skip ruff "no changed .py"
else
  run_check ruff "scripts/run-ruff.sh check ${py[*]}" scripts/run-ruff.sh check "${py[@]}"
fi

if ((run_tests)); then
  # affected-tests exits 3 when it ran every shell suite but selected suites of
  # another ecosystem it does not run; those are CI's, so that is a pass here.
  affected() {
    local rc=0
    scripts/affected-tests.sh --run --base "$base" || rc=$?
    ((rc == 3)) && return 0
    return "$rc"
  }
  run_check tests "scripts/affected-tests.sh --run --base $base" affected
fi

for s in ${skipped[@]+"${skipped[@]}"}; do echo "check-affected: SKIP $s" >&2; done
if ((${#failed[@]})); then
  cat "$out.failures" >&2
  printf '\ncheck-affected: %d failed (%s), %d passed, %d skipped. Diff: %s..HEAD\n' \
    "${#failed[@]}" "${failed[*]}" "${#passed[@]}" "${#skipped[@]}" "$merge_base" >&2
  exit 1
fi
printf 'check-affected: %d passed, %d skipped over %d changed files since %s\n' \
  "${#passed[@]}" "${#skipped[@]}" "${#changed[@]}" "$merge_base"
