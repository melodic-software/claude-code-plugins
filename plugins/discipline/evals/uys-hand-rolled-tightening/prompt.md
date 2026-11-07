---
description: "Legacy use-your-skills 1, refit: only the plugin under test loads, so no commit skill is in a run's listing; the reinvented procedure is a hand-rolled tightening pass that tighten-your-output owns. History: the user asked to cut a bloated README intro and the assistant spelled out and ran its own four-step procedure. SKILL.md lines 79-82: name the finding and invoke the skill this turn. names-the-skill (llm, trace, the skill half of legacy expectation 1) needs tighten-your-output named as the owner in the assistant's own text, before or after the Skill call (last_message holds only the text after the last tool call), names-the-procedure the reinvented procedure named by its steps (four-step, filler, splitting or merging sentences; the prompt's own words do not count), invokes-the-skill a Skill call to it (with-only indicator), skill-governs (llm, trace) legacy expectations 1 and 2 verbatim. Expectation 3 (no manufactured finding on clean use) is graded in uys-clean-quick-check. A history_file case runs single-arm, so pass --ablation with-without."
tags: [discipline, use-your-skills, outcome, history, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Names the hand-rolled tightening procedure and tighten-your-output as the listed skill that owns it, then invokes that skill this turn."
---

/discipline:use-your-skills you just hand-wrote a whole tightening procedure, but there's a skill for that in the listing.
