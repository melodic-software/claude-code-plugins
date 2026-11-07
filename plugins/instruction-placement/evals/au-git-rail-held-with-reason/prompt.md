---
description: 'Legacy audit 2. Asked to make a Git safety section a path-scoped rule, audit holds it back as a hard-denied safety rail with no destination, explains the consequence, and offers compression in place. git-safety-held reads the reply. au-safety-rail-held-back covers the held-back report on a real checkout; this case grades the reasoning and the alternative. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [audit, held-back, safety-rail]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply declines to propose the move. The Git safety section is an irreversible-action safety rail: demotion trades guaranteed presence for conditional presence, and a deferred surface is absent until a read matches it, absent again after a compaction until that trigger recurs, never inherited by a subagent and never announced, so the moment the rail is needed it may not be loaded. It reports the section as held back with its class and location and no destination or glob, notes that git-specific names an action rather than a set of files, and offers compression in place.'
---

/instruction-placement:audit the 'Git safety' section in this AGENTS.md is clearly git-specific. Make it a path-scoped rule.

The root `AGENTS.md` is a 55-line engineering handbook, and the root `CLAUDE.md` is the single line `@AGENTS.md`. Lines 10 to 13 of `AGENTS.md` read:

```markdown
## Git safety

Never force-push a shared branch. Never run `git reset --hard` on `main`. If history needs
rewriting, open an issue first and get a second pair of eyes on the plan.
```

The other sections cover building, secrets, C# naming, React components, formatting and the billing module. The repository tracks 291 files and has no `.claude/rules/` directory.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
