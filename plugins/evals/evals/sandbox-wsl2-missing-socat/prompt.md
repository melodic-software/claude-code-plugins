---
description: "Hard case. Why hard: The base model treats WSL2 as having a working sandbox and stops there; that WSL2 needs socat as well as bubblewrap, and that a missing one means each Bash-granting run is refused, are this plugin's preflight record."
tags: [preflight, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says the sandbox backend is not usable here because socat is missing, so each run granting Bash would be refused and score 0; install socat, restart Claude Code, and confirm with /sandbox before paying for the run"
---

I'm on WSL2 (Ubuntu); `/proc/version` shows `microsoft-standard-WSL2`. `command -v bwrap` prints `/usr/bin/bwrap` and `command -v socat` prints nothing. One case in my plugin's eval suite lists Bash in allowed_tools and I'll pass --allow-tools Bash. WSL2 has the sandbox, so I'm good to pay for the run, right? Answer in under 150 words.
