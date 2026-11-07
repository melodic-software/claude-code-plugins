---
description: "Legacy scrutinize-dont-coast 1, its prompt behind the slash command. History: the assistant just wrote invalidate_user() in src/cache.py and announced it is moving on to wire it into src/handlers.py. The scaffold seeds the requirement, a cache.py whose invalidate_user pops a key nothing stores, and an open owner question (order entries), so any fix carries a judgment call. SKILL.md lines 46-57 and 64-73: stop first, run the pass in one fresh non-fork subagent, remediate with the user. fresh-context-pass needs one to three Agent calls, pass-is-not-a-fork none of type fork, no-edit and no-write forbid pushing the work further or an autonomous rewrite, fix-worked-with-user (llm, trace, legacy expectation 3 verbatim) needs the fix handed back to the user in some main-thread reply: the pass runs as a background task, whose completion adds a second reply, and last_message holds only that one. Needs --scaffold and --allow-tools Edit,Write (ungranted, Edit and Write leave the run and the two max-0 graders measure nothing); a history_file case runs single-arm, so pass --ablation with-without."
tags: [discipline, scrutinize-dont-coast, outcome, scaffold, history, no-network]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Agent, Edit, Write]
expected_outcome: "One to three non-fork Agent calls, no Edit or Write; the reply surfaces the wrong key and asks the user how to fix it."
---

/discipline:scrutinize-dont-coast wait, stop. You just wrote the whole cache-invalidation function and moved straight on. Are you sure that's actually right?
