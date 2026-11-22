---
description: 'With an old team file and an old personal file present and no answer from the operator yet, setup apply migrate-config previews the team file''s move to docs/conventions/instruction-placement.yaml and asks for a yes, writes and deletes nothing, deletes an old file only after the readback, and skips the personal file because its target is not gitignored. preview-asks-first reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [setup, migrate-config, old-path]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply previews moving .claude/instruction-placement.md to docs/conventions/instruction-placement.yaml, showing the target as it will read with the 9c1e0b7a44d2f310 entry, and asks for an explicit yes for that file before writing it. It writes nothing and deletes nothing in this run, and says the old file is deleted only after the new file is written and read back resolving the same entries. For .claude/instruction-placement.local.md it says the target docs/conventions/instruction-placement.local.yaml is not gitignored, names the missing docs/conventions/**/*.local.* line, and leaves that file in place.'
---

/instruction-placement:setup apply migrate-config

No pointer region binds a convention home, and there is no `docs/conventions/instruction-placement.yaml` and no `docs/conventions/instruction-placement.local.yaml`. The tracked `.claude/instruction-placement.md` holds this fenced block:

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

The untracked `.claude/instruction-placement.local.md` holds this fenced block:

```yaml
suppressions:
  4d7a2f0c81e35b96:
    check: instruction-placement/audit/demote
    claim: narrower-scope:path-scoped-rule
    sites:
      - surface: CLAUDE.md
        anchor/v1: "a3e19c42"
    reason: "I keep the release notes section in view while I cut releases."
    date: 2026-11-04
```

There is no `~/.claude/instruction-placement.md`. The `.gitignore` has no `docs/conventions/**/*.local.*` line, so `git check-ignore -q docs/conventions/instruction-placement.local.yaml` exits 1. The operator has not answered any question in this session.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
