# Plugin names and option text

Owner doc for how this marketplace's plugins appear in Claude Code's UI: the plugin name shown in
`/plugin`, and each `userConfig` option's key, `title`, `description`, and `type`. One home per the
convention registry ([`docs/plugin-philosophy.md`](../../plugin-philosophy.md) "Convention
registry"). Whether a value belongs in `userConfig` at all, and its `default`, `required`, and
`sensitive` fields, stay with [`docs/plugin-philosophy.md`](../../plugin-philosophy.md)
"Configuration and state".

## Where the text appears

**Record.** Claim: `title` is "Label shown in the configuration dialog" and `description` is "Help
text shown beneath the field"; every option except `sensitive` options and `multiple` lists also
appears as a row in `/config`; `options` turns a `string` field into a picker in `/config` and needs
v2.1.271 or later; the docs' examples use sentence-case titles ("API token", "Bot token") and
snake_case keys; `displayName` is "Name shown in UI in place of `name`". Basis:
<https://code.claude.com/docs/en/plugins/manifest-reference> "User configuration" and "displayName". As of:
2026-10-07. Recheck: that section adds a casing or length rule, changes which options reach
`/config`, or changes the `options` version floor.

**Record.** Claim: in Claude Code 2.1.287 the `/config` row reads `<title> · <name>`, using the
plugin's kebab `name` and never `displayName`; a `boolean` row toggles in place and never shows its
description; any other type opens a dialog whose subtitle is the full description; rows keep the
manifest's key order. Basis: the 2.1.287 native binary's embedded settings code, read 2026-10-02.
As of: 2026-10-02. Recheck: a Claude Code release changes the `/config` plugin rows.

**Record.** Claim: none of the 40 Anthropic-authored plugins in `claude-plugins-official` sets
`displayName`; the 14 entries that do are third-party vendor brands ("New Relic", "HubSpot Sales").
The one Anthropic plugin with options (`code-modernization`) uses sentence-case titles, noun-phrase
titles for booleans ("X-ray reads", "Usage counts"), and `options` pickers. Basis: the
`claude-plugins-official` marketplace manifest and plugin manifests, read 2026-10-02. As of:
2026-10-02. Recheck: Anthropic's own plugins start setting `displayName`.

The official docs set no casing, length, or wording rule, so every rule below is this repository's
house rule, chosen to match what Anthropic's own plugins and examples do.

## Plugin names

- No plugin sets `displayName`, in `plugin.json` or in its marketplace entry. Every surface then
  shows the same kebab-case `name` that `/config`, slash commands, and namespacing already use.

## Option keys

- snake_case, as the official examples are.
- Never rename a shipped key: stored values are keyed by it, so a rename silently drops every
  user's setting. Fix the `title` instead.

## Titles

- **Sentence case.** Capitalize the first word, including a leading tool or hook name
  ("Bash-format hook", "Lane-stop gate"), and nothing else except proper nouns and acronyms
  (API, CI, ID, PR, URL, USD, GitHub). Never all caps.
- **No plugin name.** The row already ends `· <plugin>`. A sub-feature word stays only when the
  title is ambiguous inside the plugin without it, written as plain leading words with no colon
  ("Babysit merge method", not "Babysit: merge method").
- **Booleans are noun phrases** naming what is on or off ("Bash-format hook", "Usage counts").
  No "enable", "enabled", "toggle", "kill switch", or "master". The description is hidden in
  `/config`, so the phrase alone must say what turns on.
- **Units in parentheses** at the end: "(seconds)", "(days)", "(bytes)", "(percent)", "(USD)".
- **About 40 characters or fewer.** Detail belongs in the description.
- **One key, one title.** A key shared by several plugins carries the same title in each:

| Key | Title |
|---|---|
| `<hook>_enabled` for a hook named differently from its plugin | `<Hook-name> hook` |
| `<plugin>_enabled` for an edit hook named after its plugin | What it does on edit: Format on edit, Format and lint on edit, Lint on edit, Spell-check on edit, Normalize line endings on edit |
| `<guard>_enabled` for a guardrails guard | `<Guard-name> guard` |
| `*_lint_gitignored` | Act on files git ignores |
| `stdin_read_timeout` | Hook stdin read timeout (seconds) |
| `lane_instance` | Lane instance ID |
| `output_dir` | Output directory |

## Descriptions

- **300 characters or fewer.** The dialog prints the whole description as its subtitle. When an
  option needs more, the first 300 characters say what it controls and what the default does, and
  the rest moves to the plugin README's `### Option details` subsection, placed just before the
  generated options block. Nothing is dropped.
- First sentence says what the option controls. A picker's description names what each value
  does, leading with the value ("auto follows …; off never …").
- Plain text: the dialog renders no markdown, so no backticks, asterisks, or links. No em dash.

## Types

- A value that is a number is `type: number`, with `min` and `max` where bounds exist.
- A `string` that accepts a fixed set of values declares that set in `options` (each 1 to 64
  characters, `default` one of them). A set that includes "unset" names it as a value (`auto`,
  `off`), since an empty string cannot be an option.
- A path is `directory` or `file`. Claude Code does not check the path exists; the plugin does.

## Order

Keys appear in `/config` in manifest order. Put a plugin-wide on/off option first, then group
options by the feature they configure.

## Gate

`scripts/validate-plugin-contracts.mjs` fails a `displayName`, and warns on a title that is not
sentence case, opens with the plugin name, uses a banned boolean word, or differs from another
plugin's title for the same key, and on a description over 300 characters or containing markdown
or an em dash. Sentence case is judged word by word: a title must start with a capital or digit,
no word may be six or more capital letters, and a later word may be capitalized only when it is an
acronym, carries an inner capital (GitHub), or is on the gate's short proper-noun list.
