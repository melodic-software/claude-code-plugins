---
description: "Reach any other Claude Code lane in the fleet: the other lane on this machine (WSL or native Windows) or either lane on another machine. Run a script there, prompt it, query and wait, message a live session, or start a named one, with no human copying prompts between terminals. Accounts are per lane, so the peer tools (`ListAgents`, `SendMessage`) see only this lane; this skill starts a headless turn IN the target lane, where they work. Carries the route matrix, target resolution from `~/.config/fleet/FLEET.md`, the verbs, the permission posture and the gotchas. Use when: 'run this on melo-desk-001', 'ask the desktop to', 'spawn claude on the other machine', 'cross-machine', 'remote agent', 'reach the fleet', 'run claude over ssh', 'message the Windows session', 'from WSL to Windows'. Not for: a session in THIS lane (the built-in peer tools own that), a detached local background session (session-flow:continue-in-background), or repository fleets (repo-fleet-hygiene)."
when_to_use: "a request names another machine or the other lane on this one, or asks for work to happen somewhere other than this session's lane"
argument-hint: "[relay]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Reach another fleet lane (WSL or Windows, here or remote) to run, prompt, query or message
---

## Purpose

One procedure for agent-to-agent reach across the fleet. A **lane** is one Claude Code install
with its own sign-in: the WSL distro or native Windows, on each machine. From any lane this reaches
every other lane: run a script there, prompt it, query it and wait, message one of its sessions, or
start a named session in it.

Prefer the richest lane for the work. **WSL is the default agent lane**: it has the repos, the
toolchain and sshd. Use native Windows only for Windows-only work and Windows-side sessions.

Read `~/.config/fleet/FLEET.md` before composing anything. It is rendered per machine and carries
the real aliases, accounts and paths; the commands below are the same commands with placeholders.

## Route matrix

