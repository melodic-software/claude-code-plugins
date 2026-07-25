# context-guard

A Claude Code plugin that makes each session's context-window usage observable to any session or
tool that needs it — so long-running workflows can route heavy work away from a degraded context
**before** quality slips, instead of guessing. Three parts:

- **Statusline tee** (`scripts/statusline-tee.sh`) — a transparent wrapper around your statusline
  command. Each refresh it atomically writes `captured_at`, `session_id`, and the session's
  `context_window` object (copied verbatim from the statusline stdin) to the per-session path
  `~/.claude/context-guard/context/<session_id>.json`, then passes your statusline through
  byte-for-byte. With no statusline configured it doubles as a minimal standalone statusline.
- **Zone resolver** (`scripts/context-zone.sh`) — `context-zone.sh <session_id>` prints exactly one
  word: `smart` / `acceptable` / `dumb` / `unknown`. Bands come from the machine-scope
  `~/.claude/context-guard/zones.json` when present and valid, else from shipped defaults
  (smart ≤ 50 < acceptable ≤ 75 < dumb, over `used_percentage`). Zones say *where you are*;
  consumers decide *what to do*.
- **Reader contract** (`reference/reader-contract.md`) — the authoritative consumer contract: the
  snapshot path pattern, file shape, the 10-minute staleness rule, fail-open capability detection,
  the zones.json shape, session-id discovery via `${CLAUDE_SESSION_ID}`, and the
  zone-is-not-a-compaction-indicator rule.

## Behavior

- **Transparent by contract.** No tee outcome — missing `jq`, unwritable path, a rename blocked by
  a concurrent reader — ever changes the wrapped statusline's output or exit code. Missing `jq` is
  surfaced as a visible one-line notice, never a silent skip.
- **Per-session, atomic snapshots.** One file per session id (no cross-session last-writer-wins);
  readers never see torn JSON (temp file + rename, with a brief retry for the Windows
  rename-over-open-target case). Stale sibling files are pruned on write with a 14-day cutoff —
  far above the staleness window, so live-but-idle sessions always survive.
- **Path containment.** `session_id` becomes a filename, so the tee accepts only `[A-Za-z0-9_-]`
  and skips the snapshot for anything else — the wrapped statusline is unaffected.
- **Fail-open zone resolution.** Absent, stale, or unparsable snapshots, null or out-of-range
  `used_percentage`, null `current_usage` (early-session and post-`/compact` statusline states),
  a non-ISO `captured_at`, a snapshot whose embedded `session_id` differs from the requested one,
  or missing `jq` all resolve `unknown` — consumers take their conservative path on data they
  cannot trust, never a fabricated zone. The shipped bands are declared judgment defaults: no
  official auto-compaction threshold is documented (verified 2026-07-24); `zones.json` is the
  tuning path.
- **Integrity boundary (stated honestly).** The snapshot directory is owner-only where POSIX
  modes work; on Windows ACL volumes the `chmod` is a no-op and other local users could forge
  snapshots. Zones are routing hints — consumers must never attach security or egress decisions
  to a zone word. See the reader contract's untrusted-data section.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install context-guard@melodic-software
```

The tee needs one operator step: run `/context-guard:setup check`, which verifies prerequisites
and prints the exact `settings.json` statusline edit (wrapping your existing command, or
standalone) for you to apply — the plugin never edits your settings itself. `check` also detects
stale wiring after a plugin update (the cache path changes) even when the old file still exists.
`/context-guard:setup apply` seeds or refreshes `zones.json` from the shipped defaults on explicit
request — the one file the plugin owns the schema of.

## Requirements

The scripts run on Bash (Git Bash on native Windows — install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows); the statusline wiring
invokes `bash` explicitly) and need [`jq`](https://jqlang.org/download/) on `PATH` for the tee, the
zone resolver, and the standalone statusline. The snapshot updates only while an interactive
session refreshes the statusline; `context_window` fields can be `null` early in a session and
right after `/compact`, per the
[statusline reference](https://code.claude.com/docs/en/statusline) — readers own null handling.

## Configuration

No `userConfig`. The snapshot path and the 10-minute staleness rule are deliberately **not**
configurable: they are contract constants that cross-plugin consumers inline from the
[reader contract](reference/reader-contract.md); a per-user override would silently split the
writer from its readers. Band numbers are the one tunable — via `~/.claude/context-guard/zones.json`
(shape in the reader contract), which the operator's own statusline display may read too, so
display and consumers never drift. Disabling the tee is the operator's edit (remove or unwrap the
statusline command); disabling everything is `enabledPlugins` / uninstall.

## Consumers

First consumer: the `plugin-quality` audit skill (zone-informed dispatch and evidence-flush
decisions, conservative on `unknown`). Any session or tool on the machine may read the same files
under the same contract.

## License

MIT (SPDX-License-Identifier: MIT).
