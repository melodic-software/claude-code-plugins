---
description: "Author an unattended PowerShell script for work that is fully scriptable but not agent-launchable: the human is only the privilege or policy boundary (UAC, an elevated shell, or a run the repo reserves for the operator). The agent authors the script and never runs it. The human launches it once. The script writes cutover.result/1 JSON the agent reads back. Use when: 'run this elevated', 'I have to launch it', 'UAC', 'operator must apply', 'unattended cutover', 'scriptable but I cannot run it'. Don't use it for a dashboard click, a 2FA code, or anything the agent can already run itself."
argument-hint: "<scriptable procedure a human must launch>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Author an unattended script a human launches once for a privilege or policy boundary
---

# Unattended launch

`/wizard:generate` is for a step a human has to perform: a dashboard click, a
2FA code, an unplug. This skill is the other case. The work is fully
scriptable, and a human is in the loop only because the agent lacks the
privilege or a policy reserves the run for the operator. The human launches
the script once. The script does the work and writes a result file. The agent
reads that file. The human does not paste a terminal log back into the chat.

An irreversible step (`wsl --unregister`, `git push --force`) still asks the
human, in this skill or in `generate`. That is a consent prompt, not a reason
to make the rest of the script interactive.

## When to use which

| Reason a human is involved | Owner |
|---|---|
| Agent lacks the privilege (UAC, elevated shell) | this skill |
| Agent is forbidden by policy | this skill |
| Dashboard, 2FA, or another step no script can perform | `/wizard:generate` |
| Irreversible and needs consent | `Confirm-Irreversible` in the script |

## Process

### 1. Scope

List the steps, the inputs, and why the agent cannot launch the script. Read
the repo for commands and key names. From a live `.env`, take key names only.
Never values. Show the ordered stages and wait for the user to confirm them.

**Done when:** every stage is named, each input has a resolution rung, and
each irreversible step is marked.

### 2. Author

Copy [template.ps1](template.ps1). Leave the library above `# STAGES` unchanged.
Replace the example `Invoke-UnattendedRun` body with the procedure, using only
these helpers:

- `Assert-Elevation -Mode Required` or `Forbidden`. Elevation is a constraint
  with two failure directions.
- `Assert-NotInside -Name <distro-or-service>`. The script must not be running
  inside the thing it restarts. A WSL login cutover cannot be a script running
  inside that distro; emit PowerShell so it runs on the Windows host.
- `Resolve-UnattendedSecret -Name <ENV> -FilePath <optional>`. First hit wins:
  environment variable, then the file, then one hidden prompt. The value is
  redacted out of the transcript.
- `Assert-PriorResult -Path <result-latest.json>`. Do not start until the
  previous script's result is `ok`.
- `Add-Preflight -Name -Test -Fix`. Fail before later steps, and carry the
  remediation command in the result.
- `Invoke-IdempotentStep -Name -Done -Action`. A re-run after a partial failure
  skips work that is already done.
- `Use-GuardedResource -Name -Take -Prove -Release`. Take a shared resource out
  of service and release it only after proof. A failure leaves it listed in
  `held_resources`.
- `Confirm-Irreversible -Name`. The human types the name. Anything else aborts.

Set the result directory to a path the agent can read after the human runs the
script. The envelope is `cutover.result/1`: per-step `status` and `detail`,
`warnings`, `held_resources`, `transcript`, and a `result-latest.json` copy.

### 3. Hand off

Do not run the script. Print the `# STAGES` block and get explicit approval
before telling the human to launch it. Say which elevation mode it demands
and the result path. After they run it, read `result-latest.json`. Do not ask
them to paste the transcript.

## Next

`/wizard:generate` when a step is a dashboard click, a one-time code, or another action no script can perform.

## Gotchas

- The agent never executes the script. A pipeline or an agent shell is the
  wrong principal.
- A secret resolved at runtime stays in the human's process. Do not ask for
  the value in chat.
- `Confirm-Irreversible` is the consent prompt. Do not skip it because the
  rest of the script is unattended.
- Redaction runs when the script completes or throws. A run killed before
  that (Ctrl+C, a closed window, a reboot) leaves the transcript unredacted,
  so never print a secret, and tell the human to delete the transcript of an
  interrupted run.
- `Assert-PriorResult` trusts the file it reads. When a lower-privilege stage
  feeds an elevated one, put the result directory where only the elevated
  principal can write.
