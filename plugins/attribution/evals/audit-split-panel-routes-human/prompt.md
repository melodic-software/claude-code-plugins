---
description: "A 31-word fingerprint span against an identity-checked source with a two-to-one judge split on C3-attribution-adequacy: the split routes to the human, the finding is not fix-eligible, the grades and quoted evidence are shown, and nothing resolves the split. Narration: the scenario is described, not present. Needs --allow-tools Bash (the skill's pre-computed config lines). Deterministic: not-fix-eligible-label (regex: the finding called not fix-eligible, or unable to be fixed)."
tags: [attribution, audit, narration, fix-eligibility, no-network]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply routes the finding to the human on the split rather than the majority, declares it not fix-eligible although the separation rule fired, says each judge's criterion grades are shown with their quoted evidence, and does not average, re-run or otherwise resolve the split."
---

/attribution:audit a file where the fingerprint module reports a 31-word matched span against an identity-checked source, but the three judges split two-to-one on C3-attribution-adequacy. What happens to the finding?
