---
bump: patch
---

### Changed

- `/review:security-review` reports an added or changed `userConfig` selector key as one advisory
  summary line, `manifest userConfig.<key>: pass, advisory, ...`, with no inline comment, no
  severity line and no count in the findings total, so it opens no review thread
  ([#12646](https://github.com/melodic-software/claude-code-plugins/issues/12646)). A selector is a
  `boolean`, or a `string` with an `options` list, that is not `sensitive`, lists no command, path
  or URL, and whose value only picks among those values. A key whose value reaches a hook, an MCP,
  LSP or monitor server, a channel, a path, a URL or an unquoted shell string stays a
  `manifest <field>: flag`, and the guard-default rule still runs first. View `medium` keys
  resolved by `lib/view-settings.mjs` are selectors while `lib/view-settings.test.mjs` pins its
  trust rules. Two eval cases cover an advisory layout key and a key substituted into a hook
  command.
