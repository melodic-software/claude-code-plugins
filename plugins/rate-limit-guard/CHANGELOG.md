# Changelog

All notable changes to the `rate-limit-guard` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0] - 2026-07-24

### Added

- `scripts/statusline-shim.sh` — the durable statusline wiring target. The operator wires the shim
  once; it resolves the newest installed `statusline-tee.sh` at run time (newest by mtime across
  marketplaces, skipping transient `temp_*` cache clones), so plugin version bumps never require
  re-wiring. Transparent in every path: no tee installed degrades to running the wrapped statusline
  alone, and a wired-standalone shim prints one diagnostic line instead of leaving a blank bar.
  Pure Bash builtins — no subprocess on the statusline path. Black-box test harness with 25
  assertions, including the two-shim chaining case.
- **`setup apply`** — the skill is no longer check-only. `apply` installs the shim (byte-identical
  copy to `~/.claude/rate-limit-guard/bin/statusline-shim.sh`, idempotent, inert until the operator
  wires it) and writes nothing else; `settings.json` stays the operator's to edit.

### Changed

- **Wiring is now the shim, not the tee** (breaking for the printed wiring only; existing wiring
  keeps working until the next update). `setup check` prints
  `bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh …`, gained an installed-shim state check,
  and reclassifies a statusline wired to a version-pinned plugin-cache path as LEGACY wiring
  regardless of whether that file currently exists — the old state only flagged a missing file.
  Rationale: `${CLAUDE_PLUGIN_ROOT}` is version-pinned and the old version directory is pruned
  ~14 days after an update, so cache-path wiring stops teeing at the next bump and then breaks the
  operator's whole statusline (`bash <missing>` → 127).
- `setup check` prints the sibling-composition wiring when `context-guard` is also installed, and
  states the measured per-tee refresh cost (~0.6–0.9 s on Windows/Git Bash, spawn-bound).

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
