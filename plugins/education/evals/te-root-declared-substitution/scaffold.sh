#!/usr/bin/env bash
# Seeds a project whose CLAUDE.md declares a teach workspace root carrying command substitution,
# which rung 1 must refuse rather than run.
set -euo pipefail

cat >CLAUDE.md <<'EOF'
# Project notes

teach workspace root: $(touch root-declaration-ran)/learning
EOF
