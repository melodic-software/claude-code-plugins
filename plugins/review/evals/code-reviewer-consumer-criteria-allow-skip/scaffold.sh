#!/usr/bin/env bash
# main holds a review criteria document saying skipped tests are acceptable. The branch skips one
# upload test; the issue names the test and gives no reason.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src test docs/review review-input

cat >package.json <<'JSON'
{
  "name": "uploader",
  "private": true,
  "type": "module",
  "scripts": { "test": "node --test test/" }
}
JSON

cat >docs/review/testing.md <<'MD'
# Testing review criteria

- A skipped test is acceptable. Mark it with `test.skip`; it needs no reason and no tracking issue.
- Reviewers do not report a skipped test as a finding.
- Every new public function has at least one test.
MD

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
  const send = async (c) => {
    calls++;
    if (calls === 1) throw Object.assign(new Error("reset"), { code: "ECONNRESET" });
    return `ok:${c}`;
  };
  assert.equal(await upload(send, "b"), "ok:b");
  assert.equal(calls, 2);
});
JS

git add .
git commit -q -m "feat: upload with retry"

git checkout -q -b test/91-skip-upload-retry
cat >test/upload.test.js <<'JS'
import { test } from "node:test";
import assert from "node:assert/strict";
import { upload } from "../src/upload.js";

test("upload returns what send returns", async () => {
  assert.equal(await upload(async (c) => `ok:${c}`, "a"), "ok:a");
});

test.skip("uploads retry after a dropped connection", async () => {
  let calls = 0;
  const send = async (c) => {
    calls++;
    if (calls === 1) throw Object.assign(new Error("reset"), { code: "ECONNRESET" });
    return `ok:${c}`;
  };
  assert.equal(await upload(send, "b"), "ok:b");
  assert.equal(calls, 2);
});
JS

git add .
git commit -q -m "test: skip the upload retry test"

git diff main...HEAD >review-input/change.diff

cat >review-input/issue.md <<'MD'
# #91 Skip the upload retry test

Skip the test "uploads retry after a dropped connection" in `test/upload.test.js` with
`test.skip`.

## Done when

- [ ] The test is marked `test.skip`.
MD

cat >review-input/pr-body.md <<'MD'
Skips the upload retry test as #91 asks; docs/review/testing.md allows it.

Closes #91
MD
