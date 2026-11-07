---
description: "Legacy clarify 5. History: the user coins 'the outbox lane' and 'the drain gate', the assistant writes a design memo (M1 to M3) that also uses 'R3 budget' and 'poison pill', then two short replies follow. '/adhd:clarify the design memo you wrote three messages ago' names an explicit target, which overrides the previous-response default (SKILL.md lines 19-20). memo-terms-verbatim needs the memo's operative terms; not-latest-message fails a restructure of the latest reply; glossary-defines-coined-terms needs a glossary defining the outbox lane, the drain gate and the R3 budget (lines 63-65; poison pill is an established term the memo defines inline, so only the llm grader looks for it); lens-line-closes needs the lens line last; glossary-same-altitude (llm) quotes legacy expectations 3 and 4. A history_file case runs single-arm on a path target; pass --ablation with-without to compare."
tags: [adhd, clarify, outcome, glossary, history, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "A restructure of the design memo (not the build or flaky-test replies) with orders.webhook_outbox, 5 attempts, 15 minutes, orders.webhook_dead and 10 minutes verbatim, a glossary defining the outbox lane, the drain gate, the R3 budget and poison pill at the same altitude, and a closing lens line."
---

/adhd:clarify the design memo you wrote three messages ago
