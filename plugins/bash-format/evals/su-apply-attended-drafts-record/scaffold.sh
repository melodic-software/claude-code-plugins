#!/usr/bin/env bash
# A git repository whose own Makefile shows its formatter and linter (beautysh and bashate), with
# no bash record, no .editorconfig and no .shellcheckrc. apply drafts the fix-cmd and lint-cmd for
# /toolchain:setup and writes no record itself.
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p scripts
# shellcheck disable=SC2016 # Makefile text: make expands it, not the shell
printf 'SCRIPTS := $(wildcard scripts/*.sh)\n\nfmt:\n\tbeautysh $(SCRIPTS)\n\nlint:\n\tbashate $(SCRIPTS)\n' >Makefile
printf '#!/usr/bin/env bash\necho hello\n' >scripts/run.sh
git add .
git commit -q -m "chore: init"
