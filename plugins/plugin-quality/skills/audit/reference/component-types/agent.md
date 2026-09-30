# Auditing an agent / subagent

## Read first

- The agent definition (`.md` with frontmatter): `name`, `description`, `model`, `tools`/allowed
  tools, any skills it auto-loads.

## Check

- **Description/discovery**: does the description make the agent findable for its intended tasks,
  and does it state when NOT to use it?
- **Model**: does the definition name its model explicitly, so a dispatch that passes none does not
  fall through to the session's model? Is `inherit` used only with a stated reason on the model
  line?
- **Tool scope**: least privilege, named honestly. Does it have the tools it needs and not
  dangerous extras? A Bash grant on a "read-only" agent is a claim to verify, not accept.
- **Isolation implications**: a fresh subagent context has no parent history; does the agent's
  prompt supply the context it needs (working dir, input paths, output contract)?
- **Composition**: auto-loaded skills exist and match by exact name?
- **Untrusted input**: if the agent reads third-party content, does it carry a standing
  data-not-instructions posture?
- **Determinism**: repeatable behavior, or does it rely on ambiguous instructions?

## Categories

- **Errors:** a wrong result, an over-broad tool grant used as if it were least privilege, or an instruction in untrusted input that the agent obeyed.
- **Improvements:** context the prompt needs and does not supply, or a model line left implicit.
- **Quality of life:** a return the parent cannot use without re-reading the whole subagent transcript.
- **Standards:** the `seam-phrasing` and `untrusted-content` probes.
- **Emitted findings:** when the agent returns findings (a reviewer, an auditor), sample those findings and grade each.

## Reproduce

Dispatch it on a representative task; check it returns a concise, correct result without polluting
main context.
