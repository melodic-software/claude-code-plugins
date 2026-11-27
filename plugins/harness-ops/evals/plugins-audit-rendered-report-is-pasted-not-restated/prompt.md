---
tags: ['plugins-audit']
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The response pastes the rendered report as printed with its closing Reload lines (bare /reload-plugins, then /reload-plugins --force only if that warns), and adds no reload advice of its own. It does not retype, paraphrase, or recompute any count, id, scope, or version the render already carries (the 3, the 1, gamma''s versions, the 2 and 7 of the Divergences line), does not add rows the render omitted, and does not compute its own Divergences split from the digest. It also does not add a monitor call-out of its own: that bullet is the render''s, under Action needed, when the digest''s updated_with_monitors is non-empty.'
---

/harness-ops:plugins-audit: sync-run.sh --audit --render printed the digest line and then the rendered report, whose `Would change` section reads `would update: 3 plugin(s)` with three `would run: claude plugin update … -s user` lines and `would withhold: 1 downgrade(s)` naming gamma@market1 0.5.0 → 0.1.0, whose `Left as they are` section holds a `divergences: 7 in all` row with `7 actionable`, `2 here` and the `/harness-ops:plugins converge` remedy under it, then a `Run` footer with the timing rows, and the closing lines `Reload: after sync applies these, run /reload-plugins` and `if it warns, rerun it as /reload-plugins --force`.
