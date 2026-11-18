#!/usr/bin/env bash
# test-scope: plugins/bash-format/git-hooks/lefthook-remote.yml plugins/bash-format/git-hooks/entries.json plugins/bash-format/lib/git-hooks/install.mjs plugins/bash-format/git-hooks/format.sh plugins/bash-format/git-hooks/lint.sh plugins/bash-format/git-hooks/lint-full.sh .lefthook/*/bash-format-* .lefthook/remote-entry.sh lefthook-remote.yml lib/git-hooks/lefthook-remote-harness.sh .github/scripts/pr-require-checks/install-lefthook.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/git-hooks/lefthook-remote-harness.sh
. "$HERE/../../../lib/git-hooks/lefthook-remote-harness.sh"

lr_static
lr_e2e_start || lr_done
lr_require_tools shfmt shellcheck jq

printf '[*.sh]\nindent_style = space\nindent_size = 2\n' >"$REPO/.editorconfig"
printf '# ShellCheck settings of the repository\n' >"$REPO/.shellcheckrc"
git -C "$REPO" add -A
lr_commit config
lr_expect_pass "a commit of the opting-in configs passes"

printf '#!/usr/bin/env bash\nif true; then\n\techo hi\nfi\n' >"$REPO/a.sh"
git -C "$REPO" add a.sh
lr_commit format
lr_expect_pass "format: a staged unformatted script commits"
expect "format: the committed script is the formatted one" $'#!/usr/bin/env bash\nif true; then\n  echo hi\nfi' \
  "$(git -C "$REPO" show HEAD:a.sh)"

lr_skip_keeps bash-format-remote-format b.sh $'#!/usr/bin/env bash\nif true; then\n\techo b\nfi\n'

printf '#!/usr/bin/env bash\ncd /tmp\necho finished\n' >"$REPO/c.sh"
git -C "$REPO" add c.sh
lr_commit lint
lr_expect_block "lint: an added line with a shellcheck warning blocks" bash-format-remote-lint 'c.sh:2: .*SC2164'
lr_skip pre-commit bash-format-remote-lint commit

printf '#!/usr/bin/env bash\necho clean\n' >"$REPO/d.sh"
git -C "$REPO" add d.sh
lr_commit clean
lr_expect_pass "a clean formatted script passes both entries"

{
  printf '#!/usr/bin/env bash\n'
  for ((i = 1; i <= 2000; i++)); do printf 'echo %s\n' "$i"; done
} >"$REPO/big.sh"
git -C "$REPO" add big.sh
git -C "$REPO" commit -q -m big --no-verify
git -C "$REPO" push -q origin main >/dev/null 2>&1
lr_push
lr_expect_pass "lint-full: a push with no new finding passes"
printf 'cd /tmp\n' >>"$REPO/big.sh"
git -C "$REPO" commit -q -am big-finding --no-verify
lr_push
lr_expect_block "lint-full: a finding a push adds to a script over 2,000 lines blocks" bash-format-remote-lint-full 'big.sh:2002: .*SC2164'
lr_skip pre-push bash-format-remote-lint-full push

lr_done
