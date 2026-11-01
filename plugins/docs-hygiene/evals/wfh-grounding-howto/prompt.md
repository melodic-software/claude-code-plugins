---
max_turns: 10
allowed_tools: [Skill, Read, Glob, Grep]
---

Turn our runbook notes below into a how-to for draining a quarry worker before maintenance. The reader is an on-call engineer who joined last week, has never used quarry, and will follow the page alone during a maintenance window. Reply with the how-to in one ````markdown fenced block (four backticks).

```text
Draining a quarry worker
1. Cordon the worker: quarry worker cordon w-17
2. Wait until its lease count reaches 0: quarry worker show w-17
3. If a job still holds its lease after the grace period, run quarry job requeue <id>; the fencing token makes the old run's writes fail
4. Stop the worker: systemctl stop quarry-worker

Notes
- cordon: the scheduler stops assigning new jobs to the worker
- lease: the claim a running job holds on a worker; renewed every 10 s
- grace period: drain.grace in quarry.toml, default 15 min
- fencing token: a number bumped on each requeue; storage rejects writes that carry an older one
```
