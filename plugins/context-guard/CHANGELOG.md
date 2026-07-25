# Changelog

All notable changes to the `context-guard` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-07-24

### Changed

- **`/context-guard:setup apply reset` is renamed `apply defaults`.** The setup contract reserves
  `reset` for teardown-plus-apply — converging to the *absence* of the plugin's config, then
  reconfiguring. This action does the opposite: it converges forward, setting both recognized band
  keys to the shipped defaults while preserving every unrecognized key and never removing the file.
  An operator reading `reset` against the contract's meaning would expect their custom keys gone.
  The argument now says what it does. Callers passing the old token get no silent fallback — there
  is no compatibility alias, per the contract's clean-break stance.
- **The setup skill states the reason it owes an `apply` at all.** It cited the "narrow-write
  carve-out" and a repository-level document, which named the shape without naming the condition
  that selects it. The Purpose now says it directly: the statusline surface and the `jq`
  prerequisite are unwritable, but this plugin also owns exactly one writable artifact —
  `zones.json`, whose schema it defines and whose values the operator may edit — and one writable
  owned artifact is what obliges a narrow `apply` rather than a check-only setup.

### Fixed

- **The reader contract no longer cites a repository-level document.** Its no-`experimental.monitors`
  note pointed at `docs/PLUGIN-PHILOSOPHY.md`, a path absent from an installed plugin's cache —
  which is exactly where sibling-plugin consumers read this contract, so the citation resolved to
  nothing for its real audience. The note now states the reason itself (Monitors is experimental;
  this plugin takes no dependency on one until it stabilizes) rather than pointing somewhere
  unreachable.

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
