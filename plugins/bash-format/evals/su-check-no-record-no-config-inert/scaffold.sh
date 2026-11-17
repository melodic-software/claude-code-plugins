#!/usr/bin/env bash
# A git repository with shell scripts, no bash record, no .editorconfig and no .shellcheckrc, so
# both concerns resolve to nothing: the plugin is inert by design.
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p scripts
printf '#!/usr/bin/env bash\necho hello\n' >scripts/run.sh
git add .
git commit -q -m "chore: init"
