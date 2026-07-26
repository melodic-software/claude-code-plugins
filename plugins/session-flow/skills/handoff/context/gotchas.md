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
- **Dropping the `/loop` wrapper on resume** — a resume prompt written for a session running under
  `/loop` must re-arm it as the outermost first line (engine doc, "Emit the copy/paste resume
  prompt"), the same way an active `/goal` gets re-armed. `/clear` starts a fresh conversation, which
  clears every session-scoped scheduled task — a resume prompt that reads only as a one-shot
  continuation task runs once and silently drops the recurring behavior, with no error to signal it.
