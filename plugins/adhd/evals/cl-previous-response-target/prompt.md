---
description: "Legacy clarify 1. History: the previous assistant message is a dense Round 4 holding four cross-referenced decisions (Q12 to Q15). The prompt 'make this clear' carries no target, so the skill restructures that message (SKILL.md lines 19-20, 33-34) without asking what to clarify, keeps each Q id as a back-link beside its own row numbers, quotes the operative terms verbatim, closes with the lens line, and keeps the altitude (llm). skill-fired is a with-only indicator. A history_file case runs single-arm on a path target; pass --ablation with-without to compare."
tags: [adhd, clarify, outcome, fidelity, history, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "A one-decision-per-row view of Round 4 with rows 1-4 mapping to Q12-Q15, operative terms verbatim (ledger-scheduler, 02:30 UTC, max_attempts: 4, 90-second, IR-2291 §4, legacy_rates, 0057, 3.2.0), no question asking what to clarify, no plain-language substitutes, and a closing lens line."
---

make this clear
