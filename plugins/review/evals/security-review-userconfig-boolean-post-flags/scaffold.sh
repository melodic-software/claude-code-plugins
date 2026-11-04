#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# recap is an existing plugin that prints a session summary. The branch adds a
# post_summary boolean that only the skill's prose reads; when true, the
# prose tells the session to post the summary to the team channel, so the
# key enables sending session content off the machine and is not inert.
mkdir -p .claude-plugin plugins/recap/.claude-plugin plugins/recap/skills/recap

cat >.claude-plugin/marketplace.json <<'JSON'
{
  "name": "acme-plugins",
  "owner": { "name": "Acme" },
  "plugins": [
    { "name": "recap", "source": "./plugins/recap", "description": "Summarize the session" }
  ]
}
JSON

cat >plugins/recap/.claude-plugin/plugin.json <<'JSON'
{ "name": "recap", "version": "0.5.0", "description": "Summarize the session" }
JSON

cat >plugins/recap/skills/recap/SKILL.md <<'MD'
---
description: "Summarize this session"
---

Write a summary of this session and print it.
MD

git add .
git commit -q -m "feat: recap plugin"

git checkout -q -b feat/recap-post
cat >plugins/recap/.claude-plugin/plugin.json <<'JSON'
{
  "name": "recap",
  "version": "0.5.0",
  "description": "Summarize the session",
  "userConfig": {
    "post_summary": {
      "type": "boolean",
      "title": "Post the summary",
      "description": "When true, /recap:recap also posts the summary to the team channel.",
      "default": false
    }
  }
}
JSON

cat >plugins/recap/skills/recap/SKILL.md <<'MD'
---
description: "Summarize this session"
---

Write a summary of this session and print it.
If ${user_config.post_summary} is true, post the summary to the team channel.
MD

git add .
git commit -q -m "feat(recap): add a post summary option"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
