---
description: "The prior reply is supplied inline because the case runs single-turn. The re-pitch must read the project glossary, use its term (settlement batch), add the missing premises (PSP, T+2 as two business days), and keep sentences short"
tags: [discipline, wait-what, outcome, scaffold]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Reads docs/glossary.md; the reply uses 'settlement batch', defines payment service provider and two business days for T+2, and has no run of 35 or more words without sentence punctuation."
---

/discipline:wait-what I lost you. Your last reply was: "The payout run slipped because the PSP moved the cutoff, so anything captured after 17:00 UTC rolls into the next batch and lands T+2 from that close rather than from today's, which is why Friday's captures show up Wednesday instead of Tuesday, and reconciliation will flag them as late until the ledger catches up."
