# Changelog

All notable changes to the `verification` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.5]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.4]

### Changed

- Presence-gated the `dotnet-*`/`cloudflare` marketplace-skill evidence pointers in the `measure`
  contexts, superseding 0.2.3's "unchanged" note. `metrics` and `performance` now carry the
  `## Marketplace plugin skills (invoke only when installed)` guard heading (matching the `testing`
  plugin's gated lists) plus a lead-in that frames the `dotnet-*` skills as .NET-only and
  `cloudflare:web-perf` as web-frontend-only, each invoked only when its plugin is installed and
  otherwise falling back to the project's own tooling — the generic complexity/coverage or
  benchmark/profiling harness where that fits, with a tailored per-bullet fallback where the
  evidence type differs (query logging / database profiling / ORM diagnostics for EF-query
  analysis, a test-quality analyzer or test-smell review checklist for test-quality analysis,
  web-vitals tooling for Core Web Vitals). This removes the bare unguarded cross-plugin
  reference `docs/PLUGIN-PHILOSOPHY.md` names as a defect; no hard dependencies added, every
  reference stays optional.

## [0.2.3]

### Changed

- Neutralized the .NET/C#/PowerShell-flavored illustrative examples in the
  stack-agnostic `confirm` and `measure` skills so a non-.NET consumer isn't
  handed a stack-specific illustration as the universal path: the reproduction-test
  example uses a generic descriptive name and failure, and the metric/perf
  "how to check" cells count import/dependency declarations and point to "your
  test runner"/"your benchmark harness" instead of `using`/`ProjectReference`/
  `dotnet test`/BenchmarkDotNet. The Unix-shell `wc -l` line-count assumption is
  now stated shell-neutrally (`wc -l` on POSIX/Git Bash, `Measure-Object -Line`
  in PowerShell), honoring the cross-platform "never assume Bash" contract. The
  named marketplace-plugin evidence pointers (`dotnet-*`) are unchanged.

## [0.2.2]

### Changed

- Cross-plugin invocation tokens updated for the fleet naming-grammar wave
  (`/testing:run-e2e`); behavior unchanged.

## [0.2.1]

### Changed

- **Freshness rider on the bundled `/verify` + `/run` availability claim**
  (fleet conformance wave). The ≥ 2.1.145 floor is re-verified against the
  official bundled-skills docs and now carries a verified-date + link.

## [0.2.0]

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` states
  baselines and raw captures are checkout-local, and `/verification:measure` writes distilled
  values only into `PLAN.md` — never a memory-slice capture path (pointer discipline).

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
  ecosystem-native commands), and live-app verification prefers `/testing:run-e2e` when the `testing` plugin
  is installed (else bundled `/verify` + `/run` or a manual orchestrator launch) — no hard dependencies.
