---
description: 'The scaffold repository has config/services.json with 40 entries (name, owner, path), each path a tracked services/ folder, and a plain build.sh; the hotspot ranking itself is narrated, since collision-hotspots.sh needs a GitHub remote.'
tags: ['reduce', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
max_turns: 40
timeout_seconds: 900
expected_outcome: 'Runs derivable-list.py on the ranked file, verifies the list is a second list (most entries name folders git tracks), ledgers it as a route-lane entry without editing it, and reports a Design-It-Twice comparison of keeping the list, build-time discovery and generating the list from the tree with a --check drift step, noting that discovery needs a loader this stack lacks and that the owner-team data must move into each service''s own file before the list can be derived, then recommends one design for the human to pick.'
---

/coupling:reduce repo

The hotspot lens ranked config/services.json first: 40 entries, each with a name, an owner team and a path under services/, and every new service PR edits it. We build with plain shell scripts, no bundler.
