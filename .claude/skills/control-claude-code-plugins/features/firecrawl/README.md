# firecrawl

The skills of `plugins/firecrawl`. Each one is driven with `<plugin-dir>` set to `plugins/firecrawl`.

## Parts

- `firecrawl`: Scrape, search, crawl, or parse web pages when WebFetch is blocked.
- `setup`: Verify the firecrawl plugin's runtime prerequisites for this machine, the firecrawl-cli binary and FIRECRAWL_API_KEY ... No plain-words entry.
- `update`: Maintainer-facing drift-check and upstream sync for the firecrawl plugin's wrapper skill. No plain-words entry.

## Sub-features

none

## Entry points

- `/firecrawl:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/firecrawl:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `firecrawl` and
`<skill>` from Parts. The skill's own `plugins/firecrawl/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.
