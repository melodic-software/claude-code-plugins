#!/usr/bin/env node
/**
 * Repair synthesis promotions: semantic renames, session fixes, pipeline-junk rejects, audit notes.
 *
 * Content rejection (low-value frames, mislabels, etc.) is agent vision work — not encoded here.
 *
 * Usage: node watch/repair-synthesis-promotions.js <slice-dir> [--dry-run]
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import {
  deriveSemanticNameFromGapNote,
  forbiddenSynthesisFileNameReason,
  isForbiddenPipelineSessionSlug,
  isPipelinePlaceholderGapNote,
} from "../lib/synthesis-filename.js";
import { parseSessionsFromClaimInventory } from "../lib/watch-slice-sessions.js";
import { slugifyTitle } from "../transcript/derive-video-slug.js";
import { renderKeyFramesManifest } from "./render-key-frames-manifest.js";
import { renderQualityAudit } from "./render-quality-audit.js";

/**
 * @param {string} sessionName
 * @returns {string}
 */
function sessionSlugFromName(sessionName) {
  return slugifyTitle(sessionName).slice(0, 32);
}

/**
 * @param {string} sliceDir
 * @param {string} sourceFile
 * @returns {string}
 */
function resolveSessionForSource(sliceDir, sourceFile) {
  const selectionPath = lanePath(sliceDir, LANES.keyFrames, "selection.json");
  const claimPath = lanePath(sliceDir, LANES.research, "claim-inventory.md");
  if (!fs.existsSync(selectionPath) || !fs.existsSync(claimPath)) {
    return "misc";
  }
  const selection = JSON.parse(fs.readFileSync(selectionPath, "utf8"));
  const frame = (selection.selectedFrames ?? []).find(
    (/** @type {{ file: string }} */ f) => f.file === sourceFile,
  );
  if (!frame || frame.timestampSec == null) {
    return "misc";
  }
  const sessions = parseSessionsFromClaimInventory(fs.readFileSync(claimPath, "utf8"));
  const ts = frame.timestampSec;
  for (const session of sessions) {
    if (ts >= session.startSec && (session.endSec === null || ts < session.endSec)) {
      return sessionSlugFromName(session.name);
    }
  }
  return "misc";
}

/**
 * @param {string} destName
 * @returns {string}
 */
function normalizeDestName(destName) {
  const base = path.basename(destName);
  return base.endsWith(".png") ? base : `${base}.png`;
}

/**
 * @param {{ verdict: string, destName?: string, gapNote?: string, rejectReason?: string }} row
 * @param {string} oldDest
 * @returns {boolean}
 */
function rejectPipelinePlaceholder(row, oldDest) {
  const gapNote = row.gapNote ?? "";
  if (!forbiddenSynthesisFileNameReason(oldDest) || !isPipelinePlaceholderGapNote(gapNote)) {
    return false;
  }
  row.verdict = "reject";
  row.rejectReason = "pipeline placeholder name with placeholder gap note — no vision evidence";
  row.destName = undefined;
  return true;
}

/**
 * @param {{ destName: string, gapNote?: string }} row
 * @param {Set<string>} reserved
 * @param {[string, string][]} renamePairs
 * @returns {string}
 */
function repairDestName(row, reserved, renamePairs) {
  const oldDest = normalizeDestName(row.destName);
  let destName = oldDest;
  if (!forbiddenSynthesisFileNameReason(destName)) {
    return destName;
  }
  reserved.delete(destName);
  destName = deriveSemanticNameFromGapNote(row.gapNote ?? "", reserved);
  row.destName = destName;
  if (destName !== oldDest) {
    renamePairs.push([oldDest, destName]);
  }
  return destName;
}

/**
 * @param {string} absSlice
 * @param {string} synthesisDir
 * @param {[string, string][]} renamePairs
 * @param {object} doc
 */
function applyFileRenames(absSlice, synthesisDir, renamePairs, doc) {
  const decisionsPath = lanePath(absSlice, LANES.keyFrames, "promotion-decisions.json");
  fs.writeFileSync(decisionsPath, `${JSON.stringify(doc, null, 2)}\n`, "utf8");

  for (const [oldName, newName] of renamePairs) {
    const oldPath = path.join(synthesisDir, oldName);
    const newPath = path.join(synthesisDir, newName);
    if (fs.existsSync(oldPath) && !fs.existsSync(newPath)) {
      fs.renameSync(oldPath, newPath);
    }
  }
}

/**
 * @param {string} synthesisDir
 * @param {object} doc
 */
function pruneUnpromotedSynthesisFiles(synthesisDir, doc) {
  const promotedNames = new Set(
    doc.decisions
      .filter((/** @type {{ verdict: string }} */ d) => d.verdict === "promote")
      .map((/** @type {{ destName: string }} */ d) => normalizeDestName(d.destName)),
  );

  for (const name of fs.readdirSync(synthesisDir)) {
    if (!name.endsWith(".png")) {
      continue;
    }
    if (!promotedNames.has(name)) {
      fs.unlinkSync(path.join(synthesisDir, name));
    }
  }
}

