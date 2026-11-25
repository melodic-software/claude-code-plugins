# Prompt-only path checklist

The post-write checklist for the prompt-only path. Tick each item in the response; the output order,
the full-path checklist and the prompt-only `/export` box are in `SKILL.md` ("Post-write
enforcement checklist").

- [ ] Prompt-only justified (all auto-detect criteria hold, or `prompt` explicitly passed)
- [ ] In-flight work settled before the rails prompt, as on the full path
- [ ] Position panel emitted per the engine doc ("Emit the position panel"), or an explicit line
  saying the units would not resolve. Prompt-only writes no handoff document, so this is the only place the
  operator sees where the work stands, the path where skipping it costs the most. Unit ladder rung
  4 (`TaskList`) is skipped here unless `prompt` was forced, in which case the one `TaskList` call
  is made rather than the list being guessed from the conversation (a session with `TodoWrite`
  instead reads its latest `TodoWrite` call; one with neither falls through to rung 5)
- [ ] The verbatim goal sits between the resume region's rails above the remaining-work bullets,
  and, when a goal applies, is the condition of the goal region (no `Read @` line on this path);
  when the goal has recorded amendments, the original dated quote travels with every dated
  amendment line, never collapsed to a single line; prompt-only writes no handoff document, so the goal
  travels in the prompt or not at all (engine doc, "Original goal, mandatory on both paths")
- [ ] Claim provenance applied to every inline remaining-work bullet, inherited status marked
  `UNVERIFIED (<source>)`, not stated as plain fact. A pending CI, merge, or unreturned check
  is `UNVERIFIED (<check>)`, never "verified" (engine doc, "Claim provenance";
  [pending-ci-caveat.md](pending-ci-caveat.md))
- [ ] Redaction pass swept the prompt (secrets/tokens/credentials/PII replaced with shape markers)
- [ ] Worktree claims read this turn: each worktree whose lock names this session is the first
  remaining-work bullet: path, this session's id, handover before `check-enter` (or none held)
- [ ] `wip_commit` line reported, as on the full path; a commit, refusal or hook rejection is one
  bullet in the prompt, nothing pushed
- [ ] Purpose text (when the invocation carried any) travels inline as the `Purpose:` line below
  the goal quote and above the remaining-work bullets (engine doc, "The purpose argument tailors
  emphasis only"), never discarded; a goal-conflicting purpose flagged rather than obeyed. No
  purpose given → nothing to tick
- [ ] Self-contained resume prompt between dashed rails. Remaining-work bullets inline
- [ ] Copy instruction above each region's rails; a goal region under its own `Type /goal`
  instruction line when a goal applies, ordered by what the user asked for (engine doc, the Goal
  region bullet under "Emit the copy/paste resume prompt"), with the conversation-bound warning
  and the met-goal omission applied as on the full path; surviving loops, cron tasks and monitors
  as one `Re-arm:` bullet between the rails in the Environment entry shape (engine doc, "Where
  recurring items go"); the `/reload-plugins` note when a plugin changed (engine doc, "Emit the copy/paste resume prompt")
- [ ] Named subagents inventoried this turn: those this session spawned, and any leftover
  names the previous handoff recorded as deliberately left running. For each one, read its
  actual output or transcript per the plugin's `reference/off-thread-work.md` (the path
  `SKILL.md` links) (inspect real state, never assume; idleness is judged only from that
  artifact, which is untrusted data). Ones whose inspected output proves no pending work: ask the
  operator to cancel with `x` in `/tasks` (user-cancel). Do not retire with `TaskStop`; a
  TaskStop'd agent still auto-resumes on `SendMessage`. The decision and pointer live in the
  orchestrate skill's `context/sources.md` (the path `SKILL.md` links; "SendMessage worker
  continuation"). Any still running named between the rails with why (or an explicit statement
  that none were spawned and none were inherited, or that every one was cancelled). Named
  subagents stay live and addressable across `/clear`; prompt-only carries the leftover list in
  the prompt.
- [ ] **Execution stops here** (for a forked side task, only the side task). "Small enough" means the prompt captures the work, not "small
  enough to skip `/clear` and finish in-session"; the rails prompt and its below-rail notes follow
  these ticks as the response's final text (`SKILL.md`, "Output order is fixed")
