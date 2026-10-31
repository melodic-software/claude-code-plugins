# EARS pattern tags for acceptance criteria

Read this when the Brief's acceptance criteria are captured or written. It owns the EARS tag
vocabulary, the criteria bullet shape in both formats, and how `acceptance_criteria_format`
resolves. The coverage prompt asked at the same moment is [`coverage-prompt.md`](coverage-prompt.md).

## EARS tags, when the convention selects them

Resolve `acceptance_criteria_format` per "Resolving `acceptance_criteria_format`" below. Under `free-text`, the default and every
degrade, emit criteria exactly as today: `- AC<n>: <testable criterion>`, untagged, byte-comparable
in shape to a run with no convention surface at all. Under `ears`, every emitted criterion carries a
bracketed pattern prefix after its id on that same plain-bullet form, `- AC<n>: [<pattern>] <criterion>`:

| Tag | Pattern |
|---|---|
| `[ubiquitous]` | an always-true requirement, no trigger and no state |
| `[event-driven]` | `WHEN <trigger>, <response>` |
| `[state-driven]` | `WHILE <state>, <response>` |
| `[unwanted-behavior]` | `IF <trigger>, THEN <response>` |
| `[optional-feature]` | `WHERE <feature is included>, <response>` |

```text
### Acceptance criteria
- AC1: [ubiquitous] The manifest is valid JSON at rest
- AC2: [event-driven] WHEN the upload completes, the manifest is rewritten
- AC3: [state-driven] WHILE a rebuild is in flight, reads are served from the previous manifest
- AC4: [unwanted-behavior] IF the upload fails, THEN the partial manifest is discarded
- AC5: [optional-feature] WHERE checksum verification is enabled, the manifest records a digest per entry
```

The five names are exactly `ubiquitous`, `event-driven`, `state-driven`, `unwanted-behavior`, and
`optional-feature`. This vocabulary is a contract with whatever reads the tag downstream, and a name
spelled any other way, `unwanted_behavior`, `unwanted`, `event`, reads as no tag at all and breaks
detection silently rather than loudly. The tag prefixes the criterion; it never replaces the
testable sentence, and an untaggable criterion is a criterion still owed a shape, not a criterion
owed a sixth pattern.

The bullet stays a plain bullet in both formats, never a checkbox: `- [ ]` is
`/work-items:decompose`'s slice shape, and a `[pattern]` prefix on a checkbox line is ambiguous
with an unchecked box.

Where the tags travel: they land in the Brief's `### Acceptance criteria`, and a consumer that
publishes the Brief verbatim as a tracker container body carries them with it. They do not reach
per-slice criteria, which are freshly authored by whatever decomposes the work, because a vertical
slice owns everything it grades; a slice keeps only the criterion's id.

## Resolving `acceptance_criteria_format`

Follow [`<plugin-root>/context/authoring-formats.md`](../../../context/authoring-formats.md)
"Resolution ladder" (`<plugin-root>` per SKILL.md "Spoke paths"; `<project-root>` is the project
root SKILL.md "Acceptance-criteria capture" renders). This skill takes no format argument. Default
and every degrade: `free-text`, untagged plain-bullet criteria, exactly today's shape.

Before reading `AGENTS.md`, `CLAUDE.md` or any `authoring-formats/README.md` for this key, run the
ladder's step-2 resolver, dropping `--root "<project-root>"` when the project root is unset:

```bash
bash "<plugin-root>/lib/resolve-convention-home.sh" --root "<project-root>"
```

Read `authoring-formats/README.md` only under the home it prints, even when another copy exists
elsewhere: the pointer line names which home counts. A non-zero exit is a step-6 degrade to
`free-text` with its cause named, never a reason to hand-parse the root file instead.
