---
description: "Run a Claude Code agent turn on ANOTHER machine in the fleet, over SSH on the tailnet. Every machine signs into its own Claude account, so the peer tools (`ListAgents`, `SendMessage`) are same-account and never span machines; SSH plus a headless `claude -p` is the path that does. Carries: resolving a target host from `~/.config/fleet/FLEET.md`, the one-shot and multi-turn headless recipes for both SSH ports, the Windows-side relay that reaches a target's own native-Windows sessions, the permission and safety posture, a verification step, and the gotchas. Use when: 'run this on melo-desk-001', 'ask the desktop to', 'spawn claude on the other machine', 'cross-machine', 'remote agent', 'reach the fleet', 'run claude over ssh'. Not for: messaging a session on THIS machine (the built-in peer tools own that), a detached local background session (session-flow:continue-in-background), or repository fleets (repo-fleet-hygiene, where fleet means repos)."
when_to_use: "a request names another machine, or asks for work to happen somewhere other than here"
argument-hint: "[relay]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Run a Claude Code agent turn on another fleet machine over SSH
---

## Purpose

Getting an agent turn to happen on a machine that is not this one. The obvious route, asking the
peer tools to find the other machine's session, does not work here and cannot be made to: the
accounts are split on purpose. This carries the route that does, plus the reasons the shortcuts
fail, so neither gets rediscovered by trial.

Read `~/.config/fleet/FLEET.md` before composing anything. It is rendered per machine from the
fleet manifest and carries the real hosts, ports and accounts; the recipes below are the same
commands with placeholders where it has values.

## Resolve the target first

Machines are addressed by **hostname over the tailnet** (MagicDNS), never by session name. A
session name identifies a session, not a host, and nothing routes on it.

1. Read `~/.config/fleet/FLEET.md`. Done when you can name the target's MagicDNS host name and see
   its per-host table of reach entries, each carrying an `id`, transport, ssh `alias`, port,
   account and shell.
2. Pick the reach entry by what the work needs, not by what is first in the table. Agent work goes
   to `wsl-shell` (port 2222, the distro account, bash); Windows PowerShell work goes to
   `windows-shell` (port 22, `ssh-admin`, pwsh). Done when you hold a concrete port and account
   for the command you are about to compose, both read from the table rather than assumed.
3. If the host is absent from that file it is not a fleet host. Done by saying so and stopping;
   the manifest is the only inventory, and a guessed name reaches nothing.

## Verify the hop before you trust it

Cheap, and it separates "the host is unreachable" from "the agent over there is not signed in":

```console
ssh -p 2222 <wsl-user>@<host> 'hostname && claude -p "echo ok" < /dev/null'
```

The hostname proves which machine answered. `ok` proves that machine's Claude is authenticated and
working. Do this before sending a long or expensive prompt.

## One shot

```console
ssh -p 2222 <wsl-user>@<host> 'claude -p "<prompt>" < /dev/null'
```

The turn runs under the TARGET's account, config, plugins and usage limits. That is the point: the
work happens where its files and credentials already are, and it draws down that machine's window
rather than this one's.

## Multi-turn

The first call reports the session it created; resume by that id:

```console
ssh -p 2222 <wsl-user>@<host> 'claude -p --output-format json "<prompt>" < /dev/null'
ssh -p 2222 <wsl-user>@<host> 'claude -p --resume <session_id> "<prompt>" < /dev/null'
```

`--resume` finds the id on the machine that made it, in any project directory there. Ids do not
travel between hosts or accounts, so resume against the same host you started on.

## Port 22 is not an agent lane

`ssh-admin` is a separate Windows account with no Claude sign-in, so `claude` over port 22 has
nothing to run as. Use that hop for pwsh work only, and mind that its remote shell is PowerShell,
so the quoting differs from the bash hop:

```console
ssh -p 22 ssh-admin@<host> '<pwsh command>'
```

## Reaching the target's own sessions

A headless turn on port 2222 lands inside the WSL distro and sees only the distro's sessions. A WSL
session and a native Windows session on one computer register under different home directories and
listen on different socket types, so they cannot reach each other; that is documented behaviour,
not a misconfiguration.

