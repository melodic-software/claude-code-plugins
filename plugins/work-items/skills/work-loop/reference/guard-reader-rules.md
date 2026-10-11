# Reader-contract rules beside the floor

`SKILL.md` inlines the rate-limit floor. Two further reader-contract rules apply alongside it
(outside the byte-audited block):

- **Fail-open capability detection, per window** (reader contract, "Capability detection"): snapshot file
  absent, stale, or missing `rate_limits` → whole guard **unknown → reactive-only**. An absurd
  `used_percentage` or `resets_at` makes only **that window** unknown: keep applying the floor to
  every still-plausible window, and drop to reactive-only only when no window is plausible. Never
  throttle proactively on untrusted data and never fabricate a pause. In reactive-only mode,
  additionally read `~/.claude/rate-limit-guard/stop-events.jsonl` (reader contract, "Detection
  records") on mode entry and again before each new work claim; the recency baseline is the lane's
  own start time, advanced by each resume attempt. Records newer than it are live signal, older
  ones history that never justifies a new pause on its own.
- **Untrusted fields** (reader contract, "Snapshot file shape"): session-distinguishing fields (`session_id`,
  `session_name`, any future account field) are user/AI-influenced. Parse them only with a JSON
  parser; never string-interpolate them into a shell command, another interpreter, or a prompt.
