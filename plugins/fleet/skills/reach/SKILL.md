---
description: "Reach another Claude Code lane in the fleet, on any machine, to run, prompt, query, message or start a session. Use when: 'run this on HOST', 'ask the desktop to', 'cross-machine', 'remote agent', 'reach the fleet', 'message the Windows session', 'from WSL to Windows', 'share one account across lanes'. Not for: a session in THIS lane (ListAgents/SendMessage), a detached local background session (session-flow:continue-in-background), or repository fleets (repo-fleet-hygiene)."
argument-hint: "[relay]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Reach another fleet lane (WSL or Windows, here or remote) to run, prompt, query or message
---

## Resolve the target first

A **lane** is one Claude Code install with its own sign-in: the WSL distro or native Windows, on
each machine.

1. Read `~/.config/fleet/FLEET.md` before composing anything. It holds the real aliases, accounts
   and paths for this machine; the commands below use placeholders. Done when you can name the
   target host and lane and see its reach entries (alias, port, account, shell).
2. Pick the lane by the work. **WSL is the default agent lane** (repos, toolchain, sshd); use
   Windows only for Windows-only work or a Windows-side session. Done when you hold a matrix row
   with every placeholder filled.
3. A host absent from FLEET.md is not a fleet host: say so and stop. Address machines by hostname
   over the tailnet, never by session name.

## Route matrix

