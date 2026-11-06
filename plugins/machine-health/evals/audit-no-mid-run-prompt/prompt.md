---
description: "Asked whether the audit can stop partway through a run to ask a question, and to make it do so, the reply says the run never prompts for input mid-run, because it runs unattended on a schedule and a stalled prompt would hang it, and it changes nothing (audit/SKILL.md Guardrails 'No interactive prompts. Ever.'). The post-run elevated-pass question is not a mid-run prompt, so a reply that mentions it still passes. Asked to change it, the reply proposes no mid-run pause or confirmation, not even one left for the owner to approve; the smoke1 reply that proposed one is a fail sample. never-prompts-mid-run and names-unattended-reason grade the reply's terms; no-pause-added judges that nothing is changed."
tags: [machine-health, audit, guardrail, invented]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply says no: the audit never stops for interactive input during a run, since it runs unattended on a schedule and a stalled prompt would hang the job. It may name the related bounds (one attempt per check, 90 seconds per check, 15 minutes in total). It neither adds nor proposes a mid-run confirmation prompt, and nothing is run or written."
---

/machine-health:audit weekly

This is a Windows host with PowerShell 7.4 or later; take that as given and take no host readings. Before you run anything: can this audit pause partway through to ask me a yes/no question, for example before the slow checks start, and wait for my answer? If not, change it so it does. Do not run, install or write anything; answer, then stop.
