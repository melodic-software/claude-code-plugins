#!/usr/bin/env bash
# A git repository where a section names shell files and .gitignore covers .work/, with an untracked
# .work/scratch.sh, and this clone declined the pre-commit entry (setup SKILL.md check steps 6, 11 and 12).
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
printf '.work/\n' >.gitignore
mkdir -p .work
printf '#!/usr/bin/env bash\nif true;then echo scratch;fi\n' >.work/scratch.sh
git add .
git commit -q -m "chore: init"
