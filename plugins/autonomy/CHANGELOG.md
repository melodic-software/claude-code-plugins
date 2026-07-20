# Changelog

All notable changes to the `autonomy` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

Versions 0.1.0–0.7.0 predate this file (introduced with 0.7.1); their history lives in the
merged work-package PRs (#333, #343, #356, #372, #377, #600, #676).

## [0.7.2]

### Changed

- **Pillar 3 reconciled with the native-surface reality (`#351` audit).** The causal-tree
  contract now states what was implicit and empirically contradicted: `traceparent`
  propagation binds CONTRACT-AUTHORED emissions; a native agent surface that ignores inbound
  context starts its own root, and its session emissions attach to the chain query-side
  through the Pillar 2 join attribute — with native inbound-context adoption recorded as a
  migration trigger, not an assumption. The CI OTLP template's trace-context-injection
  section carries the same correction plus the `OTEL_RESOURCE_ATTRIBUTES` injection the
  setup flow already wires. No emission or checker behavior changes.

## [0.7.1]

### Added

- **D1 deferral sweep — every out-of-package note from the WP1–WP7 design rounds now has a
  durable trigger record (`#353`).** The README roadmap gains the fleet guardrail
  materializations, fleet routine stand-up + existing-scheduler reconciliation,
  vendor-binding capability templates, and cost-enforcement rows; the trigger register gains
  the second-binding-consumer cross-repo drift check; `reference/return-accounting.md`
  records the per-work-class precision-graduation deferral beside its band-stability rule.
  Documentation only — no contract semantics change.
