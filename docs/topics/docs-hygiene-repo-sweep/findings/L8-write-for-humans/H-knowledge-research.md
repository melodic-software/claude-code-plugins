# H-knowledge-research

Lane `L8-write-for-humans`, wave 1, read-only. Audience slice: 21 `HUMAN` rows (10 plugin READMEs,
10 CHANGELOGs, plus
`plugins/knowledge/skills/video-digest/templates/recommendations/README.md`). The 10 CHANGELOGs are
judged as a class in `README.md`.

This group holds four of the sixteen `M3` outliers, including the two least findable placements in
the corpus.

## Findings

| # | Path | Predicate | Severity |
|---|---|---|---|
| H1 | `plugins/visualization/README.md:85` | `M3` | S1 |
| H2 | `plugins/miro/README.md:76` | `M3` | S1 |
| H3 | `plugins/dometrain/README.md:150` | `M3` | S1 |
| H4 | `plugins/ai-briefing/README.md:58` | `N1` | S3 |
| H5 | `plugins/visualization/README.md:15` | `L1` | S2 |
| H6 | `plugins/visualization/README.md:104` | `L1`, `Am3` | S2 |

### H1. The options reference is under `## Possible future change`

`plugins/visualization/README.md:85`. The generated options block starts at line 96, under this
heading. Verbatim heading and the section it belongs to:

```text
## Possible future change

- **Third-party visualization server.** No credible egress-free, self-hostable
  visualization server exists to depend on today.
```

Predicate `M3`, severity S1. A reader looking for this plugin's configuration options will not open
a section headed `Possible future change`, and the section's own content is about something the
plugin deliberately does not do. The options table is not a possible future change; it is the
present interface.

Remediation as in `B-cc-config-ops.md`: move the marker-delimited block, from
`<!-- ai-slop-ignore-start: generated options block` through the matching `<!-- END GENERATED` and
its `ai-slop-ignore-end`, together with the `### How to set these` subsection, under a new
`## Configuration` heading. Leave `## Possible future change` where it is with its own content
intact. Do not edit the generated table.

### H2 and H3. The options reference is under `## Development`

`plugins/miro/README.md:76` (block at line 94) and `plugins/dometrain/README.md:150` (block at line
158). Predicate `M3`, severity S1 for both.

`## Development` in both READMEs means "how to work on this plugin's own code". Verbatim, from
`dometrain`:

```text
## Development

This plugin ships no server code. The MCP server is Dometrain-hosted. There is no build step;
`claude plugin validate plugins/dometrain` is the only local check.
```

That is contributor documentation. The options a consumer sets when installing the plugin have
nothing to do with it, and a consumer has no reason to open the section. Same remediation as H1.

### H4. A near-miss heading

`plugins/ai-briefing/README.md:58`, `## Profiles and configuration`, block at line 86.

This is **not** an `M3` failure: the heading does say configuration, and a reader will find the
block. It is filed as `N1` at S3, because the corpus calls this section `## Configuration` in 18 of
34 plugin READMEs and calling it something else in one teaches two names for one thing.

Remediation is optional and low value: rename to `## Configuration` and keep the profiles content as
a subsection. Wave 3 should skip this if it is not already editing the file.

### H5

`plugins/visualization/README.md:15`, 73 words, 7 interrupters. Verbatim:

```text
**Form**, matched to the *shape* of the content: a mermaid diagram for flow / hierarchy / sequence / state / relationships; a markdown table for attribute comparison; a chart for quantities; ASCII/Unicode for a small structural sketch; a rich rendered page for a composite or interactive view; a hand-editable design canvas (via the bundled `design` skill, when that presence-gated preview is available)
```

Predicates `L1` and `Am3`. The slash chains (`flow / hierarchy / sequence / state / relationships`,
`ASCII/Unicode`) are coordination and read as compound terms rather than as lists.

Replacement, turning the sentence into the reference table it already is:

```text
**Form**, matched to the *shape* of the content:

| Content shape | Form |
|---|---|
| Flow, hierarchy, sequence, state, or relationships | A mermaid diagram |
| Attribute comparison | A markdown table |
| Quantities | A chart |
| A small structural sketch | ASCII or Unicode |
| A composite or interactive view | A rich rendered page |
| Something the reader will tweak by hand | A design canvas, via the bundled `design` skill when that presence-gated preview is available |
```

The last row's `Content shape` cell is not in the original. **Wave 3 must confirm it against
`plugins/visualization/skills/visualize/SKILL.md` before applying, or leave the cell empty.** The
resolved guide forbids inventing a claim during a fix pass.

### H6

`plugins/visualization/README.md:104`, 56 words in one table cell listing four `output_mode` values.
Predicates `L1` and `Am3` (`'auto' (decide by content and available surfaces)` runs into the next
value with no separator a reader can see).

Replacement for the cell:

```text
One of `auto`, `terminal`, `file`, or `artifact`. `auto` decides by content and available surfaces. `terminal` always renders inline, degrading richer forms to their best terminal approximation. `file` renders richer forms as a self-contained local HTML file, never published off the machine. `artifact` prefers a published Artifact when that surface is available, then falls back to a local HTML file, then to the terminal.
```

## Document mode

Ten plugin READMEs. Nine hold one mode cleanly. The `M3` findings above are mode findings in
substance: a reference block placed under a heading that promises a different mode.

`plugins/knowledge/skills/video-digest/templates/recommendations/README.md` is a template-directory
README explaining where output lands. Reference mode, correct, no findings.

`plugins/dometrain/README.md` and `plugins/miro/README.md` both carry a `## Development` section
addressed to a contributor while the rest of the document is addressed to a consumer. That is two
audiences in one document, which Diátaxis treats as a mode question. Filed at S3, no edit proposed:
the sections are short, clearly labelled, and moving contributor docs out of a plugin README is a
structural decision above this lane's remit. Flagged for the orchestrator.

## Predicates with no findings in this group

`M1` as its own finding, `M2`, `A1`, `A2`, `Am1`, `Am2`, `Am4`, `C1`.

## Cross-lane observations

- **`ai-slop:audit`**: nothing in this group's READMEs.
- **`source-control`**: nothing in this group.
