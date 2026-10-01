<!-- markdownlint-disable MD004 MD051 -->
# Claude Code documentation: settings reference

Excerpt of a real upstream page, kept for the attribution golden set. The passages below are copied
unchanged from the pages named next, and nothing else from them is reproduced.

Canonical location for the purposes of this case: `https://code.claude.com/docs/en/settings-reference`.

## `skillListingMaxDescChars`

Each turn, Claude sees a [listing of your skills](/docs/en/skills#skill-descriptions-are-cut-short) that shows each skill's `description` and `when_to_use` text. This key caps how many characters of that text Claude Code shows per skill; longer text is cut at the cap.

* **Scope**: [`Any file`](#scopes)
* **Type**: number of characters, a positive integer
* **Default**: `1536`

# Claude Code documentation: skills

Canonical location for the purposes of this case: `https://code.claude.com/docs/en/skills#frontmatter-reference`.

## Frontmatter reference

| Field | Required | Description |
| :- | :- | :- |
| `description` | Recommended | What the skill does and when to use it. Claude uses this to decide when to apply the skill. If omitted, uses the first non-empty line of the markdown content. Put the key use case first: the combined `description` and `when_to_use` text is truncated at 1,536 characters in the skill listing to reduce context usage. |
