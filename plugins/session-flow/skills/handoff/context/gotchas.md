# Handoff gotchas

Failure patterns from real sessions. Loaded on demand from the handoff SKILL.md.

- **Prompt-only when durability is required** — prompt-only fits small, self-contained follow-ups;
  when a plan artifact, dead-ends, or load-bearing decisions back the work, write the durable
  handoff file. Any doubt → full handoff.
- **Dropping plan-anticipated work on batch pushback** — when the user rejects N≥2 proposed
  actions, separate by category (plan-anticipated vs invented); never silent-drop all.
- **Handoff without sanity-check evidence** — Progress claims need verifiable evidence (a grep
  hit, a test exit code), not "looks good."
- **Continuing after the user says stop** — a handoff is a save-point, never permission to keep
  implementing. Respect explicit pause/stop.
