---
description: "/bugs:setup check on a repo whose docs/conventions/bugs.yaml is present but untracked must FAIL that layer with a commit remediation. setup SKILL.md check B3: a present team file takes two probes, check-ignore and ls-files --error-unmatch; a non-zero ls-files on a present file is FAIL, 'present but untracked, commit it'; the ignore probe alone blesses an unshared file (Gotchas). check modifies nothing. Needs --scaffold --allow-tools Bash."
tags: [bugs, setup, check, outcome, scaffold]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Bash, Read, Glob, Grep]
expected_outcome: "The reply flags docs/conventions/bugs.yaml as present but untracked (a FAIL) and says to commit it, reports the entrypoints lane from the team layer and the manual-only posture from the default (no docs/conventions/work-items.yaml sets it), and changes no file."
---

/bugs:setup check
