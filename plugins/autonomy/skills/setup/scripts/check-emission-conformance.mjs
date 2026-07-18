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

const findings = [];

// A normalized canonical item URL must parse as a real URL, not merely match a
// shape: https protocol, a non-empty hostname, none of query, fragment, or
// trailing slash — and it must round-trip the WHATWG parser unchanged
// (url.href === value), which is what "normalized" means. Round-tripping
// rejects values the parser silently repairs (empty host `https:///items/101`
// becomes `https://items/101`) and parsing rejects outright malformed ones
// (non-numeric port `https://h:abc/items/101`).
function isNormalizedCanonicalUrl(value) {
  if (typeof value !== "string" || /\s/.test(value)) return false;
  let url;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  return (
    url.protocol === "https:" &&
    url.hostname.length > 0 &&
    url.search === "" &&
    url.hash === "" &&
    url.href === value &&
    !value.includes("?") &&
    !value.includes("#") &&
    !value.endsWith("/")
  );
}

function checkAttributeList(attributes, where, hits) {
  for (const attribute of attributes ?? []) {
    if (attribute.key !== JOIN_ATTRIBUTE) continue;
    hits.count += 1;
    const value = attribute.value?.stringValue;
    if (!isNormalizedCanonicalUrl(value)) {
      findings.push(
        `${where}: ${JOIN_ATTRIBUTE} value ${JSON.stringify(value)} is not a normalized canonical item URL (https, no trailing slash, no query/fragment)`,
      );
    }
  }
}

function checkSchemaUrl(declared, where, tally) {
  if (!declared) return;
  tally.schemaUrlDeclared += 1;
  if (declared !== PINNED_SCHEMA_URL) {
    findings.push(`${where}: schemaUrl ${declared} != pinned ${PINNED_SCHEMA_URL}`);
  }
}

// Per the contract: contract-authored emissions declare the pinned schema URL;
// a native tool's emission is consumed as-is and may declare none. So absence
// on an individual entry is tolerated, every declared URL (resource-entry or
// scope level) must match the pin, and at least one emission in the whole
// checked set must declare it. The join attribute is required per resource
// entry — an export batch can carry several entries on one line, and a joined
// pipeline entry must not vouch for an unjoined session entry beside it.
function checkResourceBlocks(blocks, file, line, tally) {
  const result = { hits: 0, entries: 0 };
  for (const [signalKey, block] of Object.entries(blocks)) {
    if (!Array.isArray(block)) continue;
    block.forEach((entry, entryIndex) => {
      result.entries += 1;
      const where = `${file}:${line} ${signalKey}[${entryIndex}]`;
      const hits = { count: 0 };
      checkSchemaUrl(entry.schemaUrl, where, tally);
      checkAttributeList(entry.resource?.attributes, `${where} resource`, hits);
      for (const scope of entry.scopeSpans ?? entry.scopeMetrics ?? entry.scopeLogs ?? []) {
        checkSchemaUrl(scope.schemaUrl, `${where} scope`, tally);
        for (const item of scope.spans ?? scope.metrics ?? scope.logRecords ?? []) {
          checkAttributeList(item.attributes, `${where} ${item.name ?? "record"}`, hits);
        }
      }
      if (hits.count === 0) {
        findings.push(`${where}: resource entry carries no ${JOIN_ATTRIBUTE} attribute`);
      }
      result.hits += hits.count;
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
    const { hits, entries } = checkResourceBlocks(parsed, target, index + 1, tally);
    joinAttributeHits += hits;
    // Per-entry join enforcement lives in checkResourceBlocks; a line with no
    // recognizable OTLP resource entries at all is its own finding.
    if (entries === 0) {
      findings.push(`${target}:${index + 1}: no OTLP resource entries found on this line`);
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
