---
description: "Reach another Claude Code lane in the fleet, here or remote, to run, prompt, query or message it or start a session, with no human copying prompts. Use when: 'run this on HOST', 'ask the desktop to', 'cross-machine', 'remote agent', 'reach the fleet', 'message the Windows session', 'from WSL to Windows'. Not for: a session in THIS lane (ListAgents/SendMessage), a detached local background session (session-flow:continue-in-background), or repository fleets (repo-fleet-hygiene)."
argument-hint: "[relay]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Reach another fleet lane (WSL or Windows, here or remote) to run, prompt, query or message
---

## Purpose

A **lane** is one Claude Code install with its own sign-in: the WSL distro or native Windows, on
each machine. From any lane this reaches every other lane: run a script there, prompt it, query it
and wait, message one of its sessions, or start a named session in it.

**WSL is the default agent lane**: it has the repos, the toolchain and sshd. Use native Windows
only for Windows-only work and Windows-side sessions.

## Route matrix

`<agent>` is the headless turn from [Verbs](#verbs): `claude` in a WSL lane, `<claude-exe>` in a
Windows lane. "Tested" means a real run of that exact shape; what each run showed is in
[reference/relay.md § Verified behavior](reference/relay.md#verified-behavior).

| # | From | To | Command shape | Status |
|---|---|---|---|---|
| R0 | any | same lane | Built-in `ListAgents` / `SendMessage`. Not this skill | n/a |
| R1 | WSL | this machine, Windows | `cd <win-dir> && <claude-exe> <agent-args> < /dev/null` | tested: script (`powershell.exe`), list, multi-turn, message a `-n` receiver |
| R2 | WSL | other machine, WSL | `<ssh> <wsl-alias> 'claude <agent-args> < /dev/null'` | tested: script, multi-turn, stream-json, `--bg`, message an interactive session and a `-p` receiver across accounts |
| R3 | WSL | other machine, Windows | `<ssh> <wsl-alias> 'cd <win-dir> && <claude-exe> <agent-args> < /dev/null'` | reaches `claude.exe`; needs `/login` at that machine's console |
| R4 | Windows | this machine, WSL | `wsl.exe -d <distro> --cd /tmp --exec <shell> -lc 'claude <agent-args> < /dev/null'` | tested: script from a native-Windows `claude.exe` (its Bash tool, Git Bash); list |
| R5 | Windows | other machine, WSL | `ssh.exe <wsl-alias> 'claude <agent-args> < /dev/null'` | untested from a Windows origin (same hop as R2) |
| R6 | Windows | other machine, Windows | `ssh.exe <wsl-alias> 'cd <win-dir> && <claude-exe> <agent-args> < /dev/null'` | untested from a Windows origin (same hop as R3) |

A script with no agent takes the same hop with the command in place of the `claude` part; on R1
that is `powershell.exe -NoProfile -Command '<cmd>'` from a Windows-side directory. A Windows
script on another machine goes over port 22 instead: `<ssh> <win-alias> '<pwsh command>'` (see
[Port 22](#port-22-is-not-an-agent-lane)).

Fill each placeholder from FLEET.md or a probe, never by guessing:

- `<ssh>`: the Windows OpenSSH client. `ssh.exe` from Windows; from WSL,
  `/mnt/c/Windows/System32/OpenSSH/ssh.exe`, because the distro holds no key.
- `<wsl-alias>` / `<win-alias>`: the target's `wsl-shell` (port 2222) and `windows-shell` (port 22)
  aliases.
- `<claude-exe>`: `/mnt/c/Users/<user>/.local/bin/claude.exe`, by absolute path.
- `<win-dir>`: a scratch directory under `/mnt/c/Users/<user>/` (`claude.exe` needs a Windows-side
  working directory), never a repository that defines the fleet's accounts or firewall.
- `<distro>`: from `wsl.exe -l -q`. `<shell>`: the distro account's login shell, so `claude` is on
  `PATH`.

[reference/relay.md](reference/relay.md) holds the per-route hop detail, the named receiver and its
nested quoting, background sessions, reply patterns, and the mechanisms not used here (Remote
Control, cloud sessions, Channels). Read it when a row or verb needs more than its cell.

## Resolve the target first

1. Read `~/.config/fleet/FLEET.md` before composing anything: it is rendered per machine with the
   real aliases, accounts and paths. Done when you can name the target host and lane and see its
   reach entries (alias, port, account, shell).
2. Pick the lane by the work: agent work goes to WSL; Windows-only work or a Windows-side session
   goes to Windows. Done when you hold a matrix row and every placeholder in it.
3. A host absent from FLEET.md is not a fleet host: say so and stop. Address machines by hostname
   over the tailnet, never by session name.

## Verify the hop before you trust it

Run the row with `hostname && <agent> -p "echo ok"` as the agent part. The hostname proves which
machine answered; `ok` proves that lane's Claude is signed in. A Windows lane that answers with an
expired-OAuth-session authentication error routed correctly and is signed out: someone runs
`/login` at that machine's console (or over RDP). Nothing remote fixes it, and no credential
travels in a prompt.

- **Pointer**: when matching a lane's answer to a signed-out state, fetch
  [Login expired](https://code.claude.com/docs/en/errors#login-expired) live. **As of**:
  2026-10-11. **Recheck trigger**: that entry's message text changes.

## Verbs

Each verb fills `<agent-args>` in a matrix row. Every verb but the first starts an agent, and each
agent turn costs real usage, even a one-line turn, mostly from SessionStart hooks and context
loading (how to read it:
[Manage costs: Track your costs](https://code.claude.com/docs/en/costs#track-your-costs); the dated
measurement and how to re-measure are in the Cost row of
[reference/relay.md § Verified behavior](reference/relay.md#verified-behavior)). When a script can
do the job, run the script.

| Verb | `<agent-args>` | Status |
|---|---|---|
| Run a script | none: the command replaces `claude ...` over the same hop | tested on R1, R2, R4; port 22 untested |
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
  stays open; per-turn `--resume` survives a disconnect. `--session-id` picks the id up front, so
  nothing parses the first turn's output; take a UUID from `/proc/sys/kernel/random/uuid` where
  `uuidgen` is missing. `--resume` ids belong to the lane that made them: resume against the same
  row.
- **Background sessions** need a trusted working directory; anywhere else the start fails with a
  workspace-not-trusted error and exit 1 (for its wording and fix, fetch
  [Workspace not trusted when dispatching a background session](https://code.claude.com/docs/en/errors#workspace-not-trusted-when-dispatching-a-background-session)
  live; as of 2026-10-11; recheck when that entry's message or fix changes). Address `claude logs`
  and `claude attach` by the `id` from `claude agents --json --all` (bare `--json` lists only
  active sessions), so a lane on an older CLI behaves like a current one; pass a name only after
  checking the lane's version against the CLI reference. `logs` prints raw TUI output, so read a
  reply from the transcript (`--resume <id>`), not from `logs`.
  - **Pointer**: when deciding whether a lane can take a session name in place of the id, fetch
    [CLI reference: CLI commands](https://code.claude.com/docs/en/cli-reference#cli-commands) live.
    **As of**: 2026-10-10. **Recheck trigger**: the `claude logs` or `claude attach` row changes.
- A `-p` receiver needs `crossSessionInbound: accept`; delivery rules and the pointer are in
  [reference/relay.md § A named receiver](reference/relay.md#a-named-receiver).
- `--bare` cuts the per-turn cost but binds no inbox socket, so a bare session cannot receive
  messages or be listed. Use it for prompts, never for a receiver.
- Remote Control is interactive only: `-p --remote-control` does not connect. Keep it out of
  headless recipes.
- Session names belong to the target lane. List first, then message a name from that list.
- **Pointer**: the receiver, `--bare` and Remote Control bullets rest on our probes and the flag
  behavior in [reference/relay.md § Verified behavior](reference/relay.md#verified-behavior); when
  one stops holding, fetch
  [Control inbound messages](https://code.claude.com/docs/en/cross-session-messaging#control-inbound-messages),
  [Non-interactive sessions](https://code.claude.com/docs/en/cross-session-messaging#non-interactive-sessions)
  and [CLI flags](https://code.claude.com/docs/en/cli-reference#cli-flags) live. **As of**:
  2026-10-18 for the two cross-session sections; 2026-10-11 for the CLI flags. **Recheck
  trigger**: a release note names `crossSessionInbound`, `--bare`, `--bg`, `--session-id` or
  Remote Control, or a route fails its hop check.

## Accounts are per lane

Each lane signs into its own claude.ai account, deliberately, so one lane's usage never draws down
another's. On melo-desk-001 the WSL and Windows lanes use different accounts; the laptop's WSL lane
uses a third. So:

- **Same lane.** Sessions find each other through files and sockets; the peer tools work.
- **Other lane, same machine.** WSL and Windows register under different homes and socket types.
  Each lane's `ListAgents` shows only its own lane.
- **Other machine.** Remote Control lists only the signed-in account's sessions. Across accounts
  `ListAgents` shows nothing remote, even with Remote Control connected.

The peer tools are same-lane only, and no setting widens them. Every other route starts a turn
inside the target lane, where the peer tools are local. Do not propose sharing an account: the
split is the decision, not an oversight.

- **Pointer**: the three facts are our probes' results
  ([reference/relay.md § Verified behavior](reference/relay.md#verified-behavior)); when one is in
  doubt, fetch
  [See which sessions Claude can reach](https://code.claude.com/docs/en/cross-session-messaging#see-which-sessions-claude-can-reach)
  and
  [Message sessions on other machines](https://code.claude.com/docs/en/cross-session-messaging#message-sessions-on-other-machines)
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: either section changes which sessions a session can see or reach across
  platforms, machines or accounts.

## Port 22 is not an agent lane

`ssh-admin` is a separate Windows account with no Claude sign-in and no DPAPI. Use port 22 for pwsh
scripts only, with pwsh quoting; anything needing the console user's credentials goes through the
on-demand tasks FLEET.md lists.

## Permission and safety posture

- Every verb except running a script starts an agent in another lane, same machine included, and
  these prompt under auto mode. That is intended; let them prompt. A script is judged on its own
  content. When a prompt's cause is in doubt, fetch
  [Eliminate prompts with auto mode](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode)
  live (as of 2026-10-11; recheck when that section changes what the classifier lets through
  for remote commands).
- There is no `Bash(ssh ...)` allow rule anywhere in this fleet, and adding one is not the fix for a
  prompt. If asked to stop the prompting, say what the rule would cost and decline.
- Neither side runs `bypassPermissions`.
- Never `wsl --shutdown` on a target, and never run `wsl -d` on a target's drift-convergence path:
  both take the distro out from under whatever else is using it.
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
