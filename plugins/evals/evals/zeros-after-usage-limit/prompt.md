---
description: "Hard case. Why hard: That a usage or rate limit mid-suite is not marked partial, so `partial: false` proves nothing, is a recent upstream doc fact (the plugin-evals troubleshooting entry) that the hub carries; the blind base answers found the limit but never said it."
tags: [reading-results, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says a usage or rate limit mid-suite is not marked partial, so `partial: false` proves nothing; and says to check each run's `error` field before believing the drop and to rerun those cases rather than call it a regression"
---

My plugin eval JSON says partial: false and the command exited 1. The last three cases scored 0 both with and without the plugin, and the suite score dropped a lot compared with last week. Is that a plugin regression or flaky cases? Answer in under 120 words.
