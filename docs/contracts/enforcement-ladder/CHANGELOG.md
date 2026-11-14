# Changelog for the enforcement-ladder convention

Notable changes to the enforcement ladder (SemVer). Renaming, removing or moving a rung is a major
bump. Adding a rung, a reader's selection rule or a boundary-rule location is a minor bump.
Wording-only clarification is a patch.

## [3.0.0] - 2026-11-14

The ladder becomes five tiers: a verification tier joins in third place, between static analysis
and guidance. The reason: the pyramid in Lauren Tan's talk "All Code Is Slop (Except
Mine)" (`docs/upstream/poteto-all-code-is-slop-talk.md`, slides 8 and 10) puts verification third, after
the shape of the code and deterministic checks and before written rules (slide 8); verification,
runtime and formal, checks invariants and whether the agent understood the intent (slide 10).
Tests stay on the static-analysis tier, where the talk puts them among the deterministic checks
(slide 9). Formal verification is opt-in: a repository chooses it for the question at hand.

- Renamed: `semgrep-rule` to `syntax-pattern-rule`, named for the capability rather than the tool.
  `semgrep-rule` stays an accepted alias, with a printed notice, through 3.x and is removed in
  4.0.0.
- Added: Tier 3 Verification with the `runtime-verification` and `formal-verification` (opt-in)
  rungs.
- Moved: Guidance from tier 3 to tier 4 and Human only from tier 4 to tier 5.
- Changed: the `custom-analyzer` and `architecture-test` rungs are defined by capability and no
  longer name a tool.
- Added: the Proportion section (most enforcement on the strongest tiers, least on guidance and
  human review, in words with no target) and the Order of work section (lint first, clean up,
  strengthen verification, then automate).

## [2.1.1] - 2026-11-12

- Clarified: the guardrail criterion's policy-class names an action that cannot be undone, exposes
  a secret, or sends data outside the repository.

## [2.1.0] - 2026-11-01

- Added: the `/corrections:codify` reader row, the strongest rung that can decide a recurring
  mistake given as a description, a findings file or review comments.
- Removed: the `/review:audit-enforceability` and `/session-flow:retro` codify reader rows, and the
  "cheapest" order only the first of them used.

## [2.0.0] - 2026-10-21

The ladder becomes four tiers (codebase, static analysis, guidance, human only), strongest first,
with a "runs at" column on the static-analysis rungs and one "Guardrail criterion" section.

- Renamed: `canonical-helper` to `shared-helper`; `hook` to `action-guard`; `llm-only` to
  `automated-review`.
- Added: `harness-setting`, `scaffold`, `instruction`, `skill`, `human-review`.
- Moved: `shared-helper` from below the linters to tier 1, after `make-impossible`, and it counts
  there only when a lint or check names the helper; `action-guard` now follows `harness-setting`
  and precedes `scaffold` in tier 2; the `CLAUDE.md`, `AGENTS.md` and rules-file routing of the old
  `llm-only` rung is now `instruction`, and project docs are `human-review`.
- Removed as rungs: "Git hook or CI" (a place a check runs, now the "runs at" column) and the
  code-content hook (the same check as a linter rule or a test).
- Unchanged ids: `make-impossible`, `editorconfig-severity`, `analyzer-pack-rule`,
  `custom-analyzer`, `semgrep-rule`, `architecture-test`.
- Added the Guardrail criterion (eight conditions), the forgotten-versus-ignored rule for a
  recurring correction, and the selection rows updated to the new ids.

## [1.0.0] - 2026-10-04

Initial ladder: one strongest-first rung list, from `make-impossible` through compiler settings,
the four analyzer and linter rungs, `canonical-helper`, `architecture-test`, tests, git hook or CI,
`hook` and `llm-only`; the list of places boundary rules live; the selection rules of
`/harness-config:audit-automation-gaps`, `/review:audit-enforceability` and `/session-flow:retro`
codify; reordering through project instructions; and the codebase and its history as the memory.
