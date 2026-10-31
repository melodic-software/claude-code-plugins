---
description: "Lost sentence 73. Written from MB:plugins/knowledge/skills/docpage-digest/SKILL.md:42-46 (a ${NAME} library_dir reference whose variable is unset fails the run loudly: report it and stop; never let a shell expand it to the empty string); head states the same stop at docpage-digest/SKILL.md:27-29 and reference/work-root.md:26-27, with work-root.mjs expanding the variable instead of the agent's printenv. New from base: docpage-digest evals.json id 1 needs a network fetch. Outcome both versions share: the variable EVAL_KNOWLEDGE_CORPUS_DIR is unset, so the run reports it and stops before any write or fetch. A plugin eval cannot set a userConfig option (the run loads no user or project settings, and case env takes only EVAL_* keys), so the prompt supplies the value; the operator must not export EVAL_KNOWLEDGE_CORPUS_DIR. Visibility: none checked by this skill; the scaffold runs git init -q so the session root is the workspace."
tags: [knowledge, docpage-digest, outcome, scaffold, stop-gate]
max_turns: 15
timeout_seconds: 450
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply names EVAL_KNOWLEDGE_CORPUS_DIR as unset and says the run stopped. No .work/ path is created, no Write call runs, and no Bash command fetches the page."
---

/knowledge:docpage-digest https://docs.example.com/api/overview

For this run my library_dir is `${EVAL_KNOWLEDGE_CORPUS_DIR}`; the value rendered in this session is stale, so use this one.
