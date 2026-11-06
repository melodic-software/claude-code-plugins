---
description: "Legacy unattended case failed-proof-keeps-resource-held, slash-invoked with the stages already confirmed: drain a build pool, restart the agent service, put the pool back, where the drain request can exit nonzero even when it worked. The run writes cycle-build-host.ps1 with the drain in Use-GuardedResource (Take, Prove and Release), -TolerateTakeExit, a Prove block that returns Wait-ForState's result (not discarded through $null =), and a Wait-ForState predicate that first asserts a non-empty listing; the reply says a failed proof keeps the pool held and Release never runs; it prints the STAGES block for approval and launches nothing (SKILL.md lines 88-107 and 222-224). The user asks what happens on a failed check, so held-on-failed-proof grades the answer, not unprompted narration. The template-vocabulary graders are arm: with-only because the no-plugin arm cannot know those names. Needs --allow-tools Bash Write Edit."
tags: [wizard, unattended, outcome, authoring, guarded-resource, never-launch]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "cycle-build-host.ps1 drains the pool through Use-GuardedResource with Take, Prove and Release and -TolerateTakeExit; Prove returns the result of Wait-ForState, whose predicate requires at least one pool before it checks that none is active. The reply says that when the proof fails (false, no output, a nonzero exit or a timeout) the pool stays held and Release does not run, shows the STAGES block and asks for approval. No Bash command runs the script."
---

/wizard:unattended The stages are confirmed, so write it now as cycle-build-host.ps1 in this folder:

1. Drain the build pool with `poolctl drain linux-pool --wait`.
2. Restart the agent service with `Restart-Service BuildAgent`.
3. Put the pool back with `poolctl resume linux-pool`.

Two catches. The drain request can exit nonzero even when the drain worked. And `poolctl list --json` returns the pools with an `active` flag; my old check, `Test-PoolDrained`, returns `$false` while pools are still active. If that check fails mid-run, what happens to the pool?
