#!/usr/bin/env bash
# A small repo citing three Claude product issues in docs, CLAUDE.md and a script.
set -euo pipefail
mkdir -p docs scripts
printf '%s\n' '# Project notes' '' 'Use the hook workaround below.' > CLAUDE.md
printf '%s\n' '' 'Stop hooks can fire twice: https://github.com/anthropics/claude-code/issues/50871' >> CLAUDE.md
printf '%s\n' '# Hook notes' '' 'PostToolUse output is truncated past 10 KB, see https://github.com/anthropics/claude-code/issues/41234.' > docs/hooks-notes.md
printf '%s\n' '#!/usr/bin/env bash' '# Retry the server start: https://github.com/microsoft/mcp/issues/1187' 'echo start' > scripts/mcp-check.sh
