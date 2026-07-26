# Changelog

All notable changes to the `desktop-notification` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.4]

### Fixed

- **Shared `hook-utils.sh`: a bare or trailing unquoted `NAME=value` Bash
  command no longer leaks the assignment value into the privacy-safe
  telemetry/audit subject.** `hook::extract_bash_subject` stripped a leading
  `VAR=value` prefix only when a following command word consumed it, so a
  command whose LAST token was an unquoted assignment (e.g. `TOKEN=ghp_…`)
  survived to the subject and emitted `Bash:TOKEN=ghp_…` into
  `hook-events.jsonl` and any wired `HOOK_TELEMETRY_SINK`. A resolved token
  still shaped like a shell assignment now bails to the bare `Bash` subject,
  matching the existing quoted-value bail (`VAR=x cmd` still reduces to
  `Bash:cmd`). Synced from `lib/hook-utils.sh`; the subject is
  telemetry/audit-only, so no guard or formatter block/allow behavior changes.

## [0.5.3]

### Fixed

- C1 fd1-leak detector in `desktop-notification.test.sh`: the threshold that was
  supposed to widen the slow-sink margin (`#751`, closing `#448`) could not actually
  widen it — `THRESHOLD_MS` was derived as `SINK_SLEEP * 1000 / 2`, so widening
  `SINK_SLEEP` widened the threshold by the same ratio and left the margin unchanged
  by construction. `#448` was reopened after this reproduced on clean `main`
  (delta=3697ms false-fail, no leak present). `THRESHOLD_MS` now asserts the real
  invariant directly — sink-sleep-minus-a-safety-margin, not half the sleep — and
  `SINK_SLEEP` is widened from 6s to 8s (still comfortably under the 10s ceiling
  documented against EXIT-cleanup file-locking on Windows) for more absolute
  separation between ambient noise and the leak signal. The safety margin is sized so
  BOTH sides of the threshold clear the 2150ms of worst observed no-leak noise, not
  just the noise side: a threshold too close to the leak signal lets a load shift that
  inflates every baseline sample and then subsides before the slow run subtract real
  leak signal out of the delta, and the detector reports no leak. At `SINK_SLEEP`=8s
  and a 3000ms margin the threshold sits at 5000ms — 2850ms of noise-side margin,
  3000ms of leak-side margin. Verified on Windows Git Bash: 10 consecutive clean runs,
  40 runs under heavy concurrent load (worst observed no-leak delta ~1590ms), and a
  deliberately reintroduced fd1 leak still fails the case (observed delta ~8065ms).

## [0.5.2]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.
  The recipe also now requires the reinstall to re-supply **every** key whose value should
  stay non-default, not only the key being changed: uninstalling drops the stored
  `pluginConfigs` entry, so an omitted key silently falls back to its manifest default.
  Record the current values before uninstalling.

## [0.5.1]

### Changed

- Sync of the shared `hook-utils.sh`: the git-option parser distinguishes `--config-env`
  (an env-var name) from `-c`/`--config` (an inline value), and a `--config-env` alias for
  a guarded subcommand is refused by shape rather than by resolving the environment
  variable's value (`#740`). No behavior change for this plugin — it does not inspect git
  config values; shipped so consumers receive the shared library update.

## [0.5.0]

### Added

- **`statusMessage` declared on the hook's `hooks.json` handler** (hook-observability
  convention, `docs/conventions/hook-observability/`): a spinner label ("Sending
  desktop notification...") now shows while the hook runs. Config-only — no
  runtime behavior change.

## [0.4.3]

### Changed

- C1 fd1-leak detector in `desktop-notification.test.sh` now measures the slow-sink
  invariant differentially — a fast-sink baseline run captures the machine's current
  process-spawn overhead, and the slow-sink run's excess over it isolates the leak
  signal — instead of asserting a fixed `< 2000ms` wall-clock bound. On Windows Git
  Bash the hook's own spawn overhead (~1.6s solo, 4-10s under parallel-suite load)
  left the fixed bound with a thin-to-negative margin and false-failed even with no
  leak. The differential form cancels ambient overhead, so the check holds under load
  while still catching a real fd1 leak (the sink's whole sleep lands in the delta).
  The baseline is the minimum of several fast runs so that one unluckily-descheduled
  baseline sample cannot inflate the subtracted overhead and let a real leak pass as a
  false-negative under load; an inflated *slow* sample only re-fails a green run
  (fail-safe), so only the baseline is sampled repeatedly.

## [0.4.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.4.1]

### Changed

- Hook stdin is read via the shared `hook::buffer_stdin` helper (bounded `read -t`,
  default 2s) instead of a bare `cat`, so a Windows Win32-pipe late-EOF stall can no
  longer hang the hook indefinitely. Empty or timed-out stdin exits as a skip, matching
  the existing empty-payload behavior.

## [0.4.0]

### Added

- **Uniform-contract `setup` skill** (fleet conformance wave). `/desktop-notification:setup
  check` reads the hook scripts as the single source of truth and probes Bash version, `jq`,
  and — for the current OS only — the `os_toast` channel dependency (Linux `notify-send`;
  macOS built-in `osascript`; Windows terminal-only), then reports the four channel toggles'
  effective values. `apply` is guidance-and-verify with no write path: it points at the
  README install steps and `/plugin configure` for a muted toggle, installs nothing, and
  re-runs the probe after any system-tool remediation.

## [0.3.2]

### Changed

- **Freshness rider on the channel table** (fleet conformance wave). The
  `terminalSequence` / Claude Code v2.1.141+ claim is re-verified against the
  Claude Code changelog and dated, with links to the changelog and the hooks
  reference.

## [0.3.1]

### Changed

- Shared `hook-utils.sh` resynced from the repository library (no behavior
  change in this plugin's hook).

## [0.3.0]

### Changed

- **Missing jq now skips visibly** (prerequisite-visibility wave; doctrine: a
  silently skipped feature is a defect). Without `jq` the hook can neither
  classify the notification nor emit its terminal sequence, so it now surfaces
  a once-per-session `systemMessage` notice (the Notification event has no
  `additionalContext` channel) instead of silently dropping every
  notification. Notice dedup state lives under
  `${CLAUDE_PLUGIN_DATA}/skip-notices`.
- Shared `hook-utils.sh` resynced with the new prerequisite-visibility helpers
  (jq-free notice emitters, once-per-session gate, jq gate).
- README now states the jq absence behavior and the Bash (Git Bash on native
  Windows) hook runtime.

## [0.2.0]

### Changed

- **Master toggle and per-channel mutes migrated to native `userConfig`** (the
  fleet-wide kill-switch doctrine ruling). The whole-hook switch is now the
  `desktop_notification_enabled` boolean and each channel its own
  `desktop_notification_<channel>_enabled` boolean (default `true`), read by the
  hook through the native `CLAUDE_PLUGIN_OPTION_<KEY>` hook-process mirror.
  Configure interactively with `/plugin configure desktop-notification` or headless via
  `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_DESKTOP_NOTIFICATION_*` environment variables are
  retired and no longer read. A consumer that set any of
  these in a settings `env` block must re-express the value as the matching
  `userConfig` option. Zero-config behavior is unchanged (all channels on, same
  defaults). The `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is unaffected.
