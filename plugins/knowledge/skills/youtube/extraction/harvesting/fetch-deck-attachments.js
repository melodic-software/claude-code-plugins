#!/usr/bin/env node
/**
 * Fetch deck and attachment URLs from source/harvested-links.json into source/decks/ and source/attachments/.
 *
 * Usage: node harvesting/fetch-deck-attachments.js <slice-dir> [--dry-run]
 */

import fs from "node:fs";
import path from "node:path";
import { Readable, Transform } from "node:stream";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";

/** Default cap on a single fetched attachment; links come from attacker-controlled video descriptions. */
export const MAX_ATTACHMENT_BYTES = 500 * 1024 * 1024;

/**
 * Stream a WHATWG response body to disk, aborting past `maxBytes`. Enforces the
 * cap on the actual byte count (a missing/lying `content-length` cannot bypass
 * it) and removes the partial file on failure so a truncated download never
 * masquerades as a complete attachment.
 *
 * @param {ReadableStream} webStream
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
  try {
    await pipeline(Readable.fromWeb(webStream), cap, fs.createWriteStream(destPath));
  } catch (error) {
    fs.rmSync(destPath, { force: true });
    throw error;
  }
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
 * @param {{ dryRun?: boolean, maxBytes?: number }} [options]
 * @returns {Promise<{ fetched: string[], skipped: string[] }>}
 */
export async function fetchDeckAttachments(
  sliceDir,
  { dryRun = false, maxBytes = MAX_ATTACHMENT_BYTES } = {},
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
    if (kind !== "deck" && kind !== "doc" && kind !== "attachment") {
      skipped.push(`${link.url ?? link.href}: type ${kind}`);
      continue;
    }

    const url = link.url ?? link.href;
    if (!url) {
      skipped.push("missing url");
      continue;
    }

    const destRoot =
      kind === "deck"
        ? lanePath(absSlice, LANES.source, "decks", link.sessionSlug ?? "unknown")
        : lanePath(absSlice, LANES.source, "attachments", kind);

    const destPath = path.join(destRoot, slugFromUrl(url));

    if (dryRun) {
      fetched.push(destPath);
      continue;
    }

    fs.mkdirSync(destRoot, { recursive: true });
    try {
      const response = await fetch(url, { redirect: "follow" });
      if (!response.ok) {
        skipped.push(`${url}: HTTP ${response.status}`);
        continue;
      }
      const declaredLen = Number(response.headers.get("content-length") ?? 0);
      if (declaredLen > maxBytes) {
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

const sliceDir = process.argv[2];
const dryRun = process.argv.includes("--dry-run");
const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  if (!sliceDir) {
    writeStderr("Usage: node harvesting/fetch-deck-attachments.js <slice-dir> [--dry-run]\n");
    process.exit(2);
  }
  fetchDeckAttachments(sliceDir, { dryRun })
    .then((result) => {
      writeStdout(`${JSON.stringify(result, null, 2)}\n`);
    })
    .catch((error) => {
      writeStderr(`${error instanceof Error ? error.message : String(error)}\n`);
      process.exit(1);
    });
}
