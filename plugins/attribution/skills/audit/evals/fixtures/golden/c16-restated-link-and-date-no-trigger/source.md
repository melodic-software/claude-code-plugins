# Claude Code documentation: skills

Excerpt of a real upstream page, kept for the attribution golden set. The passages below are copied
unchanged from the page named next, and nothing else from that page is reproduced.

Canonical location for the purposes of this case: `https://code.claude.com/docs/en/skills`.

## Frontmatter reference

| Field | Required | Description |
| :- | :- | :- |
| `description` | Recommended | What the skill does and when to use it. Claude uses this to decide when to apply the skill. If omitted, uses the first non-empty line of the markdown content. Put the key use case first: the combined `description` and `when_to_use` text is truncated at 1,536 characters in the skill listing to reduce context usage. |

## Skill descriptions are cut short

Claude Code loads a listing of skill names and descriptions into context so Claude knows what's available. The listing always contains every skill name, but if you have many skills, Claude Code drops some descriptions to fit the listing's character budget, which removes the keywords Claude needs to match your request. The budget scales at 1% of the model's context window. When the listing overflows, Claude Code drops descriptions starting with the skills you invoke least, so the skills you use most keep their full text.
