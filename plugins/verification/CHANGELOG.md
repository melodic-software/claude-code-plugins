# Changelog

All notable changes to the `verification` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.1]

### Changed

- References to the renamed `/toolchain:build` skill now invoke `/toolchain:check` (toolchain 0.2.0 breaking rename). Version bumped so existing installs pick up the rewritten prompts.

## [0.1.0]

### Added

- Initial release — two skills extracted and renamed from the `implementation` plugin's `verify-*`
  skills: `/verification:confirm` (was `verify-changes` — the mechanical prerequisite gate then
  intent-match + evidence + verdict) and `/verification:measure` (was `verify-improvement` —
  baseline/compare measurable-improvement verification). Skill trigger phrases and evals are preserved;
  only the namespace and leaf names changed.
- Bundled reference: the plugin-local `reference/topic-docs.md` binding (verification manifests and
  baselines placement) and the byte-identical `reference/artifact-protocol.md` lifecycle profile shared
  across participating lifecycle plugins.
- Cross-plugin delegation degrades gracefully: the Stage-1 mechanical pass delegates to
  `/toolchain:build` and `/toolchain:lint` when the `toolchain` plugin is installed (else the project's
  ecosystem-native commands), and live-app verification prefers `/testing:e2e` when the `testing` plugin
  is installed (else bundled `/verify` + `/run` or a manual orchestrator launch) — no hard dependencies.
