---
description: "One question audit-native-overlap answers: whether a WebFetch answer that omits a bundled skill proves Claude Code ships none (no: a summarizing fetch returns a model's answer about the page, so absence is not evidence; the claim needs the raw markdown). Reaches SKILL.md 'Any claim about what Claude Code itself ships'. Source: the consumer's own writing. routine. Read-only tools. Held-rows rows: harness-ops 15."
tags: [harness-ops, audit-native-overlap, reference-answer, routine]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The answer says no: a summarizing fetch returns a model's answer about the page, so absence from it is not evidence, and the claim must rest on the raw markdown page (fetch-docs.sh)."
---

/harness-ops:audit-native-overlap before a report: I asked WebFetch about https://code.claude.com/docs/en/skills and its answer didn't mention any bundled skill called `explain-usage`. Can I record that Claude Code ships no such skill?
