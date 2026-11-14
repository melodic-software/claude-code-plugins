---
bump: minor
---

### Added

- **Discovery agent models are configurable.** With the `multi-agent` plugin enabled, a model a `multi-agent` config layer sets for an agent's role now replaces that agent's pin on the spawn: `retrieval` for `explorer`, `worker` for `researcher` and `intent-tracer`, `verifier` for `research-verifier`. Set it on the `research` workload to move these agents and the `research-sweep` stages without moving other plugins' agents in that role. With no such layer, or without `multi-agent`, each agent keeps its pinned model. How to set it: the README's "Agent models".
