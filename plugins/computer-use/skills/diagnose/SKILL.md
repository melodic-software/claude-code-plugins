---
description: "Diagnose unexpected behavior from Claude Code's built-in computer-use MCP server (desktop screen control). Use when: 'computer use', 'control my screen', 'screenshot is blurry', 'why is the screenshot low resolution', 'zoom in on the screen', 'screenshot capture failed', 'empty capture', 'clicks are landing in the wrong place', 'the screensaver killed the session', 'UIPI', 'app is not in the allowed applications', 'escape is not closing this menu', or before driving a native desktop app. Resolves a symptom to a cause instead of retrying: the fixed screenshot pixel budget and when zoom recovers detail, the capture and input failure ladders, and the per-OS quirks that make synthesized input behave unlike a human's. Not for: browser work (use Claude in Chrome), shell work (use Bash), or a service with its own MCP server."
when_to_use: "a screenshot, click, or keystroke did not do what you expected; sizing up the hazards before driving a native app unattended"
argument-hint: "[quirks|screenshots] — omit for the symptom guide"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Resolve computer-use capture, input, and screenshot symptoms to a cause
---

## Purpose

Claude Code ships computer use as a built-in MCP server whose tool descriptions already cover
the mechanics — actions, the allowlist gate, permission tiers, the ladder that prefers a
dedicated MCP over Chrome over screen control. **This skill does not restate any of that.**

It carries only what the surface does *not* tell you and the model cannot derive: the shape of
the screenshot budget, the failure modes that look like tool bugs but are environment state,
and the per-OS input quirks that are invisible until they bite.

## Symptom guide (no file load needed)

| Situation | Answer |
|---|---|
| Screenshot looks low-resolution | Expected. Fixed pixel budget, no setting. Use `zoom`. → [screenshots-and-zoom.md](reference/screenshots-and-zoom.md) |
| Small text unreadable after downscale | `zoom` the region — it re-captures at full resolution. Do **not** lower display resolution. |
| `empty capture (0x0)` | Environment, not a tool bug. Walk the ladder → [failure-diagnostics.md](reference/failure-diagnostics.md) |
| Input returns a UIPI error | An elevated or secure-desktop process holds the foreground. Not recoverable by retrying. |
| "not in the allowed applications and is currently in front" | A background app stole focus. Retry with `screenshot` as the batch's first action. |
| Session died partway through a long task | Idle timeout. Claude's own input does **not** reset it → [failure-diagnostics.md](reference/failure-diagnostics.md#the-idle-timer-does-not-see-claude) |
| A synthesized key does nothing in a menu | Shell-owned surfaces differ from in-app menus → your OS's quirks file |

## Per-OS quirks

Load only the file for the machine you are on:

| Platform | File |
|---|---|
| Windows | [reference/windows-quirks.md](reference/windows-quirks.md) |
| macOS | not yet written — see the honest-gap note below |

**Verification gap (declared, not hidden).** Every empirical claim in this plugin was measured
on Windows 11 with the Claude Desktop surface. macOS is supported by the platform and by this
plugin's platform-neutral content, but no macOS quirks file ships because none has been
verified. A macOS user gets the platform-neutral material and no fabricated specifics.

## Surfaces differ — know which one you are on

Computer use is not one thing, and guidance written for one surface is wrong on the other
(verified 2026-08-10 against [computer use from the
CLI](https://code.claude.com/docs/en/computer-use)):

| | Claude Code CLI | Claude Desktop |
|---|---|---|
| Platforms | macOS only | macOS **and** Windows |
| Enabling | `/mcp` → enable `computer-use` | Settings → General |
| Denied-apps list | not available | configurable |

So a Windows session using computer use is on the **Desktop** surface by construction. Check
before applying any surface-specific advice.

## Gotchas

- **The screenshot budget is not a scale factor.** Two machines with different displays land at
  the same megapixel count, not the same ratio — which is why "just use a smaller monitor" does
  not produce a sharper screenshot. See the reference file before advising anyone on resolution.
- **`zoom` re-captures; it does not crop.** It therefore fails when capture is failing, and it
  recovers genuine detail when capture is healthy. Both follow from the same fact.
- **A tool error naming an unexpected app is the safety gate working**, not a defect. Nothing was
  typed into the wrong window. Re-screenshot and retry rather than escalating.
- **On a multi-monitor machine, a launched app can be missing for two opposite reasons** — it
  opened on a display you are not capturing, or you are pinned to the display it did not open
  on. Chasing the first creates the second; reset to `auto` before sweeping.
- **Elevated processes cannot be driven at all.** UIPI blocks synthesized input from a
  lower-integrity process regardless of any grant. Ask the operator to handle those windows.
