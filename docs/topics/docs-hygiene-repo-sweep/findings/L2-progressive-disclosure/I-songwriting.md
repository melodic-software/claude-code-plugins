# L2 progressive disclosure: `I-songwriting`

106 files, 12 `T2`. Plugin: `songwriting`.

Totals: T1=40, T2=2, T3=2.

## Split lane

**No findings.** The largest `T2` body is `plugins/songwriting/skills/suno/SKILL.md` at 237 lines
/ 2,862 words, less than half the line ceiling and well inside the recommended body size. Every
other skill body in the plugin is smaller. The plugin already carries the deepest on-demand tree
in the corpus (51 files under `context/pat-pattison/research/`, 2.0 MB of `T3`), and the tier model
says on-demand content is free until read, so its size is not a defect. The small-corpus guard
covers the skill bodies.

This is the clearest case in the sweep of progressive disclosure already working: the skills route
by action into a large on-demand corpus, and the invocation-loaded surface stays small.

## Structure lane

### `missing-toc` (Tier 1)

40 files above 300 lines with no table of contents. 38 of them are the
`plugins/songwriting/context/pat-pattison/research/` corpus, which is the plugin's entire
reference layer, so this is one systemic defect rather than 40 independent ones.

`plugins/songwriting/context/pat-pattison/research/meter.md:1`:

> `# Meter`
>
> `Pat Pattison - *Essential Guide to Lyric Form and Structure* (1991), Chapter 3.`

1,922 lines. Third line onward is prose. No `## Contents`. The access pattern is the one the tier
model calls out: `plugins/songwriting/skills/meter-prosody/SKILL.md` routes a reader here for one
idea, and the reader has no way to reach it short of reading the file or guessing a heading.

| Path (under `plugins/songwriting/context/pat-pattison/research/`) | Lines |
|---|---|
| `meter.md` | 1,922 |
| `form.md` | 1,540 |
| `prosody.md` | 1,531 |
| `rhyme-types.md` | 1,373 |
| `metaphor.md` | 1,321 |
| `rhyme-strategy.md` | 1,295 |
| `repetition.md` | 1,223 |
| `rhyme-sonic-bonding.md` | 1,214 |
| `object-writing.md` | 1,176 |
| `point-of-view.md` | 1,121 |
| `song-forms.md` | 1,100 |
| `rhyme-worksheets.md` | 1,071 |
| `rhyme-fundamentals.md` | 1,040 |
| `exercises.md` | 940 |
| `verse-development.md` | 894 |
| `hook.md` | 889 |
| `daily-practice.md` | 878 |
| `song-forms-examples.md` | 840 |
| `box-model.md` | 732 |
| `phrasing.md` | 671 |
| `line-edit-rubric.md` | 635 |
| `response-filter.md` | 625 |
| `rhyme-generation.md` | 614 |
| `audit-checklist.md` | 588 |
| `worksheets.md` | 546 |
| `rhyme-spotlight-connection.md` | 512 |
| `five-compositional-elements.md` | 463 |
| `cliche.md` | 452 |
| `beyond-books.md` | 446 |
| `section-building.md` | 435 |
| `bridge.md` | 427 |
| `workflows.md` | 424 |
| `mosaic-rhyme.md` | 419 |
| `rhyme-dictionary-practice.md` | 378 |
| `lyric-melodic-roadmaps.md` | 341 |
| `line-brainstorm.md` | 339 |
| `variations.md` | 312 |
| `idea-to-title.md` | 308 |

Plus, outside the research corpus:

| Path | Lines |
|---|---|
| `plugins/songwriting/skills/suno/context/genre-taxonomy.md` | 533 |
| `plugins/songwriting/skills/suno/context/power-tips.md` | 328 |

