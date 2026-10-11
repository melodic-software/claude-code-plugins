# Handoff gotchas

Failure patterns from real sessions. Loaded on demand from the handoff SKILL.md.

- **A chain that preserved every fact and lost the point.** A handoff chain preserves state
  perfectly and intent not at all unless the goal field is mandatory and immutable. Each hop
  serializes the machinery in front of it, the phase, the bundle, the checklist, as though that
  were the mission, and the resumed session optimizes it faithfully. No single hop looks wrong:
  every paraphrase is plausible, and the loss only shows up in the aggregate, many sessions later.
  Quote the user's goal verbatim in section 1, copy it from the prior file read off disk instead of
  re-deriving it, and write completion criteria as the goal-states they establish. A criterion that
  can be satisfied while the goal is no closer is a process milestone under the wrong heading.
- **The file written, the prompt never emitted.** Observed at high context occupancy: the handoff
  file lands on disk with correct content, the checklist reports success, and the turn ends without
  the rails prompt ever reaching the screen. The operator is left holding a `/clear` they cannot
  resume from, which is worse than never running the skill, because the skill claimed to have run. The
  inversion is what makes it easy: the engine's optional half (the file) gets delivered and its
  mandatory half ("A resume prompt is ALWAYS emitted") gets dropped, while every STOP instruction in
  the skill reads as license to end the turn once the file exists. Two rules exist against it, and
  they are the same rule from both ends: STOP ends the underlying task, never the response before
  the prompt is on screen (SKILL.md, "What STOP means"); and the rails block plus its below-rail
  `/loop` re-arm notes are the response's final text (SKILL.md, "Output order is fixed"). Recovery
  when it happens anyway: `/session-flow:find-handoff` rung 1 globs the handoffs dir and needs no
  transcript.
- **The panel eating the prompt.** The position panel is emitted before the rails block, so it is
  text standing between the start of the response and the one thing the operator has to have. Under
  the same heavy context that produces the failure above, a panel that grows, with every unit of a
  long rail spelled out, blocks wrapping into paragraphs, and a divergence explained rather than
  named, is a turn that runs out of room before the rails. The rules that hold it small are
  required, not cosmetic: one line per unit, one line per block, elide above 8 units, 16 lines
  total. And when anything about the panel is uncertain, the answer is an abbreviated panel or a
  single line saying the units would not resolve, never a delayed or dropped rails prompt (engine
  doc, "The panel NEVER gates the rails prompt").
- **The handoff written free-hand, with no rails at all.** The dominant failure in the transcript
  audit (10 of 25 handoff writes on this machine): a session wrote a `*-handoff-*.md` file through
  `Write` or `Edit` without ever invoking `/session-flow:handoff`, so nothing in it had read the
  engine, and no resume prompt reached the screen. The file looked complete; the operator had
  nothing to paste. The resume directive now carries the rule into every successor session
  ("For the next save-point invoke /session-flow:handoff via the Skill tool; never write a
  handoff file free-hand"), and any other surface that still licenses a free-hand write (a hook
  reason, another skill's fallback note) is a defect to close, not a route to take. A handoff
  file that a session did not produce through the skill is a defect to raise, not a save-point
  to resume from.
- **ASCII rails.** A `-----` or `=====` line typed in place of the U+2500 `─` rail (2 of the 15
  skill-produced prompts in the audit). It reads as a rail to a human and is invisible to
  `find-handoff`, which keys on the U+2500 glyph, so the prompt is unrecoverable after `/clear`.
  On the full path the script writes the rails and the validator refuses any other glyph; on
  screen, paste the `emit` output rather than retyping it, and never let a terminal or editor
  "normalize" the glyph.
- **Prompt-only when durability is required.** Prompt-only fits small, self-contained follow-ups;
  when a plan artifact, dead-ends, or decisions the work depends on stand behind it, write the
  durable handoff file. Any doubt → full handoff.
- **Dropping plan-anticipated work on batch pushback.** When the user rejects N≥2 proposed
  actions, separate by category (plan-anticipated vs invented); never silent-drop all.
- **Handoff without sanity-check evidence.** A met/unmet mark on a completion criterion needs
  verifiable evidence (a grep hit, a test exit code), not "looks good."
- **Continuing after the user says stop.** A handoff is a save-point, never permission to keep
  implementing. Respect explicit pause/stop.
- **Idle named subagents left resident.** A save-point that captures TaskList but never reaps idle
  named agents can leave them resident for later sessions. Inventory the named subagents this
  session spawned and any leftover names the previous handoff recorded as deliberately left
  running. For each one, read its actual output or transcript per `reference/off-thread-work.md`
  (inspect real state, never assume). Ones whose inspected output proves no pending work: ask the
  operator to cancel with `x` in `/tasks` (user-cancel). Do not retire with `TaskStop`, which does
  not stop a later `SendMessage` from resuming the agent. Record any still running (with why) so
  the resuming session inherits the list. Which subagents survive `/clear` and which stops a later
  message can resume are upstream behavior: read them live.
  - **Pointer**: [Create custom subagents § Resume subagents](https://code.claude.com/docs/en/sub-agents#resume-subagents)
  - **Evidence**: the `TaskStop` rule and its empirical probe are our own record,
    [orchestrate sources § SendMessage worker continuation](../../orchestrate/context/sources.md#sendmessage-worker-continuation)
  - **As of**: 2026-10-11
  - **Recheck trigger**: that section changes which stopped subagents a message resumes, a
    release note changes subagent lifetime across `/clear`, or the orchestrate record changes its
    `TaskStop` rule or probe.
- **Saying nothing about the active `/loop`s on resume.** Treat every `/loop` as gone once the
  user clears or resumes: a resume prompt that reads only as a one-shot continuation runs once and
  silently drops the recurring behavior, with no error to signal it. Each re-arm is a SEPARATE
  follow-up message carrying the ORIGINAL loop prompt, one per surviving loop, never the resume
  directive wrapped in `/loop`. The engine's counted entry header labels each re-arm inside the
  save-point's own output so a consumer can find its edges (engine doc, "Emit the copy/paste
  resume prompt"); the header is not part of what gets sent, and the follow-up message itself
  begins with `/loop`, because we never rely on a command anywhere but at the start of a message.
  `/loop` re-runs the prompt it was given on every iteration, and a save-point is an immutable
  record of one moment, so wrapping the directive would have every later tick re-read that frozen
  file and replay a remainder already done, instead of doing the loop's actual recurring job.
  Which scheduled and background tasks a resume restores is upstream behavior: read it live.
  - **Pointer**: [Run prompts on a schedule § Limitations](https://code.claude.com/docs/en/scheduled-tasks#limitations)
  - **As of**: 2026-10-11
  - **Recheck trigger**: that section changes which tasks a resume restores, or a release note
    names session-scoped scheduled tasks or `/loop` across `/clear`.
- **A `/goal ...` first line inside the pasted block.** We never rely on a command anywhere but at
  the start of a message (our rule; no docs section states it), so a `/goal <condition>` line
  pasted from a rails prompt is treated as setting nothing, while the handoff looks complete. The
  goal region therefore holds the condition alone, under an instruction that has the user type
  `/goal` and a space by hand, paste the region, and check that the goal shows as active (engine
  doc, "Emit the copy/paste resume prompt"). Never emit a leading `/goal` line between any rails.
  - **Pointer**: [Keep Claude working toward a goal § Set a goal](https://code.claude.com/docs/en/goal#set-a-goal),
    for the command syntax and the active-goal indicator.
  - **As of**: 2026-10-11
  - **Recheck trigger**: that section changes the `/goal` syntax or the indicator.
