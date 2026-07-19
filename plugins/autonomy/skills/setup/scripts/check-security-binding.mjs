#!/usr/bin/env node

// Security-binding check for the guardrail contract: validates a security
// binding document against the contract-owned schema shape
// (schemas/guardrails-security-binding.schema.json — the structural rules are
// mirrored here, dependency-free) plus the semantic rules the schema cannot
// express: matrix merge caps, runtime-marker attestability and pairwise
// joint-satisfiability, per-surface class-aware isolation verdicts, promotion
// discipline, and admission floors/precedence.
//
// Usage: node check-security-binding.mjs <binding.json> [--evidence <evidence.json>] [--probe-evidence-root <dir>]
// Exit 0 = valid (verdicts printed); 1 = findings; 2 = usage/environment error.
//
// Probe verification: an L2/L3 isolation level counts toward eligibility only
// when its probe_evidence ref resolves (relative to --probe-evidence-root
// when given, else as written) to a transcript proving the boundary per the
// isolation-probe template's capture shape — an arbitrary string must never
// enable autonomous dispatch. Under autonomous-enabled an unverifiable entry
// is UNPROVEN: a finding, and the level is excluded from eligibility
// (fail-closed). Under human-gated-only there is no autonomous dispatch to
// protect, so unproven evidence is reported in the verdicts, not a finding.
//
// Evaluation mode (--evidence): resolves each promotion_state cell's EFFECTIVE
// state. The bound state is a CEILING — contrary evidence (gate-failure,
// reverted-merge, verification-divergence) lowers it to unpromoted at
// evaluation time WITHOUT writing the binding: automatic demotion has no
// write-back actor by design, because the binding is agent-unwritable; the
// demotion event files an escalation item requesting the human-ratified
// binding update. An unavailable evidence source fail-closes every cell to
// unpromoted rather than crashing. This is the same resolution the admission
// seam and the merge disposition MUST perform (querying the promotion-evidence
// telemetry) before every autonomous dispatch/merge decision — reading the raw
// promotion_state alone is non-conforming.

import { readFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import process from "node:process";

const WORK_CLASSES = ["C1", "C2", "C3", "C4", "C5"];
const LEVEL_TOKEN = /^L[0-3]$/;
const SURFACE_CLASSES = ["tracker-vcs-event", "temporal", "agent-internal", "channel-feed"];
const PROVENANCES = ["human", "agent", "system"];
const DISPOSITIONS = ["autonomous-eligible", "human-gated", "audited-rejection"];
const EVENT_CLASSES = [
  "gate-failure",
  "verification-divergence",
  "admission-rejection",
  "demotion",
  "structural-plan-approval",
  "untrusted-provenance",
];
const LAYERS = ["deterministic", "ai-review"];
const VERIFICATION_TOKENS = ["not-required", "advisory", "blocking"];
const MERGE_TOKENS = ["auto", "human"];
const CONTRARY_EVIDENCE_EVENTS = new Set(["gate-failure", "reverted-merge", "verification-divergence"]);
// The isolation-probe template's substrate-class tokens.
const SUBSTRATE_CLASSES = new Set(["container", "os-sandbox", "vm-microvm"]);
// Recognized host-credential-location tokens (lowercase, forward slashes).
// Same no-config-source rationale as the egress-host check: the checker
// cannot know the org's probed credential paths, so any entry not
// recognizably a credential location is rejected rather than trusted — a
// failing read of an arbitrary path proves nothing about credential absence.
const CREDENTIAL_LOCATION_TOKENS = [
  ".ssh",
  ".netrc",
  ".docker/config.json",
  ".aws",
  ".gnupg",
  ".kube/config",
  ".config/gh",
  "id_rsa",
  "credentials",
  "token",
];

// Guardrail-matrix floors: min-isolation level per class (L2 is the floor for
// ANY autonomous dispatch; C5 requires L3), and the only auto-merge-eligible
// cell (C2, after promotion — C4/C5 merge human always, C1/C3 human per the
// matrix).
const MIN_ISOLATION = { C1: 2, C2: 2, C3: 2, C4: 2, C5: 3 };
const AUTO_MERGE_ELIGIBLE = new Set(["C2"]);

// The security-review leaf's shipped per-class defaults are FLOORS: a binding
// may tighten a cell but never weaken it — the admission-rule
// override_justification escape applies to admission rules ONLY, never here.
const VERIFICATION_FLOORS = {
  deterministic: { C1: "not-required", C2: "blocking", C3: "blocking", C4: "blocking", C5: "blocking" },
  "ai-review": { C1: "not-required", C2: "not-required", C3: "advisory", C4: "blocking", C5: "blocking" },
};
const VERIFICATION_STRENGTH = { "not-required": 0, advisory: 1, blocking: 2 };

const PROMOTABLE_CELLS = new Set(["C2-auto-merge", "C3-ai-review-blocking"]);

// Admission shipped defaults per work class (the admission-policy leaf), and
// the leaf's permissiveness order: autonomous-eligible > human-gated >
// audited-rejection.
const ADMISSION_DEFAULTS = {
  C1: "autonomous-eligible",
  C2: "autonomous-eligible",
  C3: "human-gated",
  C4: "human-gated",
  C5: "human-gated",
};
const PERMISSIVENESS = { "audited-rejection": 0, "human-gated": 1, "autonomous-eligible": 2 };

const findings = [];

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.length > 0;
}

