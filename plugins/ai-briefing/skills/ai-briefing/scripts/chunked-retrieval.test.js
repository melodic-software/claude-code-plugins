// Chunked retrieval test.
//
// Posts/replies extractor templates stash full results on
// window.__cap{Posts|Replies} and return only summary
// {n, oldest?, stable_iterations} to dodge MCP javascript_tool's ~1500-2000
// char response truncation. Main session reads tw[] in CHUNK_SIZE-tweet slices
// via buildChunkReaderJs and reassembles via assembleChunks before commit-s1.
//
// This test stands up a synthetic `window` via `node:vm`, runs each chunk
// reader as JS, and checks reassembly equals the original tw[] across:
//   - empty result (n=0)
//   - single chunk below CHUNK_SIZE (n=2)
//   - exact boundary (n=4 = one chunk)
//   - multi-chunk (n=10 → 3 chunks)
//   - with_replies surface
//   - invalid surface throws

import vm from "node:vm";

import {
  assembleChunks,
  buildChunkReaderJs,
  CHUNK_SIZE,
  validateExtractorOutput,
} from "./lib/chrome-extract.js";
import { createTestReporter } from "./lib/terminal.js";

const { ok, section, printResults, fail } = createTestReporter();

function mkTweets(n, prefix = "t") {
  return Array.from({ length: n }, (_, i) => ({
    t: `${prefix}${i} mock text`,
    u: `https://x.com/foo/status/${1000 + i}`,
    d: "2026-05-01T00:00",
  }));
}

function readChunk(stashTw, surface, start, end) {
  const stashKey = surface === "with_replies" ? "__capReplies" : "__capPosts";
  const sandbox = {
    window: { [stashKey]: { tw: stashTw } },
    JSON,
  };
  const js = buildChunkReaderJs(surface, start, end);
  return vm.runInNewContext(js, sandbox);
}

function assembleAll(tw, surface, summaryExtras = {}) {
  const summary = { n: tw.length, stable_iterations: 3, ...summaryExtras };
  if (surface === "posts" && summary.oldest === undefined) summary.oldest = "2026-05-01T00:00";
  const chunks = [];
  for (let s = 0; s < summary.n; s += CHUNK_SIZE) {
    chunks.push(readChunk(tw, surface, s, s + CHUNK_SIZE));
  }
  return { summary, chunks };
}

section("Test — chunked retrieval\n");

ok("CHUNK_SIZE === 2", CHUNK_SIZE === 2);

// Case 1 — empty result (n=0): no chunk reads needed
{
  const summary = { n: 0, oldest: "2026-05-01T00:00", stable_iterations: 3 };
  const assembled = assembleChunks(summary, [], { handle: "foo" });
  ok("empty: tw.length === 0", assembled.tw.length === 0);
  ok("empty: a === @foo", assembled.a === "@foo");
  ok("empty: zod-valid", !!validateExtractorOutput(assembled));
}

// Case 2 — single chunk below CHUNK_SIZE
{
  const tw = mkTweets(2);
  const { summary, chunks } = assembleAll(tw, "posts");
  ok("single: 1 chunk emitted", chunks.length === 1);
  const assembled = assembleChunks(summary, chunks, { handle: "foo" });
  ok("single: tw.length === 2", assembled.tw.length === 2);
  ok("single: tw[0] preserved", assembled.tw[0].t === tw[0].t && assembled.tw[0].u === tw[0].u);
  ok("single: zod-valid", !!validateExtractorOutput(assembled));
}

// Case 3 — exact boundary (n === CHUNK_SIZE = exactly one chunk)
{
  const tw = mkTweets(CHUNK_SIZE);
  const { summary, chunks } = assembleAll(tw, "posts");
  ok("boundary: 1 chunk emitted", chunks.length === 1);
  const assembled = assembleChunks(summary, chunks, { handle: "foo" });
  ok("boundary: tw.length === CHUNK_SIZE", assembled.tw.length === CHUNK_SIZE);
  ok("boundary: deep-equal tw", JSON.stringify(assembled.tw) === JSON.stringify(tw));
}

// Case 4 — multi-chunk (n=10)
{
  const tw = mkTweets(10);
  const expectedChunks = Math.ceil(10 / CHUNK_SIZE);
  const { summary, chunks } = assembleAll(tw, "posts");
  ok(`multi: ${expectedChunks} chunks emitted`, chunks.length === expectedChunks);
  const assembled = assembleChunks(summary, chunks, { handle: "foo" });
  ok("multi: tw.length === 10", assembled.tw.length === 10);
  ok("multi: last tweet preserved", assembled.tw[9].u === tw[9].u);
  ok("multi: deep-equal tw", JSON.stringify(assembled.tw) === JSON.stringify(tw));
  ok("multi: oldest passes through", assembled.oldest === "2026-05-01T00:00");
}

// Case 5 — with_replies surface (n=6)
{
  const tw = mkTweets(6, "r");
  const expectedChunks = Math.ceil(6 / CHUNK_SIZE);
  const { summary, chunks } = assembleAll(tw, "with_replies");
  ok(`replies: ${expectedChunks} chunks emitted`, chunks.length === expectedChunks);
  const assembled = assembleChunks(summary, chunks, { handle: "foo", surface: "with_replies" });
  ok("replies: surface === with_replies", assembled.surface === "with_replies");
  ok("replies: tw.length === 6", assembled.tw.length === 6);
  ok("replies: a === @foo", assembled.a === "@foo");
  ok("replies: zod-valid", !!validateExtractorOutput(assembled));
}

// Case 6 — buildChunkReaderJs format
{
  const js = buildChunkReaderJs("posts", 0, 4);
  ok("chunk JS contains slice(0, 4)", js.includes("slice(0, 4)"));
  ok("chunk JS targets __capPosts", js.includes("window.__capPosts.tw"));

  const js2 = buildChunkReaderJs("with_replies", 4, 8);
  ok("replies chunk JS targets __capReplies", js2.includes("window.__capReplies.tw"));
  ok("replies chunk JS contains slice(4, 8)", js2.includes("slice(4, 8)"));
}

// Case 7 — invalid inputs throw
{
  let threw1 = false;
  try {
    buildChunkReaderJs("bogus", 0, 4);
  } catch {
    threw1 = true;
  }
  ok("invalid surface throws", threw1);

  let threw2 = false;
  try {
    buildChunkReaderJs("posts", -1, 4);
  } catch {
    threw2 = true;
  }
  ok("negative start throws", threw2);

  let threw3 = false;
  try {
    buildChunkReaderJs("posts", 4, 2);
  } catch {
    threw3 = true;
  }
  ok("end < start throws", threw3);

  let threw4 = false;
  try {
    assembleChunks({ n: 5 }, [[{ t: "x", u: "u", d: "d" }]], { handle: "foo" });
  } catch {
    threw4 = true;
  }
  ok("n mismatch throws", threw4);

  let threw5 = false;
  try {
    assembleChunks({ n: 0 }, [], {});
  } catch {
    threw5 = true;
  }
  ok("missing handle throws", threw5);
}

// Case 8 — chunks accept either parsed arrays OR JSON strings
{
  const tw = mkTweets(3);
  const summary = { n: 3, oldest: "2026-05-01T00:00", stable_iterations: 1 };
  const stringChunk = JSON.stringify(tw);
  const assembled = assembleChunks(summary, [stringChunk], { handle: "foo" });
  ok("JSON-string chunks accepted", assembled.tw.length === 3);
}

printResults();
process.exit(fail > 0 ? 1 : 0);
