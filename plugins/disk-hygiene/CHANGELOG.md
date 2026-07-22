# Changelog

All notable changes to the `disk-hygiene` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.1]

### Fixed

- **A non-OS volume root (e.g. a Windows Dev Drive) is no longer blanket-rejected (#984).** A
  whole-volume root was refused purely structurally — on Windows by the mount-point gate (every drive
  letter is `os.path.ismount` True), backed by a `parent == root` filesystem-root check — with no
  reasoning about the volume's purpose, blocking a legitimate non-OS volume. Root classification is
  now reasoned: an OS-managed root (the OS drive holding an existing Windows install / `Program Files`
  / `ProgramData`, or `/` holding `/bin`, `/etc`, …) is still denied, while a non-OS volume root — a
  drive root carrying only the per-volume metadata every volume has (`System Volume Information`,
  `$Recycle.Bin`) and no OS-install marker — is now a valid target. The target-level mount rejection
  is scoped to non-root mount points, so nested and bind mounts stay hard-blocked; per-entry
  mount/OS-managed/VCS/identity protections and the preview + per-tier approval gate are unchanged.
  Scan and preview share one unverified → OS-managed → non-root-mount target-check ordering. A
  now-valid non-OS volume root composes with the large-target scan gate (0.5.0): it is a known-large
  root (`large_scan_reasons` reason `non-os-volume-root`), so an unbounded whole-volume walk returns
  `large-target-confirmation-required` unless bounded with `--max-depth` or confirmed with
  `--confirmed-large-scan`.

## [0.5.0]

### Added

- **Engine-level large-target scan gate.** A `scan` whose target resolves to the user home directory
  now returns `large-target-confirmation-required` (after a cheap top-level probe, no full walk)
  unless it carries `--max-depth` or the new `--confirmed-large-scan` flag, backing the former
  prompt-only `--max-depth 1` convention with a deterministic backstop so a forgotten bound cannot
  become an accidental unbounded whole-home walk. The Bash guard accepts the valueless
  `--confirmed-large-scan` in the exact scan shape.

## [0.4.7]

### Fixed

- **The `clean` skill now hands off git worktree checkouts to `/source-control:worktree`.** An audit
  of a repos root containing worktree checkouts (e.g. under `.worktrees/`) inventories each checkout
  and protects its tracked content and `.git` metadata, but the skill named no next step for the
  worktree lifecycle it does not own. The boundary list (and the README relationship list) now point
  at `/source-control:worktree status`/`cleanup` (if installed) — run from the checkout's own main
  repository, since those actions manage the current repository's worktrees and take no target —
  extending the existing managed-state → named-handoff pattern. Discoverability only; no engine or
  safety behavior change. (#986)

## [0.4.6]

### Changed

- **Test isolation only — no runtime behavior change.** The `run_guard_powershell` helper in
  `test_hygiene.py` — the enabled-PowerShell sibling of the three helpers sealed in 0.4.5 — carried
  the identical unsealed seam: it mocked `os.environ` to drive the kill switch but left `sys.argv`
  unpatched, so an ambient `--disk-hygiene-enabled` flag in the real test-runner invocation could
  override the env-var mock the test intends to exercise. It now patches `guard.sys.argv` to a
  clean, flag-free argv alongside its existing environment mock — matching the pattern the other
  four `run_guard*` helpers use — so the environment variable stays the sole channel under test.
  This completes the seam-sealing left out of 0.4.5 for scope; standard `unittest`/`pytest`
  invocations never produced such argv, so it seals latent fragility rather than a live failure.

## [0.4.5]

### Changed

- **Test isolation only — no runtime behavior change.** The `run_guard`, `run_guard_disabled`, and
  `run_guard_powershell_disabled` helpers in `test_hygiene.py` mocked `os.environ` to exercise the
  kill switch but left `sys.argv` unpatched. Since the guard reads `--disk-hygiene-enabled` from
  `sys.argv[1:]` before the environment fallback, a test runner whose real invocation argv happened
  to carry that flag could override the env-var mock and flip an expected `deny` to `ask`. Each
  helper now patches `guard.sys.argv` to a clean, flag-free argv alongside its existing environment
  mock — matching the pattern the `run_guard_enabled_argv` helper already established — so the
  environment variable stays the sole channel under test. Standard `unittest`/`pytest` invocations
  never produced such argv, so this seals latent fragility rather than a live failure.

## [0.4.4]

### Fixed

- **The `disk_hygiene_enabled` kill switch now actually blocks deletions in audit-only mode.**
  Setting `disk_hygiene_enabled=false` (audit-only mode) failed to prevent deletions in two
  independent ways, both fixed here.
  - The PowerShell lane never consulted the kill switch: `destructive_guard.py` routed `PowerShell`
    calls to `powershell_decision` and returned before the enabled gate was computed, so flagged
    deletion spellings (`Remove-Item`, `rm`, `del`, `::Delete`, recycle-bin calls) still returned
    `ask` — and could be approved — even with execution disabled. The enabled gate is now resolved
    before the tool-name branch and threaded into `powershell_decision`, which denies flagged
    deletions in audit-only mode and only prompts (`ask`) when execution is enabled.
  - The kill switch was inert under the env-injection failure: the guard read
    `CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED` from the hook process environment and defaulted to
    enabled when absent, but the runtime does not inject plugin env vars into a skill-frontmatter
    hook's environment, so a configured `false` was silently overridden to enabled. The `clean`
    skill's hook now passes the configured value as a runtime-substituted
    `--disk-hygiene-enabled ${user_config.disk_hygiene_enabled}` argument — inline placeholder
    substitution resolves in exec-form hook `args` where environment injection does not — and the
    guard reads the kill switch from that argument, honoring the environment variable only as a
    fallback. When no channel supplies a value the guard still fails safe to enabled (guard active,
    every mutation gated behind the final human prompt). This mirrors the `--authorized-data-root`
    argv mechanism.

## [0.4.3]

### Fixed

- **The `clean` skill's destructive-safety guard now launches via a resolvable `python3`.** The
  PreToolUse hook ran in exec form via the unqualified interpreter `python`, which stock macOS and
  many Linux distros do not ship (only `python3`). Because Claude Code treats a failed hook launch
  as a non-blocking error, an unresolvable `python` fails the guard open — `rm -rf`, engine `apply`,
  and other destructive shapes stop being intercepted on the very POSIX hosts the safety model
  relies on — and a legacy `python` 2.x resolving first would crash the guard on modern syntax. The
  hook now names `python3`. A new regression test (`test_skill_hook_interpreter_is_python3_and_resolves`)
  locks the config at `python3` and probes that a runnable `python3` reports a 3.11+ interpreter.
  Enforcement remains bounded by resolution: on a host without a resolvable `python3` the launch
  still fails open on the manual PowerShell deletion lane (engine `apply` is already unsupported on
  Windows/macOS), so the per-path human approval that lane already requires and the consumer's
  baseline permission policy stay the backstop, and `/disk-hygiene:setup check` reports interpreter
  resolution. (#380)

## [0.4.2]

### Fixed

- **The `clean` skill's step 2 now defines "suspicious" for home-directory targets.** A prior
  fix covered the `tmp_*` hint-glob gap but left two findings open: an unhinted agent-session
  status file has no shared name shape to glob, and SKILL.md never said what "suspicious"
  meant for an unhinted entry. Both are the same gap: the scan snapshot already records every
  walked entry with a possibly-empty `hints` list, so the data was always there, just never
  triaged. Step 2 now instructs the model to treat any loose root-level entry at a user-home
  target that is not in `protected_exact_names` and does not match a recognizable app/config
  convention as suspicious, closing the triage gap without inventing a fabricated
  baseline-policy.json glob for a naming pattern the evidence doesn't support. (#287)

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
