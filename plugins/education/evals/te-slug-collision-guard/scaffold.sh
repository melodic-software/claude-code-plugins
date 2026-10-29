#!/usr/bin/env bash
# Seeds a project that declares a plain project-relative teach workspace root, with an existing
# C++ topic workspace at slug `c` under this project's slug, so a new C# topic collides with it.
# The slug derivation mirrors derive_slug in skills/teach/scripts/list-workspaces.sh.
set -euo pipefail

cat >CLAUDE.md <<'EOF'
# Project notes

teach workspace root: learning-root
EOF

canonical="$(pwd -P)"
basename_slug="$(basename "$canonical" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
path_hash="$(printf '%s' "$canonical" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
workspace="learning-root/${basename_slug}-${path_hash}/topic/c"
mkdir -p "$workspace/learning-records"
cat >"$workspace/MISSION.md" <<'EOF'
# Mission: C++

## Why

Maintain the game engine's renderer.

## Success Looks Like

- Fix one renderer bug without help.
EOF
