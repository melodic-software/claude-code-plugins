#!/usr/bin/env node
/**
 * Materialize slice watch-checklist.md from skill template + watch.json signals.
 *
 * Usage: node watch/init-watch-checklist.js <slice-dir> [--force]
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { detectContentClass, outcomeFloors } from "../evals/check-watch-outcomes.js";
import { LANES, lanePath } from "../lib/slice-lanes.js";
import { parseSessionsFromClaimInventory } from "../lib/watch-slice-sessions.js";
import { watchStatePath } from "./watch-state.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// Bundled template — resolve relative to this script under the plugin (cache-isolated).
const TEMPLATE_PATH = path.resolve(__dirname, "../../templates/watch-checklist.md");

/**
 * @param {number} index 1-based
 * @returns {string}
 */
export function formatSheetId(index) {
  return String(index).padStart(3, "0");
}

/**
 * @param {number} count
 * @returns {string}
 */
export function buildSheetCheckboxes(count) {
  const lines = [];
  for (let i = 1; i <= count; i++) {
    const id = formatSheetId(i);
    lines.push(
      `- [ ] **sheet_${id}** — Vision: \`key-frames/triage/batches/sheet_${id}.json\` (agentic model); merged manifest + \`frame-triage-log.md\``,
    );
  }
  return lines.join("\n");
}

/**
 * Build the floors sentence once the content class is known (vision-plan.md present).
 *
 * @param {string} contentClass
 * @param {string} durationHours formatted (e.g. "8.0")
 * @param {number|string} sessionCount
 * @param {number} durationSec
 * @returns {string}
 */
export function buildFloorsLine(contentClass, durationHours, sessionCount, durationSec) {
  const floors = outcomeFloors(
    contentClass,
    durationSec,
    typeof sessionCount === "number" ? sessionCount : 1,
  );
  const synthesis = floors.minSynthesisFrames;
  const perHour = floors.minPerHour;
  const sheetTriagePct = Math.round(floors.minSheetTriageRatio * 100);
  const densificationPct = Math.round(floors.minDensificationRatio * 100);
  return (
    `**Floors for this slice** (from \`vision-plan\` class \`${contentClass}\`, ${durationHours}h, ` +
    `${sessionCount} sessions): ≥${synthesis} synthesis frames, ≥${perHour}/h, ` +
    `≥${sheetTriagePct}% sheet triage, ≥${densificationPct}% densification alignment.`
  );
}

/**
 * @param {string} sliceDir
 * @param {{ force?: boolean }} [options]
 * @returns {string} output path
 */
export function initWatchChecklist(sliceDir, { force = false } = {}) {
  const absSlice = path.resolve(sliceDir);
  const outPath = lanePath(absSlice, LANES.runState, "watch-checklist.md");

  if (fs.existsSync(outPath) && !force) {
    writeStderr(`SKIP: ${outPath} exists (use --force to regenerate)`);
    return outPath;
  }

  if (!fs.existsSync(TEMPLATE_PATH)) {
    throw new Error(`Missing template: ${TEMPLATE_PATH}`);
  }

  const watchPath = watchStatePath(absSlice);
  const selectionPath = lanePath(absSlice, LANES.keyFrames, "selection.json");
  const visionPlanPath = lanePath(absSlice, LANES.keyFrames, "vision-plan.md");
  const claimInventoryPath = lanePath(absSlice, LANES.research, "claim-inventory.md");

  if (!fs.existsSync(watchPath)) {
    throw new Error(`Missing watch.json in ${absSlice}`);
  }

  const watch = JSON.parse(fs.readFileSync(watchPath, "utf8"));
  const selection = fs.existsSync(selectionPath)
    ? JSON.parse(fs.readFileSync(selectionPath, "utf8"))
    : null;

  const durationSec = selection?.durationSec ?? watch.phases?.watching?.metrics?.durationSec ?? 0;
  const contactSheetCount =
    selection?.contactSheets?.length ??
    watch.artifactPaths?.contactSheetCount ??
    watch.phases?.watching?.metrics?.contactSheetCount ??
    0;
  const densificationWindowCount =
    selection?.densificationWindows?.length ??
    watch.phases?.watching?.metrics?.densificationWindows ??
    0;
  const highVolume =
    selection?.frameSelection?.highVolume ?? watch.phases?.watching?.metrics?.highVolume ?? false;

  const visionPlanBody = fs.existsSync(visionPlanPath)
    ? fs.readFileSync(visionPlanPath, "utf8")
    : "";
  const visionPlanPresent = visionPlanBody.length > 0;
  const contentClass = visionPlanPresent ? detectContentClass(visionPlanBody) : "pending";

  const claimBody = fs.existsSync(claimInventoryPath)
    ? fs.readFileSync(claimInventoryPath, "utf8")
    : "";
  const sessions = claimBody ? parseSessionsFromClaimInventory(claimBody) : [];
  const sessionCount = sessions.length || "TBD";

  const videoSlug = path.basename(absSlice);
  const durationHours = (durationSec / 3600).toFixed(1);

  // Floors derive from the vision-plan content class. Post-bootstrap, vision-plan.md
  // does not exist yet, so the class — and every floor computed from it — is unknown.
  // Defer the whole floors sentence rather than substitute fabricated numbers: the
  // checklist re-materializes (--force) once the plan lands.
  const floorsLine = visionPlanPresent
    ? buildFloorsLine(contentClass, durationHours, sessionCount, durationSec)
    : "**Floors for this slice:** deferred — pending `key-frames/vision-plan.md` (content class + floors set after the vision-plan lands; re-run with `--force`).";

  let template = fs.readFileSync(TEMPLATE_PATH, "utf8");
  const replacements = {
    "{{VIDEO_SLUG}}": videoSlug,
    "{{INIT_TIMESTAMP}}": new Date().toISOString(),
    "{{FLOORS_LINE}}": floorsLine,
    "{{CONTENT_CLASS}}": contentClass,
    "{{DURATION_HOURS}}": durationHours,
    "{{SESSION_COUNT}}": String(sessionCount),
    "{{CONTACT_SHEET_COUNT}}": String(contactSheetCount),
    "{{DENSIFICATION_WINDOW_COUNT}}": String(densificationWindowCount),
    "{{HIGH_VOLUME}}": String(highVolume),
    "{{SHEET_CHECKBOXES}}":
      contactSheetCount > 0
        ? buildSheetCheckboxes(contactSheetCount)
        : "- [ ] **sheet_NNN** — (no sheets yet; re-run after watching pipeline)",
  };

  for (const [key, value] of Object.entries(replacements)) {
    template = template.replaceAll(key, value);
  }

  fs.mkdirSync(lanePath(absSlice, LANES.runState), { recursive: true });
  fs.writeFileSync(outPath, template, "utf8");
  return outPath;
}

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  const sliceDir = process.argv[2];
  const force = process.argv.includes("--force");

  if (!sliceDir) {
    writeStderr("Usage: node watch/init-watch-checklist.js <slice-dir> [--force]");
    process.exit(2);
  }

  try {
    const outPath = initWatchChecklist(sliceDir, { force });
    writeStdout(outPath);
  } catch (error) {
    writeStderr(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
