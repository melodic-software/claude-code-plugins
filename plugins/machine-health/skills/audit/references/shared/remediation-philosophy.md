# Remediation philosophy

Remediations are the highest-risk surface of this skill. A false-positive remediation — fixing something that wasn't broken, or fixing it in a way the user would not have chosen — erodes trust faster than any number of useful findings can rebuild. This file sets the posture every OS-specific `remediation-policy.md` must conform to.

## Core posture: fail safe

**When uncertain, don't act.** Report the finding, include the reproduction command, move on. A surfaced issue the human can investigate is always better than an attempted fix that introduces a new problem.

**Do the least that could work.** If an Automatic service is stopped, try one `Start-Service` — not a service reset, not a dependency walk, not a config repair. If that fails, the check upgrades to CRIT with the failure message; human decides next step.

## The one-attempt rule

Every remediation gets exactly **one** attempt per run. No retries, no backoff loops, no "try a gentler fix first then escalate." Reasons:

1. **Retries mask underlying failure modes.** A flaky service that fails 50% of start attempts should show as flaky, not as "fine, it started eventually."
2. **Retries magnify blast radius.** A remediation that has a 5% chance of damage on one try has a 14% chance over three.
3. **Retries hide in logs.** The before/after contract is cleaner with one attempt per remediation.

If the one attempt fails, the remediation log captures the error and corresponding check upgrades to CRIT. That's the escalation path.

## Mandatory before/after logging

Every remediation attempt writes **both** before and after state to `<StateBase>/logs/remediation-YYYY-MM-DD.log`. Debuggability contract, not nice-to-have.

- **Before:** the observation that justified the remediation (service state, file count, bytes used).
- **After:** the same observation, re-taken immediately after the attempt.
- **Success bool:** whether the intended state change occurred, not whether the cmdlet threw.
- **Error:** populated when `success: false`, with the exception message or exit code.

The remediation script returns this as structured JSON; the orchestrator persists it and embeds it in the run snapshot under `remediations`.

## Forbidden actions (global)

These are **never** allowed, regardless of how obvious the need seems:

- **No reboots.** Not automatic, not "if the user is idle," not "just a restart of explorer.exe." Surface a reboot recommendation as a finding; let the human reboot.
- **No update installation.** Not Windows Update, not winget upgrade, not driver updates. Surface the finding with the exact command to run manually.
- **No registry writes** beyond transient reads. The skill reads registry keys for pending-reboot detection; it does not set keys.
- **No service configuration changes.** Never change start type, never edit service accounts, never modify dependencies. Starting a service is a state change, not a config change.
- **No firewall, UAC, or Defender policy changes.** Read Defender status; never modify it.
- **No uninstalls, repair installs, or version rollbacks.** Surface the finding; the human decides.
- **No rollback of anything.** Rolling back a driver or a Windows update is destructive and requires context the skill doesn't have.
- **No editing of user files.** `Documents\`, `Desktop\`, OneDrive, source repos, dotfiles — off-limits.
- **No network changes.** DNS, proxy, routing table — read-only.
- **No scheduled task creation.** The scheduling layer is explicitly out of scope.

A remediation requiring any of the above is not a remediation — it's a proposal for `TODO.md`.

## Authorization chain

A remediation runs only if **all** are true:

1. A check returned a severity that the OS-specific `remediation-policy.md` lists as remediable for that check.
2. The remediation is explicitly listed in the OS-specific `remediation-policy.md` with its authorization conditions.
3. `$DryRun` is `$false`. First-run mode forces `$DryRun = $true`.
4. The user load heuristic has not tripped (no interactive input in the last 60s).
5. The remediation script exists at the path named by the catalog or policy.

If any one of these is false, the remediation is skipped and the reason is logged.

## First-run dry mode

The first invocation (`RunMode = first-run`) forces `DryRun = true` regardless of user flags. Purpose:

- Prove the orchestrator works on this host without making any changes.
- Produce a report the human can review before authorizing remediations.
- Seed `state/history.jsonl` with a baseline.

`TODO.md` is seeded with explicit unchecked items asking the human to approve each remediation class. Until those are checked, even a normal `weekly` run keeps `DryRun = true`.

## Defer under user load

If the interactive user has had keyboard or mouse input in the last 60 seconds, **skip all remediations** for this run. Read-only checks still run; report still generates. A note appears in the run log and report's "Remediations" section explaining the deferral.

Rationale: a remediation restarting a service at the wrong moment can interrupt real work. The weekly cadence gives remediations a fresh chance next Monday morning.

## Escalation on failure

When a remediation fails:

1. The remediation attempt is logged with `succeeded: false` and the error.
2. The corresponding check finding upgrades to CRIT (if not already), with `notes` appended: `"Remediation <id> failed: <message>"`.
3. The report's "Remediations" section shows the failure with enough context to reproduce manually.

Failure **does not** trigger another attempt, alternate remediation, or fall-through behavior. Human's turn.

## What about remediations that work but the finding persists?

Example: `Restart-StoppedService` succeeds, but 2 hours later the service dies again. The next weekly run re-detects the stopped service and remediates again. If the same service-target pair is remediated in **3 consecutive runs**, the orchestrator should:

- Log this as a pattern in the run log.
- Add a `TODO.md` entry proposing investigation (not another remediation type — investigation by human).
- Continue remediating until the human acts.

Don't stop remediating on loop detection — the alternative is leaving a stopped service stopped, which is strictly worse. But make the loop visible.
