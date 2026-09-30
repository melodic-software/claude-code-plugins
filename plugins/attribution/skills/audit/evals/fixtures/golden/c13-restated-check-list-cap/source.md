<!-- markdownlint-disable MD051 -->
# Claude Code documentation: skills

Excerpt of a real upstream page, kept for the attribution golden set. The passages below are copied
unchanged from the page named next, and nothing else from that page is reproduced.

Canonical location for the purposes of this case: `https://code.claude.com/docs/en/skills`.

## Frontmatter reference

| Field | Required | Description |
| :- | :- | :- |
| `description` | Recommended | What the skill does and when to use it. Claude uses this to decide when to apply the skill. If omitted, uses the first non-empty line of the markdown content. Put the key use case first: the combined `description` and `when_to_use` text is truncated at 1,536 characters in the skill listing to reduce context usage. |

## Skill descriptions are cut short

To raise the budget, set the [`skillListingBudgetFraction`](/docs/en/settings-reference#skilllistingbudgetfraction) setting (for example, `0.02` = 2%) or the `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable to a fixed character count. To free budget for other skills, set low-priority entries to `"name-only"` in [`skillOverrides`](#override-skill-visibility-from-settings) so they list without a description. You can also trim the `description` and `when_to_use` text at the source: put the key use case first, since each entry's combined text is capped at 1,536 characters regardless of budget. The cap is configurable with [`skillListingMaxDescChars`](/docs/en/settings-reference#skilllistingmaxdescchars).
