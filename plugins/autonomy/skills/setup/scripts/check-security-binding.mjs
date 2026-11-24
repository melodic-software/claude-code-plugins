#!/usr/bin/env node

import { readFileSync, realpathSync } from "node:fs";
import { isAbsolute, posix, relative, resolve, sep } from "node:path";
import process from "node:process";

const WORK_CLASSES = ["C1", "C2", "C3", "C4", "C5"];
const LEVEL_TOKEN = /^L[0-3]$/;
const ROUTINE_IDENTITY = /^[a-z][a-z0-9-]*(\/[a-z][a-z0-9-]*)?$/;
const NON_DURABLE_PREFIX_SCHEMES = new Set(["data", "javascript", "blob", "about", "http", "mailto", "tel", "vbscript"]);
const SURFACE_CLASSES = ["tracker-vcs-event", "temporal", "agent-internal", "channel-feed"];
const PROVENANCES = ["human", "agent", "system"];
const RULE_SIGNAL_CLASSES = [...SURFACE_CLASSES, "*"];
const RULE_PROVENANCES = [...PROVENANCES, "*"];
const RULE_WORK_CLASSES = [...WORK_CLASSES, "*"];
const DISPOSITIONS = ["autonomous-eligible", "human-gated", "audited-rejection"];
const EVENT_CLASSES = [
  "gate-failure",
  "verification-divergence",
  "admission-rejection",
  "demotion",
  "structural-plan-approval",
  "untrusted-provenance",
];
const RUNNER_EVENT_CLASSES = ["runner-needs-human", "runner-cap-exceeded"];
const ESCALATION_EVENT_CLASSES = [...EVENT_CLASSES, ...RUNNER_EVENT_CLASSES];
const SEVERITY_TOKENS = ["notice", "attention", "urgent"];
const LAYERS = ["deterministic", "ai-review"];
const VERIFICATION_TOKENS = ["not-required", "advisory", "blocking"];
const MERGE_TOKENS = ["auto", "human"];
const CONTRARY_EVIDENCE_EVENTS = new Set(["gate-failure", "reverted-merge", "verification-divergence"]);
const REEARN_EVENT = "re-earned";
const SUBSTRATE_CLASSES = new Set(["container", "os-sandbox", "vm-microvm", "hosted-ephemeral-executor"]);
const L3_SUBSTRATE_CLASSES = new Set(["vm-microvm", "hosted-ephemeral-executor"]);
const EGRESS_TRANSPORT_OUTCOMES = new Set([
  "dns-unresolved",
  "connect-failed",
  "tls-failed",
  "peer-substituted",
]);
const ADDRESS_FAMILIES = new Set(["ipv4", "ipv6"]);
const WORKSPACE_CANARY_MINIMUM = 3;
const HOST_INTEROP_TOKENS = ["none", "wsl2"];
const INTEROP_DENIAL_EXIT_CODE = /^(?:[1-9]|[1-9][0-9]|1[01][0-9]|12[0-3]|126)$/;
// RFC 2606/6761/6762/7686 special-use and reserved TLDs.
const SPECIAL_USE_TLDS = [
  ".invalid",
  ".test",
  ".example",
  ".localhost",
  ".local",
  ".internal",
  ".home.arpa",
  ".onion",
];
const CREDENTIAL_ENV_VARS = new Set(["github_token", "gh_token"]);
const EPHEMERAL_SEGMENTS = new Set(["tmp", "temp", "shm"]);
const isEnvToken = (segment) => /^\$[a-z_]+$/.test(segment) || /^%[a-z_]+%$/.test(segment);
const envTokenName = (segment) => segment.replace(/^[$%]/, "").replace(/%$/, "");
const isHomeEnvToken = (segment) => isEnvToken(segment) && ["home", "userprofile"].includes(envTokenName(segment));
const lowerSlashed = (path) => path.toLowerCase().replaceAll("\\", "/");
const hasRoutePrefix = (pathname, prefix) => pathname === prefix || pathname.startsWith(prefix + "/");

function isMetadataEndpoint(normalized) {
  let url;
  try {
    url = new URL(normalized);
  } catch {
    return false;
  }
  if (url.protocol !== "http:" || url.port !== "") return false;
  if (url.hostname === "169.254.169.254") {
    return (
      hasRoutePrefix(url.pathname, "/metadata") ||
      hasRoutePrefix(url.pathname, "/latest") ||
      hasRoutePrefix(url.pathname, "/computemetadata")
    );
  }
  return url.hostname === "metadata.google.internal" && hasRoutePrefix(url.pathname, "/computemetadata");
}

function normalizeHostPath(p) {
  const slashed = p.replaceAll("\\", "/");
  if (slashed.startsWith("//")) return null;
  const drive = /^([a-zA-Z]:)\//.exec(slashed)?.[1].toLowerCase() ?? null;
  if (drive === null && !slashed.startsWith("/")) return null;
  const body = drive === null ? slashed.slice(1) : slashed.slice(drive.length + 1).toLowerCase();
  const out = [];
  for (const segment of body.split("/")) {
    if (segment === "" || segment === ".") continue;
    if (segment === "..") {
      if (out.length === 0) return null;
      out.pop();
      continue;
    }
    out.push(segment);
  }
  return `${drive ?? ""}/${out.join("/")}`;
}

function pathUnderConfiguredRoot(candidate, roots) {
  const normCandidate = normalizeHostPath(candidate);
  if (normCandidate === null) return false;
  return roots.some((root) => {
    const normRoot = normalizeHostPath(root);
    if (normRoot === null || normRoot === "/" || /^[a-z]:\/$/.test(normRoot)) return false;
    return normCandidate === normRoot || normCandidate.startsWith(`${normRoot}/`);
  });
}

function credentialEntryProblem(entry, expanded, credentialRoots) {
  const normalized = lowerSlashed(entry);
  if (normalized.includes("://")) {
    if (!isMetadataEndpoint(normalized)) {
      return "not a known cloud metadata endpoint credential route (169.254.169.254 or metadata.google.internal over plain HTTP on the default port, on a known credential route)";
    }
    return credentialExpansionProblem(entry, expanded);
  }
  const segments = normalized.split("/").filter((segment) => segment.length > 0);
  if (segments.length === 1 && isEnvToken(segments[0])) {
    if (!CREDENTIAL_ENV_VARS.has(envTokenName(segments[0]))) {
      return `not a well-known credential env token (${[...CREDENTIAL_ENV_VARS].map((name) => `$${name.toUpperCase()}`).join(", ")}); an org-specific token is not recognized by name — probe the host filesystem path where the injected secret is stored (e.g. /run/secrets/my-org-token) and configure its parent in --credential-roots`;
    }
    return credentialExpansionProblem(entry, expanded);
  }
  const coherence = credentialExpansionProblem(entry, expanded);
  if (coherence !== null) return coherence;
  if (credentialRoots === null) {
    return "no --credential-roots configured — a static checker cannot know whether an arbitrary host path names a real credential store, so filesystem credential evidence is untrusted by default; pass the org's trusted credential root(s) via --credential-roots";
  }
  if (!pathUnderConfiguredRoot(expanded, credentialRoots)) {
    return `host-side expansion ${JSON.stringify(expanded)} does not resolve under any configured --credential-roots (${credentialRoots.join(", ")}) — a failing read of a path outside every trusted credential root proves nothing about the host credential store`;
  }
  return null;
}

function credentialExpansionProblem(entry, expanded) {
  const normalizedEntry = lowerSlashed(entry);
  const normalizedExpanded = lowerSlashed(expanded);
  const segments = normalizedEntry.split("/").filter((segment) => segment.length > 0);
  const homeAnchored =
    !normalizedEntry.includes("://") && segments.length > 1 && isHomeEnvToken(segments[0]);
  if (!homeAnchored) {
    if (segments.some((segment) => segment === "." || segment === "..")) {
      return "a concrete credential path must not contain dot-traversal segments — use the canonical path";
    }
    return normalizedExpanded === normalizedEntry
      ? null
      : "a concrete entry needs no host-side expansion, so host_expanded must repeat the entry verbatim";
  }
  if (normalizedExpanded.startsWith("//")) {
    return "the host-side expansion is a UNC form, which invents its server rather than naming the host home";
  }
  if (!(normalizedExpanded.startsWith("/") || /^[a-z]:\//.test(normalizedExpanded))) {
    return "the host-side expansion must be rooted (POSIX-absolute or drive-letter-absolute)";
  }
  const expandedSegments = normalizedExpanded.split("/").filter((segment) => segment.length > 0);
  if (expandedSegments.some((segment) => segment === "." || segment === "..")) {
    return "the host-side expansion contains a dot segment (\".\", \"..\"), which resolves elsewhere than the recorded path claims";
  }
  if (expandedSegments.some((segment) => EPHEMERAL_SEGMENTS.has(segment))) {
    return "the host-side expansion sits under an ephemeral base (tmp, temp, shm) — planted evidence, not the host credential store";
  }
  const tail = normalizedEntry.slice(segments[0].length);
  if (!normalizedExpanded.endsWith(tail)) {
    return `the host-side expansion is not tail-consistent with the entry — everything after the home token (${JSON.stringify(tail)}) must be the expansion's trailing suffix`;
  }
  return null;
}

const MIN_ISOLATION = { C1: 2, C2: 2, C3: 2, C4: 2, C5: 3 };
const AUTO_MERGE_PROMOTION_CELL = { C2: "C2-auto-merge", C3: "C3-auto-merge", C4: "C3-auto-merge" };

const VERIFICATION_FLOORS = {
  deterministic: { C1: "not-required", C2: "blocking", C3: "blocking", C4: "blocking", C5: "blocking" },
  "ai-review": { C1: "not-required", C2: "not-required", C3: "advisory", C4: "blocking", C5: "blocking" },
};
const VERIFICATION_STRENGTH = { "not-required": 0, advisory: 1, blocking: 2 };

const TOPOLOGY_ROLES = ["generator", "checker", "cross_vendor_checker", "ranker"];
const CHECKER_TYPED_ROLES = new Set(["checker", "cross_vendor_checker"]);
const RELATIONAL_CONSTRAINTS = ["distinct_model_from", "distinct_vendor_from"];
const TOPOLOGY_FLOORS = {
  C1: { min_checkers: 1, min_model_checkers: 0, cross_vendor_required: false },
  C2: { min_checkers: 1, min_model_checkers: 0, cross_vendor_required: false },
  C3: { min_checkers: 2, min_model_checkers: 1, cross_vendor_required: false },
  C4: { min_checkers: 3, min_model_checkers: 2, cross_vendor_required: true },
  C5: { min_checkers: 3, min_model_checkers: 2, cross_vendor_required: true },
};

const PROMOTABLE_CELLS = new Set(["C2-auto-merge", "C3-auto-merge", "C3-ai-review-blocking"]);

const PROMOTION_DEPENDENCIES = { "C3-auto-merge": ["C2-auto-merge", "C3-ai-review-blocking"] };

const ADMISSION_DEFAULTS = {
  C1: "autonomous-eligible",
  C2: "autonomous-eligible",
  C3: "autonomous-eligible",
  C4: "autonomous-eligible",
  C5: "human-gated",
};
const ADMISSION_GATED_SURFACES = { "channel-feed": "human-gated" };
const PERMISSIVENESS = { "audited-rejection": 0, "human-gated": 1, "autonomous-eligible": 2 };

const findings = [];

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.length > 0;
}

