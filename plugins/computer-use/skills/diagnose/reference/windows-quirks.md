<!-- portability-scope: This file documents Windows-specific desktop behavior by construction; the platform-neutral guidance lives in SKILL.md and the sibling reference files. -->

# Windows quirks

Our content — not from upstream. Empirically verified 2026-08-10 on Windows 11 with the Claude
Desktop computer-use surface.

## Shell-owned context menus ignore a synthesized Escape

**Symptom:** you right-click in File Explorer, the context menu opens, you send `escape`, and
the menu stays up. Sending it again also does nothing.

**Reproduced:** twice, on a fully loaded menu. Two candidate explanations were tested and both
failed:

- *Load timing* — refuted. Waited 3s for the menu to finish rendering ("Show more options"
  present); Escape still did nothing.
- *Keys routing to the owning window* — not supported. `down` **did** close the menu, but it did
  not move the selection in the file list underneath, which the theory predicts.

**Mechanism: unknown. Behavior: reproducible.** The rule is encodable regardless.

**Rule:** dismiss a shell-owned menu with a **left-click on empty space**. That is the path
verified to work every time. `down` also closes it, but it is a side effect of unclear origin —
prefer the click.

**In-app menus are unaffected.** Notepad's File menu closed on the first synthesized `escape`,
instantly. So this is not "Escape is unreliable" — it is specifically shell-owned surfaces.
Before assuming either behavior, note which kind of menu you opened.

## Right-click does not universally mean "context menu"

**Symptom:** you right-click expecting a menu and nothing appears, so it looks like the click
was dropped.

**It was not.** In MS Paint, seven right-clicks along a line produced seven marks at exactly the
seven coordinates — the input landed perfectly; the canvas simply has no context menu under the
brush tool and marks instead.

**Rule:** before treating a missing context menu as a failure, confirm that *that surface in
that app* has one. A right-click that "does nothing" visible may have done something invisible
(a mark in the current color, a selection change). Check the app's own state, not just for a
popup.

## A launched app can be missing for two opposite reasons

**Symptom:** you launch an app, screenshot, and it is not there.

On a multi-monitor machine there are two distinct causes, and they pull in opposite directions:

1. **The window opened on a display you are not capturing.** Observed with Calculator, which
   launched on the secondary monitor while capture was on the primary.
2. **You are still pinned to the display it did *not* open on.** Observed immediately after, when
   Paint launched on the primary while an explicit `switch_display` was still pinned to the
   secondary from diagnosing cause 1.

Chasing cause 1 is what creates cause 2. On a multi-monitor machine, resolve a missing window by
returning capture to `auto` **first**, then sweeping displays — not the other way round.

## Elevated processes cannot be driven

Windows UIPI blocks synthesized input from a lower-integrity process to a higher-integrity one.
Task Manager, UAC prompts, installers running as administrator, the lock screen, and the
screensaver desktop are all unreachable regardless of what has been granted. See
[failure-diagnostics.md](failure-diagnostics.md#input-refused-with-a-uipi-error).

## Screensaver, display sleep, and lock are three different settings

They fail the same way and are configured independently — a machine with display sleep set to
"never" can still have a 5-minute screensaver. This caused the longest outage observed and is
covered in full, with probes, in
[failure-diagnostics.md](failure-diagnostics.md#ladder-empty-capture-0x0).
