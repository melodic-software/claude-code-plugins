# Changelog

All notable changes to the `testing` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.4.0]

### Added

- **`diagnose`: redaction guard + tagged debug logs.** A new `## Redact` section in the router
  requires every secret redacted (`<REDACTED>`) before commands, test output, stack traces, or
  CI logs are shown; reproductions read credentials from env vars so secrets never land in a
  command line, fixture, or committed regression test. Investigation step 4 now tags every
  debug log with a unique short prefix (e.g. `[DEBUG-a4f2]`), and the fix loop's green gate
  removes tagged instrumentation via a single grep before the atomic commit — the loop commits
  per iteration, which is exactly where untagged logs leak into history. (Guard and tag
  convention from upstream mattpocock/skills `diagnosing-bugs` v1.2.3; registry: the
  marketplace repository's `docs/upstream/mattpocock-skills.md`.)

## [0.3.4]

### Added

- **`/testing:diagnose`'s fix step now constrains the direction of the fix, not just its size.** The
  loop's Step 3 bullets bounded scope but never said which side of the red signal to change, leaving
  "edit the assertion until it passes" as the shortest path to green. The step now leads with fixing
  the production code, and requires a deliberate, stated correction when the test itself is the thing
  that is wrong.
- **The e2e prerequisite hard-fail says why workarounds are barred** — a substitute path yields
  unverified pass/fail results, which defeats the point of live verification. Added at both the
  `SKILL.md` and `context/e2e.md` statements of the rule.

### Changed

- **The prerequisite headings drop their `MANDATORY` tag** in `/testing:run-e2e`; the STOP-and-report
  behavior described immediately beneath each already makes the requirement unambiguous.

## [0.3.3]

### Changed

- **`/testing:run-e2e`'s handoff no longer delegates surface verification to the bundled `/verify`.**
  Claude Code v2.1.215 made `/verify` user-invoked only, so **from v2.1.215** "delegate surface
  verification to it first" named a surface the skill cannot invoke. The handoff now suggests the
  user run it and consume its findings, and carries the v2.1.215 scope rather than stating the
  restriction flatly — on 2.1.145–2.1.214 `/verify` is still model-invocable. The instruction itself
  is uniform across the window, because suggesting is correct on every version `/verify` exists on.
  The orchestrator path was already the fallback and is unchanged. The `≥ 2.1.145` availability floor
  is a separate axis, unchanged and re-verified 2026-08-02.

## [0.3.2]

### Changed

- **Doc reference updated for the `config-cascade` seam rename (#1188).** The layering-contract links in
  `README.md`, `run-e2e/SKILL.md`, and `run-e2e/context/e2e-config.md` now point at
  `docs/conventions/config-cascade/` (formerly `consumer-config-layering`). No behavior change.

## [0.3.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.3.0]

### Added

- `/testing:run-e2e` gains a consumer-project config surface, `.claude/testing/e2e.md`,
  with two per-key-override keys: `recording` (`video | gif | off`, default `off`) and
  `browser_mode` (`headed | headless`, default `headless`). Defaults preserve current
  behavior. Keys, defaults, and precedence live in the skill's bundled
  `run-e2e/context/e2e-config.md`; layers resolve per the marketplace
  consumer-config-layering convention.
- Optional recording evidence tier in the E2E evidence contract — video via the
  playwright CLI for long flows, GIF via `gif_creator` for short demos — plus a
  session-artifacts record (recording path, session ID, transcript pointer). Screenshots
  remain the evidence floor.

### Changed

- `/testing:run-e2e` now resolves the config surface before driving — anchors at the
  repo root, merges all three layers per key, and reports which layer supplied each
  effective value — then passes the resolved `browser_mode` and `recording` values
  through to the executor.
- The drive loop is delegated to a subagent; the orchestrator consumes evidence paths
  only.
- The prerequisite hard-fail keeps its STOP and now also writes a structured
  verification-environment gap report (what is missing, what the operator must provide)
  to the run's evidence output.
- Verification delegates to the bundled `/verify` command first when it is present
  (Claude Code ≥2.1.145); the orchestrator fallback is unchanged when it is absent.
- Eval #1 updated to assert the prerequisite hard-fail STOP plus the structured gap
  report.

## [0.2.5]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.4]

### Changed

- Reworded two `files: []` (context-free) eval expectations to credit a consumer-agnostic inspect/ask
  path equally with a doc-permitted default, rather than pre-committing to one answer. The `diagnose`
  fixture-collision case (case 1) now grades recognition of the process-global singleton / shared-state
  root cause plus inspecting the project's fixture layout or asking for its documented convention, with
  the specific mechanism demoted to a non-exhaustive example instead of the asserted answer. The `write`
  shared-library placement case (case 2) now grades the single-project-vs-cross-project judgment and
  deferral to the project's documented convention, keeping the create-a-test-project decision while
  dropping the co-location pre-commitment (`context/organize.md` permits co-location for single-project
  integration tests and centralization for cross-project ones). Eval expectations only; no skill
  behavior, routing, or context files changed.

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
