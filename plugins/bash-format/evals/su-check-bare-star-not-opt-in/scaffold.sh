#!/usr/bin/env bash
# A git repository whose .editorconfig has only a [*] section, so no section names shell files, and this
# clone declined the pre-commit entry (setup SKILL.md check steps 5, 6 and 12).
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
printf 'root = true\n\n[*]\nend_of_line = lf\ncharset = utf-8\n' >.editorconfig
git add .
git commit -q -m "chore: init"
