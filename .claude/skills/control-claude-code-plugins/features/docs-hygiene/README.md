# docs-hygiene

The skills of `plugins/docs-hygiene`. Each one is driven with `<plugin-dir>` set to `plugins/docs-hygiene`.

## Parts

- `audit-derivability`: Judge whether a doc earns its existence or should become a pointer.
- `audit-encapsulation`: Find external citations reaching into a skill's private surfaces.
- `audit-noise`: Classify markdown for citations, ghost refs, meta-commentary, plan/conversational/tracker residue.
- `audit-progressive-disclosure`: Grade instruction files for split opportunities and hub/spoke disclosure defects.
- `compress`: Tighten markdown by dropping flavor while preserving every directive.
- `extract-ssot`: Deduplicate repeated prose into one named source of truth.
- `rename-references`: Sweep stale references after renames, including forms grep misses.
- `setup`: Verify that markdownlint-cli2, the lint gate /docs-hygiene:compress requires, resolves and runs for this repository, and validate the compress_articles setting. No plain-words entry.
- `write-for-agents`: Authoring-time doctrine for agent-consumed markdown.
- `write-for-humans`: Authoring-time doctrine for human-read documentation.

## Sub-features

none

## Entry points

- `/docs-hygiene:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/docs-hygiene:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `docs-hygiene` and
`<skill>` from Parts. The skill's own `plugins/docs-hygiene/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.
