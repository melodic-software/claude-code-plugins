# Changelog

All notable changes to the `ai-briefing` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.2]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  applied to the other affected plugins in this release wave.

## [0.6.1]

### Changed

- **Setup now documents how to change `active_profile`, not only how it is read.** The skill
  resolved the key and reported the profile path, but named no route to a different stored value,
  so a consumer whose configured profile was wrong for the repository had nothing to act on and the
  `--profile` override looked like the only lever. `check` step 1 now names all three: the
  interactive `/plugin configure ai-briefing` flow, which is the only surface that changes the
  stored value; the headless `--config` path, with the caveat that it seeds on a fresh install only
  and is ignored once installed, so reconfiguring headlessly is uninstall-then-reinstall; and the
  per-run `--profile` for a one-off that should not touch stored config. This skill still never
  writes `pluginConfigs`.

## [0.6.0]

### Changed

- **Setup adopts the uniform `check` / `apply` contract.** The read-only `check`
  action verifies the resolved profile, `sources.md`, optional overlays, and the
  build-toolchain state (PASS/FAIL/INFO); `apply` scaffolds the profile. The
  verify-plus-install fusion behind `--with-build-deps` is split into an explicit
  `apply install-build-deps` subaction that runs the same locked build-toolchain
  install flow unchanged. `--profile <name>` still selects the profile for either
  action. README invocation references updated to the subaction.

## [0.5.2]

### Changed

- **Freshness rider on the Playwright environment matrix** (fleet conformance
  wave: volatile platform facts carry a verified-date + official link). The
  README matrix is dated and re-verified against Playwright's system
  requirements; the setup skill no longer restates the version matrix and
  defers to the linked page as authoritative.

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
