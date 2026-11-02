---
bump: patch
---

### Fixed

- The `default-judge-same-model` case no longer grades the CLI's default judge by name, a volatile upstream default the plugin-eval skill points at rather than restates. It passes an answer that says the judge resolves from `--judge-model`, not `--model`, and either names the default or says where to read it. The case allows only `Read` and `Skill`, so a run no longer searches the plugin root, which the eval sandbox denies.
- The `pe-ci-pin-full-ids` `reads-json` grader passes "Check `partial`, each run's `error`, and the `delta` field in the JSON": its window between the verb and `JSON` grows from 60 to 90 characters.
- The `pe-rules-target` `claude-md-absent` grader accepts "removed" beside its other words for an absent `CLAUDE.md`.
