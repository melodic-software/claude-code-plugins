---
description: "Hard case. Why hard: bwrap and socat both resolve, so the base model calls the WSL2 sandbox ready; that the CLI refuses every Bash-granting run while the Docker credential store holds a symlink, and that repointing DOCKER_CONFIG only dodges a safety check, are this plugin's preflight record."
tags: [preflight, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says the run is not ready: the CLI refuses every Bash-granting run because ~/.docker holds symlinks the sandbox cannot reliably exclude; resolve the links or use a host without them, and does not suggest repointing DOCKER_CONFIG"
---

I'm on WSL2 (Ubuntu) with Docker Desktop's WSL integration on. `command -v bwrap` and `command -v socat` both resolve. `find ~/.docker/ -mindepth 1 -type l` prints `/home/<user>/.docker/contexts` and `/home/<user>/.docker/features.json`, both links into `/mnt/c`. One case in my plugin's eval suite lists Bash in allowed_tools and I'll pass --allow-tools Bash. Is this machine ready to pay for the run? Answer in under 150 words.
