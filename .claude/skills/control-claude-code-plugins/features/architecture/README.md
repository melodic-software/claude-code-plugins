# architecture

The skills of `plugins/architecture`. Each one is driven with `<plugin-dir>` set to `plugins/architecture`.

## Parts

- `enforce-boundaries`: Set up a check for each recorded boundary rule and prove it on an injected violation.
- `improve`: Scan for shallow modules, boundary crossings or unwritten conventions, then hand on the fix.
- `improve-layout`: Check whether files that change together live together, then propose a target layout.
- `map-components`: Chart the modules inside one deployable as a C4 component view.
- `map-containers`: Chart deployables, the stores they bind, and contained modules.
- `map-context`: Chart one software system's C4 system context from tracked configuration.
- `map-data`: Draw an ERD from a committed schema, offline.
- `map-dependencies`: Cite project and package edges from build manifests.
- `map-deployment`: Chart IaC deployment topology per environment, with a diff.
- `map-events`: Chart publishers, consumers, and orphan messages.
- `map-flow`: Trace one C# entry point into a sequence diagram with a citation on every hop.
- `map-landscape`: Chart a repository and the systems it references as a C4 system landscape and portfolio table.
- `principles`: Define the module-design terms architecture findings use.
- `adr`: Record, audit and prune architecture decisions in the repository's existing ADR convention.
- `setup`: Verify and converge the architecture plugin's consumer configuration. No plain-words entry.

## Sub-features

none

## Entry points

- `/architecture:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/architecture:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `architecture` and
`<skill>` from Parts. The skill's own `plugins/architecture/skills/<skill>/SKILL.md` gives its arguments.
For `improve-layout`, `<args>` is empty: its co-change script reads the checkout's git history and
reports the clusters it finds.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.
