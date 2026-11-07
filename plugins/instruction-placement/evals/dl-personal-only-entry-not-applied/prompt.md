---
description: 'Legacy delta 7. An entry only in the gitignored personal override does not suppress a finding the team layer lacks: delta still reports the finding, names the entry personal-only and not applied with its layer, and points at promotion to the tracked team file. personal-only-not-applied reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [delta, suppression, personal-layer]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply still reports the Testing conventions finding rather than suppressing it. It explains that .claude/instruction-placement.local.md is the personal layer, and on this policy-floor surface a personal-layer entry for a finding_id the team layer does not carry is read, reported as personal-only, not applied, and takes no effect, since absence from the team layer is the team''s unsuppressed state. It names the contributing layer and points at promoting the entry to the tracked .claude/instruction-placement.md (through realign) as what makes it effective, neither silently honoring nor silently dropping it.'
---

/instruction-placement:delta I put an entry in .claude/instruction-placement.local.md for the CLAUDE.md testing-conventions finding, so it should be quiet now.

This branch's memory-tier home holds the spine baseline and findings artifact from the 2026-10-31 run, where IP-002 (demote the Testing conventions section of the root `CLAUDE.md` to `.claude/rules/testing.md`, `paths: **/*.test.ts`, 52 matches) is open. Its source section has since gained a paragraph, so the detector reports it as changed. The gitignored `.claude/instruction-placement.local.md` holds one entry whose key equals IP-002's derived `finding_id`, with a reason and a date. The tracked `.claude/instruction-placement.md` exists with no `suppressions` entries, and there is no `~/.claude/instruction-placement.md`.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
