---
description: "Verify the computer-use plugin's prerequisites and report the environment settings that end a screen-control session mid-run. Use when: 'set up computer use', 'is computer use working', 'why did my computer use session die', 'check computer use', 'computer use preflight', or before a long unattended screen-control run. Action: check (read-only, default) — probes the surface, the tool availability, and the idle/screensaver/sleep timeouts that no amount of Claude activity can hold off, then reports PASS/FAIL/INFO with one remediation line each. Check-only by contract: every prerequisite is external or a system setting this plugin must not write."
argument-hint: "check"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Computer use has no consumer-project configuration and no `userConfig`. Everything it depends on
is either an external prerequisite (the MCP server, the plan, OS permissions) or a system
setting this contract forbids setup to mutate (power, screensaver, lock policy).

That makes this a **check-only setup** by the plugin contract's carve-out, not by preference:
there is nothing an `apply` could conformingly write. `check` probes, reports, and hands every
remediation to the operator with the exact value it measured.

Non-interactive: never prompt. Run the probes, print the table, stop.

## `check` (read-only)

Read [`../diagnose/reference/failure-diagnostics.md`](../diagnose/reference/failure-diagnostics.md)
first — it owns the probe commands and the reasoning behind them. Do not restate them here;
run them and report. Emit a PASS / FAIL / INFO table with one remediation line per non-PASS.

### 1. Surface and platform

Determine which surface is in play, because the answer changes what is even possible:

- **Windows** → necessarily the Claude Desktop surface; the CLI's computer use is macOS-only.
- **macOS** → either surface; check whether `computer-use` is enabled in `/mcp` (CLI) or in
  Settings → General (Desktop).

Report the surface as INFO. It is context for everything below, not a pass/fail.

### 2. Tool availability

Confirm the computer-use tools are actually reachable in this session — call
`list_granted_applications`, which is read-only and has no side effects. It returns the
allowlist and the active grant flags.

- Tools reachable → PASS, and report the current allowlist and grant flags as INFO.
- Tools absent → FAIL. Remediation: enable the `computer-use` MCP server for this project, and
  confirm the plan supports it (research preview, Pro or Max; not Team or Enterprise).

Do **not** call `request_access` during a check — that raises a consent dialog, which is not
read-only behavior.

### 3. Session-killing timeouts (the one that actually bites)

This is why the skill exists. Claude's synthesized input does not reset the OS idle timer, so a
session dies on schedule regardless of how busy Claude is. Probe and report the **measured
numbers**:

- screensaver enabled, its timeout, and whether it locks on resume;
- display-off timeout;
- sleep timeout.

Probe **runtime state before configuration** — a registry or defaults read says a screensaver is
configured, not that one is on screen now — and report both.

**Platform coverage is uneven, and the check must say so rather than skip.** The diagnostics
reference ships verified probe commands for Windows only. On macOS, no verified probe set ships:
report this step as INFO-unverified, name the three settings the operator must read from System
Settings themselves (screensaver idle delay, display sleep, require-password-on-wake), and state
that the hazard is unchanged — synthesized input does not reset the idle timer on any platform.
Never silently omit the step, and never substitute an unverified command as though it were
checked.

Grade against the work in front of you rather than an absolute: any timeout **shorter than the
expected unattended run** is a FAIL, and one comfortably longer is a PASS. A 5-minute
screensaver is fine for a two-minute task and fatal for a thirty-minute one.

Remediation is always advisory, phrased as the operator's decision: *"Screensaver fires after 5
minutes and this run will exceed that — raise or disable it for the duration."* Never change a
power, screensaver, or lock setting; state the setting and the value and let the operator act.

Note the three settings are independent — "display never sleeps" says nothing about the
screensaver, and the screensaver is the more common culprit.

### 4. Multi-monitor state

Report the monitor count and which display screenshots currently target. More than one monitor
is INFO, not a failure, but it is the precondition for the "app opened where I wasn't looking"
class of confusion, and knowing it up front is cheaper than diagnosing it later.

### 5. Foreground stability

If any known focus-stealing utility is running (peripheral suites, overlays, launchers), report
it as INFO with the retry pattern from the diagnostics reference. This is a nuisance, not a
blocker — the allowlist gate catches it safely every time.

## Reporting

End with a one-line verdict: **ready**, **ready with caveats** (INFO or advisory FAILs the
operator may accept), or **blocked** (tools unreachable). When blocked, name the single next
action rather than listing everything at once.

## Gotchas

- **`request_access` is not a probe.** It raises a consent dialog, so calling it during a
  read-only check violates the contract. `list_granted_applications` is the read-only way to see
  the allowlist and grant flags.
- **A "never" display-sleep timeout does not mean the machine stays awake.** Screensaver,
  display sleep, and lock are three independent settings; the screensaver has its own timeout
  and is the more common cause of a dead session. Probe all three or the check is misleading.
- **`powercfg /requests` needs an elevated prompt.** From an ordinary session it exits non-zero
  with a permissions message — report that the probe was unavailable rather than reporting that
  nothing holds a power request.
- **A timeout is only a FAIL relative to the run.** There is no universally correct value; grade
  against the expected unattended duration or the check produces noise on short tasks.
- **Never remediate the settings this skill reports.** Power, screensaver, and lock policy are
  system settings — report the measured value and the recommendation, and let the operator act.
