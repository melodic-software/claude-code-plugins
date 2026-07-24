# Changelog

All notable changes to the `rate-limit-guard` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Changed

- **The single-account-per-machine limitation is replaced by the loop-lane convention's attribution
  rule, cited rather than restated.** This reader contract carried its own copy of the assumption
  while naming loop-lane §6 as its owner — so when §6 changed, the copy contradicted the contract it
  cited. The three attribution cases now live only in §6; this document states what is local to the
  guard, namely that the platform schema exposes no account identifier today and that the writer
  already forward-passes any top-level `account`-matching key, so the identifier cases go live with
  no plugin change the release one appears.

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
