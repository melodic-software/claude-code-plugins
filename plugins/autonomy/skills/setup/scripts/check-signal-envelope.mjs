#!/usr/bin/env node

// Exit 0 = conformant; 1 = findings; 2 = usage/environment error.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { isNormalizedCanonicalUrl, parseUrl } from "./canonical-url.mjs";

const MARKER = "<!-- autonomy:signal:v1 -->";
const SUPPORTED_SCHEMA_VERSIONS = new Set(["1.0"]);
const SURFACE_CLASSES = new Set(["tracker-vcs-event", "temporal", "agent-internal", "channel-feed"]);
const TRANSPORTS = new Set(["push", "push-lifecycle", "poll"]);
const PROVENANCES = new Set(["human", "agent", "system"]);
const WORK_CLASSES = new Set(["C1", "C2", "C3", "C4", "C5"]);
const ROUTINE_IDENTITY = /^[a-z][a-z0-9-]*(\/[a-z][a-z0-9-]*)?$/;
const REQUIRED_KEYS = [
  "signal.class",
  "signal.transport",
  "signal.provenance",
  "signal.identity",
  "signal.raw_link",
  "signal.traceparent",
];
// Version-00 traceparent only: https://www.w3.org/TR/trace-context/#traceparent-header
const TRACEPARENT = /^00-(?!0{32})[0-9a-f]{32}-(?!0{16})[0-9a-f]{16}-0[01]$/;

const findings = [];

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.length > 0;
}

function isAbsoluteHttpsUrl(value) {
  const url = parseUrl(value);
  return url !== null && url.protocol === "https:" && url.hostname.length > 0;
}

const NON_DURABLE_SCHEMES = new Set(["data", "javascript", "blob", "about", "http", "mailto", "tel", "vbscript"]);

function isDurableLocalUri(value, surfaceEntry) {
  const url = parseUrl(value);
  if (url === null) return false;
  if (url.protocol === "file:" || url.protocol === "https:") return true;
  const declared = Array.isArray(surfaceEntry?.artifact_schemes) ? surfaceEntry.artifact_schemes : [];
  return declared.some(
    (scheme) => !NON_DURABLE_SCHEMES.has(scheme) && url.protocol === `${scheme}:`,
  );
}

function underRunLinkPrefix(link, prefix) {
  const linkUrl = parseUrl(link);
  const prefixUrl = parseUrl(prefix);
  if (linkUrl === null || prefixUrl === null) return false;
  if (linkUrl.protocol !== prefixUrl.protocol) return false;
  if (linkUrl.host !== prefixUrl.host) return false;
  if (linkUrl.username !== "" || linkUrl.password !== "") return false;
  const linkPath = linkUrl.pathname;
  if (/%2e/i.test(linkPath)) return false;
  if (linkPath.split("/").some((segment) => segment === "." || segment === "..")) return false;
  const prefixPath = prefixUrl.pathname;
  return linkPath === prefixPath || linkPath.startsWith(prefixPath.endsWith("/") ? prefixPath : `${prefixPath}/`);
}

function gateSecurityBinding(securityBinding) {
  const violations = [];
  if (!isPlainObject(securityBinding)) {
    violations.push("the binding is not a JSON object");
    return violations;
  }
  const temporalHome = securityBinding.admission?.classification?.temporal;
  if (temporalHome === undefined) return violations;
  if (!isPlainObject(temporalHome)) {
    violations.push("admission.classification.temporal is not an object");
    return violations;
  }
  for (const [identity, entry] of Object.entries(temporalHome)) {
    if (!ROUTINE_IDENTITY.test(identity)) {
      violations.push(`admission.classification.temporal key ${JSON.stringify(identity)} is not a routine identity`);
    }
    if (!isPlainObject(entry)) {
      violations.push(
        `admission.classification.temporal entry ${JSON.stringify(identity)} is not the object form {class, source_surface, run_link_prefix, producer_identity}`,
      );
      continue;
    }
    if (!WORK_CLASSES.has(entry.class)) {
      violations.push(`admission.classification.temporal entry ${JSON.stringify(identity)}: class missing or invalid`);
    }
    for (const key of ["source_surface", "run_link_prefix", "producer_identity"]) {
      if (!isNonEmptyString(entry[key])) {
        violations.push(`admission.classification.temporal entry ${JSON.stringify(identity)}: ${key} missing or empty`);
      }
    }
  }
  return violations;
}

