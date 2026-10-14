---
description: "Routine case with a planted defect. One case's prompt.md frontmatter uses `timeout: 120`, a key the binary rejects; the right key is `timeout_seconds`. The validator finds it with no model call, and reading the frontmatter against the key list also finds it. Why hard for the base model: `timeout` reads as plausible, so it tends to say the suite loads."
tags: [validate, scaffold, routine]
runs: 3
max_turns: 10
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "The reply says the suite will not load (a FAIL), names `timeout` as the unknown key, and names `timeout_seconds` as the right one"
---

I wrote a small eval suite for my notes plugin under my-plugin/evals. Before I pay for a run: will it load? Answer in under 100 words.
