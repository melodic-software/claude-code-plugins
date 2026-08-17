# Topic-docs placement — where coupling artifacts land

How the `reduce` skill resolves the destination for its coupling ledger.

Implements the topic-docs convention:
<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/topic-docs/README.md#runtime-guards>.
The contract owns every general rule — tiers, schema, resolution order, slug spec, runtime
guards, no-project-root fallback, non-interactive/forked mode. This document records only
this plugin's deltas.

## What this plugin writes, per tier

| Artifact (writer) | Tier | Location (default) |
|---|---|---|
| `coupling-ledger.md` (`/coupling:reduce`) | Memory | `.work/<topic-slug>/` — never committed |

Memory tier because the placement questions resolve there: nothing downstream enforces
against the ledger, and it is read again — by the producer itself on the next run (resume is
the skill's whole iteration model) and by the user checking `status` — with that reader
scoped to this checkout. The ledger is a single file updated in place, not a timestamped
file per run: statuses inside it, not filenames, carry run-to-run history.

## Slug derivation

Delta from the contract's precedence: an explicit scope argument (slugified per the
contract's form rules) → the constant `coupling`. The branch-name rung is deliberately not
used — coupling reduction is repo-scoped and spans many short-lived branches, and a
branch-derived slug would fragment the one ledger successive runs must resume. Form and
collision rules are the contract's.

## Guards

The memory root's self-ignore guard applies on first write (verify-or-create `.gitignore`
with `*`, announced). The contract also defines **invalid roots at which the guard does not
run**; they are enumerated in its
[Runtime guards](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/topic-docs/README.md#runtime-guards)
section and deliberately not listed here, so this binding cannot drift from them. Create the
topic slice directory when absent.
