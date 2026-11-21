<!-- GENERATED from docs/contracts/config-cascade/locations.md by scripts/sync-shared-copies.sh. Do not edit this copy:
edit the canonical source, then rerun the script. -->

# Where plugin config lives

The one editable list of config file locations for this marketplace's plugins. Each plugin that
teaches a location carries a generated copy at `reference/config-locations.md`; edit
`docs/contracts/config-cascade/locations.md` in claude-code-plugins, never a copy. The [config-cascade contract](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md)
owns the rules; this page points at them.

## The four layers

Lowest first, a higher layer refining a lower one key by key
([The layers](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md#the-layers)):

1. **Plugin default**: bundled in the plugin.
2. **`userConfig`**: the plugin's option in Claude Code user or managed settings, per person,
   across repositories.
3. **Team**: `<home>/<concern>.yaml` for keyed values, `<home>/<concern>.md` for prose, tracked
   ([Location of the team layer](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md#location-of-the-team-layer-a-docs-convention-file-or-claudename)).
4. **Personal override**: `<home>/<concern>.local.<ext>`, gitignored by one
   `<home>/**/*.local.*` line
   ([Personal override naming](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md#personal-override-naming-and-the-consumer-gitignore)).

`<home>` is the repository's convention home, bound by the pointer region in `AGENTS.md` or
`CLAUDE.md`, default `docs/conventions`
([Expression doctrine](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md#expression-doctrine-which-surfaces-are-files-and-which-are-convention-docs)).
`<concern>` is the plugin's name, or a cross-plugin convention's name.

## Not a plugin config location

- **No user-global file.** A per-person value goes in `userConfig`, never `~/.claude/<name>`.
- **No new `.claude/` file for plugin config.** Write new team and personal files at `<home>`.
- **Claude Code's own files are outside this contract**: `~/.claude/settings.json`,
  `.claude/settings.json`, `.claude/settings.local.json`, `CLAUDE.md`, `CLAUDE.local.md`.
- **Machine-scope plugin state** under `~/.claude/` is outside it too
  ([Scope](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md#expression-doctrine-which-surfaces-are-files-and-which-are-convention-docs)).

## A plugin that still reads an old path

Some plugins still read `~/.claude/<name>` or `.claude/<name>.local.<ext>`. Those reads keep
working until each plugin migrates in its own change; they are not locations to copy.

A tracked `.claude/<name>` team file is still a supported team-layer location, read only when no
`<home>` file supplies the layer
([Location of the team layer](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md#location-of-the-team-layer-a-docs-convention-file-or-claudename)).

A plugin's own docs name what it reads today; the contract's
[Implementers](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md#implementers)
table and [Deviations](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md#deviations)
section list each one.
