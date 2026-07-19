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
    if (!(key in binding)) findings.push(`binding: required key ${key} missing`);
  }
  if ("schema_version" in binding && binding.schema_version !== "1.0") {
    findings.push(`schema_version: ${JSON.stringify(binding.schema_version)} is not the supported "1.0"`);
  }
  if ("executor_class" in binding) {
    checkEnum(binding.executor_class, ["self-operated", "vendor-hosted"], "executor_class");
  }
  if ("dispatch_posture" in binding) {
    checkEnum(binding.dispatch_posture, ["autonomous-enabled", "human-gated-only"], "dispatch_posture");
  }

  if ("isolation_bindings" in binding) {
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
          if ("runtime_markers" in entry) {
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

  if ("merge_policy" in binding) {
    if (!isPlainObject(binding.merge_policy)) {
      findings.push("merge_policy: must be an object keyed by work class");
    } else {
      checkAllowedKeys(binding.merge_policy, WORK_CLASSES, "merge_policy");
      for (const workClass of WORK_CLASSES) {
        if (!(workClass in binding.merge_policy)) {
          findings.push(`merge_policy.${workClass}: required key missing`);
        } else {
          checkEnum(binding.merge_policy[workClass], MERGE_TOKENS, `merge_policy.${workClass}`);
        }
      }
    }
  }

  if ("verification_blocking" in binding) {
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
          if (!(workClass in perClass)) {
            findings.push(`${where}.${workClass}: required key missing`);
          } else {
            checkEnum(perClass[workClass], VERIFICATION_TOKENS, `${where}.${workClass}`);
          }
        }
      }
    }
  }

  if ("promotion_state" in binding) {
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
        if (!("state" in entry) || !checkEnum(entry.state, ["promoted", "unpromoted"], `${where}.state`)) continue;
        if (!isNonEmptyString(entry.ratified_by_change)) {
          findings.push(`${where}.ratified_by_change: missing or empty — the flip is a reviewable change on the governance surface`);
        }
        if (!isNonEmptyString(entry.evidence_window)) {
          findings.push(`${where}.evidence_window: missing or empty — the telemetry window the evidence predicate was satisfied over`);
        }
        if (!isNonEmptyString(entry.ratified_at) || Number.isNaN(Date.parse(entry.ratified_at))) {
          findings.push(
            `${where}.ratified_at: missing or not a parsable ISO 8601 date-time — the ratification instant anchors the promotion epoch contrary evidence is scoped to`,
          );
        }
      }
    }
  }

  if ("escalation_routes" in binding) {
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

  if ("admission" in binding) validateAdmissionStructure(binding.admission);
}

function validateAdmissionStructure(admission) {
  if (!isPlainObject(admission)) {
    findings.push("admission: must be an object");
    return;
  }
  checkAllowedKeys(admission, ["classification", "rules", "autonomous_concurrency", "items_per_run"], "admission");
  for (const key of ["classification", "rules", "autonomous_concurrency", "items_per_run"]) {
    if (!(key in admission)) findings.push(`admission.${key}: required key missing`);
  }

  if ("classification" in admission) {
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

  if ("rules" in admission) {
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
        if ("override_justification" in rule && !isNonEmptyString(rule.override_justification)) {
          findings.push(`${where}.override_justification: must be a non-empty string when present`);
        }
      });
    }
  }

  for (const cap of ["autonomous_concurrency", "items_per_run"]) {
    if (cap in admission && (!Number.isInteger(admission[cap]) || admission[cap] < 1)) {
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
    if (key in markersB && markersB[key] !== value) return false;
  }
  return true;
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
  if (transcript.assertions?.egress_denied?.outcome !== "denied") {
    return `transcript ${path} does not record the egress-denial assertion with outcome "denied"`;
  }
  if (transcript.assertions?.credentials_absent?.outcome !== "absent-or-denied") {
    return `transcript ${path} does not record the credential-absence assertion with outcome "absent-or-denied"`;
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
    // The dispatch seam requires EXACTLY ONE matching surface at runtime,
    // failing closed on zero or multiple matches; rejecting jointly
    // satisfiable marker sets here keeps that rule from turning validly
    // bound fleets into ambiguity outages.
    const reportedPairs = new Set();
    for (let i = 0; i < markerEntries.length; i += 1) {
      for (let j = i + 1; j < markerEntries.length; j += 1) {
        const a = markerEntries[i];
        const b = markerEntries[j];
        if (a.surfaceId === b.surfaceId) continue;
        const pairKey = JSON.stringify([a.surfaceId, b.surfaceId]);
        if (reportedPairs.has(pairKey)) continue;
        if (jointlySatisfiable(a.markers, b.markers)) {
          reportedPairs.add(pairKey);
          findings.push(
            `isolation_bindings: runtime_markers of surfaces ${JSON.stringify(a.surfaceId)} and ${JSON.stringify(b.surfaceId)} are jointly satisfiable — a runtime context carrying the union matches both; the sets must conflict on at least one shared key`,
          );
        }
      }
    }
  }

  // Per-surface, class-aware isolation verdicts: a surface is eligible for a
  // class only when its bound level meets that class's min-isolation cell —
  // so an L2-only surface is never selected for a C5 item, and an unbound
  // surface is blocked even when a sibling surface is bound.
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
    // whose `at` cannot be parsed cannot be assigned to an epoch and is
    // treated as contrary (fail-closed) — dropping it silently would let
    // malformed telemetry mask a real demotion signal.
    const ratifiedAt = Date.parse(entry.ratified_at);
    const inEpoch = [];
    const preEpoch = [];
    for (const event of contrary) {
      const at = typeof event.at === "string" ? Date.parse(event.at) : Number.NaN;
      if (Number.isNaN(at)) {
        inEpoch.push(`${event.event} with unparsable at ${JSON.stringify(event.at)} — cannot be assigned to an epoch, treated as contrary (fail-closed)`);
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
