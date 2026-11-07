---
description: 'Legacy realign 6. Told to apply what was accepted yesterday, realign runs the staleness checks first (branch frontmatter, cited content, Claude Code version), stops on the branch mismatch and offers a re-audit instead of editing stale line ranges. branch-mismatch reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [realign, staleness, branch-match]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'Before the first edit the reply compares the artifact''s branch: frontmatter (main) with the current branch (feat/search-ui), noting that the directory an artifact sits in never proves which branch it describes; confirms whether each finding''s cited content still sits at its cited lines (IP-003''s does not); and compares the recorded Claude Code version (2.1.300) with the running one (2.1.319). On the branch mismatch it stops and offers a re-audit, and for drifted content it re-audits that finding rather than editing the cited line range, because stale line numbers excise the wrong text.'
---

/instruction-placement:realign apply everything I accepted yesterday.

The findings artifact in this checkout's memory-tier home has frontmatter `branch: main` and `claude_code_version: 2.1.300`. The current branch is `feat/search-ui` and the running Claude Code is 2.1.319. The artifact marks IP-001 and IP-003 `accepted`. IP-001 cites `CLAUDE.md` lines 40 to 58, which still hold the C# conventions section; IP-003 cites lines 70 to 81, which now hold the second half of a Search API section added this week.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
