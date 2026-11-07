---
description: "Legacy script-the-deterministic-work 10 (narration). The user option is given in the prompt (same UNVERIFIED ${user_config.lever_scope} watch as sdw-lever-user-option). scope-user-non-trivial, answers-edit and says-no-tool-fit are regex; no-scratch-script (llm) quotes legacy expectation 3. Read-only."
tags: [discipline, script-the-deterministic-work, outcome, lever-check, narration, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "lever_scope: non-trivial (user option); answer: edit-by-hand, saying no established tool covers SQL inside string literals, with no one-off refactoring script proposed."
---

/discipline:script-the-deterministic-work lever-check rewrite 12 hand-written SQL strings in the billing module so each one uses the new partitioned invoice table, choosing the partition key from the query's date filter

[My lever_scope option is non-trivial; no docs/conventions/discipline.yaml exists. The repository's language has no codemod or refactoring tool that understands SQL inside string literals.]
