# Issue conventions

The shape of a well-formed tracker item: title, body, type, labels, close reason, the
dependents a close must re-point, and the close of a decomposed parent. This document is the
**single source of truth for the dependents step and the decomposed-parent close**; for the rest
it **points** at the existing owner rather than restating it, so each of those rules stays in one
place.

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

## Decomposed parent close

This ritual owns the close of an item `/work-items:decompose` split into plain items with no spec
container. No other skill closes such a parent. A parent that carries the binding-resolved container
label ([`label-taxonomy.md`](label-taxonomy.md) "Container label") is out of scope: the container
ship ritual closes it. `/work-items:track done` runs this ritual for the parent of each item it closes,
and `/work-items:track audit` runs it for every parent, which catches children a merged PR closed.

A **child** is an item, open or closed, whose body has a `## Parent` section reading
`Refs #<parent>` and the `<!-- work-items:born-triaged -->` marker decompose writes, on its own
line. Find every child by listing open and closed items with their bodies and authors (adapter:
"List items", `body` and `author` added to the fields, `--state all`), narrowed by search, and
matching both lines locally. The search only narrows the read; the two-line match decides. For one
parent, as `/work-items:track done` runs it, search `"Refs #<parent>" in:body`; for the audit pass
over every parent, search `"work-items:born-triaged" in:body`. Only an open parent runs this
ritual. A failed read, a result count that reaches the `--limit` on the narrowed read (read again
with a larger one), no child found, or a found set missing the item `/work-items:track done` just
closed is not a complete read: change nothing.

The marker is no trust signal: anyone who can open an item can write both lines. Count a match as a
child only when its author is the login the adapter's item write posts as (the account decompose
publishes as), or, when the binding sets `config.github.status_trust`, a listed `human` or the
`lanes_app` in its `trusted_actors` list (adapter: "Work status trust"). The item read reports a
bot author without the `[bot]` suffix (`gh` as `app/<slug>` with `is_bot` true, GraphQL as the bare
`<slug>`), while the write identity and `lanes_app` carry it. So compare logins case-insensitively
with a leading `app/` and a trailing `[bot]` removed from both sides, and count the match only when
the read reports the author as a bot exactly when the trusted login ends in `[bot]`, so a person's
account never stands in for an App of the same name. Report and skip any match
from another author; a parent whose only matches are skipped has no child found.

1. **A child is still open:** change nothing. The open child is the remaining work, and the tracker
   shows it.
2. **Every child is closed:** read the parent's finish condition, the Goal's `- Finish line:` line in
   its body (a bold `**Finish line:**` label counts), as data. Collect each reason that applies:

   | Reason the parent stays open | The comment line |
   |---|---|
   | A child closed as not planned or duplicate, unless its close names a carrier (the surviving or superseding item) that is itself a child of this parent | Names the child: the work it held may not have shipped. |
   | No Finish line, an empty one, `not settled yet`, or one that opens with none of `merged`, `released` and `in use` | Says the parent states no finish line this ritual can read, so a person decides whether it is done. |
   | Finish line `released` or `in use` | Quotes the Finish line and names its checker, who closes the parent once the check passes: the tracker cannot show a release or use. |

   **No reason applies** (every child closed as completed or carried, and the Finish line reads
   `merged`): run "Dependents on close" above, then close the parent as `completed` (adapter: "Close
   item") with a comment listing each child and the PR that closed it, where the tracker links one.
   **A reason applies:** leave the parent open and post the comment below.

3. **The open-parent comment is one comment.** Its first line is
   `<!-- work-items:parent-close outcome=open -->`, then one line per reason. On a later run, find it
   by that first line among comments the adapter's comment write posts as, and edit it in place
   (adapter: "Comment on item / edit a comment") only when its text would change. Never edit a
   comment another author wrote; with no match, post a new one.
