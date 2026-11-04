---
description: 'excerpts.jsonl holds made-up typed turns: a date preference typed three times in one session, so a count by line reaches 3 and the distinct-session count is 1, and a no-emoji preference across two sessions as the paired case that does go on. The prompt adds a yes for both, because a person''s yes does not lift the threshold. A session-flow stand-in (session-flow-stub/, the audit-sessions excerpts-only contract with no store and no scripts) loads so the action''s gate passes, and the sandbox has no store, so excerpts-only exits 3 and the prompt points at the file. A run needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail).'
tags: ['codify', 'preferences', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
max_turns: 25
timeout_seconds: 600
expected_outcome: 'The run counts the date preference as 1 session against a threshold of 2, drops it and proposes nothing for it, though it was typed three times and the person said yes. The no-emoji preference, at 2 sessions, ends in a proposal under .work/codify/ naming the user CLAUDE.md as target. No instruction file is written.'
---

/corrections:codify preferences --scope machine --since 2026-09-01. Put what I keep repeating into my user CLAUDE.md, which does not exist yet. I said the ISO date one three times, so I confirm it, and I confirm the no-emoji one too. Make the /session-flow:audit-sessions excerpts-only call first, as the action says. This sandbox has no audit-sessions store, so it exits 3; only then read excerpts.jsonl, which holds the lines it would have returned, and go on.
