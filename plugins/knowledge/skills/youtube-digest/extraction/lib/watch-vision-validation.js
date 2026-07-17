/**
 * Programmatic validators for watch vision JSON artifacts (mirrors tools/schemas/watch-*.schema.json).
 */

import fs from "node:fs";
import path from "node:path";

import { LANES, lanePath } from "./slice-lanes.js";
import {
  forbiddenSynthesisFileNameReason,
  isForbiddenPipelineSessionSlug,
  isStubQualityAuditNote,
} from "./synthesis-filename.js";

/** @typedef {'keep-detail'|'promote-key-frame'|'duplicate'|'blur'|'talking-head-only'|'skip'} TriageVerdict */

export const FORBIDDEN_TRIAGE_MODELS = new Set(["selection-signals", "heuristic", "prng"]);

export const TRIAGE_VERDICTS = new Set([
  "keep-detail",
  "promote-key-frame",
  "duplicate",
  "blur",
  "talking-head-only",
  "skip",
]);

export const CELL_IDS = [
  "R1C1",
  "R1C2",
  "R1C3",
  "R1C4",
  "R2C1",
  "R2C2",
  "R2C3",
  "R2C4",
  "R3C1",
  "R3C2",
  "R3C3",
  "R3C4",
  "R4C1",
  "R4C2",
  "R4C3",
  "R4C4",
];

const SHEET_ID_RE = /^sheet_\d{3}$/;
const CELL_ID_RE = /^R[1-4]C[1-4]$/;

export const ACTIONABLE_ARTIFACT_PATHS = [
  "recommendations/README.md",
  "recommendations/menu.md",
  "recommendations/takeaways.md",
  "recommendations/questions.md",
  "recommendations/interview.md",
];

/**
 * Narrow an unknown value to a plain record, or null when it is not a non-null object.
 *
 * @param {unknown} value
 * @returns {Record<string, unknown> | null}
 */
function asRecord(value) {
  return value && typeof value === "object" ? /** @type {Record<string, unknown>} */ (value) : null;
}

/**
 * Stringified `sheetId` when the record carries that key, else null. Distinct from a `?? "?"`
 * fallback: a record whose `sheetId` is present-but-undefined still yields `"undefined"`.
 *
 * @param {unknown} sheet
 * @returns {string | null}
 */
function readSheetId(sheet) {
  const record = asRecord(sheet);
  return record && "sheetId" in record ? String(record.sheetId) : null;
}

/**
 * @param {unknown} sheet
 * @param {number} [expectedCellCount=16]
 * @returns {string[]}
 */
export function validateTriageSheet(sheet, expectedCellCount = 16) {
  /** @type {string[]} */
  const errors = [];
  const s = asRecord(sheet);
  if (!s) {
    return ["sheet must be an object"];
  }
  if (typeof s.sheetId !== "string" || !SHEET_ID_RE.test(s.sheetId)) {
    errors.push("sheetId must match sheet_NNN");
  }
  if (typeof s.reviewedAt !== "string" || s.reviewedAt.length < 10) {
    errors.push("reviewedAt required (ISO timestamp)");
  }
  if (!Array.isArray(s.cells) || s.cells.length !== expectedCellCount) {
    errors.push(`cells must have exactly ${expectedCellCount} entries`);
    return errors;
  }
  const seenCells = new Set();
  for (const cell of s.cells) {
    const c = asRecord(cell);
    if (!c) {
      errors.push("each cell must be an object");
      continue;
    }
    if (typeof c.cell !== "string" || !CELL_ID_RE.test(c.cell)) {
      errors.push(`invalid cell id: ${String(c.cell)}`);
    } else if (seenCells.has(c.cell)) {
      errors.push(`duplicate cell id: ${c.cell}`);
    } else {
      seenCells.add(c.cell);
    }
    if (typeof c.frame !== "string" || c.frame.length === 0) {
      errors.push(`missing frame for cell ${String(c.cell)}`);
    }
    if (!TRIAGE_VERDICTS.has(/** @type {string} */ (c.verdict))) {
      errors.push(`invalid verdict for ${String(c.cell)}: ${String(c.verdict)}`);
    }
  }
  for (const expected of CELL_IDS.slice(0, expectedCellCount)) {
    if (!seenCells.has(expected)) {
      errors.push(`missing cell ${expected}`);
    }
  }
  return errors;
}

/**
 * @param {unknown} manifest
 * @param {Map<string, number>} [expectedCounts]
 * @returns {string[]}
 */
