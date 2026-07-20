# Changelog

All notable changes to the `testing` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.3]

### Changed

- Neutralized repo-coupled `expected_output` in `diagnose` and `write` evals so they grade the
  underlying decision, not one private monorepo's layout. The `diagnose` fixture-collision case now
  grades recognition of a process-global singleton / shared-state collision and deferral to the
  project's documented fixture convention (dropping the `MonolithApi.Tests` /
  `MonolithApiTestFixture.CollectionName` names). The `write` cases now grade co-located placement and
  naming per the consuming project's documented conventions, and the testable-vs-contracts decision,
  without naming any project, path, or framework (dropping `Platform.Messaging`, `libs/dotnet/`, and the
  ghost `testing.md` reference to xUnit v3 / Shouldly — this plugin ships `write.md`/`organize.md` and
  defers framework/assertion choices to the consuming project). Eval prompts/expectations only; no skill
  behavior, routing, or context files changed.

## [0.2.2]

### Changed

- Fallback naming defaults, the sole worked code sample, and the sole regression command are reframed
  as ecosystem-relative rather than .NET-only. The PascalCase `{Method}_Should{Behavior}_When{Condition}`
  naming forms (in `write`, `write/context/write.md`, `write/context/organize.md`, `plan`) are demoted
  from "the universal default" to one labeled illustrative (.NET/xUnit) example, routed first through the
  convention-resolution ladder (use the project's documented pattern; when undocumented, mirror the
  consuming ecosystem's own idiom). The lone worked `[Fact]` code sample in `write/context/write.md` and
  the lone `dotnet test` regression block in `diagnose/context/loop.md` now carry an "illustrative (.NET)"
  label, with the regression block routed through `/toolchain:check` as SSOT for the exact per-ecosystem
  command (falling back to the project's own test command when the `toolchain` plugin is absent, matching
  `write`'s handoff). Framing and labeling only — TDD cadence, Four Pillars, verify-through-the-interface, the
  reproduce→fix→retest→regression loop, and all routing/handoff are unchanged; no code, template, or
  command string was altered.

## [0.2.1]

### Changed

- Cross-plugin marketplace-skill references brought under the presence-gated guard and reframed as
  stack-specific. The unguarded inline `dotnet-test:*` parenthetical in `write` (per-cycle checklist)
  is removed; its detection-layer skills moved under `write`'s now-guarded
  `## Marketplace plugin skills (invoke only when installed)` list. The all-.NET enrichment lists in
  `write`, `organize`, `plan`, `run-e2e`, and `diagnose` now state the `dotnet-*` skills apply only
  when your stack is .NET, so a non-.NET consumer is not handed a dead list as the universal path.
  No hard dependencies; every reference stays optional and installed-gated.

## [0.2.0]

### Changed

- **BREAKING: `/testing:e2e` renamed to `/testing:run-e2e`** (fleet conformance wave —
  naming grammar, verb-first skill names). Update any saved invocations. Skill behavior,
  triggers, and evals are unchanged; only the leaf name and namespace token changed.

## [0.1.2]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.1.1]

### Changed

- References to the renamed `/toolchain:build` skill now invoke `/toolchain:check` (toolchain 0.2.0 breaking rename). Version bumped so existing installs pick up the rewritten prompts.

## [0.1.0]

### Added

- Initial release — four skills extracted and renamed from the `implementation` plugin's `test-*`
  skills: `/testing:plan` (was `test-plan` — coverage-gap analysis), `/testing:write` (was `test-write` —
  TDD authoring and placement), `/testing:e2e` (was `test-e2e` — live app + non-UI smoke verification),
  and `/testing:diagnose` (was `test-diagnose` — failing-test root-cause diagnosis and the fix loop).
  Skill trigger phrases and evals are preserved; only the namespace and leaf names changed.
- Cross-plugin references degrade gracefully: test invocation defers to `/toolchain:build` when the
  `toolchain` plugin is installed (else the project's own test command), and handoffs to
  `/implementation:implement`, `/verification:confirm`, `/tdd:principles`, and `/playwright:playwright`
  fire only when those plugins are installed — no hard dependencies.
