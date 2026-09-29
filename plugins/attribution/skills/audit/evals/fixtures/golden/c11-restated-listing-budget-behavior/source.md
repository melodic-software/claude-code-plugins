# Claude Code documentation: skills

Excerpt of a real upstream page, kept for the attribution golden set. The passages below are copied
unchanged from the page named next, and nothing else from that page is reproduced.

Canonical location for the purposes of this case: `https://code.claude.com/docs/en/skills`.

## Skill descriptions are cut short

Claude Code loads a listing of skill names and descriptions into context so Claude knows what's available. The listing always contains every skill name, but if you have many skills, Claude Code drops some descriptions to fit the listing's character budget, which removes the keywords Claude needs to match your request. The budget scales at 1% of the model's context window. When the listing overflows, Claude Code drops descriptions starting with the skills you invoke least, so the skills you use most keep their full text.

To raise the budget, set the [`skillListingBudgetFraction`](/docs/en/settings-reference#skilllistingbudgetfraction) setting (for example, `0.02` = 2%) or the `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable to a fixed character count. To free budget for other skills, set low-priority entries to `"name-only"` in [`skillOverrides`](#override-skill-visibility-from-settings) so they list without a description. You can also trim the `description` and `when_to_use` text at the source: put the key use case first, since each entry's combined text is capped at 1,536 characters regardless of budget. The cap is configurable with [`skillListingMaxDescChars`](/docs/en/settings-reference#skilllistingmaxdescchars).
