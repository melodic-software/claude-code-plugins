---
description: "Hard case, judged hard by a person. A model tends to read a non-inferior two-version compare as permission to ship a cut, but a suite that cannot see a loss passes any cut. Source: two skill cuts in this repository that shipped on such a reading and were later reverted. The answer must ask for a detection control and refuse to ship on the compare alone. Run it with --judge-model sonnet; no case or grader field sets the judge"
tags: [methodology, knowledge, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says the compare alone cannot show the cut lost nothing, asks for a detection control (the before text with the cut rule removed, run on the same cases and model, which must score clearly lower than the before text), and says the cut should not ship until that control shows the suite can detect a loss"
---

I trimmed two rules out of my skill's body to save tokens. I ran the suite on the old and the new version, 6 cases at 3 runs on the same model, both runs VALID, and the noise report's compare against the old version reads `compare verdict: non-inferior` with no `case drop` lines. Can I ship the trimmed version? Answer in under 200 words.