export function validateTriageManifest(manifest, expectedCounts = new Map()) {
  /** @type {string[]} */
  const errors = [];
  const m = asRecord(manifest);
  if (!m) {
    return ["manifest must be an object"];
  }
  if (!Array.isArray(m.sheets) || m.sheets.length === 0) {
    errors.push("sheets array required");
    return errors;
  }
  const seenIds = new Set();

  for (const sheet of m.sheets) {
    const sheetId = readSheetId(sheet);
    const expected = expectedCounts.get(sheetId ?? "") ?? 16;
    const sheetErrors = validateTriageSheet(sheet, expected);
    if (sheetErrors.length > 0) {
      errors.push(...sheetErrors.map((e) => `${sheetId ?? "?"}: ${e}`));
    }
    if (sheetId !== null) {
      if (seenIds.has(sheetId)) errors.push(`duplicate sheetId ${sheetId}`);
      seenIds.add(sheetId);
    }
  }
  return errors;
}

/**
 * @param {string} sliceDir
 * @param {unknown} manifest
 * @returns {string[]}
 */
export function validateTriageBatchFiles(sliceDir, manifest) {
  /** @type {string[]} */
  const errors = [];
  const m = asRecord(manifest);
  if (!m) {
    return ["manifest must be an object"];
  }
  const batchesDir = lanePath(path.resolve(sliceDir), LANES.keyFrames, "triage", "batches");
  const sheets = m.sheets;
  if (!Array.isArray(sheets)) {
    return ["sheets array required"];
  }
  for (const sheet of sheets) {
    const record = asRecord(sheet);
    if (!record) continue;
    const sheetId = String(record.sheetId ?? "?");
    const batchPath = path.join(batchesDir, `${sheetId}.json`);
    if (!fs.existsSync(batchPath)) {
      errors.push(`missing key-frames/triage/batches/${sheetId}.json`);
    }
  }
  return errors;
}

export function validateTriageAgentic(manifest) {
  /** @type {string[]} */
  const errors = [];
  const m = asRecord(manifest);
  if (!m) {
    return ["manifest must be an object"];
  }
  const sheets = m.sheets;
  if (!Array.isArray(sheets)) {
    return ["sheets array required"];
  }
  for (const sheet of sheets) {
    const record = asRecord(sheet);
    if (!record) continue;
    const sheetId = String(record.sheetId ?? "?");
    const model = typeof record.model === "string" ? record.model : "";
    if (!model) {
      errors.push(`${sheetId}: missing model (agentic triage required)`);
    } else if (FORBIDDEN_TRIAGE_MODELS.has(model)) {
      errors.push(`${sheetId}: forbidden model "${model}"`);
    }
  }
  return errors;
}

/**
 * @param {unknown} row
 * @param {number} index
 * @returns {string[]}
 */
function validatePromotionDecisionRow(row, index) {
  /** @type {string[]} */
  const errors = [];
  const r = asRecord(row);
  if (!r) {
    return [`decisions[${index}] must be an object`];
  }
  if (typeof r.sourceFile !== "string" || r.sourceFile.length === 0) {
    errors.push(`decisions[${index}].sourceFile required`);
  }
  if (r.verdict !== "promote" && r.verdict !== "reject") {
    errors.push(`decisions[${index}].verdict must be promote or reject`);
  }
  if (r.verdict === "promote") {
    if (typeof r.destName !== "string" || r.destName.length === 0) {
      errors.push(`decisions[${index}].destName required for promote`);
    } else {
      const destBase = r.destName.endsWith(".png") ? r.destName : `${r.destName}.png`;
      const forbidden = forbiddenSynthesisFileNameReason(destBase);
      if (forbidden) errors.push(`decisions[${index}].destName: ${forbidden}`);
    }
    if (typeof r.gapNote !== "string" || r.gapNote.trim().length < 8) {
      errors.push(`decisions[${index}].gapNote required for promote (min 8 chars)`);
    }
    if (typeof r.session === "string" && isForbiddenPipelineSessionSlug(r.session)) {
      errors.push(`decisions[${index}].session forbidden pipeline slug: ${r.session}`);
    }
  }
  if (r.verdict === "reject" && typeof r.rejectReason !== "string") {
    errors.push(`decisions[${index}].rejectReason required for reject`);
  }
  return errors;
}

/**
 * @param {unknown} doc
 * @returns {string[]}
 */
export function validatePromotionDecisions(doc) {
  const d = asRecord(doc);
  if (!d) {
    return ["promotion-decisions must be an object"];
  }
  if (!Array.isArray(d.decisions)) {
    return ["decisions array required"];
  }
  /** @type {string[]} */
  const errors = [];
  for (let i = 0; i < d.decisions.length; i++) {
    errors.push(...validatePromotionDecisionRow(d.decisions[i], i));
  }
  return errors;
}

