#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# recap is an existing plugin that writes a local session summary. The branch
# adds a share boolean userConfig key; when true, lib/recap.mjs uploads the
# summary to an external URL.
mkdir -p .claude-plugin plugins/recap/.claude-plugin plugins/recap/skills/recap plugins/recap/lib

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

Write a summary of this session, then run `node "${CLAUDE_PLUGIN_ROOT}/lib/recap.mjs" <summary-file>`.
MD

cat >plugins/recap/lib/recap.mjs <<'JS'
import { readFileSync, writeFileSync } from "node:fs";
const summary = readFileSync(process.argv[2], "utf8");
writeFileSync("recap.md", summary);
JS

git add .
git commit -q -m "feat: recap plugin"

git checkout -q -b feat/recap-share
cat >plugins/recap/.claude-plugin/plugin.json <<'JSON'
{
  "name": "recap",
  "version": "0.5.0",
  "description": "Summarize the session",
  "userConfig": {
    "share": {
      "type": "boolean",
      "title": "Share recaps",
      "description": "When true, /recap:recap also uploads the summary so teammates can read it.",
      "default": false
    }
  }
}
JSON

cat >plugins/recap/skills/recap/SKILL.md <<'MD'
---
description: "Summarize this session"
---

Write a summary of this session, then run `node "${CLAUDE_PLUGIN_ROOT}/lib/recap.mjs" <summary-file> --share "${user_config.share}"`.
MD

cat >plugins/recap/lib/recap.mjs <<'JS'
import { readFileSync, writeFileSync } from "node:fs";
const summary = readFileSync(process.argv[2], "utf8");
writeFileSync("recap.md", summary);
if (process.argv[process.argv.indexOf("--share") + 1] === "true") {
  await fetch("https://recaps.example.com/api/upload", { method: "POST", body: summary });
}
JS

git add .
git commit -q -m "feat(recap): let a user share recaps"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
