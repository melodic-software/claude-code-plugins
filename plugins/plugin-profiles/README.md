# plugin-profiles

Named sets of plugins you switch between: a profile says which installed plugins are on in a
folder, in your user settings, or for one session. The plugins stay installed; a profile only
turns them on and off.

## Profiles

Each profile is one YAML file. The shipped ones are in [`profiles/`](profiles/): `always-on`,
which is on in every other profile, and `discovery`, `planning`, `interface-design`, `build`,
`review`, `improve`, `harness-upkeep` and `native`. Each file holds the profile's members and a
`description` line saying when to pick it. `native` is Claude Code as it ships: every other plugin of these
marketplaces is off, guardrails included, and only this plugin stays on, as the way back to a
profile.

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
always_on: false                          # leave always-on out; default true
plugins: [one-plugin@a-marketplace]       # members
optional: [formatter@a-marketplace]       # on when installed
remove: [inherited@a-marketplace]         # drop a member the level below added
exclude: [unwanted@a-marketplace]         # keep off, even when the repository enables it
hide_skills: [some-standalone-skill]      # skills outside plugins, hidden by skillOverrides
```

`plugins` adds members and `remove` drops inherited ones; `optional`, `exclude` and `hide_skills`
add up across levels; `description` and `always_on` are the highest one set. A profile with
`always_on: false` is its own lists alone: it switches off every always-on plugin it does not list,
from any marketplace `always-on` names, and its preview names those plugins and any that stay on, with
why. No other profile may exclude an `always-on` member; drop one with a
`remove` line in your own `always-on.yaml`. A repository file cannot switch one off: apply ignores
such a `remove` or `exclude` line, or `always_on: false`, and its preview names it, along with what
only a repository file switches on or hides.

## Set up with the skill

`/plugin-profiles:profile` runs every action below for you and shows each change before it makes
it: `apply`, `status`, `clear`, `check`, and `setup`. `setup` walks you through your installed
plugins and their skills and this machine's usage history, asks about your work and, for each
installed plugin that ships hooks or a mod, whether it is always on or per profile, then proposes
profiles to save at user or repository level. When a profile names a plugin that is not
installed, it offers to install it and installs only on your yes at that moment.

## Start a session in a profile

Start and resume from plain `claude` through the `claude` shell function your dotfiles provide.
Claude Code itself has no `--profile` flag; the function adds it:

- `--profile build` given to the function starts a terminal in `build`.
- `claude --resume <id>` resumes in the profile the session ran in, reusing the session's file
  without checking plugin prerequisites again; `start --resume <id> --unattended` checks them
  and refuses where an unattended start would.
- `claude -c` reaches Claude Code unchanged, so it continues the same conversation it always
  would. When that conversation ran in a profile, its start notice prints the
  `claude --resume <id>` that reopens it there. The tool cannot tell which conversation
  `-c` picks, so it never guesses.
- Everything else `claude` does is unchanged.

The function runs the real `claude` untouched
unless the words start with a flag and include `-r`, `--resume` or `--profile`; then it runs `profiles.mjs start --claude-args`, which takes `--profile <name>` out of
the words, writes the one-session file and starts `claude` with it and every other word. The
function finds the plugin through `~/.claude/plugin-profiles-state/root`, which the session-start
hook of the installed plugin writes. To try a copy from a worktree, set `PLUGIN_PROFILES_ROOT` to
that copy's plugin folder.

A plain `claude --resume` without the function starts without the profile, and its start notice
prints the command that resumes it there. Without the function, run `start` directly; with no
profile named, it asks which one, by number, and `0` starts with the folder's settings:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" start build
```

`--dry-run` prints the `claude` command and starts nothing. On Windows, `start` runs the native
`claude.exe` it finds on `PATH`, never through a shell, and refuses a `claude.cmd`, which would
split or interpret your arguments. Tried on one Windows lane (PowerShell 7.7.0, plugin-profiles
0.5.0, 2026-11-18) through the dotfiles PowerShell `claude` function: `--profile build` printed
"This session runs in profile build." and its resume line.

