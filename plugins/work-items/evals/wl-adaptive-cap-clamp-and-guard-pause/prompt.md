---
description: 'Legacy work-loop 2. A persisted item_cap of 5 clamps to the ceiling 3, a dirty item lowers it, the frontier-tier item runs at concurrency 1, and an opted-in 98% trip drains and pauses with a session Monitor. clamp-5-to-3 reads the reply. Read-only tools, graded on the reply.'
tags: [work-loop, adaptive-cap, rate-limit]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The cycle clamps item_cap 5 to the ceiling 3 and reports it, delegates each item to /work-items:work with worker-side provisioning, runs the frontier-tier item at concurrency 1 under ceiling 2, counts the failed verdict and exit 8 as dirty (cap down, streak reset), drains and pauses on the 98% trip until resets_at with a session Monitor on the snapshot file, latches rate_limit_latch, and persists the final post-outcome cap and guard mode.'
---

/work-items:work-loop

Durable state: item_cap=5, clean_streak=2, rate_limit_latch=false. work_loop_item_cap_ceiling is unset (manifest default 3). This cycle one item completes clean and a second returns a failed verdict after a seam exit 8 backoff. Mid-cycle the snapshot file at ~/.claude/rate-limit-guard/rate-limits.json shows five_hour used_percentage 98 with a fresh captured_at. One admitted item carries the capability-tier: frontier label. The lane's session environment sets LOOP_LANE_RATE_LIMIT_PAUSE=1 (the operator opted in to pausing).

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
