---
description: 'Legacy measure 3. The baseline phase, before any change: several runs with warm-up discarded and mean and spread recorded, stored under the topic''s memory-tier baselines/ with baseline and target written into the plan, and, since the plan''s 2% target likely sits inside run-to-run variance, the noise-floor argument raised before the work (SKILL.md Two-phase model; Gotchas ''Noise floor first''; context/performance.md). The scaffold commits a parser, bench.py and an approved .work/fast-rows/PLAN.md. runs-bench grades bench.py run through Bash, baseline-file a file created under baselines/, plan-records-baseline the plan carrying a baseline figure, names-noise the noise argument in the reply; pre-change-capture (llm) legacy expectations 1 to 3 verbatim. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [verification, measure, performance, baseline, scaffold, no-network, hard]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Bash, Read, Glob, Grep, Skill, Write, Edit]
expected_outcome: 'Runs python3 bench.py several times before any change, discards warm-up, records mean and spread under .work/fast-rows/baselines/, writes the baseline and the 2% target into .work/fast-rows/PLAN.md, and says before the work that a 2% saving may sit inside the run-to-run noise.'
---

/verification:measure performance baseline
