#!/usr/bin/env node
/**
 * Fetch deck and attachment URLs from source/harvested-links.json into source/decks/ and source/attachments/.
 *
 * Usage: node harvesting/fetch-deck-attachments.js <slice-dir> [--dry-run]
 */

import dns from "node:dns/promises";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { Readable, Transform } from "node:stream";
import { pipeline } from "node:stream/promises";

import { isMainModule } from "@melodic/video-digestion/shared/main-module";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";

/** Default cap on a single fetched attachment; links come from attacker-controlled video descriptions. */
export const MAX_ATTACHMENT_BYTES = 500 * 1024 * 1024;

/** Link kinds this fetcher downloads; any other kind is recorded as skipped. */
const FETCHABLE_KINDS = new Set(["deck", "doc", "attachment"]);

/**
 * Stream a WHATWG response body to disk, aborting past `maxBytes`. Enforces the
 * cap on the actual byte count (a missing/lying `content-length` cannot bypass
 * it). Writes to a `.partial` sidecar and renames on success, so a mid-stream
 * failure (including the cap firing after headers passed) removes only the
 * partial — a previously-fetched attachment at `destPath` survives a failed
 * retry, so retries stay idempotent.
 *
 * @param {ReadableStream<Uint8Array>} webStream
 * @param {string} destPath
 * @param {number} maxBytes
 * @returns {Promise<void>}
 */
async function streamToFileWithCap(webStream, destPath, maxBytes) {
  let bytes = 0;
  const cap = new Transform({
    transform(chunk, _encoding, callback) {
      bytes += chunk.length;
      if (bytes > maxBytes) {
        callback(new Error(`response exceeded ${maxBytes} bytes`));
        return;
      }
      callback(null, chunk);
    },
  });
  const partialPath = `${destPath}.partial`;
  try {
    await pipeline(
      Readable.fromWeb(/** @type {import('node:stream/web').ReadableStream} */ (webStream)),
      cap,
      fs.createWriteStream(partialPath),
    );
    fs.renameSync(partialPath, destPath);
  } catch (error) {
    fs.rmSync(partialPath, { force: true });
    throw error;
  }
}

/** One path segment, never `.` or `..`: the session writes it, from untrusted watch input. */
const SAFE_SESSION_SLUG = /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$/;

/** Redirect hops followed per link; each hop is re-checked like the first URL. */
export const MAX_REDIRECT_HOPS = 5;

/**
 * True when an IPv4 address is loopback, private, link-local, CGNAT, unspecified,
 * multicast or reserved.
 *
 * @param {string} address dotted-quad
 * @returns {boolean}
 */
function isNonPublicIPv4(address) {
  const parts = address.split(".").map(Number);
  if (parts.length !== 4 || parts.some((p) => !Number.isInteger(p) || p < 0 || p > 255)) {
    return true;
  }
  const [a, b] = parts;
  return (
    a === 0 ||
    a === 10 ||
    a === 127 ||
    (a === 100 && b >= 64 && b <= 127) ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 192 && b === 0 && parts[2] === 0) ||
    (a === 192 && b === 0 && parts[2] === 2) ||
    (a === 198 && (b === 18 || b === 19)) ||
    (a === 198 && b === 51 && parts[2] === 100) ||
    (a === 203 && b === 0 && parts[2] === 113) ||
    a >= 224
  );
}

/**
 * Expand an IPv6 address (with or without an embedded dotted quad) to 8 numeric groups.
 *
 * @param {string} address
 * @returns {number[] | null}
 */
function ipv6Groups(address) {
  let text = address.toLowerCase().split("%")[0];
  const dotted = text.match(/^(.*:)(\d+\.\d+\.\d+\.\d+)$/);
  if (dotted) {
    const octets = dotted[2].split(".").map(Number);
    if (octets.some((o) => o > 255)) return null;
    text = `${dotted[1]}${((octets[0] << 8) | octets[1]).toString(16)}:${((octets[2] << 8) | octets[3]).toString(16)}`;
  }
  const halves = text.split("::");
  if (halves.length > 2) return null;
  const head = halves[0] ? halves[0].split(":") : [];
  const tail = halves.length === 2 && halves[1] ? halves[1].split(":") : [];
  const missing = 8 - head.length - tail.length;
  if (halves.length === 2 ? missing < 0 : missing !== 0) return null;
  const groups = [...head, ...Array(halves.length === 2 ? missing : 0).fill("0"), ...tail].map(
    (g) => Number.parseInt(g, 16),
  );
  return groups.length === 8 && groups.every((g) => g >= 0 && g <= 0xffff) ? groups : null;
}

