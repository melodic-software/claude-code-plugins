#!/usr/bin/env bash
# set-diff-target.sh: the post-merge mutation lane's "Set the diff target"
# step, shared by its six model legs. Run with bash from the workspace root,
# with BEFORE and AFTER from the prep job. The pushed head must be on main;
# the diff target is the push's previous head, or the head's first parent
# when the push had none (a first push or a rewrite), said as a warning. It
# writes the gitignored diff-target settings file the mutation-testing plugin
# reads, checks the tree is clean, and writes mode and target to
# GITHUB_OUTPUT. errexit and pipefail match the step shell it replaces (the
# workflow's `shell: bash`).
# shellcheck disable=SC2154 # the step env sets BEFORE and AFTER, and the runner GITHUB_OUTPUT
set -eo pipefail

git merge-base --is-ancestor "$AFTER" refs/remotes/origin/main ||
  {
    echo "::error::the pushed head $AFTER is not on main"
    exit 1
  }
if [[ -n $BEFORE ]] && git cat-file -e "$BEFORE^{commit}" 2>/dev/null; then
  target=$BEFORE mode=range
else
  target=$(git rev-parse "$AFTER^") || {
    echo "::error::the head has no parent to diff against"
    exit 1
  }
  mode=commit
  echo "::warning::no usable previous head; mutating only the head commit $AFTER"
fi
printf '.base/\n.lane/\nmutation-data/\n' >>.git/info/exclude
# shellcheck disable=SC2016 # the backticks are the markdown fence
printf '# Written by post-merge-test-mutation.yml.\n\n```yaml\ndiff-target: %s\n```\n' "$target" \
  >.claude/mutation-testing.local.md
[[ -z "$(git status --porcelain)" ]] || {
  echo "::error::the checkout is not clean before the audit"
  exit 1
}
{
  echo "mode=$mode"
  echo "target=$target"
} >>"$GITHUB_OUTPUT"
