# Upstream drift: verification stamps and recheck triggers

## Contents

- [Boundary](#boundary)
- [A date is never authority](#a-date-is-never-authority)
- [Required parts](#required-parts)
- [The observability bar](#the-observability-bar)
- [When a trigger fires](#when-a-trigger-fires)
- [Reading the basis: the fetch route](#reading-the-basis-the-fetch-route)
- [Drift signal: content hashing, deferred](#drift-signal-content-hashing-deferred)
- [Enforceability](#enforceability)
- [Adopters](#adopters)
- [Why this name](#why-this-name)
- [Versioning](#versioning)
- [External authority](#external-authority)

Owner doc for **how this repository records a fact or decision derived from a source it does not
own**, whether an official doc page, an upstream issue thread, or a probed platform behavior, so the record
stays honest as the upstream moves. One name and one shape: our decision in our own words, a
**pointer** to the exact upstream section, an **as-of date**, and a **recheck trigger**, the stated
observable event that obliges re-deriving the record. The upstream text itself is never stored.

The fleet previously practiced this in five-plus places under four names: "recheck triggers"
([hook-config-delivery](../hook-config-delivery/README.md)), "revisit triggers"
([ecosystem-commands](../ecosystem-commands/README.md), the
[migration playbook](../../migration-playbook.md)), "re-trigger" (the migration playbook again, on a
plugin-acceptance review record), "re-derivation triggers"
([loop-lane](../loop-lane/README.md)), with no shared definition of what a trigger must contain
and no statement of what makes one checkable. Under the
[convention registry](../../plugin-philosophy.md#convention-registry)'s one-owner-per-concern rule
that is the fragmentation this doc closes
([melodic-software/claude-code-plugins#1638](https://github.com/melodic-software/claude-code-plugins/issues/1638)).

## Boundary

`melodic-software/standards` `conventions/engineering/documentation-and-citations.md` owns the
general org-wide rule: upstream bodies are read-on-demand; prefer citing and fetching at read time
over storing a snapshot; a time-bound external claim in durable content needs a recheck trigger.
This doc takes the concept's name from it. This doc owns the repo-level specialization: the
required parts of a conforming record, the observability bar a trigger must clear, the drift signal
for the doc pages this fleet depends on most, and the enforceability classification. It does not
own:

- **In-repo duplication.** Facts this repo owns are governed by pointer-not-copy
  (`melodic-software/standards` `conventions/engineering/reference-dont-duplicate.md`) and, for
  byte-identical cross-plugin files, `scripts/cross-plugin-source-registry.txt`.
- **Synced materializations.** A `managed` component from the standards distribution drifts and
  reconciles through its reviewed sync-PR pipeline, not through stamps in prose.
- **Where a refreshed outcome lands.** Each versioned convention's own `CHANGELOG.md` records its
  rechecks' drift outcomes; this doc only requires that the outcome be recorded somewhere durable.

One deliberate tightening, made explicit so it never reads as drift: the org standard accepts "a
date, an automation, or a tracked task" as recheck-trigger forms. The upstream surfaces this fleet
restates move without notice on research-preview cadences, where a bare date decays silently, so
here a date alone does not qualify; a trigger names an observable event (see
[the observability bar](#the-observability-bar)). This narrows only what this repository accepts;
the upstream form list is the org standard's to change.

## A date is never authority

A dated verification stamp is an **as-of record**: it tells the reader when the decision was last
derived from its source, and nothing more. It never confers standing authority. A stale stamp reads identically
to a fresh one, and upstream surfaces move without notice: Claude Code changes its own conventions
between releases, sometimes with no version signal on the surface in question, and experimental
surfaces churn outright. The part of the record that matters is therefore the **trigger**, not the
date: anything depending on a volatile upstream specific carries a stated re-derivation event, or
it is drift waiting to happen. Before acting on any record, re-read the section its pointer names.
The as-of date is the ceiling on how current the decision can be, never a guarantee.

The discipline covers two record kinds, one shape:

- a **dependent decision**: something this repository does because of an upstream specific, with
  the pointer saying where that specific lives;
- a **recorded decision**: a deferral or rejection derived from upstream facts as they stood on a
  date, whose premises can rot the same way the facts can.

## Required parts

A conforming record stores no upstream text, quoted or paraphrased, not even one line (the one
named exception is [old-patterns mapping tables](#old-patterns-mapping-tables)). It carries:

```markdown
<our decision, in our words>
- **Pointer**: when <situation>, fetch <link to the exact upstream section> live.
- **As of**: YYYY-MM-DD
- **Recheck trigger**: <an observable event, never a bare date>
```

1. **The decision**: what this repository does or decided, in our own words. It may name the topic
   the upstream page covers; it never states what the page says about it.
2. **The pointer**: the official page URL with the anchor of the exact section, or the upstream
   issue. A reader who needs the specific reads it there, live. A blog post is never the pointer
   where a main docs section covers the topic: it appears only as a "correlate with \<blog link>"
   note beside that pointer. Where no docs page covers it yet, the record links the post as that
   note, says no docs page covers the topic as of the date, and its recheck trigger is a docs page
   starting to cover it, at which point the pointer moves there. In the one-line layout, that
   correlate note may take the Pointer line's place, keeping the **Pointer** label and the
   when-fetch wording and ending `no docs page covers <topic> as of <date>`.
3. **The as-of date**: when the decision was last derived from the page.
4. **The recheck trigger**: the observable event that obliges re-derivation.

This Pointer form is **context glue**: it names the situation in which a reader needs the upstream
section and sends them to read it live, and a record that uses it is a context-glue record. New
records use it. A Pointer in the earlier form, `for <topic>, see <link>.`, still conforms.

The parts may also sit on one line under the decision prose, and that layout conforms too:

```markdown
- **Pointer**: when <situation>, fetch <link> live. **As of**: YYYY-MM-DD. **Recheck trigger**: <event>.
```

Two cases have their own form:

- **A probed behavior** has no upstream page. The pointer names the probe (the script, pull request
  or issue holding its evidence), and the decision may state what the probe observed, in our words:
  the observation is ours, not the upstream's.
- **A source conflict** is recorded only as "pages X and Y disagree on topic T", with both links,
  the as-of date and a trigger. Neither page's position is restated.

When a surface needs the specific at run time, it fetches it from the pointer
([the fetch route](#reading-the-basis-the-fetch-route)). A catalog row that must fire without a
live fetch keeps its firing rule in our own words; the rule is our decision, not the page's text.

### Old-patterns mapping tables

One named exception admits upstream names into a file. A skill may carry a table mapping old API
or interface names to their current ones, but only inside an "Old patterns" section placed where
the skill-authoring guidance recommends one. The table holds names only, never descriptions of
behavior, and the section carries the record parts below it. Everywhere else the rule above holds.

- **Pointer**: for where the guidance recommends an "Old patterns" section, see
  <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#avoid-time-sensitive-information>.
- **As of**: 2026-10-01
- **Recheck trigger**: that section stops recommending an "Old patterns" section, or moves.

## The observability bar

A trigger names an event whose firing a reader, human or agent, can decide from evidence: a
release or changelog entry touching a named surface, an upstream issue changing state, a capability
shipping or leaving an experimental key, a second consumer appearing, a recurring occasion such as
each fleet audit. "Periodically", "when things change", or an unstated intention to revisit do not
qualify: a trigger whose firing cannot be checked is a date with extra words.

## When a trigger fires

A firing is a record-maintenance event, and the procedure follows what the trigger guards:

- **A pointer record.** Re-read the section the pointer names and re-derive the decision from what
  is actually there, never patching the record from memory. A section that moved gets a new
  pointer. Refresh the as-of date **with the outcome**, drift or no drift. On a versioned surface
  a drift outcome lands as a changelog entry; refreshing a date with no verdict change is no entry
  and no version bump.
- **A named trigger guarding an in-repo decision** ([Adopters](#adopters) says which rows these
  are). There is no pointer to re-read and no as-of date to refresh: re-derive the decision
  from the state the trigger names. The decision guarded is in-repo; the firing event can live
  anywhere, upstream included. Record the outcome durably where the decision lives: the record
  itself or the owning surface's changelog. A re-derivation that ends up depending on an upstream
  specific adopts the required parts in the refreshed record. The durable outcome is the part
  this kind shares with the pointer kind.

Whichever the kind, where re-derivation finds drift the changed value lands in the owning record,
never silently in a consuming surface.

### Read-time validation is not a firing

The standing rule to re-read a record's pointer before acting on it
([a date is never authority](#a-date-is-never-authority)) is per-use validation: it protects the
act, not the record, and a lookup that finds no drift obliges no edit anywhere. A record kept
current this way states divergence as its trigger, and "a read-time re-fetch finds the source no
longer matching the record" is an event decidable from evidence, so the divergence, never the
lookup, is what fires, and only a firing invokes the maintenance procedure above.

## Reading the basis: the fetch route

Re-reading the section a pointer names is the first step of every firing above, so **how** the page is read is
part of the contract. A summarizing fetch of a long docs page is not a read of that page: it
truncates, and a summarizer asked what the page contains then answers from the truncated span. That
answer is indistinguishable from a genuine absence, so a truncated fetch does not merely fail. It
manufactures drift that is not there. `env-vars` produced exactly that false negative on three
independent fetches, each stopping before the `CLAUDE_CODE_MAX_*` range and each reporting those
rows missing ([#2182](https://github.com/melodic-software/claude-code-plugins/pull/2182)).

Three rules bind every read, whichever rung it comes from:

- **No read, no verdict.** A verdict rests on the text read, not on a paraphrase or a summary of
  it. A verdict of "current" names the span it matched in the run's working data; the span never
  enters the record.
- **A truncated read supports no absence claim, ever.** If the fetch stops short, say so and mark
  the item unverified. "Not in the response" is never "not on the page". The reader cannot tell
  those apart, which is the entire failure this rung ladder exists to prevent.
- **An absence claim names the page it was checked against, and reaches no further.** A term missing
  from one page is missing from *that page*; the product may document it elsewhere, under other
  wording. Searching one page and stating the result about Claude Code is the same false negative
  one scope up. See [the scope of an absence](#the-scope-of-an-absence).

### The rungs

| Rung | Route | What it yields |
|---|---|---|
| 1: primary | `curl` the raw-markdown channel: append `.md` to the page URL (`https://code.claude.com/docs/en/<slug>.md`), write to a file, and search the file locally | Verbatim bytes, no summarizer, no truncation |
| 2: primary, degraded | The `.md` channel fetched through a summarizing tool, or the rendered HTML page | Truncates on long pages; usable only for a page short enough to arrive whole, and the read must show it arrived whole |
| 3: mirror | A verbatim third-party mirror of the same docs, with the freshness step below | Verbatim text, **one rung below a primary read**; the record says so |

`lib/fetch-docs.sh` is the rung-1 implementation. A plugin carries it as `scripts/fetch-docs.sh`,
and `scripts/sync-fetch-docs.sh` keeps every carried copy identical to `lib/`. It reads a page
verbatim to a file and writes a manifest, and it applies the identity check
[below](#a-200-does-not-mean-you-got-the-page-you-asked-for) as the **index-listed identity rule**:
a slug the publisher's index does not list is unread, never fetched. A **publisher profile**
(`--profile`, default `anthropic`) names the index, the path prefix, the raw channel and the content
types. The Anthropic profile is the default. A page whose channel does not resolve as the profile
declares is recorded unread with a reason, so the reader drops a rung and says so; the script never
falls back to another channel itself.

Rung 1 is the default. A probe against `env-vars` on 2026-08-10 showed the raw channel returning
the whole page, including the rows the summarizing fetches had dropped, and two fetches seconds
apart hashing identically. That same fetch re-confirmed the header finding below: `Last-Modified`
came back equal to `Date`.

The route is not new here; it is **hoisted from two surfaces that each derived it independently**.
`/harness-ops:changelog`'s read-actions context carried it page-scoped ("`curl` the
`.md` and slice locally … Never report a version 'absent from the changelog' on a truncated
fetch"), and `/knowledge:docpage-digest`'s Anthropic publisher profile carried it claim-scoped,
binding any absence-establishing fetch to the raw `.md` channel with `curl` plus a recorded length,
on the asymmetry that "a truncated fetch cannot fabricate a PRESENCE, only an ABSENCE", after two
of its runs asserted a false absence exactly this way. Two independent derivations of one rule is
the signal that it wants an owner. Per the
[convention registry](../../plugin-philosophy.md#convention-registry)'s one-owner-per-concern rule,
the general form belongs in this doc and those surfaces keep their page-specific detail.

**The `.md` channel is per-page, not universal.** `docpage-digest`'s profile records that a
raw-markdown channel working for one doc can 404 for another, so a run verifies the channel for the
page it is reading and drops a rung when it does not resolve.

### A 200 does not mean you got the page you asked for

A rung-1 fetch can return `200`, `text/markdown`, and a complete untruncated body that is
**someone else's page**. A retired slug is silently aliased to its successor: no redirect, no
`Location` header, no notice in the body. A probe on 2026-08-11 found
`https://code.claude.com/docs/en/slash-commands.md` returning `200` with a body **byte-identical to
`skills.md`**, while the rendered URL reported `0` redirects. This is not a catch-all: an invented
slug (`nonexistent-page-xyz.md`) returned a clean `404`, so the alias is specific to slugs that once
existed.

The failure this produces is worse than truncation, because truncation at least yields text you can
see is short. Here a search for a term the *requested* page owns comes back empty against a full,
healthy-looking body, a false absence carrying every outward sign of a good read. **Absence is only
ever assertable against a page whose identity was checked**, which makes identity part of rung 1
rather than a nicety.

Two checks, both cheap, and a run does them before it trusts a body:

- **Confirm the slug is canonical against `https://code.claude.com/docs/llms.txt`.** It lists the
  live pages, so a slug the index does not carry is retired or renamed. That alone flags the
  alias. Verified across ten slugs on 2026-08-11: the nine live ones each appear as
  `docs/en/<slug>.md`; `slash-commands` appears in no such entry (only an unrelated
  `agent-sdk/slash-commands`), which is exactly the one that aliased.
- **Read the body's own first heading before trusting it.** A page says what it is in its first
  heading. A heading for a different page than the one you asked for ends the read; a title that
  merely differs in wording from the slug does not.

A slug missing from `llms.txt` is not automatically a dead end: it may have been renamed, and the
index is the place to find the successor. Fetch the successor and cite **that** slug, rather than
the retired one that happens to still serve bytes. Because the alias is silent, an unchecked
citation of a retired slug keeps working indefinitely while pointing somewhere its author never
read, and the day the alias is dropped it becomes a `404` on a claim nobody re-derived.

Credit where the fleet found it: this surfaced in the 2026-08-11 stamp re-verification
([#2187](https://github.com/melodic-software/claude-code-plugins/pull/2187)), where a per-page
channel check noticed `slash-commands.md` serving `skills` content and recorded that a `200` is not
proof the page is the one you wanted.

### The scope of an absence

A verified absence is a fact about **the text searched**, never about the product. Two moves break
it, and both produce a claim that reads as researched:

- **Widening the subject.** Searching `hooks` and concluding "Claude Code has no X" asserts
  something about every page not searched. The honest form names the corpus: "not documented on
  `hooks`", or, if the sweep really covered the index, "not documented on any page listed in
  `llms.txt` as of `<date>`", which is a much larger and much more expensive claim.
- **Searching the phrase instead of the capability.** A literal string can be absent while the
  thing it names is documented in other words on the same page. Worked instance, 2026-08-11 on
  [`hooks`](https://code.claude.com/docs/en/hooks): the phrase "verbose hooks" appeared **zero**
  times, yet the page documented two separate ways to see more hook output, in other words. A
  phrase search would have returned nothing and licensed "no verbose hooks toggle exists". That
  was false, from a complete, untruncated read of the right page.

So an absence claim states the corpus and the terms tried, and a claim that a *capability* is
missing searches the capability's plausible vocabulary, not one phrasing of it. This bit the fleet
for real: the same 2026-08-11 sweep advertised a nonexistence claim of exactly this shape and
withdrew it on re-check ([#2190](https://github.com/melodic-software/claude-code-plugins/pull/2190)).
The conclusion it supported survived on a different premise. That is worth stating as its own rule,
since it is the reason to care: **a sound conclusion resting on a false premise is not safe, it is
fragile**, because the next reader who checks the premise discards the conclusion with it. Fix the
premise and keep the conclusion; never keep a premise because the conclusion it props up is
convenient.

### The mirror rung and its freshness step

A mirror read is admissible only when it is **verbatim** and its currency is **corroborated against
the page's own content**, never against the mirror's self-reported sync time alone, which is a
claim by the party whose freshness is in question. The corroboration names a fact that only a sync
later than some known upstream change could carry, and the record names that release. The worked
instance: `ericbuess/claude-code-docs` `docs/env-vars.md` was accepted because it carried a change
from Claude Code v2.1.224, which no earlier sync can contain.

A record resting on a mirror **says on its face that it is one rung below a primary read**, and
states retirement of that basis as part of its trigger: a later primary read of the same range
replaces the mirror basis and the record is refreshed to say so. That is not hypothetical. The
`discipline` `sweep-all` record written this way on 2026-08-10 fired and was refreshed to a primary
basis the same day, by the rung-1 fetch above.

### Currency of a primary read

The docs serve no per-page content date ([below](#drift-signal-content-hashing-deferred)), so the
honest currency statement for a rung-1 read is the fetch itself: *fetched live from `<url>` on
`<date>`; upstream publishes no per-page content date.* Nothing stronger is available, and a stamp
that implies otherwise is the overclaim this doc's [first rule](#a-date-is-never-authority) forbids.

## Drift signal: content hashing, deferred

There is no mechanical per-page change signal on the official Claude Code docs: the raw-markdown
endpoints serve no `ETag`, and `Last-Modified` is a deploy/serving stamp rather than a per-page
content date (verified 2026-07-26 by header inspection of three `code.claude.com/docs/en/*.md`
endpoints fetched seconds apart, each returning a `Last-Modified` matching its own fetch time;
recheck trigger: those endpoints start serving an `ETag` or a stable per-page `Last-Modified`).
**Content hashing of a fetched page body is therefore the only viable mechanical drift signal** for
these pages.

The fleet **defers** storing hashes: no upstream-page hash store exists today, and every recheck is
a manual re-fetch at trigger time. Recheck trigger for the deferral itself: a stale stamp causes a
real defect a stored hash would have flagged, or a fleet audit completes without re-fetching every
stamped claim in its scope, at which point a hash store becomes its own designed issue, not an
inline addition here.

## Enforceability

Classified per `melodic-software/standards` `conventions/engineering/enforceability-tiers.md`:

| Judgment | Tier |
|---|---|
| Every verification stamp carries a recheck trigger | **Deterministic** by nature (a presence check) once stamps and triggers use greppable forms. The candidate check, flagging any `Verified <date>` line or row whose surface states no trigger, is named but **not built**: per the tiers doc's routing rule, worth-mechanizing defaults to "not yet". Build trigger: a trigger-less stamp lands on `main` again after this doc. |
| The trigger clears the observability bar | **Reasoning-only**. Whether an event is decidable from evidence is a judgment about meaning. |
| A trigger has fired | **Reasoning-only** today; **detect-then-judge** if a hash store lands: the hash mismatch flags, and judgment decides whether the page change touches the claim, because a changed page is not a changed fact. |

### Recorded decision: an adoption gate is deferred, and the check named above would have missed the case that prompted it

**Decided 2026-08-12 UTC: no CI gate is built for adoption of this convention, in either candidate
shape.** Recorded as a decision rather than left implicit, because this repo's `*-gate` CI pattern
is the standing precedent for promoting a convention to a check and the question was asked directly
([#2273](https://github.com/melodic-software/claude-code-plugins/issues/2273)).

The premise that settles it: the candidate check named in the table above, *flag any
`Verified <date>` line or row whose surface states no trigger*, **would not have caught
[#2207](https://github.com/melodic-software/claude-code-plugins/issues/2207)**, the finding that
prompted the question. That surface carried no stamp at all, so a stamp-anchored grep had nothing to
match on. The named check is shaped for a *half-conforming* record; the failure that actually ships
is the *zero-part* one. It therefore stays named-not-built on its own build trigger, unchanged, and
is not evidence that mechanization covers this class.

The zero-part shape has no deterministic check available. Deciding whether a sentence restates an
upstream-owned specific, as against an in-repo fact, a description of the surface's own behavior,
or ordinary prose, is a judgment about meaning, which is **reasoning-only** under the tiers doc. A
grep for harness vocabulary (`PostToolUse`, `${CLAUDE_*}`, `settings.json`, and so on) fires on
every correct citation and every in-repo mention alike, and a gate whose false-positive rate forces
routine suppression trains authors to bypass it. That is worse than no gate, because it converts a
real signal into noise with an approved silencer.

- **Pointer**: for the reasoning-only tier and the worth-mechanizing routing rule, see
  `melodic-software/standards` `conventions/engineering/enforceability-tiers.md`; the worked
  instance is above.
- **As of**: 2026-08-12
- **Recheck trigger**: a third unstamped upstream-fact carrier reaches `main` after this decision
  (two are already on the record: `plugin-quality`, corrected in its 0.4.0, and `architecture`,
  whose false claim was removed in its 0.5.1), **or** a detector is demonstrated that separates an
  upstream restatement from an in-repo one without a suppression list. Either event reopens the
  shape question; neither is a date.

## Adopters

The rows below were migrated at this contract's 1.0.0 to the single name, each citing this doc with
content intact. **A row added after 1.0.0 is a surface that adopted on touch**, the mechanism the
note under the table already requires, and names the release that added it, so the table never
implies a surface was migrated at 1.0.0 when it was not.

**A surface is tabled only once it actually conforms.** The third column is a promise to a reader
about what they can rely on, so a carrier *known* to be unstamped belongs in a tracked issue, never
in a row: tabling it would assert the very thing the reader would then not get. The fleet's open
carriers are recorded that way in
[#2297](https://github.com/melodic-software/claude-code-plugins/issues/2297).

The rows are not all the same thing, and the table says which is which. A **conforming record**
carries the [required parts](#required-parts) for a decision that depends on something
upstream-owned. A **named trigger** shares the canonical name, the observability bar, and
[its own firing procedure](#when-a-trigger-fires), but guards an in-repo decision: in scope for the
name, outside the pointer requirement, which binds only records that depend on something
upstream-owned. This narrows what a row advertises; it does not widen the contract to fit its
exceptions.

At 2.0.0 the required parts changed from a restated claim plus its basis to our decision plus a
pointer. The rows below were converted with that release. Records elsewhere still in the 1.x
four-part shape are tracked in
[#5684](https://github.com/melodic-software/claude-code-plugins/issues/5684) and adopt the new shape
on touch.

| Surface | Was | What a reader can rely on |
|---|---|---|
| [hook-config-delivery](../hook-config-delivery/README.md) §Recheck triggers | already the canonical name | Conforming records: per-fact pointer, a per-row verified version and date, and fact-scoped event triggers. |
| [loop-lane](../loop-lane/README.md) §Versioning | "Re-derivation triggers" | Conforming records: dated pointers; drift outcomes recorded in its changelog. |
| [plugin-philosophy](../../plugin-philosophy.md) component-stances staleness disclaimer | unlabeled discipline | Conforming records: per-row decision, linked section, and as-of date; the re-read-before-acting rule is [read-time validation](#read-time-validation-is-not-a-firing), and every row's stated trigger is a read diverging from the row. |
| [plugin-philosophy](../../plugin-philosophy.md#recorded-gate-runs) recorded gate runs | new with this table | Conforming records of the second kind: **recorded decisions**, one per platform surface the Native-first adoption gate has been run against, carrying an adopt/defer/decline verdict, a pointer to the upstream section it rests on, and a trigger written per row rather than the generic divergence-at-read. A verdict is re-derived when its own trigger fires, not on any read that differs. |
| [official-docs](../../official-docs.md) staleness warning and per-row verified dates | unlabeled discipline | Conforming records: same shape as the component-stances table: link + date, divergence-at-read as the stated trigger. |
| [migration-playbook](../../migration-playbook.md) decision records | "Revisit trigger", and "Re-trigger" on the plugin-acceptance review record | Named triggers only: the org-internal records (e.g. the ratification and plugin-acceptance review records) are named triggers; the skill-quality retrofit record states "no recheck trigger" by design, decided out, so nothing fires. The dated component-decision records keep the 1.x shape and are tracked in #5684. |
| [ecosystem-commands](../ecosystem-commands/README.md) task-runner deferral | "Revisit triggers" | Named triggers only: an undated in-repo deferral with no upstream pointer. |
| `/ai-slop:audit`, the tell catalog it loads, §Upstream-drift record | new with 1.5.0 | Conforming record: a revision-pinned pointer to the Wikipedia source page (`oldid`), as-of date, and a recurring recheck trigger: each `ai-slop` release and each fleet audit, chosen over per-revision after measuring the page at 50+ edits/week. |
| `/docs-hygiene:write-for-humans`, the source records it loads | new with docs-hygiene 0.18.0 | Conforming records: one pointer record per external writing standard the skill falls back to, each carrying the pointer, as-of date, and an observable recheck trigger: a publication event for an edition-pinned standard, a page-content divergence for a continuously edited one. The record names which. |

Elsewhere the name binds on touch: living surfaces still saying "revisit trigger", "re-trigger",
"re-derivation trigger", or "what would reopen it" (several plugin reference docs already use the
canonical `## Recheck triggers` heading) adopt the canonical name, the observability bar, and their
kind's firing procedure the next time they change; a surface depending on an upstream-owned
specific additionally adopts the required parts and drops any restated upstream text. **History
is never rewritten**: `CHANGELOG.md` entries, dated audit records, and ADR sections keep the
wording they shipped with; a new ADR uses the canonical name going forward.

## Why this name

"Recheck trigger" is what the org standard (`documentation-and-citations.md` §"Time-bound external
claims need a recheck trigger") already calls the concept. A repo-level owner doc renaming the
rule it specializes would fork the vocabulary one level up. It is also the majority name in this
fleet, and the `## Recheck triggers` heading is the one the docs-hygiene plugin's audit-noise
section-exemption list already recognizes.

## Versioning

This contract is versioned in [`CHANGELOG.md`](CHANGELOG.md). Changing a required part, the
canonical name, or an enforceability verdict is a major bump; additive guidance is a minor bump;
docs-only clarification is a patch.

## External authority

- `melodic-software/standards` `conventions/engineering/documentation-and-citations.md`: the
  org-wide read-on-demand rule and the concept's name.
- `melodic-software/standards` `conventions/engineering/enforceability-tiers.md`: the tier
  vocabulary and the routing rule.
- `melodic-software/standards` `conventions/engineering/reference-dont-duplicate.md`: the in-repo
  counterpart this doc's boundary defers to.
