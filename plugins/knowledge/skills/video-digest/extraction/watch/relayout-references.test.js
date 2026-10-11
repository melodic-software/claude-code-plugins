import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { checkLayoutLinks, rewriteReferences } from "./relayout-references.js";

/** @type {string[]} */
const scratch = [];

function makeDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "relayout-check-"));
  scratch.push(dir);
  return dir;
}

/** @param {string} root @param {Record<string, string>} files */
function writeTree(root, files) {
  for (const [rel, body] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    fs.writeFileSync(path.join(root, rel), body);
  }
}

afterEach(() => {
  for (const dir of scratch.splice(0)) fs.rmSync(dir, { recursive: true, force: true });
});

describe("rewriteReferences", () => {
  it("leaves fenced code, spaced code spans and URLs alone", () => {
    const body = [
      "Outside: [t](../source/transcript.txt).",
      "```",
      "[t](../source/transcript.txt) `source/transcript.txt` [gone](../research/gone.md)",
      "```",
      "Command: `node run.mjs source/transcript.txt`, <https://example.com/source/x.md>.",
      "",
    ].join("\n");
    const map = {
      files: new Map([["source/transcript.txt", "transcript/transcript.txt"]]),
      dirs: new Map(),
      entries: new Set(["source", "source/transcript.txt", "key-frames"]),
      tempFrames: new Map(),
    };

    const result = rewriteReferences(body, "key-frames/visual-frames.md", "frames/visual-frames.md", map);

    expect(result.text).toBe(
      body.replace("Outside: [t](../source/transcript.txt)", "Outside: [t](../transcript/transcript.txt)"),
    );
    expect(result.rewrites).toBe(1);
  });
});

describe("checkLayoutLinks", () => {
  it("stays quiet on URLs, placeholders, other-repository paths and resolvable paths", () => {
    const root = makeDir();
    writeTree(root, {
      "transcript/transcript.txt": "x",
      "analysis/notes.md": [
        "[ok](../transcript/transcript.txt#t=3) [web](https://example.com/a.md)",
        "[repo](plugins/knowledge/SKILL.md) [up](../../other-repo/x.md)",
        "`<slice-dir>/source/x.txt` `research/*.md` `SKILL.md` `/abs/path.md`",
        "",
      ].join("\n"),
    });

    expect(checkLayoutLinks(root)).toEqual([]);
  });

  it("flags a dangling link and a backticked path under a layout directory", () => {
    const root = makeDir();
    writeTree(root, {
      "transcript/transcript.txt": "x",
      "analysis/notes.md": "[gone](gone.md) `transcript/missing.txt` `SLICE/source/x.txt`\n",
    });

    expect(checkLayoutLinks(root)).toEqual([
      { file: "analysis/notes.md", ref: "gone.md" },
      { file: "analysis/notes.md", ref: "transcript/missing.txt" },
      { file: "analysis/notes.md", ref: "SLICE/source/x.txt" },
    ]);
  });
});
