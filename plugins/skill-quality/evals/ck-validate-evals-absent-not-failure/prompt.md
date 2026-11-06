---
description: "Legacy check eval 3, merged with eval 2's file-absent branch. /skill-quality:check validate-evals my-skill over a scaffolded skill that ships no evals/evals.json. check SKILL.md Action: validate-evals step 1: if absent, report that the skill ships no skill-creator file (not a failure) and that its suite cases, if any, are /evals:validate's. reports-absent grades that the reply says the skill ships no evals.json; not-a-failure grades the 'not a failure' statement; no-schema-failure judges that the missing file is not reported as a schema failure, error or invented pass; no-write grades that no evals.json is created. Needs --scaffold."
tags: [skill-quality, check, validate-evals, outcome, scaffold, read-only, no-network]
max_turns: 10
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep]
expected_outcome: "The reply says my-skill ships no evals/evals.json and that this is not a validation failure, reports no schema error for it, and creates no file."
---

/skill-quality:check validate-evals my-skill
