// Each judge leg's last step: the model's structured output is untrusted
// text, read from run-claude-cli's structured-output-file, checked for shape,
// and written as the leg's findings file. At most MAX_PER_UNIT findings survive.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { validateFinding } from "./findings.mjs";

export const MAX_PER_UNIT = 3;

export function parseJudgeOutput(text) {
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = null;
  }
  if (!Array.isArray(parsed?.findings)) return { findings: [], dropped: [{ index: null, reason: "unparsable" }] };
  const findings = [];
  const dropped = [];
  parsed.findings.forEach((finding, index) => {
    const bad = validateFinding(finding);
    if (bad.length > 0) dropped.push({ index, reason: bad.join(",") });
    else if (findings.length >= MAX_PER_UNIT) dropped.push({ index, reason: "over-limit" });
    else findings.push(finding);
  });
  return { findings, dropped };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const { STRUCTURED_OUTPUT_FILE, UNIT_ID, FINDINGS_PATH } = process.env;
  // An empty path means the leg left no structured output: unparsable.
  const { findings, dropped } = parseJudgeOutput(STRUCTURED_OUTPUT_FILE ? readFileSync(STRUCTURED_OUTPUT_FILE, "utf8") : "");
  mkdirSync(dirname(FINDINGS_PATH), { recursive: true });
  writeFileSync(FINDINGS_PATH, `${JSON.stringify({ unit: UNIT_ID, findings, dropped }, null, 2)}\n`);
  console.log(`write-findings: unit ${UNIT_ID}, kept ${findings.length}, dropped ${dropped.length}`);
}
