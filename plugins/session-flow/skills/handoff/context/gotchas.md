# Handoff gotchas

Failure patterns from real sessions. Loaded on demand from the handoff SKILL.md.

- **A chain that preserved every fact and lost the point** — a handoff chain preserves state
  perfectly and intent not at all unless the goal field is mandatory and immutable. Each hop
  serializes the machinery in front of it — the phase, the bundle, the checklist — as though that
  were the mission, and the resumed session optimizes it faithfully. No single hop looks wrong:
  every paraphrase is plausible, and the loss only shows up in the aggregate, many sessions later.
  Quote the user's goal verbatim in section 1, copy it from the prior file read off disk instead of
  re-deriving it, and write completion criteria as the goal-states they establish — a criterion that
  can be satisfied while the goal is no closer is a process milestone under the wrong heading.
- **The file written, the prompt never emitted** — observed at high context occupancy: the handoff
  file lands on disk with correct content, the checklist reports success, and the turn ends without
  the rails prompt ever reaching the screen. The operator is left holding a `/clear` they cannot
  resume from — worse than never running the skill, because the skill claimed to have run. The
  inversion is what makes it easy: the engine's optional half (the file) gets delivered and its
  mandatory half ("A resume prompt is ALWAYS emitted") gets dropped, while every STOP instruction in
  the skill reads as licence to end the turn once the file exists. Two rules exist against it, and
  they are the same rule from both ends: STOP ends the underlying task, never the response before
  the prompt is on screen (SKILL.md, "What STOP means"); and the rails block plus its below-rail
  `/loop` re-arm notes are the response's final text (SKILL.md, "Output order is fixed"). Recovery
  when it happens anyway: `/session-flow:find-handoff` rung 1 globs the handoffs dir and needs no
  transcript.
- **Prompt-only when durability is required** — prompt-only fits small, self-contained follow-ups;
  when a plan artifact, dead-ends, or load-bearing decisions back the work, write the durable
  handoff file. Any doubt → full handoff.
- **Dropping plan-anticipated work on batch pushback** — when the user rejects N≥2 proposed
  actions, separate by category (plan-anticipated vs invented); never silent-drop all.
- **Handoff without sanity-check evidence** — a met/unmet mark on a completion criterion needs
  verifiable evidence (a grep hit, a test exit code), not "looks good."
- **Continuing after the user says stop** — a handoff is a save-point, never permission to keep
  implementing. Respect explicit pause/stop.
- **Saying nothing about the active `/loop`s on resume** — `/clear` starts a fresh conversation,
  which clears every session-scoped scheduled task, so a resume prompt that reads only as a one-shot
  continuation runs once and silently drops the recurring behavior, with no error to signal it. Each
  re-arm is a SEPARATE follow-up message carrying the ORIGINAL loop prompt, one per surviving loop
  — never the resume directive wrapped in `/loop`. The engine's counted entry header labels each
  re-arm inside the save-point's own output so a consumer can find its edges (engine doc, "Emit the
  copy/paste resume prompt"); the header is not part of what gets sent, and the follow-up message
  itself begins with `/loop`, since a command is recognized only at a message's start. `/loop` re-runs the
  prompt it was given on every iteration, and a save-point is an immutable record of one moment, so
  wrapping the directive would have every later tick re-read that frozen file and replay a
  remainder already done, instead of doing the loop's actual recurring job.