/**
 * @param {unknown} doc
 * @returns {string[]}
 */
export function validateQualityAudit(doc) {
  /** @type {string[]} */
  const errors = [];
  const d = asRecord(doc);
  if (!d) {
    return ["quality audit must be an object"];
  }
  if (typeof d.reviewedAt !== "string" || d.reviewedAt.length < 10) {
    errors.push("reviewedAt required");
  }
  if (!Array.isArray(d.files)) {
    return ["files array required"];
  }
  for (let i = 0; i < d.files.length; i++) {
    const f = asRecord(d.files[i]);
    if (!f) {
      errors.push(`files[${i}] must be an object`);
      continue;
    }
    if (typeof f.name !== "string" || !f.name.endsWith(".png")) {
      errors.push(`files[${i}].name must be *.png`);
    }
    if (typeof f.pass !== "boolean") {
      errors.push(`files[${i}].pass must be boolean`);
    }
    // A passing row must carry a substantive note: an omitted note (not a
    // string) or a stub/short one both fail — this is the evidence the gate
    // exists to enforce exactly when pass=true claims review happened.
    if (f.pass === true && (typeof f.note !== "string" || isStubQualityAuditNote(f.note))) {
      errors.push(`files[${i}].note must be substantive (min 20 chars, not stub token)`);
    }
  }
  return errors;
}

/**
 * @param {string} sliceDir
 * @returns {{ valid: boolean, errors: string[] }}
 */
export function validateActionableArtifactsForSlice(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  /** @type {string[]} */
  const errors = [];
  for (const relPath of ACTIONABLE_ARTIFACT_PATHS) {
    const fullPath = path.join(absSlice, relPath);
    if (!fs.existsSync(fullPath)) {
      errors.push(`${relPath} missing`);
      continue;
    }
    const body = fs.readFileSync(fullPath, "utf8");
    if (body.trim().length < 40) {
      errors.push(`${relPath} too short`);
    }
  }
  const hubPath = lanePath(absSlice, LANES.recommendations, "README.md");
  if (fs.existsSync(hubPath)) {
    const hub = fs.readFileSync(hubPath, "utf8");
    for (const relPath of ACTIONABLE_ARTIFACT_PATHS.slice(1)) {
      const leaf = path.basename(relPath);
      if (!hub.includes(leaf)) {
        errors.push(`recommendations/README.md must link ${leaf}`);
      }
    }
  }
  return { valid: errors.length === 0, errors };
}

/**
 * @param {string} checklistBody
 * @returns {{ complete: boolean, missing: string[] }}
 */
export function parseWatchChecklistBlockingTicks(checklistBody) {
  const requiredIds = ["9.1", "9.2", "9.4", "8.1", "8.2", "8.3", "8.4"];
  /** @type {string[]} */
  const missing = [];
  for (const id of requiredIds) {
    const pattern = new RegExp(`- \\[x\\] \\*\\*${id.replace(".", "\\.")}\\*\\*`, "i");
    if (!pattern.test(checklistBody)) {
      missing.push(id);
    }
  }
  return { complete: missing.length === 0, missing };
}

/**
 * @param {string} sliceDir
 * @returns {{ valid: boolean, errors: string[], skipped: boolean }}
 */
export function validateWatchChecklistForCompleteSlice(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const watchPath = lanePath(absSlice, LANES.runState, "watch.json");
  if (!fs.existsSync(watchPath)) {
    return { valid: false, errors: ["watch.json missing"], skipped: false };
  }
  const watch = JSON.parse(fs.readFileSync(watchPath, "utf8"));
  if (watch.status !== "complete") {
    return { valid: true, errors: [], skipped: true };
  }
  const checklistPath = lanePath(absSlice, LANES.runState, "watch-checklist.md");
  if (!fs.existsSync(checklistPath)) {
    return { valid: false, errors: ["watch-checklist.md missing"], skipped: false };
  }
  const { complete, missing } = parseWatchChecklistBlockingTicks(
    fs.readFileSync(checklistPath, "utf8"),
  );
  if (complete) {
    return { valid: true, errors: [], skipped: false };
  }
  return {
    valid: false,
    errors: [`unchecked blocking ticks: ${missing.join(", ")}`],
    skipped: false,
  };
}

/**
 * @param {unknown} indexSheet
 * @param {unknown[]} manifestSheets
 * @returns {string[]}
 */
