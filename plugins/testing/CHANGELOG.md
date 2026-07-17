# Changelog

All notable changes to the `testing` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
