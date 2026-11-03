#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p docs
cat >docs/setup.md <<'EOF'
# Setup

The API listens on port 8443 and reads its keys from `config/keys.json`.
EOF
cat >docs/operations.md <<'EOF'
# Operations

Restart the API on port 8443. Its keys live in `config/keys.json`.
EOF
cat >docs/troubleshooting.md <<'EOF'
# Troubleshooting

If port 8443 is taken, the API exits at start; the setup steps in docs/setup.md say which port to free.
EOF
git add . && git commit -q -m "docs: add setup, operations and troubleshooting pages"
