---
bump: patch
---

### Security

- collect-base-activity makes the base marketplace copy read-only (`chmod -R a-w`) once it is staged, and a write skill's `--disallowedTools` carries `Edit(/$RUNNER_TEMP/base-marketplace/**)`, so neither the skill's file tools nor a process it starts can rewrite the plugin hooks and scripts that load in place from that copy ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).
