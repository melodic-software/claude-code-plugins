# Design resolution — github plugin

outcome: early-exit

## Reason

The design decisions for this plugin were resolved and user-locked through `/planning:interview`
(2026-07-20) as the Brief's locked-decisions table D1–D10 in `../PLAN.md`: packaging shape (one
vendor bundle), skill-surface shape (verb skills with area arguments), knowledge posture (zero
vendored content), mechanism ladder, write posture and routing classes, depth tiers, self-drive
posture, boundary lines against sibling plugins, and audience. The remaining design-level choices
(exact skill set and names, consumer config schema, mutation surfacing, browser-automation gating,
recipe depth, setup contract) are explicitly delegated to `/planning:plan` by the Brief's
deferred-questions table (arbiter column) — a user-approved delegation, not a skipped exploration.

No new runtime types or code contracts exist at design time: the deliverable is a prompt-artifact
plugin (SKILL.md files, reference docs, one JSON manifest, one YAML consumer-config schema). The
"type sketch" equivalent — the consumer config schema and skill contracts — is produced and
reviewed inside the Plan itself, under the marketplace's binding contracts
(`docs/PLUGIN-PHILOSOPHY.md`, `docs/MIGRATION-PLAYBOOK.md` extensibility contract v2.1,
`docs/conventions/consumer-config-layering/`).
