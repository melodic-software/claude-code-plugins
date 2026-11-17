#!/usr/bin/env bash
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.bash-format.format.declined true
git config --local checks.bash-format.lint.declined true
printf '#!/usr/bin/env bash\necho hello\n' >demo.sh
git add .
git commit -q -m "chore: init"
