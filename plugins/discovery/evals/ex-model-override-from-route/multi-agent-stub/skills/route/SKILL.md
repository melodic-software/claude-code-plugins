---
description: "Model and effort per agent role (orchestrator, worker, verifier, retrieval) for a multi-agent run, resolved through the bundled defaults and the user, team and personal override config layers into fenced JSON with single-agent and fan-out variants and the layer behind each value. Use when asked 'which model for the subagents', 'route the roles' or 'model routing', or before a skill passes a role's model on a spawn."
argument-hint: "<role|all> [workload] [session=<alias>]"
user-invocable: true
disable-model-invocation: false
---

# Route (eval stand-in)

This sandbox's personal-override layer, `.claude/multi-agent.local.yaml`, sets
`roles.retrieval.model: opus`; the bundled defaults decide every other value.

Print the JSON below in one fenced `json` block, with `session_model` set to the session alias the
caller passed (or `opus` when none was passed); for one role, keep only that role under `roles`.
`source` names the layer behind each value and `basis` says why it holds: `config` means a
consumer layer set it.

```json
{"session_model":"opus","session_frontier":false,"workload":"research","roles":{"orchestrator":{"role":"orchestrator","single":{"model":"inherit","omit_model":true,"effort":"high","guarded":false},"fanout":{"model":"inherit","omit_model":true,"effort":"high","guarded":false},"source":{"model":"bundled","effort":"bundled"},"basis":{"model":"judgment","fanout_model":"judgment","effort":"judgment"}},"worker":{"role":"worker","single":{"model":"inherit","omit_model":true,"effort":"medium","guarded":false},"fanout":{"model":"inherit","omit_model":true,"effort":"medium","guarded":false},"source":{"model":"bundled","effort":"bundled"},"basis":{"model":"judgment","fanout_model":"judgment","effort":"upstream"}},"verifier":{"role":"verifier","single":{"model":"inherit","omit_model":true,"effort":"high","guarded":false},"fanout":{"model":"inherit","omit_model":true,"effort":"high","guarded":false},"source":{"model":"bundled","effort":"bundled"},"basis":{"model":"judgment","fanout_model":"judgment","effort":"upstream"}},"retrieval":{"role":"retrieval","single":{"model":"opus","omit_model":false,"effort":"medium","guarded":false},"fanout":{"model":"opus","omit_model":false,"effort":"medium","guarded":false},"source":{"model":"personal-override","effort":"bundled"},"basis":{"model":"config","fanout_model":"config","effort":"upstream"}}},"notes":[]}
```
