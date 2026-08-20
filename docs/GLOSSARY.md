# Glossary

The project's ubiquitous language: terms this marketplace has deliberately resolved, so the same
words carry the same meaning in conversation, skill bodies, docs, and commit messages.

This file records **vocabulary only** — what a term is, and which names were considered and
rejected for it. The reasoning behind a decision lives in the artifact that made it; entries cite
that artifact rather than restating it. New terms are curated through
`/domain-driven-design:curate-language` rather than hand-written, so the entry discipline stays
uniform.

This marketplace is a single language context, so there is no context map: every entry below
applies repository-wide.

## Terms

**AFK criterion**

The test of whether remaining work is scoped to run without a human at the keyboard — no decision
still owed to it, no mid-flight approval it must stop for. A yes routes the delegation decision to
`session-flow:orchestrate`; the criterion names the test, not the delegation.

Avoid: away-from-keyboard check

**asset rush**

The failure mode where a session drives toward producing the deliverable while the job is still
reaching shared understanding of what the deliverable should be. Names the critique that the
interview-first pipeline answers.

**context load**

The tokens an agent pays to read a surface, charged on every session for always-loaded ones. Paired
with cognitive load below; the two are distinct budgets and cutting one can overspend the other.

**cognitive load**

The attention a human maintainer pays to hold where things live across a doc set. Ten small
fragment files can be cheap in context load and ruinous in cognitive load.

Avoid: mental overhead

**navigation pointer**

A curated entry in an instruction file that routes a reader to a genuinely non-obvious, load-bearing
document — stating where to look and when to look there. Distinct from a file-by-file inventory,
which an agent can rebuild from the tree and which the memory audit flags.

Avoid: highway, stale highway

**phase boundary**

The moment a stage has produced its artifact and the next has not begun — where the continuation
router runs and where a compaction, if taken at all, is least destructive.

**primary source**

A record read directly from its origin, unmediated: the on-disk transcript, a live documentation
page, a shipped script's actual emitted strings. Stays primary across compaction.

Avoid: original source

**secondary source**

An account of a primary source rather than the source itself: the model-visible conversation after
compaction, a header comment describing code beneath it, another agent's summary. Usable, but a
claim resting on one is verified against the primary before it ships.

**smart zone**

The healthiest of `context-guard`'s three context zones (`smart` / `acceptable` / `dumb`), naming
the band rather than any token figure — the band numbers are declared judgment defaults and tunable
per consumer.

## Rejected terms

Names considered for a concept this project already owns, recorded so they are not reintroduced.
Each maps to the term or doctrine that owns the concept.

| Rejected | Owned by |
|---|---|
| design concept | **shared understanding** — the existing house term |
| grill-execute-clear | the house workflow taxonomy, which already names the loop |
| push vs point | **point, don't copy** (`discipline:point-dont-copy`) |
| highway / stale highway | **navigation pointer** above; survives only as a quoted mnemonic |
| cache *(the doc-restating-environment sense)* | `docs-hygiene:audit-derivability`'s derivable-from-environment doctrine; the word is overloaded here (plugin cache, prompt cache) |
| sediment | the `docs-hygiene` audit family's pruning doctrine; collides with the code-sense use in `playbooks:fable-5` |
| sycophancy | nothing — a generic LLM-behavior term with no distinct project meaning. Free-prose use is unaffected; it is simply not project vocabulary |

## Provenance

Every term above was graded and adopted in lane 6 of the AI Hero course vetting
(2026-08-18). The decision rows, including the basis for each verdict and the rejected-term
mappings, are in [`upstream/aihero-course.md`](upstream/aihero-course.md) under "Term adoption".
Materialization of this file was tracked as
[#3000](https://github.com/melodic-software/claude-code-plugins/issues/3000).
