#!/usr/bin/env node

// Security-binding check for the guardrail contract: validates a security
// binding document against the contract-owned schema shape
// (schemas/guardrails-security-binding.schema.json — the structural rules are
// mirrored here, dependency-free) plus the semantic rules the schema cannot
// express: matrix merge caps, runtime-marker attestability and pairwise
// joint-satisfiability, per-surface class-aware isolation verdicts, promotion
// discipline, and admission floors/precedence.
//
// Usage: node check-security-binding.mjs <binding.json> [--evidence <evidence.json>] [--probe-evidence-root <dir>] [--egress-hosts <host,host,...>]
// Exit 0 = valid (verdicts printed); 1 = findings; 2 = usage/environment error.
//
// --egress-hosts is the configured/trusted probe-target seam: when supplied,
// a transcript's egress host must be one of the listed hosts. Without it the
// checker falls back to shape rules plus deny lists (local/private/encoded
// targets, special-use TLDs) — a static checker cannot resolve DNS, so orgs
// close the residual by passing their configured target here.
//
// Probe verification: an L2/L3 isolation level counts toward eligibility only
// when its probe_evidence ref resolves — relative to --probe-evidence-root,
// which is REQUIRED for verification: the root is the protected evidence
// surface outside the agent's write reach, and without it a ref would
// resolve as written, letting an agent-writable transcript swapped after
// ratification supply the claimed proof, so every L2/L3 entry is unproven
// (deliberately not a usage error — schema-only validation still runs) — to
// a transcript proving the boundary per the isolation-probe template's
// capture shape: an arbitrary string must never enable autonomous dispatch.
// Under autonomous-enabled an unverifiable entry is UNPROVEN: a finding, and
// the level is excluded from eligibility (fail-closed). Under
// human-gated-only there is no autonomous dispatch to protect, so unproven
// evidence is reported in the verdicts, not a finding.
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

import { readFileSync, realpathSync } from "node:fs";
import { isAbsolute, relative, resolve, sep } from "node:path";
import process from "node:process";

const WORK_CLASSES = ["C1", "C2", "C3", "C4", "C5"];
const LEVEL_TOKEN = /^L[0-3]$/;
// Routine identity: <class-token> or <class-token>/<posture-token> — the
// posture-qualified form is how a multi-posture routine class binds each
// posture to its own class and emitting surface.
const ROUTINE_IDENTITY = /^[a-z][a-z0-9-]*(\/[a-z][a-z0-9-]*)?$/;
// Schemes that can never anchor a durable platform run-permalink namespace —
// the same non-durable set the signal-envelope checker rejects for raw links
// (a data:/javascript:/http: prefix could never match a durable permalink).
const NON_DURABLE_PREFIX_SCHEMES = new Set(["data", "javascript", "blob", "about", "http", "mailto", "tel", "vbscript"]);
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
// The isolation-probe template's substrate-class tokens. The kernel-separated
// pair mirrors the isolation-ladder leaf's L3 substrate classes: a VM or
// microVM, and a hosted ephemeral executor surface.
const SUBSTRATE_CLASSES = new Set(["container", "os-sandbox", "vm-microvm", "hosted-ephemeral-executor"]);
const L3_SUBSTRATE_CLASSES = new Set(["vm-microvm", "hosted-ephemeral-executor"]);
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
// Recognized host-credential locations are EXACT full locations: the whole
// path must equal a well-known credential location, never merely end at a
// recognized basename somewhere under an accepted anchor. A failed read is
// credential evidence only when the path IS a well-known credential
// location in full — anchor + basename at arbitrary depth lets a probe pick
// a benign existing descendant (e.g. $HOME/scratch/credentials or
// /etc/example/credentials) whose outer existence check passes and whose
// inner read fails, producing an accepted proof while the real host
// credentials stay exposed. Substring matching is even weaker (it would
// accept "/definitely-not-a-host-credential" via "credentials"), and a
// non-secret sibling under a credential directory ($HOME/.ssh/known_hosts)
// or a directory marker ($HOME/.ssh, ambiguous read-tool semantics) proves
// nothing either — exactness excludes all of these by construction. Same
// no-config-source rationale as the egress-host check: the checker cannot
// know the org's probed credential paths, so any entry that is not exactly
// a recognized location is rejected rather than trusted. GnuPG has no
// static concrete secret file — its private keys live under
// private-keys-v1.d/ with arbitrary key-grip names — so it defers to the
// future configured allow-list, like org-named injected secrets
// (/run/secrets/<org-name> is an inventable name; /run/secrets/credentials
// is the one recognized concrete form, exactly at that depth).
// The isolation-probe template's "cloud metadata endpoint" example qualifies
// ONLY through the URL branch's known endpoints — a filesystem path segment
// named "metadata" is not credential evidence. The metadata IP there is a
// DELIBERATE asymmetry with the egress check, which DENIES 169.254.169.254
// (link-local proves no external egress): metadata IS the cloud credential
// source, and the two checks serve opposite goals.
// HOME_SECRET_RELATIVE_FORMS are the exact relative forms under a home
// anchor (a leading home env token, or the fixed /root home);
// FIXED_SECRET_PATHS are whole fixed system locations. Segment arrays,
// matched exactly and in full.
const HOME_SECRET_RELATIVE_FORMS = [
  [".ssh", "id_rsa"],
  [".ssh", "id_dsa"],
  [".ssh", "id_ecdsa"],
  [".ssh", "id_ed25519"],
  [".netrc"],
  [".git-credentials"],
  [".aws", "credentials"],
  [".kube", "config"],
  [".docker", "config.json"],
  [".config", "gh", "hosts.yml"],
];
const FIXED_SECRET_PATHS = [
  ["etc", "ssh", "ssh_host_rsa_key"],
  ["etc", "ssh", "ssh_host_dsa_key"],
  ["etc", "ssh", "ssh_host_ecdsa_key"],
  ["etc", "ssh", "ssh_host_ed25519_key"],
  ["run", "secrets", "credentials"],
];
// Well-known credential variable names for the whole-entry env-token form
// (compared against the lowercased entry).
const CREDENTIAL_ENV_VARS = new Set(["github_token", "gh_token"]);
// A recognized location counts only when the path is REAL BY CONSTRUCTION —
// its ROOT names a location every probing host actually has: a leading OS
// home env token ($HOME / %USERPROFILE%, expanded in-shell on the probing
// host to the real home) or the fixed /root home for the home-anchored
// forms; the fixed system locations carry their own roots in full. A
// literal multi-user or mount base ("/home/<user>",
// "/users/<user>", "/host-home") is free-form inventable — the named user or
// mount need not exist on any host, and a failing read of a path that need
// not exist proves nothing while real host credentials stay readable — so it
// never anchors; org-specific mounts belong in the future configured
// allow-list. The anchor must be the FIRST segment: an env token behind an
// arbitrary prefix ("/mnt/<mount>/$HOME/...") inherits the prefix's
// inventability. A recognized name under an ephemeral base like /tmp is
// planted evidence, not the host's credential store. A literal
// "/home/<user>" IS accepted as a credentials_absent.host_expanded value —
// there the capture shape's recorded outer expansion step corroborates it;
// the inventability objection applies to UNCORROBORATED bare entries.
const EPHEMERAL_SEGMENTS = new Set(["tmp", "temp", "shm"]);
const isEnvToken = (segment) => /^\$[a-z_]+$/.test(segment) || /^%[a-z_]+%$/.test(segment);
const isHomeEnvToken = (segment) =>
  isEnvToken(segment) && ["home", "userprofile"].includes(segment.replace(/^[$%]/, "").replace(/%$/, ""));