/**
 * @param {number} hi
 * @param {number} lo
 * @returns {boolean}
 */
function embeddedIPv4NonPublic(hi, lo) {
  return isNonPublicIPv4(`${hi >> 8}.${hi & 255}.${lo >> 8}.${lo & 255}`);
}

/**
 * True when an IPv6 address is loopback, unspecified, unique-local, link-local,
 * multicast, site-local, or a mapped, compatible, NAT64 or 6to4 form of a
 * non-public IPv4 address. An unparsable address is non-public.
 *
 * @param {string} address
 * @returns {boolean}
 */
function isNonPublicIPv6(address) {
  const g = ipv6Groups(address);
  if (!g) return true;
  const zeroPrefix = (n) => g.slice(0, n).every((x) => x === 0);
  if (zeroPrefix(7) && g[7] <= 1) return true; // :: and ::1
  if (zeroPrefix(6)) return embeddedIPv4NonPublic(g[6], g[7]); // ::a.b.c.d (compatible)
  if (zeroPrefix(5) && g[5] === 0xffff) return embeddedIPv4NonPublic(g[6], g[7]); // ::ffff:a.b.c.d (mapped)
  if (zeroPrefix(4) && g[4] === 0xffff && g[5] === 0) return embeddedIPv4NonPublic(g[6], g[7]); // ::ffff:0:a.b.c.d
  if (g[0] === 0x64 && g[1] === 0xff9b && g.slice(2, 6).every((x) => x === 0)) {
    return embeddedIPv4NonPublic(g[6], g[7]); // 64:ff9b::/96 NAT64
  }
  if (g[0] === 0x2002) return embeddedIPv4NonPublic(g[1], g[2]); // 6to4
  const first = g[0];
  return (
    (first & 0xfe00) === 0xfc00 || // fc00::/7 unique-local
    (first & 0xffc0) === 0xfe80 || // fe80::/10 link-local
    (first & 0xffc0) === 0xfec0 || // fec0::/10 site-local
    (first & 0xff00) === 0xff00 // ff00::/8 multicast
  );
}

/**
 * @param {string} address
 * @returns {boolean}
 */
export function isNonPublicAddress(address) {
  const family = net.isIP(address);
  if (family === 4) return isNonPublicIPv4(address);
  if (family === 6) return isNonPublicIPv6(address);
  return true;
}

/**
 * Throw unless `url` is https and its host resolves only to public addresses.
 *
 * @param {string} url
 * @param {(host: string) => Promise<Array<{ address: string }>>} lookup
 * @returns {Promise<void>}
 */
async function assertPublicHttpsUrl(url, lookup) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error("blocked: invalid URL");
  }
  if (parsed.protocol !== "https:") {
    throw new Error(`blocked: scheme ${parsed.protocol} not allowed (https only)`);
  }
  const host = parsed.hostname.replace(/^\[|\]$/g, "");
  if (net.isIP(host)) {
    if (isNonPublicAddress(host)) {
      throw new Error(`blocked: non-public address ${host}`);
    }
    return;
  }
  const records = await lookup(host);
  if (records.length === 0) {
    throw new Error(`blocked: ${host} did not resolve`);
  }
  for (const { address } of records) {
    if (isNonPublicAddress(address)) {
      throw new Error(`blocked: ${host} resolves to non-public address ${address}`);
    }
  }
}

/** @param {string} host */
const defaultLookup = (host) => dns.lookup(host, { all: true });

/**
 * Fetch with https-only, public-host enforcement on the first URL and on every
 * redirect hop (redirects are followed manually, up to MAX_REDIRECT_HOPS).
 *
 * @param {string} url
 * @param {(host: string) => Promise<Array<{ address: string }>>} lookup
 * @returns {Promise<Response>}
 */
