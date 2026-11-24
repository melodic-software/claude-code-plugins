---
description: "Hard case. Why hard: the request states no quality bar, and the bookmark-sync case teaches the open discovery form for it, but here the survey finds evidence for one (the marketplace manifest and README publish the plugin to users who run it on their own machines, and a release workflow tags each version). Round 1 should ask the bar as a decision question recommending production from that evidence, with the other bars as alternatives and a Flips if: line, still asked and never settled silently."
tags: [interview, quality-bar, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Round 1 asks the quality bar as a question with a My recommendation: line recommending production, citing the repository's evidence that the plugin ships to users, lists the prototype and internal-tool bars as alternatives, and carries a Flips if: line; the bar is not on a Settled by evidence: line"
---

/planning:interview Add a --dry-run flag to the notes-export plugin's export script, so it lists the files it would write without writing them. I'm here and will answer; ask me your first round, then stop.
