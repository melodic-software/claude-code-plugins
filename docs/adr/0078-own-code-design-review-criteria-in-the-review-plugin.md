# Own code-design review criteria in the review plugin

- Status: accepted
- Date: 2026-10-19
- Related: [ADR 0079](0079-dispatch-tagged-phase-reviews-to-quality-gate-at-the-phase-boundary.md)
  (who invokes the mode at a phase boundary). Refs
  [#8326](https://github.com/melodic-software/claude-code-plugins/issues/8326).

## Context

The plan template's `Review: code-design` phase tag promised a review that nothing ran. The checks
it needs (one fact copied into several files, one change cascading across files, abstraction with
no second use) and their severities need one owner. Three plugins touch them: planning sets
design-time defaults, implementation runs phase-boundary reviews, and review owns reviewers and the
severity vocabulary.

Plugins install independently, so a skill in one plugin cites a skill in another only by its
`/plugin:skill` invocation, never by a path into its `skills/` folder
(`docs/plugin-philosophy.md:472-478`).

## Decision

The review plugin owns the code-design review criteria and their severity, exposed as the
`/review:quality-gate code-design` mode. The
mode holds the bundled criteria, the cascade rule that limits CRITICAL to introduced,
unsynced Duplicated Code, and the consumer-criteria-win loading.

Planning keeps design-time defaults only and cites the mode by invocation
(`plugins/planning/reference/design-principles.md:96-99`). Implementation invokes the mode
(ADR 0079). Review never cites planning files, so the dependency runs one way.

Shipped in [#8348](https://github.com/melodic-software/claude-code-plugins/pull/8348) (phase-diff
inputs for `/review:quality-gate`, issue
[#8327](https://github.com/melodic-software/claude-code-plugins/issues/8327)) and
[#8388](https://github.com/melodic-software/claude-code-plugins/pull/8388) (the `code-design` mode,
issue [#8329](https://github.com/melodic-software/claude-code-plugins/issues/8329)).

## Why

Review already owns the reviewer agents, the severity tiers and the consumer-criteria loading that
the other quality-gate modes use, so the criteria sit next to the code that applies them. Both
callers reach the mode by `/plugin:skill`, which the citation rule allows.

## Alternatives considered

- **Planning owns the criteria.** Rejected: review and implementation would have to reach into
  planning's files across a plugin boundary by path, which `docs/plugin-philosophy.md:472-478`
  forbids, and review would depend on planning. Revisit if the review plugin leaves the
  marketplace.
