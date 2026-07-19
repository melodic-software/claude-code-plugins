#!/usr/bin/env node

// Signal-envelope check for the trigger-dispatch contract: validates the
// JSON-fenced `<!-- autonomy:signal:v1 -->` marker record on a queued item's
// body. This is the contract's enforcement surface — adopters and the
// conforming-path demo run it against created queue items.
//
// Usage: node check-signal-envelope.mjs <item-body-file-or-dir> [...more] [--binding <binding.json>]
// Exit 0 = conformant; 1 = findings; 2 = usage/environment error.
//
// The binding input is the resolved schema-versioned autonomy binding: a
// temporal signal's `signal.source_surface` must resolve to a surface recorded
// there, and the surface's `scheduler_class` deterministically branches the
// `signal.raw_link` form (local-scheduler surfaces have no web origin, so a
// durable local/artifact URI is legal there and only there). Every additive
// binding section that records scheduling surfaces (triggers, routines) uses
// the same `surfaces` map shape; the resolver reads them all uniformly.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";

const MARKER = "<!-- autonomy:signal:v1 -->";
// Each supported minor version is added here together with its validation
// rules — an unknown 1.x must not certify semantics this checker cannot see.
const SUPPORTED_SCHEMA_VERSIONS = new Set(["1.0"]);
const SURFACE_CLASSES = new Set(["tracker-vcs-event", "temporal", "agent-internal", "channel-feed"]);
const TRANSPORTS = new Set(["push", "push-lifecycle", "poll"]);
const PROVENANCES = new Set(["human", "agent", "system"]);
const WORK_CLASSES = new Set(["C1", "C2", "C3", "C4", "C5"]);
const REQUIRED_KEYS = [
  "signal.class",
  "signal.transport",
  "signal.provenance",
  "signal.identity",
  "signal.raw_link",
  "signal.traceparent",
];
// W3C Trace Context traceparent: this contract supports version "00" only
// (and "ff" is forbidden by the spec outright); all-zero trace-id/parent-id
// invalid; version-00 trace flags define only the sampled bit (00 or 01 —
// reserved bits must not be set by the authoring adapter).
const TRACEPARENT = /^00-(?!0{32})[0-9a-f]{32}-(?!0{16})[0-9a-f]{16}-0[01]$/;

const findings = [];

function parseUrl(value) {
  if (typeof value !== "string" || /\s/.test(value) || value.length === 0) return null;
  try {
    return new URL(value);
  } catch {
    return null;
  }
}

// Absolute https URL with a host; query and fragment PRESERVED (permalinks and
// comment anchors need them — the telemetry strip rule is the join key's, not
// the raw link's).
function isAbsoluteHttpsUrl(value) {
  const url = parseUrl(value);
  return url !== null && url.protocol === "https:" && url.hostname.length > 0;
}

// Schemes that can never be durable artifact locators — rejected even when a
// binding declares them (a declaration cannot make data:/javascript: durable).
const NON_DURABLE_SCHEMES = new Set(["data", "javascript", "blob", "about", "http", "mailto", "tel", "vbscript"]);

// Durable local/artifact URI for local-scheduler-origin temporal signals:
// file: and https: qualify by contract; an org artifact-store scheme qualifies
// only when the binding's surface entry DECLARES it (artifact_schemes) AND the
// scheme is not in the non-durable set — an undeclared scheme never conforms.
function isDurableLocalUri(value, surfaceEntry) {
  const url = parseUrl(value);
  if (url === null) return false;
  if (url.protocol === "file:" || url.protocol === "https:") return true;
  const declared = Array.isArray(surfaceEntry?.artifact_schemes) ? surfaceEntry.artifact_schemes : [];
  return declared.some(
    (scheme) => !NON_DURABLE_SCHEMES.has(scheme) && url.protocol === `${scheme}:`,
  );
}

