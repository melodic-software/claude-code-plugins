---
description: "Legacy morning-brief 10. Reaches SKILL.md 'Status report page' and context/view.md 'Resolve the medium': the resolver ignores a team file's medium: artifact, so the plugin default decides a local file; the skill prints the report line and the never-publishes notice, builds the page with build-brief-view.mjs to a local temp file and never calls the Artifact tool. says-never-publishes reads the reply; meets-expectations judges the rest. Bash is listed only so SKILL.md's pre-computed context lines load; needs --allow-tools Bash. Graded on the reply."
tags: [work-items, morning-brief, hard, status-page, config-cascade]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Reads context/view.md and runs the shared view-settings.mjs resolver (resolve --lane work-items:morning-brief). The resolver ignores the team file's publishing value, so the plugin default decides a local file; the skill prints the report line and the notice saying a team file never publishes. It runs scripts/morning-brief.sh once into a file, prints the brief, builds the page with scripts/build-brief-view.mjs to a local temp file and gives its path. It never calls the Artifact tool and does not weigh the team file itself."
---

/work-items:morning-brief

Interactive session with the Artifact tool available. The repository's tracked team file, rendered-views.yaml in its convention home, says `medium: artifact`; there is no personal rendered-views.local.yaml beside it and this plugin's `medium` option is unset.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
