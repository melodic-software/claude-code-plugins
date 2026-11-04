---
description: "Triggering case. A plain question about a WSL2 sandbox missing socat, which does not name the skill, loads evals:plugin-eval. It tests triggering; sandbox-wsl2-missing-socat tests the answer once the skill is loaded."
tags: [preflight, triggering]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The plugin-eval skill fires before the answer"
---

I'm on WSL2 (Ubuntu); `/proc/version` shows `microsoft-standard-WSL2`. `command -v bwrap` prints `/usr/bin/bwrap` and `command -v socat` prints nothing. One case in my plugin's eval suite lists Bash in allowed_tools and I'll pass --allow-tools Bash. WSL2 has the sandbox, so I'm good to pay for the run, right? Answer in under 150 words.
