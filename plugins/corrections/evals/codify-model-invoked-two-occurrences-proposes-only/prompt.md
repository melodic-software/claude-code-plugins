---
description: 'The scaffold repository holds two commits that fixed an endpoint skipping the shared auth helper, so the count meets the default threshold of 2.'
tags: ['codify']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'The count reaches the threshold of 2, so the skill picks a rung, places the lesson and runs the proof, then presents the proposal in the report. Because the model invoked it, nothing is written to .work/codify/ or the repository.'
---

(Invoked by the model while reviewing a diff, not typed by a person) Skill call: /corrections:codify "new endpoints skip the shared auth helper". The log shows two earlier occurrences.
