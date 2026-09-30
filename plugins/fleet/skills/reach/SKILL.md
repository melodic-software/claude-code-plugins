---
description: "Reach another Claude Code lane in the fleet, on this machine or another, to run, prompt, query, message or start a session, with no human copying prompts. Use when: 'run this on <host>', 'ask the desktop to', 'cross-machine', 'remote agent', 'reach the fleet', 'message the Windows session', 'from WSL to Windows'. Not for: a session in THIS lane (ListAgents/SendMessage), a detached local background session (session-flow:continue-in-background), or repository fleets (repo-fleet-hygiene)."
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
| R1 | WSL | this machine, Windows | `cd <win-dir> && <claude-exe> <agent-args> < /dev/null` | tested: script (`powershell.exe`), list, multi-turn, message a `-n` receiver |
| R2 | WSL | other machine, WSL | `<ssh> <wsl-alias> 'claude <agent-args> < /dev/null'` | tested: script, multi-turn, stream-json, `--bg`, message an interactive session and a `-p` receiver across accounts |
| R3 | WSL | other machine, Windows | `<ssh> <wsl-alias> 'cd <win-dir> && <claude-exe> <agent-args> < /dev/null'` | reaches `claude.exe`; needs `/login` at that machine's console |
| R4 | Windows | this machine, WSL | `wsl.exe -d <distro> --cd /tmp --exec <shell> -lc 'claude <agent-args> < /dev/null'` | tested: script from a native-Windows `claude.exe` (its Bash tool, Git Bash); list |
| R5 | Windows | other machine, WSL | `ssh.exe <wsl-alias> 'claude <agent-args> < /dev/null'` | untested from a Windows origin (same hop as R2) |
| R6 | Windows | other machine, Windows | `ssh.exe <wsl-alias> 'cd <win-dir> && <claude-exe> <agent-args> < /dev/null'` | untested from a Windows origin (same hop as R3) |

A script with no agent goes over the same hop with the command in place of the `claude` part; on
R1 that is `powershell.exe -NoProfile -Command '<cmd>'` from a Windows-side directory. The exception is a Windows script on another machine, which goes over port 22 instead:
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

Each verb fills `<agent-args>` in a matrix row. All but the first start an agent, and each agent
turn costs real usage (about 22 to 31 US cents for a one-line turn, mostly SessionStart hooks and
context loading). When a script can do the job, run the script.

| Verb | `<agent-args>` | Status |
|---|---|---|
| Run a script | none: the command itself replaces `claude ...` over the same hop | tested on R1, R2, R4; port 22 untested |
| Prompt | `-p "<prompt>"` | tested on R1, R2, R4 |
| Multi-turn | `-p --session-id <uuid> "<prompt>"`, then `-p --resume <uuid> "<prompt>"` against the same lane | tested on R1, R2 |
| One open pipe | `-p --input-format stream-json --output-format stream-json --verbose`, user messages as NDJSON on stdin | tested on R2 |
| List sessions | `-p "List the sessions you can reach"` | tested on R1, R4 |
| Message a session | `-p "SendMessage to <name>: <text>"` | tested on R1, R2 |
| Named receiver | `-p -n <name> --settings '{"crossSessionInbound":"accept"}' "<standing instructions>"` | tested on R1, R2 |
| Background session | `--bg --name <name> "<prompt>"`, not `-p`; manage with `claude agents --json --all`, `stop <id>`, `rm <id>` | tested on R2, trusted directory only |

- Give every prompt the whole task: what done looks like, and what should make it stop and report.
  Nobody answers a question a headless turn asks.
- **Query and wait has no one-turn form.** `notify_when_idle` from a `-p` sender does not work: the
  turn ends before the notice arrives. Send the message, then poll `claude agents --json` in that
  lane, or `--resume` the receiver or read its output.
- **Multi-turn versus one open pipe.** The pipe keeps context in one process while the connection
  stays open. Per-turn `--resume` survives a disconnect. `--session-id` picks the id up front, so
  nothing parses the first turn's output; use a UUID from `/proc/sys/kernel/random/uuid` where
  `uuidgen` is missing.
- **Background sessions** need a trusted working directory. Anywhere else the start fails with
  ``Workspace not trusted. Run `claude` in <dir> once and accept the trust prompt`` and exit 1.
  `claude logs` takes only the short id, not the name, and prints raw TUI output, so read a reply
  from the transcript (`--resume <id>`), not from `logs`.
- An interactive session in a prompting mode (default or auto) accepts inbound messages. A `-p`
  receiver needs `crossSessionInbound: accept`, and lives only as long as its turn.
- `--bare` cuts the per-turn cost but binds no inbox socket, so a bare session cannot receive
  messages or be listed. Use it for prompts, never for a receiver.
- Remote Control is interactive only: `-p --remote-control` does not connect. Keep it out of
  headless recipes.
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
  quotes on the LOCAL shell, so a `'` in the prompt ("what's") closes that quote early. The rule
  follows the origin shell, not the lane:
  - **bash, zsh, and Git Bash** (a native-Windows Claude's Bash tool, R4 to R6): replace each `'`
    with `'\''`, or wrap the command in `$'...'` and write `\'`. Doubling (`''`) silently drops the
    apostrophe here: `'what''s'` arrives as `whats`.
  - **pwsh** (a native-Windows Claude's PowerShell tool, or a pwsh terminal): double it, `''`.
- **Use `wsl.exe --exec`, not `--`.** With `--`, the distro's login shell re-parses the rest of the
  line before `<shell> -lc` sees it; `--exec` hands the arguments over as they are.
- **Probe interop by absolute path.** `cmd.exe /c` prints nothing inside an sshd session and reads
  as "interop is broken" when it is not; run the `.exe` by absolute path.
- **Parse the JSON, not the stream.** `SessionEnd` hooks print `Hook cancelled` on stdout. Extract
  the object first, for example `grep '^{' | jq -r .session_id`.
- **A session name is not an address.** Hostname and lane, always.
