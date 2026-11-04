#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# digest writes its page to a local file. The branch adds a medium userConfig
# key and has lib/send.mjs read it directly: hosted uploads the page to an
# external host, with no resolver or trust rule in between.
mkdir -p .claude-plugin plugins/digest/.claude-plugin plugins/digest/skills/digest plugins/digest/lib

cat >.claude-plugin/marketplace.json <<'JSON'
{
  "name": "acme-plugins",
  "owner": { "name": "Acme" },
  "plugins": [
    { "name": "digest", "source": "./plugins/digest", "description": "Digest a change" }
  ]
}
JSON

cat >plugins/digest/.claude-plugin/plugin.json <<'JSON'
{ "name": "digest", "version": "2.1.0", "description": "Digest a change" }
JSON

cat >plugins/digest/skills/digest/SKILL.md <<'MD'
---
description: "Digest the current change"
---

Write the digest page, then run `node "${CLAUDE_PLUGIN_ROOT}/lib/send.mjs" <page-file>`.
MD

cat >plugins/digest/lib/send.mjs <<'JS'
import { copyFileSync } from "node:fs";
copyFileSync(process.argv[2], "digest.html");
JS

git add .
git commit -q -m "feat: digest plugin"

git checkout -q -b feat/digest-medium
cat >plugins/digest/.claude-plugin/plugin.json <<'JSON'
{
  "name": "digest",
  "version": "2.1.0",
  "description": "Digest a change",
  "userConfig": {
    "medium": {
      "type": "string",
      "title": "Digest medium",
      "description": "Where /digest:digest sends the page. auto (default): a local file; terminal: no page; file: a local file; hosted: the shared page host.",
      "default": "auto",
      "options": ["auto", "terminal", "file", "hosted"]
    }
  }
}
JSON

cat >plugins/digest/skills/digest/SKILL.md <<'MD'
---
description: "Digest the current change"
---

Write the digest page, then run `node "${CLAUDE_PLUGIN_ROOT}/lib/send.mjs" <page-file> --medium "${user_config.medium}"`.
MD

cat >plugins/digest/lib/send.mjs <<'JS'
import { copyFileSync, readFileSync } from "node:fs";
const medium = process.argv[process.argv.indexOf("--medium") + 1];
if (medium === "hosted") {
  await fetch("https://pages.example.com/api/publish", { method: "POST", body: readFileSync(process.argv[2]) });
} else if (medium !== "terminal") {
  copyFileSync(process.argv[2], "digest.html");
}
JS

git add .
git commit -q -m "feat(digest): let the user pick the digest medium"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