// Strict ISO 8601 date-time with an EXPLICIT offset (Z or +/-hh:mm),
// validated by regex AND a calendar round trip: Date.parse alone accepts
// forms like "06/30/2026" (timezone-dependent) and silently normalizes
// calendar-invalid values like 2026-02-30 to March 2 — either could shift an
// event across the promotion-epoch boundary. The epoch is derived from the
// captured components, never from Date.parse, so no engine-specific parsing
// behavior is load-bearing.
const ISO_DATE_TIME = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/;
function parseIsoStrict(value) {
  const match = typeof value === "string" ? ISO_DATE_TIME.exec(value) : null;
  if (match === null) return Number.NaN;
  const [, year, month, day, hour, minute, second, fraction, offset] = match;
  // Milliseconds truncate at three fraction digits — Date's own precision.
  const ms = Number((fraction ?? "").padEnd(3, "0").slice(0, 3) || "0");
  const utc = new Date(Date.UTC(+year, +month - 1, +day, +hour, +minute, +second, ms));
  // Date.UTC silently normalizes out-of-range fields; requiring the round
  // trip back to the supplied components rejects calendar-invalid values
  // (2026-02-30 fails, leap days pass).
  if (
    utc.getUTCFullYear() !== +year ||
    utc.getUTCMonth() !== +month - 1 ||
    utc.getUTCDate() !== +day ||
    utc.getUTCHours() !== +hour ||
    utc.getUTCMinutes() !== +minute ||
    utc.getUTCSeconds() !== +second
  ) {
    return Number.NaN;
  }
  const offsetMs =
    offset === "Z"
      ? 0
      : (offset[0] === "-" ? -1 : 1) *
        (Number(offset.slice(1, 3)) * 60 + Number(offset.slice(4, 6))) *
        60000;
  return utc.getTime() - offsetMs;
}

function checkAllowedKeys(object, allowed, where) {
  for (const key of Object.keys(object)) {
    if (!allowed.includes(key)) {
      findings.push(`${where}: unknown key ${JSON.stringify(key)} (additionalProperties: false)`);
    }
  }
}

function checkEnum(value, tokens, where) {
  if (!tokens.includes(value)) {
    findings.push(`${where}: ${JSON.stringify(value)} is not one of ${tokens.join(" | ")}`);
    return false;
  }
  return true;
}

// --- Structural validation (mirrors guardrails-security-binding.schema.json) ---

function validateStructure(binding) {
  if (!isPlainObject(binding)) {
    findings.push("binding: document root must be an object");
    return;
  }
  checkAllowedKeys(
    binding,
    [
      "schema_version",
      "executor_class",
      "dispatch_posture",
      "isolation_bindings",
      "merge_policy",
      "verification_blocking",
      "promotion_state",
      "escalation_routes",
      "admission",
    ],
    "binding",
  );
  for (const key of [
    "schema_version",
    "executor_class",
    "isolation_bindings",
    "merge_policy",
    "verification_blocking",
    "escalation_routes",
    "admission",
  ]) {
    if (!Object.hasOwn(binding, key)) findings.push(`binding: required key ${key} missing`);
  }
  if (Object.hasOwn(binding, "schema_version") && binding.schema_version !== "1.0") {
    findings.push(`schema_version: ${JSON.stringify(binding.schema_version)} is not the supported "1.0"`);
  }
  if (Object.hasOwn(binding, "executor_class")) {
    checkEnum(binding.executor_class, ["self-operated", "vendor-hosted"], "executor_class");
  }
  if (Object.hasOwn(binding, "dispatch_posture")) {
    checkEnum(binding.dispatch_posture, ["autonomous-enabled", "human-gated-only"], "dispatch_posture");
  }

  if (Object.hasOwn(binding, "isolation_bindings")) {
    if (!isPlainObject(binding.isolation_bindings)) {
      findings.push("isolation_bindings: must be an object keyed by execution-surface id");
    } else {
      for (const [surfaceId, levels] of Object.entries(binding.isolation_bindings)) {
        const surfaceWhere = `isolation_bindings.${surfaceId}`;
        if (!isPlainObject(levels)) {
          findings.push(`${surfaceWhere}: must be an object keyed by level token (L0-L3)`);
          continue;
        }
        for (const [level, entry] of Object.entries(levels)) {
          const where = `${surfaceWhere}.${level}`;
          if (!LEVEL_TOKEN.test(level)) {
            findings.push(`${where}: ${JSON.stringify(level)} is not a level token (L0-L3)`);
            continue;
          }
          if (!isPlainObject(entry)) {
            findings.push(`${where}: must be an object`);
            continue;
          }
          checkAllowedKeys(entry, ["substrate", "probe_evidence", "runtime_markers"], where);
          if (!isNonEmptyString(entry.substrate)) {
            findings.push(`${where}.substrate: missing or empty — the bound substrate instance id is required`);
          }
          if (!isNonEmptyString(entry.probe_evidence)) {
            findings.push(
              `${where}.probe_evidence: missing or empty — every bound isolation level carries the probe transcript reference that proved the boundary`,
            );
          }
          if (Object.hasOwn(entry, "runtime_markers")) {
            if (!isPlainObject(entry.runtime_markers)) {
              findings.push(`${where}.runtime_markers: must be an object of string key/value markers`);
            } else {
              for (const [marker, markerValue] of Object.entries(entry.runtime_markers)) {
                if (!isNonEmptyString(markerValue)) {
                  findings.push(`${where}.runtime_markers.${marker}: marker value must be a non-empty string`);
                }
              }
            }
          }
        }
      }
    }
  }

  if (Object.hasOwn(binding, "merge_policy")) {
    if (!isPlainObject(binding.merge_policy)) {
      findings.push("merge_policy: must be an object keyed by work class");
    } else {
      checkAllowedKeys(binding.merge_policy, WORK_CLASSES, "merge_policy");
      for (const workClass of WORK_CLASSES) {
        if (!Object.hasOwn(binding.merge_policy, workClass)) {
          findings.push(`merge_policy.${workClass}: required key missing`);
        } else {
          checkEnum(binding.merge_policy[workClass], MERGE_TOKENS, `merge_policy.${workClass}`);
        }
      }
    }
  }

  if (Object.hasOwn(binding, "verification_blocking")) {
    if (!isPlainObject(binding.verification_blocking)) {
      findings.push("verification_blocking: must be an object keyed by layer");
    } else {
      checkAllowedKeys(binding.verification_blocking, LAYERS, "verification_blocking");
      for (const layer of LAYERS) {
        const where = `verification_blocking.${layer}`;
        const perClass = binding.verification_blocking[layer];
        if (!isPlainObject(perClass)) {
          findings.push(`${where}: required per-class knob object missing`);
          continue;
        }
        checkAllowedKeys(perClass, WORK_CLASSES, where);
        for (const workClass of WORK_CLASSES) {
          if (!Object.hasOwn(perClass, workClass)) {
            findings.push(`${where}.${workClass}: required key missing`);
          } else {
            checkEnum(perClass[workClass], VERIFICATION_TOKENS, `${where}.${workClass}`);
          }
        }
      }
    }
  }

  if (Object.hasOwn(binding, "promotion_state")) {
    if (!isPlainObject(binding.promotion_state)) {
      findings.push("promotion_state: must be an object keyed by promotable cell id");
    } else {
      for (const [cell, entry] of Object.entries(binding.promotion_state)) {
        const where = `promotion_state.${cell}`;
        if (!isPlainObject(entry)) {
          findings.push(`${where}: must be an object`);
          continue;
        }
        checkAllowedKeys(entry, ["state", "ratified_by_change", "evidence_window", "ratified_at"], where);
        if (!Object.hasOwn(entry, "state") || !checkEnum(entry.state, ["promoted", "unpromoted"], `${where}.state`)) continue;
        if (!isNonEmptyString(entry.ratified_by_change)) {
          findings.push(`${where}.ratified_by_change: missing or empty — the flip is a reviewable change on the governance surface`);
        }
        if (!isNonEmptyString(entry.evidence_window)) {
          findings.push(`${where}.evidence_window: missing or empty — the telemetry window the evidence predicate was satisfied over`);
        }
        if (Number.isNaN(parseIsoStrict(entry.ratified_at))) {
          findings.push(
            `${where}.ratified_at: missing, not strict ISO 8601 with explicit offset (Z or +/-hh:mm), or not a calendar-valid instant — the ratification instant anchors the promotion epoch contrary evidence is scoped to, so its interpretation must depend on neither the evaluator's timezone nor silent date normalization`,
          );
        }
      }
    }
  }

  if (Object.hasOwn(binding, "escalation_routes")) {
    if (!isPlainObject(binding.escalation_routes)) {
      findings.push("escalation_routes: must be an object keyed by escalation event class");
    } else {
      checkAllowedKeys(binding.escalation_routes, EVENT_CLASSES, "escalation_routes");
      for (const eventClass of EVENT_CLASSES) {
        if (!isNonEmptyString(binding.escalation_routes[eventClass])) {
          findings.push(`escalation_routes.${eventClass}: missing or empty — every event class has an org-bound route`);
        }
      }
    }
  }

  if (Object.hasOwn(binding, "admission")) validateAdmissionStructure(binding.admission);
}

