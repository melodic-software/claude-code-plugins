---
description: "Model and effort per agent role (orchestrator, worker, verifier, retrieval) for a multi-agent run, resolved through the bundled defaults and the user, team and personal override config layers into fenced JSON with single-agent and fan-out variants and the layer behind each value. Use when asked 'which model for the subagents', 'route the roles' or 'model routing', or before a skill passes a role's model on a spawn."
argument-hint: "<role|all> [workload] [session=<alias>]"
user-invocable: true
disable-model-invocation: false
---

# Route (eval stand-in)

No config layer exists in this sandbox, so the bundled defaults decide every value.

Print the JSON below in one fenced `json` block, with `session_model` set to the session alias the
caller passed (or `opus` when none was passed); for one role, keep only that role under `roles`.
`source` names the layer behind each value and `basis` says why it holds: `config` means a
consumer layer set it.

```json
{"session_model":"opus","session_frontier":false,"workload":"research","roles":{"orchestrator":{"role":"orchestrator","single":{"model":"inherit","omit_model":true,"effort":"high","guarded":false},"fanout":{"model":"inherit","omit_model":true,"effort":"high","guarded":false},"source":{"model":"bundled","effort":"bundled"},"basis":{"model":"judgment","fanout_model":"judgment","effort":"judgment"}},"worker":{"role":"worker","single":{"model":"inherit","omit_model":true,"effort":"medium","guarded":false},"fanout":{"model":"inherit","omit_model":true,"effort":"medium","guarded":false},"source":{"model":"bundled","effort":"bundled"},"basis":{"model":"judgment","fanout_model":"judgment","effort":"upstream"}},"verifier":{"role":"verifier","single":{"model":"inherit","omit_model":true,"effort":"high","guarded":false},"fanout":{"model":"inherit","omit_model":true,"effort":"high","guarded":false},"source":{"model":"bundled","effort":"bundled"},"basis":{"model":"judgment","fanout_model":"judgment","effort":"upstream"}},"retrieval":{"role":"retrieval","single":{"model":"sonnet","omit_model":false,"effort":"medium","guarded":false},"fanout":{"model":"sonnet","omit_model":false,"effort":"medium","guarded":false},"source":{"model":"bundled","effort":"bundled"},"basis":{"model":"judgment","fanout_model":"judgment","effort":"upstream"}}},"notes":[]}
```
