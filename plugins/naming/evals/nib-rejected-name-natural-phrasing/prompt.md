---
description: "Routing case, no slash command: a natural 'that name is wrong, give me better ones' retry on a rejected name must invoke the skill (SKILL.md line 2). The skill's sharpest rule: rejected incumbent NAMES stay out of the generator brief and sit on the main thread's reject list, while a user-stated blocklist WORD enters the brief with its reason (SKILL.md 'Default pass' step 1, lines 111-121). Generators are ~3 blind fresh-context subagents (step 2), so none is a fork, which inherits the conversation. The shortlist holds no compound built on the banned word (step 3). Agent needs no grant; no gated tool is listed, so nothing can be renamed here."
tags: [naming, name-it-better, outcome, routing, anti-anchoring, scaffold, invented]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Agent]
expected_outcome: "The run invokes naming:name-it-better through a Skill call, spawns at least three non-fork subagents whose prompts carry the 'Helper' blocklist entry with its reason but never the rejected name LedgerSync, and replies with a ranked shortlist (no candidate built on Helper) with one recommended pick, leaving the choice to the user."
---

You suggested `LedgerSync` for the class in src/ledger/reconcile.ts and that is the wrong name: it syncs nothing. It compares bank statement lines with ledger entries and flags the mismatches, and it never writes anything. Also keep the word `Helper` out of it; that word says nothing. Give me better ones.
