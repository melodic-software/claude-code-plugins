---
description: "The `tournament` argument on a high-stakes, hard-to-refactor name: widen to ~5 blind generators, then elimination rounds with independent scoring judges, ending at a finalist plus runners-up for the human (SKILL.md 'tournament action', lines 192-226). The skill must frame the bracket honestly as an adaptation, not a documented naming technique (lines 222-226). Generators stay fresh-context, so none is a fork. Settling the rubric before the pool returns leaves no tool-call trace and is not graded here. Agent needs no grant; no gated tool is listed."
tags: [naming, name-it-better, outcome, tournament, invented]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Agent]
expected_outcome: "At least five subagents run (generators, then judges), none a fork. The reply presents one finalist plus runners-up for the user to choose from and says the tournament is an adaptation of elimination brackets and pairwise scoring, not an established naming technique. It publishes or locks nothing."
---

/naming:name-it-better tournament

This is the name of our public npm package: a CLI and library that diffs two OpenAPI specs and reports the breaking changes between them. Once it is published, renaming it breaks every consumer's install. Our org already publishes `@acme/spec-lint` and `@acme/spec-mock`.
