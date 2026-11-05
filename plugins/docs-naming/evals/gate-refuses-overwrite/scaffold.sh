#!/usr/bin/env bash
# Seeds a git repo with a docs-naming team config and an older, hand-edited
# file-name checker already in scripts/, with no suite beside it.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p docs/conventions scripts
cat >docs/conventions/docs-naming.yaml <<'YAML'
# File-name convention for the docs tree.
roots:
  - "docs"
rule: "lower-kebab"
YAML
printf '# Harbor\n\nShipment tracking service.\n' >README.md
printf '# Getting started\n\nInstall and run the service.\n' >docs/getting-started.md
printf '# API reference\n\nEndpoints for shipments.\n' >docs/api-reference.md
cat >scripts/check-file-names.sh <<'SH'
#!/usr/bin/env bash
# File-name gate for docs/. Local change: also skips docs/vendor/.
set -euo pipefail
status=0
while IFS= read -r path; do
  case "$path" in docs/vendor/*) continue ;; esac
  base="${path##*/}"
  [[ "$base" == README.md ]] && continue
  if ! grep -Eq '^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$' <<<"$base"; then
    printf '%s: basename is not lower-kebab\n' "$path" >&2
    status=1
  fi
done < <(git ls-files docs)
exit "$status"
SH
chmod +x scripts/check-file-names.sh

git add -A
git commit -q -m "chore: seed"
