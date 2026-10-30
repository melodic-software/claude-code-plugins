# EARS pattern tags for acceptance criteria

Read this when the Brief's acceptance criteria are captured or written. It owns the EARS tag
vocabulary, the criteria bullet shape in both formats, and how `acceptance_criteria_format`
resolves. The coverage prompt asked at the same moment is [`coverage-prompt.md`](coverage-prompt.md).

## EARS tags, when the convention selects them

Resolve `acceptance_criteria_format` per the ladder below. Under `free-text`, the default and every
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

## Resolution ladder for `acceptance_criteria_format`

Restated here rather than cited: an installed plugin never sees the publishing repository's
convention docs, so a path citation would make that publisher a runtime dependency of this session.

```markdown
1. Anchor at the repository root: `${CLAUDE_PROJECT_DIR}` when set, otherwise
   `git rev-parse --show-toplevel`. Never a CWD-relative read.
2. Resolve the convention home `<home>` from the pointer line in the marked
   `<!-- BEGIN GENERATED: convention-home -->` region of the root instruction file
   (`AGENTS.md` canonical; `CLAUDE.md` unless it is a pure `@AGENTS.md` shim). Use the
   bundled resolver where the plugin ships one; never hand-parse the root file.
3. The printed home is repo-relative: join it to the root resolved in step 1,
   then read `<home>/authoring-formats/README.md` from that path and take the
   key's value from its fenced YAML block.
4. Layer order is one layer deep: an explicit invocation argument, where the skill has
   one, then the team convention doc, then the documented default. A convention-doc
   surface has no personal overlay, so there is no further layer to consult.
5. Default: `acceptance_criteria_format` is `free-text` — emit untagged plain-bullet
   criteria, exactly today's shape.
6. Degrade soft, and say so. No pointer line, no convention home on disk, no
   `authoring-formats/README.md`, no YAML block, an absent key, or an unrecognized value
   each resolve to the documented default. Name the cause in one clause and continue;
   never hard-fail, and never ask the operator to create the surface mid-task.
7. Report provenance whenever the resolved value shapes output: name the key, the value,
   and the layer it came from — `argument`, `team convention doc <path>`, or `default`.
```

This file arrives through the Read tool unsubstituted, so step 1's `${CLAUDE_PROJECT_DIR}` is the
project root SKILL.md "Acceptance-criteria capture" renders, never a token to expand in a command.

This plugin ships the step-2 resolver at `bash "<plugin-root>/lib/resolve-convention-home.sh"`
(`<plugin-root>` per SKILL.md "Spoke paths"): exit 0 prints the home on stdout, exit 1 means no
pointer line is bound, exit 2 is usage, and exit 3 is a FAIL (two pointer lines in one region, an
unterminated or nested region, an invalid pointer path, or a pointer whose target directory does
not exist). Every non-zero exit is a step-6 degrade, `free-text`, cause named in one clause, never
a halt and never a prompt to go create the surface.
