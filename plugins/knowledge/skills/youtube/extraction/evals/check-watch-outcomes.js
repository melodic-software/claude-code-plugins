#!/usr/bin/env node
/**
 * Host verify script: end-to-end watch slice outcome verification (vision + research + synthesis).
 *
 * Usage: node evals/check-watch-outcomes.js <slice-dir> [--write-report]
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { forbiddenSynthesisFileNameReason } from "../lib/synthesis-filename.js";
import { parseSessionsFromClaimInventory } from "../lib/watch-slice-sessions.js";
import {
  listSynthesisPngs,
  validateActionableArtifactsForSlice,
  validatePromotionDecisionsForSlice,
  validateQualityAuditForSlice,
  validateTriageAgentic,
  validateTriageBatchFiles,
  validateTriageManifestForSlice,
  validateWatchChecklistForCompleteSlice,
} from "../lib/watch-vision-validation.js";
import { resolveSourceFile } from "../watch/rebuild-visual-frames.js";

/** @typedef {{ id: string, pass: boolean, actual: string, expected: string, severity: 'fail'|'warn' }} OutcomeCheck */

/**
 * @param {string} timestamp
 * @returns {number|null}
 */
export function parseMinuteTimestamp(timestamp) {
  const match = timestamp.match(/~?(\d+)m/);
  if (!match) return null;
  return Number(match[1]) * 60;
}

/**
 * @param {string} visualFramesBody
 * @returns {number[]}
 */
export function parsePromotedTimestampsSec(visualFramesBody) {
  const timestamps = [];
  for (const line of visualFramesBody.split("\n")) {
    if (!line.startsWith("| ~")) continue;
    const cols = line.split("|").map((c) => c.trim());
    const ts = parseMinuteTimestamp(cols[1] ?? "");
    if (ts !== null) timestamps.push(ts);
  }
  return timestamps;
}

/**
 * Exact timestamps for synthesis promotions (from selection.json, not floored minutes).
 *
 * @param {string} sliceDir
 * @returns {number[]}
 */
export function loadPromotedTimestampsSec(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const synthesisDir = lanePath(absSlice, LANES.keyFrames, "frames");
  if (!fs.existsSync(synthesisDir)) return [];

  const selectionPath = lanePath(absSlice, LANES.keyFrames, "selection.json");
  if (!fs.existsSync(selectionPath)) return [];

  const selection = JSON.parse(fs.readFileSync(selectionPath, "utf8"));
  const byFile = Object.fromEntries(selection.selectedFrames.map((f) => [f.file, f]));
  const mapPath = lanePath(absSlice, LANES.keyFrames, "promotion-map.json");
  const promotionMap = fs.existsSync(mapPath) ? JSON.parse(fs.readFileSync(mapPath, "utf8")) : {};

  const timestamps = [];
  for (const file of fs.readdirSync(synthesisDir)) {
    if (!file.endsWith(".png")) continue;
    const source = resolveSourceFile(file, promotionMap);
    const ts = source && byFile[source] ? byFile[source].timestampSec : null;
    if (ts !== null && ts !== undefined) timestamps.push(ts);
  }
  return timestamps;
}

/**
 * @param {string} contentClass
 * @param {number} durationSec
 * @param {number} sessionCount
 * @returns {{
 *   minSynthesisFrames: number,
 *   minPerHour: number,
 *   minPerSession: number,
 *   minSheetTriageRatio: number,
 *   minDensificationRatio: number,
 *   minPromotedDensificationRatio: number,
 * }}
 */
export function outcomeFloors(contentClass, durationSec, sessionCount) {
  const hours = durationSec / 3600;
  if (contentClass === "conference-multi-session" || hours >= 4) {
    return {
      minSynthesisFrames: Math.max(sessionCount * 4, Math.ceil(hours * 5)),
      minPerHour: 5,
      minPerSession: 3,
      minSheetTriageRatio: 0.75,
      minDensificationRatio: 0.35,
      minPromotedDensificationRatio: 0.25,
    };
  }
  if (hours >= 1) {
    return {
      minSynthesisFrames: Math.max(8, Math.ceil(hours * 3)),
      minPerHour: 3,
      minPerSession: 2,
      minSheetTriageRatio: 0.5,
      minDensificationRatio: 0.2,
      minPromotedDensificationRatio: 0.15,
    };
  }
  return {
    minSynthesisFrames: 2,
    minPerHour: 1,
    minPerSession: 1,
    minSheetTriageRatio: 0.25,
    minDensificationRatio: 0.1,
    minPromotedDensificationRatio: 0.05,
  };
}

