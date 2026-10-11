#!/usr/bin/env bash
# Seeds an app whose team config caps the large animation role at 400ms.
set -euo pipefail

mkdir -p docs/conventions src/styles
cat > package.json <<'JSON'
{ "name": "fernway", "private": true }
JSON
cat > docs/conventions/user-interface.yaml <<'YAML'
version: 1
animation:
  duration_ms:
    large: 400
YAML
cat > src/styles/base.css <<'CSS'
.page { display: grid; gap: 16px; }
CSS
