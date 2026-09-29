# Claude Code documentation: settings reference

Excerpt of a real upstream page, kept for the attribution golden set. The passages below are copied
unchanged from the pages named next, and nothing else from them is reproduced.

Canonical location for the purposes of this case: `https://code.claude.com/docs/en/settings-reference`.

## `skillListingBudgetFraction`

Each turn, Claude sees a [listing of your skills](/docs/en/skills#skill-descriptions-are-cut-short) with their descriptions, and Claude Code caps that listing at a share of the context window. When the listing is over the cap, Claude Code keeps every skill's name but drops the descriptions of the least-used skills, so Claude can still invoke those skills but is less likely to choose one on its own. Raise this key to keep more descriptions visible at the cost of more context per turn.

* **Scope**: [`Any file`](#scopes)
* **Type**: number, a fraction greater than `0` and at most `1`
* **Default**: `0.01`, which reserves 1% of the context window

## `skillListingMaxDescChars`

Each turn, Claude sees a [listing of your skills](/docs/en/skills#skill-descriptions-are-cut-short) that shows each skill's `description` and `when_to_use` text. This key caps how many characters of that text Claude Code shows per skill; longer text is cut at the cap.

* **Scope**: [`Any file`](#scopes)
* **Type**: number of characters, a positive integer
* **Default**: `1536`

# Claude Code documentation: environment variables

Canonical location for the purposes of this case: `https://code.claude.com/docs/en/env-vars`.

| Variable | Purpose |
| :- | :- |
| `SLASH_COMMAND_TOOL_CHAR_BUDGET` | Override the character budget for skill metadata shown to the [Skill tool](/docs/en/skills#control-who-invokes-a-skill). The budget scales dynamically at 1% of the context window, with a fallback of 8,000 characters. Legacy name kept for backwards compatibility |
