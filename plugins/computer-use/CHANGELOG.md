# Changelog

All notable changes to the `computer-use` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.1]

### Changed

- **Instruction-surface de-slop (#2891, computer-use cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change.
  One quoted remediation protocol string keeps its em dash. The setup skill now
  ships warranted `evals/evals.json` because a SKILL.md edit requires it.

## [0.1.0]

### Added

- **Initial release.** Two skills covering the computer-use concern: operating knowledge and a
  read-only preflight. Deliberately restates nothing the built-in computer-use MCP server's own
  tool descriptions already carry.
- **`/computer-use:diagnose`** — symptom-to-cause router over three reference spokes: the
  screenshot pixel budget and `zoom` semantics, the capture/input failure ladders, and Windows
  quirks. A symptom guide answers the common cases with no reference load, and a surface
  comparison table separates CLI (macOS-only) from Desktop (macOS and Windows) guidance.
  Named with the default imperative grammar rather than repeating the tool name: the
  `firecrawl`/`playwright` exception covers a wrapper you invoke the tool *through*, and this
  skill drives nothing — the computer-use MCP tools are called directly. Registered as a
  `diagnose` leaf-name collision alongside `songwriting` and `testing`.
- **`/computer-use:setup`** — check-only preflight per the contract's carve-out: probes the
  surface, tool availability via `list_granted_applications`, the screensaver/display/sleep
  timeouts, monitor count, and known focus-stealing utilities. Reports measured values with
  operator-owned remediation; writes nothing.

### Empirical basis

Measured 2026-08-10 on Windows 11 / Claude Desktop. Findings that drove the design:

- **Synthesized input does not reset the OS idle timer.** Idle time went 10.4s → 29.6s across an
  injected `mouse_move`, and 22.2s after four more. A screen-control session therefore hits the
  screensaver or display-sleep timeout regardless of Claude's activity, and cannot recover
  itself once the screensaver desktop refuses synthesized input.
- **The screenshot target is a pixel budget, not a scale factor.** 2560x1440 → 1456x816 (1.19MP)
  locally against upstream's documented 3456x2234 → 1372x887 (1.22MP).
- **`zoom` re-captures rather than crops** — corroborated by upstream's "at full resolution"
  wording and by `zoom` failing outright during a capture outage.
- **Windows 11 shell context menus ignore a synthesized Escape**, reproducibly. Two candidate
  mechanisms (load timing, keys routing to the owning window) were tested and neither held; the
  rule ships with the mechanism recorded as unknown.
- **A screensaver is not a lock and not display sleep.** With `ScreenSaverIsSecure = 0` a
  `LogonUI` probe correctly reports "not locked" while capture is dead — the most misleading
  signal in the set.

### Known gaps

- **No macOS quirks file.** macOS is supported by the platform and by this plugin's
  platform-neutral content, but nothing macOS-specific has been verified, so nothing
  macOS-specific ships.
- **`screenshot save_to_disk: true`** produced no discoverable output on Windows; where it
  writes is unresolved and it is documented as unreliable rather than broken.