/**
 * @param {string} absSlice
 * @param {object} doc
 */
function writePromotionArtifacts(absSlice, doc) {
  /** @type {Record<string, { sourceFile: string, gapNote?: string, session?: string }>} */
  const promotionMap = {};
  for (const row of doc.decisions) {
    if (row.verdict !== "promote") {
      continue;
    }
    const destName = normalizeDestName(row.destName);
    if (forbiddenSynthesisFileNameReason(destName)) {
      throw new Error(`still forbidden after repair: ${destName}`);
    }
    promotionMap[destName] = {
      sourceFile: row.sourceFile,
      gapNote: row.gapNote,
      session: row.session,
    };
  }

  fs.writeFileSync(
    lanePath(absSlice, LANES.keyFrames, "promotion-map.json"),
    `${JSON.stringify(promotionMap, null, 2)}\n`,
    "utf8",
  );

  const promotes = doc.decisions.filter(
    (/** @type {{ verdict: string }} */ d) => d.verdict === "promote",
  );
  const auditDoc = {
    reviewedAt: new Date().toISOString(),
    model: "repair-synthesis-promotions",
    files: promotes.map((/** @type {{ destName: string, gapNote?: string }} */ row) => ({
      name: normalizeDestName(row.destName),
      pass: true,
      note: (row.gapNote ?? "vision-gated promotion").slice(0, 120),
    })),
  };
  fs.writeFileSync(
    lanePath(absSlice, LANES.keyFrames, "key-frame-quality-audit.json"),
    `${JSON.stringify(auditDoc, null, 2)}\n`,
    "utf8",
  );
  renderKeyFramesManifest(absSlice);
  renderQualityAudit(absSlice);
}

/**
 * @param {object} doc
 * @param {Set<string>} reserved
 * @param {string} absSlice
 * @returns {{ renamed: number, rejected: number, sessionsFixed: number, renamePairs: [string, string][] }}
 */
function repairPromotionRows(doc, reserved, absSlice) {
  let renamed = 0;
  let rejected = 0;
  let sessionsFixed = 0;
  /** @type {[string, string][]} */
  const renamePairs = [];

  for (const row of doc.decisions) {
    if (row.verdict !== "promote") {
      continue;
    }

    const oldDest = normalizeDestName(row.destName);
    if (rejectPipelinePlaceholder(row, oldDest)) {
      rejected += 1;
      continue;
    }

    const destName = repairDestName(row, reserved, renamePairs);
    if (destName !== oldDest) {
      renamed += 1;
    }

    if (typeof row.session === "string" && isForbiddenPipelineSessionSlug(row.session)) {
      row.session = resolveSessionForSource(absSlice, row.sourceFile);
      sessionsFixed += 1;
    }
  }

  return { renamed, rejected, sessionsFixed, renamePairs };
}

/**
 * @param {string} sliceDir
 * @param {{ dryRun?: boolean }} [options]
 * @returns {{ renamed: number, rejected: number, sessionsFixed: number }}
 */
export function repairSynthesisPromotions(sliceDir, { dryRun = false } = {}) {
  const absSlice = path.resolve(sliceDir);
  const decisionsPath = lanePath(absSlice, LANES.keyFrames, "promotion-decisions.json");
  const synthesisDir = lanePath(absSlice, LANES.keyFrames, "frames");
  const doc = JSON.parse(fs.readFileSync(decisionsPath, "utf8"));
  const reserved = new Set(
    fs.existsSync(synthesisDir)
      ? fs.readdirSync(synthesisDir).filter((f) => f.endsWith(".png"))
      : [],
  );

  const { renamed, rejected, sessionsFixed, renamePairs } = repairPromotionRows(
    doc,
    reserved,
    absSlice,
  );

  if (!dryRun) {
    applyFileRenames(absSlice, synthesisDir, renamePairs, doc);
    pruneUnpromotedSynthesisFiles(synthesisDir, doc);
    writePromotionArtifacts(absSlice, doc);
  }

  return { renamed, rejected, sessionsFixed };
}

const sliceDir = process.argv[2];
const dryRun = process.argv.includes("--dry-run");
const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  if (!sliceDir) {
    writeStderr("Usage: node watch/repair-synthesis-promotions.js <slice-dir> [--dry-run]\n");
    process.exit(2);
  }
  const result = repairSynthesisPromotions(sliceDir, { dryRun });
  writeStdout(
    `${dryRun ? "DRY RUN" : "Applied"}: renamed=${result.renamed} rejected=${result.rejected} sessionsFixed=${result.sessionsFixed}\n`,
  );
}
