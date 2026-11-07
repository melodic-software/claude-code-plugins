---
description: "Legacy tighten-your-output 4, its prompt behind the slash command with the two files named. The scaffold seeds docs/refunds.md and docs/faq.md, each wordy, both stating the same refund policy. Terseness is not duplication: removing a second copy is point-dont-copy's job (SKILL.md lines 123-125). names-point-dont-copy needs the duplication routed there, refunds-keeps-policy and faq-keeps-policy each file still stating the whole policy (14 days, original payment method, never store credit), refunds-filler-cut and faq-filler-cut the filler gone from each. Needs --scaffold and --allow-tools Edit,Write."
tags: [discipline, tighten-your-output, outcome, boundary, scaffold, no-network]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Edit, Write]
expected_outcome: "Both docs lose their filler and each still states the full refund policy; the reply routes the duplicated policy to point-dont-copy."
---

/discipline:tighten-your-output docs/refunds.md and docs/faq.md: this section and the other doc both explain the same refund policy; also each is wordy on its own.