Find the row for where you are and where the work goes. `<agent>` is the headless turn from
[Verbs](#verbs); in a WSL lane it is `claude`, in a Windows lane `<claude-exe>`. "Tested" means a
real run of that exact shape; see [reference/relay.md](reference/relay.md#verified-behavior) for
what each run showed.

| # | From | To | Command shape | Status |
|---|---|---|---|---|
| R0 | any | same lane | Built-in `ListAgents` / `SendMessage`. Not this skill | n/a |
| R1 | WSL | this machine, Windows | `cd <win-dir> && <claude-exe> <agent-args> < /dev/null` | tested: list, message a `-n` receiver |
| R2 | WSL | other machine, WSL | `<ssh> <wsl-alias> 'claude <agent-args> < /dev/null'` | tested: message an interactive session across accounts |
| R3 | WSL | other machine, Windows | `<ssh> <wsl-alias> 'cd <win-dir> && <claude-exe> <agent-args> < /dev/null'` | tested up to auth: needs the target's Windows lane signed in |
| R4 | Windows | this machine, WSL | `wsl.exe -d <distro> --cd /tmp -- <shell> -lc 'claude <agent-args> < /dev/null'` | tested: list |
| R5 | Windows | other machine, WSL | `ssh.exe <wsl-alias> 'claude <agent-args> < /dev/null'` | untested from a Windows origin (same hop as R2) |
| R6 | Windows | other machine, Windows | `ssh.exe <wsl-alias> 'cd <win-dir> && <claude-exe> <agent-args> < /dev/null'` | untested from a Windows origin (same hop as R3) |

A script with no agent goes over the same hop with the command in place of the `claude` part.
The exception is a Windows script on another machine, which goes over port 22 instead:
`<ssh> <win-alias> '<pwsh command>'` (see [Port 22](#port-22-is-not-an-agent-lane)).

Placeholders, each filled from FLEET.md or a probe, never guessed:

- `<ssh>`: the Windows OpenSSH client. `ssh.exe` from Windows; from WSL,
  `/mnt/c/Windows/System32/OpenSSH/ssh.exe`, because the distro holds no key.
- `<wsl-alias>` / `<win-alias>`: the target's `wsl-shell` (port 2222) and `windows-shell` (port 22)
  aliases.
- `<claude-exe>`: `/mnt/c/Users/<user>/.local/bin/claude.exe`, by absolute path.
- `<win-dir>`: a scratch directory under `/mnt/c/Users/<user>/`, never a repository that defines the
  fleet's accounts or firewall. `claude.exe` needs a Windows-side working directory.
- `<distro>`: from `wsl.exe -l -q`. `<shell>`: the distro account's login shell, so `claude` is on
  `PATH`.

Per-route detail, the receiver and the reply patterns are in [reference/relay.md](reference/relay.md).

## Resolve the target first

1. Read `~/.config/fleet/FLEET.md`. Done when you can name the target host and lane and see its
   reach entries (alias, port, account, shell).
2. Pick the lane by the work: agent work goes to WSL; Windows-only work or a Windows-side session
   goes to Windows. Done when you hold a concrete row from the matrix and every placeholder in it.
3. A host absent from FLEET.md is not a fleet host. Say so and stop. Machines are addressed by
   hostname over the tailnet, never by session name.

## Verify the hop before you trust it

Run the row with `hostname && <agent> -p "echo ok"` as the agent part. The hostname proves which
machine answered; `ok` proves that lane's Claude is signed in. A Windows lane that answers
`Failed to authenticate: OAuth session expired and could not be refreshed` routed correctly and is
signed out: someone runs `/login` at that machine's console (or over RDP). Nothing remote fixes it,
and no credential travels in a prompt.

## Verbs

Each verb fills `<agent-args>` in a matrix row. All but the first start an agent.

| Verb | `<agent-args>` | Status |
|---|---|---|
| Run a script | none: the command itself replaces `claude ...` over the same hop | tested (the hops) |
| Prompt | `-p "<prompt>"` | tested |
| Multi-turn | `-p --session-id <uuid> "<prompt>"`, then `-p --resume <uuid> "<prompt>"` against the same lane | untested |
| List sessions | `-p "List the sessions you can reach"` | tested |
| Message a session | `-p "SendMessage to <name>: <text>"` | tested |
| Query and wait | `-p "SendMessage to <name> with notify_when_idle: <question>. Wait for the reply and print it."` | untested |
| Named receiver | `-p -n <name> --settings '{"crossSessionInbound":"accept"}' "<standing instructions>"` | tested on R1 only |
| Background session | `--bg --name <name> "<prompt>"`, not `-p`; manage with `claude agents --json`, `logs`, `stop` | untested |

- Give every prompt the whole task: what done looks like, and what should make it stop and report.
  Nobody answers a question a headless turn asks.
- A relay turn is one headless turn. A reply that arrives after it returns is not in its output:
  make it wait (query and wait), or read the reply with a second turn or `--resume`.
  `notify_when_idle` works only between sessions on one machine, which the relay turn is.
- An interactive session in a prompting mode (default or auto) accepts inbound messages. A `-p`
  receiver needs `crossSessionInbound: accept`, and lives only as long as its turn. `--bare` binds
  no inbox socket, so a bare turn can neither receive nor be listed.
- Session names belong to the target lane. List first, then message a name from that list.
- `--resume` ids belong to the lane that made them. Resume against the same row. `--session-id`
  picks the id up front, so nothing has to parse the first turn's output.

The receiver's nested quoting, background sessions, and the mechanisms not used here (Remote
Control, cloud sessions, Channels) are in [reference/relay.md](reference/relay.md).

## Accounts are per lane

Each lane signs into its own claude.ai account, deliberately, so one lane's usage never draws down
another's. On melo-desk-001 the WSL lane and the Windows lane use different accounts; the laptop's
WSL lane uses a third. Three facts follow:

- **Same lane.** Sessions find each other through files and sockets; the peer tools work.
- **Other lane, same machine.** WSL and Windows register under different homes and socket types.
  Each lane's `ListAgents` shows only its own lane.
- **Other machine.** Remote Control lists only the signed-in account's sessions. Across accounts
  `ListAgents` shows nothing remote, even with Remote Control connected.

So the peer tools are same-lane only, and no setting widens them. Every other route starts a turn
inside the target lane, where the peer tools are local. Do not propose sharing an account: the
split is the decision, not an oversight.

## Port 22 is not an agent lane

`ssh-admin` is a separate Windows account with no Claude sign-in and no DPAPI. Use port 22 for pwsh
scripts only, with pwsh quoting; anything needing the console user's credentials goes through the
on-demand tasks FLEET.md lists.

## Permission and safety posture

- Every verb except running a script starts an agent in another lane, same machine included. The
  auto-mode classifier reaches only read-only remote commands, so these prompt under auto mode.
  That is intended; let them prompt. A script is judged on its own content.
- There is no `Bash(ssh ...)` allow rule anywhere in this fleet, and adding one is not the fix for a
  prompt. If asked to stop the prompting, say what the rule would cost and decline.
- Neither side runs `bypassPermissions`.
- Never `wsl --shutdown` on a target, and never run `wsl -d` on a target's drift-convergence path.
  Both take the distro out from under whatever else is using it.
- The prompt travels in the command line, visible to the target's process table and shell history.
  No secret belongs in one.

## Boundary

| Neighbor | Owns |
|---|---|
| This skill | Every lane other than this session's: the other lane on this machine, and both lanes on other machines |
| Built-in `ListAgents` / `SendMessage` | Sessions in this lane, under this lane's account |
| Built-in Remote Control | Human use of a lane's session from a phone or the web, under that lane's account. Not agent-to-agent across accounts |
| `session-flow:continue-in-background` | A detached session in THIS lane |
| `session-flow:orchestrate` | Delegation inside one session, to subagents |
| `repo-fleet-hygiene:audit` | Fleets of REPOSITORIES. Same word, different subject |

## Gotchas

- **Use the Windows OpenSSH client.** It is agent-backed and is what `~/.ssh/config` is wired to.
  Git Bash's MSYS `ssh` reaches no agent and fails with `Permission denied (publickey)`, which reads
  like a key problem and is not one.
- **Redirect stdin, always.** `claude -p` reads stdin, so without `< /dev/null` (or `ssh -n`) it
  waits several seconds before answering every turn.
- **Escape apostrophes in `<prompt>`.** Every row except R1 wraps the remote command in single
  quotes on the LOCAL shell, so a `'` in the prompt ("what's") closes that quote early. In bash,
  replace each `'` with `'\''`, or wrap the command in `$'...'` and write `\'`. In pwsh (R4 to R6),
  double it: `''`.
- **Probe interop by absolute path.** `cmd.exe /c` prints nothing inside an sshd session and reads
  as "interop is broken" when it is not; run the `.exe` by absolute path.
- **Parse the JSON, not the stream.** `SessionEnd` hooks print `Hook cancelled` on stdout. Extract
  the object first, for example `grep '^{' | jq -r .session_id`.
- **A session name is not an address.** Hostname and lane, always.
