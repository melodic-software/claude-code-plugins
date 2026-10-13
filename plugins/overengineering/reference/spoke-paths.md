# Spoke paths

The `context/` files of this plugin's skills write the plugin's root directory as `<plugin-root>`,
never as a `${CLAUDE_PLUGIN_ROOT}` token. The skill reading them puts the plugin root in place of
the placeholder before it runs a command or writes the path into a brief, so no command depends
on a `${…}` token being expanded in a file loaded through the Read tool or in the Bash tool's
environment.

- **Pointer**: when deciding whether a `${…}` token in a skill's supporting file would resolve,
  fetch
  [plugins reference § Where each variable resolves](https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves)
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: that section starts listing a skill's supporting files, or the Bash tool's
  environment, as a place where `${CLAUDE_PLUGIN_ROOT}` resolves.
