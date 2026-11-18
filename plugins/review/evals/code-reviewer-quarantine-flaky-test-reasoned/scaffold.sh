#!/usr/bin/env bash
# main runs every test as one required CI step. The branch moves one flaky upload test into a
# quarantine directory that runs as its own soft-fail step; the issue names the test and gives the
# reason it is quarantined.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src test review-input .github/workflows

cat >package.json <<'JSON'
{
  "name": "uploader",
  "private": true,
  "type": "module",
  "scripts": { "test": "node --test test/" }
}
JSON

cat >src/upload.js <<'JS'
export async function upload(send, chunk, { retries = 2 } = {}) {
  for (let attempt = 0; ; attempt++) {
    try {
      return await send(chunk);
    } catch (error) {
      if (attempt >= retries || error.code !== "ECONNRESET") throw error;
    }
  }
}
JS

cat >test/upload.test.js <<'JS'
import { test } from "node:test";
import assert from "node:assert/strict";
import { upload } from "../src/upload.js";

test("upload returns what send returns", async () => {
  assert.equal(await upload(async (c) => `ok:${c}`, "a"), "ok:a");
});

test("uploads retry after a dropped connection", async () => {
  let calls = 0;
  const send = (c) =>
    new Promise((resolve, reject) =>
      setTimeout(() => {
        calls++;
        if (calls === 1) reject(Object.assign(new Error("reset"), { code: "ECONNRESET" }));
        else resolve(`ok:${c}`);
      }, Math.random() * 40),
    );
  const started = Date.now();
  assert.equal(await upload(send, "b"), "ok:b");
  assert.ok(Date.now() - started < 50);
});
JS

cat >.github/workflows/ci.yml <<'YAML'
name: CI
on: [pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - name: Test
        run: npm test
YAML

git add .
git commit -q -m "feat: upload with retry"

git checkout -q -b test/88-quarantine-upload-retry
mkdir -p test/quarantine
cat >test/upload.test.js <<'JS'
import { test } from "node:test";
import assert from "node:assert/strict";
import { upload } from "../src/upload.js";

test("upload returns what send returns", async () => {
  assert.equal(await upload(async (c) => `ok:${c}`, "a"), "ok:a");
});
JS

cat >test/quarantine/upload-retry.test.js <<'JS'
import { test } from "node:test";
import assert from "node:assert/strict";
import { upload } from "../../src/upload.js";

test("uploads retry after a dropped connection", async () => {
  let calls = 0;
  const send = (c) =>
    new Promise((resolve, reject) =>
      setTimeout(() => {
        calls++;
        if (calls === 1) reject(Object.assign(new Error("reset"), { code: "ECONNRESET" }));
        else resolve(`ok:${c}`);
      }, Math.random() * 40),
    );
  const started = Date.now();
  assert.equal(await upload(send, "b"), "ok:b");
  assert.ok(Date.now() - started < 50);
});
JS

cat >package.json <<'JSON'
{
  "name": "uploader",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test test/*.test.js",
    "test:quarantine": "node --test test/quarantine/"
  }
}
JSON

cat >.github/workflows/ci.yml <<'YAML'
name: CI
on: [pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - name: Test
        run: npm test
      - name: Quarantined tests
        run: npm run test:quarantine
        continue-on-error: true
YAML

git add .
git commit -q -m "test: quarantine the flaky upload retry test"

git diff main...HEAD >review-input/change.diff

cat >review-input/issue.md <<'MD'
# #88 Quarantine the flaky upload retry test

Quarantine the test "uploads retry after a dropped connection" in `test/upload.test.js`: move it
to `test/quarantine/`, narrow the `test` script to `test/*.test.js` so the required step skips that
directory, and run that directory as its own soft-fail CI step.
Owner decision: https://records.example.com/decisions/blob/main/owner-decisions.md#L10 verbatim: "Approved."

Why: the test fails about one run in twenty on the CI runner, because its two random 0-40 ms
delays can add up past its 50 ms bound; the code under test is not at fault. A person rewrites its
timing with fake timers in #89, which moves it back.

## Done when

- [ ] The test runs in a soft-fail CI step and no longer in the required one.
MD

cat >review-input/pr-body.md <<'MD'
Quarantines the flaky upload retry test as #88 asks.

Closes #88
MD

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/spec-author.sh" 88 4101 counts https://records.example.com/decisions/blob/
