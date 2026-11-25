#!/usr/bin/env node

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

function malformed(what) {
  process.stderr.write(`plugin-validate-report: ${what}\n`);
  process.exitCode = 2;
}

function emit(label, bucket) {
  if (bucket === null || bucket === undefined) return;
  if (typeof bucket !== "object") {
    malformed(`${label} is not an object`);
    return;
  }
  const file = typeof bucket.file === "string" ? bucket.file : "(no file)";
  for (const kind of ["errors", "warnings", "notes"]) {
    const items = bucket[kind];
    if (items === undefined) continue;
    if (!Array.isArray(items)) {
      malformed(`${file} ${kind} is not an array`);
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
  const gating = bucket.gatingHooks;
  if (gating === undefined) return;
  if (!Array.isArray(gating)) {
    malformed(`${file} gatingHooks is not an array`);
    return;
  }
  for (const item of gating) {
    if (item?.hasCatch !== false) continue;
    const where = typeof item.module === "string" ? `${item.module} ` : "";
    const hook = typeof item.hook === "string" ? item.hook : "(unnamed hook)";
    process.stdout.write(
      `${label}\t${file}\twarnings\t${where}gating hook without .catch: ${hook}\n`,
    );
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
  malformed("contents is not an array");
}