function validateAdmissionStructure(admission) {
  if (!isPlainObject(admission)) {
    findings.push("admission: must be an object");
    return;
  }
  checkAllowedKeys(admission, ["classification", "rules", "autonomous_concurrency", "items_per_run"], "admission");
  for (const key of ["classification", "rules", "autonomous_concurrency", "items_per_run"]) {
    if (!Object.hasOwn(admission, key)) findings.push(`admission.${key}: required key missing`);
  }

  if (Object.hasOwn(admission, "classification")) {
    if (!isPlainObject(admission.classification)) {
      findings.push("admission.classification: must be an object keyed by signal-surface class");
    } else {
      checkAllowedKeys(admission.classification, SURFACE_CLASSES, "admission.classification");
      for (const [surfaceClass, ruleHome] of Object.entries(admission.classification)) {
        const where = `admission.classification.${surfaceClass}`;
        if (!isPlainObject(ruleHome)) {
          findings.push(`${where}: must be an object mapping signal markers to work classes`);
          continue;
        }
        for (const [marker, workClass] of Object.entries(ruleHome)) {
          checkEnum(workClass, WORK_CLASSES, `${where}.${JSON.stringify(marker)}`);
        }
      }
    }
  }

  if (Object.hasOwn(admission, "rules")) {
    if (!Array.isArray(admission.rules)) {
      findings.push("admission.rules: must be an array of decision-table rules");
    } else {
      admission.rules.forEach((rule, index) => {
        const where = `admission.rules[${index}]`;
        if (!isPlainObject(rule)) {
          findings.push(`${where}: must be an object`);
          return;
        }
        checkAllowedKeys(
          rule,
          ["signal_class", "provenance", "work_class", "disposition", "override_justification"],
          where,
        );
        checkEnum(rule.signal_class, [...SURFACE_CLASSES, "*"], `${where}.signal_class`);
        checkEnum(rule.provenance, [...PROVENANCES, "*"], `${where}.provenance`);
        checkEnum(rule.work_class, [...WORK_CLASSES, "*"], `${where}.work_class`);
        checkEnum(rule.disposition, DISPOSITIONS, `${where}.disposition`);
        if (Object.hasOwn(rule, "override_justification") && !isNonEmptyString(rule.override_justification)) {
          findings.push(`${where}.override_justification: must be a non-empty string when present`);
        }
      });
    }
  }

  for (const cap of ["autonomous_concurrency", "items_per_run"]) {
    if (Object.hasOwn(admission, cap) && (!Number.isInteger(admission[cap]) || admission[cap] < 1)) {
      findings.push(`admission.${cap}: must be an integer >= 1`);
    }
  }
}

