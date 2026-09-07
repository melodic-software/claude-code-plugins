# fleet

A Claude Code plugin for reaching the other machines you own. One skill, one job: get an agent turn
to happen on a machine that is not this one.

| Skill | What it does |
|---|---|
| `/fleet:reach` | Resolve a target host from the fleet manifest, then run a Claude Code agent turn there over SSH: one-shot, multi-turn, or a Windows-side relay that reaches the target's own sessions |

## Why SSH and not the peer tools

The obvious route is to ask the built-in peer tools to find the other machine's session. It does
not work when each machine signs into its own Claude account, and that split is usually deliberate:
it keeps one machine's usage limits off another's.

`ListAgents` and `SendMessage` reach the sessions your own account can see. Past this machine that
means Remote Control on both ends under one claude.ai sign-in, so with split accounts another
machine's sessions are never listed. No setting changes that, and sharing an account gives back
exactly what the split was protecting.

What does work is SSH plus a headless `claude -p` on the target. The turn runs under the target's
own account, config, plugins and limits, which is what you want anyway: the work happens where its
files and credentials already are.

```shell
/fleet:reach          # resolve a target, then compose the right recipe for it
/fleet:reach relay    # the Windows-side relay, for reaching a target's own live sessions
```

## What it expects

A rendered fleet manifest at `~/.config/fleet/FLEET.md` naming each host's reach paths: transport,
port, account and shell. The skill reads it before composing anything, and treats a host that is
absent from it as not a fleet host. Machines are addressed by hostname over the tailnet, never by
session name.

## Posture

Starting an agent on another machine is a state change on a host nobody is watching, so it is
outside the auto-mode classifier and prompts by design. This plugin ships no scripts, requests no
tool grants, and never proposes an ssh allow rule to quiet the prompt.

## Boundaries

`repo-fleet-hygiene` also says "fleet" and means fleets of REPOSITORIES. Different subject, no
overlap. Delegation inside one session belongs to subagents and `session-flow:orchestrate`; a
detached session on this same machine belongs to `session-flow:continue-in-background`. Interactive
human use of a target's session, from a phone or the web, is the built-in Remote Control feature,
under that machine's own account.
