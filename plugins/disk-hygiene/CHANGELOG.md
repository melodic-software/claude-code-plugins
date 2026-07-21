# Changelog

All notable changes to the `disk-hygiene` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.1]

### Fixed

- **The skill-frontmatter guard now receives its authorized data root.**
  `destructive_guard.py` read the authoritative data root only from the
  `CLAUDE_PLUGIN_DATA` environment variable, which the runtime does not inject
  into a skill-frontmatter hook's process environment. As a result `--data-root`
  never validated and the `scan`/`preview`/`apply` engine lane failed closed on
  every guarded invocation, on all platforms. The `clean` skill's hook now
  passes the root as a runtime-substituted `--authorized-data-root
  ${CLAUDE_PLUGIN_DATA}` argument — inline placeholder substitution resolves in
  hook arguments where environment injection does not — and the guard reads its
  authority from that argument, honoring `CLAUDE_PLUGIN_DATA` only as a fallback.
  The security property is unchanged: the authority is a runtime-substituted
  value the model cannot forge, validated against the model-supplied
  `--data-root`. The unsubstituted-placeholder fallback matches only the exact
  `${CLAUDE_PLUGIN_DATA}` token, so a real data-root path that merely contains
  the `${` sequence is preserved as the authority instead of being discarded.

## [0.4.0]

### Added

- **`/disk-hygiene:setup` skill on the uniform contract** (fleet conformance
  wave, dim 8). `check` reads the clean skill's bundled scripts as the source
  of truth and probes Python 3.11+, conditional Git, the current OS family's
  documented lane (Linux `lsof` and macOS audit-only reported as INFO), and
  the effective `disk_hygiene_enabled` toggle. `apply` is guidance-only with
  no write path; toggle guidance states `--config`'s fresh-install-only
  semantics. A disabled toggle downgrades prerequisite FAILs to INFO.

## [0.3.0]

Fixes driven by a live Windows user-profile audit where the engine was unusable through its
sanctioned lane and the guard's protections did not cover the platform's primary shell.

### Added

- `--data-root` on scan, preview, and apply. The Bash guard validates the value against the
  `CLAUDE_PLUGIN_DATA` its own hook process received (the runtime exports it to hook processes but
  not to shell tool subprocesses, so the engine could previously never find its generated-state
  root through the guarded lane) and discloses the authorized value in denial guidance alongside
  the interpreter path. Absent hook authority the flag fails closed; the environment variable
  remains honored as a fallback.
- `--max-depth` bounded scans. Directories at the cutoff are recorded in `truncated_paths`,
  reported as coverage gaps, and blocked from plans by a new `truncated-not-inventoried` preview
  blocker. This makes a profile-root audit possible: the previous all-or-nothing walk exceeded the
  250k entry cap on any real home directory before reaching a single loose file.
- PowerShell guard lane (matcher now `Bash|PowerShell`): engine invocations from PowerShell are
  hard-denied (Bash stays the only engine lane), and known deletion spellings / .NET Delete calls
  surface a final human permission prompt instead of executing silently. Read-only support work
  passes through untouched.
- Documented unsupported-platform manual handoff: on Windows/macOS, after the same exact-list
  human approval as the engine lane, removal proceeds manually with per-path revalidation and
  reversible (Recycle Bin / Trash) deletion preferred.
- Scan progress heartbeat to stderr every 25k entries; the entry-cap error now suggests
  `--max-depth`.
- `os_autoclean` advisory is computed before the walk and included in scan failure payloads, so a
  capped profile scan still surfaces the Storage Sense / systemd-tmpfiles recommendation.
- Baseline hints for `tmp_*` (medium ceiling) and `scratch*` (low ceiling) artifacts.

### Changed

- Generated-state error messages name the `--data-root`/`CLAUDE_PLUGIN_DATA` pair instead of the
  environment variable alone.
- **Execution kill switch migrated to native `userConfig`** (the fleet-wide kill-switch
  doctrine ruling): the `disk_hygiene_enabled` boolean (default `true`) now gates the clean
  skill's execution tiers, read by the skill-scoped guard through the native
  `CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED` hook-process mirror. Configure with
  `/plugin configure disk-hygiene` or `claude plugin install --config`.
- **BREAKING:** the `HOOK_DISK_HYGIENE_ENABLED` environment variable is retired and no
  longer read. Zero-config behavior is unchanged (execution allowed).
