---
bump: patch
---

### Changed

- `/review:security-review` treats an added or changed `number` or `boolean` `userConfig` key that is not `sensitive` and whose only reader is skill or agent body text as inert, per the owner's decision: it gets one summary line, `manifest userConfig.<key>: pass, inert, <file:line>`, with no inline comment, no severity line and no count in the findings total. A key whose value reaches a hook, a server, a script or other code, as `${user_config.<key>}` or as `CLAUDE_PLUGIN_OPTION_<KEY>`, still flags, and the guard-default rule still runs first.
