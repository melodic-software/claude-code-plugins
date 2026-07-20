#!/usr/bin/env node

// Signal-envelope check for the trigger-dispatch contract: validates the
// JSON-fenced `<!-- autonomy:signal:v1 -->` marker record on a queued item's
// body. This is the contract's enforcement surface — adopters and the
// conforming-path demo run it against created queue items.
//
// Usage: node check-signal-envelope.mjs <item-body-file-or-dir> [...more] [--binding <binding.json>] [--security-binding <security-binding.json>]
// Exit 0 = conformant; 1 = findings; 2 = usage/environment error.
//
// TWO binding inputs, two governance homes — never one file:
// --binding is the resolved schema-versioned AUTONOMY binding (repo-local,
// agent-writable): a temporal signal's `signal.source_surface` must resolve
// to a surface recorded there, and the surface's `scheduler_class`
// deterministically branches the `signal.raw_link` form (local-scheduler
// surfaces have no web origin, so a durable local/artifact URI is legal
// there and only there). Every additive binding section that records
// scheduling surfaces (triggers, routines) uses the same `surfaces` map
// shape; the resolver reads them all uniformly.
// --security-binding is the guardrails SECURITY binding (settings-as-code
// home, outside the agents' blast radius): its
// `admission.classification.temporal` table is where a temporal envelope's
// stamped `signal.work_class` must trace to — classification can never live
// in the agent-writable autonomy binding, or the agents it governs could
// rewrite it. A stamped class without --security-binding fails closed:
// unverifiable is never conformant.
//
// Honest boundary: this checker validates RECORDED evidence consistency —
// the envelope against the two bindings as written. Resolving
// `signal.source_surface` from the platform's authenticated run context at
// emit time (rather than trusting the handler's stamp) is the adapter's
// obligation under the trigger-dispatch contract, not something a static
// checker can perform.

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
// Routine identity: <class-token> or <class-token>/<posture-token> — the
// posture-qualified form is how a multi-posture routine class stamps which
// posture's classification the signal claims.
const ROUTINE_IDENTITY = /^[a-z][a-z0-9-]*(\/[a-z][a-z0-9-]*)?$/;
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

