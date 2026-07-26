# Handoff gotchas

Failure patterns from real sessions. Loaded on demand from the handoff SKILL.md.

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
  and headed by the engine's counted entry header (engine doc, "Emit the
  copy/paste resume prompt") — never the resume directive wrapped in `/loop`. `/loop` re-runs the
  prompt it was given on every iteration, and a save-point is an immutable record of one moment, so
  wrapping the directive would have every later tick re-read that frozen file and replay a
  remainder already done, instead of doing the loop's actual recurring job.
