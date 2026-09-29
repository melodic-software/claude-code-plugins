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
Never values. Mark each irreversible step with the exact name the human will
type (`wsl --unregister Ubuntu-26.04`); step 2 passes those names to
`-Irreversible`. Show the ordered stages and wait for the user to confirm them.

**Done when:** every stage is named, each input has a resolution rung, and
each irreversible step is marked and listed as an `-Irreversible` name.

### 2. Author

Copy [template.ps1](template.ps1). Leave the library above `# STAGES` unchanged.
Replace the example `Invoke-UnattendedRun` body with the procedure, using only
these helpers:

- `Invoke-UnattendedRun -ResultDirectory -Stages -Irreversible <names>`. Runs the
  stages and writes the result. `-Irreversible` is the declared list of
  irreversible steps, for example `'wsl --unregister Ubuntu-26.04'`. It is
  printed to the transcript before the stages run (`irreversible actions:
  none` when empty) and recorded as `irreversible_actions`, on success and on
  failure.
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
- `Wait-ForState -Name -Predicate -TimeoutSeconds 300 -IntervalSeconds 5`. The
  preferred way to prove a requested state: poll the outcome, never the exit
  code of the request. It polls the predicate, prints one progress line per
  poll, and returns once the predicate's last output is truthy; otherwise it
  throws `timed out waiting for <Name>` with the last value or error. A
  predicate that throws counts as not yet, because ephemeral targets race. The
  predicate must first assert a non-empty observation (`$pools.Count -gt 0 -and
  ...`): a vacuous pass is the author's bug, so a drain proof that sees no pools
  must fail, not pass. It records a `wait <Name>` step.
- `Use-GuardedResource -Name -Take -Prove -Release [-TolerateTakeExit]`. Take a
  shared resource out of service and release it only after proof. `Prove` must
  throw on failure or emit a truthy value as its last output; `$false`, no
  output, or a nonzero native exit all count as failed proof and keep the
  resource held. A failure leaves it listed in `held_resources`.
  `-TolerateTakeExit` records a nonzero native exit from `Take` as a warning
  instead of throwing (a thrown exception still fails), so `Prove` is the only
  gate. Drain example: the request exits 5 while the drain proceeds, so use
  `-TolerateTakeExit` with `-Prove { Wait-ForState -Name drain -Predicate {
  $pools.Count -gt 0 -and -not ($pools | Where-Object Active) } }`.
- `Assert-ParsedState -Name -Value`. Throws when a parsed listing is `$null`, an
  empty array, or only whitespace, and otherwise prints the item count.
  Unknown state is a stop, not `already absent`.
- `Invoke-NativeUtf8 -Block`. Runs the block with `WSL_UTF8=1` and UTF-8
  console decoding, restores both afterwards (also when the block throws), and
  returns the block's output. It is the pin for `wsl.exe` listings (see
  Gotchas). A CLI that has `--json` should use that instead of parsing human
  output.
- `Confirm-Irreversible -Name`. The human types the name. Anything else aborts.
  It refuses before prompting when the name is not in `-Irreversible`
  (`irreversible step X was not declared`) and while any guarded resource is
  still held (`refusing irreversible step X while resources are held: ...`).
  A confirmed step is recorded as `irreversible <Name>`.

Set the result directory to a path the agent can read after the human runs the
script. The envelope is `cutover.result/1`: per-step `status` and `detail`,
`warnings`, `held_resources`, `irreversible_actions`, `transcript`, and a
`result-latest.json` copy. The schema string is unchanged and
`irreversible_actions` is an additive field, so read its absence in an older
result as an empty list.

#### Order and unknowns

- Irreversible steps go last, after every precondition is proven in the same
  run. A proof from an earlier run or an answer typed at a prompt is not one.
  `Confirm-Irreversible` enforces the resource half: it refuses while any
  `Use-GuardedResource` is still held.
- Every guard whose false branch skips a destructive step
  (`-Done { $names -notcontains 'Ubuntu-26.04' }`) reads a listing that is empty
  when the read failed. Pass the parsed listing through `Assert-ParsedState`
  first, so an unknown state stops the run instead of reading as `already
  absent`.
- After the destructive step, re-verify the outcome with `Wait-ForState` (the
  distro is gone, the port is closed). The destructive command's exit code is
  not that proof.

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
- A `Take` that asks a system to reach a state (a drain with `--wait`) can exit
  nonzero while the state is reached. Do not trust that exit code either way:
  pass `-TolerateTakeExit` and prove the state with `Wait-ForState`.
- `wsl.exe` writes its listings (`--list`, `--status`) as UTF-16, which a
  PowerShell capture decodes as text with embedded NULs, so a `-contains
  'Ubuntu'` guard never matches and reads `absent`. `WSL_UTF8=1` makes it emit
  UTF-8 (WSL 0.64.0 and later); wrap the call in `Invoke-NativeUtf8`. Verified
  2026-09-29 against the 0.64.0 release notes
  (<https://github.com/microsoft/WSL/releases/tag/0.64.0>), `WslClient.cpp` in
  `microsoft/WSL` (reads `WSL_UTF8`; only the value `1` enables UTF-8), and
  Microsoft's `diagnostics/collect-wsl-logs.ps1` (sets it beside
  `[Console]::OutputEncoding`). The Microsoft Learn WSL pages do not mention
  it. Recheck when a WSL release note changes or drops `WSL_UTF8`, or the Learn
  basic-commands page documents a different switch for `wsl.exe` output
  encoding.
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