async function safeFetch(url, lookup) {
  let current = url;
  for (let hop = 0; hop <= MAX_REDIRECT_HOPS; hop += 1) {
    await assertPublicHttpsUrl(current, lookup);
    const response = await fetch(current, { redirect: "manual" });
    if (response.status < 300 || response.status >= 400) {
      return response;
    }
    const location = response.headers.get("location");
    if (!location) {
      return response;
    }
    await response.body?.cancel();
    current = new URL(location, current).href;
  }
  throw new Error(`blocked: more than ${MAX_REDIRECT_HOPS} redirects`);
}

/**
 * @param {string} url
 * @returns {string}
 */

function slugFromUrl(url) {
  try {
    const parsed = new URL(url);
    const base = path.basename(parsed.pathname) || "download";
    return base.replace(/[^a-zA-Z0-9._-]+/g, "-").slice(0, 80);
  } catch {
    return "download";
  }
}

/**
 * @param {string} sliceDir
 * @param {{ dryRun?: boolean, maxBytes?: number, lookup?: (host: string) => Promise<Array<{ address: string }>> }} [options]
 * @returns {Promise<{ fetched: string[], skipped: string[] }>}
 */
export async function fetchDeckAttachments(
  sliceDir,
  { dryRun = false, maxBytes = MAX_ATTACHMENT_BYTES, lookup = defaultLookup } = {},
) {
  const absSlice = path.resolve(sliceDir);
  const linksPath = lanePath(absSlice, LANES.source, "harvested-links.json");
  if (!fs.existsSync(linksPath)) {
    return { fetched: [], skipped: ["harvested-links.json missing"] };
  }

  const links = JSON.parse(fs.readFileSync(linksPath, "utf8"));
  const fetched = [];
  const skipped = [];

  for (const link of links) {
    const kind = link.type ?? link.kind ?? "other";
    const url = link.url ?? link.href;
    if (!FETCHABLE_KINDS.has(kind)) {
      skipped.push(`${url}: type ${kind}`);
      continue;
    }

    if (!url) {
      skipped.push("missing url");
      continue;
    }

    const sessionSlug = link.sessionSlug ?? "unknown";
    if (kind === "deck" && !SAFE_SESSION_SLUG.test(sessionSlug)) {
      skipped.push(`${url}: unsafe sessionSlug ${JSON.stringify(sessionSlug)}`);
      continue;
    }

    const destRoot =
      kind === "deck"
        ? lanePath(absSlice, LANES.source, "decks", sessionSlug)
        : lanePath(absSlice, LANES.source, "attachments", kind);

    const destPath = path.join(destRoot, slugFromUrl(url));

    if (dryRun) {
      fetched.push(destPath);
      continue;
    }

    fs.mkdirSync(destRoot, { recursive: true });
    try {
      const response = await safeFetch(url, lookup);
      if (!response.ok) {
        await response.body?.cancel();
        skipped.push(`${url}: HTTP ${response.status}`);
        continue;
      }
      const declaredLen = Number(response.headers.get("content-length") ?? 0);
      if (declaredLen > maxBytes) {
        await response.body?.cancel();
        skipped.push(`${url}: too large (content-length ${declaredLen} > ${maxBytes})`);
        continue;
      }
      if (!response.body) {
        skipped.push(`${url}: empty response body`);
        continue;
      }
      await streamToFileWithCap(response.body, destPath, maxBytes);
      fetched.push(destPath);
    } catch (error) {
      skipped.push(`${url}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  return { fetched, skipped };
}

if (isMainModule(import.meta.url)) {
  const sliceDir = process.argv[2];
  const dryRun = process.argv.includes("--dry-run");
  if (!sliceDir) {
    writeStderr("Usage: node harvesting/fetch-deck-attachments.js <slice-dir> [--dry-run]");
    process.exit(2);
  }
  fetchDeckAttachments(sliceDir, { dryRun })
    .then((result) => {
      writeStdout(JSON.stringify(result, null, 2));
    })
    .catch((error) => {
      writeStderr(error instanceof Error ? error.message : String(error));
      process.exit(1);
    });
}
