#!/usr/bin/env bash
# A git repo with no remote (repo-visibility reads local, which head's gate allows) and the
# existing jo-park skill the prompt continues. The corpus and progress file live under the
# plugin data directory, which this scaffold cannot reach.
set -euo pipefail

git init -q
mkdir -p .claude/skills/jo-park/reference
cat > .claude/skills/jo-park/SKILL.md <<'EOF'
---
name: jo-park
description: "Jo Park's published essays on product launches and pacing, distilled."
---

# Jo Park

| Query about... | Load |
|---|---|
EOF
