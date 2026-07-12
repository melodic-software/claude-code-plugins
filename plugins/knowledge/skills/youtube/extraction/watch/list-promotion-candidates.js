#!/usr/bin/env node
/**
 * List promotion candidates from triage manifest + claim-inventory sessions.
 *
 * Usage: node watch/list-promotion-candidates.js <slice-dir>
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { parseSessionsFromClaimInventory } from "../lib/watch-slice-sessions.js";

/**
 * @typedef {object} PromotionCandidate
 * @property {string} sourceFile
 * @property {string} verdict
 * @property {string} session
 * @property {number|null} timestampSec
 * @property {number} priorityScore
 */

/**
 * @param {string} sliceDir
 * @returns {PromotionCandidate[]}
 */
export function listPromotionCandidates(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const manifest = JSON.parse(
    fs.readFileSync(lanePath(absSlice, LANES.keyFrames, "triage", "manifest.json"), "utf8"),
  );
  const selection = JSON.parse(
    fs.readFileSync(lanePath(absSlice, LANES.keyFrames, "selection.json"), "utf8"),
  );
  const claimBody = fs.readFileSync(
    lanePath(absSlice, LANES.research, "claim-inventory.md"),
    "utf8",
  );
  const sessions = parseSessionsFromClaimInventory(claimBody);
  const byFile = Object.fromEntries(selection.selectedFrames.map((f) => [f.file, f]));
  const durationSec = selection.durationSec;

  /** @type {Map<string, { sourceFile: string, verdict: string, session: string, timestampSec: number|null, priorityScore: number }>} */
  const candidates = new Map();

  for (const sheet of manifest.sheets) {
    for (const cell of sheet.cells) {
      if (cell.verdict !== "promote-key-frame" && cell.verdict !== "keep-detail") continue;
      const frame = byFile[cell.frame];
      if (!frame) continue;
      const ts = frame.timestampSec ?? null;
      const session =
        sessions.find((s) => {
          const end = s.endSec ?? durationSec;
          return ts != null && ts >= s.startSec && ts <= end;
        })?.name ?? "unknown";

      const existing = candidates.get(cell.frame);
      const score = frame.priorityScore ?? 0;
      if (!existing || score > existing.priorityScore) {
        candidates.set(cell.frame, {
          sourceFile: cell.frame,
          verdict: cell.verdict,
          session,
          timestampSec: ts,
          priorityScore: score,
        });
      }
    }
  }

  const list = [...candidates.values()].sort(
    (a, b) => (a.timestampSec ?? 0) - (b.timestampSec ?? 0),
  );

  for (const session of sessions) {
    const end = session.endSec ?? durationSec;
    const inSession = list.filter(
      (c) => c.timestampSec != null && c.timestampSec >= session.startSec && c.timestampSec <= end,
    );
    if (inSession.length < 3) {
      const extras = selection.selectedFrames
        .filter(
          (f) =>
            f.timestampSec >= session.startSec && f.timestampSec <= end && !candidates.has(f.file),
        )
        .sort((a, b) => b.priorityScore - a.priorityScore)
        .slice(0, 3 - inSession.length);
      for (const frame of extras) {
        candidates.set(frame.file, {
          sourceFile: frame.file,
          verdict: "keep-detail",
          session: session.name,
          timestampSec: frame.timestampSec,
          priorityScore: frame.priorityScore,
        });
      }
    }
  }

  return [...candidates.values()].sort((a, b) => (a.timestampSec ?? 0) - (b.timestampSec ?? 0));
}

const sliceDir = process.argv[2];
const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  if (!sliceDir) {
    writeStderr("Usage: node watch/list-promotion-candidates.js <slice-dir>");
    process.exit(2);
  }
  writeStdout(`${JSON.stringify(listPromotionCandidates(sliceDir), null, 2)}\n`);
}