/**
 * @param {string} visionPlanBody
 * @returns {string}
 */
export function detectContentClass(visionPlanBody) {
  const match = visionPlanBody.match(
    /`(conference-multi-session|single-talk|screencast|slide-talk)`/,
  );
  if (match) return match[1];
  if (visionPlanBody.includes("conference-multi-session")) return "conference-multi-session";
  if (visionPlanBody.includes("single-talk")) return "single-talk";
  return "unknown";
}

/**
 * Outcome floors from slice artifacts (vision-plan class + selection duration + session count).
 *
 * @param {string} sliceDir
 */
export function outcomeFloorsForSlice(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const selectionPath = lanePath(absSlice, LANES.keyFrames, "selection.json");
  const selection = fs.existsSync(selectionPath)
    ? JSON.parse(fs.readFileSync(selectionPath, "utf8"))
    : { durationSec: 0 };
  const visionPlanPath = lanePath(absSlice, LANES.keyFrames, "vision-plan.md");
  const visionPlan = fs.existsSync(visionPlanPath) ? fs.readFileSync(visionPlanPath, "utf8") : "";
  const claimPath = lanePath(absSlice, LANES.research, "claim-inventory.md");
  const sessions = fs.existsSync(claimPath)
    ? parseSessionsFromClaimInventory(fs.readFileSync(claimPath, "utf8"))
    : [];
  const contentClass = visionPlan.length > 100 ? detectContentClass(visionPlan) : "unknown";
  return outcomeFloors(contentClass, selection.durationSec ?? 0, sessions.length || 1);
}

/**
 * @param {string} frameTriageLogBody
 * @returns {number}
 */
