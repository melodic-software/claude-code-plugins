---
description: "Hard case. Why hard: The base model expects Bash to run, unsandboxed, or via Git Bash; that each granting run is refused and scores 0, and the supported hosts, are this plugin's preflight record."
tags: [preflight, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says native Windows has no sandbox backend, so each run granting Bash is refused and scores 0, so do not pay for the run here; run it under WSL2, a Linux host with bubblewrap and socat, macOS, or a Claude cloud session"
---

I'm on native Windows, no WSL. One case in my plugin's eval suite lists Bash in allowed_tools because the skill runs a helper script, and I'll pass --allow-tools Bash. Anything I should know before I pay for the run? Answer in under 150 words.
