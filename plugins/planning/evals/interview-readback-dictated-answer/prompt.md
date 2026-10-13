---
description: "Eval-first case for the per-answer read-back. Why hard: the dictated reply reads 'fee chair flag' for 'feature flag' and departs from two recommendations, so recording the answers as typed, or echoing them verbatim, both look like progress."
tags: [interview, read-back, dictation]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply restates Q2 and Q3 in its own words, says it took 'fee chair flag' to mean a feature flag, and asks the user to confirm Q2 and Q3 before treating them as settled; Q1 needs no confirmation question"
---

/planning:interview Add a dark mode toggle to the settings page.

You already asked round 1:

Q1: Should dark mode follow the operating system setting until the user picks one? My recommendation: yes.
Q2: How should the toggle roll out? My recommendation: behind a flag, off by default, then on for everyone.
Q3: Where should the user's choice be stored? My recommendation: on the user profile, so it follows them across devices.

My answers, dictated: Q1 yes. Q2 put it behind the fee chair flag but turn it on for staff first. Q3 local storage is fine for now.
