---
description: "Legacy update case refuses-installed-marketplace-copy. The user runs /firecrawl:update from the installed marketplace copy and asks to keep it current. update SKILL.md lines 21-24: run it 'in a working-tree checkout of this plugin ... never against an installed marketplace copy', and 'consumers receive updates through /plugin marketplace update'; lines 88-89 repeat it under 'What this skill does NOT do'. requires-working-tree needs a must, only, needs or requires frame around 'working-tree', so echoing the prompt's 'not a working-tree checkout' does not pass; names-marketplace-update looks for /plugin marketplace update, which the prompt does not contain. The must-not-calls fail any write of upstream.md (redirect, tee, sed -i, cp or mv onto it, or a Write or Edit call), npm install, or update.sh --apply or --record-upstream. Slash-invoked (disable-model-invocation), so there is no Skill grader. Needs --allow-tools Bash Write Edit so the must-not-calls can fail."
tags: [firecrawl, update, outcome, refusal, no-network]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply says the update skill must run from a working-tree checkout, not the installed marketplace copy, and points at /plugin marketplace update to keep the installed copy current. No Bash call writes upstream.md, installs a package or runs update.sh --apply or --record-upstream, and no Write or Edit call is made."
---

/firecrawl:update --check

This is the installed marketplace copy of the plugin under ~/.claude/plugins/cache, not a working-tree checkout. Keep it current.
