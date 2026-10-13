---
description: "A vague nightly-sync report under --no-survey gets the unknown-needs-confirmation placeholder or one targeted question, never invented numbered repro steps"
tags: [bugs, write, outcome, no-invention]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "Either the steps to reproduce are marked '(unknown — needs reporter confirmation)', or the reply asks one targeted question about how to trigger it. It does not list three or more concrete reproduction steps the user never gave."
---

/bugs:write --no-survey Something is off with the nightly sync job: sometimes records come out stale, but I honestly can't tell you how to trigger it and I don't have a specific case. Can you write up a bug report?
