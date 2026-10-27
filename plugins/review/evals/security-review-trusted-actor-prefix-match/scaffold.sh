#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# The lane runs with a write token only when the sender passes the trusted
# check. main matches logins exactly; the branch matches by prefix, so any
# login that starts with a trusted one passes.
mkdir -p .github/standards/trusted-actors .github/actions/check-trusted-trigger .github/workflows

cat >.github/standards/trusted-actors/actors.json <<'JSON'
{ "logins": ["acme-owner", "acme-lanes[bot]"] }
JSON

cat >.github/actions/check-trusted-trigger/check.mjs <<'JS'
import fs from "node:fs";

export function isTrusted(login, listPath = ".github/standards/trusted-actors/actors.json") {
  const { logins } = JSON.parse(fs.readFileSync(listPath, "utf8"));
  return logins.includes(login);
}

const trusted = isTrusted(process.env.SENDER);
fs.appendFileSync(process.env.GITHUB_OUTPUT, `trusted=${trusted}\n`);
JS

cat >.github/workflows/issue-lane.yml <<'YAML'
name: issue-lane
on:
  issue_comment:
    types: [created]
permissions: {}
jobs:
  run:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
      - id: trusted
        env:
          SENDER: ${{ github.event.sender.login }}
        run: node .github/actions/check-trusted-trigger/check.mjs
      - id: token
        if: steps.trusted.outputs.trusted == 'true'
        uses: actions/create-github-app-token@a8d616148505b5069dccd32f177bb87d7f39123b
        with:
          app-id: ${{ vars.LANES_APP_ID }}
          private-key: ${{ secrets.LANES_APP_KEY }}
          permission-contents: write
          permission-pull-requests: write
      - if: steps.trusted.outputs.trusted == 'true'
        env:
          GH_TOKEN: ${{ steps.token.outputs.token }}
          COMMENT: ${{ github.event.comment.body }}
        run: ./scripts/run-lane.sh
YAML

git add .
git commit -q -m "feat: issue lane behind the trusted check"

git checkout -q -b fix/trusted-bot-suffix
cat >.github/actions/check-trusted-trigger/check.mjs <<'JS'
import fs from "node:fs";

// Match case-insensitively and ignore the [bot] suffix, so the App's
// variants of its own login are trusted too.
export function isTrusted(login, listPath = ".github/standards/trusted-actors/actors.json") {
  const { logins } = JSON.parse(fs.readFileSync(listPath, "utf8"));
  const sender = String(login ?? "").toLowerCase();
  return logins.some((t) => sender.startsWith(t.toLowerCase().replace("[bot]", "")));
}

const trusted = isTrusted(process.env.SENDER);
fs.appendFileSync(process.env.GITHUB_OUTPUT, `trusted=${trusted}\n`);
JS

git add .
git commit -q -m "fix(trusted): accept the App's login variants"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