// --- Semantic rules the schema cannot express ---

function levelNumber(token) {
  return Number(token.slice(1));
}

// Two conjunctive marker predicates are jointly satisfiable — and the binding
// AMBIGUOUS — unless they require conflicting values for at least one shared
// key: a runtime context carrying the union of two non-conflicting predicates
// matches both. Subset/identity checks alone miss e.g. {pool: blue, region:
// us} vs {pool: blue, os: linux}.
function jointlySatisfiable(markersA, markersB) {
  for (const [key, value] of Object.entries(markersA)) {
    if (Object.hasOwn(markersB, key) && markersB[key] !== value) return false;
  }
  return true;
}

// The egress-probe target must be a genuinely EXTERNAL host — loopback,
// private, link-local, and single-label targets prove nothing about external
// egress, and alternate ENCODINGS of local addresses must not slip past a
// textual deny list: trailing-dot hostnames, bracketed literals, v4-mapped
// IPv6 (::ffff:127.0.0.1, hex ::ffff:7f00:1), and inet_aton numeric forms
// (2130706433 = 0x7f000001 = 127.1 = 127.0.0.1) all normalize before
// classification. Deny-list + shape rule: the checker has no config source
// for the org's configured probe target, so a positive allow-check is not
// possible — the acceptance shape is a multi-label DNS name or a public
// literal IP.
const INET_PART = /^(?:0[xX][0-9a-fA-F]+|0[0-7]*|[1-9]\d*)$/;

// inet_aton semantics: 1-4 dot-separated parts (decimal, 0x-hex, or
// 0-octal); the last part fills the remaining bytes. Returns the folded
// 32-bit address, or null where the token is not an address.
function foldInetAton(token) {
  const parts = token.split(".");
  if (parts.length > 4 || parts.some((part) => part === "" || !INET_PART.test(part))) return null;
  const values = parts.map((part) =>
    /^0[xX]/.test(part) ? Number.parseInt(part, 16) : /^0./.test(part) ? Number.parseInt(part, 8) : Number(part),
  );
  const last = values[values.length - 1];
  if (values.slice(0, -1).some((value) => value > 255) || last > 2 ** (8 * (5 - values.length)) - 1) return null;
  let addr = 0;
  for (let i = 0; i < values.length - 1; i += 1) addr = addr * 256 + values[i];
  return addr * 256 ** (5 - values.length) + last;
}

function isDeniedV4(addr) {
  const a = Math.floor(addr / 16777216) % 256;
  const b = Math.floor(addr / 65536) % 256;
  return (
    a === 0 ||
    a === 127 ||
    a === 10 ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 169 && b === 254)
  );
}

function isNonExternalEgressHost(host) {
  const h = host.toLowerCase().replace(/^\[|\]$/g, "");
  if (h.includes(":")) {
    if (h === "::1" || h === "::") return true;
    const mapped = /^::ffff:(.+)$/.exec(h);
    if (mapped !== null) {
      let embedded = null;
      if (mapped[1].includes(".")) {
        embedded = foldInetAton(mapped[1]);
      } else {
        const groups = /^([0-9a-f]{1,4}):([0-9a-f]{1,4})$/.exec(mapped[1]);
        if (groups !== null) {
          embedded = Number.parseInt(groups[1], 16) * 65536 + Number.parseInt(groups[2], 16);
        }
      }
      return embedded === null || isDeniedV4(embedded);
    }
    // fc00::/7 unique-local, fe80::/10 link-local.
    return /^f[cd]/.test(h) || /^fe[89ab]/.test(h);
  }
  const name = h.endsWith(".") ? h.slice(0, -1) : h;
  if (name === "localhost" || name.endsWith(".localhost")) return true;
  const folded = foldInetAton(name);
  if (folded !== null) return isDeniedV4(folded);
  // A numeric-shaped token that folds to no valid address is not a DNS name
  // either — reject rather than guess.
  if (name.split(".").every((label) => INET_PART.test(label))) return true;
  // A single-label name resolves through search domains or mDNS — never
  // provably external.
  return !name.includes(".");
}

