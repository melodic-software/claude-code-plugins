---
tags: ['plugins-audit']
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The response pastes the rendered report as printed and appends exactly one line of its own: the reload guidance, stated as the docs'' two-step (run /reload-plugins; if it warns that the next message would re-read the conversation, run /reload-plugins --force). It does not retype, paraphrase, or recompute any count, id, scope, or version the render already carries (the 3, the 1, gamma''s versions, the 2 and 7 of the Divergences line), does not add rows the render omitted, and does not compute its own Divergences split from the digest. It also does not add a monitor call-out of its own: that bullet is the render''s, under Action needed, when the digest''s updated_with_monitors is non-empty.'
---

/harness-ops:plugins-audit — sync-run.sh --audit --render printed the digest line and then the rendered report, whose rows read `Would update: 3 plugin(s)` with three `would run: claude plugin update … -s user` lines, `Would withhold: 1 downgrade(s)` naming gamma@market1 0.5.0 → 0.1.0, `Divergences: 2 behind here → run /harness-ops:plugins converge; on this whole machine 7 actionable: …`, and a `Timing:` row.
