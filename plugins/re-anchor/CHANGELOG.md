# Changelog

All notable changes to the `re-anchor` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Added

- `/re-anchor:script-the-deterministic-work` — offload-the-deterministic
  discipline: purely deterministic sub-work (counting, diffing, sorting,
  transforming, matching, sweeping, arithmetic) gets a script that runs and
  returns real output, and the model reasons only afterward over that output.
  The tier boundary — deterministic (script it), detect-then-judge (script
  the detect half; the verdict stays judgement), reasoning-only (never
  script) — re-anchors the consuming org's enforceability-tiers convention;
  the in-task "script it now" application has no standards doc yet, so the
  skill flags that gap rather than inventing a rubric. Runs in both
  directions: analysis reasons over a script's output; generation emits a
  deterministic scaffold (PR body, issue, report, config boilerplate) from a
  script or native template so model output is reserved for the judgment
  slots. Distinct from a standing-automation capability: recurring checks
  route to a hook, this corrector owns the one-off, session-time script.

## [0.1.0]

### Added

- **Initial release.** Discipline correctors sharing one re-anchor / audit /
  correct-forward method at plugin scope
  (`context/re-anchor-audit-correct.md`):
  - `/re-anchor:do-your-research` — research and no-assumptions discipline: assert
    nothing without a source, verify every concrete specific, frame the problem before
    the solution, and treat training-data recall as unverified.
  - `/re-anchor:do-your-research-deep` — the verification-fan-out tier of
    `do-your-research`: enumerates every load-bearing claim and dispatches fresh-context
    subagents to verify each against a primary source, throttled in bounded waves, then
    reports a per-claim ledger. A sibling skill rather than a `deep` argument because the
    subagent fan-out is a heavier execution tier (mirrors `/discovery:research-deep`).
  - `/re-anchor:follow-our-standards` — alignment to the consuming organization's
    engineering conventions, with relevance-routed progressive loading and respect
    for a declared managed / locally-owned seam.
  - `/re-anchor:point-dont-copy` — pointer-over-copy discipline: no copied content,
    internal-name coupling, or closed capability lists; duplication threshold of two.
    Re-anchors through the consuming org's reference-don't-duplicate and
    documentation-and-citations conventions (in-repo and external facts), degrading
    to a portable baseline.
  - `/re-anchor:reason-dont-recite` — incumbency discipline: inherited content is
    evidence of what is, never self-justifying authority; a choice supported only by
    precedent earns first-principles re-derivation. A standards disagreement it
    surfaces routes upstream via `/re-anchor:follow-our-standards`.
  - `/re-anchor:tighten-your-output` — terseness discipline: fewer words or lines
    with no loss of meaning or correctness. Code re-anchors the consuming org's
    simpler-code convention; prose terseness has no standards doc yet, so the skill
    flags that gap and routes batch work to compress (prose) and simplify (code).
- Repo-agnostic and machine-agnostic: each corrector re-anchors the discipline the
  consuming project declares in its own instruction layer, and degrades to a portable
  baseline when none is declared.
