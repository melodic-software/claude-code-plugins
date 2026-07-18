#!/usr/bin/env node
/**
 * Render key-frame-quality-audit.md from key-frame-quality-audit.json
 *
 * Usage: node watch/render-quality-audit.js <slice-dir>
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";

/**
 * @param {string} sliceDir
 * @returns {string}
 */
export function renderQualityAudit(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const auditPath = lanePath(absSlice, LANES.keyFrames, "key-frame-quality-audit.json");
  const doc = JSON.parse(fs.readFileSync(auditPath, "utf8"));

  const failures = doc.files.filter((f) => !f.pass);
  const lines = [
    "# Key frame quality audit",
    "",
    `Reviewed: ${doc.reviewedAt}`,
    "",
    "| File | Pass | Notes |",
    "| --- | --- | --- |",
  ];

  for (const file of doc.files) {
    lines.push(`| ${file.name} | ${file.pass ? "yes" : "no"} | ${file.note ?? ""} |`);
  }

  lines.push("");
  if (failures.length > 0) {
    lines.push(`**Rejected / pending delete:** ${failures.map((f) => f.name).join(", ")}`, "");
  } else {
    lines.push("**Rejected / deleted:** none", "");
  }

  const outPath = lanePath(absSlice, LANES.keyFrames, "key-frame-quality-audit.md");
  fs.writeFileSync(outPath, `${lines.join("\n")}\n`, "utf8");
  return outPath;
}

const sliceDir = process.argv[2];
const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  if (!sliceDir) {
    process.stderr.write("Usage: node watch/render-quality-audit.js <slice-dir>\n");
    process.exit(2);
  }
  writeStdout(`${renderQualityAudit(sliceDir)}\n`);
}
