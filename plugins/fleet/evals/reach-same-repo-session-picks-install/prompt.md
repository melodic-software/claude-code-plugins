---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Asks or determines which install the other session is in. If it is in this same install, routes to the built-in peer tools with no SSH and no relay. If it is in the other install on this machine (WSL versus native Windows), uses the same-machine cross-install row (R1 or R4) instead, because each install lists only its own sessions.'
---

I'm in the laptop's WSL session (lap-01). Message my other Claude session that's running in the same repo on this laptop.

In this session the fleet manifest is at `.config/fleet/FLEET.md` in the working directory, not under `~`.
