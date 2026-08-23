# Artifact shape — `INTENT.md` and its sidecars

The on-disk shape of a `/discovery:trace-intent` run's output. `SKILL.md` carries the mandate; this
file carries the header schema and the reasoning behind it.

**The shared parts are not restated here.** Index-at-every-size rather than past a threshold,
section-keyed sidecar filenames, the sub-slice rule for a collision, and both placement rules are
identical across this plugin's three families and are stated once in
[`${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md`](${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md).
Read them there. What follows is what differs, which is the header and one property of the index.

## `INTENT.md` is private to this skill

It is deliberately **not** a shared lifecycle-protocol kind: it has no entry in
`reference/artifact-protocol.md`, no downstream skill consumes it by name, and nothing outside this
plugin is entitled to its shape.

That is a decision with a cost and a reason. The cost is that a planning step cannot pick this
artifact up by protocol the way it picks up a `PLAN.md`. The reason is that the protocol file is one
of five byte-identical copies across five plugins, so promoting a kind into it obliges an identical
edit to all five plus a protocol version bump — a price worth paying for an artifact several plugins
consume, and not worth paying for one this skill writes and this skill's reader reads. Promote it
when a second plugin actually needs it, and pay the five-copy cost then.

## The index — `INTENT.md`

Everything the shared shape requires, plus one section the other two families do not have:

1. **The why-question restated**, with the code anchor it was asked about.
2. **One-line abstract per sidecar**, copied verbatim from that sidecar's `abstract` field.
3. **Section → file + anchor table.**
4. **Sources consulted** — one line per evidence category, *including every category that found
   nothing*, in the form `SKILL.md`'s Output section specifies.

**Item 4 lives in the index, not in a sidecar, and that placement is load-bearing.** The coverage map
is the part of this artifact a reader most needs and is least likely to go looking for: someone who
opens `INTENT.md`, finds a confident-sounding answer, and stops has taken the answer without the
shape of the record behind it. A sidecar is opt-in reading; the index is not. Where a run's whole
census sits in `Speculative` and `Unknown`, the index is where a reader has to meet that.

## The sidecars — `INTENT-<section>.md`

Siblings of the index, inside the same slice directory, each opening with this header:

```yaml
---
topic: <topic-slug>
section: <stable kebab-case id, matches the index anchor and the filename>
abstract: <one line, mirrored verbatim into the index>
question: <the why-question this section answers>
claims:
  - claim: "<the reconstructed intent, one line>"
    tier: Direct              # Direct | Supported | Inferred | Speculative | Unknown
    sources:
      - ref: "<commit sha | PR #N | ticket id | doc url | path:line>"
        kind: source-control  # the evidence category that produced it
        reliability: "<author's proximity to the decision; how old the record is>"
produced_by: <evidence category or investigation pass>
---
```

`Unknown` claims carry `sources[]` too, and theirs name **what was searched**, not what was found —
that is what makes "we looked and it is not written down anywhere" a checkable statement rather than
a shrug.

## Two properties are why this is a contract rather than prose

**`tier` is readable off the header.** A verifier who never saw the run can grade tier assignment
mechanically — pull every `tier: Direct` claim, check that each one's `sources[]` actually contains
someone stating the intent. That is the same property `verified:` buys the exploration header and
`sources[]` buys the research one, and it is the reason the outcome gate can split: the producer
assembles the evidence, and a fresh context renders the verdict.

**`reliability` is a sibling of `ref`, not of `tier`.** Every comparator scheme separates evidence
directness from source reliability and forbids merging them — ICD 203 explicitly, and GRADE and
Admiralty AJP-2.1 by construction. Only `tier` routes a claim to an output section; `reliability`
annotates the citation and never routes. Collapsing them would put a review comment by the change's
author and a four-year-old wiki page in different tiers when they are both, factually, someone
writing down why — and the whole scale would stop measuring inferential distance and start measuring
a vague feeling about the source.

## Why not either sibling's header

Pointing an intent run at the research or exploration header is a real defect rather than a shortcut,
and it is the mistake this file exists to prevent:

- **The research header's fields are `confidence`, source `tier` (0-3), and publishing `pool`.**
  Those describe external evidence and its authority. An intent run has no publishing pool, and its
  tier measures a different thing entirely — inferential distance from an explicit statement, not
  source authority. A run handed that header either fabricates pool values it has none of, or
  improvises a shape no consumer can parse. The fabrication is the worse outcome, because it
  launders "someone hinted at this in a merge thread" into the field a fetched primary source
  occupies.
- **The exploration header's `verified: read | grep | inferred`** describes whether a repository file
  was opened. That is precisely the axis this skill refuses to grade intent on: reading the
  implementation tells you what was built, almost never why, and code shape leaves this scale
  entirely rather than landing at its bottom rung.

**The header set is closed; the sidecar set is open.** Adding a sidecar needs no schema change.
Adding a header *field* does — keep the header small enough that widening it stays cheap.
