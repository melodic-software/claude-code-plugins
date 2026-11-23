#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/workspace.sh" repo
mkdir -p docs/conventions
cat >docs/conventions/multi-agent.yaml <<'EOF'
schema: 1
vendors:
  routing: false
EOF
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/vendor-boards.sh" all-read
