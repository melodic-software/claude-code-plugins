#!/usr/bin/env bash
# A git repository with a tracked team layer (one entrypoints lane), a tracked work-items file that
# sets filing_posture: allowed, and a gitignored personal override that opts out with lanes: [].
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" .git .gitignore .claude README.md docs src
git init -q
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src/api docs/conventions .claude
printf '.claude/**/*.local.*\n' >.gitignore
printf '# Service\n' >README.md
printf 'export const ping = () => "pong";\n' >src/api/ping.ts
cat >docs/conventions/bugs.yaml <<'YAML'
lanes:
  - name: entrypoints
    globs:
      - 'src/api/**/*.ts'
YAML
printf 'filing_posture: allowed\n' >docs/conventions/work-items.yaml
git add -A
git commit -q -m "chore: initial commit"
cat >.claude/bugs.local.md <<'MD'
# My bugs override

I hunt nothing on this machine for now.

```yaml
lanes: []
```
MD
