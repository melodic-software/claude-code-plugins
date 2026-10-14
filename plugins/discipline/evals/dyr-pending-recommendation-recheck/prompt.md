---
description: "Inline tier on pending recommendations: two concrete specifics in the note (jest as the test script, engines node >=16) contradict package.json; the run must verify them against the file and restate each with a Basis label"
tags: [discipline, do-your-research, outcome, scaffold]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Edit]
expected_outcome: "Reads package.json, corrects recommendation 1 from jest to vitest and recommendation 2 from node >=16 to >=20, and labels each restated recommendation with Basis: verified or Basis: judgment (or withholds it as an open question)."
---

/discipline:do-your-research re-check the pending recommendations in notes/recommendation.md before I act on them
