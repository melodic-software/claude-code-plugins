#!/usr/bin/env node
/**
 * Exclusive row claims for `.work/<watch-epic>/claims/<n>.json` (canonical epic dir: derive-video-slug.js).
 *
 * Usage:
 *   node watch/queue-claim.js claim <row> [--video-id <id>] [--epic-dir <path>]
 *   node watch/queue-claim.js release <row> [--epic-dir <path>]
 *   node watch/queue-claim.js list [--epic-dir <path>]
 *   node watch/queue-claim.js stale-check [--epic-dir <path>] [--max-age-days 7]
 */

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { resolveWorkRoot } from "../lib/work-root.js";
import { YOUTUBE_WATCH_EPIC_DIR } from "../transcript/derive-video-slug.js";

/** @typedef {{ row: number, videoId: string | null, claimedAt: string, claimedBy: string }} QueueClaim */

export const DEFAULT_STALE_DAYS = 7;

/**
 * @param {string} [workRoot]
 * @returns {string}
 */
export function resolveEpicDir(workRoot = resolveWorkRoot()) {
  return path.join(workRoot, ".work", YOUTUBE_WATCH_EPIC_DIR);
}

/**
 * @param {string} epicDir
 * @param {number} row
 * @returns {string}
 */
export function claimFilePath(epicDir, row) {
  return path.join(epicDir, "claims", `${row}.json`);
}

/**
 * @returns {string}
 */
export function defaultClaimedBy() {
  const host = os.hostname().replace(/[^\w.-]/g, "-");
  return `${host}-pid${process.pid}`;
}

/**
 * @param {QueueClaim} claim
 * @param {number} [maxAgeDays]
 * @returns {boolean}
 */
export function isStaleClaim(claim, maxAgeDays = DEFAULT_STALE_DAYS) {
  const claimedMs = Date.parse(claim.claimedAt);
  if (Number.isNaN(claimedMs)) {
    return true;
  }
  const maxMs = maxAgeDays * 24 * 60 * 60 * 1000;
  return Date.now() - claimedMs > maxMs;
}

/**
 * @param {string} epicDir
 * @param {number} row
 * @param {{ videoId?: string | null, claimedBy?: string }} [options]
 * @returns {QueueClaim}
 */
export function claimRow(epicDir, row, { videoId = null, claimedBy = defaultClaimedBy() } = {}) {
  if (!Number.isInteger(row) || row < 1) {
    throw new Error(`Invalid row: ${row}`);
  }

  const claimsDir = path.join(epicDir, "claims");
  fs.mkdirSync(claimsDir, { recursive: true });

  const filePath = claimFilePath(epicDir, row);
  /** @type {QueueClaim} */
  const payload = {
    row,
    videoId,
    claimedAt: new Date().toISOString(),
    claimedBy,
  };

  let handle;
  try {
    handle = fs.openSync(filePath, "wx");
    fs.writeFileSync(handle, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
  } catch (err) {
    if (/** @type {NodeJS.ErrnoException} */ (err).code === "EEXIST") {
      const existing = readClaimFile(filePath);
      const error = new Error(
        `Row ${row} already claimed by ${existing.claimedBy} at ${existing.claimedAt}`,
      );
      error.name = "ClaimExistsError";
      throw error;
    }
    throw err;
  } finally {
    if (handle !== undefined) {
      fs.closeSync(handle);
    }
  }

  return payload;
}

/**
 * @param {string} filePath
 * @returns {QueueClaim}
 */
export function readClaimFile(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  const parsed = JSON.parse(raw);
  return /** @type {QueueClaim} */ (parsed);
}

/**
 * @param {string} epicDir
 * @param {number} row
 * @returns {boolean}
 */
export function releaseRow(epicDir, row) {
  const filePath = claimFilePath(epicDir, row);
  if (!fs.existsSync(filePath)) {
    return false;
  }
  fs.unlinkSync(filePath);
  return true;
}

/**
 * @param {string} epicDir
 * @returns {QueueClaim[]}
 */
export function listClaims(epicDir) {
  const claimsDir = path.join(epicDir, "claims");
  if (!fs.existsSync(claimsDir)) {
    return [];
  }

  const claims = [];
  for (const name of fs.readdirSync(claimsDir)) {
    if (!name.endsWith(".json")) {
      continue;
    }
    const filePath = path.join(claimsDir, name);
    try {
      claims.push(readClaimFile(filePath));
    } catch {
      writeStderr(`WARN: unreadable claim file ${filePath}`);
    }
  }

  return claims.sort((a, b) => a.row - b.row);
}

/**
 * @param {string} epicDir
 * @param {number} [maxAgeDays]
 * @returns {{ released: number[], rows: number[] }}
 */
export function reclaimStaleClaims(epicDir, maxAgeDays = DEFAULT_STALE_DAYS) {
  const released = [];
  for (const claim of listClaims(epicDir)) {
    if (!isStaleClaim(claim, maxAgeDays)) {
      continue;
    }
    if (releaseRow(epicDir, claim.row)) {
      released.push(claim.row);
    }
  }
  return { released, rows: released };
}

/**
 * @param {string[]} argv
 */
// biome-ignore lint/complexity/noExcessiveCognitiveComplexity: CLI dispatches claim/release/list/stale-check subcommands
function main(argv) {
  const args = argv.slice(2);
  const command = args[0];
  if (!command) {
    writeStderr("Usage: queue-claim.js <claim|release|list|stale-check> ...");
    process.exit(1);
  }

  let epicDir = resolveEpicDir();
  let maxAgeDays = DEFAULT_STALE_DAYS;
  const positional = [];

  for (let i = 1; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--epic-dir" && args[i + 1]) {
      epicDir = path.resolve(args[++i]);
      continue;
    }
    if (arg === "--max-age-days" && args[i + 1]) {
      maxAgeDays = Number(args[++i]);
      continue;
    }
    if (arg === "--video-id" && args[i + 1]) {
      positional.push({ type: "videoId", value: args[++i] });
      continue;
    }
    positional.push({ type: "raw", value: arg });
  }

  if (command === "list") {
    const claims = listClaims(epicDir);
    writeStdout(JSON.stringify({ epicDir, claims }, null, 2));
    return;
  }

  if (command === "stale-check") {
    const result = reclaimStaleClaims(epicDir, maxAgeDays);
    writeStdout(JSON.stringify({ epicDir, maxAgeDays, ...result }, null, 2));
    return;
  }

  const rowToken = positional.find((p) => p.type === "raw");
  if (!rowToken) {
    writeStderr(`Missing row for ${command}`);
    process.exit(1);
  }

  const row = Number(rowToken.value);
  if (!Number.isInteger(row) || row < 1) {
    writeStderr(`Invalid row: ${rowToken.value}`);
    process.exit(1);
  }

  const videoIdEntry = positional.find((p) => p.type === "videoId");
  const videoId = videoIdEntry ? videoIdEntry.value : null;

  if (command === "claim") {
    try {
      const claim = claimRow(epicDir, row, { videoId });
      writeStdout(JSON.stringify({ ok: true, claim }, null, 2));
    } catch (err) {
      if (/** @type {Error} */ (err).name === "ClaimExistsError") {
        writeStderr(err.message);
        process.exit(2);
      }
      throw err;
    }
    return;
  }

  if (command === "release") {
    const released = releaseRow(epicDir, row);
    writeStdout(JSON.stringify({ ok: released, row }, null, 2));
    if (!released) {
      process.exit(1);
    }
    return;
  }

  writeStderr(`Unknown command: ${command}`);
  process.exit(1);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv);
}
