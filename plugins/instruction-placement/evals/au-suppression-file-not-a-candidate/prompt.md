---
description: 'With docs/conventions/instruction-placement.yaml present and the detector reporting a candidate on it, audit drops that candidate because the suppression surface is excluded from the scan set, still counts the file in coverage, applies its suppression, and proposes the remaining finding. surface-excluded reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [audit, suppression, scan-set]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply raises no finding on docs/conventions/instruction-placement.yaml: it drops the detector''s promote candidate on that file because the suppression file is excluded from the audit''s scan set, while the detector''s coverage numbers still count the file. It suppresses the Deploy conventions finding with its reason, date (2026-11-02) and the team layer, still proposes the Lint rules finding with paths: **/*.ts, and writes neither the suppression file nor any instruction file.'
---

/instruction-placement:audit

No pointer region binds a convention home. The tracked `docs/conventions/instruction-placement.yaml` holds:

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

There is no `docs/conventions/instruction-placement.local.yaml` and no file at an old suppression path. The detector read 214 tracked files and reports three candidates: a demote of Deploy conventions in the root `CLAUDE.md`, whose check, claim and site anchor derive `finding_id` `9c1e0b7a44d2f310`; a demote of Lint rules in the root `CLAUDE.md` (`paths: **/*.ts`, 140 matches), which derives an id with no entry; and a promote of `docs/conventions/instruction-placement.yaml`, which it reads as a convention file under the convention home that nothing loads.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