To act on the target's Windows-side sessions, start a Windows `claude.exe` turn through the same
SSH hop. It runs as the target's Windows console account, so its peer tools are same-account there
and do work:

```console
ssh -p 2222 <wsl-user>@<host> 'cd /mnt/c/Users/<user>/claude-lane-sandbox && /mnt/c/Users/<user>/.local/bin/claude.exe -p "List the sessions you can reach" < /dev/null'
```

FLEET.md renders this with the real profile path. For the interop mechanics, the send and
wait-for-reply variants, and why the obvious `cmd.exe` probe misleads, read
[reference/relay.md](reference/relay.md).

## The account model, and why ListAgents is out

Every machine here signs into its OWN Claude account, deliberately, so one machine's usage limits
never draw down another's. Two different mechanisms follow, and conflating them is the usual error:

- **Same machine.** Sessions of the same OS user find each other through files and sockets. No
  account check is documented for that path.
- **Beyond this machine.** The only route is Remote Control, and it lists your own claude.ai
  sign-in's sessions. With the accounts split, another fleet machine's sessions are never listed
  and cannot be messaged.

So `ListAgents` and `SendMessage` are not the cross-machine path, and no setting makes them one.
Do not propose sharing an account: the split is the decision, not an oversight. The built-in Remote
Control session on a target serves that target's own account, opened from the Claude app signed
into it, which is the human path from a phone or the web.

## Permission and safety posture

- Starting an agent on another machine is **not** covered by the auto-mode classifier, which
  reaches only read-only remote commands. Both `claude -p` and the relay turn prompt under auto
  mode. That is intended; let them prompt.
- There is no `Bash(ssh ...)` allow rule anywhere in this fleet, and adding one is not the fix for
  a prompt. If asked to stop the prompting, say what the rule would cost and decline to add it.
- Neither side runs `bypassPermissions`.
- Never `wsl --shutdown` on a target, and never run `wsl -d` on a target's drift-convergence path.
  Both take the distro out from under whatever else is using it.
- The prompt travels in the command line, visible to the target's process table and shell history.
  No secret belongs in one.

## Boundary

| Neighbour | Owns |
|---|---|
| Built-in Remote Control | Interactive use of a target's session from a phone, the web, or another device, under THAT machine's account. Not agent-to-agent under split accounts |
| Built-in `ListAgents` / `SendMessage` | Sessions this session's own account can see; same machine, or same account through Remote Control |
| `session-flow:continue-in-background` | A detached session on THIS machine. Same host, no SSH |
| `session-flow:orchestrate` | Delegation inside one session, to subagents. Same host, same account |
| `repo-fleet-hygiene` | Fleets of REPOSITORIES. Same word, different subject |

## Gotchas

- **Use the Windows OpenSSH client.** `C:\Windows\System32\OpenSSH\ssh.exe` is agent-backed and is
  what `~/.ssh/config` is wired to. Git Bash's MSYS `ssh` reaches no agent and fails with
  `Permission denied (publickey)`, which reads like a key problem and is not one.
- **Redirect stdin, always.** `claude -p` reads stdin, so without `< /dev/null` inside the remote
  command (or `ssh -n` on the client) it waits several seconds before answering every turn.
- **Two shells, two quoting rules.** Single-quote the remote command and double-quote the prompt
  inside it. Port 2222 is bash; port 22 is pwsh, where that quoting does not carry over.
- **Parse the JSON, not the stream.** A relay turn's `SessionEnd` hooks print `Hook cancelled` on
  stdout. Take the JSON object out of the output before reading it, for example
  `grep '^{' | jq -r .session_id`, rather than piping the whole stream to `jq`.
- **`--resume` is per target account.** An id from one host means nothing on another.
- **A session name is not an address.** Hostname over the tailnet, always.
- **The relay's working directory matters.** It runs where the target's Remote Control task runs,
  a scratch checkout, never a repository that defines the fleet's own accounts or firewall rules.
