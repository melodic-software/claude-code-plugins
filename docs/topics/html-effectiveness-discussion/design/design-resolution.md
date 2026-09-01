# Design resolution — html-effectiveness integration, wave 1

outcome: resolved-via-brief (Tier B, light design)

The design threads for wave 1 were resolved through the interview and its adversarial
validation chain (blindspot scan, devils-advocate stress-test, two-validator answer audit)
and are enumerated as settled decisions in [../PLAN.md](../PLAN.md). No separate design
phase is owed because wave 1 introduces no new code types or module topology: its surfaces
are convention documents, one registry-synced HTML asset with a validation lane, and
instruction-text wiring in one exemplar skill.

Resolved threads carried by the Brief:

- Shared-asset shape: registry-synced per-plugin copies, never a single cited file
  (Brief decision 3; the cross-plugin source registry is the proven mechanism).
- Preference architecture: config-cascade concern for the cross-plugin format preference,
  per-plugin userConfig for plugin-specific dials, tier ladder argument, plugin dial,
  cascade, shipped default (Brief decision 6).
- Boundary and ladder semantics: record-vs-view, reachability rung, offer-not-emit for
  dual-audience reports, native Artifact switches as the day-one flip (Brief decisions 2, 5).
- Security architecture: staged escaping, deterministic helper deferred to the gated wave
  (Brief decision 7).

Design-significant residue deliberately deferred, with owners: the deterministic escape
helper's interface (wave 2, gated), and the fleet ladder sweep's eval redesign (priced
release sweep, tracked as an issue).
