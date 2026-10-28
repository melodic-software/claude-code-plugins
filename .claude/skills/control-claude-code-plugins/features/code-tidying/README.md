# code-tidying

The skills of `plugins/code-tidying`. Each one is driven with `<plugin-dir>` set to `plugins/code-tidying`.

## Parts

- `audit-comment-residue`: Classify code comments for history narration and session-reference residue.
- `audit-dead-code`: Whole-repo dead-code hunt across four labeled lanes with adjudicated candidates.
- `batch-simplify`: Batch-run simplification across changed files, or a whole repository, by ecosystem.
- `dissolve-comments`: Dissolve comments into expressive code via triage. Delete, refactor-then-delete, or keep.
- `setup`: Checks or scaffolds this repository's code-tidying configuration: tracked project tidy lanes and the optional ... No plain-words entry.
- `tidy`: Proactively hunt one lane for safe structural tidyings and ship a structure-only PR.
- `tidy-diff`: Tidy one change's own lines before its commit, scoped by a file-and-line list.

## Sub-features

none

## Entry points

- `/code-tidying:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/code-tidying:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `code-tidying` and
`<skill>` from Parts. The skill's own `plugins/code-tidying/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.
