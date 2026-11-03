---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['codify', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'A note is an observation, not a codification, so a model invocation appends the row like a person''s does. The skill uses a session source_id, writes the row file and runs buffer.sh append. It writes no proposal.'
---

(Invoked by the model, not typed by a person) Skill call: `/corrections:codify note "new endpoints skip the shared auth helper"`.
