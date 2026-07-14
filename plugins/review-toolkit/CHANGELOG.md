# Changelog

All notable changes to the `review-toolkit` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0]

### Changed

- **Consume the topic-docs convention** (`docs/conventions/topic-docs/README.md`), bound for this
  plugin in the new `reference/topic-docs.md`. The default findings location moves from
  `.claude/review/<branch-slug>/` to `.work/reviews/<branch-slug>/` — the memory tier's
  concern-scoped reviews home (branch axis, never committed, self-ignoring root). A consumer-declared
  review-artifacts location still wins; every report write runs the verify-or-create self-ignore
  guard on the memory root; no skill edits the consumer's root `.gitignore`.
- **Legacy grace for `.claude/review/`:** reads check the new home first and fall back to the legacy
  directory with a deprecation note; when legacy content exists for the current branch, writes stay
  pinned there so one branch's review history never splits across roots. Dual-read and the fallback
  are removed at the next major version.
- **`quality-gate` self-mode plan source:** the approved plan/brief is now sourced from the
  conversation, else the topic's contract slice `docs/topics/<slug>/PLAN.md` (memory-tier fallback
  under `contract_tier: local`), replacing the untyped "project's working notes" phrase.

### Added

- **`reference/topic-docs.md`** — the plugin's compact binding to the topic-docs contract: what it
  writes (memory tier only, branch axis), resolution order, branch-slug and timestamp spec, runtime
  guards, and the deprecation window.

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
