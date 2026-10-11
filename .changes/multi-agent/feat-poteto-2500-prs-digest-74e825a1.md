---
bump: minor
---

### Added

- **`/multi-agent:assess` names the run's shape.** A `workflow` or `subagent` verdict gains a third line, `shape: <sections|race (<selection rule>)|mixed>`. A race states its selection rule before any agent is spawned; one without a rule is reported, not run.
- **`/multi-agent:route` notes the effort cap.** The output ends with a line pointing at the new "Hard cap" section of `reference/config.md`, which documents `maxEffortLevel` and where role effort applies (workflow `agent()` calls, not Agent tool dispatches).

### Changed

- **The `mechanical` workload runs the worker on `sonnet` by default** (`roles.worker.workloads.mechanical.model: sonnet`); `code` and `research` keep the role's model. Opt out with `roles.worker.workloads.mechanical.model: inherit` in any layer.
- **`scripts/yaml-subset.awk` is now a generated copy of the repository's `lib/yaml-subset.awk`.** The parser also reads block and flow sequences, flow mappings, quoted keys, YAML quote escapes (`''`, `\"`, `\\`) and a document at a uniform base indent, so the shared concern reader can use it. Valid YAML inside the subset reads the same as before, except that an escape inside quotes now yields the character it stands for. Four non-standard forms the old parser read now make the layer a parse error, so it is skipped and named: a key indented between its parent and the block it closes (`planner:` at two spaces after `worker:` at four, both under `roles:`), text after a closing quote (`a: "x"y"`), an unclosed quote (`a: "x`), and a tag (`a: !true`). A sequence, which used to be an error, now flattens to indexed keys (`a.0`) that the resolver reports as unknown.

### Fixed

- **The shared `yaml-subset.awk` refuses a tab indent and an unquoted colon followed by a space in a value (`key: a: b`).** Both parsed before although a YAML loader rejects them; a file holding either now reads as a parse error, so quote a value that holds a colon followed by a space. A tab in a markdown fence's base indent is still accepted.
