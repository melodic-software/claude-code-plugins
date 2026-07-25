# Changelog

All notable changes to the `rate-limit-guard` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.1]

### Changed

- **Setup states the accurate reason it is check-only.** It claimed the check-only carve-out as
  scoped to plugins whose entire configuration is native `userConfig` — a premise this plugin does
  not meet, since its statusline wiring lives in the user's own `settings.json`. The conclusion was
  right and the justification was not. The Purpose now names the condition that actually holds: no
  writable owned artifact anywhere in the surface. Each of the three surfaces is enumerated with why
  setup cannot write it, and the machine files under `~/.claude/rate-limit-guard/` are called out as
  runtime-owned plugin data rather than a fourth, operator-editable surface — which is what
  distinguishes a plugin that must not invent an `apply` from one that owes a narrow one.
- **Setup documents the headless reconfiguration route beside the interactive one.** The kill
  switch's only route was `/plugin configure rate-limit-guard`, leaving a headless consumer with
  nothing; the obvious guess, re-running `claude plugin install --config`, silently no-ops on an
  installed plugin. The fresh-install-only behavior and the uninstall-then-reinstall route it forces
  are now stated where the reconfiguration guidance lives.
- **The reader contract no longer cites a repository-level document.** Its no-`experimental.monitors`
  note pointed at `docs/PLUGIN-PHILOSOPHY.md`, a path that does not exist in an installed plugin's
  cache — where this contract is read by sibling-plugin consumers, the citation resolves to nothing.
  The note now states the reason a reader needs (Monitors is experimental; this plugin takes no
  dependency on one until it stabilizes) without a pointer that cannot be followed.

## [0.1.0]

### Added

- **Statusline tee wrapper** (`scripts/statusline-tee.sh`): transparent passthrough around the
  user's statusline command that atomically tees `rate_limits`, `captured_at`, and every
  session-distinguishing stdin field to the fixed contract path
  `~/.claude/rate-limit-guard/rate-limits.json` (temp file + rename; Windows locked-target renames
  retried then skipped without ever affecting the statusline pipeline). Standalone minimal
  statusline when invoked with no wrapped command; visible notice instead of a silent skip when
  `jq` is absent.
- **StopFailure detection hook** (`hooks/record-rate-limit-stop.sh`, matcher `rate_limit`):
  side-effect-only, jq-free reactive fallback appending bounded JSONL detection records to
  `~/.claude/rate-limit-guard/stop-events.jsonl`. Kill switch via the `rate_limit_guard_enabled`
  `userConfig` boolean.
- **Reader contract** (`reference/reader-contract.md`): the operable floor consumers inline —
  fixed tee path, 90%-of-either-window pause threshold, tripped-window `resets_at` pause end
  (later `resets_at` only when both windows trip), 10-minute staleness rule with mandatory
  session-Monitor arming while paused, capability-detect fail-open (absent/absurd values →
  reactive-only), and drain-then-pause.
- **Check-only `setup` skill**: verifies `jq`, tee freshness (distinguishing "no statusline
  configured" from "wrapper missing" and from a cache path gone stale after a plugin update), and
  the hook kill switch; prints the exact `settings.json` statusline edit for the operator — the
  skill never mutates user settings.
