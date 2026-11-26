---
description: "The session-start peer list reaches the model before the first prompt: a stub claude in the run's temporary home lists one live peer whose name is derived from this session's id, and the reply names that peer with no tool call"
tags: [fleet, peer-list, hook]
max_turns: 3
timeout_seconds: 180
allowed_tools: [Glob, Grep]
expected_outcome: "The reply names the one live peer session from the peer list the fleet hook added at session start, by its exact name (fleet-peer- followed by eight hex characters), and the run makes no Bash or Read call."
---

Which other Claude Code sessions are live on my fleet right now? Answer only from what you already know at this point: do not run commands or read files. Give each live session's exact name.
