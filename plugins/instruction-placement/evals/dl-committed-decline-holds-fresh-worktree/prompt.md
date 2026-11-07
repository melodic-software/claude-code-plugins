---
description: 'Legacy delta 6. In a fresh worktree with no spine baseline, delta still suppresses a finding declined on main through the committed .claude/instruction-placement.md entry, reports the suppression with reason, date and layer, and never writes that file. suppressed-by-team-layer reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [delta, suppression, worktree]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply says this worktree has no spine baseline, which is expected because the memory tier does not cross checkouts, and still does not surface the Deploy conventions finding. It resolves .claude/instruction-placement.md across its three layers, derives the finding''s finding_id from its check, claim and site anchor, matches the committed team-layer entry, and suppresses it, naming the tracked file (not a baseline) as what carried the decline across checkouts. It reports the suppression with its reason, its date (2026-11-02) and its contributing layer (team), plus any entry that did not suppress. It writes only its own memory-tier baseline and never edits the suppression file, which realign owns.'
---

/instruction-placement:delta fresh worktree of the same repo, branch cut from main. On main I declined the deploy-conventions demote finding and committed .claude/instruction-placement.md.

This worktree's memory-tier home is empty: no spine baseline and no findings artifact. The tracked `.claude/instruction-placement.md` holds one entry:

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

There is no `~/.claude/instruction-placement.md` and no `.claude/instruction-placement.local.md`. The detector reports two demote candidates in the root `CLAUDE.md`: Deploy conventions, whose check, claim and site anchor derive `finding_id` `9c1e0b7a44d2f310`, and Lint rules (`paths: **/*.ts`, 140 matches), which derives an id with no entry.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
