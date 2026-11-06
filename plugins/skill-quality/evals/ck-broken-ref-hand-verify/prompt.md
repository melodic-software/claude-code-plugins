---
description: "Legacy check eval 4. Given a broken skill-internal ref FAIL line citing SKILL.md:42 of a scaffolded skill whose line 42 is an illustrative link, the reply quotes the FAIL line verbatim and reads the cited line before deciding anything. check SKILL.md Action: check: FAIL messages are self-describing, surface them rather than re-derive; hand-verify the cited SKILL.md line before editing, since it may be an illustrative example path. quotes-fail-line grades the verbatim quote (the legacy expectation is to quote it, so it shares the prompt's words); quotes-line-42 grades a term only line 42 carries (orchard), which the reply has only by reading the line; verifies-before-edit judges that the decision follows from the line and no file is created, deleted or rewritten blind; no-edit and no-write grade that nothing changes. Needs --scaffold."
tags: [skill-quality, check, outcome, scaffold, read-only, no-network]
max_turns: 10
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep]
expected_outcome: "The reply quotes the FAIL line as given, reads .claude/skills/skill-x/SKILL.md line 42, reports that it is an illustrative example link (the orchard sample) rather than a real missing spoke, and proposes no blind fix: it neither creates reference/big-picture.md nor deletes the reference without that check."
---

The skill-quality check on skill-x (`.claude/skills/skill-x`) returned this line:

`FAIL: broken skill-internal ref: reference/big-picture.md (no such file under the skill dir; cited at SKILL.md:42 — hand-verify the line before fixing, may be an illustrative example)`

Interpret it and decide what to do. Read anything you need, but do not change any file.
