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
    fs.writeFileSync(path.join(sliceDir, "source", "harvested-links.json"), JSON.stringify(links));
  }

  /**
   * @param {() => Promise<unknown>} impl
   */
  function stubFetch(impl) {
    vi.stubGlobal("fetch", vi.fn(impl));
  }

  it("streams a normal attachment to disk", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/spec.pdf" }]);
    stubFetch(async () => fakeResponse(Buffer.from("hello world"), { contentLength: "11" }));

    const result = await fetchDeckAttachments(sliceDir);

    expect(result.fetched).toHaveLength(1);
    expect(result.skipped).toHaveLength(0);
    expect(fs.readFileSync(result.fetched[0], "utf8")).toBe("hello world");
  });

  it("skips a deck whose sessionSlug would escape the slice, without fetching", async () => {
    writeLinks([
      { type: "deck", url: "https://example.com/x/.bashrc", sessionSlug: "../../../../outside" },
      { type: "deck", url: "https://example.com/x/deck.pdf", sessionSlug: ".." },
    ]);
    const fetchMock = vi.fn(async () => fakeResponse(Buffer.from("x"), { contentLength: "1" }));
    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchDeckAttachments(sliceDir);

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped).toHaveLength(2);
    expect(result.skipped[0]).toMatch(/unsafe sessionSlug/);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("files a deck under its sessionSlug", async () => {
    writeLinks([{ type: "deck", url: "https://example.com/deck.pdf", sessionSlug: "keynote-2026" }]);
    stubFetch(async () => fakeResponse(Buffer.from("deck"), { contentLength: "4" }));

    const result = await fetchDeckAttachments(sliceDir);

    expect(result.fetched).toEqual([
      path.join(sliceDir, "source", "decks", "keynote-2026", "deck.pdf"),
    ]);
  });

  it("skips when content-length exceeds the cap without downloading", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/huge.zip" }]);
    stubFetch(async () => fakeResponse(Buffer.from("x".repeat(50)), { contentLength: "9999999" }));

    const result = await fetchDeckAttachments(sliceDir, { maxBytes: 10 });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/too large/);
  });

  it("aborts and removes the partial file when the streamed body exceeds the cap", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/lying.bin" }]);
    // No content-length header — the byte-counting cap must catch it mid-stream.
    stubFetch(async () => fakeResponse(Buffer.from("x".repeat(100))));

    const result = await fetchDeckAttachments(sliceDir, { maxBytes: 10 });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/exceeded 10 bytes/);
    const attachmentsDir = path.join(sliceDir, "source", "attachments", "attachment");
    const leftovers = fs.existsSync(attachmentsDir) ? fs.readdirSync(attachmentsDir) : [];
    expect(leftovers).toEqual([]);
  });

  it("preserves a previously-fetched attachment when a retry stream fails", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/spec.pdf" }]);
    const destPath = path.join(sliceDir, "source", "attachments", "attachment", "spec.pdf");
    fs.mkdirSync(path.dirname(destPath), { recursive: true });
    fs.writeFileSync(destPath, "previously-good-content");

    // Retry that overruns the cap mid-stream — must not clobber the good file.
    stubFetch(async () => fakeResponse(Buffer.from("x".repeat(100))));

    const result = await fetchDeckAttachments(sliceDir, { maxBytes: 10 });

    expect(result.fetched).toHaveLength(0);
    expect(fs.readFileSync(destPath, "utf8")).toBe("previously-good-content");
  });

  it("skips a non-ok HTTP response", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/missing.pdf" }]);
    stubFetch(async () => fakeResponse(Buffer.from(""), { ok: false, status: 404 }));

    const result = await fetchDeckAttachments(sliceDir);

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/HTTP 404/);
  });

  it("skips when fetch itself rejects", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/boom.pdf" }]);
    stubFetch(async () => {
      throw new Error("network down");
    });

    const result = await fetchDeckAttachments(sliceDir);

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/network down/);
  });
});
