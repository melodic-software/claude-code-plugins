#!/usr/bin/env bash
# test-scope: plugins/code-tidying/git-hooks/lefthook-remote.yml plugins/code-tidying/git-hooks/entries.json plugins/code-tidying/lib/git-hooks/install.mjs plugins/code-tidying/git-hooks/comment-lint.sh plugins/code-tidying/git-hooks/comment-lint.py .lefthook/*/code-tidying-* .lefthook/remote-entry.sh lefthook-remote.yml lib/git-hooks/lefthook-remote-harness.sh .github/scripts/pr-require-checks/install-lefthook.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/git-hooks/lefthook-remote-harness.sh
. "$HERE/../../../lib/git-hooks/lefthook-remote-harness.sh"

lr_static
lr_e2e_start || lr_done

PY=""
while IFS= read -r candidate; do
  if "$candidate" -c 'import pygments' >/dev/null 2>&1; then
    PY="$candidate"
    break
  fi
done < <(type -ap python3)
[[ -n "$PY" ]] || lr_missing pygments "no python3 on PATH imports pygments"
mkdir -p "$WORK/py"
ln -s "$PY" "$WORK/py/python3"
export PATH="$WORK/py:$PATH"

mkdir -p "$REPO/docs/conventions"
printf 'comment_lint: block\n' >"$REPO/docs/conventions/code-tidying.yaml"
git -C "$REPO" add -A
lr_commit config
lr_expect_pass "pre-commit: a commit with no comment passes"

printf 'x=1\n# a planted note\n' >"$REPO/run.sh"
git -C "$REPO" add run.sh
lr_commit note
lr_expect_block "pre-commit: an added comment outside the posture blocks, naming the consumer's line" \
  code-tidying-remote-comment-lint '^run\.sh:2: comment outside the necessary posture'
lr_skip pre-commit code-tidying-remote-comment-lint commit

printf 'comment_lint: report\n' >"$REPO/docs/conventions/code-tidying.yaml"
printf 'y=1\n# another planted note\n' >"$REPO/two.sh"
git -C "$REPO" add -A
lr_commit report
expect "pre-commit: the consumer's report level prints and passes" "0|yes" \
  "$LR_RC|$(grep -q '^two.sh:2: comment outside' <<<"$LR_ERR" && echo yes)"

lr_done
