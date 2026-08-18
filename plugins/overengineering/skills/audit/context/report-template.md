# Report shape — three layers, one source of truth

The run produces output in three layers. Only the first is mandatory-and-authoritative, only the
second is always shown, and the third is an optional extra that is skipped without ceremony when its
prerequisite is absent.

| Layer | When | Authority |
|---|---|---|
| **Findings artifact** | always | **The single source of truth.** Everything that drives the reasoning lives here |
| **Inline terminal summary** | always | A *view* of the artifact — never a second record, never a place a fact appears first |
| **Rendered HTML view** | presence-gated | A rendering of the same artifact; skipped when unavailable |

## Layer 1 — the findings artifact

Shape, fields, ids, ordering, the stable-spine / free-prose split, the status vocabulary, and the
re-run merge rules are owned by `${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`. Its home is
resolved through `${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`. **This document restates neither.**

Two reminders that are about *writing* the file rather than about the contract:

- The evidence-availability assessment leads the file, ahead of the summary and the findings, because
  it changes what UNPROVEN means for every row beneath it.
- The spine lines are the machine-comparable part, so they stay single-line, closed-vocabulary, and
  free of prose. Anything that wants to be a sentence goes below the spine. A spine line that grew a
  clause is a diff that reports model noise as change.

The spine's line format, as a shape rather than as a definition of any token in it:

```markdown
### <finding-id>

- **Layer:** <one enum value>
- **Artifact:** <repo-relative path or kind-prefixed identifier>
- **Verdict:** <one verdict token>
- **Status:** <one status value>
```

The tokens that may fill those last two value slots — and what each one asserts — belong to
`${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` §6 and to the findings-artifact contract's status
table. They are named there once.

## Layer 2 — the inline terminal summary

Always printed, in the response, after the artifact is written. It is a navigation aid: it tells the
operator what the run found, what it could not find out, and where to read the rest. Keep it short
enough to read without scrolling past it.

1. **The read-only line, first.** *"Read-only pass; the only file written is the findings artifact at
   `<resolved path>`."* Plus the layers walked this run, and — when the pass was layer-scoped — the
   layers that were not, so nobody reads a partial pass as a complete one.
2. **Evidence availability, one line per tier**: present / partial / unavailable, with the probe. A
   shallow clone and a missing telemetry sink each get named here explicitly.
3. **Counts**, per verdict class and per layer. A small table, not prose.
4. **The top findings**, ranked — protected items flagged for a human first, then the strongest
   evidenced retirement-direction verdicts, then the carry-cost-ranked head of the UNPROVEN residue.
   Cap the inline list; the artifact carries the rest.
5. **The proposed ablation batch**, when one was produced: its items, an owner and a re-check date
   each, and the observation window's end date.
6. **Open checkpoints** — the intent questions awaiting an answer (attended), or the count of
   findings whose `Intent` is `OPEN-INTENT` (unattended). Where members were also judged, their
   `OPEN-INTENT` count is reported as a separate number, labelled as members.
7. **Configuration provenance**, one line: which config layers contributed, or that none were present
   and the bundled defaults applied. Name a personal layer explicitly whenever one shaped output.
8. **The next step**, named but not taken: `overengineering:realign` consumes this artifact and
   executes accepted findings behind an explicit per-item human gate. Do not start it unasked.

A run that found nothing to retire says so plainly. A clean surface is a valid outcome, and
manufacturing a finding to justify the pass is the failure this whole method is pointed at.

## Layer 3 — the rendered HTML view

**Presence-gated on the visualization plugin.** When `visualization:visualize` is installed, offer it
the artifact for a rendered view — the artifact stays the source of truth and the rendering is a
second presentation of it, never a place a finding appears first.

**Documented fallback when that plugin is not installed: skip it.** Say nothing beyond a single line
noting that the optional rendered view was unavailable, and do not substitute a hand-built HTML file,
an inline chart, or an extra markdown file. Layers 1 and 2 are complete on their own; a substitute
built here would be a third record to keep in sync, which is exactly what the single-source-of-truth
rule forbids.

## What never appears in any layer

- **Credential values.** The *name* of a secret or token referenced by a lane or hook is evidence; its
  value never is, and never leaves the file it lives in.
- **A verdict without its evidence.** Every row carries at least one empirical citation or is UNPROVEN
  naming the tier consulted and whether it was silent or unavailable.
- **A threshold without its label.** A cited threshold carries its source and its analogical-transfer
  label verbatim, in the artifact and in the summary alike.
- **A protected item's evidence, withheld.** The cap changes the recommendation, never what is
  reported.
- **A route recorded as taken when the neighbor was absent.** Presence answers are recorded either
  way, so a skipped route is visible rather than silent.