function isArrayOfNonEmptyStrings(value) {
  return Array.isArray(value) && value.every(isNonEmptyString);
}

const bareHost = (host) => host.toLowerCase().replace(/\.$/, "");

function splitRecordedList(raw) {
  return typeof raw === "string" ? raw.split(",").map((entry) => entry.trim()) : [];
}

const ISO_DATE_TIME = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/;
function parseIsoStrict(value) {
  const match = typeof value === "string" ? ISO_DATE_TIME.exec(value) : null;
  if (match === null) return Number.NaN;
  const [, year, month, day, hour, minute, second, fraction, offset] = match;
  const ms = Number((fraction ?? "").padEnd(3, "0"));
  const utc = new Date(Date.UTC(+year, +month - 1, +day, +hour, +minute, +second, ms));
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

function checkPerClassEnums(perClass, tokens, where) {
  for (const workClass of WORK_CLASSES) {
    if (Object.hasOwn(perClass, workClass)) {
      checkEnum(perClass[workClass], tokens, `${where}.${workClass}`);
    } else {
      findings.push(`${where}.${workClass}: required key missing`);
    }
  }
}


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
      "verification_topology",
      "promotion_state",
      "escalation_routes",
      "escalation_severity",
      "escalation_severity_routes",
      "escalation_ack",
      "admission",
    ],
    "binding",
  );
  for (const key of [
    "schema_version",
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
          checkAllowedKeys(
            entry,
            ["substrate", "substrate_class", "host_interop", "component_reachable_hosts", "base_egress_allowlist", "probe_evidence", "runtime_markers"],
            where,
          );
          if (Object.hasOwn(entry, "host_interop")) {
            checkEnum(entry.host_interop, HOST_INTEROP_TOKENS, `${where}.host_interop`);
          }
          if (Object.hasOwn(entry, "base_egress_allowlist") && !isArrayOfNonEmptyStrings(entry.base_egress_allowlist)) {
            findings.push(`${where}.base_egress_allowlist: must be an array of non-empty strings (the empty array is allowed); it records the base allowlist for the reviewing human and is never probe coverage`);
          }
          if (Object.hasOwn(entry, "component_reachable_hosts") && !isArrayOfNonEmptyStrings(entry.component_reachable_hosts)) {
            findings.push(`${where}.component_reachable_hosts: must be an array of non-empty host strings — the empty array is the explicit claim that this surface installs nothing carrying policy rules of its own`);
          }
          if (!isNonEmptyString(entry.substrate)) {
            findings.push(`${where}.substrate: missing or empty — the bound substrate instance id is required`);
          }
          if (!SUBSTRATE_CLASSES.has(entry.substrate_class)) {
            findings.push(
              `${where}.substrate_class: ${JSON.stringify(entry.substrate_class)} — the human-ratified substrate-class assertion is required on every level binding, one of ${[...SUBSTRATE_CLASSES].join(" | ")}`,
            );
          } else if (level === "L3" && !L3_SUBSTRATE_CLASSES.has(entry.substrate_class)) {
            findings.push(
              `${where}.substrate_class: ${JSON.stringify(entry.substrate_class)} ratified for an L3 entry — L3 requires kernel separation, which only the kernel-separated substrate classes (${[...L3_SUBSTRATE_CLASSES].map((token) => JSON.stringify(token)).join(", ")}) provide; ratify a kernel-separated class, or bind this substrate at the level its class can reach`,
            );
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
      checkPerClassEnums(binding.merge_policy, MERGE_TOKENS, "merge_policy");
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
        checkPerClassEnums(perClass, VERIFICATION_TOKENS, where);
      }
    }
  }

  if (Object.hasOwn(binding, "verification_topology")) {
    if (!isPlainObject(binding.verification_topology)) {
      findings.push("verification_topology: must be an object keyed by work class");
    } else {
      checkAllowedKeys(binding.verification_topology, WORK_CLASSES, "verification_topology");
      for (const workClass of WORK_CLASSES) {
        if (!Object.hasOwn(binding.verification_topology, workClass)) continue;
        validateClassTopologyStructure(binding.verification_topology[workClass], `verification_topology.${workClass}`);
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
      checkAllowedKeys(binding.escalation_routes, ESCALATION_EVENT_CLASSES, "escalation_routes");
      for (const eventClass of EVENT_CLASSES) {
        if (!isNonEmptyString(binding.escalation_routes[eventClass])) {
          findings.push(`escalation_routes.${eventClass}: missing or empty — every event class has an org-bound route`);
        }
      }
      for (const eventClass of RUNNER_EVENT_CLASSES) {
        if (Object.hasOwn(binding.escalation_routes, eventClass) && !isNonEmptyString(binding.escalation_routes[eventClass])) {
          findings.push(`escalation_routes.${eventClass}: present but empty — a bound runner event-class route carries an org-bound route like any other`);
        }
      }
    }
  }

  if (Object.hasOwn(binding, "escalation_severity")) {
    if (!isPlainObject(binding.escalation_severity)) {
      findings.push("escalation_severity: must be an object mapping escalation event class to severity token");
    } else {
      const eventRoutes = isPlainObject(binding.escalation_routes) ? binding.escalation_routes : {};
      for (const [eventClass, severity] of Object.entries(binding.escalation_severity)) {
        const where = `escalation_severity.${eventClass}`;
        if (!checkEnum(eventClass, ESCALATION_EVENT_CLASSES, `escalation_severity key ${JSON.stringify(eventClass)}`)) {
          continue;
        }
        checkEnum(severity, SEVERITY_TOKENS, where);
        if (RUNNER_EVENT_CLASSES.includes(eventClass) && !isNonEmptyString(eventRoutes[eventClass])) {
          findings.push(
            `${where}: severity is bound for a runner event class with no escalation_routes.${eventClass} entry — severity only selects notification fan-out on the filed item, so without a queue destination the class's human-gated handoff has nowhere to file (fail-closed); bind escalation_routes.${eventClass}`,
          );
        }
      }
    }
  }

  if (Object.hasOwn(binding, "escalation_severity_routes")) {
    if (!isPlainObject(binding.escalation_severity_routes)) {
      findings.push("escalation_severity_routes: must be an object mapping severity token to notification legs");
    } else {
      for (const [severity, legs] of Object.entries(binding.escalation_severity_routes)) {
        if (!checkEnum(severity, SEVERITY_TOKENS, `escalation_severity_routes key ${JSON.stringify(severity)}`)) {
          continue;
        }
        if (!isPlainObject(legs)) {
          findings.push(
            `escalation_severity_routes.${severity}: must be an object binding the notification legs separately ({channel, push}, at least one) — a bare route cannot say which leg it is, and an urgent fan-out carries both`,
          );
          continue;
        }
        checkAllowedKeys(legs, ["channel", "push"], `escalation_severity_routes.${severity}`);
        if (Object.keys(legs).length === 0) {
          findings.push(
            `escalation_severity_routes.${severity}: empty — a bound severity entry carries at least one notification leg (channel or push)`,
          );
        }
        for (const leg of ["channel", "push"]) {
          if (Object.hasOwn(legs, leg) && !isNonEmptyString(legs[leg])) {
            findings.push(`escalation_severity_routes.${severity}.${leg}: missing or empty — a bound leg carries an org-bound route`);
          }
        }
        if (isNonEmptyString(legs.push) && !isNonEmptyString(legs.channel)) {
          findings.push(
            `escalation_severity_routes.${severity}: binds a push leg with no channel leg — the fan-out ladder is cumulative (tracker item, then channel notification, then the personal-push tier), so a push-only entry leaves the channel notification the contract requires at this tier unbound; bind the channel leg too`,
          );
        }
      }
    }
  }

  if (Object.hasOwn(binding, "escalation_ack")) {
    if (!isPlainObject(binding.escalation_ack)) {
      findings.push("escalation_ack: must be an object");
    } else {
      checkAllowedKeys(binding.escalation_ack, ["staleness_window", "reescalation_cap"], "escalation_ack");
      for (const knob of ["staleness_window", "reescalation_cap"]) {
        if (Object.hasOwn(binding.escalation_ack, knob) && (!Number.isInteger(binding.escalation_ack[knob]) || binding.escalation_ack[knob] < 1)) {
          findings.push(
            `escalation_ack.${knob}: must be a positive integer (>= 1) — a non-positive acknowledgment window or re-escalation cap is meaningless; contract defaults (72h staleness window, one re-escalation) live in the runner escalation contract, not here`,
          );
        }
      }
      if (Number.isInteger(binding.escalation_ack.reescalation_cap) && binding.escalation_ack.reescalation_cap > 1) {
        findings.push(
          `escalation_ack.reescalation_cap: ${binding.escalation_ack.reescalation_cap} exceeds the contract cap — the runner escalation contract allows a single stale-unacked re-escalation (one severity bump, never a loop), so 1 is the only bindable value`,
        );
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
  checkAllowedKeys(
    admission,
    ["classification", "rules", "autonomous_concurrency", "items_per_run"],
    "admission",
  );
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
        if (surfaceClass === "temporal") {
          validateTemporalClassificationHome(ruleHome, where);
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
        checkEnum(rule.signal_class, RULE_SIGNAL_CLASSES, `${where}.signal_class`);
        checkEnum(rule.provenance, RULE_PROVENANCES, `${where}.provenance`);
        checkEnum(rule.work_class, RULE_WORK_CLASSES, `${where}.work_class`);
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

function validateTemporalClassificationHome(ruleHome, where) {
  const identityBySurface = new Map();
  const identityByProducer = new Map();
  for (const [identity, entry] of Object.entries(ruleHome)) {
    const entryWhere = `${where}.${JSON.stringify(identity)}`;
    if (!ROUTINE_IDENTITY.test(identity)) {
      findings.push(
        `${entryWhere}: ${JSON.stringify(identity)} is not a routine identity — <class-token> or <class-token>/<posture-token>, each segment lowercase [a-z][a-z0-9-]*; an out-of-grammar key can never match a stamped signal.routine, so its classification is unreachable dead policy`,
      );
    }
    if (!isPlainObject(entry)) {
      findings.push(
        `${entryWhere}: ${JSON.stringify(entry)} is a bare work class — a temporal classification with no bound emitting surface is an unprotected selector: the scheduled workflow (agent-writable in adopting repos) would pick the class; bind the object form {class, source_surface, run_link_prefix, producer_identity}`,
      );
      continue;
    }
    checkAllowedKeys(entry, ["class", "source_surface", "run_link_prefix", "producer_identity"], entryWhere);
    if (Object.hasOwn(entry, "class")) {
      checkEnum(entry.class, WORK_CLASSES, `${entryWhere}.class`);
    } else {
      findings.push(`${entryWhere}.class: required key missing`);
    }
    if (!isNonEmptyString(entry.source_surface)) {
      findings.push(
        `${entryWhere}.source_surface: missing or empty — the entry binds its routine identity to the ONE emitting surface admission attests; without the bound surface the classification is an unprotected selector, fail-closed`,
      );
    } else if (identityBySurface.has(entry.source_surface)) {
      findings.push(
        `${where}: routine identities ${JSON.stringify(identityBySurface.get(entry.source_surface))} and ${JSON.stringify(identity)} both bind source_surface ${JSON.stringify(entry.source_surface)} — one routine identity per emitting surface: on a shared surface a swapped selector still resolves a different class`,
      );
    } else {
      identityBySurface.set(entry.source_surface, identity);
    }
    if (!isNonEmptyString(entry.producer_identity)) {
      findings.push(
        `${entryWhere}.producer_identity: missing or empty — with repo-scoped run-permalink namespaces shared across schedules, only the ratified producer identity (the workflow/unit reference the platform injects into the authenticated run context) pins WHICH schedule may emit this identity; without it the class association cannot be attested, fail-closed`,
      );
    } else if (identityByProducer.has(entry.producer_identity)) {
      findings.push(
        `${where}: routine identities ${JSON.stringify(identityByProducer.get(entry.producer_identity))} and ${JSON.stringify(identity)} both declare producer_identity ${JSON.stringify(entry.producer_identity)} — two routine identities sharing one producer cannot be distinguished at admission, so the producer that pins the schedule within the shared namespace must be unique per entry`,
      );
    } else {
      identityByProducer.set(entry.producer_identity, identity);
    }
    const prefix = entry.run_link_prefix;
    if (!isNonEmptyString(prefix)) {
      findings.push(
        `${entryWhere}.run_link_prefix: missing or empty — the ratified attestation anchor is required: it pins the platform-and-repository run-permalink namespace a raw link must fall under, and without it the producer identity cannot be located within a ratified namespace, so the class association cannot be attested, fail-closed`,
      );
      continue;
    }
    let prefixUrl = null;
    if (!/\s/.test(prefix)) {
      try {
        prefixUrl = new URL(prefix);
      } catch {
      }
    }
    if (
      prefixUrl === null ||
      (prefixUrl.protocol === "https:" && prefixUrl.hostname.length === 0) ||
      NON_DURABLE_PREFIX_SCHEMES.has(prefixUrl.protocol.slice(0, -1))
    ) {
      findings.push(
        `${entryWhere}.run_link_prefix: ${JSON.stringify(prefix)} is not an attestable run-permalink namespace — an absolute https URL prefix (ci-cron) or a durable file:/artifact-scheme URI prefix (local-scheduler) is required: a relative or non-durable prefix can never match a platform-assigned run permalink, so it could never anchor the ratified namespace`,
      );
    }
  }
}

function validateClassTopologyStructure(topology, where) {
  if (!isPlainObject(topology)) {
    findings.push(`${where}: must be an object binding the class's declared topology ({min_checkers, min_model_checkers, cross_vendor_required, roles})`);
    return;
  }
  const topologyKeys = ["min_checkers", "min_model_checkers", "cross_vendor_required", "roles"];
  checkAllowedKeys(topology, topologyKeys, where);
  for (const key of topologyKeys) {
    if (!Object.hasOwn(topology, key)) {
      findings.push(`${where}.${key}: required key missing — a declared class topology carries all four axes, because a count without its role list (or a role list without its count) cannot be evaluated`);
    }
  }
  if (Object.hasOwn(topology, "min_checkers") && (!Number.isInteger(topology.min_checkers) || topology.min_checkers < 1)) {
    findings.push(`${where}.min_checkers: must be an integer >= 1`);
  }
  if (Object.hasOwn(topology, "min_model_checkers") && (!Number.isInteger(topology.min_model_checkers) || topology.min_model_checkers < 0)) {
    findings.push(`${where}.min_model_checkers: must be an integer >= 0`);
  }
  if (Object.hasOwn(topology, "cross_vendor_required") && typeof topology.cross_vendor_required !== "boolean") {
    findings.push(`${where}.cross_vendor_required: must be a boolean`);
  }
  if (!Object.hasOwn(topology, "roles")) return;
  if (!Array.isArray(topology.roles) || topology.roles.length === 0) {
    findings.push(`${where}.roles: must be a non-empty array of declared role entries`);
    return;
  }
  topology.roles.forEach((entry, index) => {
    const entryWhere = `${where}.roles[${index}]`;
    if (!isPlainObject(entry)) {
      findings.push(`${entryWhere}: must be an object`);
      return;
    }
    checkAllowedKeys(
      entry,
      ["name", "role", "scanner_class", "distinct_model_from", "distinct_vendor_from", "min_context_tokens", "requires_modality", "requires_feature"],
      entryWhere,
    );
    if (Object.hasOwn(entry, "scanner_class") && !isNonEmptyString(entry.scanner_class)) {
      findings.push(`${entryWhere}.scanner_class: must be a non-empty string naming the scanner class that distinguishes this deterministic slot`);
    }
    if (!isNonEmptyString(entry.name)) {
      findings.push(`${entryWhere}.name: missing or empty — the class-local id relational constraints resolve against`);
    }
    checkEnum(entry.role, TOPOLOGY_ROLES, `${entryWhere}.role`);
    for (const constraint of RELATIONAL_CONSTRAINTS) {
      if (!Object.hasOwn(entry, constraint)) continue;
      const value = entry[constraint];
      const targets = typeof value === "string" ? [value] : Array.isArray(value) ? value : null;
      if (!isArrayOfNonEmptyStrings(targets) || targets.length === 0) {
        findings.push(`${entryWhere}.${constraint}: must be a non-empty role name or a non-empty array of role names`);
        continue;
      }
      if (new Set(targets).size !== targets.length) {
        findings.push(
          `${entryWhere}.${constraint}: ${JSON.stringify(value)} repeats a target — listing one role twice restates a single constraint while presenting as several`,
        );
      }
    }
    if (Object.hasOwn(entry, "min_context_tokens") && (!Number.isInteger(entry.min_context_tokens) || entry.min_context_tokens < 1)) {
      findings.push(`${entryWhere}.min_context_tokens: must be an integer >= 1 — the predicate evaluates against the declared input limit of the bound instance`);
    }
    for (const predicate of ["requires_modality", "requires_feature"]) {
      if (!Object.hasOwn(entry, predicate)) continue;
      const value = entry[predicate];
      if (!isArrayOfNonEmptyStrings(value) || value.length === 0) {
        findings.push(`${entryWhere}.${predicate}: must be a non-empty array of non-empty string tokens`);
        continue;
      }
      if (new Set(value).size !== value.length) {
        findings.push(
          `${entryWhere}.${predicate}: ${JSON.stringify(value)} repeats a token — a repeated requirement is one requirement presenting as several`,
        );
      }
    }
  });
}


function levelNumber(token) {
  return Number(token.slice(1));
}

function jointlySatisfiable(markersA, markersB) {
  return Object.entries(markersA).every(([key, value]) => !Object.hasOwn(markersB, key) || markersB[key] === value);
}

const INET_PART = /^(?:0[xX][0-9a-fA-F]+|0[0-7]*|[1-9]\d*)$/;

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
  const c = Math.floor(addr / 256) % 256;
  return (
    a === 0 ||
    a === 127 ||
    a === 10 ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 169 && b === 254) ||
    (a === 192 && b === 0 && c === 0) ||
    (a === 192 && b === 0 && c === 2) ||
    (a === 192 && b === 88 && c === 99) ||
    (a === 198 && b === 51 && c === 100) ||
    (a === 203 && b === 0 && c === 113) ||
    (a === 198 && (b === 18 || b === 19)) ||
    (a === 100 && b >= 64 && b <= 127) ||
    a >= 224
  );
}

function expandIpv6(value) {
  let v = value;
  let groupsNeeded = 8;
  let v4Hextets = null;
  if (v.includes(".")) {
    const lastColon = v.lastIndexOf(":");
    if (lastColon === -1) return null;
    const parts = v.slice(lastColon + 1).split(".");
    if (parts.length !== 4 || parts.some((part) => !/^\d{1,3}$/.test(part) || Number(part) > 255)) return null;
    const [a, b, c, d] = parts.map(Number);
    v4Hextets = [(a * 256 + b).toString(16), (c * 256 + d).toString(16)];
    v = v.slice(0, lastColon + 1);
    if (!v.endsWith("::")) v = v.slice(0, -1);
    groupsNeeded = 6;
  }
  const compressed = v.split("::");
  if (compressed.length > 2) return null;
  const parseGroups = (s) => (s === "" ? [] : s.split(":"));
  const head = parseGroups(compressed[0]);
  const tail = compressed.length === 2 ? parseGroups(compressed[1]) : null;
  const validGroup = (group) => /^[0-9a-f]{1,4}$/.test(group);
  if (!head.every(validGroup) || (tail !== null && !tail.every(validGroup))) return null;
  let groups;
  if (tail === null) {
    if (head.length !== groupsNeeded) return null;
    groups = head;
  } else {
    const fill = groupsNeeded - head.length - tail.length;
    if (fill < 1) return null;
    groups = [...head, ...Array(fill).fill("0"), ...tail];
  }
  if (v4Hextets !== null) groups = [...groups, ...v4Hextets];
  return groups.map((group) => group.padStart(4, "0"));
}

function isNonExternalEgressHost(host) {
  const h = host.toLowerCase().replace(/^\[|\]$/g, "");
  if (h.includes(":")) {
    const hextets = expandIpv6(h);
    if (hextets === null) return true;
    const allZeroHextets = (start, end) => hextets.slice(start, end).every((hextet) => hextet === "0000");
    const embeddedV4 = () => Number.parseInt(hextets[6], 16) * 65536 + Number.parseInt(hextets[7], 16);
    if (allZeroHextets(0, 5) && hextets[5] === "ffff") {
      return isDeniedV4(embeddedV4());
    }
    if (allZeroHextets(0, 6)) {
      return true;
    }
    if (hextets[0] === "0064" && hextets[1] === "ff9b" && allZeroHextets(2, 6)) {
      return isDeniedV4(embeddedV4());
    }
    const first = Number.parseInt(hextets[0], 16);
    const second = Number.parseInt(hextets[1], 16);
    if (hextets[0] === "2001" && second <= 0x01ff) {
      const reachableAnycast = second === 0x0001 && allZeroHextets(2, 7) && ["0001", "0002", "0003"].includes(hextets[7]);
      return !(
        reachableAnycast ||
        second === 0x0003 ||
        (second === 0x0004 && hextets[2] === "0112") ||
        (second >= 0x0020 && second <= 0x003f)
      );
    }
    return (
      (first >= 0xfc00 && first <= 0xfdff) ||
      (first >= 0xfe80 && first <= 0xfebf) ||
      (first >= 0xfec0 && first <= 0xfeff) ||
      first >= 0xff00 ||
      (hextets[0] === "0100" &&
        hextets[1] === "0000" &&
        hextets[2] === "0000" &&
        (hextets[3] === "0000" || hextets[3] === "0001")) ||
      (hextets[0] === "0064" && hextets[1] === "ff9b" && hextets[2] === "0001") ||
      hextets[0] === "2002" ||
      (hextets[0] === "2001" && hextets[1] === "0db8") ||
      (hextets[0] === "3fff" && second <= 0x0fff) ||
      hextets[0] === "5f00"
    );
  }
  const name = h.endsWith(".") ? h.slice(0, -1) : h;
  if (name === "localhost" || name.endsWith(".localhost")) return true;
  const folded = foldInetAton(name);
  if (folded !== null) return isDeniedV4(folded);
  if (name.split(".").every((label) => INET_PART.test(label))) return true;
  const labels = name.split(".");
  const validLabel = (label) => /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(label);
  return name.length > 253 || labels.length < 2 || !labels.every(validLabel);
}

function verifyProbeTranscript(ref, probeRoot, surfaceId, level, substrate, substrateClass, egressAllowList, credentialRoots, componentReachableHosts, hostInterop) {
  if (probeRoot === null) {
    return `no --probe-evidence-root configured — probe evidence verifies only against a protected evidence root outside the agent's write reach; pass --probe-evidence-root <dir> naming the protected evidence surface the capture lives on`;
  }
  if (isAbsolute(ref)) {
    return `probe_evidence ${JSON.stringify(ref)} is an absolute path but --probe-evidence-root ${JSON.stringify(probeRoot)} is configured — reference the transcript relative to the root, never by absolute path`;
  }
  const resolvedRoot = resolve(probeRoot);
  const resolved = resolve(resolvedRoot, ref);
  const rel = relative(resolvedRoot, resolved);
  if (rel === ".." || rel.startsWith(`..${sep}`)) {
    return `probe_evidence ${JSON.stringify(ref)} escapes --probe-evidence-root ${JSON.stringify(probeRoot)} via ".." traversal — reference a transcript inside the configured root`;
  }
  let realResolved = null;
  try {
    realResolved = realpathSync(resolved);
  } catch {
  }
  let path;
  if (realResolved !== null) {
    const realRoot = realpathSync(resolvedRoot);
    const fold = (p) => (process.platform === "win32" ? p.toLowerCase() : p);
    if (!fold(realResolved).startsWith(fold(realRoot + sep))) {
      return `probe_evidence ${JSON.stringify(ref)} resolves through a link to a real path outside --probe-evidence-root ${JSON.stringify(probeRoot)} — evidence must physically live inside the configured root`;
    }
    path = realResolved;
  } else {
    path = resolved;
  }
  let transcript;
  try {
    transcript = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    return `transcript ${path} is not readable JSON (${error.message})`;
  }
  if (!isPlainObject(transcript)) {
    return `transcript ${path} is not a capture-shape object`;
  }
  if (transcript.schema_version !== "1") {
    return `transcript ${path} records schema_version ${JSON.stringify(transcript.schema_version)} — the capture shape requires "1"`;
  }
  if (Number.isNaN(parseIsoStrict(transcript.probed_at))) {
    return `transcript ${path} records probed_at ${JSON.stringify(transcript.probed_at)} — a strict ISO 8601 date-time with explicit offset is required`;
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
  if (transcript.substrate_class !== substrateClass) {
    return `transcript ${path} records substrate_class ${JSON.stringify(transcript.substrate_class)}, not this binding entry's ratified substrate_class ${JSON.stringify(substrateClass)} — the capture proves a different substrate than the human-ratified assertion`;
  }
  if (!SUBSTRATE_CLASSES.has(transcript.substrate_class)) {
    return `transcript ${path} records substrate_class ${JSON.stringify(transcript.substrate_class)} — required, one of ${[...SUBSTRATE_CLASSES].join(" | ")}`;
  }
  if (level === "L3" && !L3_SUBSTRATE_CLASSES.has(transcript.substrate_class)) {
    return `transcript ${path} records substrate_class ${JSON.stringify(transcript.substrate_class)} for an L3 entry — L3 requires kernel separation, which only the kernel-separated substrate classes (${[...L3_SUBSTRATE_CLASSES].map((token) => JSON.stringify(token)).join(", ")}) provide`;
  }
  if (transcript.assertions?.egress_denied?.outcome !== "denied") {
    return `transcript ${path} does not record the egress-denial assertion with outcome "denied"`;
  }
  if (transcript.assertions?.credentials_absent?.outcome !== "absent-or-denied") {
    return `transcript ${path} does not record the credential-absence assertion with outcome "absent-or-denied"`;
  }
  const egress = transcript.assertions.egress_denied;
  const credentials = transcript.assertions.credentials_absent;
  const nonzeroExit = (value) => typeof value === "string" && /^[1-9][0-9]*$/.test(value);
  const rawEgressHost = egress.host;
  if (typeof rawEgressHost !== "string" || rawEgressHost.length === 0) {
    return `transcript ${path} records assertions.egress_denied.host ${JSON.stringify(rawEgressHost)} — a proven egress-denial requires the probed external host (non-empty; comma-separated entries when several targets were probed)`;
  }
  const egressHosts = splitRecordedList(rawEgressHost);
  for (const host of egressHosts) {
    if (host.length === 0 || /\s/.test(host)) {
      return `transcript ${path} records assertions.egress_denied.host ${JSON.stringify(rawEgressHost)} — every comma-separated host entry must be non-empty with no whitespace`;
    }
  }
  const rawEgressCodes = egress.exit_code;
  const egressCodes = splitRecordedList(rawEgressCodes);
  if (egressCodes.length !== egressHosts.length) {
    return `transcript ${path} records assertions.egress_denied.exit_code ${JSON.stringify(rawEgressCodes)} for ${egressHosts.length} probed host entr${egressHosts.length === 1 ? "y" : "ies"} — one recorded exit code per probed host is required, comma-separated and positionally paired with host: a single code cannot prove denial toward every listed target`;
  }
  const rawTransportForExit = egress.transport_outcome;
  const transportForExit = splitRecordedList(rawTransportForExit);
  for (const [index, code] of egressCodes.entries()) {
    if (nonzeroExit(code)) continue;
    if (transportForExit[index] === "peer-substituted") continue;
    return `transcript ${path} records assertions.egress_denied.exit_code entry ${JSON.stringify(code)} for host ${JSON.stringify(egressHosts[index])} — a proven egress-denial requires a non-zero integer exit code string for every probed host, unless that host's transport_outcome is "peer-substituted" and its recorded peer fingerprints differ, which proves an interceptor answered rather than the origin`;
  }
  for (const host of egressHosts) {
    if (
      host.includes("/") ||
      (host.match(/:/g) ?? []).length === 1 ||
      (host.includes("]") && !host.endsWith("]"))
    ) {
      return `transcript ${path} records assertions.egress_denied.host ${JSON.stringify(host)} — record the BARE probed hostname or IP; URI, path, and host:port forms are rejected rather than parsed`;
    }
    if (isNonExternalEgressHost(host)) {
      return `transcript ${path} records assertions.egress_denied.host ${JSON.stringify(host)} — a loopback/private/link-local or otherwise non-external target (after normalizing encoded forms) cannot prove EXTERNAL egress denial; probe a genuine external host (multi-label DNS name or public IP)`;
    }
    if (egressAllowList !== null) {
      if (!egressAllowList.includes(bareHost(host))) {
        return `transcript ${path} records assertions.egress_denied.host ${JSON.stringify(host)} — not in the configured egress-probe allow-list (--egress-hosts ${egressAllowList.join(",")})`;
      }
    } else {
      const bare = bareHost(host);
      const specialTld = SPECIAL_USE_TLDS.find((tld) => bare === tld.slice(1) || bare.endsWith(tld));
      if (specialTld !== undefined) {
        return `transcript ${path} records assertions.egress_denied.host ${JSON.stringify(host)} — the special-use/reserved TLD ${JSON.stringify(specialTld)} can never demonstrate public egress; probe a resolvable public host, or pass the org's configured target via --egress-hosts`;
      }
    }
  }
  const rawOuterCodes = egress.outer_exit_code;
  const outerCodes = splitRecordedList(rawOuterCodes);
  if (outerCodes.length !== egressHosts.length) {
    return `transcript ${path} records assertions.egress_denied.outer_exit_code ${JSON.stringify(rawOuterCodes)} for ${egressHosts.length} probed host entr${egressHosts.length === 1 ? "y" : "ies"} — one recorded outer-context exit code per probed host is required, comma-separated and positionally paired with host: a failed inner probe proves an egress boundary only when the outer context proves the target was reachable`;
  }
  for (const [index, code] of outerCodes.entries()) {
    if (code !== "0") {
      return `transcript ${path} records assertions.egress_denied.outer_exit_code entry ${JSON.stringify(code)} for host ${JSON.stringify(egressHosts[index])} — the outer-context fetch of the same target must succeed (exit "0"): a failed inner probe proves an egress boundary only when the outer context proves the target was reachable`;
    }
  }
  if (!isNonEmptyString(credentials.path)) {
    return `transcript ${path} records assertions.credentials_absent.path ${JSON.stringify(credentials.path)} — a proven credential-absence requires the probed host-credential path`;
  }
  const credentialPaths = splitRecordedList(credentials.path);
  const rawCredentialCodes = credentials.exit_code;
  const credentialCodes = splitRecordedList(rawCredentialCodes);
  if (credentialCodes.length !== credentialPaths.length) {
    return `transcript ${path} records assertions.credentials_absent.exit_code ${JSON.stringify(rawCredentialCodes)} for ${credentialPaths.length} probed path entr${credentialPaths.length === 1 ? "y" : "ies"} — one recorded exit code per probed credential path is required, comma-separated and positionally paired with path: a single code cannot prove absence on every listed location`;
  }
  const rawHostExpanded = credentials.host_expanded;
  const hostExpanded = splitRecordedList(rawHostExpanded);
  if (hostExpanded.length !== credentialPaths.length) {
    return `transcript ${path} records assertions.credentials_absent.host_expanded ${JSON.stringify(rawHostExpanded)} for ${credentialPaths.length} probed path entr${credentialPaths.length === 1 ? "y" : "ies"} — one recorded host-side expansion per probed credential path is required, comma-separated and positionally paired with path: an in-shell home token expands to the boundary's own home, so only a recorded host-side expansion names the host credential location`;
  }
  const rawTransportOutcomes = credentials.transport_outcome;
  const transportOutcomes = splitRecordedList(rawTransportOutcomes);
  if (transportOutcomes.length !== credentialPaths.length) {
    return `transcript ${path} records assertions.credentials_absent.transport_outcome ${JSON.stringify(rawTransportOutcomes)} for ${credentialPaths.length} probed path entr${credentialPaths.length === 1 ? "y" : "ies"} — one recorded transport outcome per probed credential path is required ("connect-failed" for a metadata URL, "read-denied" for a filesystem or env-token entry), comma-separated and positionally paired with path: without it a reachable metadata service's HTTP error is indistinguishable from a denied connection`;
  }
  const rawCredentialOuterCodes = credentials.outer_exit_code;
  const credentialOuterCodes = splitRecordedList(rawCredentialOuterCodes);
  if (credentialOuterCodes.length !== credentialPaths.length) {
    return `transcript ${path} records assertions.credentials_absent.outer_exit_code ${JSON.stringify(rawCredentialOuterCodes)} for ${credentialPaths.length} probed path entr${credentialPaths.length === 1 ? "y" : "ies"} — one recorded outer-context exit code per probed credential path is required, comma-separated and positionally paired with path: a failed inner read proves a credential boundary only when the outer context proves the target exists on the host`;
  }
  for (const [index, entry] of credentialPaths.entries()) {
    const entryProblem = credentialEntryProblem(entry, hostExpanded[index], credentialRoots);
    if (entryProblem !== null) {
      return `transcript ${path} records assertions.credentials_absent.path entry ${JSON.stringify(entry)} — ${entryProblem}`;
    }
    if (!nonzeroExit(credentialCodes[index])) {
      return `transcript ${path} records assertions.credentials_absent.exit_code entry ${JSON.stringify(credentialCodes[index])} for path ${JSON.stringify(entry)} — a proven credential-absence requires a non-zero integer exit code string for every probed path`;
    }
    const urlEntry = entry.toLowerCase().replaceAll("\\", "/").includes("://");
    if (urlEntry && transportOutcomes[index] !== "connect-failed") {
      return `transcript ${path} records assertions.credentials_absent.transport_outcome entry ${JSON.stringify(transportOutcomes[index])} for metadata-URL path ${JSON.stringify(entry)} — an HTTP-level service error proves the connection SUCCEEDED (the metadata service is reachable; no boundary); only connection-level failure (refused, timeout, no route), recorded as "connect-failed", demonstrates the service is unreachable from inside the boundary`;
    }
    if (!urlEntry && transportOutcomes[index] !== "read-denied") {
      return `transcript ${path} records assertions.credentials_absent.transport_outcome entry ${JSON.stringify(transportOutcomes[index])} for path ${JSON.stringify(entry)} — a filesystem or env-token read has no connection to fail; its probe outcome is recorded as "read-denied"`;
    }
    if (credentialOuterCodes[index] !== "0") {
      return `transcript ${path} records assertions.credentials_absent.outer_exit_code entry ${JSON.stringify(credentialOuterCodes[index])} for path ${JSON.stringify(entry)} — the outer-context existence check of the same target must succeed (exit "0"): a failed inner read proves a credential boundary only when the outer context proves the target exists on the host`;
    }
  }
  if (transcript.outer_context_networked !== true) {
    return `transcript ${path} does not record outer_context_networked true — an offline outer context would deny egress on its own`;
  }
  if (egress.client_ready !== "0") {
    return `transcript ${path} records assertions.egress_denied.client_ready ${JSON.stringify(egress.client_ready)} — the probe client must first be shown to RUN inside the boundary (exit "0" against an in-boundary endpoint): an absent or broken client would otherwise satisfy every egress assertion trivially`;
  }
  if (egressHosts.length < 2) {
    return `transcript ${path} records ${egressHosts.length} probed egress target — a single probed target cannot establish default-deny egress, since a policy may allow other destinations while denying this one; probe at least two distinct external targets under different operators`;
  }
  const distinctEgressHosts = new Set(egressHosts.map(bareHost));
  if (distinctEgressHosts.size < 2) {
    return `transcript ${path} records ${egressHosts.length} egress entries naming only ${distinctEgressHosts.size} distinct target — repeating one host measures a single policy decision while presenting as several; probe at least two distinct external targets under different operators`;
  }
  const rawEgressTransport = egress.transport_outcome;
  const egressTransport = splitRecordedList(rawEgressTransport);
  if (egressTransport.length !== egressHosts.length) {
    return `transcript ${path} records assertions.egress_denied.transport_outcome ${JSON.stringify(rawEgressTransport)} for ${egressHosts.length} probed host entr${egressHosts.length === 1 ? "y" : "ies"} — one recorded transport outcome per probed host is required, comma-separated and positionally paired with host: an exit code alone cannot distinguish a boundary that dropped the session from one that returned an interception response`;
  }
  const rawOuterFingerprints = egress.outer_peer_fingerprint;
  const rawInnerFingerprints = egress.inner_peer_fingerprint;
  const outerFingerprints = splitRecordedList(rawOuterFingerprints);
  const innerFingerprints = splitRecordedList(rawInnerFingerprints);
  if (outerFingerprints.length !== egressHosts.length || innerFingerprints.length !== egressHosts.length) {
    return `transcript ${path} records assertions.egress_denied.outer_peer_fingerprint ${JSON.stringify(rawOuterFingerprints)} and inner_peer_fingerprint ${JSON.stringify(rawInnerFingerprints)} for ${egressHosts.length} probed host entries — one recorded peer fingerprint per probed host is required on each side, comma-separated and positionally paired with host (the literal "none" where no handshake completed)`;
  }
  for (const [index, outcome] of egressTransport.entries()) {
    if (!EGRESS_TRANSPORT_OUTCOMES.has(outcome)) {
      return `transcript ${path} records assertions.egress_denied.transport_outcome entry ${JSON.stringify(outcome)} for host ${JSON.stringify(egressHosts[index])} — required, one of ${[...EGRESS_TRANSPORT_OUTCOMES].join(" | ")}; a completed handshake with the origin's own peer identity from which data was read has no passing token, because it is egress`;
    }
    if (outcome === "peer-substituted") {
      if (outerFingerprints[index] === "none" || innerFingerprints[index] === "none") {
        return `transcript ${path} records assertions.egress_denied.transport_outcome "peer-substituted" for host ${JSON.stringify(egressHosts[index])} with fingerprint ${JSON.stringify(innerFingerprints[index])} — a substituted peer is proven by COMPARISON, so both the outer-context and in-boundary peer fingerprints must be recorded for that target`;
      }
      if (outerFingerprints[index] === innerFingerprints[index]) {
        return `transcript ${path} records assertions.egress_denied.inner_peer_fingerprint entry ${JSON.stringify(innerFingerprints[index])} for host ${JSON.stringify(egressHosts[index])} matching the outer-context fingerprint — an identical peer identity means the ORIGIN answered inside the boundary, which is reached egress, not interception`;
      }
    } else if (innerFingerprints[index] !== "none") {
      return `transcript ${path} records assertions.egress_denied.inner_peer_fingerprint entry ${JSON.stringify(innerFingerprints[index])} for host ${JSON.stringify(egressHosts[index])} whose transport_outcome is ${JSON.stringify(outcome)} — an outcome other than "peer-substituted" asserts that no peer completed a handshake, so its fingerprint must be the literal "none"; a recorded peer contradicts the outcome beside it`;
    }
  }
  const rawAddressFamilies = egress.address_families;
  const addressFamilies = splitRecordedList(rawAddressFamilies);
  if (addressFamilies.length === 0 || addressFamilies.some((family) => !ADDRESS_FAMILIES.has(family))) {
    return `transcript ${path} records assertions.egress_denied.address_families ${JSON.stringify(rawAddressFamilies)} — required, a non-empty comma-separated list drawn from ${[...ADDRESS_FAMILIES].join(" | ")}: a boundary sealed on one address family and open on the other passes an unrecorded probe, so the exercised families are recorded rather than inferred`;
  }
  const workspaceProblem = verifyWorkspaceContainment(transcript, path);
  if (workspaceProblem !== null) return workspaceProblem;
  if (!Array.isArray(componentReachableHosts)) {
    return `the level binding ratifies no component_reachable_hosts — the destinations this surface's installed components may request are an outer-world fact no capture can establish, so they are ratified on the binding entry and the probe must cover them; ratify the list (or the empty list, where this surface installs nothing carrying policy rules of its own) on the agent-unwritable binding surface`;
  }
  if (componentReachableHosts.some((host) => !isNonEmptyString(host))) {
    return `the level binding ratifies a component_reachable_hosts entry that is not a non-empty host string — every ratified destination must name a host the probe can be checked against`;
  }
  const uncoveredRatified = componentReachableHosts
    .map((host) => bareHost(host.trim()))
    .filter((host) => !distinctEgressHosts.has(host));
  if (uncoveredRatified.length > 0) {
    return `transcript ${path} probes ${[...distinctEgressHosts].join(", ")}, leaving ratified component_reachable_hosts ${uncoveredRatified.join(", ")} unprobed — each ratified destination is a separate policy decision, so covering one says nothing about the rest; probe every ratified component-reachable destination in the configuration the run will actually use`;
  }
  return verifyHostInterop(transcript, path, hostInterop, hostExpanded);
}

function verifyHostInterop(transcript, path, hostInterop, hostExpanded) {
  const recorded = Object.hasOwn(transcript.assertions, "interop_launch_denied");
  if (hostInterop === "wsl2" && !recorded) {
    return `transcript ${path} does not record assertions.interop_launch_denied, which the level binding requires by ratifying host_interop "wsl2": a Windows binary launched from inside a WSL2 boundary runs on the Windows host, so only a denied launch of a present executable proves the boundary`;
  }
  if (recorded) {
    const interop = transcript.assertions.interop_launch_denied;
    if (!isPlainObject(interop)) {
      return `transcript ${path} records assertions.interop_launch_denied ${JSON.stringify(interop)}: the interop launch check must be recorded as an object with every field, never skipped`;
    }
    for (const field of ["executable", "outer_executable"]) {
      const value = interop[field];
      const base = typeof value === "string" ? value.split("/").pop() : "";
      if (!isNonEmptyString(value) || !value.startsWith("/") || value.includes("\\") || !/.\.exe$/i.test(base)) {
        return `transcript ${path} records assertions.interop_launch_denied.${field} ${JSON.stringify(value)}: an absolute POSIX path to a Windows executable (basename ending ".exe") is required, so the launch provably targeted the Windows host`;
      }
    }
    for (const field of ["arguments", "outer_arguments"]) {
      if (typeof interop[field] !== "string") {
        return `transcript ${path} records assertions.interop_launch_denied.${field} ${String(JSON.stringify(interop[field]))}: [interop-same-invocation] the launch arguments are recorded on both sides as strings (empty when none), so the inner launch is provably the invocation the outer control ran`;
      }
    }
    if (interop.arguments !== interop.outer_arguments) {
      return `transcript ${path} records assertions.interop_launch_denied.arguments ${JSON.stringify(interop.arguments)} against outer_arguments ${JSON.stringify(interop.outer_arguments)}: [interop-same-invocation] the inner launch must be byte-identical to the outer control, or a non-zero inner exit may be a different invocation that ran and failed`;
    }
    for (const field of ["executable_sha256", "outer_executable_sha256"]) {
      if (typeof interop[field] !== "string" || !/^[0-9a-f]{64}$/.test(interop[field])) {
        return `transcript ${path} records assertions.interop_launch_denied.${field} ${String(JSON.stringify(interop[field]))}: [interop-same-executable] a SHA-256 digest of 64 lowercase hex characters is required on both sides`;
      }
    }
    if (interop.executable_sha256 !== interop.outer_executable_sha256) {
      return `transcript ${path} records assertions.interop_launch_denied.executable_sha256 differs from outer_executable_sha256: [interop-same-executable] the inner file must be the executable the outer control ran`;
    }
    if (interop.executable_magic !== "4d5a") {
      return `transcript ${path} records assertions.interop_launch_denied.executable_magic ${String(JSON.stringify(interop.executable_magic))}: [interop-pe-magic] the inner file's first two bytes must be "4d5a" (the PE "MZ" header), so the launch targeted a Windows binary`;
    }
    if (interop.outer_exit_code !== "0") {
      return `transcript ${path} records assertions.interop_launch_denied.outer_exit_code ${JSON.stringify(interop.outer_exit_code)}: the outer-context launch must succeed (exit "0"), or an inner failure cannot be told apart from an executable that fails everywhere`;
    }
    if (interop.presence_exit_code !== "0") {
      return `transcript ${path} records assertions.interop_launch_denied.presence_exit_code ${JSON.stringify(interop.presence_exit_code)}: the inner \`test -x\` must succeed (exit "0"), because a failed launch of a missing executable is no evidence of a denied launch`;
    }
    const code = interop.exit_code;
    if (typeof code !== "string" || !INTEROP_DENIAL_EXIT_CODE.test(code)) {
      return `transcript ${path} records assertions.interop_launch_denied.exit_code ${JSON.stringify(code)}: a denied launch requires an exit code string from 1 to 123, or 126 (the kernel refused the binary format); 124 and 125 are timeout statuses, 127 is command not found (contradicting the presence proof), and 128 or above is death by signal, none of which is a denial${code === "0" ? `; exit "0" means the launch reached the Windows host` : ""}`;
    }
    if (interop.launch_outcome !== "launch-denied") {
      return `transcript ${path} records assertions.interop_launch_denied.launch_outcome ${JSON.stringify(interop.launch_outcome)}: the only passing token is "launch-denied"; a missing file has no passing token`;
    }
    if (interop.outcome !== "denied") {
      return `transcript ${path} records assertions.interop_launch_denied.outcome ${JSON.stringify(interop.outcome)}: a proven interop denial records outcome "denied"`;
    }
  }
  if (hostInterop === "none") {
    const driveMount = (value) =>
      typeof value === "string" && /^\/mnt\/[a-z](\/|$)/i.test(posix.normalize(value.trim().replaceAll("\\", "/")));
    const interop = transcript.assertions.interop_launch_denied;
    const candidates = [
      ...hostExpanded.map((value) => ["credentials_absent.host_expanded entry", value]),
      ["workspace_host_write_contained.workspace_host_path", transcript.assertions.workspace_host_write_contained.workspace_host_path],
      ["interop_launch_denied.executable", interop?.executable],
      ["interop_launch_denied.outer_executable", interop?.outer_executable],
    ];
    const hit = candidates.find(([, value]) => driveMount(value));
    if (hit !== undefined) {
      return `transcript ${path} records assertions.${hit[0]} ${JSON.stringify(hit[1])} sits under a Windows drive mount (/mnt/<letter>/), but the level binding ratifies host_interop "none": a surface that reaches a Windows drive is WSL2-hosted, so ratify host_interop "wsl2" and record the interop launch check`;
    }
  }
  if (!HOST_INTEROP_TOKENS.includes(hostInterop)) {
    return `the level binding ratifies no host_interop${hostInterop === undefined ? "" : ` token (${JSON.stringify(hostInterop)} is not one of ${HOST_INTEROP_TOKENS.join(" | ")})`}: whether the surface's host can launch host binaries from inside the boundary is an outer-world fact no capture can establish, so an L2/L3 level states it on the agent-unwritable binding as "wsl2" (the transcript must then record the interop launch check) or "none"`;
  }
  return null;
}

function verifyWorkspaceContainment(transcript, path) {
  const workspace = transcript.assertions?.workspace_host_write_contained;
  if (workspace?.outcome !== "contained") {
    return `transcript ${path} does not record the workspace host-write containment assertion with outcome "contained" — the process boundary the level describes does not cover the workspace mount, and an unmeasured mount can carry host-executing writes; a recorded outcome of "not-applicable" leaves the level unproven rather than passing it`;
  }
  if (!isNonEmptyString(workspace.workspace_host_path)) {
    return `transcript ${path} records assertions.workspace_host_write_contained.workspace_host_path ${JSON.stringify(workspace.workspace_host_path)} — containment is proven from the OUTER side, so the host-side workspace root the outer context inspected must be recorded`;
  }
  if (workspace.checked_after_teardown !== true) {
    return `transcript ${path} does not record assertions.workspace_host_write_contained.checked_after_teardown true — a caching or asynchronously-flushed mount can propagate an inner write after an immediate check, so the host-side re-check runs after the boundary is torn down`;
  }
  const canaries = splitRecordedList(workspace.canaries);
  if (canaries.length < WORKSPACE_CANARY_MINIMUM || canaries.some((entry) => entry.length === 0)) {
    return `transcript ${path} records assertions.workspace_host_write_contained.canaries ${JSON.stringify(workspace.canaries)} — at least ${WORKSPACE_CANARY_MINIMUM} non-empty canary paths are required (an ordinary file, a dotfile, and a VCS-control-plane path), because a single literal path proves nothing about hidden-file handling, case folding, or the control plane that executes host code`;
  }
  if (new Set(canaries.map((entry) => entry.toLowerCase())).size !== canaries.length) {
    return `transcript ${path} records assertions.workspace_host_write_contained.canaries ${JSON.stringify(workspace.canaries)} — the canary paths must be DISTINCT (compared case-insensitively, since a case-folding host filesystem would otherwise let one landed write hide behind a differently-spelled name); repeating a path probes one location while presenting as several`;
  }
  if (canaries.some((entry) => entry.startsWith("/") || entry.split(/[\\/]/).includes(".."))) {
    return `transcript ${path} records assertions.workspace_host_write_contained.canaries ${JSON.stringify(workspace.canaries)} — every canary must be a workspace-relative path with no parent traversal; an absolute or escaping path proves containment somewhere other than the workspace mount under test`;
  }
  const isVcsControlPlane = (entry) => entry.split(/[\\/]/)[0] === ".git";
  const isDotfile = (entry) => {
    const base = entry.split(/[\\/]/).pop() ?? "";
    return base.startsWith(".") && !isVcsControlPlane(entry);
  };
  const missingShapes = [
    canaries.some(isVcsControlPlane) ? null : "a VCS-control-plane path (a `.git/`-relative entry)",
    canaries.some(isDotfile) ? null : "a dotfile",
    canaries.some((entry) => !isVcsControlPlane(entry) && !isDotfile(entry)) ? null : "an ordinary file",
  ].filter(Boolean);
  if (missingShapes.length > 0) {
    return `transcript ${path} records assertions.workspace_host_write_contained.canaries ${JSON.stringify(workspace.canaries)} — missing ${missingShapes.join(" and ")}; the three shapes are the assertion, not a suggestion: a set that omits the control-plane path leaves the documented host-execution route unprobed, and one that omits the dotfile says nothing about hidden-file handling`;
  }
  for (const [field, requirement] of [
    ["host_pre_absent", "the outer context must prove every canary ABSENT before the probe, or its later absence proves nothing"],
    ["host_post_absent", "every canary must still be absent on the host after teardown — a visible canary is a write that escaped the boundary"],
  ]) {
    const raw = workspace[field];
    const codes = splitRecordedList(raw);
    if (codes.length !== canaries.length) {
      return `transcript ${path} records assertions.workspace_host_write_contained.${field} ${JSON.stringify(raw)} for ${canaries.length} canary entries — one recorded exit code per canary is required, comma-separated and positionally paired with canaries: a single code cannot vouch for every path`;
    }
    for (const [index, code] of codes.entries()) {
      if (code !== "0") {
        return `transcript ${path} records assertions.workspace_host_write_contained.${field} entry ${JSON.stringify(code)} for canary ${JSON.stringify(canaries[index])} — ${requirement}`;
      }
    }
  }
  const innerCodes = splitRecordedList(workspace.inner_exit_code);
  if (innerCodes.length !== canaries.length) {
    return `transcript ${path} records assertions.workspace_host_write_contained.inner_exit_code ${JSON.stringify(workspace.inner_exit_code)} for ${canaries.length} canary entries — one recorded inner exit code per canary is required (recorded as evidence, never asserted on: a clone-mode mount legitimately ACCEPTS the write and discards it)`;
  }
  for (const [index, code] of innerCodes.entries()) {
    if (!/^(0|[1-9][0-9]*)$/.test(code)) {
      return `transcript ${path} records assertions.workspace_host_write_contained.inner_exit_code entry ${JSON.stringify(code)} for canary ${JSON.stringify(canaries[index])} — every entry must be a recorded integer exit code (any value; zero is legitimate on a copy-on-read mount), because host absence evidences containment only where a write was actually attempted`;
    }
  }
  if (!isNonEmptyString(workspace.git_config_digest_pre) || !isNonEmptyString(workspace.git_config_digest_post)) {
    return `transcript ${path} records assertions.workspace_host_write_contained.git_config_digest_pre ${JSON.stringify(workspace.git_config_digest_pre)} and git_config_digest_post ${JSON.stringify(workspace.git_config_digest_post)} — both are required (the literal "absent" where the workspace carries no .git/config), because the VCS control plane is the documented host-execution path and needs its own before/after evidence`;
  }
  if (workspace.git_config_digest_pre !== workspace.git_config_digest_post) {
    return `transcript ${path} records assertions.workspace_host_write_contained.git_config_digest_post ${JSON.stringify(workspace.git_config_digest_post)} against a pre-probe digest of ${JSON.stringify(workspace.git_config_digest_pre)} — the VCS control plane changed from inside the boundary, which is host code execution: config keys there run commands, and one of them fires on a read-only-looking status call`;
  }
  return null;
}

function checkSemantics(binding, probeRoot, egressAllowList, credentialRoots) {
  const posture = binding.dispatch_posture ?? "autonomous-enabled";
  const autonomous = posture === "autonomous-enabled";

  if (isPlainObject(binding.merge_policy)) {
    for (const workClass of WORK_CLASSES) {
      if (binding.merge_policy[workClass] !== "auto") continue;
      if (!Object.hasOwn(AUTO_MERGE_PROMOTION_CELL, workClass)) {
        findings.push(
          `merge_policy.${workClass}: "auto" exceeds the matrix cap — ${workClass === "C5" ? "C5 merge is human always" : "the matrix merges this class human; only the C2, C3 and C4 cells are auto-merge eligible"}`,
        );
      }
    }
  }

  const surfaces = isPlainObject(binding.isolation_bindings) ? Object.entries(binding.isolation_bindings) : [];

  if (autonomous) {
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

  const verdicts = [];
  let anyProvenL2 = false;
  let anyUnprovenL2Plus = false;
  for (const [surfaceId, levels] of surfaces) {
    if (!isPlainObject(levels)) continue;
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
        ? verifyProbeTranscript(entry.probe_evidence, probeRoot, surfaceId, level, entry.substrate, entry.substrate_class, egressAllowList, credentialRoots, entry.component_reachable_hosts, entry.host_interop)
        : "probe_evidence missing";
      if (reason === null) {
        provenMax = Math.max(provenMax, levelNo);
        continue;
      }
      anyUnprovenL2Plus = true;
      unproven.push(`${level} unproven (${reason})`);
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

  if (isPlainObject(binding.promotion_state)) {
    for (const cell of Object.keys(binding.promotion_state)) {
      if (!PROMOTABLE_CELLS.has(cell)) {
        findings.push(
          `promotion_state.${cell}: not a promotable cell — promotable cells are ${[...PROMOTABLE_CELLS].join(", ")}; C4 auto-merge reads C3-auto-merge, and C5 merge never promotes`,
        );
      }
    }
  }

  const ratifiedPromoted = (cell) => binding.promotion_state?.[cell]?.state === "promoted";
  for (const [workClass, cell] of Object.entries(AUTO_MERGE_PROMOTION_CELL)) {
    if (binding.merge_policy?.[workClass] === "auto" && !ratifiedPromoted(cell)) {
      findings.push(
        `merge_policy.${workClass}: "auto" without a ratified promotion_state.${cell} entry (state "promoted") — promotion is a human-ratified knob flip recorded on the governance surface; an earned value without its ratification record bypasses the promotion discipline`,
      );
    }
  }
  const aiReview = binding.verification_blocking?.["ai-review"];
  if (isPlainObject(aiReview) && aiReview.C3 === "blocking" && !ratifiedPromoted("C3-ai-review-blocking")) {
    findings.push(
      'verification_blocking.ai-review.C3: "blocking" without a ratified promotion_state.C3-ai-review-blocking entry (state "promoted") — advisory -> blocking is the earned promotion flip for this cell; an earned value without its ratification record bypasses the promotion discipline',
    );
  }

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

  if (
    isPlainObject(binding.merge_policy) &&
    isPlainObject(binding.verification_blocking)
  ) {
    for (const workClass of WORK_CLASSES) {
      if (binding.merge_policy[workClass] !== "auto") continue;
      for (const layer of LAYERS) {
        const perClass = binding.verification_blocking[layer];
        if (!isPlainObject(perClass) || perClass[workClass] !== "advisory") continue;
        findings.push(
          `merge_policy.${workClass}: "auto" with verification_blocking.${layer}.${workClass} "advisory" — an automatic transition requires unanimous agreement among every checker the class declares, and an advisory layer records a checker's dissent without withholding the transition; set verification_blocking.${layer}.${workClass} to "blocking" (ratifying its promotion_state cell where the cell is promotable) or bind merge_policy.${workClass} to "human"`,
        );
      }
      if (!isPlainObject(aiReview) || aiReview[workClass] !== "not-required") continue;
      const topology = binding.verification_topology?.[workClass];
      if (!isPlainObject(topology) || !Array.isArray(topology.roles)) continue;
      const declaredModelCheckers = topology.roles
        .filter(
          (role) =>
            isPlainObject(role) &&
            CHECKER_TYPED_ROLES.has(role.role) &&
            isNonEmptyString(role.name) &&
            !isNonEmptyString(role.scanner_class),
        )
        .map((role) => JSON.stringify(role.name));
      if (declaredModelCheckers.length === 0) continue;
      findings.push(
        `verification_topology.${workClass}.roles: model-adjudicated checkers [${declaredModelCheckers.join(", ")}] declared while merge_policy.${workClass} is "auto" and verification_blocking.ai-review.${workClass} is "not-required" — the layer those checkers judge in never runs, so their agreement can never be obtained and unanimity over them is vacuous while the merge proceeds automatically; set verification_blocking.ai-review.${workClass} to "blocking", drop the model-adjudicated roles and let the class's deterministic slot seat its floor, or bind merge_policy.${workClass} to "human"`,
      );
    }
  }

  if (isPlainObject(binding.verification_topology)) {
    for (const workClass of WORK_CLASSES) {
      const topology = binding.verification_topology[workClass];
      if (!isPlainObject(topology)) continue;
      checkTopologySemantics(topology, workClass);
    }
  }


  if (isPlainObject(binding.admission) && Array.isArray(binding.admission.rules)) {
    checkAdmissionSemantics(binding.admission.rules, binding.admission.classification);
  }
  return verdicts;
}

function checkAdmissionSemantics(rules, classification) {
  const validRules = rules.filter(
    (rule) =>
      isPlainObject(rule) &&
      RULE_SIGNAL_CLASSES.includes(rule.signal_class) &&
      RULE_PROVENANCES.includes(rule.provenance) &&
      RULE_WORK_CLASSES.includes(rule.work_class) &&
      DISPOSITIONS.includes(rule.disposition),
  );

  validRules.forEach((rule) => {
    const index = rules.indexOf(rule);
    const covered = rule.work_class === "*" ? WORK_CLASSES : [rule.work_class];
    const weakened = covered.filter(
      (workClass) => PERMISSIVENESS[rule.disposition] > PERMISSIVENESS[ADMISSION_DEFAULTS[workClass]],
    );
    for (const [surface, disposition] of Object.entries(ADMISSION_GATED_SURFACES)) {
      const surfaceClassified = isPlainObject(classification) && Object.hasOwn(classification, surface);
      const matchesSurface =
        rule.signal_class === surface ||
        (rule.signal_class === "*" && (rule.work_class === "*" || surfaceClassified));
      if (matchesSurface && PERMISSIVENESS[rule.disposition] > PERMISSIVENESS[disposition]) {
        weakened.push(surface);
      }
    }
    if (weakened.length > 0 && !isNonEmptyString(rule.override_justification)) {
      findings.push(
        `admission.rules[${index}]: disposition ${JSON.stringify(rule.disposition)} is more permissive than the shipped default for ${weakened.join(", ")} — invalid without override_justification`,
      );
    }
  });

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

function topologyConstraintTargets(entry, constraint) {
  const value = entry[constraint];
  if (typeof value === "string") return isNonEmptyString(value) ? [value] : [];
  if (Array.isArray(value)) return value.filter(isNonEmptyString);
  return [];
}

function checkTopologySemantics(topology, workClass) {
  const where = `verification_topology.${workClass}`;
  const floor = TOPOLOGY_FLOORS[workClass];
  for (const knob of ["min_checkers", "min_model_checkers"]) {
    if (Number.isInteger(topology[knob]) && topology[knob] < floor[knob]) {
      findings.push(
        `${where}.${knob}: ${topology[knob]} weakens the shipped floor ${floor[knob]} — floors may be tightened, never weakened (override_justification applies to admission rules only)`,
      );
    }
  }
  if (topology.cross_vendor_required === false && floor.cross_vendor_required) {
    findings.push(
      `${where}.cross_vendor_required: false weakens the shipped floor true — floors may be tightened, never weakened (override_justification applies to admission rules only)`,
    );
  }
  if (!Array.isArray(topology.roles)) return;
  const entries = topology.roles.filter((entry) => isPlainObject(entry) && isNonEmptyString(entry.name));
  const declared = new Map();
  for (const entry of entries) {
    if (declared.has(entry.name)) {
      findings.push(
        `${where}.roles: ${JSON.stringify(entry.name)} is declared more than once — role names are the class-local identity relational constraints resolve against, so a repeated name declares one role while presenting as several`,
      );
    } else {
      declared.set(entry.name, entry);
    }
  }
  for (const entry of entries) {
    for (const constraint of RELATIONAL_CONSTRAINTS) {
      if (!Object.hasOwn(entry, constraint)) continue;
      for (const target of topologyConstraintTargets(entry, constraint)) {
        if (target === entry.name) {
          findings.push(
            `${where}.roles[${JSON.stringify(entry.name)}].${constraint}: names its own role — a role cannot be distinct from itself, so a self-reference can never be evaluated`,
          );
        } else if (!declared.has(target)) {
          findings.push(
            `${where}.roles[${JSON.stringify(entry.name)}].${constraint}: ${JSON.stringify(target)} names a role this class does not declare — a relational constraint resolves against its own class's role list, so an undeclared reference can never be evaluated; invalid, not ignored`,
          );
        }
      }
    }
  }
  const generatorNames = new Set(
    [...declared.values()].filter((entry) => entry.role === "generator").map((entry) => entry.name),
  );
  if (generatorNames.size === 0) {
    for (const entry of declared.values()) {
      if (entry.role !== "cross_vendor_checker") continue;
      findings.push(
        `${where}.roles[${JSON.stringify(entry.name)}]: role cross_vendor_checker with no generator declared in this class — the role is a checker constrained to a different vendor from the GENERATOR, so without a declared generator its defining constraint has no referent and can never be evaluated; declare the generator role, or use role checker`,
      );
    }
  }
  const checkers = [...declared.values()].filter((entry) => CHECKER_TYPED_ROLES.has(entry.role));
  const deterministic = checkers.filter((entry) => isNonEmptyString(entry.scanner_class));
  const modelCheckers = checkers.filter((entry) => !isNonEmptyString(entry.scanner_class));
  for (const entry of deterministic) {
    if (entry.role !== "checker") {
      findings.push(
        `${where}.roles[${JSON.stringify(entry.name)}]: scanner_class on role ${entry.role} — scanner_class marks a DETERMINISTIC slot, which has no vendor identity, so it is legal on role checker only`,
      );
    }
    for (const key of [...RELATIONAL_CONSTRAINTS, "min_context_tokens", "requires_modality", "requires_feature"]) {
      if (!Object.hasOwn(entry, key)) continue;
      findings.push(
        `${where}.roles[${JSON.stringify(entry.name)}].${key}: declared on a deterministic slot — a deterministic layer has no model or vendor identity, so this constraint can never be evaluated against it; drop it, or drop scanner_class to declare a model-adjudicated slot`,
      );
    }
  }
  const scannerClasses = new Map();
  for (const entry of deterministic) {
    const seen = scannerClasses.get(entry.scanner_class);
    if (seen !== undefined) {
      findings.push(
        `${where}.roles: deterministic slots ${JSON.stringify(seen)} and ${JSON.stringify(entry.name)} share scanner_class ${JSON.stringify(entry.scanner_class)} — two slots that resolve identically declare ONE checker, so the pair counts once toward min_checkers`,
      );
    } else {
      scannerClasses.set(entry.scanner_class, entry.name);
    }
  }
  for (const entry of modelCheckers) {
    if (generatorNames.size === 0) continue;
    const targets = RELATIONAL_CONSTRAINTS.flatMap((constraint) => topologyConstraintTargets(entry, constraint));
    if (targets.some((target) => generatorNames.has(target))) continue;
    findings.push(
      `${where}.roles[${JSON.stringify(entry.name)}]: model-adjudicated checker with no distinctness relation to the generator — a model judging its own output measures its own preference rather than the artifact, and an undeclared constraint is unestablished, not generous; declare distinct_model_from against the generator role`,
    );
  }
  const minModelCheckers = Number.isInteger(topology.min_model_checkers)
    ? topology.min_model_checkers
    : floor.min_model_checkers;
  if (modelCheckers.length < minModelCheckers) {
    findings.push(
      `${where}.roles: declares ${modelCheckers.length} model-adjudicated checker slot${modelCheckers.length === 1 ? "" : "s"} against min_model_checkers ${minModelCheckers} — a total count cannot express which KIND of coverage is owed, so a class meeting min_checkers with deterministic slots alone never faces the model judge its verification cell requires`,
    );
  }
  const minCheckers = Number.isInteger(topology.min_checkers) ? topology.min_checkers : floor.min_checkers;
  if (checkers.length < minCheckers) {
    findings.push(
      `${where}.roles: declares ${checkers.length} distinct checker role${checkers.length === 1 ? "" : "s"} against min_checkers ${minCheckers} — min_checkers counts DISTINCT checker roles drawn from the declared role list, so a list that cannot seat the count makes the topology unsatisfiable`,
    );
  }
  const relatedBy = (a, b, constraints) =>
    constraints.some(
      (constraint) =>
        topologyConstraintTargets(a, constraint).includes(b.name) ||
        topologyConstraintTargets(b, constraint).includes(a.name),
    );
  for (let i = 0; i < modelCheckers.length; i += 1) {
    for (let j = i + 1; j < modelCheckers.length; j += 1) {
      if (!relatedBy(modelCheckers[i], modelCheckers[j], RELATIONAL_CONSTRAINTS)) {
        findings.push(
          `${where}.roles: checker roles ${JSON.stringify(modelCheckers[i].name)} and ${JSON.stringify(modelCheckers[j].name)} carry no distinct_model_from/distinct_vendor_from relation between them — nothing keeps both from resolving to one instance, and N runs of a single instance count as ONE checker toward min_checkers; constrain the pair distinct in at least one direction`,
        );
      }
    }
  }
  if (topology.cross_vendor_required === true) {
    if (modelCheckers.length < 2) {
      findings.push(
        `${where}: cross_vendor_required true with ${modelCheckers.length} model-adjudicated checker slot${modelCheckers.length === 1 ? "" : "s"} — the requirement is vendor disjointness AMONG the model slots, so fewer than two makes it vacuous rather than trivially conforming; declare at least two model-adjudicated checkers or bind cross_vendor_required false where the floor allows`,
      );
    }
    const seated = checkers.some(
      (entry) =>
        entry.role === "cross_vendor_checker" ||
        topologyConstraintTargets(entry, "distinct_vendor_from").some((target) => generatorNames.has(target)),
    );
    if (!seated) {
      findings.push(
        `${where}: cross_vendor_required true but no declared checker is vendor-distinct from the generator — declare a cross_vendor_checker role, or constrain a checker distinct_vendor_from a declared generator role; a requirement the role list cannot seat is decorative, not policy`,
      );
    }
    for (let i = 0; i < modelCheckers.length; i += 1) {
      for (let j = i + 1; j < modelCheckers.length; j += 1) {
        const a = modelCheckers[i];
        const b = modelCheckers[j];
        if (!relatedBy(a, b, ["distinct_vendor_from"])) {
          findings.push(
            `${where}.roles: model-adjudicated checkers ${JSON.stringify(a.name)} and ${JSON.stringify(b.name)} carry no distinct_vendor_from relation between them while cross_vendor_required is true — vendor disjointness is required AMONG the model slots, not only against the generator, because same-vendor checkers share failure modes and their agreement is weaker evidence than its count suggests`,
          );
        }
      }
    }
  }
}


function resolveEffectivePromotion(binding, evidencePath) {
  const lines = [];
  let events = null;
  try {
    const parsed = JSON.parse(readFileSync(evidencePath === "-" ? 0 : evidencePath, "utf8"));
    if (!Array.isArray(parsed)) throw new Error("evidence document must be a JSON array of events");
    events = parsed;
  } catch (error) {
    lines.push(
      `evidence source ${evidencePath} unavailable (${error.message}) — fail-closed: every cell resolves to effective state unpromoted`,
    );
  }

  const promotionState = isPlainObject(binding.promotion_state) ? binding.promotion_state : {};

  const resolved = new Map();
  for (const [cell, entry] of Object.entries(promotionState)) {
    if (!isPlainObject(entry)) continue;
    const bound = entry.state;
    if (events === null) {
      resolved.set(cell, {
        bound,
        effective: "unpromoted",
        line: `${cell}: bound ${bound} -> effective unpromoted (evidence unavailable, fail-closed)`,
      });
      continue;
    }
    const dependencyCells = PROMOTION_DEPENDENCIES[cell] ?? [];
    const contrary = events.filter(
      (event) =>
        isPlainObject(event) &&
        (event.cell === cell || dependencyCells.includes(event.cell)) &&
        CONTRARY_EVIDENCE_EVENTS.has(event.event),
    );
    const ratifiedAt = parseIsoStrict(entry.ratified_at);
    const inEpoch = [];
    const inEpochTimes = [];
    const preEpoch = [];
    for (const event of contrary) {
      const source = event.cell === cell ? "" : `${event.cell} (prerequisite cell) `;
      const at = parseIsoStrict(event.at);
      const discovered = event.discovered === undefined ? at : parseIsoStrict(event.discovered);
      const found = event.discovered === undefined ? "" : ` (discovered ${event.discovered})`;
      if (Number.isNaN(at)) {
        inEpoch.push(`${source}${event.event} with non-ISO or unparsable at ${JSON.stringify(event.at)} — cannot be assigned to an epoch, treated as contrary (fail-closed)`);
        inEpochTimes.push(at);
      } else if (Number.isNaN(ratifiedAt) || Number.isNaN(discovered) || Math.max(at, discovered) >= ratifiedAt) {
        inEpoch.push(`${source}${event.event} at ${event.at}${found}`);
        inEpochTimes.push(Number.isNaN(discovered) ? discovered : Math.max(at, discovered));
      } else {
        preEpoch.push(`${source}${event.event} at ${event.at}${found}`);
      }
    }
    const reearn =
      inEpoch.length === 0
        ? undefined
        : events.find((event) => {
            if (!isPlainObject(event) || event.cell !== cell || event.event !== REEARN_EVENT) return false;
            const since = parseIsoStrict(event.since);
            const at = parseIsoStrict(event.at);
            return (
              !Number.isNaN(since) &&
              !Number.isNaN(at) &&
              at >= since &&
              inEpochTimes.every((t) => !Number.isNaN(t) && since >= t)
            );
          });
    if (bound === "promoted" && reearn) {
      resolved.set(cell, {
        bound,
        effective: "promoted",
        line: `${cell}: bound promoted -> effective promoted (re-earned at ${reearn.at} over evidence since ${reearn.since}, at or after every in-epoch contrary event: ${inEpoch.join("; ")})`,
      });
    } else if (bound === "promoted" && inEpoch.length > 0) {
      resolved.set(cell, {
        bound,
        effective: "unpromoted",
        demotedReason: `contrary evidence (${inEpoch.join("; ")})`,
        line: `${cell}: bound promoted -> effective unpromoted — ceiling lowered by contrary evidence (${inEpoch.join("; ")}) WITHOUT modifying the binding; demotion files an escalation item on route ${JSON.stringify(binding.escalation_routes?.demotion)}, and the cell stays unpromoted until a re-earned event shows its predicate met again over evidence counted from after the latest of them`,
      });
    } else {
      let line = `${cell}: bound ${bound} -> effective ${bound}`;
      if (preEpoch.length > 0) {
        line += ` (${preEpoch.length} pre-epoch contrary event(s) ignored: ${preEpoch.join("; ")} — predate ratified_at ${entry.ratified_at}, whose ratification closed their epoch)`;
      }
      resolved.set(cell, { bound, effective: bound === "promoted" ? "promoted" : "unpromoted", line });
    }
  }

  for (const [cell, record] of resolved) {
    if (record.effective !== "promoted") continue;
    const failed = (PROMOTION_DEPENDENCIES[cell] ?? []).filter((dep) => resolved.get(dep)?.effective !== "promoted");
    if (failed.length === 0) continue;
    const detail = failed.map((dep) => {
      const depRecord = resolved.get(dep);
      if (!depRecord) return `${dep}: no promotion_state entry`;
      if (depRecord.demotedReason) return `${dep}: demoted by ${depRecord.demotedReason}`;
      return `${dep}: bound ${depRecord.bound}`;
    });
    record.effective = "unpromoted";
    record.line = `${cell}: bound promoted -> effective unpromoted — prerequisite cell(s) not effective-promoted (${detail.join("; ")}); the predicate this cell was earned on requires its prerequisite promoted, so the dependent promotion lowers with it`;
  }
  for (const record of resolved.values()) lines.push(record.line);
  if (Object.keys(promotionState).length === 0) {
    lines.push("no promotion_state entries — every promotable cell is at its unpromoted default");
  }
  return lines;
}


const args = process.argv.slice(2);
const options = {
  "--evidence": null,
  "--probe-evidence-root": null,
  "--egress-hosts": null,
  "--credential-roots": null,
};
let bindingPath = null;
for (let i = 0; i < args.length; i += 1) {
  if (Object.hasOwn(options, args[i])) {
    options[args[i]] = args[i + 1];
    i += 1;
  } else if (bindingPath === null) {
    bindingPath = args[i];
  } else {
    bindingPath = undefined;
    break;
  }
}
const {
  "--evidence": evidencePath,
  "--probe-evidence-root": probeRoot,
  "--egress-hosts": egressHostsArg,
  "--credential-roots": credentialRootsArg,
} = options;
if (
  !isNonEmptyString(bindingPath) ||
  Object.values(options).some((value) => value !== null && !isNonEmptyString(value))
) {
  console.error(
    "usage: check-security-binding.mjs <binding.json> [--evidence <evidence.json>] [--probe-evidence-root <dir>] [--egress-hosts <host,host,...>] [--credential-roots <path,path,...>]",
  );
  process.exit(2);
}
const egressAllowList =
  egressHostsArg === null
    ? null
    : egressHostsArg.split(",").map((host) => bareHost(host.trim())).filter((host) => host.length > 0);
const credentialRootsParsed =
  credentialRootsArg?.split(",").map((root) => root.trim()).filter((root) => root.length > 0) ?? [];
const credentialRoots = credentialRootsParsed.length > 0 ? credentialRootsParsed : null;

let raw;
try {
  raw = readFileSync(bindingPath, "utf8");
} catch (error) {
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
  if (isPlainObject(binding)) verdicts = checkSemantics(binding, probeRoot, egressAllowList, credentialRoots);
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
