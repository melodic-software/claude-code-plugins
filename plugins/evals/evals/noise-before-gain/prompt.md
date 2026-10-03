---
description: "Hard case, judged hard by a person. A model tends to take a 5-point gain at face value, and the right answer needs noise and ceiling reasoning. Read a small with-plugin gain over a near-ceiling baseline on a 4-case suite. Two graders split the five required points so one judge error costs half a run, not the whole run. Run it with --judge-model sonnet; no case or grader field sets the judge"
tags: [methodology, knowledge, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says the gain is not established, names the small sample (few cases or few runs) as why it is within noise, suggests harder or more cases before concluding, says a case at 1.00 in both arms shows nothing about the plugin, and says the 0.95 baseline leaves no headroom"
---

I changed my skill's description and re-ran `claude plugin eval` at the default 3 runs. The suite has 4 cases. The with-plugin mean went from 0.92 to 0.97; the without-plugin mean stayed at 0.95. Two cases score 1.00 in both arms. Has the new description improved the skill? Answer in under 200 words.