export function countTriageSheetsLogged(frameTriageLogBody) {
  return (frameTriageLogBody.match(/^## sheet_\d+/gm) ?? []).length;
}

/**
 * @param {object} params
 * @param {number} params.durationSec
 * @param {{ startSec: number, endSec: number, densityMultiplier?: number }[]} params.windows
 * @param {number[]} params.promotedTimestampsSec
 * @param {string} params.visualGapsBody
 * @returns {{ covered: number, total: number }}
 */
export function densificationCoverage({
  durationSec: _durationSec,
  windows,
  promotedTimestampsSec,
  visualGapsBody,
}) {
  let covered = 0;
  for (const window of windows) {
    const inWindow = promotedTimestampsSec.some(
      (ts) => ts >= window.startSec && ts <= window.endSec,
    );
    const regionMin = Math.round(window.startSec / 60);
    const gapLogged =
      visualGapsBody.includes(`~${regionMin}m`) ||
      visualGapsBody.includes(`~${regionMin}–`) ||
      visualGapsBody.includes(`${regionMin}m`);
    if (inWindow || gapLogged) covered++;
  }
  return { covered, total: windows.length };
}

/**
 * @typedef {object} WatchOutcomeSlice
 * @property {string} sliceDir
 * @property {object} watch
 * @property {object|null} selection
 * @property {number} durationSec
 * @property {number} contactSheetCount
 * @property {{ startSec: number, endSec: number, densityMultiplier?: number }[]} windows
 * @property {number} synthesisCount
 * @property {string} visionPlanBody
 * @property {string} contentClass
 * @property {{ name: string, startSec: number, endSec: number|null }[]} sessions
 * @property {ReturnType<typeof outcomeFloors>} floors
 * @property {string} triageBody
 * @property {number} triageSheets
 * @property {number[]} promotedTs
 * @property {string} visualGapsBody
 * @property {string} claimInventoryPath
 * @property {string} manifestPath
 * @property {string} qualityAuditPath
 * @property {string} triageManifestPath
 * @property {string[]} synthesisPngs
 */

/**
 * @param {string} sliceDir
 * @returns {WatchOutcomeSlice|null}
 */
function loadWatchOutcomeSlice(sliceDir) {
  const watchPath = lanePath(sliceDir, LANES.runState, "watch.json");
  if (!fs.existsSync(watchPath)) return null;

  const selectionPath = lanePath(sliceDir, LANES.keyFrames, "selection.json");
  const synthesisDir = lanePath(sliceDir, LANES.keyFrames, "frames");
  const visionPlanPath = lanePath(sliceDir, LANES.keyFrames, "vision-plan.md");
  const triageLogPath = lanePath(sliceDir, LANES.keyFrames, "frame-triage-log.md");
  const visualGapsPath = lanePath(sliceDir, LANES.keyFrames, "visual-gaps.md");
  const claimInventoryPath = lanePath(sliceDir, LANES.research, "claim-inventory.md");
  const manifestPath = lanePath(sliceDir, LANES.keyFrames, "key-frames-manifest.md");
  const qualityAuditPath = lanePath(sliceDir, LANES.keyFrames, "key-frame-quality-audit.md");
  const triageManifestPath = lanePath(sliceDir, LANES.keyFrames, "triage", "manifest.json");

  const watch = JSON.parse(fs.readFileSync(watchPath, "utf8"));
  const selection = fs.existsSync(selectionPath)
    ? JSON.parse(fs.readFileSync(selectionPath, "utf8"))
    : null;
  const durationSec = selection?.durationSec ?? watch.phases?.watching?.metrics?.durationSec ?? 0;
  const contactSheetCount =
    selection?.contactSheets?.length ?? watch.artifactPaths?.contactSheetCount ?? 0;
  const windows = selection?.densificationWindows ?? [];
  const synthesisCount = fs.existsSync(synthesisDir)
    ? fs.readdirSync(synthesisDir).filter((f) => f.endsWith(".png")).length
    : 0;
  const visionPlanBody = fs.existsSync(visionPlanPath)
    ? fs.readFileSync(visionPlanPath, "utf8")
    : "";
  const contentClass = detectContentClass(visionPlanBody);
  const claimBody = fs.existsSync(claimInventoryPath)
    ? fs.readFileSync(claimInventoryPath, "utf8")
    : "";
  const sessions = parseSessionsFromClaimInventory(claimBody);

  return {
    sliceDir,
    watch,
    selection,
    durationSec,
    contactSheetCount,
    windows,
    synthesisCount,
    visionPlanBody,
    contentClass,
    sessions,
    floors: outcomeFloors(contentClass, durationSec, sessions.length || 1),
    triageBody: fs.existsSync(triageLogPath) ? fs.readFileSync(triageLogPath, "utf8") : "",
    triageSheets: countTriageSheetsLogged(
      fs.existsSync(triageLogPath) ? fs.readFileSync(triageLogPath, "utf8") : "",
    ),
    promotedTs: loadPromotedTimestampsSec(sliceDir),
    visualGapsBody: fs.existsSync(visualGapsPath) ? fs.readFileSync(visualGapsPath, "utf8") : "",
    claimInventoryPath,
    manifestPath,
    qualityAuditPath,
    triageManifestPath,
    synthesisPngs: listSynthesisPngs(sliceDir),
  };
}

/**
 * @param {OutcomeCheck[]} checks
 * @param {WatchOutcomeSlice} slice
 */
function pushArtifactAndFloorChecks(checks, slice) {
  const {
    visionPlanBody,
    claimInventoryPath,
    synthesisCount,
    contentClass,
    durationSec,
    floors,
    triageSheets,
    contactSheetCount,
  } = slice;

  checks.push({
    id: "vision-plan",
    pass: visionPlanBody.length > 100,
    actual: visionPlanBody.length > 100 ? "present" : "missing",
    expected: "key-frames/vision-plan.md before fan-out",
    severity: "fail",
  });
  checks.push({
    id: "claim-inventory",
    pass: fs.existsSync(claimInventoryPath),
    actual: fs.existsSync(claimInventoryPath) ? "present" : "missing",
    expected: "research/claim-inventory.md before research",
    severity: "fail",
  });
  checks.push({
    id: "synthesis-count-floor",
    pass: synthesisCount >= floors.minSynthesisFrames,
    actual: String(synthesisCount),
    expected: `>= ${floors.minSynthesisFrames} (${contentClass}, ${(durationSec / 3600).toFixed(1)}h)`,
    severity: "warn",
  });
  const perHour = durationSec > 0 ? synthesisCount / (durationSec / 3600) : 0;
  checks.push({
    id: "synthesis-per-hour",
    pass: perHour >= floors.minPerHour,
    actual: perHour.toFixed(2),
    expected: `>= ${floors.minPerHour}/h`,
    severity: "warn",
  });
  const triageRatio = contactSheetCount > 0 ? triageSheets / contactSheetCount : 0;
  checks.push({
    id: "sheet-triage-coverage",
    pass: triageRatio >= floors.minSheetTriageRatio,
    actual: `${triageSheets}/${contactSheetCount} (${(triageRatio * 100).toFixed(0)}%)`,
    expected: `>= ${(floors.minSheetTriageRatio * 100).toFixed(0)}% sheets with per-cell log`,
    severity: "fail",
  });
}

/**
 * @param {OutcomeCheck[]} checks
 * @param {WatchOutcomeSlice} slice
 */
function pushSessionCoverageChecks(checks, slice) {
  const { durationSec, windows, promotedTs, visualGapsBody, floors, sessions } = slice;
  const dens = densificationCoverage({
    durationSec,
    windows,
    promotedTimestampsSec: promotedTs,
    visualGapsBody,
  });
  const densRatio = dens.total > 0 ? dens.covered / dens.total : 1;
  checks.push({
    id: "densification-alignment",
    pass: densRatio >= floors.minDensificationRatio,
    actual: `${dens.covered}/${dens.total} (${(densRatio * 100).toFixed(0)}%)`,
    expected: `>= ${(floors.minDensificationRatio * 100).toFixed(0)}% windows promoted or gap-logged`,
    severity: "fail",
  });

  const sessionsWithoutFrame = sessions.filter((session) => {
    const end = session.endSec ?? durationSec;
    return !promotedTs.some((ts) => ts >= session.startSec && ts <= end);
  });
  checks.push({
    id: "session-visual-coverage",
    pass: sessionsWithoutFrame.length === 0,
    actual:
      sessionsWithoutFrame.length === 0
        ? "all sessions covered"
        : `missing: ${sessionsWithoutFrame.map((s) => s.name).join("; ")}`,
    expected: ">=1 synthesis frame per session segment",
    severity: "fail",
  });

  const sessionsBelowFloor = sessions.filter((session) => {
    const end = session.endSec ?? durationSec;
    const count = promotedTs.filter((ts) => ts >= session.startSec && ts <= end).length;
    return count < floors.minPerSession;
  });
  checks.push({
    id: "session-synthesis-depth",
    pass: sessionsBelowFloor.length === 0,
    actual:
      sessionsBelowFloor.length === 0
        ? `>=${floors.minPerSession} per session`
        : `thin: ${sessionsBelowFloor.map((s) => s.name).join("; ")}`,
    expected: `>=${floors.minPerSession} synthesis frames per session`,
    severity: "fail",
  });

  const densPromotedOnly = densificationCoverage({
    durationSec,
    windows,
    promotedTimestampsSec: promotedTs,
    visualGapsBody: "",
  });
  const densPromotedRatio =
    densPromotedOnly.total > 0 ? densPromotedOnly.covered / densPromotedOnly.total : 1;
  checks.push({
    id: "densification-promoted",
    pass: densPromotedRatio >= floors.minPromotedDensificationRatio,
    actual: `${densPromotedOnly.covered}/${densPromotedOnly.total} (${(densPromotedRatio * 100).toFixed(0)}%)`,
    expected: `>= ${(floors.minPromotedDensificationRatio * 100).toFixed(0)}% windows with synthesis frame (not gap-only)`,
    severity: "fail",
  });
}

/**
 * @param {OutcomeCheck[]} checks
 * @param {WatchOutcomeSlice} slice
 */
function pushTriageManifestChecks(checks, slice) {
  const { sliceDir, triageBody, triageManifestPath } = slice;
  const triageJson = validateTriageManifestForSlice(sliceDir, { requireIndexMatch: true });
  checks.push({
    id: "triage-json-present",
    pass: fs.existsSync(triageManifestPath) && triageJson.valid,
    actual: fs.existsSync(triageManifestPath)
      ? triageJson.valid
        ? "valid manifest"
        : triageJson.errors.slice(0, 2).join("; ")
      : "missing",
    expected: "key-frames/triage/manifest.json validates",
    severity: "fail",
  });

  const triageCellComplete =
    triageJson.valid && fs.existsSync(triageManifestPath) && triageJson.errors.length === 0;
  checks.push({
    id: "triage-cell-completeness",
    pass: triageCellComplete,
    actual: triageCellComplete ? "cells match index" : "incomplete cells",
    expected: "every sheet matches sheet-frame-index cell count",
    severity: "fail",
  });

  const triageAgenticErrors =
    fs.existsSync(triageManifestPath) && triageJson.valid
      ? validateTriageAgentic(JSON.parse(fs.readFileSync(triageManifestPath, "utf8")))
      : ["manifest missing or invalid"];
  checks.push({
    id: "triage-agentic-required",
    pass: triageAgenticErrors.length === 0,
    actual:
      triageAgenticErrors.length === 0
        ? "agentic model on all sheets"
        : triageAgenticErrors.slice(0, 2).join("; "),
    expected: "no selection-signals/heuristic triage; subagent vision per sheet",
    severity: "fail",
  });

  const triageBatchErrors =
    fs.existsSync(triageManifestPath) && triageJson.valid
      ? validateTriageBatchFiles(sliceDir, JSON.parse(fs.readFileSync(triageManifestPath, "utf8")))
      : ["manifest missing or invalid"];
  checks.push({
    id: "triage-batch-files-present",
    pass: triageBatchErrors.length === 0,
    actual:
      triageBatchErrors.length === 0
        ? "batch JSON per sheet"
        : triageBatchErrors.slice(0, 2).join("; "),
    expected: "key-frames/triage/batches/sheet_NNN.json exists for every manifest sheet",
    severity: "fail",
  });

  const hasMarkdownTriage = triageBody.length > 100;
  const hasJsonTriage = fs.existsSync(triageManifestPath);
  checks.push({
    id: "heuristic-triage-forbidden",
    pass: !hasMarkdownTriage || hasJsonTriage,
    actual: hasMarkdownTriage && !hasJsonTriage ? "markdown-only triage" : "json-backed",
    expected: "frame-triage-log requires key-frames/triage/manifest.json",
    severity: "fail",
  });
}

/**
 * @param {OutcomeCheck[]} checks
 * @param {WatchOutcomeSlice} slice
 */
function pushPromotionChecks(checks, slice) {
  const { sliceDir, synthesisPngs } = slice;
  const promotionDecisionsPath = lanePath(sliceDir, LANES.keyFrames, "promotion-decisions.json");
  const promotionValidation = validatePromotionDecisionsForSlice(sliceDir);
  checks.push({
    id: "promotion-decisions-present",
    pass:
      synthesisPngs.length === 0 ||
      (fs.existsSync(promotionDecisionsPath) && promotionValidation.valid),
    actual:
      synthesisPngs.length === 0
        ? "no synthesis pngs"
        : promotionValidation.valid
          ? "valid decisions"
          : promotionValidation.errors.slice(0, 2).join("; "),
    expected: "key-frames/promotion-decisions.json when key-frames/frames/ has PNGs",
    severity: "fail",
  });

  const forbiddenNames = synthesisPngs
    .map((name) => forbiddenSynthesisFileNameReason(name))
    .filter(Boolean);
  checks.push({
    id: "synthesis-filename-policy",
    pass: forbiddenNames.length === 0,
    actual:
      forbiddenNames.length === 0
        ? "all semantic names"
        : `${forbiddenNames.length} forbidden (${synthesisPngs[0]})`,
    expected:
      "no pipeline tokens (at-*, scene_*, dens-*, code-code-*, -mNNN, pipeline session slugs)",
    severity: "fail",
  });

  let traceabilityPass = synthesisPngs.length === 0;
  let traceabilityActual = "no synthesis pngs";
  if (synthesisPngs.length > 0 && fs.existsSync(promotionDecisionsPath)) {
    const decisions = JSON.parse(fs.readFileSync(promotionDecisionsPath, "utf8"));
    const mapPath = lanePath(sliceDir, LANES.keyFrames, "promotion-map.json");
    const promotionMap = fs.existsSync(mapPath) ? JSON.parse(fs.readFileSync(mapPath, "utf8")) : {};
    const promoteByDest = new Map(
      (decisions.decisions ?? [])
        .filter((d) => d.verdict === "promote")
        .map((d) => {
          const dest = d.destName.endsWith(".png") ? d.destName : `${d.destName}.png`;
          return [dest, d];
        }),
    );
    const missing = synthesisPngs.filter((png) => !promoteByDest.has(png) || !promotionMap[png]);
    traceabilityPass = missing.length === 0;
    traceabilityActual =
      missing.length === 0
        ? `${synthesisPngs.length} traced`
        : `untraced: ${missing.slice(0, 3).join(", ")}`;
  }
  checks.push({
    id: "promotion-traceability",
    pass: traceabilityPass,
    actual: traceabilityActual,
    expected: "every synthesis PNG has promote decision + promotion-map entry",
    severity: "fail",
  });
}

/**
 * @param {OutcomeCheck[]} checks
 * @param {WatchOutcomeSlice} slice
 */
function pushQualityAuditChecks(checks, slice) {
  const {
    sliceDir,
    watch,
    contactSheetCount,
    triageSheets,
    manifestPath,
    qualityAuditPath,
    synthesisPngs,
  } = slice;
  const qualityAuditJsonPath = lanePath(sliceDir, LANES.keyFrames, "key-frame-quality-audit.json");
  const qualityAuditValidation = validateQualityAuditForSlice(sliceDir);
  const auditFailures =
    // biome-ignore lint/suspicious/noUnnecessaryConditions: validateQualityAuditForSlice() returns without `doc` on the missing-audit branch, so `doc` may be undefined; Biome models only the doc-present shape.
    qualityAuditValidation.doc && Array.isArray(qualityAuditValidation.doc.files)
      ? qualityAuditValidation.doc.files.filter((f) => !f.pass)
      : [];

  let manifestRowCount = 0;
  if (fs.existsSync(manifestPath)) {
    manifestRowCount = fs
      .readFileSync(manifestPath, "utf8")
      .split("\n")
      .filter(
        (line) => line.startsWith("| ") && !line.includes("---") && !line.includes("Filename"),
      ).length;
  }

  const auditRowCount =
    // biome-ignore lint/suspicious/noUnnecessaryConditions: same as the auditFailures guard — validateQualityAuditForSlice() can return without `doc` (missing audit JSON), so `doc` may be undefined.
    qualityAuditValidation.doc && Array.isArray(qualityAuditValidation.doc.files)
      ? qualityAuditValidation.doc.files.length
      : 0;
  const parityPass =
    synthesisPngs.length === 0 ||
    (manifestRowCount === synthesisPngs.length &&
      auditRowCount === synthesisPngs.length &&
      qualityAuditValidation.valid);

  checks.push({
    id: "manifest-audit-parity",
    pass: parityPass,
    actual: `pngs=${synthesisPngs.length} manifestRows=${manifestRowCount} auditRows=${auditRowCount}`,
    expected: "manifest + audit JSON rows match synthesis PNG count",
    severity: "fail",
  });
  checks.push({
    id: "quality-audit-failures",
    pass: auditFailures.length === 0,
    actual:
      auditFailures.length === 0
        ? "no failures"
        : `${auditFailures.length} failing (${auditFailures.map((f) => f.name).join(", ")})`,
    expected: "delete or fix frames with pass:false in key-frame-quality-audit.json",
    severity: "fail",
  });
  checks.push({
    id: "quality-audit",
    pass:
      fs.existsSync(qualityAuditPath) &&
      fs.existsSync(manifestPath) &&
      fs.existsSync(qualityAuditJsonPath) &&
      qualityAuditValidation.valid,
    actual: [
      fs.existsSync(manifestPath) ? "manifest" : "no-manifest",
      fs.existsSync(qualityAuditPath) ? "audit-md" : "no-audit-md",
      fs.existsSync(qualityAuditJsonPath) ? "audit-json" : "no-audit-json",
    ].join(", "),
    expected: "manifest + key-frame-quality-audit.md + .json after promotion",
    severity: "fail",
  });

  const claimedTriaged = watch.phases?.vision?.metrics?.contactSheetsTriaged;
  if (typeof claimedTriaged === "number" && contactSheetCount > 0) {
    const honestRatio = triageSheets / contactSheetCount;
    checks.push({
      id: "vision-metrics-honesty",
      pass: honestRatio >= 0.5 || triageSheets >= claimedTriaged * 0.5,
      actual: `logged ${triageSheets} sheets; watch.json claims ${claimedTriaged}`,
      expected: "frame-triage-log matches watch.json vision metrics",
      severity: "warn",
    });
  }
}

/**
 * @param {OutcomeCheck[]} checks
 * @param {string} sliceDir
 */
function pushSynthesisCloseoutChecks(checks, sliceDir) {
  const actionable = validateActionableArtifactsForSlice(sliceDir);
  checks.push({
    id: "actionable-artifacts",
    pass: actionable.valid,
    actual: actionable.valid ? "hub + menu present" : actionable.errors.slice(0, 2).join("; "),
    expected: "recommendations/{README,menu,takeaways,questions,interview}.md",
    severity: "fail",
  });

  const checklist = validateWatchChecklistForCompleteSlice(sliceDir);
  if (!checklist.skipped) {
    checks.push({
      id: "watch-checklist-complete",
      pass: checklist.valid,
      actual: checklist.valid ? "blocking ticks checked" : checklist.errors.join("; "),
      expected: "8.1–8.4 and 9.1, 9.2, 9.4 ticked when status complete",
      severity: "fail",
    });
  }
}

/**
 * @param {string} sliceDir
 * @param {OutcomeCheck[]} checks
 * @param {boolean} pass
 * @returns {string}
 */
function writeWatchOutcomeReport(sliceDir, checks, pass) {
  const verificationDir = lanePath(sliceDir, LANES.verification);
  fs.mkdirSync(verificationDir, { recursive: true });
  // Latest report is authoritative: clear prior outcome reports before writing this run's.
  for (const name of fs.existsSync(verificationDir) ? fs.readdirSync(verificationDir) : []) {
    if (/-watch-outcomes\.md$/.test(name)) {
      fs.rmSync(path.join(verificationDir, name));
    }
  }
  const isoBasic = new Date()
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d+Z$/, "Z");
  const reportPath = path.join(verificationDir, `${isoBasic}-watch-outcomes.md`);
  const lines = [
    "# Outcome verification",
    "",
    `**Result:** ${pass ? "PASS" : "FAIL"}`,
    `**Generated:** ${new Date().toISOString()}`,
    "",
    "| Check | Status | Actual | Expected |",
    "| --- | --- | --- | --- |",
    ...checks.map((c) => {
      const status = c.pass ? "pass" : c.severity;
      return `| ${c.id} | ${status} | ${c.actual} | ${c.expected} |`;
    }),
    "",
    "## Interpretation",
    "",
    "- **Extraction** (bulk frames + contact sheets in temp) is separate from **curation** (synthesis key frames).",
    "- A long conference fails if sheet triage, session coverage, or densification alignment is shallow.",
    "- Re-run vision with full sheet fan-out before marking `watch.json` complete.",
    "",
  ];
  fs.writeFileSync(reportPath, lines.join("\n"));
  return reportPath;
}

/**
 * @param {string} sliceDir
 * @param {{ writeReport?: boolean }} [options]
 * @returns {{ pass: boolean, checks: OutcomeCheck[], reportPath?: string }}
 */
export function checkWatchOutcomes(sliceDir, { writeReport = false } = {}) {
  /** @type {OutcomeCheck[]} */
  const checks = [];
  const slice = loadWatchOutcomeSlice(sliceDir);
  if (!slice) {
    checks.push({
      id: "watch-json",
      pass: false,
      actual: "missing",
      expected: "watch.json present",
      severity: "fail",
    });
    return { pass: false, checks };
  }

  pushArtifactAndFloorChecks(checks, slice);
  pushSessionCoverageChecks(checks, slice);
  pushTriageManifestChecks(checks, slice);
  pushPromotionChecks(checks, slice);
  pushQualityAuditChecks(checks, slice);
  pushSynthesisCloseoutChecks(checks, sliceDir);

  const pass = checks.every((c) => c.pass || c.severity === "warn");
  const reportPath = writeReport ? writeWatchOutcomeReport(sliceDir, checks, pass) : undefined;
  return { pass, checks, reportPath };
}

/**
 * @param {string} sliceDir
 * @param {{ writeReport?: boolean }} [options]
 * @returns {number}
 */
export function runCheckWatchOutcomes(sliceDir, options = {}) {
  const result = checkWatchOutcomes(sliceDir, options);
  for (const check of result.checks) {
    const label = check.pass ? "PASS" : check.severity.toUpperCase();
    writeStderr(`${label}: ${check.id} — ${check.actual} (expected ${check.expected})`);
  }
  if (result.reportPath) {
    writeStdout(`Wrote ${result.reportPath}\n`);
  }
  return result.pass ? 0 : 1;
}

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  const sliceDir = process.argv[2];
  const writeReport = process.argv.includes("--write-report");
  if (!sliceDir) {
    writeStderr("Usage: node evals/check-watch-outcomes.js <slice-dir> [--write-report]");
    process.exit(2);
  }

  process.exitCode = runCheckWatchOutcomes(sliceDir, { writeReport });
}
