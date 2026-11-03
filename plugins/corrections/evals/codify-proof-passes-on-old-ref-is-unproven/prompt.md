---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['codify', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'The check passed on the old ref, so it does not catch the mistake. The skill reports the check as unproven with the exit code and the script''s lines, does not propose it for install, and says to change the check or the rung and prove again.'
---

/corrections:codify "config loader ignores the timeout key" - codify this. My candidate check is `grep -q timeout config/defaults.yaml`. Running prove-check.sh on it printed: old (a91c3d2): exit 0 (expected non-zero) and new (HEAD): exit 0, and the script exited 1.
