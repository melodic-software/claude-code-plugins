#!/usr/bin/env bash
# Writes a small service that sends texts through the Textwave SMS gateway: a deploy workflow that
# reads one repository variable and one secret, an env template, and a local .env holding a key.
set -euo pipefail
mkdir -p .github/workflows src scripts
cat >README.md <<'MD'
# notify-service

Sends order and shipping text messages through the Textwave SMS gateway.

## Local setup

1. `npm ci`
2. Copy `.env.example` to `.env` and fill in the values.
3. `npm start`
MD
cat >.env.example <<'ENV'
SMS_SENDER_ID=
SMS_GATEWAY_KEY=
SMS_WEBHOOK_PATH=/hooks/textwave
ENV
cat >.env <<'ENV'
SMS_WEBHOOK_PATH='/hooks/textwave'
SMS_GATEWAY_KEY='devkey-local-placeholder-4417'
ENV
printf '%s\n' node_modules/ .env >.gitignore
cat >package.json <<'JSON'
{
  "name": "notify-service",
  "private": true,
  "scripts": {
    "start": "node src/send.js",
    "deploy": "node src/deploy.js"
  }
}
JSON
cat >src/send.js <<'JS'
const sender = process.env.SMS_SENDER_ID;
const key = process.env.SMS_GATEWAY_KEY;
if (!sender || !key) {
  throw new Error('SMS_SENDER_ID and SMS_GATEWAY_KEY must be set');
}
module.exports = { sender, key, webhookPath: process.env.SMS_WEBHOOK_PATH };
JS
cat >.github/workflows/deploy.yml <<'YML'
name: deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npm run deploy
        env:
          SMS_SENDER_ID: ${{ vars.SMS_SENDER_ID }}
          SMS_GATEWAY_KEY: ${{ secrets.SMS_GATEWAY_KEY }}
YML