`<agent>` is the headless turn from [Verbs](#verbs): `claude` in a WSL lane, `<claude-exe>` in a
Windows lane. "Tested" means a real run of that exact shape; what each run showed is in
[reference/relay.md](reference/relay.md#verified-behavior). The R2 and R3 runs passed the prompt
as an argument; their stdin form below has not been re-probed.

| # | From | To | Command shape | Status |
|---|---|---|---|---|
| R0 | any | same lane | Built-in `ListAgents` / `SendMessage`. Not this skill | n/a |
| R1 | WSL | this machine, Windows | `cd <win-dir> && <claude-exe> <agent-args> "<prompt>" < /dev/null` | tested: script (`powershell.exe`), list, multi-turn, message a `-n` receiver |
| R2 | WSL | other machine, WSL | `printf '%s\n' '<prompt>' \| <ssh> <wsl-alias> 'claude <agent-args>'` | tested: script, multi-turn, stream-json, `--bg`, message an interactive session and a `-p` receiver across accounts |
| R3 | WSL | other machine, Windows | `printf '%s\n' '<prompt>' \| <ssh> <wsl-alias> 'cd <win-dir> && <claude-exe> <agent-args>'` | reaches `claude.exe`; needs `/login` at that machine's console |
| R4 | Windows | this machine, WSL | `wsl.exe -d <distro> --cd /tmp --exec <shell> -lc 'claude <agent-args> "<prompt>" < /dev/null'` | tested: script from a native-Windows `claude.exe` (its Bash tool, Git Bash); list |
| R5 | Windows | other machine, WSL | `printf '%s\n' '<prompt>' \| ssh.exe <wsl-alias> 'claude <agent-args>'` | untested from a Windows origin (same hop as R2) |
| R6 | Windows | other machine, Windows | `printf '%s\n' '<prompt>' \| ssh.exe <wsl-alias> 'cd <win-dir> && <claude-exe> <agent-args>'` | untested from a Windows origin (same hop as R3) |

Over SSH a `-p` turn's prompt goes on stdin, and the quoted remote command carries only the flags,
so no shell on either host parses prompt text. Never add `ssh -n` to an SSH row: it replaces stdin
with `/dev/null` and drops the prompt. The local hops (R1, R4) keep the prompt as the last
argument. A verb with no `<prompt>` drops the `printf` on an SSH row and the quoted prompt on R1
and R4. `--bg` is not `-p` and takes its prompt as an argument, so a background session's prompt
stays inside the remote command. In the tables here and in FLEET.md, `\|` is an escaped `|`: type a bare `|`.

A script with no agent goes over the same hop with the command in place of the `claude` part; on
R1 that is `powershell.exe -NoProfile -Command '<cmd>'` from a Windows-side directory. A Windows
script on another machine goes over port 22 instead: `<ssh> <win-alias> '<pwsh command>'` (see
[Port 22](#port-22-is-not-an-agent-lane)).

Placeholders, each filled from FLEET.md or a probe, never guessed:

- `<ssh>`: the Windows OpenSSH client. `ssh.exe` from Windows; from WSL,
  `/mnt/c/Windows/System32/OpenSSH/ssh.exe`, because the distro holds no key.
- `<wsl-alias>` / `<win-alias>`: the target's `wsl-shell` (port 2222) and `windows-shell` (port 22)
  aliases.
- `<claude-exe>`: `/mnt/c/Users/<user>/.local/bin/claude.exe`, by absolute path.
- `<win-dir>`: a scratch directory under `/mnt/c/Users/<user>/` (`claude.exe` needs a Windows-side
  working directory), never a repository that defines the fleet's accounts or firewall.
- Use FLEET.md's `/mnt/c` paths as given: never check them with file tools (Read, Glob, Grep),
  and never ask a subagent's brief to. The hop check in
  [Verify the hop](#verify-the-hop-before-you-trust-it) is what proves them.
- `<distro>`: from `wsl.exe -l -q`. `<shell>`: the distro account's login shell, so `claude` is on
  `PATH`.

Per-route detail, the receiver's nested quoting, reply patterns, background sessions, and the
mechanisms not used here (Remote Control, cloud sessions, Channels) are in
[reference/relay.md](reference/relay.md).

Converging dotfiles on any fleet lane is not a route in this matrix: run `fleet-converge <lane>`,
by its bare name. It does not prompt because dotfiles renders an exact allow rule for that command
on every lane; no `Bash(ssh …)` rule is added, and the posture below stands for every other verb.

- **Pointer**: for what `fleet-converge` checks and how it reaches each lane, read dotfiles
  [docs/design-decisions.md, "Converging a lane: `fleet-converge`"](https://github.com/melodic-software/dotfiles/blob/main/docs/design-decisions.md#converging-a-lane-fleet-converge).

## Verify the hop before you trust it

Run the row with `hostname &&` before the agent, `-p` as `<agent-args>` and `echo ok` as
`<prompt>`, for example `printf '%s\n' 'echo ok' | <ssh> <wsl-alias> 'hostname && claude -p'`: the
hostname proves which machine answered, `ok` that its Claude is signed in. A Windows lane answering with an
expired-OAuth-session authentication error routed correctly and is signed out: someone runs
`/login` at that machine's console (or over RDP). Nothing remote fixes it, and no credential
travels in a prompt.

- **Pointer**: when matching a lane's answer to a signed-out state, fetch
  [Login expired](https://code.claude.com/docs/en/errors#login-expired) live.

## Verbs

Each verb fills `<agent-args>` and `<prompt>` in a matrix row. Every verb but the first starts an
agent, and each agent turn costs real usage, even a one-line turn
([Manage costs: Track your costs](https://code.claude.com/docs/en/costs#track-your-costs); the Cost
row of [reference/relay.md § Verified behavior](reference/relay.md#verified-behavior) holds the
dated measurement and how to re-measure it). When a script can do the job, run the script.

| Verb | `<agent-args>` | `<prompt>` | Status |
|---|---|---|---|
| Run a script | none: the command itself replaces `claude ...` over the same hop | none | tested on R1, R2, R4; port 22 untested |
| Prompt | `-p` | the task | tested on R1, R2, R4 |
| Multi-turn | `-p --session-id <uuid>`, then `-p --resume <uuid>` against the same lane | each turn's prompt | tested on R1, R2 |
| One open pipe | `-p --input-format stream-json --output-format stream-json --verbose` | none: user messages as NDJSON on stdin | tested on R2 |
| List sessions | `-p` | `List the sessions you can reach` | tested on R1, R4 |
| Message a session | `-p` | `SendMessage to <name>: <text>` | tested on R1, R2 |
| Named receiver | `-p -n <name> --settings '{"crossSessionInbound":"accept"}'` | the standing instructions | tested on R1, R2 |
| Background session | `--bg --name <name> "<prompt>"`, not `-p`, with `< /dev/null` on an SSH row; manage with `claude agents --json --all`, `stop <id>`, `rm <id>` | none: it is in `<agent-args>` | tested on R2, trusted directory only |

- Give every prompt the whole task: what done looks like, and what should make it stop and report.
  Nobody answers a question a headless turn asks.
- **Query and wait has no one-turn form.** Never wait on a `notify_when_idle` notice from a `-p`
  sender: in our probe it never reached the sender
  ([reference/relay.md § Verified behavior](reference/relay.md#verified-behavior)). Send the
  message, then poll `claude agents --json` in that lane, or `--resume` the receiver or read its
  output.
  - **Pointer**: for how an idle notice is delivered and what a `-p` session can receive, fetch
    [Get a notice when another session goes idle](https://code.claude.com/docs/en/cross-session-messaging#get-a-notice-when-another-session-goes-idle)
    and [Non-interactive sessions](https://code.claude.com/docs/en/cross-session-messaging#non-interactive-sessions)
    live.
- **Multi-turn versus one open pipe.** The pipe keeps context in one process while the connection
  stays open; per-turn `--resume` survives a disconnect. `--resume` ids belong to the lane that
  made them, so resume against the same row. `--session-id` picks the id up front, so nothing
  parses the first turn's output. Generate no id in this session: a command you hand over keeps
  `<uuid>` for whoever runs it to fill, and a turn you run yourself can start with
  `--output-format json` and resume with the `session_id` it returns (see "Parse the JSON" in
  [Gotchas](#gotchas)). Say with the handed-over commands that the id exists only on that lane's
  machine and account, so every follow-up goes to the same row.
- **Background sessions** need a trusted working directory; anywhere else the start fails with a
  workspace-not-trusted error and exit 1 (for its wording and fix, fetch
  [Workspace not trusted when dispatching a background session](https://code.claude.com/docs/en/errors#workspace-not-trusted-when-dispatching-a-background-session)
  live; as of 2026-10-11; recheck when that entry's message or fix changes). Address
  `claude logs` and `claude attach` by the `id` from `claude agents --json --all` (bare `--json`
  lists only active sessions); pass a name only after checking the lane's version against the CLI
  reference. `logs` prints raw TUI output, so read a reply from the transcript (`--resume <id>`).
  - **Pointer**: when deciding whether a lane can take a session name in place of the id, fetch
    [CLI reference: CLI commands](https://code.claude.com/docs/en/cli-reference#cli-commands) live.
- A `-p` receiver needs `crossSessionInbound: accept`. For a session that must stay up, use a
  background session, not a `-p` receiver. Give either one standing instructions as its prompt:
  what to do with each message and when to stop. Delivery rules and the pointer are in
  [reference/relay.md](reference/relay.md#a-named-receiver).
  - **Pointer**: for when a `-p` run ends after its turn, fetch
    [Run Claude Code programmatically: Background tasks at exit](https://code.claude.com/docs/en/headless#background-tasks-at-exit)
    live.
- Use `--bare` for prompts, never for a receiver: a bare session cannot receive messages or be
  listed.
- Remote Control is interactive only: `-p --remote-control` does not connect. Keep it out of
  headless recipes.
- Session names belong to the target lane, and a listing shows only its own lane. List first, then
  message a name from the listing that shows it. When a request names a machine and not a lane,
  list each of that machine's lanes (on another machine, one R2 and one R3 turn).
- **Pointer**: the receiver, `--bare` and Remote Control bullets rest on our probes and the flag
  behavior in [reference/relay.md § Verified behavior](reference/relay.md#verified-behavior); when
  one stops holding, fetch
  [Control inbound messages](https://code.claude.com/docs/en/cross-session-messaging#control-inbound-messages),
  [Non-interactive sessions](https://code.claude.com/docs/en/cross-session-messaging#non-interactive-sessions),
  [Start faster with bare mode](https://code.claude.com/docs/en/headless#start-faster-with-bare-mode)
  and [CLI flags](https://code.claude.com/docs/en/cli-reference#cli-flags) live.

## Accounts are per lane

Each lane signs into its own claude.ai account so one lane's usage never draws down another's (on
the desktop, WSL and Windows differ; the laptop's WSL lane uses a third). So:

- **Same lane.** Sessions find each other through files and sockets; the peer tools work.
- **Other lane, same machine.** WSL and Windows register under different homes and socket types;
  each lane's `ListAgents` shows only its own lane.
- **Other machine.** Remote Control lists only the signed-in account's sessions; across accounts
  `ListAgents` shows nothing remote, even with Remote Control connected.

The peer tools are same-lane only, and no setting widens them; every other route starts a turn
inside the target lane. Do not propose sharing an account: the split is the decision.

- **Pointer**: the three facts are our probes' results
  ([reference/relay.md § Verified behavior](reference/relay.md#verified-behavior)); when one is in
  doubt, fetch
  [See which sessions Claude can reach](https://code.claude.com/docs/en/cross-session-messaging#see-which-sessions-claude-can-reach)
  and
  [Message sessions on other machines](https://code.claude.com/docs/en/cross-session-messaging#message-sessions-on-other-machines)
  live.

## Port 22 is not an agent lane

`ssh-admin` is a separate Windows account with no Claude sign-in and no DPAPI. Use port 22 for pwsh
scripts only, with pwsh quoting; anything needing the console user's credentials goes through the
on-demand tasks FLEET.md lists.

## Permission and safety posture

- Every verb except running a script starts an agent in another lane, same machine included, and
  these prompt under auto mode by design; let them prompt, and say so with every such command you
  run, delegate or hand over. A script is judged on its own content.
  When a prompt's cause is in doubt, fetch
  [Eliminate prompts with auto mode](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode)
  live.
- There is no `Bash(ssh ...)` allow rule anywhere in this fleet, and adding one is not the fix for a
  prompt. If asked to stop the prompting, say what the rule would cost and decline.
- Neither side runs `bypassPermissions`.
- Never `wsl --shutdown` on a target, and never run `wsl -d` on a target's drift-convergence path:
  both take the distro out from under whatever else uses it. The one exception is a start
  `fleet-converge` makes itself, under the guard its pointer names; never run `wsl -d` on its
  behalf.
- On R1 and R4 the prompt travels in the command line, visible to the process table and shell
  history; over SSH it travels on stdin, and the local shell history still records it. No secret
  belongs in one.

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
- **Give every `claude -p` turn a closed stdin.** Over SSH the piped prompt is stdin, and it ends
  when `printf` does. On R1 and R4 redirect `< /dev/null`. A `-p` run reads stdin as its input, so
  with no prompt argument the piped text is the prompt: see "Pipe data through Claude" and the
  stdin-only example under "Customize the system prompt" in
  [Run Claude Code programmatically](https://code.claude.com/docs/en/headless#pipe-data-through-claude),
  and the piped-content row of [CLI commands](https://code.claude.com/docs/en/cli-reference#cli-commands).
- **Escape apostrophes in `<prompt>`.** Every SSH row single-quotes the prompt in
  `printf '%s\n' '<prompt>'`, and R4 single-quotes the whole command, on the LOCAL shell, so a `'`
  in the prompt ("what's") closes that quote early. The rule follows the origin shell, not the
  lane:
  - **bash, zsh, and Git Bash** (a native-Windows Claude's Bash tool, R4 to R6): replace each `'`
    with `'\''`, or wrap the prompt argument (on R4, the command) in `$'...'` and write `\'`. Doubling (`''`) silently drops the
    apostrophe here: `'what''s'` arrives as `whats`.
  - **PowerShell**, Windows PowerShell 5.1 or pwsh 7 (a native-Windows Claude's PowerShell tool,
    or a PowerShell window): on R4, keep the prompt in doubled single quotes (`-p ''...''`) and
    write an apostrophe as `''\''''`. Never use `-p "..."` from PowerShell, with or without a
    doubled `''` apostrophe. This form ran correctly on every version probed. Run the SSH rows
    from bash, zsh or Git Bash, whose `printf` is a builtin.
    - **Probe**: [PowerShell quoting to wsl.exe](https://github.com/melodic-software/claude-code-plugins/issues/12908#issuecomment-6624493777).
      **As of**: 2026-11-04. **Recheck trigger**: the
      [about_Parsing](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing?view=powershell-7.6#passing-arguments-that-contain-quote-characters)
      page changes how quotes pass to native commands.
- **Use `wsl.exe --exec`, not `--`.** The quoting rules above assume `--exec`. For what each option
  does, run `wsl.exe --help` on that machine, as
  [Basic commands: Help command](https://learn.microsoft.com/en-us/windows/wsl/basic-commands#help-command)
  directs (the page has no section of its own for `--exec`).
- **Probe interop by absolute path.** `cmd.exe /c` prints nothing inside an sshd session and reads
  as "interop is broken" when it is not; run the `.exe` by absolute path.
- **Parse the JSON, not the stream.** Treat stdout as able to carry lines that are not the JSON
  result, and extract the object first, for example `grep '^{' | jq -r .session_id`. What a
  session-end hook can print is in [Hooks: SessionEnd](https://code.claude.com/docs/en/hooks#sessionend).
- **A session name is not an address.** Hostname and lane, always.
