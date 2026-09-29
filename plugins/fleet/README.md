# fleet

A Claude Code plugin for agent-to-agent reach across the machines you own. One skill, one job: from
any Claude Code lane, get work to happen in any other lane, with no human copying prompts between
terminals.

| Skill | What it does |
|---|---|
| `/fleet:reach` | Resolve a target lane from the fleet manifest, then run a script, prompt, query and wait, message a session, or start a named session there: the other lane on this machine (WSL or native Windows) or either lane on another machine |

## Why not the peer tools

A **lane** is one Claude Code install with its own sign-in: a WSL distro or native Windows, on each
machine. When each lane signs into its own Claude account, which keeps one lane's usage limits off
another's, the built-in peer tools see only their own lane:

- WSL and native Windows on one machine register sessions under different homes and sockets, so
  neither lists the other.
- Remote Control lists only the signed-in account's sessions, so another account's sessions never
  appear, even with Remote Control connected.

What works is starting a headless `claude -p` turn inside the target lane: over WSL interop for
native Windows on this machine, `wsl.exe` for WSL on this machine, and SSH for another machine. That
turn runs under the target lane's own account, config and limits, and its peer tools are local
there, so it can list and message the target's sessions.

```shell
/fleet:reach          # resolve a target, then compose the route for it
/fleet:reach relay    # the per-route detail: hops, named receiver, replies, verification
```

## What it expects

A rendered fleet manifest at `~/.config/fleet/FLEET.md` naming each host's reach paths: ssh alias,
port, account and shell. The skill reads it before composing anything, and treats a host that is
absent from it as not a fleet host. Machines are addressed by hostname over the tailnet, never by
session name.

## Posture

Starting an agent in another lane is a state change nobody is watching, so it is outside the
auto-mode classifier and prompts by design. This plugin ships no scripts, requests no tool grants,
and never proposes an ssh allow rule to quiet the prompt.

## Boundaries

`repo-fleet-hygiene` also says "fleet" and means fleets of REPOSITORIES. Different subject, no
overlap. Messaging a session in the same lane belongs to the built-in peer tools. Delegation inside
one session belongs to subagents and `session-flow:orchestrate`; a detached session in this lane
belongs to `session-flow:continue-in-background`. Interactive human use of a lane's session, from a
phone or the web, is the built-in Remote Control feature, under that lane's own account.
