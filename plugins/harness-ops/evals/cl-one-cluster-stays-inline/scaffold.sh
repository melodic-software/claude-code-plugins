#!/usr/bin/env bash
# A small plugin whose skill states a default, and a two-release changelog that changes it.
set -euo pipefail
mkdir -p .claude-plugin skills/notes
printf '{"name":"notes-kit","version":"1.0.0","description":"Session notes"}\n' >.claude-plugin/plugin.json
cat >skills/notes/SKILL.md <<'EOF'
---
description: Save session notes before the conversation is compacted.
---

# Notes

Compaction starts when the conversation reaches 80% of the context window (the
`autoCompactWindow` default), so write the notes file before then.
EOF
cat >changelog.md <<'EOF'
# Claude Code changelog

<Update label="2.1.261" description="November 2, 2026">
* Changed the `autoCompactWindow` default from 80% to 90% of the context window
* Fixed a crash when a hook printed invalid UTF-8
</Update>

<Update label="2.1.260" description="November 1, 2026">
* Added a `--tail` flag to `claude agents`
</Update>
EOF
