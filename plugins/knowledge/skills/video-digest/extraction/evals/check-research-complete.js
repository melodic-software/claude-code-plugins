#!/usr/bin/env node
/**
 * Host verify script: research phase has RESEARCH.md and resolved agenda items.
 *
 * Usage: node evals/check-research-complete.js <slice-dir>
 */

import fs from "node:fs";
import path from "node:path";

import { isMainModule } from "@melodic/video-digestion/shared/main-module";
import { writeStderr } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";

/**
 * @param {string} body
 * @param {RegExp} pattern
 * @returns {number}
 */
function countMatches(body, pattern) {
  return (body.match(pattern) ?? []).length;
}

/**
 * The research gate's first failure, or null when it passes.
 *
 * @param {string} sliceDir
 * @param {{ warn?: (message: string) => void }} [options]
 * @returns {string|null}
 */
export function researchGateFailure(sliceDir, { warn = writeStderr } = {}) {
  const researchPath = path.join(sliceDir, "RESEARCH.md");
  const agendaPath = lanePath(sliceDir, LANES.research, "research-agenda.md");

  if (!fs.existsSync(researchPath)) {
    return `missing ${researchPath}`;
  }

  const researchBody = fs.readFileSync(researchPath, "utf8");
  if (researchBody.trim().length < 200) {
    return "RESEARCH.md too short";
  }

  const inventoryPath = lanePath(sliceDir, LANES.research, "claim-inventory.md");
  if (!fs.existsSync(inventoryPath)) {
    return `missing ${inventoryPath}`;
  }

  // The agenda is required, not optional: without it, success would carry no
  // auditable claim-resolution plan.
  if (!fs.existsSync(agendaPath)) {
    return `missing ${agendaPath}`;
  }

  const agenda = fs.readFileSync(agendaPath, "utf8");
  const pendingRows = countMatches(agenda, /\|\s*pending\s*\|/gi);
  if (pendingRows > 0) {
    return `${pendingRows} research-agenda rows still pending`;
  }

  const openClaims = countMatches(agenda, /\|\s*T2\s*\|\s*$/gm);
  if (openClaims > 0) {
    warn(`WARN: ${openClaims} agenda rows may still be T2-only — verify promotion`);
  }

  const doneRows = countMatches(agenda, /\|\s*done\s*\|/gi);
  const deferredRows = countMatches(agenda, /\|\s*deferred\s*\|/gi);
  const findingsDir = lanePath(sliceDir, LANES.research, "findings");
  const findingCount = fs.existsSync(findingsDir)
    ? fs.readdirSync(findingsDir).filter((name) => name.endsWith(".md")).length
    : 0;
  if (doneRows > 0 && findingCount < doneRows) {
    return `research-findings count (${findingCount}) < done agenda rows (${doneRows})`;
  }
  if (doneRows + deferredRows === 0) {
    return "research-agenda has no done or deferred rows";
  }

  return null;
}

/**
 * @param {string} sliceDir
 * @returns {number}
 */
export function checkResearchComplete(sliceDir) {
  const failure = researchGateFailure(sliceDir);
  if (failure === null) return 0;
  writeStderr(`FAIL: ${failure}`);
  return 1;
}

if (isMainModule(import.meta.url)) {
  const sliceDir = process.argv[2];
  if (!sliceDir) {
    writeStderr("Usage: node evals/check-research-complete.js <slice-dir>");
    process.exit(2);
  }
  process.exitCode = checkResearchComplete(sliceDir);
}
