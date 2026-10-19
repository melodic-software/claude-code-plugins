import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { Readable } from "node:stream";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  fetchDeckAttachments,
  isNonPublicAddress,
  MAX_REDIRECT_HOPS,
  pinnedLookup,
} from "./fetch-deck-attachments.js";

/** Resolve every host to a public address so tests never touch real DNS. */
const publicLookup = async () => [{ address: "93.184.216.34" }];

/** Transport that delegates to the stubbed global fetch, recording the pinned address. */
const fetchTransport = (url, address) => fetch(url, { redirect: "manual", address });

/**
 * @param {string} location
 * @param {number} [status]
 */
function redirectResponse(location, status = 302) {
  const headers = new Headers({ location });
  return { ok: false, status, headers, body: null };
}

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

    const result = await fetchDeckAttachments(sliceDir, { lookup: publicLookup, transport: fetchTransport });

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

    const result = await fetchDeckAttachments(sliceDir, { lookup: publicLookup, transport: fetchTransport });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped).toHaveLength(2);
    expect(result.skipped[0]).toMatch(/unsafe sessionSlug/);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("files a deck under its sessionSlug", async () => {
    writeLinks([{ type: "deck", url: "https://example.com/deck.pdf", sessionSlug: "keynote-2026" }]);
    stubFetch(async () => fakeResponse(Buffer.from("deck"), { contentLength: "4" }));

    const result = await fetchDeckAttachments(sliceDir, { lookup: publicLookup, transport: fetchTransport });

    expect(result.fetched).toEqual([
      path.join(sliceDir, "source", "decks", "keynote-2026", "deck.pdf"),
    ]);
  });

  it("skips when content-length exceeds the cap without downloading", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/huge.zip" }]);
    stubFetch(async () => fakeResponse(Buffer.from("x".repeat(50)), { contentLength: "9999999" }));

    const result = await fetchDeckAttachments(sliceDir, { maxBytes: 10, lookup: publicLookup, transport: fetchTransport });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/too large/);
  });

  it("aborts and removes the partial file when the streamed body exceeds the cap", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/lying.bin" }]);
    // No content-length header — the byte-counting cap must catch it mid-stream.
    stubFetch(async () => fakeResponse(Buffer.from("x".repeat(100))));

    const result = await fetchDeckAttachments(sliceDir, { maxBytes: 10, lookup: publicLookup, transport: fetchTransport });

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

    const result = await fetchDeckAttachments(sliceDir, { maxBytes: 10, lookup: publicLookup, transport: fetchTransport });

    expect(result.fetched).toHaveLength(0);
    expect(fs.readFileSync(destPath, "utf8")).toBe("previously-good-content");
  });

  it("skips a non-ok HTTP response", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/missing.pdf" }]);
    stubFetch(async () => fakeResponse(Buffer.from(""), { ok: false, status: 404 }));

    const result = await fetchDeckAttachments(sliceDir, { lookup: publicLookup, transport: fetchTransport });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/HTTP 404/);
  });

  it("rejects non-https schemes without fetching", async () => {
    writeLinks([
      { type: "attachment", url: "http://example.com/a.pdf" },
      { type: "attachment", url: "ftp://example.com/b.pdf" },
      { type: "attachment", url: "file:///etc/passwd" },
    ]);
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchDeckAttachments(sliceDir, { lookup: publicLookup, transport: fetchTransport });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped).toHaveLength(3);
    for (const entry of result.skipped) expect(entry).toMatch(/not allowed \(https only\)/);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it.each([
    "https://127.0.0.1/a.pdf",
    "https://10.1.2.3/a.pdf",
    "https://172.16.0.1/a.pdf",
    "https://192.168.1.1/a.pdf",
    "https://169.254.169.254/latest/meta-data",
    "https://[::1]/a.pdf",
    "https://[fd00::1]/a.pdf",
    "https://[fe80::1]/a.pdf",
    "https://[::ffff:127.0.0.1]/a.pdf",
    "https://[::127.0.0.1]/a.pdf",
    "https://[::ffff:0:7f00:1]/a.pdf",
    "https://[64:ff9b::a9fe:a9fe]/a.pdf",
    "https://[2002:7f00:1::]/a.pdf",
    "https://[fec0::1]/a.pdf",
    "https://198.18.0.1/a.pdf",
  ])("rejects the non-public IP literal %s without fetching", async (url) => {
    writeLinks([{ type: "attachment", url }]);
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchDeckAttachments(sliceDir, { lookup: publicLookup, transport: fetchTransport });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/blocked: non-public address/);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects a hostname that resolves to a private address", async () => {
    writeLinks([{ type: "attachment", url: "https://internal.example.com/a.pdf" }]);
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchDeckAttachments(sliceDir, {
      lookup: async () => [{ address: "93.184.216.34" }, { address: "10.0.0.5" }],
      transport: fetchTransport,
    });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/resolves to non-public address 10\.0\.0\.5/);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects a redirect to a private host and stops before fetching it", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/a.pdf" }]);
    const fetchMock = vi.fn(async () => redirectResponse("https://169.254.169.254/secret"));
    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchDeckAttachments(sliceDir, { lookup: publicLookup, transport: fetchTransport });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/blocked: non-public address 169\.254\.169\.254/);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("rejects a scheme-relative redirect to a private host", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/a.pdf" }]);
    stubFetch(async () => redirectResponse("//10.0.0.1/x"));

    const result = await fetchDeckAttachments(sliceDir, { lookup: publicLookup, transport: fetchTransport });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/blocked: non-public address 10\.0\.0\.1/);
  });

  it("skips when the host does not resolve", async () => {
    writeLinks([{ type: "attachment", url: "https://nowhere.example.com/a.pdf" }]);
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchDeckAttachments(sliceDir, { lookup: async () => [], transport: fetchTransport });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/did not resolve/);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("cancels the body of a non-ok response", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/a.pdf" }]);
    const cancel = vi.fn(async () => {});
    stubFetch(async () => ({ ok: false, status: 503, headers: new Headers(), body: { cancel } }));

    const result = await fetchDeckAttachments(sliceDir, { lookup: publicLookup, transport: fetchTransport });

    expect(result.skipped[0]).toMatch(/HTTP 503/);
    expect(cancel).toHaveBeenCalledTimes(1);
  });

  it("rejects a redirect downgrade to http", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/a.pdf" }]);
    stubFetch(async () => redirectResponse("http://example.com/a.pdf", 301));

    const result = await fetchDeckAttachments(sliceDir, { lookup: publicLookup, transport: fetchTransport });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/not allowed \(https only\)/);
  });

  it("follows a redirect to another public https host", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/a.pdf" }]);
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(redirectResponse("/real/a.pdf"))
      .mockResolvedValueOnce(fakeResponse(Buffer.from("ok"), { contentLength: "2" }));
    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchDeckAttachments(sliceDir, { lookup: publicLookup, transport: fetchTransport });

    expect(result.fetched).toHaveLength(1);
    expect(fetchMock.mock.calls[1][0]).toBe("https://example.com/real/a.pdf");
    expect(fetchMock.mock.calls[0][1]).toEqual({
      redirect: "manual",
      address: "93.184.216.34",
    });
  });

  it("pins each hop to the address it resolved, not a later DNS answer", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/a.pdf" }]);
    const answers = ["93.184.216.34", "93.184.216.35"];
    const lookup = vi.fn(async () => [{ address: answers.shift() }]);
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(redirectResponse("/b.pdf"))
      .mockResolvedValueOnce(fakeResponse(Buffer.from("ok"), { contentLength: "2" }));
    vi.stubGlobal("fetch", fetchMock);

    await fetchDeckAttachments(sliceDir, { lookup, transport: fetchTransport });

    expect(fetchMock.mock.calls.map((call) => call[1].address)).toEqual([
      "93.184.216.34",
      "93.184.216.35",
    ]);
    expect(lookup).toHaveBeenCalledTimes(2);
  });

  it("gives up after the redirect hop cap", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/loop" }]);
    const fetchMock = vi.fn(async () => redirectResponse("https://example.com/loop"));
    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchDeckAttachments(sliceDir, { lookup: publicLookup, transport: fetchTransport });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/more than \d+ redirects/);
    expect(fetchMock).toHaveBeenCalledTimes(MAX_REDIRECT_HOPS + 1);
  });

  it("skips when fetch itself rejects", async () => {
    writeLinks([{ type: "attachment", url: "https://example.com/boom.pdf" }]);
    stubFetch(async () => {
      throw new Error("network down");
    });

    const result = await fetchDeckAttachments(sliceDir, { lookup: publicLookup, transport: fetchTransport });

    expect(result.fetched).toHaveLength(0);
    expect(result.skipped[0]).toMatch(/network down/);
  });
});

describe("pinnedLookup", () => {
  it("answers every lookup with the vetted address", () => {
    const callback = vi.fn();
    pinnedLookup("93.184.216.34")("rebind.example", {}, callback);
    expect(callback).toHaveBeenCalledWith(null, "93.184.216.34", 4);
  });

  it("answers an all-records lookup with only the vetted address", () => {
    const callback = vi.fn();
    pinnedLookup("2606:4700:4700::1111")("rebind.example", { all: true }, callback);
    expect(callback).toHaveBeenCalledWith(null, [{ address: "2606:4700:4700::1111", family: 6 }]);
  });
});

describe("isNonPublicAddress", () => {
  it.each(["0.0.0.0", "100.64.0.1", "172.31.255.255", "224.0.0.1", "::", "ff02::1", "not-an-ip"])(
    "treats %s as non-public",
    (address) => {
      expect(isNonPublicAddress(address)).toBe(true);
    },
  );

  it.each(["93.184.216.34", "8.8.8.8", "172.32.0.1", "2606:4700:4700::1111"])(
    "treats %s as public",
    (address) => {
      expect(isNonPublicAddress(address)).toBe(false);
    },
  );
});
