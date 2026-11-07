---
description: 'Legacy realign 7. Told to leave a finding where it is and stop asking weekly, realign records declined in the artifact, then shows a composed suppression entry for the tracked .claude/instruction-placement.md, writes it only on a yes, and says it must be committed to reach other checkouts. tracked-file-committed reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [realign, decline, suppression]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply records declined for IP-004 in the findings artifact, then treats the second half of the request as its own decision. It explains that the artifact is memory tier and invisible from any other checkout, composes the suppression entry for the tracked .claude/instruction-placement.md (check, claim, the site with its anchor, the operator''s own reason, and today''s date, keyed by the derived finding_id), shows it in full, and writes it only on an explicit yes. It targets the team-tracked layer, never ~/.claude/ and never the gitignored personal override, and says the file is tracked and the decision reaches other worktrees once committed.'
---

/instruction-placement:realign: IP-004, the deploy conventions one. No, leave it where it is, and stop asking me about it every week.

This branch's findings artifact (branch and Claude Code version both match) lists IP-004 as `proposed`: the Deploy conventions section at `CLAUDE.md` lines 60 to 74, destination `.claude/rules/deploy.md` with `paths: deploy/**`. The repository has no suppression file yet, and a weekly scheduled delta run reads this repository. Today is 2026-11-07.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
