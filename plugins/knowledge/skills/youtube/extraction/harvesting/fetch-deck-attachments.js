#!/usr/bin/env node
/**
 * Fetch deck and attachment URLs from source/harvested-links.json into source/decks/ and source/attachments/.
 *
 * Usage: node harvesting/fetch-deck-attachments.js <slice-dir> [--dry-run]
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";

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
 * @param {{ dryRun?: boolean }} [options]
 * @returns {Promise<{ fetched: string[], skipped: string[] }>}
 */
export async function fetchDeckAttachments(sliceDir, { dryRun = false } = {}) {
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
      const buffer = Buffer.from(await response.arrayBuffer());
      fs.writeFileSync(destPath, buffer);
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
