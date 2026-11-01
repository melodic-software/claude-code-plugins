---
description: "Routing from plain words (SKILL.md line 2: 'interactive explorer for X', 'tune a parameter space visually') in an eval run, where the upstream playground plugin is never installed (the run copy drops the manifest dependencies key). The skill must reach Step 3 (lines 65-75) and print the marketplace-qualified install command, and must not build the explorer itself (lines 18-19 and 147-148: this skill never builds a playground). Write is granted so the no-write grader can fail: a baseline is expected to hand-build the HTML page. The marketplace-add line is not graded, since lines 72-74 and 78-79 disagree on when it belongs. Needs --allow-tools Write."
tags: [playgrounds, use, outcome, routing]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write]
expected_outcome: "The run invokes playgrounds:use, the reply prints `/plugin install playground@claude-plugins-official`, no file is written, and no HTML explorer appears in the reply."
---

I'm tuning our HTTP client's retry policy: base delay, multiplier, max attempts and jitter. I want an interactive page with a slider for each one beside a live timeline of when the retries fire, and when I've settled on values it should hand me a prompt I can paste back here.
