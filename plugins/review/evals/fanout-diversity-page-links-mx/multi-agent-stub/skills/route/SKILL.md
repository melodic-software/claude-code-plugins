---
description: "Model and effort per agent role (orchestrator, worker, verifier, retrieval) for a multi-agent run, resolved through the bundled defaults and the user, team and personal override config layers into fenced JSON with single-agent and fan-out variants and the layer behind each value; fan-out stays off frontier models unless config opts in. Use when asked 'which model for the subagents', 'route the roles', 'what effort should the workers use', 'roles for the workflow args', 'model routing' or 'is fan-out on Fable', or before a skill launches a workflow that takes args.roles."
argument-hint: "<role|all> [workload] [session=<alias>]"
user-invocable: true
disable-model-invocation: false
---

# Route (eval stand-in)

No config layer exists in this sandbox, so the bundled defaults decide every value.

## Arguments

- `<role|all>`: `orchestrator`, `worker`, `verifier`, `retrieval`, or `all`.
- `session=<alias>`: the session model's alias. When the caller passed none, take the family name
  in your own model ID (`opus`, `sonnet`, `haiku`, `fable`). When you cannot tell, treat the
  session as `fable`.

## Output

Print the JSON below for the session's alias, in one fenced `json` block, with `session_model` set
to that alias; for one role, keep only that role under `roles`. A caller launching a workflow
passes the `roles` object as `args.roles`, unchanged.

`opus`, `sonnet` or `haiku` session:

```json
{"session_model":"<alias>","session_frontier":false,"workload":null,"roles":{"orchestrator":{"role":"orchestrator","single":{"model":"inherit","omit_model":true,"effort":"high","guarded":false},"fanout":{"model":"inherit","omit_model":true,"effort":"high","guarded":false}},"worker":{"role":"worker","single":{"model":"inherit","omit_model":true,"effort":"medium","guarded":false},"fanout":{"model":"inherit","omit_model":true,"effort":"medium","guarded":false}},"verifier":{"role":"verifier","single":{"model":"inherit","omit_model":true,"effort":"high","guarded":false},"fanout":{"model":"inherit","omit_model":true,"effort":"high","guarded":false}},"retrieval":{"role":"retrieval","single":{"model":"sonnet","omit_model":false,"effort":"medium","guarded":false},"fanout":{"model":"sonnet","omit_model":false,"effort":"medium","guarded":false}}},"notes":[]}
```

`fable` session:

```json
{"session_model":"fable","session_frontier":true,"workload":null,"roles":{"orchestrator":{"role":"orchestrator","single":{"model":"inherit","omit_model":true,"effort":"high","guarded":false},"fanout":{"model":"opus","omit_model":false,"effort":"high","guarded":true}},"worker":{"role":"worker","single":{"model":"inherit","omit_model":true,"effort":"medium","guarded":false},"fanout":{"model":"opus","omit_model":false,"effort":"medium","guarded":true}},"verifier":{"role":"verifier","single":{"model":"inherit","omit_model":true,"effort":"high","guarded":false},"fanout":{"model":"opus","omit_model":false,"effort":"high","guarded":true}},"retrieval":{"role":"retrieval","single":{"model":"sonnet","omit_model":false,"effort":"medium","guarded":false},"fanout":{"model":"sonnet","omit_model":false,"effort":"medium","guarded":false}}},"notes":[]}
```
