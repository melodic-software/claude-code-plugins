---
description: "Legacy hold-my-hand 6 (prompt verbatim). Regression guard: the chained history (phasing on, Phase 1 done, Phase 2 of 4 presented) carries no skill body, so the turn measures a model told to stop phasing with the phased turns in view, which a bare model also obeys; the be-ambitious hard-goal case (tagged hard) is this plugin's hard case. Graders: says-phasing-stopped (exp 1), finishes-or-hands-back (llm, exp 2), no-more-phasing (no 'Phase N of M' count and no `phase N done` reply, exp 3). A history_file case runs single-arm on a path target."
tags: [discipline, hold-my-hand, outcome, history, regression-guard, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "One line saying phasing stopped, Phase 2's registration step handed back, and the remaining work in normal output with no phase count or advancing reply."
---

stop phasing, just do it all and give me normal output from here.
