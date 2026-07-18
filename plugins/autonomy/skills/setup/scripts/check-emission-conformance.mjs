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

// Per the contract: contract-authored emissions declare the pinned schema URL;
// a native tool's emission is consumed as-is and may declare none. So absence
// on an individual line is tolerated, a declared URL must match the pin, and
// at least one line in the whole checked set must declare it.
function checkResourceBlocks(blocks, file, line, tally) {
  const hits = { count: 0 };
  for (const [signalKey, block] of Object.entries(blocks)) {
    if (!Array.isArray(block)) continue;
    for (const entry of block) {
      const where = `${file}:${line} ${signalKey}`;
      if (entry.schemaUrl) {
        tally.schemaUrlDeclared += 1;
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
const tally = { schemaUrlDeclared: 0 };
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
    const hits = checkResourceBlocks(parsed, target, index + 1, tally);
    joinAttributeHits += hits;
    // Every emission must carry the join key somewhere (resource or item
    // attributes) — a single global hit would let an unjoined session emission
    // pass on the back of a conforming pipeline line.
    if (hits === 0) {
      findings.push(`${target}:${index + 1}: emission carries no ${JOIN_ATTRIBUTE} attribute`);
    }
  });
}

if (linesChecked === 0) {
  findings.push("no OTLP JSON lines found under the given targets");
}
if (tally.schemaUrlDeclared === 0 && linesChecked > 0) {
  findings.push(
    `no emission in the set declares the pinned schemaUrl (${PINNED_SCHEMA_URL}) — contract-authored emissions must`,
  );
}

if (findings.length > 0) {
  console.error("Emission conformance FAILED:");
  for (const finding of findings) console.error(`- ${finding}`);
  process.exit(1);
}
console.log(
  `Emission conformance OK: ${linesChecked} OTLP JSON lines, ${joinAttributeHits} join-attribute occurrence(s), ${tally.schemaUrlDeclared} pinned schemaUrl declaration(s).`,
);
