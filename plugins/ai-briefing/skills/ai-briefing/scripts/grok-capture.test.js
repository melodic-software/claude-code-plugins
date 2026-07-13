// grok-normalize — parse + merge helpers
//
// Run: node scripts/grok-capture.test.js

import { strict as assert } from "node:assert";

import {
  buildGrokBatchCapturePrompt,
  mergeTweetLists,
  normalizeGrokPosts,
  parseGrokJsonPayload,
  parseGrokSessionId,
} from "./lib/grok-normalize.js";
import { writelnStdout } from "./lib/terminal.js";

const HANDLE_LIMIT_ERROR_REGEX = /20 handles/;

let passed = 0;
let failed = 0;
const test = (name, fn) => {
  try {
    fn();
    writelnStdout(`  ✓ ${name}`);
    passed++;
  } catch (e) {
    writelnStdout(`  ✗ ${name}\n    ${e.message}`);
    failed++;
  }
};

writelnStdout("parseGrokJsonPayload:");
test("parses bare JSON object with posts array", () => {
  const raw = JSON.stringify({
    posts: [{ t: "hi", u: "https://x.com/xai/status/1", d: "2026-06-01T00:00:00Z" }],
  });
  const parsed = parseGrokJsonPayload(raw);
  assert.equal(parsed.posts.length, 1);
});

test("parses json output-format wrapper with result string", () => {
  const inner = { posts: [{ t: "a", u: "https://x.com/a/status/2", d: "2026-06-02" }] };
  const raw = JSON.stringify({ result: JSON.stringify(inner) });
  const parsed = parseGrokJsonPayload(raw);
  assert.equal(parsed.posts[0].t, "a");
});

test("parses json output-format wrapper with text string", () => {
  const inner = { posts: [{ t: "b", u: "https://x.com/b/status/3", d: "2026-06-03" }] };
  const raw = JSON.stringify({ text: JSON.stringify(inner), stopReason: "EndTurn" });
  const parsed = parseGrokJsonPayload(raw);
  assert.equal(parsed.posts[0].t, "b");
});

writelnStdout("parseGrokSessionId:");
test("parses sessionId from json output-format wrapper", () => {
  const raw = JSON.stringify({
    text: '{"posts":[]}',
    sessionId: "019ec806-3342-7851-804b-c6b5ca380edf",
    stopReason: "EndTurn",
  });
  assert.equal(parseGrokSessionId(raw), "019ec806-3342-7851-804b-c6b5ca380edf");
});

writelnStdout("normalizeGrokPosts:");
test("maps to chrome-compatible tw rows", () => {
  const rows = normalizeGrokPosts(
    {
      posts: [
        {
          t: "long\nmultiline",
          u: "https://x.com/cursor/status/9",
          d: "2026-06-03T10:00:00Z",
        },
      ],
    },
    "@cursor",
  );
  assert.ok(!rows[0].t.includes("\n"));
  assert.equal(rows[0]._source, "grok");
});

writelnStdout("mergeTweetLists:");
test("prefers chrome row on URL collision", () => {
  const url = "https://x.com/x/status/1";
  const merged = mergeTweetLists(
    [{ t: "grok", u: url, d: "2026-06-01", _source: "grok" }],
    [{ t: "chrome", u: url, d: "2026-06-01" }],
  );
  assert.equal(merged.length, 1);
  assert.equal(merged[0].t, "chrome");
});

writelnStdout("buildGrokBatchCapturePrompt:");
test("batch prompt rejects >20 handles", () => {
  try {
    buildGrokBatchCapturePrompt({
      handles: Array.from({ length: 21 }, (_, i) => `@h${i}`),
      cutoffIso: "2026-06-01T00:00:00.000Z",
    });
    assert.fail("expected throw");
  } catch (e) {
    assert.match(e.message, HANDLE_LIMIT_ERROR_REGEX);
  }
});

writelnStdout(`\n${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
