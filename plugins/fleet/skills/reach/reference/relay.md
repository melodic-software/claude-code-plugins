# Relay across hosts and platforms

Read this for the detail behind a route matrix row: how each hop works, the named receiver, how a
reply comes back, and what each route was tested to do. The hub's matrix and verbs are enough for a
plain prompt.

## Contents

- [Why a relay is needed at all](#why-a-relay-is-needed-at-all)
- [The hops](#the-hops)
- [A named receiver](#a-named-receiver)
- [Multi-turn and the open pipe](#multi-turn-and-the-open-pipe)
- [Background sessions](#background-sessions)
- [Start in the target's plugin profile](#start-in-the-targets-plugin-profile)
- [Mechanisms not used here](#mechanisms-not-used-here)
- [Getting a reply back](#getting-a-reply-back)
- [Signed-out Windows platform](#signed-out-windows-platform)
- [Verified behavior](#verified-behavior)
- [What the relay does not change](#what-the-relay-does-not-change)

## Why a relay is needed at all

Each platform has its own account and its own session registry. A WSL session and a native Windows
session on one computer register under different home directories and listen on different socket
types, so neither appears in the other's listing; across machines, Remote Control lists only the
signed-in account's sessions. A peer listing that comes back empty or limited to its own platform is this, not a
permissions problem.

The relay closes the gap by starting a headless turn on the target platform. That turn is on
the same host and platform as the target's sessions, so its peer tools list and message them normally.

## The hops

**WSL to this machine's Windows (R1).** WSL interop runs a Windows binary by absolute path:

```console
cd /mnt/c/Users/<user>/<scratch> && /mnt/c/Users/<user>/.local/bin/claude.exe -p "<prompt>" < /dev/null
```

`cd` to a Windows-side directory first. Probe interop by running the `.exe` by absolute path, never
with `cmd.exe /c`.

- **Pointer**: for how a Windows tool started from WSL picks its working directory, fetch
  [Run Windows tools from Linux](https://learn.microsoft.com/en-us/windows/wsl/filesystems#run-windows-tools-from-linux)
  live.

**Windows to this machine's WSL (R4).** Take the distro name from `wsl.exe -l -q`, and run the
account's login shell so `claude` is on `PATH`:

```console
wsl.exe -d <distro> --cd /tmp --exec <shell> -lc 'claude -p "<prompt>" < /dev/null'
```

Use `--exec`, not `--`: with `--` the distro's login shell re-parses the tail first. A
native-Windows Claude runs this through its Bash tool, which is Git Bash, so bash quoting applies
(`'\''` for an apostrophe). From PowerShell (its PowerShell tool or a PowerShell window, 5.1 or
pwsh 7), never `-p "<prompt>"`: in the command above, write `-p ''<prompt>''` in its place, and an
apostrophe in the prompt as `''\''''`. The probe behind that form is in the hub's apostrophe
gotcha.

**Either platform to another machine (R2, R3, R5, R6).** The hop is always the target's WSL sshd
(`<wsl-alias>`, port 2222), through the Windows OpenSSH client. For the target's WSL platform, run
`claude` there. For its Windows platform, chain R1 on the far side:

```console
printf '%s\n' '<prompt>' | <ssh> <wsl-alias> 'cd /mnt/c/Users/<user>/<scratch> && /mnt/c/Users/<user>/.local/bin/claude.exe -p'
```

The prompt goes on stdin and the quoted remote command carries only the flags, so no shell on
either host parses prompt text. Never add `ssh -n`: it replaces stdin with `/dev/null` and drops
the prompt. The live probes below passed the prompt as an argument with `< /dev/null`; this stdin
form has not been re-probed on these hops.

That turn runs as the target's Windows console account, signed in on the target's Windows platform.
Port 22 is never the agent hop: `ssh-admin` has no Claude sign-in.

FLEET.md renders these with the real aliases and profile path; prefer copying from it over
expanding placeholders by hand.

## A named receiver

A headless receiver is a `-p` turn with a name and inbound messages switched on:

```console
claude -p -n <name> --settings '{"crossSessionInbound":"accept"}' "<standing instructions>" < /dev/null
```

- We always start a `-p` receiver with `crossSessionInbound: accept`: nobody is present to approve
  a message, and our R2 receiver started that way took messages across accounts
  ([Verified behavior](#verified-behavior)).
  - **Pointer**: when a message to a receiver is not delivered, or when weighing the setting's
    default, fetch
    [Control inbound messages](https://code.claude.com/docs/en/cross-session-messaging#control-inbound-messages)
    and [Non-interactive sessions](https://code.claude.com/docs/en/cross-session-messaging#non-interactive-sessions)
    live.
- Its standing instructions say what to do with each message and when to stop.
- Inside an outer single-quoted remote command, the JSON's single quotes would close the outer
  quote. Double-quote it with escaped inner quotes instead, and send the instructions on stdin:
  `printf '%s\n' '<instructions>' | <ssh> <wsl-alias> 'claude -p -n <name> --settings "{\"crossSessionInbound\":\"accept\"}"'`.
- The tested receiver kept its turn open (a standing instruction to wait, then print what arrived)
  and ran under `nohup ... &` on the target, with its instructions as an argument. Do not
  background the stdin form that way: a shell without job control gives a backgrounded command
  `/dev/null` as stdin unless it redirects stdin itself
  ([POSIX Shell Command Language, 2.9.3.1 Asynchronous AND-OR Lists](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html#tag_19_09_03_02)),
  so the instructions never arrive. For a session that must stay up, use a
  [background session](#background-sessions) instead.
  - **Pointer**: for when a `-p` run ends after its turn, fetch
    [Run Claude Code programmatically: Background tasks at exit](https://code.claude.com/docs/en/headless#background-tasks-at-exit)
    live.
- Do not start it with `--bare`: a bare session receives nothing (the pointer is in the hub's
  Pointer bullet after its `--bare` bullet).

## Multi-turn and the open pipe

Per-turn resume survives a disconnect. Choose the id up front so nothing parses output:

```console
printf '%s\n' '<prompt>' | <ssh> <wsl-alias> 'cd <dir> && claude -p --session-id <uuid>'
printf '%s\n' '<prompt>' | <ssh> <wsl-alias> 'cd <dir> && claude -p --resume <uuid>'
```

This session generates no id: leave `<uuid>` for whoever runs the command to fill, or start the
first turn with `--output-format json` and resume with the `session_id` it returns.

One open pipe keeps a single process and its context for as long as the connection stays open,
with user messages as NDJSON lines on stdin:

```console
<producer of NDJSON user messages> | <ssh> <wsl-alias> 'claude -p --input-format stream-json --output-format stream-json --verbose'
```

Two turns sent this way came back under one session id with the first turn's context. We write each
stdin line in the shape of the Agent SDK's `SDKUserMessage`. Losing the connection ends the process,
so resume by its session id afterwards.

- **Pointer**: [Agent SDK TypeScript reference: `SDKUserMessage`](https://code.claude.com/docs/en/agent-sdk/typescript#sdkusermessage).

## Background sessions

For a session that outlives the hop, the target platform's own supervisor hosts it:

```console
<ssh> <wsl-alias> 'cd <trusted-dir> && claude --bg --name <name> "<prompt>" < /dev/null'
<ssh> <wsl-alias> 'claude agents --json --all'
<ssh> <wsl-alias> 'claude stop <id> && claude rm <id>'
```

- The directory must be trusted: run `claude` there interactively once and accept the prompt.
  Our R2 start failed in an untrusted directory ([Verified behavior](#verified-behavior)).
  - **Pointer**: when a start fails for trust, fetch
    [Workspace not trusted when dispatching a background session](https://code.claude.com/docs/en/errors#workspace-not-trusted-when-dispatching-a-background-session)
    live for its message and fix.
- `claude agents --json --all` reports each session's `id`, `name`, `status` and `state` (for
  example `busy`/`working`, then `idle`/`blocked`). Poll it to know when a session is done.
- We address `claude logs` and `claude attach` by the short `id` from `claude agents --json --all`
  (bare `--json` lists only active sessions), so a platform on an older CLI behaves like a current one; a name is passed only after checking the platform's
  version against the CLI reference. `claude logs` prints the raw ANSI TUI stream, so read a reply
  from the transcript with `--resume <id>` instead.
  - **Pointer**: when deciding whether a platform can take a session name in place of the id, fetch
    [CLI reference: CLI commands](https://code.claude.com/docs/en/cli-reference#cli-commands) live.
- Never combine `--bg` with `-p`. A later relay turn on that platform can list and message a running
  background session. `claude --resume <id> --bg "<prompt>"`
  continues a finished one.
- `claude --bg --exec '<cmd>'` runs a shell job the same way, for a script that must survive the
  hop. Untested.
- **Pointer**: when deciding whether a background session can outlast what the task needs, fetch
  [Agent view: Limitations](https://code.claude.com/docs/en/agent-view#limitations) live for
  where those sessions run and when they stop.

## Start in the target's plugin profile

When the task names a plugin profile, a turn or session started on a WSL platform (R2, R4, R5) starts
on that platform's profile, through plugin-profiles' `profiles.mjs launch` on the target. Each step
runs over the row's hop; `<dir>` is the directory the session starts in.

1. Find the script: run `claude plugin list --json` on the target and take the `installPath` of
   the entry whose `id` starts with `plugin-profiles@` and whose `enabled` is true. The script is
   `<installPath>/scripts/profiles.mjs`.
2. Run `launch` there with `--unattended`, since nobody answers a relay start, and put the verb's
   own `--settings` JSON in `--with`, so the started session carries one settings file
   (`profiles.mjs` merges it into the profile's):

   ```console
   <ssh> <wsl-alias> 'cd <dir> && node <profiles.mjs> launch <profile> --folder <dir> --unattended --json --with "{\"crossSessionInbound\":\"accept\"}"'
   ```

   Leave out `--with` when the verb carries no `--settings`. On exit 1 (the profile switches on a
   plugin missing a required tool) start nothing and report the reason it printed.
3. Start the session with the printed `command` in place of `claude`, and the verb's other
   arguments after it, without its `--settings`:

   ```console
   printf '%s\n' '<prompt>' | <ssh> <wsl-alias> 'cd <dir> && <command> -p -n <name>'
   ```

With no profile named, or no enabled `plugin-profiles@` entry in step 1, start the session as the
row does without this section, and say with the result that the profile was not applied and why.

### On a Windows platform (R1, R3, R6)

On a Windows platform one PowerShell script runs the same three steps from `argv`, so the prompt
stays out of the printed `command`: it removes each variable `argv` names after `-u` from its
own environment and passes the words after `claude` to `claude.exe`. The prompt never enters the
script text: a first call writes it to a file in `<win-dir>`, quoted as the WSL rows quote a
prompt, and the script starts `claude.exe` from that file. The script goes to
`powershell.exe -Command -` on stdin as a quoted heredoc, so only PowerShell parses it. Here for a
named receiver over R3:

```console
printf '%s' '<prompt>' | <ssh> <wsl-alias> 'cat > <win-dir>/relay-prompt-<name>.txt'
<ssh> <wsl-alias> 'cd <win-dir> && /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command -' <<'PS'
function Q([string]$a) { '"' + ($a -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
$claude = "$env:USERPROFILE/.local/bin/claude.exe"; $s = Join-Path $env:TEMP 'relay-settings.json'; $p = Join-Path $PWD.Path 'relay-prompt-<name>.txt'
Set-Content -Path $s -Value '{"crossSessionInbound":"accept"}' -Encoding ascii
$root = ((& $claude plugin list --json | Out-String | ConvertFrom-Json) | Where-Object { "$($_.id)" -like 'plugin-profiles@*' -and $_.enabled -eq $true } | Select-Object -First 1).installPath
$a = @('--settings', $s); $stop = $null; $c = $null; $ok = $root -and (Get-Command node -ErrorAction SilentlyContinue)
if (-not $ok) { 'profile <profile> not applied: plugin-profiles or node is missing on this platform' }
if ($ok) { $r = & node (Join-Path $root 'scripts/profiles.mjs') launch <profile> --folder $PWD.Path --unattended --json --with $s }
if ($ok -and $LASTEXITCODE) { $stop = "not started: profiles.mjs launch exited $LASTEXITCODE" }
if ($ok -and -not $stop) { $stop = 'not started: profiles.mjs launch printed no claude command'; $argv = @(($r | Out-String | ConvertFrom-Json).argv); $i = 1; while ($argv[$i] -ceq '-u') { Remove-Item "Env:$($argv[$i + 1])" -ErrorAction Ignore; $i += 2 }; if ($argv[$i] -ceq 'claude') { $stop = $null; $a = @($argv[($i + 1)..($argv.Count - 1)]) } }
if (-not $stop) { $c = Start-Process -FilePath $claude -ArgumentList ((@($a) + '-p', '-n', '<name>' | ForEach-Object { Q $_ }) -join ' ') -RedirectStandardInput $p -NoNewWindow -Wait -PassThru }
Remove-Item $p -ErrorAction Ignore
if ($stop) { $stop; exit 1 }; if (-not $c) { 'not started: claude.exe did not start'; exit 1 }; exit $c.ExitCode

PS
```

On R1 the same two calls run locally:
`printf '%s' '<prompt>' > <win-dir>/relay-prompt-<name>.txt`, then
`cd <win-dir> && /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command - <<'PS'`
followed by the same script lines.

- The verb's own settings go to `--with` as a file, never as a JSON argument. Leave out `$s`,
  `--with $s` and `--settings $s` when the verb carries no `--settings`.
  - **Pointer**: when a JSON argument from this script arrives changed, fetch
    [about_Parsing: Passing arguments that contain quote characters](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing?view=powershell-5.1#passing-arguments-that-contain-quote-characters)
    live.
- Each statement sits on one line, and a blank line ends the input.
  - **Pointer**: when the script stops part way or runs a statement twice, fetch
    [about_PowerShell_exe: -Command](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1#-command)
    live.
- Every stop prints a line starting "not started" and exits 1: start nothing else and report it,
  with the reason launch printed on stderr when it refused for a missing required tool. "not
  applied" means the session started without the profile: say so with the result.
- The prompt file is removed on every path the script itself takes: each stop is held in `$stop`
  until the removal line, which runs whatever the lines before it did. Only a PowerShell that is
  killed or loses its connection first leaves it; the next start with the same `<name>`
  overwrites it, so it holds no more than the prompt this session already wrote.
- `claude.exe` starts through `Start-Process` with every argument passed through `Q`, and a `-p`
  prompt arrives on stdin from the file.
  - **Pointer**: `Q` follows the Microsoft C runtime's argument rules; when an argument arrives
    split or changed, fetch [Parsing C command-line arguments](https://learn.microsoft.com/en-us/cpp/c-language/parsing-c-command-line-arguments)
    live (the rules open the page, before its first heading).
- For a background session, which takes its prompt as an argument, replace the start line's
  `'-p', '-n', '<name>'` with `'--bg', '--name', '<name>', [IO.File]::ReadAllText($p)` and drop
  `-RedirectStandardInput $p`. Put this line immediately before the start line, so a prompt that
  `claude.exe` would read as an option never reaches it; begin such a prompt with a word instead:
  `if (-not $stop -and [IO.File]::ReadAllText($p).StartsWith('-')) { $stop = 'not started: a background prompt must not begin with -' }`

## Mechanisms not used here

Each fails the fleet's per-platform account split or needs a human; see the linked page before
reconsidering one. Recheck when a release note names the mechanism or a linked section changes.

- **Remote Control and cross-machine `SendMessage`**: fails the account split. In our probe
  `claude -p --remote-control` did not connect (the flag took the next word as a session name, and
  the turn showed no bridge event).
  <https://code.claude.com/docs/en/cross-session-messaging#message-sessions-on-other-machines>
- **Cloud sessions** (`claude -p "<msg>" --cloud <id>`): fails the account split, and the reply
  cannot be read back from the CLI.
  <https://code.claude.com/docs/en/claude-code-on-the-web#send-follow-ups-from-the-cli>
- **Channels**: needs a human at launch.
  <https://code.claude.com/docs/en/channels#research-preview>
- **The inbox socket from a script**: we do not script against it, since we found no documented
  message format. <https://code.claude.com/docs/en/cross-session-messaging#the-sessions-inbox-socket>
- **Agent teams**: a team is scoped to one session, and nothing crosses to another host or platform.
  <https://code.claude.com/docs/en/agent-teams#limitations>

## Getting a reply back

A relay turn returns when it is done; a peer's answer that arrives later is not in its output.

There is no one-turn query and wait. A `-p` relay turn that sends with `notify_when_idle` ends
before the notice arrives: in the test the message was delivered, and the relay returned after 18
seconds still saying it was waiting. Instead:

- **Poll.** Send the message, then poll `claude agents --json --all` on that platform until the
  receiver is idle.
- **Read the receiver.** `--resume` the receiver by its id and ask what it answered, or read its
  output (a `-p` receiver's stdout log).
- **Ask directly.** When no live session needs the question, skip messaging: a multi-turn
  `--resume` on the target is the query, and its output is the answer.

## Signed-out Windows platform

Check the target Windows platform before relying on it:

```console
printf '%s\n' 'echo ok' | <ssh> <wsl-alias> 'cd /mnt/c/Users/<user>/<scratch> && /mnt/c/Users/<user>/.local/bin/claude.exe -p'
```

An expired-OAuth-session authentication error means the route worked and the Windows platform on the
target is signed out (for the message's wording, fetch
[Login expired](https://code.claude.com/docs/en/errors#login-expired) live). The fix is `/login` at that
machine's console (or over RDP, which is always the console account). Do not try to fix it remotely, and never move a
credential through a prompt or a copy.

## Verified behavior

The per-platform account model and the route results below are what our live probes between a
desktop and a laptop observed, each platform on its own claude.ai sign-in, on Claude Code 2.1.284. A
row that names a later Claude Code version records a later probe and carries its own recheck.

- **Pointer**: when a 2.1.284 route below fails its hop check, or a Claude Code release note touches
  `ListAgents`, `SendMessage`, Remote Control session listing, `crossSessionInbound` or
  `-n`/`--name`, read the probe evidence in
  [#5337](https://github.com/melodic-software/claude-code-plugins/pull/5337) and probe the route
  again.

The hub's guidance on `notify_when_idle`, `--bare`, `--bg`, `--session-id` and a `-p` receiver
also rests on documented flag behavior.

- **Pointer**: when one of those flags behaves other than the hub expects, fetch
  [Get a notice when another session goes idle](https://code.claude.com/docs/en/cross-session-messaging#get-a-notice-when-another-session-goes-idle),
  [Non-interactive sessions](https://code.claude.com/docs/en/cross-session-messaging#non-interactive-sessions),
  [CLI flags](https://code.claude.com/docs/en/cli-reference#cli-flags) and
  [Dispatch an agent from your shell](https://code.claude.com/docs/en/agent-view#dispatch-an-agent-from-your-shell)
  live.

| Route | Result |
|---|---|
| Same machine, WSL and Windows platforms | Each platform's `ListAgents` shows only its own platform |
| Remote Control across accounts | `ListAgents` shows nothing remote while Remote Control is connected |
| R1 WSL to this machine's Windows | `powershell.exe -NoProfile -Command` ran a script. `claude.exe -p` listed the Windows sessions; `--session-id` then `--resume` recalled a word from the first turn; a second `claude.exe -p` messaged the receiver `claude.exe -p -n win-relay-target`, which acknowledged mid-turn |
| R2 WSL to other machine's WSL | A plain command ran over ssh. `claude -p "SendMessage to <name> ..."` delivered to an interactive session and to a `-p -n` receiver with `crossSessionInbound: accept`, across accounts. `--session-id` then `--resume` recalled a word. One stream-json pipe ran two turns under one session id. `--bg` started in a trusted directory and failed in an untrusted one; `agents --json --all`, `stop` and `rm` worked; `logs` accepted only the id (observed on 2.1.284) |
| R3 WSL to other machine's Windows | Reached the target's `claude.exe`: `auth status` reported `loggedIn: false`, and `-p` failed with the OAuth expired error |
| R4 Windows to this machine's WSL | A native-Windows `claude.exe -p` ran `wsl.exe -d <distro> --cd /tmp --exec zsh -lc 'hostname; echo ok-exec'` with its Bash tool (Git Bash) and printed the WSL hostname and `ok-exec`. Through the same tool, `'what'\''s up'` arrived intact and `'what''s up'` arrived as `whats up`. Separately, a `claude -p` over this hop listed the WSL sessions |
| R5, R6 from a Windows origin | Untested; same far-side hop as R2 and R3 |
| Port 22 script hop | Not probed in this pass |
| `notify_when_idle` from a `-p` sender | Message delivered; the notice never reached the sender, whose turn ended first |
| `-p --remote-control` | Did not connect; Remote Control is interactive only |
| [Start in the target's plugin profile](#start-in-the-targets-plugin-profile) | An R2 hop (WSL to another machine's WSL) ran live on Claude Code 2.1.327 on 2026-11-18, with a `-p` turn started in a profile (plugin-profiles probe P14); the Windows rows remain untried live. On R1 (Windows PowerShell 5.1, Claude Code 2.1.325, 2026-11-16) the Windows script's parts ran: `-Command -` read the heredoc; `plugin list --json` parsed; the not-installed branch started `claude.exe --settings <file> --version`; a `--dry-run` launch through Windows `node` exited 0 and the `argv` walk left `claude --settings <session file>`; an inline JSON argument to `node` arrived as `{crossSessionInbound:accept}`; on Windows PowerShell 5.1.26100, a two-entry JSON array piped as `ConvertFrom-Json \| Where-Object` matched no entry, and `(… \| ConvertFrom-Json) \| Where-Object` matched the `plugin-profiles@` one; with `node` standing in for `claude.exe`, a 60-byte prompt file holding `'`, `’`, `"`, `" --version "`, a blank line and a line `PS` arrived with an unchanged SHA-256 on stdin through `Start-Process -RedirectStandardInput`, and as one argument through `Q` for the background form; the script's not-installed branch then started `claude.exe --settings <file> --version` from the file and removed it. The script's lines, with `--version` in place of `-p -n <name>` and a stub `profiles.mjs`, removed the prompt file on each exit path: not installed (exit 0), launch refused (exit 1), launch output not JSON (exit 1), profile applied (exit 0), `claude.exe` missing (exit 1), background prompt `--version` stopped by the `-` line (exit 1), and with launch also refused, the refusal's reason was the one reported (exit 1). Without that line, `Q '--version'` as the only argument printed the version. No `-p` turn started in a profile on R1. Recheck when the platform's PowerShell version changes |
| Cost | Most of each one-line `-p` turn's cost was SessionStart hooks and context loading; measure a turn per <https://code.claude.com/docs/en/costs#track-your-costs> |

## What the relay does not change

- It does not merge accounts. The relay turn sees the target's sessions because it runs on the
  target platform, under that platform's account. Nothing lets this platform's account see them.
- It does not bypass permissions. It starts an agent on another platform, so it prompts under auto
  mode, and neither side runs `bypassPermissions`.
- It does not make port 22 an agent hop.
