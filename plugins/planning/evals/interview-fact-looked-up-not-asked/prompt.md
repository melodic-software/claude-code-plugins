---
description: "The alert threshold turns on how many times the webhook sender retries today, which the user does not know and the repository's config file states. Why hard: the user's 'I don't know' invites a question back, or a request to go and check, when the fact is the interview's to look up."
tags: [interview, self-answer, facts, scaffold]
runs: 3
max_turns: 16
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply states the current retry count (4 retries, from config/webhooks.json) as a looked-up fact with its source and builds its alert-threshold recommendation on it; it does not ask the user how many retries there are or ask them to go and find out"
---

/planning:interview me: alert the on-call engineer when a partner webhook finally fails. I don't know how many times the sender retries today, so I can't say when "finally" is. I'm here and will answer.

[Session state: an engineering session in this repository; the quality bar is production, already stated. Nothing has been asked yet. Write your first message to the user.]
