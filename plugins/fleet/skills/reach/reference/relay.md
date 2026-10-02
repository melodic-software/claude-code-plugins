# Cross-lane relay

Read this for the detail behind a route matrix row: how each hop works, the named receiver, how a
reply comes back, and what each route was tested to do. The hub's matrix and verbs are enough for a
plain prompt.

## Contents

- [Why a relay is needed at all](#why-a-relay-is-needed-at-all)
- [The hops](#the-hops)
- [A named receiver](#a-named-receiver)
- [Multi-turn and the open pipe](#multi-turn-and-the-open-pipe)
- [Background sessions](#background-sessions)
- [Mechanisms not used here](#mechanisms-not-used-here)
- [Getting a reply back](#getting-a-reply-back)
- [Signed-out Windows lane](#signed-out-windows-lane)
- [Verified behavior](#verified-behavior)
- [What the relay does not change](#what-the-relay-does-not-change)

## Why a relay is needed at all

Each lane has its own account and its own session registry. A WSL session and a native Windows
session on one computer register under different home directories and listen on different socket
types, so neither appears in the other's listing; across machines, Remote Control lists only the
signed-in account's sessions. A peer listing that comes back empty or lane-only is this, not a
permissions problem.

The relay closes the gap by starting a headless turn inside the target lane. That turn is
same-lane with the target's sessions, so its peer tools list and message them normally.

## The hops

**WSL to this machine's Windows (R1).** WSL interop runs a Windows binary by absolute path:

```console
cd /mnt/c/Users/<user>/<scratch> && /mnt/c/Users/<user>/.local/bin/claude.exe -p "<prompt>" < /dev/null
```

The `cd` matters: `claude.exe` needs a Windows-side working directory. Inside an sshd session
interop still answers by absolute path even though `$WSL_INTEROP` is unset there; do not probe with
`cmd.exe /c`, which prints nothing in that session.

**Windows to this machine's WSL (R4).** Take the distro name from `wsl.exe -l -q`, and run the
account's login shell so `claude` is on `PATH`:

```console
wsl.exe -d <distro> --cd /tmp --exec <shell> -lc 'claude -p "<prompt>" < /dev/null'
```

Use `--exec`, not `--`: with `--` the distro's login shell re-parses the tail first. A
native-Windows Claude runs this through its Bash tool, which is Git Bash, so bash quoting applies
(`'\''` for an apostrophe); through its PowerShell tool, pwsh quoting applies (`''`).

**Either lane to another machine (R2, R3, R5, R6).** The hop is always the target's WSL sshd
(`<wsl-alias>`, port 2222), through the Windows OpenSSH client. For the target's WSL lane, run
`claude` there. For its Windows lane, chain R1 on the far side:

```console
<ssh> <wsl-alias> 'cd /mnt/c/Users/<user>/<scratch> && /mnt/c/Users/<user>/.local/bin/claude.exe -p "<prompt>" < /dev/null'
```

That turn runs as the target's Windows console account, signed into the target's Windows lane.
Port 22 is never the agent hop: `ssh-admin` has no Claude sign-in.

FLEET.md renders these with the real aliases and profile path; prefer copying from it over
expanding placeholders by hand.

## A named receiver

A headless receiver is a `-p` turn with a name and inbound messages switched on:

```console
claude -p -n <name> --settings '{"crossSessionInbound":"accept"}' "<standing instructions>" < /dev/null
```

- Without `crossSessionInbound: accept`, a `-p` turn does not take messages unattended. An
  interactive session in default or auto mode accepts by default and needs no setting.
- The receiver lives as long as its turn. Its standing instructions say what to do with each
  message and when to stop.
- Inside an outer single-quoted remote command, the JSON's single quotes would close the outer
  quote. Double-quote it with escaped inner quotes instead:
  `<ssh> <wsl-alias> 'claude -p -n <name> --settings "{\"crossSessionInbound\":\"accept\"}" "<instructions>" < /dev/null'`.
- It ends when its turn ends. The tested receiver kept its turn open (a standing instruction to
  wait, then print what arrived) and ran under `nohup ... &` on the target. For a session that must
  stay up, use a [background session](#background-sessions) instead.
- Do not start it with `--bare`: a bare session binds no inbox socket and receives nothing.

## Multi-turn and the open pipe

Per-turn resume survives a disconnect. Choose the id up front so nothing parses output:

```console
<ssh> <wsl-alias> 'cd <dir> && claude -p --session-id <uuid> "<prompt>" < /dev/null'
<ssh> <wsl-alias> 'cd <dir> && claude -p --resume <uuid> "<prompt>" < /dev/null'
```

Take `<uuid>` from `uuidgen`, or `/proc/sys/kernel/random/uuid` where `uuidgen` is missing.

One open pipe keeps a single process and its context for as long as the connection stays open,
with user messages as NDJSON lines on stdin:

```console
<producer of NDJSON user messages> | <ssh> <wsl-alias> 'claude -p --input-format stream-json --output-format stream-json --verbose'
```

Two turns sent this way came back under one session id with the first turn's context. The CLI
docs do not specify the stdin message schema; the Agent SDK's `SDKUserMessage` type is the de facto
one. Losing the connection ends the process, so resume by its session id afterwards.

## Background sessions

For a session that outlives the hop, the target lane's own supervisor hosts it:

```console
<ssh> <wsl-alias> 'cd <trusted-dir> && claude --bg --name <name> "<prompt>" < /dev/null'
<ssh> <wsl-alias> 'claude agents --json --all'
<ssh> <wsl-alias> 'claude stop <id> && claude rm <id>'
```

- The directory must be trusted: run `claude` there interactively once and accept the prompt.
  Anywhere else the start fails with ``Workspace not trusted. Run `claude` in <dir> once and accept
  the trust prompt, then retry.`` and exit 1.
- `claude agents --json --all` reports each session's `id`, `name`, `status` and `state` (for
  example `busy`/`working`, then `idle`/`blocked`). Poll it to know when a session is done.
- `claude logs` takes only the short `id`, not the name (`No job matching '<name>'`), and prints the
  raw ANSI TUI stream. Read a reply from the transcript with `--resume <id>` instead.
- `--bg` cannot be combined with `-p`. A running background session binds an inbox socket, so a
  later relay turn in that lane can list and message it. `claude --resume <id> --bg "<prompt>"`
  continues a finished one.
- `claude --bg --exec '<cmd>'` runs a shell job the same way, for a script that must survive the
  hop. Untested.
- Agent view is a research preview. Basis: <https://code.claude.com/docs/en/agent-view>, fetched
  2026-09-29 against 2.1.284; recheck when a release note names `--bg` or `claude agents`.

## Mechanisms not used here

Each fails the fleet's per-lane account split or needs a human; see the linked page before
reconsidering one. Fetched 2026-09-29 against 2.1.284; recheck when a release note names the
mechanism.

- **Remote Control and cross-machine `SendMessage`**: same claude.ai account only, and
  interactive only: `claude -p --remote-control` does not connect (the flag takes the next word as
  a session name, and the turn shows no bridge event).
  <https://code.claude.com/docs/en/cross-session-messaging#message-sessions-on-other-machines>
- **Cloud sessions** (`claude -p "<msg>" --cloud <id>`): same account, and no CLI read-back of the
  reply. <https://code.claude.com/docs/en/claude-code-on-the-web>
- **Channels**: research preview; a custom channel needs
  `--dangerously-load-development-channels`, which asks for confirmation at launch.
  <https://code.claude.com/docs/en/channels>
- **The inbox socket from a script**: only the auth line is documented, not the message format, so
  do not script against it. <https://code.claude.com/docs/en/cross-session-messaging>
- **Agent teams**: one team per session, and nothing crosses a lane.
  <https://code.claude.com/docs/en/agent-teams>

## Getting a reply back

A relay turn returns when it is done; a peer's answer that arrives later is not in its output.

There is no one-turn query and wait. A `-p` relay turn that sends with `notify_when_idle` ends
before the notice arrives: in the test the message was delivered, and the relay returned after 18
seconds still saying it was waiting. Instead:

- **Poll.** Send the message, then poll `claude agents --json --all` in that lane until the
  receiver is idle.
- **Read the receiver.** `--resume` the receiver by its id and ask what it answered, or read its
  output (a `-p` receiver's stdout log).
- **Ask directly.** When no live session needs the question, skip messaging: a multi-turn
  `--resume` on the target is the query, and its output is the answer.

## Signed-out Windows lane

Check the target Windows lane before relying on it:

```console
<ssh> <wsl-alias> 'cd /mnt/c/Users/<user>/<scratch> && /mnt/c/Users/<user>/.local/bin/claude.exe -p "echo ok" < /dev/null'
```

`Failed to authenticate: OAuth session expired and could not be refreshed` means the route worked
and the Windows lane on the target is signed out. The fix is `/login` at that machine's console
(or over RDP, which is always the console account). Do not try to fix it remotely, and never move a
credential through a prompt or a copy.

## Verified behavior

Claim: the per-lane account model and the route results below. Basis: live probes between
melo-desk-001 and melo-lap-001, each lane on its own claude.ai sign-in. As of 2026-09-29, Claude
Code 2.1.284. Recheck when a Claude Code release note touches `ListAgents`, `SendMessage`, Remote
Control session listing, `crossSessionInbound` or `-n`/`--name`, or when a route below fails its
hop check.

The documented flag behavior the hub restates (`notify_when_idle` is same-machine only, `--bare`
binds no inbox socket, `--bg` rejects `-p`, `--session-id` takes a UUID, a `-p` receiver needs
`crossSessionInbound: accept`) rests on
<https://code.claude.com/docs/en/cross-session-messaging>,
<https://code.claude.com/docs/en/cli-reference> and <https://code.claude.com/docs/en/agent-view>,
fetched 2026-09-29 against 2.1.284. Recheck when a release note names any of those flags.

| Route | Result |
|---|---|
| Same machine, WSL and Windows lanes | Each lane's `ListAgents` shows only its own lane |
| Remote Control across accounts | `ListAgents` shows nothing remote while Remote Control is connected |
| R1 WSL to this machine's Windows | `powershell.exe -NoProfile -Command` ran a script. `claude.exe -p` listed the Windows sessions; `--session-id` then `--resume` recalled a word from the first turn; a second `claude.exe -p` messaged the receiver `claude.exe -p -n win-relay-target`, which acknowledged mid-turn |
| R2 WSL to other machine's WSL | A plain command ran over ssh. `claude -p "SendMessage to <name> ..."` delivered to an interactive session and to a `-p -n` receiver with `crossSessionInbound: accept`, across accounts. `--session-id` then `--resume` recalled a word. One stream-json pipe ran two turns under one session id. `--bg` started in a trusted directory and failed in an untrusted one; `agents --json --all`, `stop` and `rm` worked; `logs` accepted only the id |
| R3 WSL to other machine's Windows | Reached the target's `claude.exe`: `auth status` reported `loggedIn: false`, and `-p` failed with the OAuth expired error |
| R4 Windows to this machine's WSL | A native-Windows `claude.exe -p` ran `wsl.exe -d <distro> --cd /tmp --exec zsh -lc 'hostname; echo ok-exec'` with its Bash tool (Git Bash) and printed the WSL hostname and `ok-exec`. Through the same tool, `'what'\''s up'` arrived intact and `'what''s up'` arrived as `whats up`. Separately, a `claude -p` over this hop listed the WSL sessions |
| R5, R6 from a Windows origin | Untested; same far-side hop as R2 and R3 |
| Port 22 script hop | Not probed in this pass |
| `notify_when_idle` from a `-p` sender | Message delivered; the notice never reached the sender, whose turn ended first |
| `-p --remote-control` | Did not connect; Remote Control is interactive only |
| Cost | Most of each one-line `-p` turn's cost was SessionStart hooks and context loading; measure a turn per <https://code.claude.com/docs/en/costs#track-your-costs>, as of 2026-10-02; recheck when that section renames or replaces its tracking commands |

## What the relay does not change

- It does not merge accounts. The relay turn sees the target's sessions because it runs in the
  target lane, under that lane's account. Nothing lets this lane's account see them.
- It does not bypass permissions. It starts an agent in another lane, so it prompts under auto
  mode, and neither side runs `bypassPermissions`.
- It does not make port 22 an agent lane.
