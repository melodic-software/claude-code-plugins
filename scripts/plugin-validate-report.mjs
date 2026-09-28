#!/usr/bin/env node
// Render one `claude plugin validate --json` report as per-file findings.
//
// Stdin is the command's stdout. Exit 0 when the payload is a report object
// (success may still be false; the caller keeps the CLI's exit code). Exit 2
// when stdin is not that object, so the caller can fall back to text output.
//
// Report shape, from the plugin commands reference
// (https://code.claude.com/docs/en/plugins/cli-reference#plugin-validate):
// success, strict, target, manifest (or null), contents[] of {file, errors,
// warnings, notes}. Each finding is {path, message, code}.

import { readFileSync } from "node:fs";

const raw = readFileSync(0, "utf8").trim();
let report;
try {
  report = JSON.parse(raw);
} catch {
  process.exit(2);
}

if (
  report === null ||
  typeof report !== "object" ||
  Array.isArray(report) ||
  typeof report.success !== "boolean"
) {
  process.exit(2);
}

function emit(label, bucket) {
  if (bucket === null || bucket === undefined) return;
  if (typeof bucket !== "object") {
    process.stderr.write(`plugin-validate-report: ${label} is not an object\n`);
    process.exitCode = 2;
    return;
  }
  const file = typeof bucket.file === "string" ? bucket.file : "(no file)";
  for (const kind of ["errors", "warnings", "notes"]) {
    const items = bucket[kind];
    if (items === undefined) continue;
    if (!Array.isArray(items)) {
      process.stderr.write(
        `plugin-validate-report: ${file} ${kind} is not an array\n`,
      );
      process.exitCode = 2;
      continue;
    }
    for (const item of items) {
      const path =
        item && typeof item.path === "string" && item.path !== ""
          ? `${item.path}: `
          : "";
      const message =
        item && typeof item.message === "string"
          ? item.message
          : JSON.stringify(item);
      process.stdout.write(`${label}\t${file}\t${kind}\t${path}${message}\n`);
    }
  }
}

const target = typeof report.target === "string" ? report.target : "";
process.stdout.write(
  `validate\ttarget\t${target}\tsuccess=${report.success}\tstrict=${report.strict === true}\n`,
);
emit("manifest", report.manifest);
if (Array.isArray(report.contents)) {
  for (const entry of report.contents) emit("contents", entry);
} else if (report.contents != null) {
  process.stderr.write("plugin-validate-report: contents is not an array\n");
  process.exitCode = 2;
}
