---
description: "Legacy reuse-or-replace 7. The scaffold seeds a finished migration to the jobs registry whose paved-path entry (PP-02) still names plain cron. no-write-paved-paths, no-edit-paved-paths and no-shell-write-paved-paths (max 0, both arms) check paved-paths.md is not changed before a yes (no file grader: the file is scaffold-created); asks-yes is regex; draft-replaces-entry (llm) quotes legacy expectations 1-3. Needs --scaffold --allow-tools Bash Write Edit."
tags: [discipline, reuse-or-replace, outcome, scaffold, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "Drafts a replacement for the PP-02 scheduled-jobs entry pointing at the jobs registry and retry wrapper with its enforcing check, shows it, asks for a yes, and leaves docs/standards/paved-paths.md untouched."
---

/discipline:reuse-or-replace we just finished replacing the hand-rolled cron entries with the jobs/ registry and its shared retry wrapper, and all existing jobs are migrated. Our docs/standards/README.md index has a paved-path row pointing at docs/standards/paved-paths.md, whose scheduled-jobs entry still says "plain cron entry in the deploy config; enforced by none".
