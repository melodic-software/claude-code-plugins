---
description: "assess on a one-file rename returns single in exactly two lines with no shape line. Also covers legacy assess 3 and 5: reason-dependent-shape needs a dependency-shape word (dependent, chain, sequential) on the reason line, which the prompt lacks, and fails a negated one (no dependencies, doesn't depend); reason-names-size needs a size statement there that the prompt lacks: a size word (small, tiny, short, trivial, minor, few, little, quick) or an un-negated 'fits this context', the legacy expected_output's own wording and SKILL.md step 2's 'the context it needs' (line 70); neither an echoed one 30-line nor one dependent chain alone passes (lines 19-21: size and effort set the verdict, not the topic); no Workflow call."
tags: [multi-agent, assess, outcome, single]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
expected_outcome: "The reply is exactly two lines, `verdict: single` and a `reason:` line, with no `shape:` line; the reason names the small size and the dependent shape. No agent or workflow is started."
---

/multi-agent:assess Rename the local variable `cnt` to `count` inside the one 30-line function `sumScores` in src/util/math.ts.