// The normalized canonical item URL per the telemetry contract's strip rule:
// https, non-empty host, no query/fragment/trailing slash, parser round-trip.
function isNormalizedCanonicalUrl(value) {
  const url = parseUrl(value);
  return (
    url !== null &&
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

function extractEnvelope(body, where) {
  const markerIndex = body.indexOf(MARKER);
  if (markerIndex === -1) {
    findings.push(`${where}: no ${MARKER} marker record found`);
    return null;
  }
  // The contract is ONE marker plus ONE fenced record bound to it — a second
  // marker is a conflict to surface for repair, never something to certify.
  if (body.indexOf(MARKER, markerIndex + MARKER.length) !== -1) {
    findings.push(`${where}: multiple ${MARKER} markers found — exactly one marker record is allowed`);
    return null;
  }
  const fence = body.slice(markerIndex + MARKER.length).match(/^\s*```json\s*\n([\s\S]*?)\n```/);
  if (!fence) {
    findings.push(`${where}: marker is not immediately followed by its fenced JSON record`);
    return null;
  }
  try {
    return JSON.parse(fence[1]);
  } catch {
    findings.push(`${where}: fenced record after the marker is not valid JSON`);
    return null;
  }
}

// Merge every `surfaces` map any top-level binding section records (triggers
// today, routines when that section lands). An id recorded by more than one
// section is AMBIGUOUS — resolution refuses it rather than silently picking a
// winner whose scheduler class may differ.
function collectSurfaces(binding) {
  const surfaces = new Map();
  const duplicates = new Set();
  for (const section of Object.values(binding ?? {})) {
    if (typeof section !== "object" || section === null) continue;
    const map = section.surfaces;
    if (typeof map !== "object" || map === null) continue;
    for (const [id, entry] of Object.entries(map)) {
      if (surfaces.has(id)) duplicates.add(id);
      else surfaces.set(id, entry);
    }
  }
  return { surfaces, duplicates };
}

function checkEnvelope(envelope, where, { surfaces, duplicates }, bindingSupplied) {
  const version = envelope.schema_version;
  if (!SUPPORTED_SCHEMA_VERSIONS.has(version)) {
    findings.push(
      `${where}: schema_version ${JSON.stringify(version)} is not a supported version (${[...SUPPORTED_SCHEMA_VERSIONS].join(", ")})`,
    );
  }
  for (const key of REQUIRED_KEYS) {
    const value = envelope[key];
    if (typeof value !== "string" || value.length === 0) {
      findings.push(`${where}: required key ${key} missing or empty`);
    }
  }
  const signalClass = envelope["signal.class"];
  if (typeof signalClass === "string" && !SURFACE_CLASSES.has(signalClass)) {
    findings.push(`${where}: signal.class ${JSON.stringify(signalClass)} is not a surface-class token`);
  }
  const transport = envelope["signal.transport"];
  if (typeof transport === "string" && !TRANSPORTS.has(transport)) {
    findings.push(`${where}: signal.transport ${JSON.stringify(transport)} is not a transport token`);
  }
  const provenance = envelope["signal.provenance"];
  if (typeof provenance === "string" && !PROVENANCES.has(provenance)) {
    findings.push(`${where}: signal.provenance ${JSON.stringify(provenance)} is not a provenance token`);
  }
  const workClass = envelope["signal.work_class"];
  if (workClass !== undefined && !WORK_CLASSES.has(workClass)) {
    findings.push(`${where}: signal.work_class ${JSON.stringify(workClass)} is not C1-C5 (omit the key when unclassified)`);
  }
  const traceparent = envelope["signal.traceparent"];
  if (typeof traceparent === "string" && traceparent.length > 0 && !TRACEPARENT.test(traceparent)) {
    findings.push(`${where}: signal.traceparent ${JSON.stringify(traceparent)} is not a valid W3C traceparent`);
  }

  // agent-internal: serialized provenance is REQUIRED — an unverifiable
  // self-stamped class would bypass admission.
  const parentItem = envelope["signal.parent_item"];
  if (signalClass === "agent-internal") {
    if (!isNormalizedCanonicalUrl(parentItem)) {
      findings.push(
        `${where}: signal.parent_item ${JSON.stringify(parentItem)} must be the emitting session's admitted source item as a normalized canonical https URL (required for agent-internal)`,
      );
    }
  }

  // raw_link form branches DETERMINISTICALLY on the serialized origin.
  const rawLink = envelope["signal.raw_link"];
  const sourceSurface = envelope["signal.source_surface"];
  let localScheduler = false;
  let surfaceEntry = null;
  if (signalClass === "temporal") {
    if (typeof sourceSurface !== "string" || sourceSurface.length === 0) {
      findings.push(`${where}: signal.source_surface missing (required for temporal signals)`);
    } else if (!bindingSupplied) {
      findings.push(`${where}: temporal signal requires --binding to resolve signal.source_surface`);
    } else if (duplicates.has(sourceSurface)) {
      findings.push(
        `${where}: signal.source_surface ${JSON.stringify(sourceSurface)} is recorded by more than one binding section — ambiguous, fix the binding`,
      );
    } else if (!surfaces.has(sourceSurface)) {
      findings.push(`${where}: signal.source_surface ${JSON.stringify(sourceSurface)} is not recorded in any binding surfaces map`);
    } else {
      const entry = surfaces.get(sourceSurface);
      if (entry?.class !== "temporal") {
        findings.push(
          `${where}: signal.source_surface ${JSON.stringify(sourceSurface)} resolves to a ${JSON.stringify(entry?.class)} surface — a temporal signal's source must be a temporal scheduling surface`,
        );
      } else if (entry.scheduler_class !== "ci-cron" && entry.scheduler_class !== "local-scheduler") {
        findings.push(
          `${where}: surface ${JSON.stringify(sourceSurface)} must declare scheduler_class "ci-cron" or "local-scheduler" (found ${JSON.stringify(entry.scheduler_class)}) — the required discriminator for temporal surfaces`,
        );
      } else {
        surfaceEntry = entry;
        localScheduler = entry.scheduler_class === "local-scheduler";
      }
    }
  }
  if (typeof rawLink === "string" && rawLink.length > 0) {
    if (localScheduler ? !isDurableLocalUri(rawLink, surfaceEntry) : !isAbsoluteHttpsUrl(rawLink)) {
      findings.push(
        `${where}: signal.raw_link ${JSON.stringify(rawLink)} is not a durable absolute reference (${localScheduler ? "local-scheduler origin allows file:, https:, or a binding-declared artifact scheme" : "this origin requires an absolute https URL"})`,
      );
    }
  }
}

function filesUnder(target) {
  if (statSync(target).isDirectory()) {
    return readdirSync(target)
      .map((entry) => join(target, entry))
      .flatMap(filesUnder);
  }
  return [target];
}

const args = process.argv.slice(2);
const targets = [];
let bindingPath = null;
for (let i = 0; i < args.length; i += 1) {
  if (args[i] === "--binding") {
    bindingPath = args[i + 1];
    i += 1;
  } else {
    targets.push(args[i]);
  }
}
if (targets.length === 0) {
  console.error("usage: check-signal-envelope.mjs <item-body-file-or-dir> [...more] [--binding <binding.json>]");
  process.exit(2);
}

let resolver = { surfaces: new Map(), duplicates: new Set() };
if (bindingPath !== null) {
  try {
    resolver = collectSurfaces(JSON.parse(readFileSync(bindingPath, "utf8")));
  } catch (error) {
    console.error(`cannot read binding ${bindingPath}: ${error.message}`);
    process.exit(2);
  }
}

let envelopesChecked = 0;
try {
  for (const target of targets.flatMap(filesUnder)) {
    const envelope = extractEnvelope(readFileSync(target, "utf8"), target);
    if (envelope === null) continue;
    envelopesChecked += 1;
    checkEnvelope(envelope, target, resolver, bindingPath !== null);
  }
} catch (error) {
  // A missing or unreadable target is an environment error (exit 2), never a
  // conformance finding.
  console.error(`cannot read target: ${error.message}`);
  process.exit(2);
}

if (envelopesChecked === 0) {
  findings.push("no signal envelopes found under the given targets — nothing was verified");
}

if (findings.length > 0) {
  console.error("Signal-envelope conformance FAILED:");
  for (const finding of findings) console.error(`- ${finding}`);
  process.exit(1);
}
console.log(`Signal-envelope conformance OK: ${envelopesChecked} envelope(s) checked.`);
