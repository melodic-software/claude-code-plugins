---
description: 'Legacy confirm 12 (narration). Before calling a fix failed, the run rules out the observation (stale build, cached page, wrong port or instance) and observes again by a second route (SKILL.md Stage 2, ''A failed check: suspect the observation first''). Framed like the existing narration cases. names-observation-doubt grades a named observation cause in the reply; doubts-observation-first (llm) legacy expectations 1 and 2 verbatim.'
tags: [verification, confirm, narration, no-network, fix, observation, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Names a stale build, cached page or wrong instance as the first suspect, plans a second observation (fresh build, hard reload or the API response), and does not yet call the fix failed.'
---

/verification:confirm fix. Do not read the repository, launch, install or run anything; treat these as facts. Stage 1 already passed this conversation. After the fix, the browser still shows the old wrong total on the cart page, although the diff clearly changes the total calculation. Say what you conclude and what you do next, then stop.
