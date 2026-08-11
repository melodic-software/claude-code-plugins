# Diagnosing capture and input failures

Our content, measured 2026-08-10 on Windows 11 / Claude Desktop. Upstream documents no
troubleshooting for screenshot failures, which is why this file exists.

The governing rule: **a capture or input failure is almost always environment state, not a tool
defect.** Retrying an action that failed for an environmental reason will fail identically.
Diagnose, then either fix or hand it to the operator.

## The idle timer does not see Claude

The single most disruptive finding, and the least obvious.

**Measured:** user idle time was 10.4s. A computer-use `mouse_move` was injected. Idle time
immediately after: **29.6s** — it kept climbing. Repeated with four more synthesized moves:
**22.2s**. Synthesized input from computer use does **not** reset the OS idle timer.

**Consequences:**

- A long session hits the screensaver or display-sleep timeout **no matter how much Claude is
  clicking and typing**. Claude cannot keep the machine awake by working.
- Long non-GUI stretches inside a computer-use session — research, file edits, reasoning — are
  pure idle time to the OS, so a mixed session is *more* exposed than a purely GUI one.
- Once the screensaver is up, computer use **cannot recover itself**: synthesized input to the
  screensaver desktop is refused. Only a human touching the mouse clears it.

**Remediation is the operator's** (it is a system setting; do not change it for them): raise or
disable the screensaver/display timeout for the duration of the work. Report the measured value
and let them decide.

## Ladder: `empty capture (0x0)`

Walk it in order; stop at the first hit.

1. **Is a screensaver running?** The most likely cause and the easiest to miss, because a
   screensaver is *not* a lock and *not* display sleep — they are three separate settings.
2. **Is the workstation locked?** The secure desktop blocks capture and input wholesale.
3. **Is the display asleep / powered off?** Upstream is explicit that the machine must be awake
   ([Cowork computer use](https://support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork),
   verified 2026-08-10).
4. **Are you pinned to a monitor that is off?** An explicit `switch_display` persists until
   reset. Return to `auto` and retry before concluding anything.

### Windows probes

**Configuration is not runtime state, and step 1 needs runtime state.** A registry read tells you
a screensaver is *configured* and after how long; it does not tell you one is *on the screen right
now*. Diagnosing a live `0x0` needs the latter, so probe runtime first and treat the registry as
the follow-up that explains it.

<!-- portability-ok: Windows-only probe commands; the ladder above is platform-neutral and each platform supplies its own equivalents. -->

```powershell
# 1a. RUNTIME: is a screensaver on screen right now? (SPI_GETSCREENSAVERRUNNING = 0x0072)
Add-Type @'
using System;using System.Runtime.InteropServices;
public class SS { [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a,uint b,ref bool c,uint d); }
'@
$running=$false; [void][SS]::SystemParametersInfo(0x0072,0,[ref]$running,0); "screensaver running: $running"

# 1b. CONFIG: why it fired, and when it will fire again
Get-ItemProperty 'HKCU:\Control Panel\Desktop' |
  Select-Object ScreenSaveActive, ScreenSaveTimeOut, 'SCRNSAVE.EXE', ScreenSaverIsSecure

# 2. Locked? LogonUI owns the secure desktop.
Get-Process LogonUI -ErrorAction SilentlyContinue

# 3. Display and sleep timeouts (0 = never)
powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE
powercfg /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE

# What actually holds a power request (requires an elevated prompt; exits non-zero otherwise)
powercfg /requests
```

A configured-but-not-running screensaver does **not** explain a current `0x0` — keep walking the
ladder. It is still worth reporting, because it predicts when the session will die next.

**A locked-looking failure that reports "not locked" is the screensaver.** With
`ScreenSaverIsSecure = 0` the screensaver takes the screen without locking the session, so a
`LogonUI` check correctly says unlocked while capture is dead and input is refused. Observed
exactly this way; it is the most misleading signal in the set.

Note that display/sleep timeouts of `0` (never) do **not** imply the screensaver is off — that
is a separate setting with its own timeout, and it was the actual culprit in the observed case.

### macOS probes

**None ship, and that is a declared gap rather than an oversight.** No macOS machine was available
to verify a probe set, and this plugin does not ship platform specifics it has not run.

On macOS, say so explicitly rather than skipping the step silently: report that the equivalent
settings — screensaver idle delay, display sleep, and whether a lock is required on wake — must be
read from System Settings by the operator, and that the ladder above still applies unchanged. The
ladder is platform-neutral; only the probe commands are missing.

## Input refused with a UIPI error

```text
Error moving mouse: Simulate("not all input events were sent. they may have been blocked by UIPI")
```

An elevated or secure-desktop process holds the foreground. Windows blocks synthesized input
from a lower-integrity process — no grant overrides this. Candidates: a UAC consent prompt, Task
Manager, an installer running as administrator, the lock screen, or a screensaver.

This is **not recoverable by retrying**. Identify the window and ask the operator to dismiss it:

```powershell
Get-Process | Where-Object MainWindowHandle -ne 0 | Select-Object Name, MainWindowTitle
```

## "X is not in the allowed applications and is currently in front"

A background utility took focus between your screenshot and your action. **The gate did its job
— nothing was sent to the wrong app.** This is the desired behavior, not a failure to route
around.

Typical culprits are peripheral, overlay, and launcher utilities that raise transient windows:
RGB and peripheral suites, game overlays, notification helpers, update prompts. The error names
the process when it can and withholds the name when it cannot.

**Retry pattern** — put a `screenshot` first in the batch so the retry re-establishes state and
reveals whatever appeared:

```json
[{"action": "screenshot"}, {"action": "left_click", "coordinate": [x, y]}]
```

If one process trips this repeatedly on a given machine, that is a durable machine fact for the
operator's own `CLAUDE.md`, not a plugin fact — the mitigation above is already general.

## When to stop and ask

Escalate to the operator instead of retrying when:

- capture fails after the full ladder — the machine needs a human touch;
- input is UIPI-blocked — nothing you can send will land;
- the remediation is a system setting — power, screensaver, lock policy, or accessibility
  permissions are the operator's to change, never the agent's.

Report the specific measured value you found (`ScreenSaveTimeOut = 300`) rather than a generic
"something went wrong". The operator can act on the number.
