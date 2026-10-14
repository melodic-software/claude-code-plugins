---
description: "Reaches docpage-digest's Work root section (slug guard and 'Collision check, before the first write'): the work root for https://docs.example.com/api/overview already exists with a checklist recording a different canonical URL, so the run refuses and stops, naming the recorded URL, with no write, edit, or shell write under .work/"
tags: [knowledge, docpage-digest, outcome, scaffold, stop-gate]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply names the recorded URL https://docs.example.com/other/overview and says the run refused or stopped. No Write or Edit call, and no Bash command writes, moves, or removes anything under .work/."
---

/knowledge:docpage-digest https://docs.example.com/api/overview

That URL is already canonical: no redirects, no query string, no fragment.
