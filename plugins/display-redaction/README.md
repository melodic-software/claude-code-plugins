# display-redaction

A Claude Code mod that masks email addresses and secret-shaped text in what Claude Code draws, so a
recording or screen share does not show them. Each match draws as `[hidden]`.

**It masks the screen only.** The model, the transcript stored on disk and anything you copy out
keep the real text. This is not a privacy, DLP or data control, and its patterns can miss a secret.
Check a recording before you share it.

## Requirements

Claude Code 2.1.287 or later (mods).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install display-redaction@melodic-software
```

The marketplace lists the plugin as off by default; enable it after installing.

## What is masked

- Email addresses, including one still streaming at the end of the text.
- `sk-` keys, `ghp_` and `github_pat_` tokens, `xox*` Slack tokens, `AKIA` AWS key IDs, and JWTs
  (`eyJ...`).
- PEM private-key blocks, including one that has no end line yet.
- Your own patterns from the `extra_patterns` option, one regular expression per entry. A pattern
  that is over 200 characters, can match empty text, nests a quantifier inside a quantified group,
  or does not compile is skipped, and a log line at session start counts the skipped entries.

Not masked on purpose: an address whose local part is exactly `noreply`, a GitHub
`<digits>+<name>@users.noreply.github.com` address, and `git@<host>:` remotes.

## Where it applies

Claude's replies, your prompts, tool calls and their output (including failed calls), command
output, question prompts and info notices. Claude Code's own formatting is kept, because the text is
swapped before Claude Code draws it.

## What it does not mask

A mod cannot reach, or this one does not hook:

- the permission dialog
- thinking blocks
- multi-part or summarized teammate messages
- the prompt input box
- the slash-command echo
- toasts, the status line, notifications, spinners and hints
- ToolGroup summary lines
- other plugins' rows and panes
- the stored transcript and what the model reads

## Limits

- A masked value can break a tool-output row whose schema needs an exact value, such as an enum or
  a match inside base64 image or PDF data. That row draws nothing; it does not leak.
- Masked question texts and option labels are numbered so they stay distinct, so an answer may not
  line up beside its question.
- A `+` or `-` diff marker directly before an email is masked with it.
- If the mod itself fails in a way nobody foresaw, the original text can draw. Check a recording
  before you share it.

## Fail-closed behavior

Masking is on whenever the plugin is enabled. If a masking hook fails, the row draws masked text,
not the original.

## Commands

- `/display-redaction off` shows the real text for the current session.
- `/display-redaction on` masks again.

Both work mid-reply. Masking returns on at the next session. After `/resume` or `/branch` the
command may need to be run again only if it has disappeared; masking stays on.

There is no hover reveal.

## Tested in

The plugin test kit (terminal and desktop surfaces) on Claude Code 2.1.296, plus `validate` and
`tsc`. No live session yet.

## Options

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `extra_patterns` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_EXTRA_PATTERNS` | Regular expressions to mask in addition to the built-in email and secret shapes, one per list entry. A pattern that is invalid, over 200 characters, can match nothing, or nests a quantifier inside a quantified group is skipped. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure display-redaction@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install display-redaction@<marketplace> -s <scope> --config extra_patterns=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "display-redaction@<marketplace>": {
         "options": {
           "extra_patterns": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
