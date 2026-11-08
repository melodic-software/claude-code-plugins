# Issue conventions

The shape of a well-formed tracker item: title, body, type, labels, close reason, and the
dependents a close must re-point. This document is the **single source of truth for the
dependents step**; for the rest it **points** at the existing owner rather than restating it, so
each of those rules stays in one place.

## Title

Read [`issue-house-style.md`](issue-house-style.md) before filing or retitling an item and follow
what it resolves. A child-of relationship is recorded as a native sub-issue edge, **never** as a
title suffix.

When folding a member into an umbrella, treat the sequence as **one atomic action**: post the
membership comment on the item, post the matching membership comment on the umbrella issue, record
the `blocked-by` edge, then strip the raw marker. Never stop after the item-side comment alone
(#633).

A recurring maintenance item's title is its schedule row's `title`. The title never links an item
to its schedule row; the [recurring marker](#recurring-marker) does.

### Recurring marker

A recurring item's body carries one line, on its own, that names its schedule row's `id`:

```text
<!-- recurring-schedule id=<id> -->
```

An item matches a row when it carries the resolved `recurring-maintenance` label
([`label-taxonomy.md`](label-taxonomy.md) "Canonical roles") **and** its body has that line with
the row's `id`, exactly. Never match by title: a title edit cannot break the link, and a row whose
title is a prefix of another's cannot claim the other's item. `track add --recurring` writes the
line; the `due`, `recheck`, `done`, `audit` and `setup` flows and `work`'s candidate discovery read
it. The line must appear alone on its line; the same text inside a sentence is not a marker. An
open recurring item with no marker matches no row: report it for retitling and a marker, never
guess its row from the title.

## Body

Follows the `track add` "Build body" template: the default skeleton, or the agent-brief shape for
autonomous-eligible items. See [`../skills/track/actions/add.md`](../skills/track/actions/add.md)
"Build body" and [`agent-brief.md`](agent-brief.md); not restated here.

## Type and labels

The issue type resolves through `track add`'s type-resolution step (native Issue Type on org repos,
`type:` label otherwise). See [`../skills/track/actions/add.md`](../skills/track/actions/add.md)
"Resolve the issue type". Label axes and their grammar live in [`label-taxonomy.md`](label-taxonomy.md).

## Close reason

`completed` vs `not planned`: decided-against and superseded items take `not planned`; a duplicate
takes the provider's native `duplicate` reason where it has one, `not planned` otherwise. This follows the
`done` action's close discipline: [`../skills/track/actions/done.md`](../skills/track/actions/done.md).

## Dependents on close

Every close runs these steps first, so closing an item never frees an item that was waiting on
work still to come:

1. **List the open items it blocks** (provider mechanic; GitHub: the adapter's "Close item"
   section). None: close. A failed or partial read is not none: do not close.
2. **Name the carrier** of the closing item's work. Delivered (a `completed` close, or already
   implemented): no carrier, close with the edges as they are. Duplicate: the surviving item or
   items that hold the work each dependent waits on. Superseded, or scope moved or split into
   other items: the items that now carry it. Dropped with no carrier (won't fix, decided against):
   keep the edges, which keep each dependent blocked, and name the dependents in the closing
   comment so they are re-triaged. A dependent is never its own carrier.
3. **Add, then remove, then close.** For each dependent and carrier, add the edge through the seam:
   `bash "${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh" link-blocks <dependent> --blocked-by <carrier>`.
   Only after it lands, remove the dependent's edge to the closing item (provider mechanic, same
   section): a won't-do blocker keeps counting as open, so a stale edge would hold the dependent
   off the frontier for good (`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md`
   `blocked_by_count`). When any add or removal fails, do not close; report the item and the
   dependent.
