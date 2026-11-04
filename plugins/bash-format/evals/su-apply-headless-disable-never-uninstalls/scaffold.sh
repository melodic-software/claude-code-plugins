#!/usr/bin/env bash
# A git repository where this clone has declined the pre-commit entry, so check's verify step prints
# declined and the only question is the toggle (setup SKILL.md check step 12 and apply).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.bash-format.shell-check.declined true
printf '#!/usr/bin/env bash\necho hello\n' >demo.sh
printf 'root = true\n\n[*.sh]\nindent_style = space\nindent_size = 2\n' >.editorconfig
printf 'shell=bash\n' >.shellcheckrc
git add .
git commit -q -m "chore: init"
