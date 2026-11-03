---
bump: patch
---

### Fixed

- `/review:fanout` in run-everything mode omits `args.roles` when the reviewed change set touches a `multi-agent.yaml` file, the multi-agent team layer, so the change under review cannot choose the models that review it. It checked only the old team files, `docs/conventions/multi-agent.md` and `.claude/multi-agent.yaml`, which the multi-agent resolver no longer reads ([#9737](https://github.com/melodic-software/claude-code-plugins/issues/9737)).
