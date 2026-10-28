# mcp-tools

The skills of `plugins/mcp-tools`. Each one is driven with `<plugin-dir>` set to `plugins/mcp-tools`.

## Parts

- `audit`: Audit MCP tool definitions against design quality criteria.
- `audit-posture`: Inventory configured MCP servers and flag floating versions and other supply-chain risks.

## Sub-features

none

## Entry points

- `/mcp-tools:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/mcp-tools:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `mcp-tools` and
`<skill>` from Parts. The skill's own `plugins/mcp-tools/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.
