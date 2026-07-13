import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { Readable } from "node:stream";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { fetchDeckAttachments } from "./fetch-deck-attachments.js";

/**
 * @param {Buffer} buffer
 * @param {{ ok?: boolean, status?: number, contentLength?: string | null }} [meta]
 */
function fakeResponse(buffer, { ok = true, status = 200, contentLength } = {}) {
  const headers = new Headers();
  if (contentLength !== undefined && contentLength !== null) {
    headers.set("content-length", contentLength);
  }
  return {
    ok,
    status,
    headers,
    body: ok ? Readable.toWeb(Readable.from(buffer)) : null,
  };
}

describe("fetchDeckAttachments", () => {
  /** @type {string} */
  let sliceDir;

  beforeEach(() => {
    sliceDir = fs.mkdtempSync(path.join(os.tmpdir(), "fetch-deck-test-"));
    fs.mkdirSync(path.join(sliceDir, "source"), { recursive: true });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    fs.rmSync(sliceDir, { recursive: true, force: true });
  });

  /**
   * @param {Array<Record<string, unknown>>} links
   */
  function writeLinks(links) {
    fs.writeFileSync(
      path.join(sliceDir, "source", "harvested-links.json"),
      JSON.stringify(links),
    );
  }

  it("streams a normal attachment to disk", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/spec.pdf" }]);
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => fakeResponse(Buffer.from("hello world"), { contentLength: "11" })),
    );

    const result = await fetchDeckAttachments(sliceDir);

    expect(result.fetched).toHaveLength(1);
    expect(result.skipped).toHaveLength(0);
    expect(fs.readFileSync(result.fetched[0], "utf8")).toBe("hello world");
  });

  it("skips when content-length exceeds the cap without downloading", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/huge.zip" }]);
    const fetchMock = vi.fn(async () =>
      fakeResponse(Buffer.from("x".repeat(50)), { contentLength: "9999999" }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchDeckAttachments(sliceDir, { maxBytes: 10 });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/too large/);
  });

  it("aborts and removes the partial file when the streamed body exceeds the cap", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/lying.bin" }]);
    // No content-length header — the byte-counting cap must catch it mid-stream.
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => fakeResponse(Buffer.from("x".repeat(100)))),
    );

    const result = await fetchDeckAttachments(sliceDir, { maxBytes: 10 });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/exceeded 10 bytes/);
    const attachmentsDir = path.join(sliceDir, "source", "attachments", "attachment");
    const leftovers = fs.existsSync(attachmentsDir) ? fs.readdirSync(attachmentsDir) : [];
    expect(leftovers).toEqual([]);
  });

  it("skips a non-ok HTTP response", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/missing.pdf" }]);
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => fakeResponse(Buffer.from(""), { ok: false, status: 404 })),
    );

    const result = await fetchDeckAttachments(sliceDir);

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/HTTP 404/);
  });

  it("skips when fetch itself rejects", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/boom.pdf" }]);
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw new Error("network down");
      }),
    );

    const result = await fetchDeckAttachments(sliceDir);

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/network down/);
  });
});
