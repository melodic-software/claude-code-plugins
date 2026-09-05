<!-- portability-scope: This file documents Windows-specific desktop behavior by construction; the platform-neutral guidance lives in SKILL.md and the sibling reference files. -->

# Windows quirks

Our content — not from upstream. Empirically verified 2026-08-10 on Windows 11 with the Claude
Desktop computer-use surface.

## Shell-owned context menus ignore a synthesized Escape

**Symptom:** you right-click in File Explorer, the context menu opens, you send `escape`, and
the menu stays up. Sending it again also does nothing.

**Mechanism: unknown. Behavior: reproducible.** Two explanations do not hold, so do not act on
them:

- *Load timing.* Waiting 3s for the menu to finish rendering ("Show more options" present)
  changes nothing; Escape still does nothing.
- *Keys routing to the owning window.* `down` closes the menu but does not move the selection in
  the file list underneath, which that theory predicts.

**Rule:** dismiss a shell-owned menu with a **left-click on empty space**. That is the path
verified to work every time. `down` also closes it, but it is a side effect of unclear origin —
prefer the click.

**In-app menus are unaffected.** Notepad's File menu closes on the first synthesized `escape`.
So this is not "Escape is unreliable"; it is specifically shell-owned surfaces.
Before assuming either behavior, note which kind of menu you opened.

## Right-click does not universally mean "context menu"

**Symptom:** you right-click expecting a menu and nothing appears, so it looks like the click
was dropped.

**It was not.** In MS Paint, right-clicks under the brush tool land as marks at exactly the
clicked coordinates: the input arrives, and the canvas simply has no context menu there.

**Rule:** before treating a missing context menu as a failure, confirm that *that surface in
that app* has one. A right-click that "does nothing" visible may have done something invisible
(a mark in the current color, a selection change). Check the app's own state, not just for a
popup.

## A launched app can be missing for two opposite reasons

**Symptom:** you launch an app, screenshot, and it is not there.

On a multi-monitor machine there are two distinct causes, and they pull in opposite directions:

1. **The window opened on a display you are not capturing.** An app such as Calculator launches
   on the secondary monitor while capture is on the primary.
2. **You are still pinned to the display it did *not* open on.** An explicit `switch_display`
   left over from diagnosing cause 1 keeps capture on the secondary while the next app launches
   on the primary.

Chasing cause 1 is what creates cause 2. On a multi-monitor machine, resolve a missing window by
returning capture to `auto` **first**, then sweeping displays — not the other way round.

## Elevated processes cannot be driven

Windows UIPI blocks synthesized input from a lower-integrity process to a higher-integrity one.
Task Manager, UAC prompts, installers running as administrator, the lock screen, and the
screensaver desktop are all unreachable regardless of what has been granted. See
[failure-diagnostics.md](failure-diagnostics.md#input-refused-with-a-uipi-error).

## Screensaver, display sleep, and lock are three different settings

They fail the same way and are configured independently: a machine with display sleep set to
"never" can still have a 5-minute screensaver. The full ladder, with probes, is in
[failure-diagnostics.md](failure-diagnostics.md#ladder-empty-capture-0x0).
