# Artifact shape — index plus sidecars

The on-disk shape of a `/discovery:research` run's output. `SKILL.md` carries the mandate ("always
an index"); this file carries the schema and the reasoning. `EXPLORE.md` follows the same shape with
`EXPLORE-<scope>.md` sidecars.

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

## The sidecars — `RESEARCH-<topic>.md`

Siblings of the index, inside the same slice directory. Each carries the Output Format's content for
one section, opening with a machine-readable YAML header so a consumer can grep headers rather than
prose:

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

A worktree that carries the index without its sidecars is strictly worse than a self-contained
artifact, so any glob that ships `RESEARCH.md` must also ship `RESEARCH-*.md` and `*-checklist.md`.
The topic-docs convention's `.worktreeinclude` recipe already does.
