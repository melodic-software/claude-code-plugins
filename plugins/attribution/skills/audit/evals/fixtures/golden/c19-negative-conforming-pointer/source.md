# Claude Code documentation: skills

Excerpt of a real upstream page, kept for the attribution golden set. The passages below are copied
unchanged from the page named next, and nothing else from that page is reproduced.

Canonical location for the purposes of this case: `https://code.claude.com/docs/en/skills#frontmatter-reference`.

## Frontmatter reference

| Field | Required | Description |
| :- | :- | :- |
| `name` | No | Command name shown in the `/` menu. Defaults to the directory name. See [How a skill gets its command name](#how-a-skill-gets-its-command-name) for how the field interacts with the name you type to invoke the skill. |
| `description` | Recommended | What the skill does and when to use it. Claude uses this to decide when to apply the skill. If omitted, uses the first non-empty line of the markdown content. Put the key use case first: the combined `description` and `when_to_use` text is truncated at 1,536 characters in the skill listing to reduce context usage. |
| `when_to_use` | No | Additional context for when Claude should invoke the skill, such as trigger phrases or example requests. Appended to `description` in the skill listing and counts toward the 1,536-character cap. |
