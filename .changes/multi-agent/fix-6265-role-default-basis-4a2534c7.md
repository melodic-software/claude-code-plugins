---
bump: minor
---

### Changed

- Every role default in `reference/defaults.yaml` now records a basis per value: `upstream`, naming the section and statement that set it (`pointer_<field>`, `claim_<field>`), or `judgment` with a `reason_<field>`. No model or effort value changed. Upstream: worker and verifier effort (model-config, choose an effort level), the worker's `mechanical` workload model (costs, choose the right model; recorded as `basis_mechanical_model`, the form every `workloads.<w>.<field>` value uses). Judgment: orchestrator model and effort, worker and verifier model, retrieval model and effort. The generic `pointer`, `pointer_cost` and `pointer_model_split` on the roles are gone; `pointer_skill` and `pointer_spawn` stay as mechanism pointers. (#6265)
- `/multi-agent:route` prints a `basis` (`upstream`, `judgment`, `config` or `unrecorded`) beside each role's model, fan-out model and effort; a guarded fan-out model takes the fan-out guard's basis.
- `/multi-agent:audit-defaults` reports `unsupported` when a cited section states neither the value nor a rule it follows from, proposing `basis_<field>: judgment` in the diff when the owner records an upstream basis for it, and lists judgment values with their reasons instead of checking them.
