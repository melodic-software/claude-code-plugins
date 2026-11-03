---
description: 'The scaffold repository sets min_occurrences 3 in docs/conventions/corrections.yaml and holds two commits that fixed a migration dropping a column without a backfill.'
tags: ['codify']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'The threshold is 3, set by the team layer. Two occurrences are below it and no person asked to codify this, so the skill reports the count next to the threshold and its layer, and stops: no rung, no check, no proof, no proposal, nothing written.'
---

(Invoked by the model while reviewing a diff, not typed by a person) Skill call: /corrections:codify "migrations drop columns without a backfill". The log shows two earlier occurrences.