// A probe transcript proves an L2/L3 boundary only when it records both
// failed-inside assertions AND a networked outer context (a fully-offline
// outer context would deny egress on its own) — the capture shape of
// templates/isolation-probe.md; keep the two in sync. The transcript's own
// surface/level/substrate identity must match the binding entry it is cited
// from: a genuine transcript reused under a different surface, level, or
// substrate proves a DIFFERENT boundary, not this one. Returns null when
// verified, else the reason the entry is unproven.
function verifyProbeTranscript(ref, probeRoot, surfaceId, level, substrate) {
  const path = probeRoot !== null && !isAbsolute(ref) ? join(probeRoot, ref) : ref;
  let transcript;
  try {
    transcript = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    return `transcript ${path} is not readable JSON (${error.message})`;
  }
  if (!isPlainObject(transcript)) {
    return `transcript ${path} is not a capture-shape object`;
  }
  if (transcript.surface !== surfaceId) {
    return `transcript ${path} records surface ${JSON.stringify(transcript.surface)}, not this binding entry's surface ${JSON.stringify(surfaceId)}`;
  }
  if (transcript.level !== level) {
    return `transcript ${path} records level ${JSON.stringify(transcript.level)}, not this binding entry's level ${JSON.stringify(level)}`;
  }
  if (transcript.substrate !== substrate) {
    return `transcript ${path} records substrate ${JSON.stringify(transcript.substrate)}, not this binding entry's substrate ${JSON.stringify(substrate)}`;
  }
  // The claimed level must be reachable by the substrate CLASS that ran the
  // probe: L3 is the ladder's kernel-separated floor, which container and
  // os-sandbox boundaries never provide — a genuine L2 transcript relabeled
  // L3 must not unlock C5.
  if (!SUBSTRATE_CLASSES.has(transcript.substrate_class)) {
    return `transcript ${path} records substrate_class ${JSON.stringify(transcript.substrate_class)} — required, one of ${[...SUBSTRATE_CLASSES].join(" | ")}`;
  }
  if (level === "L3" && transcript.substrate_class !== "vm-microvm") {
    return `transcript ${path} records substrate_class ${JSON.stringify(transcript.substrate_class)} for an L3 entry — L3 requires kernel separation, which only substrate_class "vm-microvm" provides`;
  }
  if (transcript.assertions?.egress_denied?.outcome !== "denied") {
    return `transcript ${path} does not record the egress-denial assertion with outcome "denied"`;
  }
  if (transcript.assertions?.credentials_absent?.outcome !== "absent-or-denied") {
    return `transcript ${path} does not record the credential-absence assertion with outcome "absent-or-denied"`;
  }
  // The probe contract is expected-FAILURE: both checks assert a NON-zero
  // exit inside the boundary, so a recorded exit_code of "0" contradicts the
  // outcome it sits next to — the transcript is internally inconsistent and
  // proves nothing.
  const nonzeroExit = (value) => typeof value === "string" && /^[1-9][0-9]*$/.test(value);
  if (!nonzeroExit(transcript.assertions.egress_denied.exit_code)) {
    return `transcript ${path} records assertions.egress_denied.exit_code ${JSON.stringify(transcript.assertions.egress_denied.exit_code)} — a proven egress-denial requires a non-zero integer exit code string`;
  }
  if (!nonzeroExit(transcript.assertions.credentials_absent.exit_code)) {
    return `transcript ${path} records assertions.credentials_absent.exit_code ${JSON.stringify(transcript.assertions.credentials_absent.exit_code)} — a proven credential-absence requires a non-zero integer exit code string`;
  }
  // An assertion without its recorded target proves nothing about the
  // boundary: a failing run against no named host/path could be any failing
  // command, not the probe.
  const egressHost = transcript.assertions.egress_denied.host;
  if (typeof egressHost !== "string" || egressHost.length === 0 || /\s/.test(egressHost)) {
    return `transcript ${path} records assertions.egress_denied.host ${JSON.stringify(egressHost)} — a proven egress-denial requires the probed external host (non-empty, no whitespace)`;
  }
  if (isNonExternalEgressHost(egressHost)) {
    return `transcript ${path} records assertions.egress_denied.host ${JSON.stringify(egressHost)} — a loopback/private/link-local or otherwise non-external target (after normalizing encoded forms) cannot prove EXTERNAL egress denial; probe a genuine external host (multi-label DNS name or public IP)`;
  }
  if (!isNonEmptyString(transcript.assertions.credentials_absent.path)) {
    return `transcript ${path} records assertions.credentials_absent.path ${JSON.stringify(transcript.assertions.credentials_absent.path)} — a proven credential-absence requires the probed host-credential path`;
  }
  // The path value is a comma-separated list of probed locations; every
  // entry must be recognizably a host-credential location (case-insensitive,
  // path-separator-agnostic).
  for (const entry of transcript.assertions.credentials_absent.path.split(",")) {
    const normalized = entry.trim().toLowerCase().replaceAll("\\", "/");
    if (!CREDENTIAL_LOCATION_TOKENS.some((token) => normalized.includes(token))) {
      return `transcript ${path} records assertions.credentials_absent.path entry ${JSON.stringify(entry.trim())} — not a recognized host-credential location; probe genuine host credential locations (${CREDENTIAL_LOCATION_TOKENS.join(", ")})`;
    }
  }
  if (transcript.outer_context_networked !== true) {
    return `transcript ${path} does not record outer_context_networked true — an offline outer context would deny egress on its own`;
  }
  return null;
}

