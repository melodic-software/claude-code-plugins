# The file-name findings artifact

The whole interface between `audit-file-names` and `realign-file-names`. The
audit writes it and mutates nothing else; the realign is the only writer of an
operator's decision into it. Both skills read this document, and neither
restates it.

## Deliberately not `type: review-findings`

This artifact declares `type: docs-hygiene-file-name-findings` and must never
declare `type: review-findings`, nor be written where an auto-apply relay scans
for that type.

A findings file of that type is located by frontmatter alone, with nothing
authenticating the writer, so it is auto-applicable by construction. Every
rename this artifact proposes moves a tracked file and rewrites references
across the tree behind one human acceptance each. Routing them through an
auto-apply relay would launder exactly the gate that makes the pair safe to
point at a repository nobody has reviewed.

## Where it lives

In the repository's memory tier, resolved through the plugin's topic-docs
binding ([`../reference/topic-docs.md`](../reference/topic-docs.md)), never
committed. Resolve the home; never hardcode the documented default's shape.

Two properties the contract fixes:

- **The `branch:` frontmatter proves which branch the artifact belongs to**,
  never the directory it sits in. Two branch names can slug to one directory. A
  consumer finding a mismatch refuses rather than proceeding.
- **One stable filename per home, rewritten in place.** A re-audit merges into
  the existing file; the run timestamp lives in frontmatter.

## Frontmatter

```yaml
---
type: docs-hygiene-file-name-findings
schema: 1
date: <ISO-basic UTC, colon-free: YYYYMMDDTHHMMSSZ>
branch: <branch at audit time, or detached-<short-sha>>
head: <HEAD at audit time>
config: <how the configuration was resolved>
roots: <the roots inventoried>
files_scanned: <n>
findings: <n>
collisions: 0
---
```

`head` is recorded for the evidence trail and is **never checked**. A consumer
commits between accepted renames, so an equality test on it would block the
walk after the first commit. What the realign checks per record is narrower and
exact: the old path is still in the index, and each site still carries the old
name.

`collisions` is always `0` in a written artifact. A case-only collision refuses
the whole plan and nothing is written, because two paths differing only by case
cannot coexist on a case-insensitive checkout.

## Finding record

One section per rename, ranked by site count, most-cited first.

```markdown
### FN-9a1c4e70 `docs/PLUGIN-PHILOSOPHY.md` to `docs/plugin-philosophy.md`

- **Status:** pending
- **Collision:** none
- **References:** 61 site(s) in 48 file(s)
- **By tier:** 54 current (edit), 6 historical (report), 1 released (report)
- **Needs a human:** 2 site(s) marked review
- **Generated touched:** docs/architecture/landscape.json
- **Sites:**

| file | line | form | tier | action | excerpt |
|---|---|---|---|---|---|
| `README.md` | 12 | md-link | current | edit | ... |
```

**The id is derived from the old path**, as `FN-` plus the first eight
characters of its git object hash. Rank decides presentation order and nothing
else. An id that shifted when a re-audit reordered the plan would make an
operator's "apply FN-005" name a different file than the one they read, and a
record whose id moved carries no decision forward.

**Every site carries its own action.** The realign never re-derives a form, a
tier, or an action; it applies what this record says, after checking the site
still matches.

| Action | Meaning |
|---|---|
| `edit` | the site's tier allows this reference shape to be rewritten |
| `report` | the site's tier freezes this shape; it is listed and left alone |
| `review` | an ambiguous bare stem; a human decides before anything is written |
| `skip` | a `sweep_exclude_sites` entry; never edited |
| `regenerate` | inside a generated file; the record's command rebuilds it |

## Status

`pending` moves to `accepted`, `applying`, `applied`, `declined`, or `blocked`.
Every forward move is written by the realign and by nothing else, because every
one of them records an operator's decision.

`applying` exists because a rename is not one operation. The realign writes it
before `git mv` and clears it after the last edit, so an interrupted run is
**resumed** rather than blocked: the maps are idempotent, and an old path that
is gone while the new path is present with `applying` is a half-finished apply,
not a drifted tree.

## Re-audit merge

A re-audit reads the artifact, matches records by id, and carries every status
forward. A record whose offender no longer exists is dropped. A declined finding
is never resurrected as `pending` by a re-run: re-proposing a decision the
operator already made is the fastest way to train them to rubber-stamp.

`--replace` starts a fresh artifact and says so.

## Decline durability

The artifact is memory tier: branch-keyed, checkout-local, and gone with the
memory root. A decline written only there is a judgment the next checkout never
sees.

The realign therefore OFFERS, and never takes, a second write: an entry under
`file_names.exempt_paths` in the tracked `.claude/docs-hygiene.json`, which git
carries to every checkout. `exempt_paths` already means "never renamed", so a
decline that should outlive this branch has a home that needs no new mechanism.
Declining one finding and agreeing never to be asked again are two decisions,
and only the operator makes the second.