What each situation does to the profile, and how to get back to the state before any profile, is
in [`reference/scenarios.md`](reference/scenarios.md).

## Apply a profile

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" apply build --for folder --dry-run
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" apply build --for folder
```

`--for` picks where the entries go:

- `folder`: the repository's `.claude/settings.local.json`, at the main checkout's root, which Claude Code reads for every worktree and subdirectory of the repository. On Windows, outside git, or where the repository root is your home folder or not yours, it is the folder's own file. To give one terminal its own profile, start it in a one-session profile.
- `initial`: your user `settings.json`, the profile new folders start from.
- `session`: a generated file for `claude --settings <file>`, for one session; no settings file
  changes. The file also sets `PLUGIN_PROFILES_SESSION` to the profile's name, and
  `SESSION_SETTINGS_FILE` to its own path, so plugin-diagnostics and harness-ops skip the
  prerequisite notices of plugins the profile turns off. A resumed session
  does not keep `--settings`, so resume it with `claude --resume <id>`. The file names every plugin and
  every skill a profile can switch, so a folder switch in another terminal never reaches it.

Where two levels set the same plugin, Claude Code's
[settings precedence](https://code.claude.com/docs/en/settings#settings-precedence) decides:
managed settings, then the one-session file, then the folder, then the repository's committed
`.claude/settings.json`, then your user settings.

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

`/plugin-profile` switches this folder's profile without a model turn: it opens a pane with a row
for every profile and **No profile** (where no pane can be placed, the question dialog a page at a
time), or takes one by name, `/plugin-profile review`. A row's whole description shows under the
pointer, and the focused row's under the list. The pick then shows the same preview as
`apply --dry-run`, one line per row, and asks before writing. When the switch would turn on a plugin that ships an MCP or language server, the
question names it and says your next message re-reads the whole conversation.

On Apply it writes the entries that switch plugins on and runs `/reload-plugins` once, when the
next turn ends: send any message, or run `/reload-plugins` yourself. Then it writes the entries that
switch plugins off: those plugins stay loaded in this session until a later `/reload-plugins` or
the next session start. A switch cut off between the two writes is named by `status` and finished
by the next apply.

**No profile**, the picker's last choice, clears the folder's profile (as `clear` below does)
behind the same preview and confirm, and reloads the same way, so the session then has the plugins
your user and project settings name.

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
`claude`; in a folder with no applied profile it prints nothing, unless the session was resumed
without the profile it ran in. The hook also records, under the plugin's data folder, the profile
each one-session start runs in, for `start --resume`; the next `start` or `launch` removes a record no session start has written
for 30 days. `clear` puts every entry back to what it was before the first apply and
removes a settings file the tool created; like `apply`, it prints what it changes and writes on
`--yes` or a yes at the prompt. The record of what apply wrote lives in the repository's `.git`
folder (`.git/plugin-profiles/`, never committed) for a folder in git, in
`~/.claude/plugin-profiles-state/` for user settings, and otherwise in the plugin's data folder;
`status` and `clear` also find a record in the data folder, including one another copy of the
plugin wrote, such as a `--plugin-dir` copy's. With no record, `clear` changes nothing and says
how many entries the file holds. A profile an earlier version applied to a worktree's or
subdirectory's own `.claude/settings.local.json` is named by `status` as partly in force;
`clear --for worktree` puts that file back.

### Reset everything

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" reset --dry-run
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" reset
```

