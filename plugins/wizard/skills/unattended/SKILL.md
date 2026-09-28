---
description: "Author an unattended script the human launches once when they are only the privilege boundary: UAC, an elevated shell, or a policy that reserves the applying run for the operator. Emits bash or PowerShell that resolves its own inputs, refuses the wrong elevation and the wrong host, and writes a JSON result the agent reads back. Use when: 'unattended setup script', 'script I will run elevated', 'operator-only apply', 'do not run this inside WSL', 'leave a result JSON'. Do not use for dashboard clicks, 2FA, or unplugging hardware (that is /wizard:generate) or for steps the agent can run itself."
argument-hint: "<procedure>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Author an unattended elevated or policy-gated script that reports JSON
---

# Unattended script

The human is the privilege boundary, not the actor. The procedure is fully
scriptable. The agent is barred from launching it (UAC, or a repo rule that
reserves the applying run for the operator). Author a script they run once.
The script leaves `wizard-unattended/1` JSON. The agent reads that file. The
human does not paste a transcript.

`/wizard:generate` stays the interactive bash wizard for dashboard clicks, 2FA,
and other steps an agent cannot perform. Irreversible commands (`wsl --unregister`,
`git push --force`) get one consent prompt up front in either skill, then run
without a confirm at every step.

## Decision

**Claim:** this is a sibling skill, not a mode of `generate`. It emits bash
(`template.sh`) or PowerShell 7 (`template.ps1`). PowerShell is the Windows
host shell when the script must restart a WSL distro it cannot run inside.
Elevation is checked in both directions. Secrets resolve environment variable,
then a conventional file, then one hidden prompt. The script never installs
tools.

**Basis:** PowerShell elevation is
[`WindowsPrincipal.IsInRole`](https://learn.microsoft.com/en-us/dotnet/api/system.security.principal.windowsprincipal.isinrole)
with `WindowsBuiltInRole.Administrator`. The transcript cmdlet is
[`Start-Transcript`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.host/start-transcript).
Bash elevation is `id -u` (0 means root).

**As of:** 2026-09-28.

**Recheck:** `IsInRole` stops treating `WindowsBuiltInRole.Administrator` as
the elevated token, or `Start-Transcript` stops recording the session the
`-Path` argument names.

## Process

1. Say why a human is in the loop. Privilege or policy: this skill. A click,
   a code, or a cable: `/wizard:generate`. If both, split them.
2. Pick the shell. PowerShell when the script must not run inside the Linux
   distro it restarts, or when the elevation is a Windows admin token. Bash
   otherwise (Git Bash or WSL is fine when the script is not restarting that
   environment).
3. Copy `template.sh` or `template.ps1`. Replace the `stages` body below the
   marker. Do not edit the library above it.
4. Each stage is idempotent (`run_step` skips an id already `ok` in
   `*-latest.json` unless `FORCE=1`). Preflight every external binary with the
   exact install command. `hold` a shared resource and `release` it only after
   the proof, including on the failure path (an unreleased hold is a failed
   result). `refuse_if_env` (bash) or `Refuse-IfEnv` (PowerShell) names the
   environment the script must not be inside. `require_root` / `require_user`
   or `Require-Elevated` / `Refuse-Elevated` match the privilege the stage
   needs.
5. `resolve_secret` / `Resolve-Secret`: environment, then file, then one hidden
   prompt. Do not put secret values in the script text or in stage details.
6. Show the stages to the user. After they approve, tell them the one command
   to run and the JSON path (`$RESULT_DIR/$RESULT_NAME-latest.json`). Do not
   run the script.

## Result

`schema` is `wizard-unattended/1`. `status` is `ok` or `failed`. `steps[]`
has `id`, `status` (`ok`, `skipped`, `failed`), and `detail`. `held` lists
shared resources still taken. `transcript` is the log path. Secret values are
replaced with `[redacted]` before the file is written.

## Gotchas

- A transcript captures everything. Stage details must not echo secrets; the
  library scrubs values it resolved, not values the stage prints on its own.
- Re-run after a partial failure is the recovery path. Do not write a step
  that is unsafe to repeat.
- `generate` still refuses a non-TTY and confirms every stage. This skill does
  not. Do not copy those gates in.
