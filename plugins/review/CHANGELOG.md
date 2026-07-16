# Changelog

All notable changes to the `review` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.9.0]

### Added

- **Cross-repo `REVIEW.md` citation dereferencing** in `code-reviewer`, `security-reviewer`, and
  `architecture-guardian`. Each now recognizes a code-span citation in a consuming project's
  `REVIEW.md` shaped like `<relative-path>.md#<heading>`, splits it into the file path and heading
  anchor, and Reads only the `.md` file — which may live outside the current repository, mounted via
  `--add-dir` — before locating the referenced heading for the full criterion behind a thin
  `REVIEW.md` line before finalizing an overlapping finding. An unresolved citation (mount absent,
  wrong path) is noted in the agent's report rather than dropped silently or treated as a hard
  failure. Whether a `--add-dir`-mounted path is visible to a plugin subagent's `Read` tool the same
  way it is to the main session is not yet empirically verified against a live cross-repo mount.

## [0.8.0]

### Changed

- Renamed the plugin `review-toolkit` → `review` and its skill `code-review-fanout` → `fanout`;
  the six reviewer agents move to the `review:` namespace. Invocations are now `/review:fanout`
  and `/review:quality-gate`. Existing installs migrate automatically through the marketplace
  renames map.

## [0.7.0]

### Added

- **Judgement-call labeling in reviewer output formats.** `code-reviewer` and
  `architecture-guardian` now label design-smell and convention findings as judgement calls —
  advisory, reviewer-tier — never as hard violations; hard-violation framing is reserved for
  findings backed by a documented project rule, a failing check, or a demonstrable defect
  (`architecture-guardian` admits a finding into its Violations bucket only with that backing).
- **Pre-flight fail-fast gate in `code-review-fanout`.** Both review modes now resolve the review
  diff base and confirm a non-empty diff BEFORE any surface is spawned: an unresolvable base ref
  or an empty change set reports and stops — reviewers are never fanned out against an empty or
  wrong diff. The default mode's inline dispatch-gate summary folds into the shared gate; the full
  clean-tree and untracked-only logic stays in the default-mode context, and run-everything mode
  defers to the same gate.
- **Per-dimension breakdown in the fanout report.** The persisted findings file keeps the merged
  ranked queue and adds a required `## By dimension` section regrouping the same findings under
  one heading per review dimension — a merged rank can mask one dimension failing badly while the
  others pass. Stage 4 of the normalization pipeline carries the matching two-axis presentation
  rule; the fix action's parse contract (`## Findings` + `## Unparsed`) is unchanged.

## [0.6.0]

### Added

- **Restored fanout regression evals.** `code-review-fanout`'s `evals/evals.json` gains 14 cases
  (ids 7–20) covering behavior that was still documented but had lost eval coverage: dedup and
  severity-derivation (Stage 3/4 cross-surface merge, content-derived severity for
  no-native-severity surfaces), the fix-pass safety fence (correctness findings are never routed
  to `/simplify`, branch-scoped findings lookup, mixed-class routing), and run-everything's
  null-reconciliation and priority-ordering (named null leaves, the tier-1 barrier ahead of
  tier-2). Also restored: per-tier surface routing and promotion, the large-tier ownerless-slice
  exclusions, the findings-file shape contract, the clean-tree short-circuit, and graceful
  orchestrator-absent degradation.

## [0.5.0]

### Added

- **Model-assignment cost routing for the findings-normalization pipeline.** Each stage heading in
  `code-review-fanout`'s findings-normalization context now carries its model annotation, and a
  closing `## Model assignment` section summarizes the routing: Stage 0 Sonnet (parse fidelity),
  Stages 1–2 deterministic/Haiku (enum lookup), Stage 3 Sonnet (semantic merge), Stage 4
  deterministic.

## [0.4.0]

### Changed

- **Consume the topic-docs convention** (`docs/conventions/topic-docs/README.md`), bound for this
  plugin in the new `reference/topic-docs.md`. The default findings location moves from
  `.claude/review/<branch-slug>/` to `.work/reviews/<branch-slug>/` — the memory tier's
  concern-scoped reviews home (branch axis, never committed, self-ignoring root). Resolution
  follows the contract's ladder: the concern file's `memory_dir` first, then a consumer-declared
  review-artifacts location (an inference source — the skills offer to persist it into the concern
  file), then the default. The session's first memory-tier write runs the verify-or-create
  self-ignore guard on the resolved memory root; no skill edits the consumer's root `.gitignore`.
- **`.claude/review/` retired outright.** The prior findings location gets no compatibility
  layer, no dual-read window, no migration tooling; move residual content manually.
- **`quality-gate` self-mode plan source:** the approved plan/brief is now sourced from the
  conversation, else the topic's contract slice `docs/topics/<slug>/PLAN.md` (memory-tier fallback
  under `contract_tier: local`), replacing the untyped "project's working notes" phrase.

### Added

- **`reference/topic-docs.md`** — the plugin's compact binding to the topic-docs contract: what it
  writes (memory tier only, branch axis), resolution order, branch-slug and timestamp spec, and
  runtime guards.

## [0.3.0]

### Added

- **Skill evals for the two orchestration skills.** Rich-form `evals/evals.json` authored for
  `quality-gate` (6 cases) and `code-review-fanout` (6 cases), each covering trigger/routing, the
  happy path, a refusal/guardrail, and an anti-pattern the skill must not do. Additive test
  definitions only — no behavioral change to any skill or agent.

## [0.2.0]

### Changed

- **`ecosystem-specialist` consumes the ecosystem-commands contract.** The agent now resolves each
  ecosystem's build/test/lint command truth from the consumer repo's `.claude/ecosystems/<ecosystem>.yaml`
  files (authoritative when present) — the marketplace-wide ecosystem-commands contract
  (`docs/conventions/ecosystem-commands/README.md`) — falling back to the project's documented
  conventions, then the agent's own bundled generic defaults as an explicit last resort. Ecosystem
  detection may use the contract's `globs` when config exists. Report format, MISSING-tool handling,
  and detection behavior are unchanged; only the command-truth sourcing moved from the agent's inline
  defaults to the declared contract.

## [0.1.0]

- Initial release: six read-only reviewer agents (`code-reviewer`, `security-reviewer`,
  `architecture-guardian`, `doc-drift-detector`, `ecosystem-specialist`, `ci-log-auditor`) plus two
  orchestration skills (`quality-gate`, `code-review-fanout`).
