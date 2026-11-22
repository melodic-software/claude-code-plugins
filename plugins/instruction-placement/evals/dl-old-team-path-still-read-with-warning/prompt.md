---
description: 'With only the old .claude/instruction-placement.md present, delta still reads it as the team layer, suppresses the finding it carries, and prints one warning naming the old file, docs/conventions/instruction-placement.yaml as the new location, and /instruction-placement:setup apply migrate-config. old-path-warning reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [delta, suppression, old-path]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply reads the old .claude/instruction-placement.md as the team layer because no docs/conventions/instruction-placement.yaml supplies it, and still suppresses the Deploy conventions finding with its reason, date (2026-11-02) and layer. It prints one warning that names the old file, the new location docs/conventions/instruction-placement.yaml, and /instruction-placement:setup apply migrate-config as the command that moves it. It still reports the Lint rules finding, and it writes neither file.'
---

/instruction-placement:delta

This branch's memory-tier home holds a spine baseline from the 2026-11-01 run. No pointer region binds a convention home, and there is no `docs/conventions/instruction-placement.yaml` and no `docs/conventions/instruction-placement.local.yaml`. The tracked `.claude/instruction-placement.md` holds this fenced block:

```yaml
suppressions:
  9c1e0b7a44d2f310:
    check: instruction-placement/audit/demote
    claim: narrower-scope:path-scoped-rule
    sites:
      - surface: CLAUDE.md
        anchor/v1: "71d0c3aa"
    reason: "Ops reads this section during incidents; it stays always-loaded."
    date: 2026-11-02
```

There is no `.claude/instruction-placement.local.md` and no `~/.claude/instruction-placement.md`. The detector reports two demote candidates in the root `CLAUDE.md`: Deploy conventions, whose check, claim and site anchor derive `finding_id` `9c1e0b7a44d2f310`, and Lint rules (`paths: **/*.ts`, 140 matches), which derives an id with no entry.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
