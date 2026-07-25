# Auditing an agent / subagent

Growable stub.

## Read first

- The agent definition (`.md` with frontmatter): `name`, `description`, `model`, `tools`/allowed
  tools, any skills it auto-loads.

## Check

- **Description/discovery** — does the description make the agent findable for its intended tasks,
  and does it state when NOT to use it?
- **Model** — explicitly set where the task demands it (not accidentally defaulting to a weak
  model), or deliberately inheriting?
- **Tool scope** — least privilege, named honestly: does it have the tools it needs and not
  dangerous extras? A Bash grant on a "read-only" agent is a claim to verify, not accept.
- **Isolation implications** — a fresh subagent context has no parent history; does the agent's
  prompt supply the context it needs (working dir, input paths, output contract)?
- **Composition** — auto-loaded skills exist and match by exact name?
- **Untrusted input** — if the agent reads third-party content, does it carry a standing
  data-not-instructions posture?
- **Determinism** — repeatable behavior, or does it rely on ambiguous instructions?

## Reproduce

Dispatch it on a representative task; check it returns a concise, correct result without polluting
main context.
