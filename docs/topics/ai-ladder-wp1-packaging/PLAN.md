# ai-ladder-wp1-packaging

## Brief

### TLDR

Packaging and topology for the AI-adoption-ladder machinery (T1–T7 contract set): role-vocabulary
repo topology, one new plugin as the single home composing existing plugin seams, and a
surface-based wiring-vs-advisor principle for guided setup.

### Goal

Every ladder artifact has one owning home named by ROLE in contract text; fleet repo names appear
only in the binding-seam instance doc; the new plugin ships the contract docs and capabilities and
composes existing plugins without duplicating them.

### Locked decisions

| # | Decision |
|---|---|
| D1 | Role vocabulary for repo topology: capability-distribution home, CI-orchestration home, settings-as-code home, org-policy home, runner-execution home (unborn; born only when the T4 build trigger fires). |
| D2 | Contract docs + capabilities ship in the capability-distribution home. Fleet binding: claude-code-plugins marketplace. |
| D3 | GitHub-event adapter splits by role: handler logic = CI-orchestration home (fleet: ci-workflows reusables); enabling settings incl. labels, permissions, runner-policy admission = settings-as-code home (fleet: github-iac). |
| D4 | One new plugin (working name `autonomy`; final name via naming pass) is the single home for: contract docs, guided-setup capability, guardrail-matrix + org-binding seam, sandbox-ladder setup, telemetry contract, return-accounting convention, routine catalog + v1 definitions. |
| D5 | The new plugin composes existing plugin seams — work-items (queue/lease/dispatch), guardrails (deterministic hooks), verification (gates), claude-ops (observability). Orchestration-composing-plugins is the sanctioned model; near-duplicate skill variants are banned. |
| D6 | Wiring-vs-advisor principle: WIRE when the target surface is machine-editable + local + reviewable (repo files, settings, workflow files, IaC code) — wiring always lands as reviewable changes, never silent mutation. ADVISE (steps + cost surfaced) when the surface is org-external, entitlement-gated, paid, or GUI-only. Paid anything = advisory + explicit opt-in first, regardless of wireability. |
| D7 | Adoption starts with discovery/exploration/interview of the adopting org's state — guided-setup owns that phase and never assumes fleet shape. Fleet = first adopting instance (dogfood). |

### Constraints

- Any fleet repo name in normative contract text is a defect; fleet names live only in the
  binding-seam instance doc.
- No new repos until the T4 build trigger fires.
- Plugin format is Claude-Code-specific; contract docs inside remain tool-agnostic markdown any
  org/tool can consume.
- Boris-alignment is the standing acceptance criterion (no step-skipping, trust before scale).
- No new cost without discussion; free defaults, paid = explicit opt-in surfaced first.

### Acceptance criteria

- Contract text names roles only; a binding-seam doc maps each role to the fleet instance.
- New plugin clears the plugin-acceptance gates (plugin validate, contract tests, security review
  per MIGRATION-PLAYBOOK).
- No near-duplicate skill of an existing plugin capability exists in the new plugin.
- Every wiring path lands as a reviewable change.

### Captured assumptions

- Split-later is cheap: renames map is append-only and many-to-one is verified legal, so the
  single-plugin decision is reversible.
- Marketplace distribution suffices for universality: any org can install from the marketplace;
  non-Claude-Code orgs consume the contract markdown directly.

### Out-of-scope (deferred with triggers)

- Runner-execution home creation — trigger: T4 build trigger fires (WP7 owns the design pack).
- Org-enablement track beyond fleet dogfood — trigger: day-job adoption becomes concrete.

### Deferred questions

- Final plugin name + category assignment (category possibly new and broader — not article-tied;
  D22 category vocabulary governs) — `/architect`.
- Contract-doc file layout inside the plugin (docs/ vs skill context/) — `/architect`.
- Per-capability wiring depth — resolved per-package in WP2–WP6 Briefs.

## Plan

(unfilled — /architect)
