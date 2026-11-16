# plugin-profiles

Named sets of plugins you switch between: a profile says which installed plugins are on in a
folder, in your user settings, or for one session. The plugins stay installed; a profile only
turns them on and off.

## Profiles

Each profile is one YAML file. The shipped ones are in [`profiles/`](profiles/): `always-on`,
which is on in every profile, and `discovery`, `planning`, `interface-design`, `build`, `review` and
`harness-upkeep`. Each file holds the profile's members and a `description` line saying when to
pick it.

You can add or extend profiles at two more levels. A file with the same name at a higher level
extends the one below it:

| Level | Folder |
| --- | --- |
| Shipped | `profiles/` in this plugin |
| User | `~/.claude/plugin-profiles/` |
| Repository | `docs/conventions/plugin-profiles/` |

A profile file takes these keys. Every plugin is written `name@marketplace`.

```yaml
description: One line saying what the profile is for.
plugins: [one-plugin@a-marketplace]       # members
optional: [formatter@a-marketplace]       # on when installed
remove: [inherited@a-marketplace]         # drop a member the level below added
exclude: [unwanted@a-marketplace]         # keep off, even when the repository enables it
hide_skills: [some-standalone-skill]      # skills outside plugins, hidden by skillOverrides
```

`plugins` adds members and `remove` drops inherited ones; `optional`, `exclude` and `hide_skills`
add up across levels. No profile may exclude an `always-on` member; drop one with a `remove` line in
your own `always-on.yaml`.

## Apply a profile

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" apply build --for folder --dry-run
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" apply build --for folder
```

`--for` picks where the entries go:

- `folder`: this folder's `.claude/settings.local.json`.
- `initial`: your user `settings.json`, the profile new folders start from.
- `session`: a generated file for `claude --settings <file>`, for one session; no settings file
  changes.

Before writing, apply prints the plugins it switches on and off, the ones a higher level pins
(managed settings, or the folder when you set the initial profile), the ones that are not installed
with their install command, and the plugins of marketplaces the profile does not name, which it
leaves alone. It also names each plugin it switches off that ships hooks or a mod. It writes after
you answer yes, or with `--yes` when nobody is there to ask; with neither it writes nothing.

When a plugin it would switch on lacks a tool its `prerequisites.json` marks required, the preview
names the tool, its install line and what stops working. Only a yes typed at the prompt applies the
profile anyway; `--yes` alone does not.

Apply writes only the `enabledPlugins` and `skillOverrides` entries, never your repository's
committed `.claude/settings.json`. Plugins the repository enables there stay on unless the profile
excludes them, and a plugin the repository sets to `false` stays off. Apply installs nothing.

## Status and clear

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" status
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" clear
```

`status` names the profile recorded for the folder, each entry that differs from it and each
plugin installed since. `clear` puts every entry back to what it was before the first apply and
removes a settings file the tool created. The record lives in the plugin's data folder.

`inventory` lists the installed plugins, what they depend on and what each ships.

## Check the profiles

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" check --catalog <marketplace.json>
```

`check` fails, exiting 1, when a shipped profile names a plugin the catalog lacks, writes an id
under another marketplace than the catalog's own name (it names the fix), has no description line,
excludes an `always-on` member, or when `interface-design` lacks a `planning` member. For your
user and repository profiles it reports, without failing, a plugin of the catalog's marketplace
that the catalog lacks and a plugin of another marketplace that is not installed, and it reports installed plugins that no profile names, which an apply switches off.
`--catalog` defaults to the `marketplace.json` of the repository the plugin sits in. In this
repository, CI runs it through `scripts/check-plugin-profiles.sh`.
