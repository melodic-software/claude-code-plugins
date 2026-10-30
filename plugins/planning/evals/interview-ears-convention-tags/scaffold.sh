#!/usr/bin/env bash
# A repository whose AGENTS.md binds the convention home docs/conventions, and whose
# authoring-formats convention selects EARS-tagged acceptance criteria.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions/authoring-formats src

cat >AGENTS.md <<'MD'
# uploads

<!-- BEGIN GENERATED: convention-home -->
Team conventions live in `docs/conventions`; read the topic doc there before changing a governed surface.
<!-- END GENERATED: convention-home -->
MD

cat >docs/conventions/authoring-formats/README.md <<'MD'
# Authoring formats

```yaml
acceptance_criteria_format: ears
```
MD

printf 'export function upload(file) { return file; }\n' >src/upload.js

git add .
git commit -q -m "feat: upload stub and authoring-formats convention"
