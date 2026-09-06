---
outcome: early-exit
tier: B
date: 2026-09-06
---

# Design resolution. Typed ticket body lane

## Outcome

Early exit. No separate `/planning:design` session was run, because the design threads this lane
would explore were already resolved upstream and recorded, and re-deriving them here would
re-litigate settled decisions rather than surface new ones.

## Where the design was actually done

The container Brief on issue #3799 carries the resolved design: the two convention keys and their
allowed values and defaults, the artifact type emitted per design scope, the dialect offered per
artifact kind, the inlining trigger, and the verdict-table shape. It also carries the captured
assumptions and the out-of-scope list. That Brief is the design artifact for this lane.

Behind it sits an interview whose ledger and shared-understanding summary were written during the
decomposition session. Fifteen questions were asked and answered there, including the ones that
would otherwise open here: whether to build a Gherkin pipeline (no), whether to add a standalone
design-document skill (no), whether these format choices belong in `userConfig` (no, they are
team-shared and belong in a consumer convention doc), and whether Mermaid's C4 support is fit for
the system scope (no, it is experimental).

## Type and contract inventory

This lane introduces no runtime types. Every artifact it changes is Markdown that a model reads:
skill bodies, a convention owner document, and a registry table. What it does introduce is three
contracts, and those are the reason this file records Tier B rather than Tier C.

1. **Two convention keys**, their allowed values, and their defaults. Owned by a new convention
   document; consumed by five skills across three plugins.
2. **The EARS pattern tag**, written at acceptance-criteria capture and detected at verification.
   A bracketed prefix on the criterion line.
3. **The design-artifact scope label**, written when a design artifact is emitted and read when a
   slice body is composed, so artifact-to-slice matching is a lookup rather than prose inference.

## Threads resolved in session, not by the Brief

Four threads were open after the Brief and were settled with the operator before the plan body was
authored. They are recorded in PLAN.md's decisions table with their bases. In summary: the owner
document is one folder under the conventions directory carrying both keys, with one registry row
per key; the consumer's own declaration of those keys is a separate artifact that by the config
cascade lives in the consuming repository rather than here; the EARS tag is a bracketed prefix; and
the design-artifact scope becomes an explicit label rather than something inferred from prose.

## What would reopen design

A consumer needing to set the two keys independently of one another, which would break the
single-surface assumption. Or a second artifact kind arriving for a design scope, which would turn
the scope-to-artifact mapping from a function into a relation and change the matching contract in
the third listed item above.
