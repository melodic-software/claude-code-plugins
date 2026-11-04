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
  LSP or monitor server, a channel, a path, a URL or an unquoted shell string, or whose value
  turns on sending repository or session content off the machine, stays a
  `manifest <field>: flag`, and the guard-default rule still runs first. The one exception is a
  view `medium` key whose value the diff or repository shows passed to a plugin's
  `lib/view-settings.mjs` resolver, whose trust rules `lib/view-settings.test.mjs` pins; a
  `medium` key read any other way, with a publishing value, still flags. Five eval cases cover an
  advisory layout key, a key substituted into a hook command, a share switch that uploads a
  session summary, and a publishing `medium` key read through the resolver and read directly.
