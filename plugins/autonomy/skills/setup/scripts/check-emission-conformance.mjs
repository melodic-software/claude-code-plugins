#!/usr/bin/env node

// Emission-conformance check for the telemetry contract: verifies produced
// OTLP JSON-lines declare the pinned schema URL and carry the work-item join
// attribute in normalized form. This is the contract's enforcement surface —
// adopters and the conforming-path demo run it against their artifact output.
//
// Usage: node check-emission-conformance.mjs <file-or-dir> [...more]
// Exit 0 = conformant; 1 = findings; 2 = usage/environment error.
//
// OTLP JSON encoding uses lowerCamelCase field names (resourceSpans,
// schemaUrl) — never the proto snake_case forms.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";

const PINNED_SCHEMA_URL = "https://opentelemetry.io/schemas/1.43.0";
const JOIN_ATTRIBUTE = "autonomy.work_item.url";
const NORMALIZED_URL = /^https:\/\/[^\s?#]+[^\s?#/]$/;

const findings = [];

function checkAttributeList(attributes, where, hits) {
  for (const attribute of attributes ?? []) {
    if (attribute.key !== JOIN_ATTRIBUTE) continue;
    hits.count += 1;
    const value = attribute.value?.stringValue;
    if (typeof value !== "string" || !NORMALIZED_URL.test(value)) {
      findings.push(
        `${where}: ${JOIN_ATTRIBUTE} value ${JSON.stringify(value)} is not a normalized canonical item URL (https, no trailing slash, no query/fragment)`,
      );
    }
  }
}

function checkResourceBlocks(blocks, file, line) {
  let sawSchemaUrl = false;
  const hits = { count: 0 };
  for (const [signalKey, block] of Object.entries(blocks)) {
    if (!Array.isArray(block)) continue;
    for (const entry of block) {
      const where = `${file}:${line} ${signalKey}`;
      if (entry.schemaUrl) {
        sawSchemaUrl = true;
        if (entry.schemaUrl !== PINNED_SCHEMA_URL) {
          findings.push(`${where}: schemaUrl ${entry.schemaUrl} != pinned ${PINNED_SCHEMA_URL}`);
        }
      }
      checkAttributeList(entry.resource?.attributes, `${where} resource`, hits);
      for (const scope of entry.scopeSpans ?? entry.scopeMetrics ?? entry.scopeLogs ?? []) {
        for (const item of scope.spans ?? scope.metrics ?? scope.logRecords ?? []) {
          checkAttributeList(item.attributes, `${where} ${item.name ?? "record"}`, hits);
        }
      }
    }
  }
  if (!sawSchemaUrl) {
    findings.push(`${file}:${line}: no schemaUrl declared on any resource block`);
  }
  return hits.count;
}

function filesUnder(target) {
  if (statSync(target).isDirectory()) {
    return readdirSync(target)
      .map((entry) => join(target, entry))
      .flatMap(filesUnder);
  }
  return /\.(?:json|jsonl|ndjson)$/.test(target) ? [target] : [];
}

const targets = process.argv.slice(2);
if (targets.length === 0) {
  console.error("usage: check-emission-conformance.mjs <file-or-dir> [...more]");
  process.exit(2);
}

let joinAttributeHits = 0;
let linesChecked = 0;
for (const target of targets.flatMap(filesUnder)) {
  const lines = readFileSync(target, "utf8").split(/\r?\n/).filter(Boolean);
  lines.forEach((raw, index) => {
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      findings.push(`${target}:${index + 1}: not valid JSON`);
      return;
    }
    linesChecked += 1;
    joinAttributeHits += checkResourceBlocks(parsed, target, index + 1);
  });
}

if (linesChecked === 0) {
  findings.push("no OTLP JSON lines found under the given targets");
}
if (joinAttributeHits === 0 && linesChecked > 0) {
  findings.push(`no occurrence of ${JOIN_ATTRIBUTE} anywhere in the checked output`);
}

if (findings.length > 0) {
  console.error("Emission conformance FAILED:");
  for (const finding of findings) console.error(`- ${finding}`);
  process.exit(1);
}
console.log(
  `Emission conformance OK: ${linesChecked} OTLP JSON lines, ${joinAttributeHits} join-attribute occurrence(s), schemaUrl pinned.`,
);
