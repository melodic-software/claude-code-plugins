# computer-use

A Claude Code plugin carrying the operating knowledge for the built-in **computer-use** MCP
server — the desktop screen-control surface. Two skills, one concern: making a screen-control
session succeed, and making its failures legible.

| Skill | What it does |
|---|---|
| `/computer-use:diagnose` | Symptom-to-cause for a screen-control session — the screenshot pixel budget and when `zoom` recovers detail, the ladders for capture and input failures, and the per-OS quirks that make synthesized input behave unlike a human's. A symptom guide answers the common cases with no file load. |
| `/computer-use:setup` | Read-only preflight. Confirms the surface and tool availability, then reports the screensaver, display-sleep, and lock timeouts that end a session mid-run regardless of how busy Claude is. Check-only: every prerequisite is external or a system setting this plugin must not write. |

## Why this exists

The computer-use tool descriptions already document the mechanics — the actions, the allowlist
gate, the permission tiers, the ladder that prefers a dedicated MCP over Chrome over screen
control. **This plugin restates none of that**, on purpose: a standing instruction that repeats
what the surface already says is a per-session tax for zero gain.

What it carries instead is the material that is not derivable from the tool surface and is not
documented upstream:

- **The idle timer does not see Claude.** Synthesized input does not reset the OS idle timer, so
  a long session hits the screensaver or display-sleep timeout no matter how much Claude is
  clicking — and cannot recover itself once it does. Measured, not inferred.
- **Screenshot quality is a fixed pixel budget, not a scale factor**, so the intuitive fixes
  (smaller monitor, lower resolution) do not work and one non-obvious one (`zoom`, which
  re-captures at full resolution) does.
- **Capture and input failures are environment state**, not tool defects — and each has a
  distinct signature worth reading rather than retrying past.

## Works on any machine

- **No machine facts baked in.** Focus-stealing utilities, monitor layouts, and timeout values
  are described as classes with general mitigations; specific processes and displays belong in
  the operator's own memory file, not here.
- **Per-OS content is opt-in.** The skill routes to a quirks file for the platform you are on
  and loads nothing else.
- **Zero configuration.** No `userConfig`, no tracked project files, nothing to write.

## Honest verification gap

Every empirical claim in this plugin was measured on **Windows 11 with the Claude Desktop
surface** on 2026-08-10. macOS is supported by the platform, and the platform-neutral content
applies there, but **no macOS quirks file ships because none has been verified.** Rather than
generate plausible macOS specifics, the plugin states the gap and serves macOS users the
platform-neutral material only.

Surfaces are not interchangeable, and the skill says so: computer use in the Claude Code CLI is
macOS-only, while the Desktop app covers macOS and Windows. Guidance written for one is wrong on
the other.

## What it deliberately does not do

- **No system-setting changes.** Power, screensaver, and lock policy are reported with their
  measured values and handed to the operator. The plugin never writes them.
- **No `apply` action.** There is nothing it could conformingly write — the check-only carve-out
  applies, so `setup` verifies and reports and stops.
- **No mechanism claims it cannot support.** Where a behavior is reproducible but unexplained —
  Windows shell menus ignoring a synthesized Escape — the plugin says exactly that and ships the
  rule anyway.

## Prerequisites

The `computer-use` MCP server must be enabled, on a plan that supports it (research preview; Pro
or Max, not Team or Enterprise), with OS-level permissions granted. `/computer-use:setup` probes
all of it and reports what is missing; installing and enabling remain the operator's.
