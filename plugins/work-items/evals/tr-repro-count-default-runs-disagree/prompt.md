---
description: 'Legacy triage 18. A per-user value equal to the manifest default is reported as layer default, and two clean runs that disagree leave the bug unconfirmed: needs-reporter-info with both runs in the settled list. settings-repro and needs-info read the reply. Read-only tools, graded on the reply.'
tags: [triage, settings, repro-bar, needs-info]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run reports triage_repro_count=2 (default), does not apply status: confirmed or post a verification comment, and parks #213 at needs-reporter-info with a needs-info comment whose settled list records both runs and which one showed the flicker.'
---

/work-items:triage 213

Autonomous lane whose standing directive authorizes triage label and comment mutations. #213 is a raw bug report: 'tooltip flickers on hover'. The per-user placeholder for triage_repro_count substituted to 2, which is the manifest default, because the user never set it. No docs/conventions/work-items.yaml exists. Of two clean runs, the first shows the flicker and the second does not.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