Remediation: insert a `## Contents` anchor list under the H1 of each file, matching
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`. In this
corpus the list must sit **after** the source-attribution block each file opens with (for
`meter.md`, after line 11) and before the first substantive paragraph, so the attribution stays
the first thing a partial read sees. This is mechanical enough to script from each file's own
H2 headings; do it as one pass over the directory, not file by file.

### `missing-toc`: the corpus has no index either (Tier 2)

`plugins/songwriting/context/pat-pattison/research/` holds 51 files and contains no `README.md`
or index. The plugin README gestures at the directory as a whole:

`plugins/songwriting/README.md:82`:

```text
under `context/pat-pattison/research/` reproduce Pat Pattison's examples, worked
```

but names no file, and the per-skill Action Routers each name only the two or three files that
skill routes to. An agent that needs "the file about X" has no listing to consult.

Remediation: add `plugins/songwriting/context/pat-pattison/research/README.md`, one row per file,
each row a filename and a one-line "read this when" clause. Then point at it from
`plugins/songwriting/README.md:82`:

```markdown
The files under [`context/pat-pattison/research/`](context/pat-pattison/research/README.md)
reproduce Pat Pattison's examples, worked exercises, and rubrics. That README indexes all 51 by
what each one answers; read it when you need a file no skill's action router names.
```

This is the only new-file recommendation in this group, and it is a spoke index rather than a
content split, so it does not move any existing path.

### `orphan-spoke` (Tier 2)

**`plugins/songwriting/skills/suno/reference/suno-drift-audit-ledger.md`** (34 lines)

```text
# Suno context drift audit ledger

Committed authority for what has and has not been audited in the `suno`
skill's context spokes.
```

Verified: unreachable from `plugins/songwriting/skills/suno/SKILL.md`, and the only repo-wide
mention outside itself is `plugins/songwriting/CHANGELOG.md:645`. It is the sole file in
`skills/suno/reference/`, so the whole directory is unreachable.

Three-way treatment. The file calls itself "committed authority", which is a maintenance artifact
about the skill rather than content the skill reads at run time, so **add the pointer** is right
and it belongs in a maintenance section, not in the run path:

Append to `plugins/songwriting/skills/suno/SKILL.md`:

```markdown
## Maintaining this skill

[`reference/suno-drift-audit-ledger.md`](reference/suno-drift-audit-ledger.md) is the committed
record of which `context/` spokes have been drift-audited against Suno's live behavior and which
have not. Read it before editing a context spoke or after a Suno platform change, never during a
generation run.
```

If the maintainer prefers the ledger out of the skill body entirely, the alternative is to move it
to `plugins/songwriting/reference/suno-drift-audit-ledger.md` and cite it from
`plugins/songwriting/README.md`. Either resolves the orphan; do not leave it unreferenced.

### `deep-nesting` (Tier 3, awareness only)

`plugins/songwriting/context/pat-pattison/research/book-references.md` is the one research file no
skill or agent cites. It is reached from sibling research files (`voiceprint.md`,
`coaching-protocol.md`, and others) and from `plugins/songwriting/README.md:108`. A shared
bibliography cited by its siblings is a legitimate cross-reference, not a required-reading chain.
No treatment.

### Not a finding

`plugins/songwriting/skills/suno/SKILL.md:37` and `:185` point at the 12 genre templates as
`[templates/<name>.md](templates/)` with the 12 names enumerated in the same sentence:

```text
1. **Template mode**. `<name>` matches one of the 12 built-in templates (pop, rock, hip-hop,
   trap, edm, jazz, classical, folk, metal, ambient, lofi, rnb): read
   [templates/<name>.md](templates/) and present.
```

Condition and intent are both present and the target set is enumerated. The depth-2 reading my
reachability pass produced for those 13 files is an artifact of the `<name>` placeholder, not a
defect.

### `missing-toc`, 100 to 300 lines (Tier 3, awareness only)

34 files. No treatment.

## Cross-lane observations

- The research corpus reproduces a copyrighted author's worked examples. Whether each file earns
  its existence is an L1 question with an attribution dimension; this lane takes no position.
- `rhyme-types.md`, `rhyme-strategy.md`, `rhyme-fundamentals.md`, `rhyme-generation.md`,
  `rhyme-sonic-bonding.md`, `rhyme-spotlight-connection.md`, `rhyme-worksheets.md`,
  `rhyme-dictionary-practice.md`, and `mosaic-rhyme.md` are nine files on one topic totalling
  roughly 7,400 lines. Whether that is over-partitioned is L3's boundary, not a disclosure defect:
  each is separately routed to by `plugins/songwriting/skills/rhyme/SKILL.md`.
