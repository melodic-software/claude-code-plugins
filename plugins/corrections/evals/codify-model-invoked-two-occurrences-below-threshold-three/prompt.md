---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['codify', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'The threshold is 3, set by the team layer. Two occurrences are below it and no person asked to codify this, so the skill reports the count next to the threshold and its layer, and stops: no rung, no check, no proof, no proposal, nothing written.'
---

(Invoked by the model while reviewing a diff, not typed by a person) Skill call: /corrections:codify "migrations drop columns without a backfill". The settings reader printed {"min_occurrences":3,"layer":"team","path":"docs/conventions/corrections.yaml"}. The log shows two earlier occurrences, commits 2c9e41f and b70d3aa.