function extractEnvelope(body, where) {
  const markerIndex = body.indexOf(MARKER);
  if (markerIndex === -1) {
    findings.push(`${where}: no ${MARKER} marker record found`);
    return null;
  }
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

function collectSurfaces(binding) {
  const surfaces = new Map();
  const sections = new Map();
  const duplicates = new Set();
  for (const [sectionName, section] of Object.entries(binding ?? {})) {
    if (typeof section !== "object" || section === null) continue;
    const map = section.surfaces;
    if (typeof map !== "object" || map === null) continue;
    for (const [id, entry] of Object.entries(map)) {
      if (surfaces.has(id)) duplicates.add(id);
      else {
        surfaces.set(id, entry);
        sections.set(id, sectionName);
      }
    }
  }
  const enabledMap = binding?.routines?.enabled;
  const routinesEnabled = isPlainObject(enabledMap) ? enabledMap : null;
  return { surfaces, sections, duplicates, routinesEnabled };
}

function checkEnvelope(envelope, where, { surfaces, sections, duplicates, routinesEnabled, securityBinding }, bindingSupplied, securityBindingSupplied) {
  const version = envelope.schema_version;
  if (!SUPPORTED_SCHEMA_VERSIONS.has(version)) {
    findings.push(
      `${where}: schema_version ${JSON.stringify(version)} is not a supported version (${[...SUPPORTED_SCHEMA_VERSIONS].join(", ")})`,
    );
  }
  for (const key of REQUIRED_KEYS) {
    if (!isNonEmptyString(envelope[key])) {
      findings.push(`${where}: required key ${key} missing or empty`);
    }
  }
  for (const [key, tokens, noun] of [
    ["signal.class", SURFACE_CLASSES, "surface-class"],
    ["signal.transport", TRANSPORTS, "transport"],
    ["signal.provenance", PROVENANCES, "provenance"],
  ]) {
    const value = envelope[key];
    if (typeof value === "string" && !tokens.has(value)) {
      findings.push(`${where}: ${key} ${JSON.stringify(value)} is not a ${noun} token`);
    }
  }
  const signalClass = envelope["signal.class"];
  const workClass = envelope["signal.work_class"];
  if (workClass !== undefined && !WORK_CLASSES.has(workClass)) {
    findings.push(`${where}: signal.work_class ${JSON.stringify(workClass)} is not C1-C5 (omit the key when no class resolves)`);
  }
  const traceparent = envelope["signal.traceparent"];
  if (isNonEmptyString(traceparent) && !TRACEPARENT.test(traceparent)) {
    findings.push(`${where}: signal.traceparent ${JSON.stringify(traceparent)} is not a valid W3C traceparent`);
  }

  const parentItem = envelope["signal.parent_item"];
  if (signalClass === "agent-internal" && !isNormalizedCanonicalUrl(parentItem)) {
    findings.push(
      `${where}: signal.parent_item ${JSON.stringify(parentItem)} must be the emitting session's admitted source item as a normalized canonical https URL (required for agent-internal)`,
    );
  }

  const rawLink = envelope["signal.raw_link"];
  const sourceSurface = envelope["signal.source_surface"];
  const routine = envelope["signal.routine"];
  const producerIdentity = envelope["signal.producer_identity"];
  const routineIsIdentity = typeof routine === "string" && ROUTINE_IDENTITY.test(routine);
  let localScheduler = false;
  let surfaceEntry = null;
  let sourceSection = null;
  if (signalClass === "temporal") {
    if (routine !== undefined && !isNonEmptyString(routine)) {
      findings.push(
        `${where}: signal.routine must be a nonempty routine identity when the key is present — an empty or non-string claim is neither a conforming identity nor an absent one, fail-closed`,
      );
    } else if (typeof routine === "string" && !ROUTINE_IDENTITY.test(routine)) {
      findings.push(
        `${where}: signal.routine ${JSON.stringify(routine)} is not a routine identity — <class-token> or <class-token>/<posture-token>, each segment lowercase [a-z][a-z0-9-]*`,
      );
    }
    if (!isNonEmptyString(sourceSurface)) {
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
        sourceSection = sections.get(sourceSurface) ?? null;
      }
    }

    const stampedClass = typeof workClass === "string" && WORK_CLASSES.has(workClass);

    if (surfaceEntry !== null && routine === undefined) {
      if (sourceSection === "routines") {
        findings.push(`${where}: signal.routine missing (required for temporal signals from a routines-section surface)`);
      } else {
        if (stampedClass) {
          findings.push(
            `${where}: signal.work_class ${JSON.stringify(workClass)} is stamped on a detector-fired temporal signal (no routine identity claimed) — a detector emission has no admission.classification.temporal home, so the class cannot be attested and fails closed; omit the class (admission evaluates a classless enqueue with the work-class axis "*")`,
          );
        }
        if (producerIdentity !== undefined) {
          findings.push(
            `${where}: signal.producer_identity is stamped on a detector-fired temporal signal (no routine identity claimed) — the producer identity accompanies a routine claim, and with no routine identity it pins nothing; a detector emission carries neither`,
          );
        }
      }
    } else if (surfaceEntry !== null) {
      if (routineIsIdentity) {
        const enabledEntry =
          routinesEnabled !== null && typeof routinesEnabled[routine] === "object" && routinesEnabled[routine] !== null
            ? routinesEnabled[routine]
            : null;
        if (enabledEntry === null) {
          findings.push(
            `${where}: signal.routine ${JSON.stringify(routine)} has no routines.enabled entry in the autonomy binding — a claimed identity that no enabled routine records is either drift or a foreign claim, and it cannot be validated, fail-closed`,
          );
        } else {
          if (enabledEntry.source_surface !== sourceSurface) {
            findings.push(
              `${where}: signal.source_surface ${JSON.stringify(sourceSurface)} is not the surface the binding's routines.enabled entry records for ${JSON.stringify(routine)} (${JSON.stringify(enabledEntry.source_surface)}) — the enablement record and the emitting surface must agree, or the claim is drift the binding review never saw`,
            );
          }
          if (enabledEntry.enabled !== true) {
            findings.push(
              `${where}: signal.routine ${JSON.stringify(routine)} is not enabled in the binding's routines.enabled entry — a disabled routine emitting signals is a misconfiguration or a foreign claim, fail-closed`,
            );
          }
        }
      }
      if (!isNonEmptyString(producerIdentity)) {
        findings.push(
          `${where}: signal.producer_identity missing (required for routine-fired temporal signals) — the adapter must resolve it from the platform's authenticated run context, like signal.source_surface and signal.raw_link, so admission can pin which schedule within the ratified namespace produced the run`,
        );
      }
      if (stampedClass && !securityBindingSupplied) {
        findings.push(
          `${where}: signal.work_class ${JSON.stringify(workClass)} cannot be verified without --security-binding — the class association lives in the protected security binding, and an unverifiable class fails closed rather than certifying`,
        );
      }
      if (stampedClass && securityBindingSupplied && routineIsIdentity) {
        const temporalHome = securityBinding?.admission?.classification?.temporal;
        const classificationEntry =
          typeof temporalHome === "object" && temporalHome !== null ? temporalHome[routine] : undefined;
        if (typeof classificationEntry !== "object" || classificationEntry === null) {
          findings.push(
            `${where}: signal.work_class ${JSON.stringify(workClass)} has no admission.classification.temporal object entry for routine ${JSON.stringify(routine)} in the security binding — a class the protected binding never ratified is self-stamped and bypasses admission`,
          );
        } else {
          if (classificationEntry.source_surface !== sourceSurface) {
            findings.push(
              `${where}: signal.source_surface ${JSON.stringify(sourceSurface)} is not the emitting surface the security binding ratifies for routine ${JSON.stringify(routine)} (${JSON.stringify(classificationEntry.source_surface)}) — a wrongly associated identity/surface pair lets a swapped selector resolve a different class; the ratified association pins one surface per routine identity`,
            );
          }
          if (classificationEntry.class !== workClass) {
            findings.push(
              `${where}: signal.work_class ${JSON.stringify(workClass)} does not match the class the security binding ratifies for routine ${JSON.stringify(routine)} (${JSON.stringify(classificationEntry.class)}) — the work class rides the protected binding, never the envelope's own stamp`,
            );
          }
          const runLinkPrefix = classificationEntry.run_link_prefix;
          if (!isNonEmptyString(runLinkPrefix)) {
            findings.push(
              `${where}: the security binding ratifies no run_link_prefix for routine ${JSON.stringify(routine)} — without the ratified attestation anchor the run-permalink namespace cannot be pinned, so the stamped class fails closed (repair the security binding; check-security-binding.mjs rejects the entry too)`,
            );
          } else if (isNonEmptyString(rawLink) && !underRunLinkPrefix(rawLink, runLinkPrefix)) {
            findings.push(
              `${where}: signal.raw_link ${JSON.stringify(rawLink)} is outside the run-link namespace the security binding ratifies for routine ${JSON.stringify(routine)} (${JSON.stringify(runLinkPrefix)}) — the ratified run_link_prefix pins the platform-and-repository run-permalink namespace (which may be shared across schedules), and an agent-writable schedule cannot mint run permalinks outside it: a raw link outside the ratified prefix is not a platform-attested run in that namespace`,
            );
          }
          const ratifiedProducer = classificationEntry.producer_identity;
          if (!isNonEmptyString(ratifiedProducer)) {
            findings.push(
              `${where}: the security binding ratifies no producer_identity for routine ${JSON.stringify(routine)} — without the ratified producer the schedule within the run-permalink namespace cannot be pinned, so the stamped class fails closed (repair the security binding; check-security-binding.mjs rejects the entry too)`,
            );
          } else if (isNonEmptyString(producerIdentity) && producerIdentity !== ratifiedProducer) {
            findings.push(
              `${where}: signal.producer_identity ${JSON.stringify(producerIdentity)} does not match the producer the security binding ratifies for routine ${JSON.stringify(routine)} (${JSON.stringify(ratifiedProducer)}) — the producer identity the platform injects into the authenticated run context pins which schedule within the shared namespace ran; a mismatch means the claimed producer is not the schedule the binding ratifies for this routine identity`,
            );
          }
        }
      }
    }
  } else {
    if (routine !== undefined) {
      findings.push(
        `${where}: signal.routine is temporal-only — a routine identity stamped on a ${JSON.stringify(signalClass)} signal smuggles a routine run past the protected temporal admission mapping (a routine run always enters the queue as a temporal-class signal through its ratified scheduling surface; see routines.md)`,
      );
    }
    if (producerIdentity !== undefined) {
      findings.push(
        `${where}: signal.producer_identity is temporal-only — a producer identity stamped on a ${JSON.stringify(signalClass)} signal has no ratified run-permalink namespace or schedule to pin and smuggles a producer claim past the protected temporal admission mapping`,
      );
    }
  }
  if (
    isNonEmptyString(rawLink) &&
    (localScheduler ? !isDurableLocalUri(rawLink, surfaceEntry) : !isAbsoluteHttpsUrl(rawLink))
  ) {
    findings.push(
      `${where}: signal.raw_link ${JSON.stringify(rawLink)} is not a durable absolute reference (${localScheduler ? "local-scheduler origin allows file:, https:, or a binding-declared artifact scheme" : "this origin requires an absolute https URL"})`,
    );
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
let securityBindingPath = null;
for (let i = 0; i < args.length; i += 1) {
  if (args[i] === "--binding") {
    bindingPath = args[i + 1];
    i += 1;
  } else if (args[i] === "--security-binding") {
    securityBindingPath = args[i + 1];
    i += 1;
  } else {
    targets.push(args[i]);
  }
}
if (targets.length === 0) {
  console.error(
    "usage: check-signal-envelope.mjs <item-body-file-or-dir> [...more] [--binding <binding.json>] [--security-binding <security-binding.json>]",
  );
  process.exit(2);
}

let resolver = { surfaces: new Map(), sections: new Map(), duplicates: new Set(), routinesEnabled: null, securityBinding: null };
if (bindingPath !== null) {
  try {
    resolver = { ...resolver, ...collectSurfaces(JSON.parse(readFileSync(bindingPath, "utf8"))) };
  } catch (error) {
    console.error(`cannot read binding ${bindingPath}: ${error.message}`);
    process.exit(2);
  }
}
if (securityBindingPath !== null) {
  try {
    resolver = { ...resolver, securityBinding: JSON.parse(readFileSync(securityBindingPath, "utf8")) };
  } catch (error) {
    console.error(`cannot read security binding ${securityBindingPath}: ${error.message}`);
    process.exit(2);
  }
  for (const violation of gateSecurityBinding(resolver.securityBinding)) {
    findings.push(
      `--security-binding ${securityBindingPath}: ${violation} — the supplied security binding is itself invalid, so no envelope can certify against it; repair it and re-run check-security-binding.mjs (the authority, including checks this gate does not repeat)`,
    );
  }
}

let envelopesChecked = 0;
try {
  for (const target of targets.flatMap(filesUnder)) {
    const envelope = extractEnvelope(readFileSync(target, "utf8"), target);
    if (envelope === null) continue;
    envelopesChecked += 1;
    checkEnvelope(envelope, target, resolver, bindingPath !== null, securityBindingPath !== null);
  }
} catch (error) {
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
