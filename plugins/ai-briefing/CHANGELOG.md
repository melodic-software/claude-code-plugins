# Changelog

All notable changes to the `ai-briefing` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.1]

### Changed

- README states the POSIX-shell requirement of the `setup --with-build-deps`
  install step with its Windows path (Git Bash; the script's platform gate
  already accepts MINGW/MSYS/CYGWIN) — cross-platform declaration wave. The
  Node build pipeline is unchanged and remains shell-free.

## [0.5.0]

### Changed

- Renamed the `ai-briefing` skill → `generate`. Update any `/ai-briefing:ai-briefing` invocations to
  `/ai-briefing:generate`; the plugin ID (`ai-briefing`) is unchanged, only the skill's leaf name
  moved. `scripts/validate-plugin-contracts.mjs` retargeted to `skills/generate` for its
  active-profile and build-root checks.

## [0.4.0]

### Added

- Engine behavioral evals in `skills/ai-briefing/evals/evals.json`, covering: `retro` action
  routing and per-item acted/noted/skipped scoring against an archived briefing; `search`
  action full-text matching across archives; markdown-only output when `--format slides`/`html`
  is not explicitly requested; merge-not-append behavior when folding newly collected items into
  an already-open briefing window; the apolitical filter, pragmatic-use ranking lens, and
  profile-provided impact-lens annotation (via `references/audience-defaults.md`); and graceful,
  visibly-surfaced degradation when an optional collection source is unreachable, without
  aborting the run.
- Three supporting fixtures under `skills/ai-briefing/evals/fixtures/`: `archive-sample.md`,
  `open-window-sample.md`, and `candidate-items-sample.md` — neutral, synthetic AI-industry
  content with no real company, person, or consumer-specific references.
