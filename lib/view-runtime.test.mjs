// The runtime keeps its download buttons only where a page's own download is known
// to work: a file opened from disk, the session bridge on 127.0.0.1, and a page
// served top-level over https. It runs here in a vm against a stub document, so
// no browser is needed.
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";

const RUNTIME = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "view-runtime.js"), "utf8");

/** Run the runtime on a page at `url`; returns how many of its two download buttons it removed. */
function removedButtons(url, framed = false) {
  let removed = 0;
  const button = { remove: () => (removed += 1) };
  const body = { querySelectorAll: () => [], matches: () => false };
  const document = {
    URL: url,
    readyState: "complete",
    body,
    documentElement: { classList: { add() {} } },
    getElementById: () => null,
    querySelector: () => null,
    querySelectorAll: (selector) => (selector === "button[data-rv-download]" ? [button, button] : []),
    addEventListener() {},
  };
  const self = {};
  runInNewContext(RUNTIME, { document, URL, self, top: framed ? {} : self });
  return removed;
}

describe("download buttons", () => {
  for (const url of ["file:///tmp/view/page.html", "http://127.0.0.1:8765/page.html", "https://pages.example.com/abc/"]) {
    test(`a top-level page at ${url} keeps them`, () => {
      assert.equal(removedButtons(url), 0);
    });
  }
  for (const [url, framed] of [
    ["https://pages.example.com/abc/", true],
    ["http://localhost:8765/page.html", false],
    ["http://pages.example.com/abc/", false],
    ["blob:https://claude.ai/1", false],
  ]) {
    test(`a ${framed ? "framed" : "top-level"} page at ${url} loses them`, () => {
      assert.equal(removedButtons(url, framed), 2);
    });
  }
});
