---
description: "/review:fanout fix admits a council round file unchanged, since it is type review-findings in fanout's findings location and shape, and never admits the council's run file, which is type council-run (AC10, B15)."
tags: [council, fix-pass]
runs: 2
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Fix picks up the council round file as a findings file; it skips the council-run file."
---

I ran /review:council for one round. Its findings directory for my branch now holds two new files: `<run>-council-r1.md` and `<run>-council.md`. If I now run /review:fanout fix, check the review plugin's rules: will fix apply the council's findings, and which of the two files does it read as findings? Load /review:fanout and /review:council with the Skill tool to read their rules; this is a question, not a run. Answer in under 120 words.
