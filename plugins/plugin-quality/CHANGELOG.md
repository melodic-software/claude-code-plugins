# Changelog

All notable changes to the `plugin-quality` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-07-25

### Changed

- `skills/audit` step 2 no longer justifies its dispatch by what a fork inherits. Three successive
  rationales for rejecting `context: fork` were each defeated in review, so the requirement is now
  stated as an invariant the step must satisfy: a context that carries the evidence packet but
  **not** this session's conversation history or prior reasoning, plus a named dispatch target that
  makes the dispatch site auditable. The `auditor` agent supplies both — and the packet crossing the
  boundary is deliberate, since the agent reads it as ground truth. The framing holds either way on
  #1258, which reports the Agent tool's `fork` subagent type not inheriting the conversation in
  practice, against its documentation.

## [0.1.1] - 2026-07-24

### Fixed

- `skills/audit` step 2 no longer claims a fork "would inherit this session's degraded history".
  That is false for a skill's `context: fork` frontmatter, which starts the subagent with no
  conversation history; conversation inheritance belongs to the Agent tool's separate `fork`
  subagent type. The step now names that type explicitly and also forbids running inline.
- `skills/audit/references/component-types/skill.md` composition lens no longer asserts that a
  forked sub-skill "loses history" as a defect; it asks whether the inline-vs-`context: fork`
  choice matches what the step needs, and names the mechanism.
- `agents/auditor.md` says why it has no conversation history — it is a named subagent rather than
  a conversation fork — instead of leaving "by design" for the reader to interpret.

## [0.1.0] - 2026-07-24

### Added

- `skills/audit` — six-step post-use component audit (`/plugin-quality:audit
  <plugin>[:<component>]`): evidence capture into a compaction-proof packet, map+ground in the
  fresh `auditor` subagent with per-topic fresh-docs verification, blindspot + candidates,
  interactive contract lock, presence-gated review seams, sink emit behind the draft+confirm
  egress gate (acting `gh` account surfaced). Context-gate over context-guard snapshots with a
  per-zone decision table; conservative on unknown. Evals incl. conservative-dispatch and
  prompt-injection anti-pattern cases.
- `agents/auditor.md` — fresh-context audit specialist (steps 2–3) with an honest Bash grant and
  the standing untrusted-content instruction.
- `skills/audit/references/` — recurring-concerns checklist + five component-type lenses, ported
  from the retiring machine-local skill and generalized.
- `reference/config.md` — `.claude/plugin-quality.md` cascade surface (per-key override), sink
  resolution ladder, markdown item schema (byte-compatible with the cross-terminal handoff inbox
  contract), work-items seam boundary.
- `skills/setup` — `check` (gh + acting account, context-guard seam → dispatch mode, config
  provenance) / `apply` (tracked config only), with evals.
