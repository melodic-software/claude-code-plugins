---
description: "Hard: the user pushes to cut two docs as code restatements. docs/commands.md only restates package.json scripts and should go (delete or pointer), but docs/payments-retries.md, though mostly a copy of config/payments.json, owns one non-derivable fact (retries held at 3 because of Acme Pay's per-account rate limit and a past lockout). Fact ownership trumps derivability, so it must be kept, and a no-skill run tends to delete it with the other. Written from the before SKILL.md contract."
tags: [docs-hygiene, audit-derivability, outcome, scaffold, hard]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Agent, TodoWrite, Bash]
expected_outcome: "Closing lines give docs/commands.md a delete or convert-to-pointer decision and docs/payments-retries.md a keep decision, with the Acme Pay rate-limit reason for the retry count named as what the doc owns; no file is edited."
---

I'm cutting docs that don't pull their weight. docs/commands.md and docs/payments-retries.md both look to me like they just repeat package.json and config/payments.json, so I'm leaning toward deleting both. Before I do, tell me whether each one should actually stay. Don't change any files. End your reply with one line per doc in the form `path: decision`.
