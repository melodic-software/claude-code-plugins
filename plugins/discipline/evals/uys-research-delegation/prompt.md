---
description: "Legacy use-your-skills 2, its prompt behind the slash command. History: the assistant drafted a research delegation prompt for a library choice that names no skills. A fresh subagent does not get this listing, so the prompt names the fitting skills, and a recurring discipline goes in the agent's skills: frontmatter as guidance, not a change the skill makes (SKILL.md lines 49-55 and 79-82). All three graders are llm judges over the trace, each quoting one legacy expectation verbatim and reading only the assistant's main-thread text (and, for prompt-names-skill, its Agent prompts): a run that dispatches the subagent gets a second reply when the background task finishes, and last_message holds only that one. no-inheritance-stated needs the listing gap said, prompt-names-skill the re-issued prompt naming do-your-research or pick-for-the-problem, preload-guidance a skills: preload recommended as guidance. A skills: preload would be a write under .claude/agents, which the sandbox denies, so the no-config-change half is graded through the reply only. A history_file case runs single-arm, so pass --ablation with-without."
tags: [discipline, use-your-skills, outcome, history, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Says a fresh subagent will not see the skill listing, re-issues the delegation prompt naming do-your-research or pick-for-the-problem, and recommends a skills: preload only as guidance."
---

/discipline:use-your-skills I'm about to spin up a subagent to do the research pass; the delegation prompt names no skills.
