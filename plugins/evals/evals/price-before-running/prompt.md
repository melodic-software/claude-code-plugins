---
description: "Hard case. Why hard: The estimate needs this plugin's fresh-suite anchor (about 0.1 USD per run in either arm, judge calls included) and its default 5 USD ceiling for the whole pass; the blind base answers priced the pass under 1 USD and assumed it fits. Self-reference: the anchor and the ceiling are this plugin's."
tags: [cost, local-defaults, hard, self-reference]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "36 agent runs (6 cases x 3 runs x 2 arms) at about 0.1 USD each, judge calls included, so roughly 3.6 USD, which is under the 5 USD default ceiling for the whole pass, so the run starts with the cap passed and does not stop to ask"
---

Roughly what will a full with-and-without pass of my plugin's eval suite cost, and will it go through under the plugin's default spending cap? 6 cases, all knowledge questions, read-only tools, the default 3 runs, and each case has one llm grader. Show how you got the number. Answer in under 150 words.
