# Settle in-flight work before writing

Hand off only once everything the handoff describes is settled; the failure shape is in
`context/gotchas.md`.

Before `save_point.py new` (or, on the prompt-only path, before the rails prompt), take every
still-running item of off-thread work this session started or the previous handoff recorded as
left running, the kinds in the plugin's `reference/off-thread-work.md` (the path `SKILL.md`
links) with spawned subagents the usual case, read its real state there, and sort it. Judge
progressing versus stuck by the Active-verification protocol in `/session-flow:keep-going`:
progress against elapsed time only raises suspicion, and ambiguous evidence means the work is
alive.

- **The handoff depends on it**: its result would change the brief, the next action, a decision,
  or a completion criterion. When it is progressing and expected to finish, wait for its result,
  fold the result into this session's state, then write the save-point.
- **The handoff does not depend on it**: it writes its own durable output and the next session only
  reads that output, such as a background workflow writing to a known path. Hand off without
  waiting and record it in Environment to re-establish, as the subagent inventory in `SKILL.md`
  does.
- **Dependent but stuck or long-running**: say so with the evidence from its real state, and let
  the user choose: wait, cancel it, or hand off with it recorded as in flight, its pending result
  marked `UNVERIFIED (<item> still running)` wherever the save-point leans on it. Under
  `unattended` no one is asked: take the third option and say so.

A user who asked to hand off now, without waiting, gets the third option for every dependent item.
