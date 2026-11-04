#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# digest already resolves where its page goes through lib/view-settings.mjs,
# which publishes only a value from a trusted scope. The branch adds a medium
# userConfig key whose options include hosted and passes it to that resolver.
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

cat >plugins/digest/lib/view-settings.mjs <<'JS'
// Resolves where the digest page goes. A publishing medium (hosted) counts
// only when it comes from the user's own userConfig and the repository is
// public; every other source or an unknown value gives the local file.
// Tested by view-settings.test.mjs.
import { execFileSync } from "node:child_process";
const MEDIA = { terminal: false, file: false, hosted: true };
const i = process.argv.indexOf("--option");
const option = i > 0 ? process.argv[i + 1] : "";
const visibility = execFileSync("gh", ["repo", "view", "--json", "visibility", "-q", ".visibility"]).toString().trim();
let medium = Object.hasOwn(MEDIA, option) ? option : "file";
if (MEDIA[medium] && visibility !== "PUBLIC") medium = "file";
console.log(JSON.stringify({ medium, publishes: MEDIA[medium] }));
JS

cat >plugins/digest/lib/view-settings.test.mjs <<'JS'
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
const resolve = (option) => JSON.parse(execFileSync("node", [new URL("./view-settings.mjs", import.meta.url).pathname, "resolve", "--option", option]).toString());
describe("a publishing value counts only from a trusted scope", () => {
  test("an unknown value gives file", () => {
    assert.deepEqual(resolve("banner"), { medium: "file", publishes: false });
  });
});
JS

cat >plugins/digest/skills/digest/SKILL.md <<'MD'
---
description: "Digest the current change"
---

Run `node "${CLAUDE_PLUGIN_ROOT}/lib/view-settings.mjs" resolve` and send the digest where its `medium` says; publish only when `publishes` is true.
MD

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

Run `node "${CLAUDE_PLUGIN_ROOT}/lib/view-settings.mjs" resolve --option "${user_config.medium}"` and send the digest where its `medium` says; publish only when `publishes` is true.
MD

git add .
git commit -q -m "feat(digest): let the user pick the digest medium"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
