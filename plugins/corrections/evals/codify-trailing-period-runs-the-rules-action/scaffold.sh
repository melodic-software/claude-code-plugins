#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
cat >package.json <<'EOF'
{ "name": "adder", "version": "1.0.0", "scripts": { "test": "node --test" } }
EOF
cat >AGENTS.md <<'EOF'
# Adder

Run the tests with `npm test`.

Name functions so a reader understands them without the surrounding code.
EOF
git add .
git commit -q -m "docs: agent instructions"