// A route prefix matches on a SEGMENT boundary only: the pathname equals the
// prefix or continues with "/" immediately after it — a plain startsWith
// would accept e.g. "/metadata-not-a-credential" via "/metadata".
const hasRoutePrefix = (pathname, prefix) => pathname === prefix || pathname.startsWith(prefix + "/");

function isRecognizedCredentialEntry(entry) {
  const normalized = entry.toLowerCase().replaceAll("\\", "/");
  if (normalized.includes("://")) {
    let url;
    try {
      url = new URL(normalized);
    } catch {
      return false;
    }
    // KNOWN cloud metadata endpoints only, and only their known credential
    // ROUTES — an arbitrary path on the metadata host proves nothing, a
    // "metadata" label or path segment on an arbitrary host proves nothing,
    // and the bare single-label alias is search-domain-dependent; org-specific
    // endpoints belong in a future configured allow-list. (The whole entry is
    // lowercased before parsing, so the prefixes and protocol compare
    // lowercase.) The transport must be the service's own: metadata credential
    // services speak plain HTTP on the default port, so a file:// read or an
    // odd-port probe can fail for non-boundary reasons (unsupported local
    // scheme, closed port) while the real service stays reachable — such an
    // entry proves nothing. The WHATWG parser normalizes an explicit default
    // ":80" away, so an empty port means the default.
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
  const segments = normalized.split("/").filter((segment) => segment.length > 0);
  // A whole-entry env-style token naming a credential variable qualifies on
  // its own (e.g. $GITHUB_TOKEN — an injected token env var per the
  // template's marked examples), but only WELL-KNOWN credential variable
  // names are recognizable statically: an invented *_token name proves
  // nothing; org-specific names belong to the future configured allow-list.
  if (segments.length === 1 && isEnvToken(segments[0])) {
    const bare = segments[0].replace(/^[$%]/, "").replace(/%$/, "");
    return CREDENTIAL_ENV_VARS.has(bare);
  }
  // A dot segment resolves the path elsewhere than its anchor claims
  // ("/root/../var/empty/.ssh" probes /var/empty/.ssh while "root" anchors),
  // so the anchor cannot be trusted — rejected outright rather than
  // canonicalized: resolving traversal invites its own edge cases, and a
  // probe recipe has no reason to record a non-canonical path.
  if (segments.some((segment) => segment === "." || segment === "..")) return false;
  // A UNC form ("//server/..." — a leading "\\" normalizes to it above)
  // invents its server: "//etc/credentials" names a share on a server called
  // "etc", not the host's /etc, so no UNC path names a by-construction-real
  // host location; org file-share credential roots belong to the future
  // configured allow-list.
  if (normalized.startsWith("//")) return false;
  // A relative path resolves against an arbitrary cwd and says nothing about
  // the host credential store — only a rooted form names a host location:
  // POSIX-absolute or a leading home env token. A drive-letter root is
  // deliberately not rooted enough: the only by-construction Windows home
  // form is %USERPROFILE%, and a literal "c:/users/<user>" invents its user.
  if (!(normalized.startsWith("/") || isHomeEnvToken(segments[0]))) {
    return false;
  }
  if (segments.some((segment) => EPHEMERAL_SEGMENTS.has(segment))) return false;
  const segmentsEqual = (a, b) => a.length === b.length && a.every((segment, index) => segment === b[index]);
  if (isHomeEnvToken(segments[0]) || segments[0] === "root") {
    const relativeForm = segments.slice(1);
    return HOME_SECRET_RELATIVE_FORMS.some((form) => segmentsEqual(form, relativeForm));
  }
  return FIXED_SECRET_PATHS.some((form) => segmentsEqual(form, segments));
}

// Per-entry validation of the recorded host-side expansion. The credential
// probe runs INSIDE the boundary with no host environment, so an in-shell
// home token expands to the boundary's OWN home (e.g. /root in a container)
// and its failing read tests nothing about the host store — the recipe
// expands the token OUTSIDE the boundary, passes the concrete path in as a
// literal, and records that expansion. A concrete entry (fixed system path,
// metadata URL, or whole-entry credential env token) needs no expansion, so
// host_expanded must repeat it verbatim — anything else means the capture
// step rewrote a path it had no reason to touch. A home-env-token entry's
// expansion must itself plausibly be the host home path: rooted
// (POSIX-absolute or drive-letter-absolute), not a UNC form, free of
// ephemeral segments, and TAIL-CONSISTENT with the entry — everything after
// the token must be the expansion's trailing suffix ($HOME/.ssh pairs with
// /home/runner/.ssh, never /home/runner/.gnupg). Normalization matches the
// entry handling (lowercase, backslashes to slashes). Returns null when
// valid, else the reason.
function credentialExpansionProblem(entry, expanded) {
  const normalizedEntry = entry.toLowerCase().replaceAll("\\", "/");
  const normalizedExpanded = expanded.toLowerCase().replaceAll("\\", "/");
  const segments = normalizedEntry.split("/").filter((segment) => segment.length > 0);
  const homeAnchored =
    !normalizedEntry.includes("://") && segments.length > 1 && isHomeEnvToken(segments[0]);
  if (!homeAnchored) {
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
  // Same dot-segment rejection as the entry side: a traversal in the
  // expansion resolves elsewhere than the recorded path claims.
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
const ISO_DATE_TIME = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/;
function parseIsoStrict(value) {
  const match = typeof value === "string" ? ISO_DATE_TIME.exec(value) : null;
  if (match === null) return Number.NaN;
  const [, year, month, day, hour, minute, second, fraction, offset] = match;
  // Fractional seconds are bounded to millisecond precision (max 3 digits) by
  // the grammar above, then zero-padded to exactly 3. The epoch comparison is
  // integer-millisecond, so accepting finer precision would silently collapse
  // distinct instants — ".5001Z" and ".5009Z" both become 500 ms — and could
  // misorder a promotion epoch, demoting a legitimately re-earned promotion. A
  // sub-millisecond fraction fails the regex and is rejected, never truncated.
  const ms = Number((fraction ?? "").padEnd(3, "0"));
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
          checkAllowedKeys(entry, ["substrate", "substrate_class", "probe_evidence", "runtime_markers"], where);
          if (!isNonEmptyString(entry.substrate)) {
            findings.push(`${where}.substrate: missing or empty — the bound substrate instance id is required`);
          }
          // The substrate CLASS is the HUMAN-RATIFIED binding-side assertion
          // the eligibility decision keys off, living on the agent-unwritable
          // surface — never the transcript's recorded class, which is capture
          // evidence an executing agent could doctor. The transcript-side
          // class checks in verifyProbeTranscript stay as capture-shape
          // validation; this is the governance-surface assertion the capture
          // is matched against.
          if (!SUBSTRATE_CLASSES.has(entry.substrate_class)) {
            findings.push(
              `${where}.substrate_class: ${JSON.stringify(entry.substrate_class)} — the human-ratified substrate-class assertion is required on every level binding, one of ${[...SUBSTRATE_CLASSES].join(" | ")}`,
            );
          } else if (level === "L3" && !L3_SUBSTRATE_CLASSES.has(entry.substrate_class)) {
            // Level/class coherence is judged on the RATIFIED class, not the
            // transcript's: an L3 entry whose ratified class is not
            // kernel-separated is an INVALID BINDING — the ratified assertion
            // itself is wrong, not merely the evidence unproven — because
            // container and os-sandbox boundaries never reach the ladder's
            // kernel-separated L3 floor, whatever any capture claims.
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

// The TEMPORAL home is keyed by ROUTINE IDENTITY, and every entry must be the
// surface-bound object form: the scheduled workflow that stamps a routine
// identity is agent-writable in adopting repos, so the identity alone is an
// unprotected selector — a bare class here would let a swapped selector
// resolve high-risk scheduled work through a benign class. Only the
// identity-to-surface association ratified on this agent-unwritable surface
// lets admission stamp a class; anything less fails closed. Two anchors pin
// the producing schedule together, because a run-permalink namespace may be
// repo-scoped and SHARED across every schedule on the platform: the
// run_link_prefix pins the platform-and-repository namespace (a relative or
// non-durable prefix could never match a platform-assigned permalink), while
// the producer_identity — the workflow/unit reference the platform injects
// into the authenticated run context — pins WHICH schedule within that shared
// namespace produced the run. Prefixes may therefore overlap or coincide
// across entries (one shared namespace is the norm on repo-scoped platforms);
// what must stay unique is the producer_identity, since two routine
// identities sharing one producer cannot be distinguished at admission. The
// other classification homes keep their bare-enum entries: their markers
// arrive on attested event surfaces, not through an agent-writable selector.
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
        // Not an absolute URI — rejected below.
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
  const c = Math.floor(addr / 256) % 256;
  return (
    a === 0 ||
    a === 127 ||
    a === 10 ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 169 && b === 254) ||
    // Non-global space that can never demonstrate public egress (IANA IPv4
    // special-purpose registry, "not globally reachable"): IETF protocol
    // assignments (192.0.0/24), TEST-NET-1/2/3, benchmarking (198.18/15),
    // CGNAT (100.64/10), multicast (224/4), reserved (240/4), and 6to4 relay
    // anycast (192.88.99/24, deprecated per RFC 7526 and not reliably
    // globally routed). Registry entries flagged globally reachable (AS112
    // 192.175.48/24 and 192.31.196/24, AMT 192.52.193/24) stay allowed.
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

// Expand an IPv6 literal to its 8 zero-padded hextets, resolving "::"
// compression and an embedded dotted-quad tail; null where the literal is
// invalid. Classification must run on the EXPANDED form — prefix tests on
// the compressed text miss e.g. "0:0:0:0:0:0:0:1".
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
    // An invalid literal is not a valid probe target — reject outright.
    if (hextets === null) return true;
    if (hextets.slice(0, 5).every((hextet) => hextet === "0000") && hextets[5] === "ffff") {
      // v4-mapped: classify the embedded IPv4.
      return isDeniedV4(Number.parseInt(hextets[6], 16) * 65536 + Number.parseInt(hextets[7], 16));
    }
    if (hextets.slice(0, 6).every((hextet) => hextet === "0000")) {
      // ::/96 — unspecified (::), loopback (::1), and the whole deprecated
      // IPv4-compatible space (::0.0.0.0 through ::255.255.255.255, RFC 4291
      // §2.5.5.1): the embedded-dotted-quad form (e.g. "::127.0.0.1") writes
      // its address into hextets[6]/[7], so gating on those would let a
      // deprecated-space literal masquerade as external. None of ::/96 is a
      // meaningful external target.
      return true;
    }
    // 64:ff9b::/96 — well-known NAT64 prefix (RFC 6052): the IANA registry
    // flags it globally reachable, but RFC 6052 forbids embedding non-global
    // IPv4, so classify the embedded address like the v4-mapped branch above.
    if (hextets[0] === "0064" && hextets[1] === "ff9b" && hextets.slice(2, 6).every((hextet) => hextet === "0000")) {
      return isDeniedV4(Number.parseInt(hextets[6], 16) * 65536 + Number.parseInt(hextets[7], 16));
    }
    const first = Number.parseInt(hextets[0], 16);
    const second = Number.parseInt(hextets[1], 16);
    // 2001::/23 — IETF Protocol Assignments (IANA IPv6 special-purpose
    // registry, "not globally reachable"), EXCEPT the registry's
    // more-specific rows flagged globally reachable, which stay allowed:
    // PCP/TURN/DNS-SD-SRP anycast (2001:1::1 / ::2 / ::3), AMT
    // (2001:3::/32), AS112-v6 (2001:4:112::/48), ORCHIDv2 (2001:20::/28),
    // and DETs (2001:30::/28). Teredo (2001::/32) and deprecated ORCHID
    // (2001:10::/28) are registry "N/A" — tunneled/deprecated, not reliably
    // routed — and stay denied, the same posture as the IPv4 6to4 relay
    // anycast. (2001:db8::/32 documentation space sits OUTSIDE this /23 and
    // keeps its own test below.)
    if (hextets[0] === "2001" && second <= 0x01ff) {
      const reachableAnycast =
        second === 0x0001 &&
        hextets.slice(2, 7).every((hextet) => hextet === "0000") &&
        ["0001", "0002", "0003"].includes(hextets[7]);
      return !(
        reachableAnycast ||
        second === 0x0003 ||
        (second === 0x0004 && hextets[2] === "0112") ||
        (second >= 0x0020 && second <= 0x003f)
      );
    }
    // Remaining non-global space that can never demonstrate public egress
    // (IANA IPv6 special-purpose registry, "not globally reachable"):
    // fc00::/7 unique-local, fe80::/10 link-local, fec0::/10 site-local
    // (deprecated per RFC 3879, still non-global), ff00::/8 multicast,
    // discard-only (100::/64, RFC 6666), the dummy prefix (100:0:0:1::/64,
    // RFC 9780), local-use IPv4-IPv6 translation (64:ff9b:1::/48, RFC 8215),
    // 6to4 (2002::/16, deprecated per RFC 7526 — mirrors the IPv4
    // 192.88.99/24 posture), documentation (2001:db8::/32 and 3fff::/20,
    // RFC 9637), and SRv6 SIDs (5f00::/16, RFC 9602).
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
  // A numeric-shaped token that folds to no valid address is not a DNS name
  // either — reject rather than guess.
  if (name.split(".").every((label) => INET_PART.test(label))) return true;
  // A syntactically valid DNS hostname is required: every label 1-63 chars
  // of [a-z0-9-] with no hyphen at either edge, at most 253 chars total, and
  // at least two labels. A single-label name resolves through search domains
  // or mDNS, and a malformed name (empty labels from consecutive dots,
  // invalid chars, hyphen edges) resolves nowhere — neither is provably
  // external.
  const labels = name.split(".");
  const validLabel = (label) => /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(label);
  return name.length > 253 || labels.length < 2 || !labels.every(validLabel);
}

// A probe transcript proves an L2/L3 boundary only when it records both
// failed-inside assertions AND a networked outer context (a fully-offline
// outer context would deny egress on its own) — the capture shape of
// templates/isolation-probe.md; keep the two in sync. The transcript's own
// surface/level/substrate/substrate-class identity must match the binding
// entry it is cited from: a genuine transcript reused under a different
// surface, level, substrate, or substrate class proves a DIFFERENT boundary,
// not this one. Returns null when verified, else the reason the entry is
// unproven.
function verifyProbeTranscript(ref, probeRoot, surfaceId, level, substrate, substrateClass, egressAllowList) {
  // Evidence verifies ONLY against the configured protected root: without
  // --probe-evidence-root a ref resolves as written — including to an
  // agent-writable file swapped after the human ratified the binding — so no
  // root means no proof. Deliberately NOT a usage error (exit 2):
  // schema-only validation of a binding must keep working without it.
  if (probeRoot === null) {
    return `no --probe-evidence-root configured — probe evidence verifies only against a protected evidence root outside the agent's write reach; pass --probe-evidence-root <dir> naming the protected evidence surface the capture lives on`;
  }
  // Confine evidence to the configured root: --probe-evidence-root exists to
  // keep accepted captures on a protected evidence surface, so an absolute
  // ref or a "../" escape — which would let an agent-writable file outside
  // the root supply the claimed L2/L3 proof — is rejected before the read.
  // The lexical check gives the clean error message; the REAL-path check
  // below closes the symlink hole (a link inside the root pointing outside
  // defeats a purely lexical comparison). No committed fixture exercises
  // the symlink case — symlinks in git are unreliable on Windows — so it
  // is covered by a runtime test instead.
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
    // Nonexistent path: fall through so readFileSync below reports the
    // standard unreadable-transcript finding.
  }
  let path;
  if (realResolved !== null) {
    const realRoot = realpathSync(resolvedRoot);
    // win32 paths compare case-insensitively.
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
  // The transcript's substrate_class is CAPTURE EVIDENCE; the binding entry's
  // is the human-ratified assertion the eligibility decision keys off. A
  // mismatch means the capture proves a DIFFERENT substrate: relabeling a
  // container capture with a kernel-separated class fails closed right here,
  // and upgrading the ratified class itself takes a human change on the
  // agent-unwritable surface — exactly the trust boundary. The dispatch seam
  // attests the RUNNER identity via runtime_markers against platform-attested
  // context; the substrate class rides the ratified binding, never the
  // capture.
  if (transcript.substrate_class !== substrateClass) {
    return `transcript ${path} records substrate_class ${JSON.stringify(transcript.substrate_class)}, not this binding entry's ratified substrate_class ${JSON.stringify(substrateClass)} — the capture proves a different substrate than the human-ratified assertion`;
  }
  // Capture-shape validation of the transcript's own recorded class (the
  // ratified-class coherence is enforced binding-side in validateStructure):
  // the claimed level must be reachable by the substrate CLASS that ran the
  // probe — L3 is the ladder's kernel-separated floor, which container and
  // os-sandbox boundaries never provide, so a genuine L2 transcript relabeled
  // L3 must not unlock C5.
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
  // The probe contract is expected-FAILURE: every check asserts a NON-zero
  // exit inside the boundary, so a recorded exit_code of "0" contradicts the
  // outcome it sits next to — the transcript is internally inconsistent and
  // proves nothing. The credentials_absent codes are per-target and checked
  // alongside the path entries below.
  const nonzeroExit = (value) => typeof value === "string" && /^[1-9][0-9]*$/.test(value);
  // An assertion without its recorded target proves nothing about the
  // boundary: a failing run against no named host/path could be any failing
  // command, not the probe.
  const rawEgressHost = transcript.assertions.egress_denied.host;
  if (typeof rawEgressHost !== "string" || rawEgressHost.length === 0) {
    return `transcript ${path} records assertions.egress_denied.host ${JSON.stringify(rawEgressHost)} — a proven egress-denial requires the probed external host (non-empty; comma-separated entries when several targets were probed)`;
  }
  // The host value is a comma-separated list of probed targets (usually just
  // one), and every entry is validated INDEPENDENTLY below — classifying the
  // unsplit string would reject a genuine multi-target capture as one
  // invalid DNS name. Empty entries (leading/trailing/double commas) reject.
  const egressHosts = rawEgressHost.split(",").map((host) => host.trim());
  for (const host of egressHosts) {
    if (host.length === 0 || /\s/.test(host)) {
      return `transcript ${path} records assertions.egress_denied.host ${JSON.stringify(rawEgressHost)} — every comma-separated host entry must be non-empty with no whitespace`;
    }
  }
  // The inner exit codes pair with the probed hosts like the per-target
  // credential codes: one non-zero code per host — a single code cannot
  // prove denial toward every listed target.
  const rawEgressCodes = transcript.assertions.egress_denied.exit_code;
  const egressCodes = typeof rawEgressCodes === "string" ? rawEgressCodes.split(",").map((code) => code.trim()) : [];
  if (egressCodes.length !== egressHosts.length) {
    return `transcript ${path} records assertions.egress_denied.exit_code ${JSON.stringify(rawEgressCodes)} for ${egressHosts.length} probed host entr${egressHosts.length === 1 ? "y" : "ies"} — one recorded exit code per probed host is required, comma-separated and positionally paired with host: a single code cannot prove denial toward every listed target`;
  }
  for (const [index, code] of egressCodes.entries()) {
    if (!nonzeroExit(code)) {
      return `transcript ${path} records assertions.egress_denied.exit_code entry ${JSON.stringify(code)} for host ${JSON.stringify(egressHosts[index])} — a proven egress-denial requires a non-zero integer exit code string for every probed host`;
    }
  }
  for (const host of egressHosts) {
    // The transcript must record the BARE probed hostname or IP: URI and
    // host:port forms would route a loopback down the wrong classification
    // branch (e.g. "http://127.0.0.1"), so they are rejected outright rather
    // than parsed — one classification path, no parser disagreements. A
    // single colon can only be a port separator (hostnames and IPv4 have
    // none, IPv6 literals have at least two); a "]" not at the end is a
    // bracketed authority with a port suffix.
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
      if (!egressAllowList.includes(host.toLowerCase().replace(/\.$/, ""))) {
        return `transcript ${path} records assertions.egress_denied.host ${JSON.stringify(host)} — not in the configured egress-probe allow-list (--egress-hosts ${egressAllowList.join(",")})`;
      }
    } else {
      // RFC 2606/6761/6762/7686 special-use/reserved names never demonstrate
      // public egress (a DNS failure with open egress also "denies"). A
      // static checker cannot resolve DNS; the --egress-hosts allow-list
      // seam plus the live probe recipe close the residual.
      const bare = host.toLowerCase().replace(/\.$/, "");
      const specialTld = SPECIAL_USE_TLDS.find((tld) => bare === tld.slice(1) || bare.endsWith(tld));
      if (specialTld !== undefined) {
        return `transcript ${path} records assertions.egress_denied.host ${JSON.stringify(host)} — the special-use/reserved TLD ${JSON.stringify(specialTld)} can never demonstrate public egress; probe a resolvable public host, or pass the org's configured target via --egress-hosts`;
      }
    }
  }
  // A non-zero inner exit alone cannot tell a denied boundary from a target
  // that fails everywhere: an unregistered name NXDOMAINs with OPEN egress
  // too, so its failing fetch proves nothing. The probe therefore runs the
  // SAME fetch from the networked outer context and records its exit —
  // outer_exit_code, comma-separated and positionally paired with the probed
  // host(s) like the per-target credential codes — and only outer success
  // ("0") makes the inner failure evidence of the boundary. Required with or
  // without --egress-hosts: reachability evidence is orthogonal to which
  // targets are trusted.
  const rawOuterCodes = transcript.assertions.egress_denied.outer_exit_code;
  const outerCodes = typeof rawOuterCodes === "string" ? rawOuterCodes.split(",").map((code) => code.trim()) : [];
  if (outerCodes.length !== egressHosts.length) {
    return `transcript ${path} records assertions.egress_denied.outer_exit_code ${JSON.stringify(rawOuterCodes)} for ${egressHosts.length} probed host entr${egressHosts.length === 1 ? "y" : "ies"} — one recorded outer-context exit code per probed host is required, comma-separated and positionally paired with host: a failed inner probe proves an egress boundary only when the outer context proves the target was reachable`;
  }
  for (const [index, code] of outerCodes.entries()) {
    if (code !== "0") {
      return `transcript ${path} records assertions.egress_denied.outer_exit_code entry ${JSON.stringify(code)} for host ${JSON.stringify(egressHosts[index])} — the outer-context fetch of the same target must succeed (exit "0"): a failed inner probe proves an egress boundary only when the outer context proves the target was reachable`;
    }
  }
  if (!isNonEmptyString(transcript.assertions.credentials_absent.path)) {
    return `transcript ${path} records assertions.credentials_absent.path ${JSON.stringify(transcript.assertions.credentials_absent.path)} — a proven credential-absence requires the probed host-credential path`;
  }
  // The path value is a comma-separated list of probed locations, and
  // exit_code is the comma-separated list of their recorded exit codes,
  // positionally paired — one non-zero code per probed path: a single code
  // could come from a failing read of one listed path while another
  // (readable) path leaks. Every path entry must be recognizably a
  // host-credential location (case-insensitive, path-separator-agnostic,
  // matched per component).
  const credentialPaths = transcript.assertions.credentials_absent.path.split(",").map((entry) => entry.trim());
  const rawCredentialCodes = transcript.assertions.credentials_absent.exit_code;
  const credentialCodes =
    typeof rawCredentialCodes === "string" ? rawCredentialCodes.split(",").map((code) => code.trim()) : [];
  if (credentialCodes.length !== credentialPaths.length) {
    return `transcript ${path} records assertions.credentials_absent.exit_code ${JSON.stringify(rawCredentialCodes)} for ${credentialPaths.length} probed path entr${credentialPaths.length === 1 ? "y" : "ies"} — one recorded exit code per probed credential path is required, comma-separated and positionally paired with path: a single code cannot prove absence on every listed location`;
  }
  // host_expanded carries the recipe's outside-the-boundary expansion of each
  // probed path (validated per entry below): an in-shell home token expands
  // to the boundary's OWN home, so only a recorded host-side expansion names
  // the host credential location.
  const rawHostExpanded = transcript.assertions.credentials_absent.host_expanded;
  const hostExpanded =
    typeof rawHostExpanded === "string" ? rawHostExpanded.split(",").map((entry) => entry.trim()) : [];
  if (hostExpanded.length !== credentialPaths.length) {
    return `transcript ${path} records assertions.credentials_absent.host_expanded ${JSON.stringify(rawHostExpanded)} for ${credentialPaths.length} probed path entr${credentialPaths.length === 1 ? "y" : "ies"} — one recorded host-side expansion per probed credential path is required, comma-separated and positionally paired with path: an in-shell home token expands to the boundary's own home, so only a recorded host-side expansion names the host credential location`;
  }
  // For a metadata-URL entry the boundary claim is that the service is
  // UNREACHABLE from inside the boundary, and an HTTP-level error (missing
  // required header, wrong api-version) means the connection SUCCEEDED — a
  // reachable metadata service, no boundary. The transcript therefore
  // records HOW each probe failed: transport_outcome, comma-separated and
  // positionally paired with path — "connect-failed" (refused, timeout, no
  // route) required for URL entries, which also moots request protocol
  // completeness since no request semantics matter when the connection
  // itself must fail; "read-denied" for filesystem and env-token entries,
  // where no connection exists to fail.
  const rawTransportOutcomes = transcript.assertions.credentials_absent.transport_outcome;
  const transportOutcomes =
    typeof rawTransportOutcomes === "string" ? rawTransportOutcomes.split(",").map((outcome) => outcome.trim()) : [];
  if (transportOutcomes.length !== credentialPaths.length) {
    return `transcript ${path} records assertions.credentials_absent.transport_outcome ${JSON.stringify(rawTransportOutcomes)} for ${credentialPaths.length} probed path entr${credentialPaths.length === 1 ? "y" : "ies"} — one recorded transport outcome per probed credential path is required ("connect-failed" for a metadata URL, "read-denied" for a filesystem or env-token entry), comma-separated and positionally paired with path: without it a reachable metadata service's HTTP error is indistinguishable from a denied connection`;
  }
  // The exact symmetry of the egress outer_exit_code: a failing inner read
  // proves a boundary only when the target demonstrably EXISTS on the host —
  // inside a container or sandbox a fixed path like /root/.ssh names the
  // BOUNDARY's own (empty) root, and an empty inner path, an invented
  // target, or an absent service "fails" inside with no boundary at all. The
  // recipe captures the outer side per entry kind (path present/readable,
  // env var set and non-empty, metadata service reachable) and records its
  // exit as outer_exit_code, comma-separated and positionally paired with
  // path; every entry must be "0".
  const rawCredentialOuterCodes = transcript.assertions.credentials_absent.outer_exit_code;
  const credentialOuterCodes =
    typeof rawCredentialOuterCodes === "string" ? rawCredentialOuterCodes.split(",").map((code) => code.trim()) : [];
  if (credentialOuterCodes.length !== credentialPaths.length) {
    return `transcript ${path} records assertions.credentials_absent.outer_exit_code ${JSON.stringify(rawCredentialOuterCodes)} for ${credentialPaths.length} probed path entr${credentialPaths.length === 1 ? "y" : "ies"} — one recorded outer-context exit code per probed credential path is required, comma-separated and positionally paired with path: a failed inner read proves a credential boundary only when the outer context proves the target exists on the host`;
  }
  for (const [index, entry] of credentialPaths.entries()) {
    if (!isRecognizedCredentialEntry(entry)) {
      return `transcript ${path} records assertions.credentials_absent.path entry ${JSON.stringify(entry)} — not a recognized host-credential location; probe a well-known credential location IN FULL: a home-anchored secret file (a leading home env token like $HOME / %USERPROFILE%, or the fixed /root home, followed exactly by ${HOME_SECRET_RELATIVE_FORMS.map((form) => form.join("/")).join(", ")}) or a fixed system secret file (${FIXED_SECRET_PATHS.map((form) => `/${form.join("/")}`).join(", ")}) — never an arbitrary descendant of a credential anchor (a recognized basename at arbitrary depth lets a probe pick a benign existing file while real credentials stay exposed), never under an ephemeral base (tmp, temp, shm), and free of dot segments (".", ".." — a dot-segment path resolves elsewhere than its anchor claims, so the anchor cannot be trusted); a well-known credential env token like $GITHUB_TOKEN alone; or a known cloud metadata endpoint credential route`;
    }
    if (!nonzeroExit(credentialCodes[index])) {
      return `transcript ${path} records assertions.credentials_absent.exit_code entry ${JSON.stringify(credentialCodes[index])} for path ${JSON.stringify(entry)} — a proven credential-absence requires a non-zero integer exit code string for every probed path`;
    }
    const expansionProblem = credentialExpansionProblem(entry, hostExpanded[index]);
    if (expansionProblem !== null) {
      return `transcript ${path} records assertions.credentials_absent.host_expanded entry ${JSON.stringify(hostExpanded[index])} for path ${JSON.stringify(entry)} — ${expansionProblem}`;
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
  return null;
}

function checkSemantics(binding, probeRoot, egressAllowList) {
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
        ? verifyProbeTranscript(entry.probe_evidence, probeRoot, surfaceId, level, entry.substrate, entry.substrate_class, egressAllowList)
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
let egressHostsArg = null;
for (let i = 0; i < args.length; i += 1) {
  if (args[i] === "--evidence") {
    evidencePath = args[i + 1];
    i += 1;
  } else if (args[i] === "--probe-evidence-root") {
    probeRoot = args[i + 1];
    i += 1;
  } else if (args[i] === "--egress-hosts") {
    egressHostsArg = args[i + 1];
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
  (probeRoot !== null && !isNonEmptyString(probeRoot)) ||
  (egressHostsArg !== null && !isNonEmptyString(egressHostsArg))
) {
  console.error(
    "usage: check-security-binding.mjs <binding.json> [--evidence <evidence.json>] [--probe-evidence-root <dir>] [--egress-hosts <host,host,...>]",
  );
  process.exit(2);
}
const egressAllowList =
  egressHostsArg === null
    ? null
    : egressHostsArg.split(",").map((host) => host.trim().toLowerCase().replace(/\.$/, "")).filter((host) => host.length > 0);

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
  if (isPlainObject(binding)) verdicts = checkSemantics(binding, probeRoot, egressAllowList);
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
