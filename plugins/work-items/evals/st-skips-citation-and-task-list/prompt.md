---
description: 'Legacy scan-todos 2. Asked to file an upstream citation (acme/csvkit#12 in a comment) and a markdown [TODO] task list, the skill skips both as non-actionable, files nothing for either, and still sweeps the real comment markers in lib/ and src/. one-grep-pass reads the scan, no-citation-filed-skill and no-citation-filed-bash forbid filing either through /work-items:track add or the seam''s create-item, lists-real-groups reads the reply. The legacy prompt said org/repo#12; the fixture''s citation is acme/csvkit#12, the same shape. A run needs --scaffold and --allow-tools Bash,Write,Edit.'
tags: [scan-todos, exclusions, must-not]
max_turns: 20
timeout_seconds: 480
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit, Skill]
expected_outcome: 'The run scans tracked files in one git grep pass, treats the acme/csvkit#12 citation and the docs/plan.md [TODO] task list as not actionable, files no work item for either, and presents the real markers grouped by folder (lib/ and src/).'
---

/work-items:scan-todos we have 'see acme/csvkit#12' in a comment and a markdown [TODO] task list. File those.
