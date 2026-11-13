---
description: 'Legacy apply-preserves-unrecognized-keys-and-custom-bands. The scaffold seeds a fully valid zones.json (40/70, custom token_bands, display_color) under the run''s home, so bare apply repairs nothing. setup SKILL.md lines 170-176 (bare apply is repair-only; custom valid bands are never overwritten), 177-179 (apply defaults is the explicit route), 180-188 (unrecognized keys preserved; merge with jq, never a jq-less rewrite, hence no-write and no-edit), 189 (idempotent), 193-194 (nothing outside zones.json). token_bands are seeded on purpose: without them bare apply must add the shipped token bands (lines 173-175), a write. Legacy ''writes only zones.json'' is no-other-shell-write plus no-write and no-edit. Host-bound: needs jq on PATH, and without it apply FAILs with the jq remediation (lines 185-188). Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [context-usage, setup, apply, idempotent, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Leaves 40/70 and the custom token bands untouched and reports them, keeps display_color, names apply defaults as the route to shipped defaults, says a second run changes nothing; no Write, Edit, other shell write, install or plugin CLI write.'
---

/context-usage:setup apply

My zones.json has custom bands (40/70 and my own token bands) and a display_color key another tool of mine reads. Afterwards tell me what changed in the file, what happened to my bands and to display_color, how I would get the shipped defaults instead, and what a second identical run would change.
