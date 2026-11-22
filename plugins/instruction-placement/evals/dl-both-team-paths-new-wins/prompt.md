---
description: 'With both docs/conventions/instruction-placement.yaml and the old .claude/instruction-placement.md present, delta applies the new file as the team layer, does not apply the old one, and warns naming both files and the id only the old file carries. both-files-named reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [delta, suppression, old-path]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply applies docs/conventions/instruction-placement.yaml as the team layer and suppresses the Deploy conventions finding from it. It does not apply the old .claude/instruction-placement.md, so the Lint rules finding, whose id only the old file carries, is still reported. It prints a warning naming both files, saying the new one supplies the team layer, listing 4d7f2a90c1e3b856 as the id only in the old file, and naming /instruction-placement:setup apply migrate-config to merge it. It writes neither file.'
---

/instruction-placement:delta

This branch's memory-tier home holds a spine baseline from the 2026-11-01 run. No pointer region binds a convention home. The tracked `docs/conventions/instruction-placement.yaml` holds one entry:

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

The tracked `.claude/instruction-placement.md` is still there too. Its fenced block holds the same `9c1e0b7a44d2f310` entry and one more, `4d7f2a90c1e3b856`, for the Lint rules demote finding, with the reason "Lint rules stay global while the TypeScript migration runs" and the date 2026-10-20. There is no personal override at either path and no `~/.claude/instruction-placement.md`. The detector reports two demote candidates in the root `CLAUDE.md`: Deploy conventions (`finding_id` `9c1e0b7a44d2f310`) and Lint rules (`paths: **/*.ts`, 140 matches, `finding_id` `4d7f2a90c1e3b856`).

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