function validateIndexSheetParity(indexSheet, manifestSheets) {
  const sheet = asRecord(indexSheet);
  if (!sheet) return [];
  const sheetId = String(sheet.sheetId ?? "?");
  const manifestSheet = asRecord(
    manifestSheets.find((candidate) => {
      const record = asRecord(candidate);
      return record !== null && record.sheetId === sheet.sheetId;
    }),
  );
  if (!manifestSheet) {
    return [`missing manifest sheet ${sheetId}`];
  }

  /** @type {string[]} */
  const errors = [];
  const indexCells = Array.isArray(sheet.cells) ? sheet.cells : [];
  const manifestCells = Array.isArray(manifestSheet.cells) ? manifestSheet.cells : [];
  for (const indexCellRaw of indexCells) {
    const indexCell = asRecord(indexCellRaw);
    if (!indexCell) continue;
    const cellId = String(indexCell.cell ?? "?");
    const manifestCell = asRecord(
      manifestCells.find((candidate) => {
        const record = asRecord(candidate);
        return record !== null && record.cell === indexCell.cell;
      }),
    );
    if (!manifestCell) {
      errors.push(`${sheetId} missing cell ${cellId}`);
      continue;
    }
    if (manifestCell.frame !== indexCell.frame) {
      errors.push(
        `${sheetId} ${cellId} frame mismatch: ${String(manifestCell.frame)} vs ${String(indexCell.frame)}`,
      );
    }
  }
  return errors;
}

/**
 * @param {unknown[]} indexSheets
 * @param {unknown[]} manifestSheets
 * @returns {string[]}
 */
function validateTriageManifestIndexParity(indexSheets, manifestSheets) {
  /** @type {string[]} */
  const errors = [];
  if (indexSheets.length !== manifestSheets.length) {
    errors.push(
      `sheet count mismatch: manifest ${manifestSheets.length} vs index ${indexSheets.length}`,
    );
  }
  for (const indexSheet of indexSheets) {
    errors.push(...validateIndexSheetParity(indexSheet, manifestSheets));
  }
  return errors;
}

/**
 * @param {string} sliceDir
 * @param {object} [options]
 * @param {boolean} [options.requireIndexMatch]
 * @returns {{ valid: boolean, errors: string[] }}
 */
export function validateTriageManifestForSlice(sliceDir, { requireIndexMatch = true } = {}) {
  const absSlice = path.resolve(sliceDir);
  const manifestPath = lanePath(absSlice, LANES.keyFrames, "triage", "manifest.json");
  if (!fs.existsSync(manifestPath)) {
    return { valid: false, errors: ["key-frames/triage/manifest.json missing"] };
  }
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const indexPath = lanePath(absSlice, LANES.keyFrames, "sheet-frame-index.json");
  const indexExists = fs.existsSync(indexPath);
  const index = indexExists ? JSON.parse(fs.readFileSync(indexPath, "utf8")) : null;

  /** @type {Map<string, number>} */
  const expectedCounts = new Map();
  for (const indexSheet of index?.sheets ?? []) {
    expectedCounts.set(indexSheet.sheetId, indexSheet.cells.length);
  }

  const errors = validateTriageManifest(manifest, expectedCounts);

  if (requireIndexMatch && errors.length === 0 && indexExists) {
    errors.push(...validateTriageManifestIndexParity(index?.sheets ?? [], manifest.sheets ?? []));
  }

  return { valid: errors.length === 0, errors };
}

/**
 * @param {string} sliceDir
 * @returns {{ valid: boolean, errors: string[] }}
 */
export function validatePromotionDecisionsForSlice(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const decisionsPath = lanePath(absSlice, LANES.keyFrames, "promotion-decisions.json");
  if (!fs.existsSync(decisionsPath)) {
    return { valid: false, errors: ["key-frames/promotion-decisions.json missing"] };
  }
  const doc = JSON.parse(fs.readFileSync(decisionsPath, "utf8"));
  const errors = validatePromotionDecisions(doc);
  return { valid: errors.length === 0, errors };
}

/**
 * @param {string} sliceDir
 * @returns {{ valid: boolean, errors: string[], doc?: object }}
 */
export function validateQualityAuditForSlice(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const auditPath = lanePath(absSlice, LANES.keyFrames, "key-frame-quality-audit.json");
  if (!fs.existsSync(auditPath)) {
    return { valid: false, errors: ["key-frames/key-frame-quality-audit.json missing"] };
  }
  const doc = JSON.parse(fs.readFileSync(auditPath, "utf8"));
  const errors = validateQualityAudit(doc);
  return { valid: errors.length === 0, errors, doc };
}

/**
 * @param {string} sliceDir
 * @returns {string[]}
 */
export function listSynthesisPngs(sliceDir) {
  const synthesisDir = lanePath(path.resolve(sliceDir), LANES.keyFrames, "frames");
  if (!fs.existsSync(synthesisDir)) return [];
  return fs.readdirSync(synthesisDir).filter((f) => f.endsWith(".png"));
}
