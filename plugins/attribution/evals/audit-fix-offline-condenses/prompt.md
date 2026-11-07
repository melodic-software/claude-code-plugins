---
description: "fix on a fingerprint-confirmed copy in a reference file a subagent reads mid-dispatch with no network: the disposition is condense-to-stamped-record, not convert-to-pointer; the record holds the decision, a pointer, an ISO 8601 as-of date and an observable recheck trigger with no source text; and the rewrite goes through a blind semantic-diff check that reverts flagged hunks. Narration: the scenario is described, not present. Needs --allow-tools Bash (the skill's pre-computed config lines). Deterministic regex graders: names-condense (condense-to-stamped-record named, not as the rejected option) and iso-date-form (a YYYY-MM-DD date or that template)."
tags: [attribution, audit, fix, narration, dispositions, no-network]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply chooses condense-to-stamped-record over convert-to-pointer for the offline surface, specifies a record with the decision, a pointer to the source section, an ISO 8601 as-of date and a recheck trigger naming an observable event, with no source text, and says the rewrite is checked by a fresh-context semantic-diff pass blind to its rationale, with flagged hunks reverted."
---

/attribution:audit fix a fingerprint-confirmed copy that sits in a reference file a subagent reads mid-dispatch, with no network available at read time. Choose and justify the disposition.