function checkSemantics(binding, probeRoot) {
  const posture = binding.dispatch_posture ?? "autonomous-enabled";
  const autonomous = posture === "autonomous-enabled";

  // Merge caps: vendor-hosted caps every class at human-gated; otherwise the
  // matrix caps apply (only C2 is auto-merge eligible).
  if (isPlainObject(binding.merge_policy)) {
    for (const workClass of WORK_CLASSES) {
      if (binding.merge_policy[workClass] !== "auto") continue;
      if (binding.executor_class === "vendor-hosted") {
        findings.push(
          `merge_policy.${workClass}: "auto" with executor_class vendor-hosted — a vendor-hosted executor caps every class at human-gated merge`,
        );
      } else if (!AUTO_MERGE_ELIGIBLE.has(workClass)) {
        findings.push(
          `merge_policy.${workClass}: "auto" exceeds the matrix cap — ${workClass === "C4" || workClass === "C5" ? "C4/C5 merge is human always" : "the matrix merges this class human; only the C2 cell is auto-merge eligible"}`,
        );
      }
    }
  }

  const surfaces = isPlainObject(binding.isolation_bindings) ? Object.entries(binding.isolation_bindings) : [];

  if (autonomous) {
    // Every bound surface must be attestable: without non-empty
    // runtime_markers the dispatch seam could never attest the actual
    // surface, and every dispatch would fail closed as unattestable.
    const markerEntries = [];
    for (const [surfaceId, levels] of surfaces) {
      if (!isPlainObject(levels)) continue;
      for (const [level, entry] of Object.entries(levels)) {
        if (!isPlainObject(entry)) continue;
        const markers = entry.runtime_markers;
        if (!isPlainObject(markers) || Object.keys(markers).length === 0) {
          findings.push(
            `isolation_bindings.${surfaceId}.${level}: runtime_markers missing or empty under dispatch_posture autonomous-enabled — the dispatch seam could never attest this surface; every dispatch would fail closed as unattestable`,
          );
        } else {
          markerEntries.push({ surfaceId, level, markers });
        }
      }
    }
    // The dispatch seam requires EXACTLY ONE matching entry at runtime,
    // failing closed on zero or multiple matches; rejecting jointly
    // satisfiable marker sets here keeps that rule from turning validly
    // bound fleets into ambiguity outages. The requirement applies to level
    // entries WITHIN a surface too: an L2 runner subset sharing a surface id
    // with an L3 subset, without conflicting markers, could receive the work
    // the surface's max level admits.
    const reportedPairs = new Set();
    for (let i = 0; i < markerEntries.length; i += 1) {
      for (let j = i + 1; j < markerEntries.length; j += 1) {
        const a = markerEntries[i];
        const b = markerEntries[j];
        const sameSurface = a.surfaceId === b.surfaceId;
        const pairKey = sameSurface
          ? JSON.stringify([a.surfaceId, a.level, b.level])
          : JSON.stringify([a.surfaceId, b.surfaceId]);
        if (reportedPairs.has(pairKey)) continue;
        if (jointlySatisfiable(a.markers, b.markers)) {
          reportedPairs.add(pairKey);
          findings.push(
            sameSurface
              ? `isolation_bindings.${a.surfaceId}: runtime_markers of level entries ${a.level} and ${b.level} are jointly satisfiable — runtime attestation could not pin which level boundary the workload runs in; give each level's runner subset conflicting markers on a shared key, or split the levels into distinct surfaces`
              : `isolation_bindings: runtime_markers of surfaces ${JSON.stringify(a.surfaceId)} and ${JSON.stringify(b.surfaceId)} are jointly satisfiable — a runtime context carrying the union matches both; the sets must conflict on at least one shared key`,
          );
        }
      }
    }
  }

  // Per-surface, class-aware isolation verdicts: a surface is eligible for a
  // class only when its bound level meets that class's min-isolation cell —
  // so an L2-only surface is never selected for a C5 item, and an unbound
  // surface is blocked even when a sibling surface is bound. Aggregating to
  // the max PROVEN level is sound only because same-surface level entries
  // must carry mutually conflicting runtime_markers (checked above):
  // dispatch attests the exact level entry, never just the surface id.
  const verdicts = [];
  let anyProvenL2 = false;
  let anyUnprovenL2Plus = false;
  for (const [surfaceId, levels] of surfaces) {
    if (!isPlainObject(levels)) continue;
    // L2/L3 count only when their probe transcript verifies; L0/L1 are
    // exempt — they can never satisfy an eligibility floor, so unverified
    // evidence there enables nothing.
    let provenMax = -1;
    const unproven = [];
    for (const [level, entry] of Object.entries(levels)) {
      if (!LEVEL_TOKEN.test(level) || !isPlainObject(entry)) continue;
      const levelNo = levelNumber(level);
      if (levelNo < 2) {
        provenMax = Math.max(provenMax, levelNo);
        continue;
      }
      const reason = isNonEmptyString(entry.probe_evidence)
        ? verifyProbeTranscript(entry.probe_evidence, probeRoot, surfaceId, level, entry.substrate)
        : "probe_evidence missing";
      if (reason === null) {
        provenMax = Math.max(provenMax, levelNo);
        continue;
      }
      anyUnprovenL2Plus = true;
      unproven.push(`${level} unproven (${reason})`);
      // A missing ref already produced its structural finding; only a
      // present-but-unverifiable ref needs one here.
      if (autonomous && isNonEmptyString(entry.probe_evidence)) {
        findings.push(
          `isolation_bindings.${surfaceId}.${level}: probe evidence unverifiable — ${reason}; the level is UNPROVEN and does not count toward isolation eligibility (fail-closed) — run the isolation probe inside the boundary and reference its captured transcript`,
        );
      }
    }
    if (provenMax >= 2) anyProvenL2 = true;
    const perClass = WORK_CLASSES.map((workClass) => {
      const floor = MIN_ISOLATION[workClass];
      return provenMax >= floor
        ? `${workClass} eligible`
        : `${workClass} blocked (requires L${floor}${provenMax >= 0 ? `, proven L${provenMax}` : ", no proven level"})`;
    });
    verdicts.push(
      `surface ${JSON.stringify(surfaceId)}: ${perClass.join(", ")}${unproven.length > 0 ? `; ${unproven.join("; ")}` : ""}`,
    );
  }

  // When an L2+ entry is bound but unproven, its own finding already names
  // the failure and the compliant path — a second no-L2 finding would be
  // redundant noise for the same root cause.
  if (autonomous && !anyProvenL2 && !anyUnprovenL2Plus) {
    findings.push(
      "isolation_bindings: no bound surface reaches L2 under dispatch_posture autonomous-enabled — autonomous dispatch is blocked fail-closed; compliant paths: bind an L2-capable substrate (whole-process OS-sandbox wrap, default-deny-egress container) on an execution surface, or declare dispatch_posture human-gated-only",
    );
  }
  if (!autonomous) {
    verdicts.push(
      "autonomous dispatch blocked: dispatch_posture human-gated-only is the DECLARED posture — every item enqueues human-gated (deliberate posture, not a defect)",
    );
  }

  // Promotion entries exist for promotable cells only.
  if (isPlainObject(binding.promotion_state)) {
    for (const cell of Object.keys(binding.promotion_state)) {
      if (!PROMOTABLE_CELLS.has(cell)) {
        findings.push(
          `promotion_state.${cell}: not a promotable cell — promotable cells are ${[...PROMOTABLE_CELLS].join(", ")}; C4/C5 merge never promotes`,
        );
      }
    }
  }

  // Promotion-gated knobs at their EARNED value require the ratified
  // promotion_state entry: promotion is a human-ratified knob flip recorded
  // on the governance surface, and an earned value without its ratification
  // record bypasses that discipline.
  const ratifiedPromoted = (cell) =>
    isPlainObject(binding.promotion_state) &&
    isPlainObject(binding.promotion_state[cell]) &&
    binding.promotion_state[cell].state === "promoted";
  if (
    isPlainObject(binding.merge_policy) &&
    binding.merge_policy.C2 === "auto" &&
    binding.executor_class !== "vendor-hosted" &&
    !ratifiedPromoted("C2-auto-merge")
  ) {
    findings.push(
      'merge_policy.C2: "auto" without a ratified promotion_state.C2-auto-merge entry (state "promoted") — promotion is a human-ratified knob flip recorded on the governance surface; an earned value without its ratification record bypasses the promotion discipline',
    );
  }
  // For the promotable ai-review C3 cell, blocking is the EARNED flip
  // (advisory -> blocking per the security-review leaf) — a deliberate
  // carve-out from the floors-may-tighten rule for this one cell: stronger
  // than the advisory floor here is a promotion, not mere tightening.
  const aiReview = isPlainObject(binding.verification_blocking)
    ? binding.verification_blocking["ai-review"]
    : null;
  if (isPlainObject(aiReview) && aiReview.C3 === "blocking" && !ratifiedPromoted("C3-ai-review-blocking")) {
    findings.push(
      'verification_blocking.ai-review.C3: "blocking" without a ratified promotion_state.C3-ai-review-blocking entry (state "promoted") — advisory -> blocking is the earned promotion flip for this cell; an earned value without its ratification record bypasses the promotion discipline',
    );
  }

  // Verification floors: weakening below the security-review leaf's shipped
  // per-class default is simply invalid — no override escape exists here.
  if (isPlainObject(binding.verification_blocking)) {
    for (const layer of LAYERS) {
      const perClass = binding.verification_blocking[layer];
      if (!isPlainObject(perClass)) continue;
      for (const workClass of WORK_CLASSES) {
        const knob = perClass[workClass];
        if (!VERIFICATION_TOKENS.includes(knob)) continue;
        const floor = VERIFICATION_FLOORS[layer][workClass];
        if (VERIFICATION_STRENGTH[knob] < VERIFICATION_STRENGTH[floor]) {
          findings.push(
            `verification_blocking.${layer}.${workClass}: ${JSON.stringify(knob)} weakens the shipped floor ${JSON.stringify(floor)} — floors may be tightened, never weakened (override_justification applies to admission rules only)`,
          );
        }
      }
    }
  }

  if (isPlainObject(binding.admission) && Array.isArray(binding.admission.rules)) {
    checkAdmissionSemantics(binding.admission.rules);
  }

  return verdicts;
}

