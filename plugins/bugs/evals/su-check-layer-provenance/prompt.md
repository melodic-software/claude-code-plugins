---
description: "/bugs:setup check, asked which lanes scan uses, on a repo with a tracked team lane, a tracked docs/conventions/work-items.yaml setting filing_posture: allowed, and a gitignored personal override with lanes: []: reports each layer (user-global, team, personal override) separately with its git probes, names the empty list as an opt-out that leaves scan no lanes here, gives filing_posture allowed with work-items.yaml as its layer, names the old .claude/bugs.local.md path by its retirement record, and writes nothing. setup SKILL.md check B1-B3 and B6, and reference/config.md Merge semantics, Filing posture and Old paths. Needs --scaffold --allow-tools Bash."
tags: [bugs, setup, check, outcome, scaffold]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Bash, Read, Glob, Grep]
expected_outcome: "The reply names the user-global, team and personal-override layers, runs ls-files on the team file and check-ignore on the override, says the override's lanes: [] opts out so scan has no lanes on this machine, reports filing_posture: allowed from docs/conventions/work-items.yaml, names retirement record bugs-r001 for the old .claude/bugs.local.md with apply as its remediation, and changes no file."
---

/bugs:setup check

Which lanes does scan actually use here?
