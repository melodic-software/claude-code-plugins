---
description: "check asked whether the eol rule covers an uncommitted file, in a repository with a committed '*.md text eol=lf' rule and an untracked notes/draft.md. setup SKILL.md check step 5: resolve with git check-attr eol, which answers for any candidate path, tracked or not; probe candidate paths or the declared patterns, never a tracked-files listing. ran-check-attr is the process check; no grader forbids git ls-files, since an orientation listing before the candidate-path probe is not the probe method that rule forbids. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['setup', 'check', 'read-only']
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Yes: check-attr answers for any candidate path, tracked or not, and the hook normalizes a first write to a brand-new file the same as an edit to a tracked one; the probe runs git check-attr on candidate paths.'
---

/eol-normalizer:setup check

Does the eol rule cover a brand-new file I haven't committed yet?