function checkAdmissionSemantics(rules) {
  const validRules = rules.filter(
    (rule) =>
      isPlainObject(rule) &&
      [...SURFACE_CLASSES, "*"].includes(rule.signal_class) &&
      [...PROVENANCES, "*"].includes(rule.provenance) &&
      [...WORK_CLASSES, "*"].includes(rule.work_class) &&
      DISPOSITIONS.includes(rule.disposition),
  );

  // A rule more permissive than the shipped default for ANY cell it matches
  // requires a recorded override_justification; tightening needs none.
  validRules.forEach((rule) => {
    const index = rules.indexOf(rule);
    const covered = rule.work_class === "*" ? WORK_CLASSES : [rule.work_class];
    const weakened = covered.filter(
      (workClass) => PERMISSIVENESS[rule.disposition] > PERMISSIVENESS[ADMISSION_DEFAULTS[workClass]],
    );
    if (weakened.length > 0 && !isNonEmptyString(rule.override_justification)) {
      findings.push(
        `admission.rules[${index}]: disposition ${JSON.stringify(rule.disposition)} is more permissive than the shipped default for ${weakened.join(", ")} — invalid without override_justification`,
      );
    }
  });

  // Two rules of equal specificity that can both match some concrete triple
  // with different dispositions make the binding invalid — most-specific-wins
  // has no winner there, and an ambiguous admission decision is fail-closed
  // at the binding, not at the seam.
  const specificity = (rule) =>
    [rule.signal_class, rule.provenance, rule.work_class].filter((axis) => axis !== "*").length;
  const axesCompatible = (a, b) =>
    [
      [a.signal_class, b.signal_class],
      [a.provenance, b.provenance],
      [a.work_class, b.work_class],
    ].every(([x, y]) => x === "*" || y === "*" || x === y);
  for (let i = 0; i < validRules.length; i += 1) {
    for (let j = i + 1; j < validRules.length; j += 1) {
      const a = validRules[i];
      const b = validRules[j];
      if (
        specificity(a) === specificity(b) &&
        a.disposition !== b.disposition &&
        axesCompatible(a, b)
      ) {
        findings.push(
          `admission.rules[${rules.indexOf(a)}] and admission.rules[${rules.indexOf(b)}]: equal specificity (${specificity(a)} bound axes) with different dispositions and a jointly matchable triple — no most-specific winner exists; invalid binding, fail-closed`,
        );
      }
    }
  }
}

