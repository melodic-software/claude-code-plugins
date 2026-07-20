# Setup skill gotchas

Observed failure modes when editing or running this skill.

- **Two-binding split.** The `routines`, `triggers`, `telemetry`, and `capture` sections live in
  the repo-local autonomy binding under `.claude/autonomy/`. The security binding is a SEPARATE
  artifact on the settings-as-code home carrying only the guardrail security axes and
  `admission.classification.temporal`. A change that puts a repo-local section (routines included)
  into the security binding schema, or a security axis into the repo-local binding, is wrong —
  both artifacts are "schema-versioned," so always qualify WHICH artifact every section names.
- **Coined hyphenated compounds trip the spell gate.** The CI spell check splits a coined
  hyphenated compound into parts and flags a fragment as wrongly spelled. Keep multi-word
  identifiers as backticked tokens (`run_link_prefix`) or plain words — write "wrongly
  associated," not a coined hyphenated form — so the gate has nothing to split.
- **Detector-fired temporal carries no routine identity.** A poll-fallback detector emission is
  not a routine run: it carries no `signal.routine`, no `signal.producer_identity`, and stamps no
  `signal.work_class` — any of the three on a claimless or detector-fired signal is rejected
  fail-closed. Routine-fired status is the envelope's `signal.routine` CLAIM validated against
  `routines.enabled` (entry exists, enabled, `source_surface` agrees) — NOT the section owning
  the surface record: a routine may reuse a `triggers`-recorded surface. Only a surface recorded
  under `routines` itself makes the claim mandatory.
- **One surface per section.** A scheduling surface recorded in both the `triggers` and `routines`
  `surfaces` maps resolves as ambiguous and fails the envelope check
  ([`context/trigger-dispatch-slice.md`](trigger-dispatch-slice.md) records the shape). A routine
  riding an existing trigger surface references its id; only a new surface gets a new entry.
