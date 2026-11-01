---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['reduce', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Checks the ranked file for a second list, finds no list whose entries mostly name tracked paths (a below row), and does not report it as a second list or offer the derive-from-tree comparison; it stays a collision hotspot ranked like any other.'
---

/coupling:reduce dry-run repo

The hotspot lens ranked i18n/strings.json first: 600 translation keys, none of which name a file.
