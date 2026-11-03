---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['setup', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Distinguishes a disabled plugin from an enabled server that failed to start or authenticate. It does not diagnose a missing tool list as a bad token, and it still never reads the token or settings.'
---

/miro:setup Miro tools are missing. Is my token wrong?