// --- Evaluation mode: effective promotion state from an evidence source ---

function resolveEffectivePromotion(binding, evidencePath) {
  const lines = [];
  let events = null;
  let evidenceUnavailable = false;
  try {
    const parsed = JSON.parse(readFileSync(evidencePath, "utf8"));
    if (!Array.isArray(parsed)) throw new Error("evidence document must be a JSON array of events");
    events = parsed;
  } catch (error) {
    // Unavailable evidence telemetry fail-closes to the unpromoted default —
    // a report, never a crash.
    evidenceUnavailable = true;
    lines.push(
      `evidence source ${evidencePath} unavailable (${error.message}) — fail-closed: every cell resolves to effective state unpromoted`,
    );
  }

  const promotionState = isPlainObject(binding.promotion_state) ? binding.promotion_state : {};
  for (const [cell, entry] of Object.entries(promotionState)) {
    if (!isPlainObject(entry)) continue;
    const bound = entry.state;
    if (evidenceUnavailable) {
      lines.push(`${cell}: bound ${bound} -> effective unpromoted (evidence unavailable, fail-closed)`);
      continue;
    }
    const contrary = events.filter(
      (event) => isPlainObject(event) && event.cell === cell && CONTRARY_EVIDENCE_EVENTS.has(event.event),
    );
    // Contrary evidence is scoped to the promotion epoch: an event predating
    // the cell's ratified_at belongs to a previous epoch and was already
    // consumed by the re-earn that produced this ratification. An event
    // whose `at` is not strict ISO (or missing) cannot be assigned to an
    // epoch and is treated as contrary (fail-closed) — dropping it silently
    // would let malformed telemetry mask a real demotion signal.
    const ratifiedAt = parseIsoStrict(entry.ratified_at);
    const inEpoch = [];
    const preEpoch = [];
    for (const event of contrary) {
      const at = parseIsoStrict(event.at);
      if (Number.isNaN(at)) {
        inEpoch.push(`${event.event} with non-ISO or unparsable at ${JSON.stringify(event.at)} — cannot be assigned to an epoch, treated as contrary (fail-closed)`);
      } else if (Number.isNaN(ratifiedAt) || at >= ratifiedAt) {
        inEpoch.push(`${event.event} at ${event.at}`);
      } else {
        preEpoch.push(`${event.event} at ${event.at}`);
      }
    }
    if (bound === "promoted" && inEpoch.length > 0) {
      lines.push(
        `${cell}: bound promoted -> effective unpromoted — ceiling lowered by contrary evidence (${inEpoch.join("; ")}) WITHOUT modifying the binding; demotion files an escalation item on route ${JSON.stringify(binding.escalation_routes?.demotion)} requesting the human-ratified binding update`,
      );
    } else {
      let line = `${cell}: bound ${bound} -> effective ${bound}`;
      if (preEpoch.length > 0) {
        line += ` (${preEpoch.length} pre-epoch contrary event(s) ignored: ${preEpoch.join("; ")} — predate ratified_at ${entry.ratified_at} and were consumed by the re-earn)`;
      }
      lines.push(line);
    }
  }
  if (Object.keys(promotionState).length === 0) {
    lines.push("no promotion_state entries — every promotable cell is at its unpromoted default");
  }
  return lines;
}

// --- Entry point ---

const args = process.argv.slice(2);
let bindingPath = null;
let evidencePath = null;
let probeRoot = null;
for (let i = 0; i < args.length; i += 1) {
  if (args[i] === "--evidence") {
    evidencePath = args[i + 1];
    i += 1;
  } else if (args[i] === "--probe-evidence-root") {
    probeRoot = args[i + 1];
    i += 1;
  } else if (bindingPath === null) {
    bindingPath = args[i];
  } else {
    bindingPath = undefined;
    break;
  }
}
if (
  !isNonEmptyString(bindingPath) ||
  (evidencePath !== null && !isNonEmptyString(evidencePath)) ||
  (probeRoot !== null && !isNonEmptyString(probeRoot))
) {
  console.error("usage: check-security-binding.mjs <binding.json> [--evidence <evidence.json>] [--probe-evidence-root <dir>]");
  process.exit(2);
}

let raw;
try {
  raw = readFileSync(bindingPath, "utf8");
} catch (error) {
  // A missing or unreadable binding file is an environment error (exit 2),
  // never a conformance verdict on the document.
  console.error(`cannot read binding ${bindingPath}: ${error.message}`);
  process.exit(2);
}

let binding = null;
try {
  binding = JSON.parse(raw);
} catch {
  findings.push("binding: not valid JSON — an invalid security binding fail-closes autonomous dispatch");
}

let verdicts = [];
if (binding !== null) {
  validateStructure(binding);
  if (isPlainObject(binding)) verdicts = checkSemantics(binding, probeRoot);
}

if (findings.length > 0) {
  console.error(`Security-binding validation FAILED: ${bindingPath}`);
  for (const finding of findings) console.error(`- ${finding}`);
  process.exit(1);
}

console.log(`Security binding OK: ${bindingPath}`);
for (const verdict of verdicts) console.log(`- ${verdict}`);
if (evidencePath !== null) {
  console.log("Effective promotion state (evaluation mode):");
  for (const line of resolveEffectivePromotion(binding, evidencePath)) console.log(`- ${line}`);
}