// Segment-boundary anchoring: the raw link equals the ratified prefix or
// continues with "/" immediately after it — plain startsWith would let
// ".../runs-evil" ride the ".../runs" namespace.
// Canonical run-namespace containment: parse BOTH sides and compare origin
// equality plus path-segment-boundary containment on the parsed pathnames —
// the URL parser resolves dot segments for the schemes it knows, so a
// lexical "/../" traversal cannot slip a canonical-outside link past a
// string-prefix test. Anything the parser leaves unresolved is rejected
// outright: a dot segment surviving in the parsed path (non-special
// schemes), or a percent-encoded dot in the path (server decoding behavior
// is unknowable here), is not certifiable evidence, fail-closed.
function underRunLinkPrefix(link, prefix) {
  const linkUrl = parseUrl(link);
  const prefixUrl = parseUrl(prefix);
  if (linkUrl === null || prefixUrl === null) return false;
  if (linkUrl.origin !== prefixUrl.origin) return false;
  const linkPath = linkUrl.pathname;
  if (/%2e/i.test(linkPath)) return false;
  if (linkPath.split("/").some((segment) => segment === "." || segment === "..")) return false;
  const prefixPath = prefixUrl.pathname;
  return linkPath === prefixPath || linkPath.startsWith(prefixPath.endsWith("/") ? prefixPath : `${prefixPath}/`);
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
// and routines both do). An id recorded by more than one section is AMBIGUOUS
// — resolution refuses it rather than silently picking a winner whose
// scheduler class may differ. Alongside the raw entry we record WHICH
// top-level section recorded each id — but the section is NOT the
// routine/detector discriminator: a routine may REUSE a surface the trigger
// slice already recorded under `triggers` (the binding refuses duplicate ids,
// so the reused record stays where it is and `routines.enabled` references
// it). Routine-fired status is the envelope's own `signal.routine` claim,
// validated against the `routines.enabled` map; the owning section decides
// only the missing-claim case (a surface recorded under `routines` exists
// solely to emit routine runs, so a claimless signal from it is
// nonconformant).
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
  const routinesEnabled =
    typeof enabledMap === "object" && enabledMap !== null && !Array.isArray(enabledMap) ? enabledMap : null;
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
  const routine = envelope["signal.routine"];
  const producerIdentity = envelope["signal.producer_identity"];
  let localScheduler = false;
  let surfaceEntry = null;
  let sourceSection = null;
  if (signalClass === "temporal") {
    // signal.routine's shape is checked whenever the KEY is present — an
    // empty or non-string value is a claim that is neither a conforming
    // identity nor an absent one, so it fails closed rather than slipping
    // between the claimed and claimless branches below; whether a routine is
    // REQUIRED is decided once the source surface resolves.
    if (routine !== undefined && (typeof routine !== "string" || routine.length === 0)) {
      findings.push(
        `${where}: signal.routine must be a nonempty routine identity when the key is present — an empty or non-string claim is neither a conforming identity nor an absent one, fail-closed`,
      );
    } else if (typeof routine === "string" && !ROUTINE_IDENTITY.test(routine)) {
      findings.push(
        `${where}: signal.routine ${JSON.stringify(routine)} is not a routine identity — <class-token> or <class-token>/<posture-token>, each segment lowercase [a-z][a-z0-9-]*`,
      );
    }
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
        sourceSection = sections.get(sourceSurface) ?? null;
      }
    }

    const stampedClass = typeof workClass === "string" && WORK_CLASSES.has(workClass);

    if (surfaceEntry !== null && routine === undefined) {
      // No routine identity claimed. From a routines-section surface that is
      // nonconformant (such a surface exists solely to emit routine runs);
      // from any other surface this is a detector-fired signal — legal, but
      // it has no admission.classification.temporal home, so a stamped class
      // can never be attested and fails closed, and a producer identity with
      // no routine claim pins nothing. An envelope WITHOUT a class stays
      // legal — an unclassified enqueue is human-gated downstream.
      if (sourceSection === "routines") {
        findings.push(`${where}: signal.routine missing (required for temporal signals from a routines-section surface)`);
      } else {
        if (stampedClass) {
          findings.push(
            `${where}: signal.work_class ${JSON.stringify(workClass)} is stamped on a detector-fired temporal signal (no routine identity claimed) — a detector emission has no admission.classification.temporal home, so the class cannot be attested and fails closed; omit the class (an unclassified enqueue is human-gated downstream)`,
          );
        }
        if (producerIdentity !== undefined) {
          findings.push(
            `${where}: signal.producer_identity is stamped on a detector-fired temporal signal (no routine identity claimed) — the producer identity accompanies a routine claim, and with no routine identity it pins nothing; a detector emission carries neither`,
          );
        }
      }
    } else if (surfaceEntry !== null) {
      // A routine identity is CLAIMED (whatever section recorded the surface
      // — a routine may reuse a triggers-recorded surface). The claim is
      // validated against the binding's routines.enabled map (the repo-local
      // enablement home: the identity must be an enabled routine whose
      // recorded source_surface agrees), a producer identity is required, and
      // a stamped class must trace to the SECURITY binding's
      // admission.classification.temporal entry that ratifies the exact
      // (routine, source_surface) association — the same rationale as the
      // agent-internal provenance rule: a self-stamped or wrongly associated
      // class bypasses admission, so the class rides the protected binding,
      // never the agent-writable autonomy binding or the agent-writable
      // scheduled workflow that stamped the identity. The routine, surface,
      // and producer fields are agent-controlled claims, so consistency among
      // them proves nothing on its own. Two ratified anchors pin the
      // producing schedule together, because a run-permalink namespace may be
      // repo-scoped and SHARED across every schedule: the run_link_prefix
      // pins the platform-and-repository namespace a raw link must fall
      // under, while the producer_identity — the workflow/unit reference the
      // platform injects into the authenticated run context — pins WHICH
      // schedule within that shared namespace produced the run. An envelope
      // WITHOUT signal.work_class stays legal: an unclassified enqueue is
      // human-gated downstream. The association check runs only once the
      // source surface RESOLVED — an unresolved surface already carries its
      // own finding above.
      if (typeof routine === "string" && ROUTINE_IDENTITY.test(routine)) {
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
      if (typeof producerIdentity !== "string" || producerIdentity.length === 0) {
        findings.push(
          `${where}: signal.producer_identity missing (required for routine-fired temporal signals) — the adapter must resolve it from the platform's authenticated run context, like signal.source_surface and signal.raw_link, so admission can pin which schedule within the ratified namespace produced the run`,
        );
      }
      if (stampedClass && !securityBindingSupplied) {
        findings.push(
          `${where}: signal.work_class ${JSON.stringify(workClass)} cannot be verified without --security-binding — the class association lives in the protected security binding, and an unverifiable class fails closed rather than certifying`,
        );
      }
      if (stampedClass && securityBindingSupplied && typeof routine === "string" && ROUTINE_IDENTITY.test(routine)) {
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
          if (typeof runLinkPrefix !== "string" || runLinkPrefix.length === 0) {
            findings.push(
              `${where}: the security binding ratifies no run_link_prefix for routine ${JSON.stringify(routine)} — without the ratified attestation anchor the run-permalink namespace cannot be pinned, so the stamped class fails closed (repair the security binding; check-security-binding.mjs rejects the entry too)`,
            );
          } else if (typeof rawLink === "string" && rawLink.length > 0 && !underRunLinkPrefix(rawLink, runLinkPrefix)) {
            findings.push(
              `${where}: signal.raw_link ${JSON.stringify(rawLink)} is outside the run-link namespace the security binding ratifies for routine ${JSON.stringify(routine)} (${JSON.stringify(runLinkPrefix)}) — the ratified run_link_prefix pins the platform-and-repository run-permalink namespace (which may be shared across schedules), and an agent-writable schedule cannot mint run permalinks outside it: a raw link outside the ratified prefix is not a platform-attested run in that namespace`,
            );
          }
          const ratifiedProducer = classificationEntry.producer_identity;
          if (typeof ratifiedProducer !== "string" || ratifiedProducer.length === 0) {
            findings.push(
              `${where}: the security binding ratifies no producer_identity for routine ${JSON.stringify(routine)} — without the ratified producer the schedule within the run-permalink namespace cannot be pinned, so the stamped class fails closed (repair the security binding; check-security-binding.mjs rejects the entry too)`,
            );
          } else if (typeof producerIdentity === "string" && producerIdentity.length > 0 && producerIdentity !== ratifiedProducer) {
            findings.push(
              `${where}: signal.producer_identity ${JSON.stringify(producerIdentity)} does not match the producer the security binding ratifies for routine ${JSON.stringify(routine)} (${JSON.stringify(ratifiedProducer)}) — the producer identity the platform injects into the authenticated run context pins which schedule within the shared namespace ran; a mismatch means the claimed producer is not the schedule the binding ratifies for this routine identity`,
            );
          }
        }
      }
    }
  } else {
    // signal.routine and signal.producer_identity are temporal-only identity
    // claims; stamped on any other class they fail closed rather than riding
    // past the protected admission mapping.
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
