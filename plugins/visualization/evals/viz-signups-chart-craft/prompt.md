---
description: "Legacy visualize 3. Monthly signups are a quantitative trend, so the form is a chart, and SKILL.md lines 85-89 route the chart craft to a chart-craft/dataviz capability when one is installed, else a simple default chart with a line saying the craft capability was unavailable. dataviz is a bundled Claude Code skill, so a run may take either branch. chart-rendered grades Unicode bars or an inline SVG in the reply; craft-presence-gated (llm on the trace) legacy expectations 1-3 verbatim, both branches as the legacy words them. Expectation 4 ('Does not restate chart craft ... in the skill') is a property of the SKILL.md text, not of a run."
tags: [visualization, visualize, outcome, form-pick, no-network]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "A chart of the six monthly signup values (Unicode bars in the terminal or an inline SVG), with the chart craft either taken from a dataviz or chart-craft skill call or replaced by a simple default and a line saying the craft capability was unavailable."
---

/visualization:visualize these monthly signups: Jan 120, Feb 180, Mar 150, Apr 240, May 300, Jun 280.
