# Changelog

All notable changes to the `context-guard` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-24

### Added

- `scripts/statusline-tee.sh` — transparent statusline wrapper teeing `captured_at` +
  `session_id` + the verbatim `context_window` object to the per-session snapshot path
  `~/.claude/context-guard/context/<session_id>.json` (atomic temp+rename, Windows rename retry,
  jq-missing visible degrade, session-id sanitization, 14-day sibling pruning, standalone mode).
- `scripts/context-zone.sh` — fail-open zone resolver printing `smart` / `acceptable` / `dumb` /
  `unknown`; shipped default bands 50/75 with `~/.claude/context-guard/zones.json` as the
  machine-scope override; malformed zones fall back visibly.
- `reference/reader-contract.md` — consumer contract: snapshot path pattern, file shape,
  10-minute staleness rule, fail-open capability table, zones.json shape, `${CLAUDE_SESSION_ID}`
  discovery + fallback, inline-floor byte-identity rule, zone-is-not-a-compaction-indicator rule.
- `skills/setup` — `check` (read-only: jq, wiring with stale-cache-path detection, live-session
  snapshot freshness, zones state, printed operator edit) and `apply` (seeds/refreshes zones.json
  only), with evals.
- Black-box test harnesses for both scripts (sandboxed `HOME`, 80 assertions total).
