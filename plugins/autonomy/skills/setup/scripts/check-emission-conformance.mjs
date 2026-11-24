#!/usr/bin/env node

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { isNormalizedCanonicalUrl } from "./canonical-url.mjs";

const PINNED_SCHEMA_URL = "https://opentelemetry.io/schemas/1.43.0";
const JOIN_ATTRIBUTE = "autonomy.work_item.url";

const findings = [];
let schemaUrlDeclared = 0;

function checkAttributeList(attributes, where) {
  let hits = 0;
  for (const attribute of attributes ?? []) {
    if (attribute.key !== JOIN_ATTRIBUTE) continue;
    hits += 1;
    const value = attribute.value?.stringValue;
    if (!isNormalizedCanonicalUrl(value)) {
      findings.push(
        `${where}: ${JOIN_ATTRIBUTE} value ${JSON.stringify(value)} is not a normalized canonical item URL (https, no trailing slash, no query/fragment)`,
      );
    }
  }
  return hits;
}

function checkSchemaUrl(declared, where) {
  if (!declared) return;
  schemaUrlDeclared += 1;
  if (declared !== PINNED_SCHEMA_URL) {
    findings.push(`${where}: schemaUrl ${declared} != pinned ${PINNED_SCHEMA_URL}`);
  }
}

function checkResourceBlocks(blocks, file, line) {
  const result = { hits: 0, entries: 0 };
  for (const [signalKey, block] of Object.entries(blocks)) {
    if (!Array.isArray(block)) continue;
    block.forEach((entry, entryIndex) => {
      result.entries += 1;
      const where = `${file}:${line} ${signalKey}[${entryIndex}]`;
      checkSchemaUrl(entry.schemaUrl, where);
      let hits = checkAttributeList(entry.resource?.attributes, `${where} resource`);
      for (const scope of entry.scopeSpans ?? entry.scopeMetrics ?? entry.scopeLogs ?? []) {
        checkSchemaUrl(scope.schemaUrl, `${where} scope`);
        for (const item of scope.spans ?? scope.metrics ?? scope.logRecords ?? []) {
          hits += checkAttributeList(item.attributes, `${where} ${item.name ?? "record"}`);
        }
      }
      if (hits === 0) {
        findings.push(`${where}: resource entry carries no ${JOIN_ATTRIBUTE} attribute`);
      }
      result.hits += hits;
    });
  }
  return result;
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
    const where = `${target}:${index + 1}`;
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      findings.push(`${where}: not valid JSON`);
      return;
    }
    linesChecked += 1;
    const { hits, entries } = checkResourceBlocks(parsed, target, index + 1);
    joinAttributeHits += hits;
    if (entries === 0) {
      findings.push(`${where}: no OTLP resource entries found on this line`);
    }
  });
}

if (linesChecked === 0) {
  findings.push("no OTLP JSON lines found under the given targets");
}
if (schemaUrlDeclared === 0 && linesChecked > 0) {
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
  `Emission conformance OK: ${linesChecked} OTLP JSON lines, ${joinAttributeHits} join-attribute occurrence(s), ${schemaUrlDeclared} pinned schemaUrl declaration(s).`,
);
