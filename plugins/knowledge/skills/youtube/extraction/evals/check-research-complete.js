#!/usr/bin/env node
/**
 * Host verify script: research phase has RESEARCH.md and resolved agenda items.
 *
 * Usage: node evals/check-research-complete.js <slice-dir>
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";

/**
 * @param {string} sliceDir
 * @returns {number}
 */
export function checkResearchComplete(sliceDir) {
  const researchPath = path.join(sliceDir, "RESEARCH.md");
  const agendaPath = lanePath(sliceDir, LANES.research, "research-agenda.md");

  if (!fs.existsSync(researchPath)) {
    writeStderr(`FAIL: missing ${researchPath}`);
    return 1;
  }

  const researchBody = fs.readFileSync(researchPath, "utf8");
  if (researchBody.trim().length < 200) {
    writeStderr("FAIL: RESEARCH.md too short");
    return 1;
  }

  const inventoryPath = lanePath(sliceDir, LANES.research, "claim-inventory.md");
  if (!fs.existsSync(inventoryPath)) {
    writeStderr(`FAIL: missing ${inventoryPath}`);
    return 1;
  }

  // The agenda is required, not optional: without it the gate previously fell
  // through to success with no auditable claim-resolution plan.
  if (!fs.existsSync(agendaPath)) {
    writeStderr(`FAIL: missing ${agendaPath}`);
    return 1;
  }

  const agenda = fs.readFileSync(agendaPath, "utf8");
  const pendingRows = (agenda.match(/\|\s*pending\s*\|/gi) ?? []).length;
  if (pendingRows > 0) {
    writeStderr(`FAIL: ${pendingRows} research-agenda rows still pending`);
    return 1;
  }

  const openClaims = (agenda.match(/\|\s*T2\s*\|\s*$/gm) ?? []).length;
  if (openClaims > 0) {
    writeStderr(`WARN: ${openClaims} agenda rows may still be T2-only — verify promotion`);
  }

  const doneRows = (agenda.match(/\|\s*done\s*\|/gi) ?? []).length;
  const deferredRows = (agenda.match(/\|\s*deferred\s*\|/gi) ?? []).length;
  const findingsDir = lanePath(sliceDir, LANES.research, "findings");
  const findingCount = fs.existsSync(findingsDir)
    ? fs.readdirSync(findingsDir).filter((name) => name.endsWith(".md")).length
    : 0;
  if (doneRows > 0 && findingCount < doneRows) {
    writeStderr(`FAIL: research-findings count (${findingCount}) < done agenda rows (${doneRows})`);
    return 1;
  }
  if (doneRows + deferredRows === 0) {
    writeStderr("FAIL: research-agenda has no done or deferred rows");
    return 1;
  }

  return 0;
}

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  const sliceDir = process.argv[2];
  if (!sliceDir) {
    writeStderr("Usage: node evals/check-research-complete.js <slice-dir>");
    process.exit(2);
  }
  process.exitCode = checkResearchComplete(sliceDir);
}
