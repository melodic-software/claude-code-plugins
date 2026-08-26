# L-docs-topics

Lane `L8-write-for-humans`, wave 1, read-only. Audience slice: all 57 rows in this group are
classified `HUMAN` in `inventory/manifest.tsv`.

**This lane files no conformance findings against any of the 57, and recommends reclassifying the
whole group out of the authoring-doctrine corpus.** The reasoning takes the whole file, because a
group-wide reclassification needs to be arguable rather than asserted.

## The reclassification

### What these files are

`docs/topics/<slug>/` is a tier defined by this repository's own contract,
`docs/conventions/topic-docs/README.md`. That contract's tier table says, verbatim:

```text
| Contract | `docs/topics/<slug>/` | Committed **on the task branch only**; pruned before merge | `PLAN.md` (Brief + Plan), `PRD.md`, `design/` (incl. the `design-threads.md` / `design-resolution.md` gate files), `verification/` (the distilled manifest) |
```

Three properties follow from that row, and each one on its own would disqualify a file from
authoring doctrine:

1. **They are committed on the task branch only and pruned before merge.** A conformance rewrite
   applied to a file scheduled for deletion is work that is discarded by design. The repository even
   has a gate for the pruning: `scripts/check-contract-slice-prune.sh`.
2. **They exist to be enforced against.** The tier's own selection question is *"does anything
   downstream enforce against this document?"* A document whose job is to be checked by a gate is a
   contract, and its wording is load-bearing in a way ordinary prose is not. Rewriting a criterion
   for readability risks changing what the gate checks.
3. **Their reader is the task's own agents.** A `PLAN.md` is read by the orchestrator running the
   plan. A `design-threads.md` is read by the agent resolving the threads. A `RESEARCH-*.md` is read
   by whoever consumes the research. None of these is a person reading published documentation.

### What this group's contents actually are

The 57 files, by shape:

| Shape | Count | Read by |
|---|---|---|
| `PLAN.md` | 8 | The orchestrator executing the plan |
| `design/*.md` (design threads, resolutions, research records) | 24 | The agent resolving or consuming them |
| `findings/*.md` | 14 | The agent applying the dispositions |
| Briefs, ledgers, reviews, checklists, and one topic `index.md` | 11 | The agent resuming or reviewing the task |

Not one of them is a document a person opens to learn how to use this marketplace.

### The self-reference argument

This sweep's own artifacts live at `docs/topics/docs-hygiene-repo-sweep/`, and `PLAN.md` excludes
them from the corpus with the reason:

```text
Everything under `docs/topics/docs-hygiene-repo-sweep/` — this sweep's own artifacts. A lane
that audited its own findings would feed on itself.
```

That exclusion is right, and the reason generalises. `docs/topics/plugin-audit-port/PLAN.md` and
`docs/topics/docs-hygiene-repo-sweep/PLAN.md` are the same kind of document. The only difference is
which task produced them. If the sweep's own plan is out of scope because it is a working artifact,
the other eight plans are out of scope for the same reason.

### Recommended verdict

**Out of scope: working artifact.** This matches the category `L1-derivability` used for the same
shape (its `out-of-scope: functional artifact` bucket, 141 files) and needs no new vocabulary.

Note that `L1-derivability` classified all 57 of these as `keep-owns-facts` rather than as
out-of-scope. The two lanes are answering different questions and both answers can hold: these
documents do own facts (so `L1` keeps them), and they are not the product of authoring doctrine (so
`L8` does not rule on them). The orchestrator should reconcile the vocabulary, not the verdicts.

## What is being given up

Stated plainly, because a lane that declines 57 files owes the orchestrator the cost.

The mechanical scan found **152 sentences** over the `L1` filter in this group, the second-highest
concentration in the corpus after `K-repo-docs`. Nine files carry five or more:

```text
19  docs/topics/plugin-audit-port/PLAN.md
12  docs/topics/ai-adoption-ladder/design/RESEARCH-channel-adapters.md
11  docs/topics/ai-adoption-ladder/design/RESEARCH-headless-agents.md
10  docs/topics/context-engineering-claude-5/design/checks-and-sweep.md
 9  docs/topics/context-engineering-claude-5/PLAN.md
 9  docs/topics/ai-adoption-ladder/design/design-threads.md
 8  docs/topics/fresh-eyes-checkpoint-audit/PLAN.md
 7  docs/topics/context-engineering-claude-5/design/rerun-contract.md
 6  docs/topics/ladder-climb-roadmap/PLAN.md
```

Those sentences are real. They are dense, they carry stacked interrupters, and a person reading them
does have to backtrack. The judgment is not that they read well. It is that this lane should not
rewrite a contract document that a gate enforces against and that is scheduled for pruning, on a
readability axis, without the task owner in the loop.

If the orchestrator disagrees, the reversal is cheap: the 152 sites are enumerable from the same
scan, and the `L1` treatment is the same as everywhere else in this lane.

## Findings

None. Per the sweep's standing rule, a group with no findings reports none, and padding this file
with `Tier 3` non-defects would make wave 2 worse.

Two mechanical hits are recorded so nobody re-derives them:

- `Am2`, `(s)` in prose, at `docs/topics/ai-adoption-ladder/design/RESEARCH-routine-catalog.md:108`
  and `:111` and `:113` and `:115`, and at `docs/topics/fresh-eyes-checkpoint-audit/PLAN.md:190`.
  All five are table column headers or vocabulary-table rows, which are labels rather than
  sentences, so they would not be findings even if the group were in scope.
- `Am3`, a slash in prose, at
  `docs/topics/ai-adoption-ladder/design/RESEARCH-peer-frameworks.md:5`
  (`autonomously/headlessly`). One instance, S3, in a research prompt restatement.

## Document mode

The Diátaxis compass does not apply cleanly to this group, and saying so is the honest answer rather
than forcing a classification.

A `PLAN.md` is not a tutorial, how-to, reference, or explanation. It is a work contract: a brief, a
set of criteria, and an execution order, addressed to whoever runs it. The skill's compass is built
for documentation, and its own scope statement is about *"prose a **person** reads"*. Applying it to
a work contract would be a category error.

The one genuine mode observation, offered to the orchestrator rather than filed: several
`design/RESEARCH-*.md` files under `docs/topics/ai-adoption-ladder/` read as **explanation** and are
durable in a way the tier is not. If any of them are meant to outlive the task branch, the
`topic-docs` contract's own graduation edge applies: they belong in `docs/specs/` or `docs/adr/`,
which is the durable tier. That is a placement question for the task owner, not a prose question,
and `docs/specs/d1-model-already-knows-measurement.md` is the worked example of what graduation
looks like.

## Cross-lane observations

- **`ai-slop:audit`**: heavy em-dash use throughout, `docs/topics/fable-field-guide-audit/dispositions.md`
  carrying 251. As with `K-repo-docs`, `docs/**` sits outside the scope
  `.claude/rules/vendor-docs-are-not-style.md` declares for the em-dash prohibition, so these are in
  policy.
- **`source-control`**: nothing in this group.
