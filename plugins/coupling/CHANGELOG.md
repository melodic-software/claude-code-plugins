# Changelog

All notable changes to the `coupling` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

- `reduce` skill: iterative coupling reduction at four altitudes (docs, code, application,
  repository) — model-typed scan with a verification gate, two-lane partition (safe
  behavior-preserving reductions applied under a scope budget; cross-file and architectural
  candidates surfaced and routed, never auto-applied), and a durable per-repo ledger via the
  topic-docs memory tier so successive runs resume instead of restarting.
- `reference/coupling-model.md`: the assessment model — change-centric coupling definition,
  structured-design strength ladder, connascence (strength × degree × locality), volatility
  weighting, per-altitude mechanisms, and the not-a-finding list.
- `reference/remediations.md`: mechanism catalog (dependency injection, owned interfaces at
  volatile boundaries, configuration externalization, events/mediator, single-source-of-truth
  pointers, published contracts) with an explicit over-abstraction counterweight per entry.
- Topic-docs binding (`reference/topic-docs.md`) for the repo-scoped coupling ledger.
