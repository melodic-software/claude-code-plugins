# wizard

A Claude Code plugin for setup work that depends on a person's own logins and
approvals. It writes **interactive bash wizards**. When the person has run one,
the project's `.env` and CI secret store hold the values it needs, and a closing
summary names anything still left to do by hand.

| Skill | What it does |
|---|---|
| `/wizard:generate` | Scope the manual procedure from the repo, author its stages onto the fixed hardened template, verify statically, and hand off to the human after explicit approval |
| `/wizard:unattended` | Author a PowerShell script the human launches once when the work is scriptable and the human is only the privilege or policy boundary. The script writes `cutover.result/1` JSON. Needs PowerShell 7 (`pwsh`); see Prerequisites |

Invocation: `/wizard:generate` is model-invoked as well as typed. Its
description limits it to steps outside the agent's reach and excludes any step
the agent could carry out itself.

## Security posture

- **Only the person runs a wizard.** It runs in their own terminal; the agent's
  part ends once the file is written. The script itself refuses to start without a
  controlling TTY (`/dev/tty`), so its confirmation gates cannot be satisfied by
  piped or pasted input.
- **Human approval gate.** The skill's verify step is stop-the-line: the full
  `STAGES` block is printed to the user and explicitly approved BEFORE the
  script is made executable or offered for running.
- **What the model can see.** It depends on how a value travels:

  | Value | Visible to the model |
  |---|---|
  | Entered at a wizard prompt (secrets unechoed), then written to `.env` or `gh` | Never: the running script has no model attached |
  | In a live `.env` the skill scans while planning | Key **names** only |
  | Pasted by the user into the chat | Yes |

- **Hardened template.** Every wizard carries the same library ahead of its `STAGES` marker, and
  nobody edits that part by hand. It enforces:
  - https-only URL opening, with the full URL printed before dispatch.
  - Fail-closed prompts: a closed terminal aborts rather than falling through.
  - Key-name validation.
  - Single-quoted, escaped `.env` values, an is-it-gitignored check, and trap-cleaned atomic
    rewrites from a `0600` temp file. A symlinked `.env` is written through to its target, which
    keeps its own mode.
  - GitHub writes that resolve and echo the target repo once, require explicit confirmation before
    the first write, pass `--repo` on every call, pipe values over stdin rather than argv, refuse
    empty values, and surface `gh` errors into the closing summary.
  - A names-only closing summary.

## Prerequisites

- **bash**, to run the generated script. On Windows the supported path is Git
  Bash or WSL. (Generating a wizard needs nothing beyond the agent itself.)
- **PowerShell 7 (`pwsh`)**, to run a script `/wizard:unattended` authors. Launch it
  with `pwsh -File <script>`: Windows PowerShell 5.1 fails at the script's
  `#requires -Version 7.0`. On Windows, install it side by side with 5.1 using
  `winget install --id Microsoft.PowerShell --source winget`
  ([install guide](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows)).
- **`gh` (GitHub CLI), optional**. Only for stages that write GitHub Actions
  secrets or variables. Without an installed, signed-in `gh`, those stages
  print a warning and are listed in the closing to-do summary; the run
  continues. Wizards whose values live only in `.env` never touch `gh`.

## Unattended secrets

A script `/wizard:unattended` authors resolves each secret in this order, first hit wins:
environment variable, a file the author names, a `Microsoft.PowerShell.SecretManagement` vault,
then the native store (macOS Keychain through `security find-generic-password -s <name> -w`, Linux
`pass show <name>` first line, for an entry `<name>.gpg` in the password store), then a hidden prompt. A store rung is skipped silently when its
module, command or the name is absent, and the vault uses only a string secret. The vault reads
every registered vault, so a locked vault, Keychain or `pass` can prompt during a dry run, and an
unattended run needs an unlocked keychain or a `gpg-agent` with a cached passphrase. Names declared with
`-Secrets` on `Invoke-UnattendedRun` resolve once, before the first stage, so every hidden prompt
comes up front. An undeclared name falls back to the same ladder at first use. The result JSON
lists declared names, never values.

## Ephemeral by default

| Will this setup be repeated? | What happens to the script |
|---|---|
| No (the default) | Scratch directory or `scripts/`, never committed, removed after the run |
| Yes, by other contributors | Committed and linked from the project README |

## Setup skill assessment

This plugin ships no `setup` skill, per the philosophy's criteria: it has (a) no
consumer-project configuration surface, (b) no external prerequisite for its own
operation, and (c) no `userConfig` at all. `bash` and `gh` are prerequisites of
the *generated artifact's run*, declared above and at the point of use in the
generated script itself, which degrades visibly when `gh` is absent. Setup
would be blanket ceremony with nothing to check or apply.