`reset` clears every settings file on the machine that holds a record: each folder's, each
worktree's or subdirectory's own file, and user settings for the initial profile. One preview
names each file, what it goes back to, and each entry edited since the apply that it would
overwrite; one yes, typed or `--yes`, restores them, and reset prints one line per file. That yes
covers only the files a profile record covers, a worktree copy adopted from its root file's record
included; a no keeps those files, and reset still asks each file that has its own question
(`--keep-recorded` passes that no for a caller that asked already). A folder whose
`.claude/settings.local.json` holds plugin or
skill entries but no record is listed with those entries, which may be the person's own; they go
only after a yes for that folder. In a terminal reset asks each such folder, `--yes` or not, and
the default is no; a no to every question writes nothing and exits 1; `--remove-unrecorded <file>` and `--keep-unrecorded <file>` answer for a caller
that asked already; with nobody at a terminal, `--yes` alone leaves each such folder as it is,
and with neither a terminal nor `--yes` reset writes nothing and exits 1, as it does for recorded
files.
A file reset put back is not listed that way again while it holds the bytes reset left: reset notes
their hash beside where that file's record is saved, and the preview names such files in one
line, the first three and how many more. An edit to the file, or an apply, ends that, and a record always wins over the note.
Inside a session, `/plugin-profile` and **Reset** do the same and reload the session; the profile
skill's reset action previews and asks the same way. Both pass the preview's `previewId` with
`--preview-id`, and the write refuses, writing nothing, when what it would write no longer matches
that preview. Reset exits 0 when every file is done, 3 when it skipped some and named each, and 1
when it wrote nothing.

Every question lists the answer that changes nothing first, so the picker pre-selects it (Cancel,
Keep) and Esc is that answer; the terminal's `[y/N]` takes anything but `y` or `yes` as no. Each
question also comes with a recommendation from `reset --dry-run --json`: `ask.recommend` per file
and `questionRecommend` for the one question, each an answer and a one-sentence reason. A folder
without a record is recommended Keep, since reset did not write its entries; a cut-off file or a
moved repository's older record is recommended a yes only while no entry the profile wrote was
changed by hand to another value; the one question is recommended a yes for a person who asked
for a reset, since applying a profile again undoes it. The picker shows that advice as a line
before each question, and the skill marks that answer `(Recommended)` with the reason.

Reset finds a repository through a pointer file under `~/.claude/plugin-profiles-state/repositories/`,
written at each apply there and each session start there, and through the folders Claude Code has
opened, the one-session records, the live sessions and the folder it runs in. It cannot find a
repository with no pointer whose every known path is gone, such as a removed worktree or a
submodule known only from its superproject, until a session starts there; an apply run from a
plain terminal in a folder Claude Code never opened; or another config folder or lane. A record
whose folder is gone is kept, never deleted; when it was a repository root's and the repository
moved, the preview names the root file where it is now, which reset puts back only after a yes for
it, asked as its own question with Keep first (`--put-back-moved <file>`, `--keep-moved <file>`). A record reset finds in a home that cannot hold it, such as a repository's `.git` naming user
settings, is listed as ignored and never written from. Reset never writes a
committed `.claude/settings.json`. Each file is replaced whole, so a reset stopped part way
leaves each file restored or untouched and the next reset finishes the rest; that holds for a
process stopped part way, not for a power loss. When a file was changed by hand after such a stop,
reset cannot tell whether the stopped reset wrote it: it keeps the record and asks a yes for that
file, default no (`--finish-cut-off <file>`, `--keep-cut-off <file>`); the yes puts back only the
entries still at the profile's values and leaves every entry changed by hand. A file with no entry
left at the profile's value is left as it is and its record removed. One reset writes each file
from one record only. When a profile was applied at a moved repository's new place, reset first
puts back that newest record, to the values from before that profile was applied, and keeps the
older one waiting, saying so; it exits 3 and says to run reset again, and the next run offers the
file from the older record. A repository moved more than
once goes back the same way, one layer per run, newest first, until the file holds what it held
before the first apply; a no at any layer leaves the file and every record. A one-session file names each installed plugin of
every marketplace a profile governs, so a reset elsewhere never changes a running terminal's
plugins; a later `/plugin` toggle of such a plugin reaches only sessions started after it.

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
its own form with every list in alphabetical order (comments are not kept), and refuses a profile that would exclude an `always-on`
member without `always_on: false`. It keeps the file's `always_on` line.

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
excludes an `always-on` member without `always_on: false`, or when `interface-design` lacks a `planning` member. For your
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
