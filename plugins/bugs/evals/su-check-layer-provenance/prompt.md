---
description: "/bugs:setup check, asked which focus areas scan uses, on a repo with a tracked team focus area, a tracked docs/conventions/work-items.yaml setting filing_posture: allowed, and a gitignored personal override with areas: []: reports each layer (user-global, team, personal override) separately with its git probes, names the empty list as an opt-out that leaves scan no focus areas here, gives filing_posture allowed with work-items.yaml as its layer, reports the retired .claude/bugs.local.md path via its report-only retirement record as INFO, and writes nothing. setup SKILL.md check B1-B3 and B6, and reference/config.md Merge semantics and Filing posture. Needs --scaffold --allow-tools Bash."
tags: [bugs, setup, check, outcome, scaffold]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Bash, Read, Glob, Grep]
expected_outcome: "The reply names the user-global, team and personal-override layers, runs ls-files on the team file and check-ignore on docs/conventions/bugs.local.md, says the override's areas: [] opts out so scan has no focus areas on this machine, reports filing_posture: allowed from docs/conventions/work-items.yaml, reports retirement record bugs-r001 as INFO for the retired .claude/bugs.local.md (no longer read, no apply migration), and changes no file."
---

/bugs:setup check

Which focus areas does scan actually use here?
