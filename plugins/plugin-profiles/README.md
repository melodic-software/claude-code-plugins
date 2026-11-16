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

## Set up with the skill

`/plugin-profiles:profile` runs every action below for you and shows each change before it makes
it: `apply`, `status`, `clear`, `check`, and `setup`. `setup` walks you through your installed
plugins and their skills and this machine's usage history, asks about your work and, for each
installed plugin that ships hooks or a mod, whether it is always on or per profile, then proposes
profiles to save at user or repository level. When a profile names a plugin that is not
installed, it offers to install it and installs only on your yes at that moment.

## Apply a profile

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" apply build --for folder --dry-run
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" apply build --for folder
```

`--for` picks where the entries go:

- `folder`: this folder's `.claude/settings.local.json`.
- `initial`: your user `settings.json`, the profile new folders start from.
- `session`: a generated file for `claude --settings <file>`, for one session; no settings file
  changes. The file also sets `PLUGIN_PROFILES_SESSION` to the profile's name. A resumed session
  does not keep `--settings`, so pass it again with `--resume`.

Where you run it matters. The CLI and `claude -p` take all three targets. VS Code and Claude
Desktop take `folder` and `initial`; a one-session apply there is refused with the folder level
offered instead. A cloud session reads no local or user settings, so there profiles do not apply
and nothing is written. Inside Claude Code on a surface the tool does not recognize, status reads
"surface not detected" and only `folder` applies.

To have every session start from the initial profile instead of the folder's, set the
`remember_folder_profile` option to false. A folder apply is then refused, and status names a
folder profile left from before as not in force, with `clear` to remove it.

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

`list` names the profiles a folder apply can use, each with its description line.

## Switch in a running session

`/plugin-profile` switches this folder's profile without a model turn: it lists the profiles (or
takes one by name, `/plugin-profile review`), shows the same preview as `apply --dry-run`, and asks
before writing. When the switch would turn on a plugin that ships an MCP or language server, the
question names it and says your next message re-reads the whole conversation.

On Apply it writes the entries that switch plugins on and runs `/reload-plugins` once, when the
next turn ends (or when you run `/reload-plugins` yourself first). Then it writes the entries that
switch plugins off: those plugins stay loaded for this session and go at the next session start. A
switch cut off between the two writes is named by `status` and finished by the next apply.

It refuses the switch when `remember_folder_profile` is false or the session was started from a
one-session file, and says how to start a session in that profile instead. A plugin it would switch
on that lacks a required prerequisite is left to `apply` in a terminal.

The command is a mod and needs Claude Code 2.1.287 or later (tested on 2.1.325, interactive CLI
sessions); `apply` works without it.

## Status and clear

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" status
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" clear
```

`status` names the profile recorded for the folder, each entry that differs from it, each
plugin installed since, a one-session profile the session runs in, and the surface. At session
start a hook prints the same notice, reading the installed plugins from disk without starting
`claude`; in a folder with no applied profile it prints nothing. `clear` puts every entry back to what it was before the first apply and
removes a settings file the tool created; like `apply`, it prints what it changes and writes on
`--yes` or a yes at the prompt. The record lives in the plugin's data folder.

`inventory` lists the installed plugins, what they depend on, what each ships and its skills.
`usage` lists how often each skill and plugin was used on this machine, most used first, from the
counts Claude Code keeps, or says that no usage history was found.

## Save a profile and install a missing plugin

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" save docs --level user --plugins a@market,b@market --dry-run
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" install b@market --dry-run
```

`save <name> --level user|repository` writes a profile file: the lists you give (`--plugins`,
`--optional`, `--remove`, `--exclude`, `--hide-skills`, comma-separated) are added to the file's
own, and `--description` replaces its description. It prints the whole file first, writes it in
its own form (comments are not kept), and refuses a profile that would exclude an `always-on`
member.

`install <name@marketplace>` installs one missing plugin at user scope. It installs only from a
marketplace this machine already knows, never for a plugin that only a repository profile names,
and never updates or uninstalls. After the install it switches the plugin off in your user
settings unless the initial profile (`always-on` plus the profile applied `--for initial`)
includes it; applying a profile that names it switches it on there.

Both print what they do first and write on `--yes` or a yes typed at the prompt; with neither,
they write nothing.

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

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `remember_folder_profile` | boolean | `true` | When on, a profile applied to a folder holds for every later session there. When off, every session starts from the initial profile: a folder apply is refused, and the session-start notice names a folder profile left from before as not in force. Read from managed settings first, then user settings. |

### How to set these

Set the options above for `plugin-profiles@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->
