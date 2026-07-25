# Changelog

All notable changes to the `rate-limit-guard` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.1]

### Added

- **`hook::jq_fields` in the shared hook lib (#1345).** Extracts N jq fields in ONE `jq` process
  instead of N `printf | jq | tr` pipelines, returning them in `HOOK_JQ_FIELDS`. Values are joined on
  U+001E, which jq strips from each value first so payload text can never shift field alignment. This
  plugin's own hooks do not call it yet; it arrives with the shared-lib sync.

### Fixed

- **Two process spawns removed from every hook invocation (#1345).** `hook::buffer_stdin` stripped CR
  with `$(printf '%s' "$input" | tr -d '\r')`; it now uses parameter expansion. On Windows, where
  `fork` emulation makes each spawn cost hundreds of milliseconds, that command substitution was the
  largest fixed cost paid by every hook in this plugin on every matching tool call. The buffered
  payload — including the trailing-newline trim a command substitution performed implicitly — is
  byte-identical. Carried in via `scripts/sync-hook-utils.sh`; no behavior of this plugin changed.

## [0.2.0]

### Changed

- **The single-account-per-machine text is repointed at its owner.** This reader contract
  carried its own copy of the assumption while naming loop-lane §6 as its owner, so the copy would
  contradict §6 the moment §6 moved — which it now has: §6 reframes the assumption as a known gap.
  §6 owns the framing; what stays here cites it rather than asserting it independently. What is
  local to the guard stays local: the writer already
  forward-passes any top-level `account`-matching key, so an identity field costs no plugin change
  the release one appears. The account-identity design itself is `TODO(#1218)`.

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
