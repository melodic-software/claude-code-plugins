---
description: "Three questions the lanes skill answers before any lane runs: auto-compaction is a lossy summary, not a reset; a lane is never restarted with `claude --resume <id> --bg`; `claude agents --json` does not list cloud sessions. Any git gather call stays a separate Bash call. Reaches SKILL.md (repository context, 'A relaunch is the only context reset', Gotchas, verified CLI surface) and context/config.md. Source: the consumer's own writing. routine. Needs --allow-tools Bash for the pre-computed lines. Held-rows rows: harness-ops 64, 66, 71, 74."
tags: [harness-ops, lanes, reference-answer, routine]
max_turns: 20
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "Nothing starts or stops. The answer says auto-compaction summarizes older history and is not a fresh context, declines `--resume ... --bg` as a restart (restart launches a fresh session from the prompt file), and says cloud sessions do not show in `claude agents --json`."
---

/harness-ops:lanes three questions before I set up a lane on this box:

1. If a lane runs for a week, does auto-compaction give it a fresh context, so I can skip restarts?
2. Can I restart a lane by resuming its session with `claude --resume <session-id> --bg`?
3. If I run a lane in the cloud, will `claude agents --json` show it?

Answer only, don't start or stop anything.
