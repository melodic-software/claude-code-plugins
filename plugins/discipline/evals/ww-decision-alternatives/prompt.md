---
description: "Legacy wait-what 1, its prompt behind the slash command. History: a dense reply that ends 'so we ship that' without naming the decision (stream the export rows) or the alternatives it set aside (a chunked variant, a higher pod memory limit). The re-pitch restores the missing context (SKILL.md lines 12-18 and 24-26). decision-named needs streaming named, alternatives-named both alternatives, context-not-restated (llm) the three legacy expectations verbatim. A history_file case runs single-arm, so pass --ablation with-without."
tags: [discipline, wait-what, outcome, history, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Says the decision is to stream the export rows instead of building the file in memory, and names the two alternatives set aside (chunking, a higher memory limit) and why."
---

/discipline:wait-what I lost you after 'so we ship that'. What decision? What alternatives did you skip?
