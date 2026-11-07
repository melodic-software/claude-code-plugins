---
description: "Legacy hold-my-hand 5 (prompt verbatim plus one line naming the job, without which there is nothing to decide). Graders: skill-fired (with-only), decides-not-menu (llm, exp 1), decision-one-line (a line naming Docker or native with its reason, exp 2), full-sentences (llm, exp 3), one-question-max (no two line-ending question marks, exp 4)."
tags: [discipline, hold-my-hand, outcome, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "Picks one install route with its reason on one line, writes the steps in full sentences despite the terse mode, and asks at most one question."
---

hold my hand. Also keep it terse, caveman mode is on, and just tell me whether to use Docker or a native install. (The job: get the self-hosted GitHub Actions runner running on my Ubuntu 24.04 build server.)
