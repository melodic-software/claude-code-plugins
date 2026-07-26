# Artifact shape — index plus sidecars

The on-disk shape of a `/discovery:research` run's output. `SKILL.md` carries the mandate ("always
an index"); this file carries the schema and the reasoning. `EXPLORE.md` follows the same shape with
`EXPLORE-<section>.md` sidecars.

## Why an index at every size, not past a threshold

A size threshold makes the artifact's shape depend on how much the run happened to write, so a
consumer cannot know what it is holding without opening it. Worse, the threshold arrives exactly when
the artifact is already too big to skim — the reader pays the full cost once, then the shape changes
under them on the next run. Committing to the index shape from the first line makes the contract
stable and the reading cost proportional to what the consumer actually needs.

The unit of progressive disclosure is a **section**, and the consumer decides which sections it
wants. A planning step chasing one settled fact should read one sidecar, not the whole stage.

## The index — `RESEARCH.md`

Always the entry point. A consumer handed that filename must get a readable document.

1. **Task restatement** — what was asked, in the run's own words.
2. **One-line abstract per sidecar**, copied verbatim from that sidecar's `abstract` header field.
   Verbatim matters: an abstract paraphrased into the index drifts from the sidecar it describes, and
   the reader picks a file on the strength of a summary that no longer matches its contents.
3. **Section → file + anchor table**, so an abstract that looks relevant resolves to a path without
   opening anything.
4. **Next-stage-handoff** — settled facts vs. open decisions for the planning step.

## The sidecars — `RESEARCH-<section>.md`

Siblings of the index, inside the same slice directory. Each carries the Output Format's content for
one section, opening with a machine-readable YAML header so a consumer can grep headers rather than
prose.

**The filename is keyed on the SECTION, not the topic or scope.** A run has exactly one topic and
many sections, so a topic-keyed name gives every sidecar in the run the same filename: later sections
silently overwrite earlier ones, or the worker invents an undocumented name and the index's
section → file table stops resolving. Use the same stable kebab-case id that the header's `section`
field carries, so the filename, the header, and the index anchor are one identifier rather than three
that have to be kept in agreement.

```yaml
---
topic: <topic-slug>
section: <stable kebab-case id, matches the index anchor>
abstract: <one line, mirrored verbatim into the index>
claims:
  - claim: "<one-line claim>"
    confidence: HIGH          # HIGH | MEDIUM | LOW
    tiers: [0, 1]             # source tiers backing this claim
    sources:                  # what makes gate criterion 4 gradeable off the artifact
      - url: "<url fetched this turn>"
        tier: 1
        pool: "<publisher/org — two sources sharing a pool are NOT independent>"
produced_by: <phase id>
---
```

The vocabulary is reused, never reinvented: `HIGH | MEDIUM | LOW` and `Tier 0..3` are the research
skill's own, defined in `discipline.md`.

**`sources[]` is not redundant with `tiers[]`.** It is what lets outcome-gate criterion 4 — "≥2
INDEPENDENT corroborators, not two cites of one upstream pool" — be graded **by a verifier that never
saw the run**. Independence is a property of the publishing pools behind a claim; a bare tier list
encodes neither the URL nor the pool, so without `sources[]` the verifier can only take the run's
word for the one criterion the whole discipline rests on. Two entries sharing a `pool` are one
corroborator.

**The header set is closed; the sidecar set is open.** Adding a sidecar needs no schema change.
Adding a header *field* does — keep the header small enough that widening it stays cheap.

## Two placement rules, both load-bearing

1. **Sidecars stay inside `<memory_dir>/<slug>/`.** A sidecar root anywhere else is a placement
   change governed by the topic-docs convention, not by this skill — and it would strand the sidecars
   for any consumer that resolves the slice and finds only the index.
2. **`RESEARCH.md` stays the entry point.** Renaming it, or demoting it to one sidecar among several,
   breaks every consumer that was handed the declared filename.

**A sub-slice satisfies both, and is the only sanctioned way to put two runs in one slice.** When a
slice root is already occupied, or a parent is fanning out over several topics, each run writes its
whole set — index and sidecars, under their normal names — into `<memory_dir>/<slug>/<topic-slug>/`.
That is still inside the slice, so rule 1 holds; and the index inside it is still `RESEARCH.md`, so
rule 2 holds. What is **not** sanctioned is renaming the index to dodge a collision: `RESEARCH-*.md`
is the sidecar pattern, so a renamed index collides with its own sidecars and every consumer handed
the declared filename gets the *other* run's artifact. The run reports the path it actually wrote,
and the parent assigns sub-slices rather than letting workers pick — two workers choosing
independently can choose the same one.

A worktree that carries the index without its sidecars is strictly worse than a self-contained
artifact, so any glob that ships `RESEARCH.md` must also ship `RESEARCH-*.md` and `*-checklist.md`.
The topic-docs convention's `.worktreeinclude` recipe already does.

## The `EXPLORE.md` sidecar header — a different evidence kind

The index shape, the section-keyed filenames, the sub-slice rule, and both placement rules are
identical for exploration. **The header is not**, and pointing an exploration run at the research
header is a real defect rather than a shortcut: that header's fields are `confidence`, source
`tier`, and publishing `pool`, which describe *external* evidence. Local exploration evidence is a
repository path and whether the file was actually Read. A run handed the research header either
fabricates URL and pool values it has none of, or improvises a shape no consumer can parse — and the
fabrication is worse, because it launders "I grepped a filename" into the same field a fetched
primary source would occupy.

```yaml
---
topic: <topic-slug>
section: <stable kebab-case id, matches the index anchor and the filename>
abstract: <one line, mirrored verbatim into the index>
dimension: codebase        # which of the six exploration dimensions produced this
findings:
  - finding: "<one-line finding>"
    verified: read         # read | grep | inferred — see below
    paths:                 # repo-relative, never absolute; the outcome gate checks this
      - "src/payments/rounding.ts:112-140"
produced_by: <phase or dimension id>
---
```

**`verified` is the whole point of the header**, and it is the local analogue of the source tier:

- **`read`** — the file was opened and the finding comes from its contents. The only value a
  conclusion-driving claim may carry, per the outcome gate's Read-verified criterion.
- **`grep`** — a search hit located it and nothing was opened. Discovery only. A `grep`-verified
  finding is a lead, not a conclusion.
- **`inferred`** — drawn from a filename, a directory layout, or a convention rather than from
  content. Always suspect; name it so a reader can discount it.

Keeping these three distinct is what lets a verifier grade "conclusion-driving claims are
Read-verified, not inferred from a filename or grep hit" off the artifact instead of taking the
run's word for it — the same job `sources[]` does for the research side.
