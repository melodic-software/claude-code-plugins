# Upstream drift — verification stamps and recheck triggers

Owner doc for **how this repository records a fact or decision derived from a source it does not
own** — an official doc page, an upstream issue thread, a probed platform behavior — so the record
stays honest as the upstream moves. One name and one shape: a dated **verification stamp** paired
with a **recheck trigger**, the stated observable event that obliges re-deriving the record.

The fleet previously practiced this in five-plus places under four names — "recheck triggers"
([hook-config-delivery](../hook-config-delivery/README.md)), "revisit triggers"
([ecosystem-commands](../ecosystem-commands/README.md), the
[migration playbook](../../MIGRATION-PLAYBOOK.md)), "re-trigger" (the migration playbook again, on a
plugin-acceptance review record), "re-derivation triggers"
([loop-lane](../loop-lane/README.md)) — plus the unlabeled "What would reopen it"
([topic-docs](../topic-docs/README.md)) — with no shared definition of what a trigger must contain
and no statement of what makes one checkable. Under the
[convention registry](../../PLUGIN-PHILOSOPHY.md#convention-registry)'s one-owner-per-concern rule
that is the fragmentation this doc closes
([melodic-software/claude-code-plugins#1638](https://github.com/melodic-software/claude-code-plugins/issues/1638)).

## Boundary

`melodic-software/standards` `conventions/engineering/documentation-and-citations.md` owns the
general org-wide rule — upstream bodies are read-on-demand; prefer citing and fetching at read time
over storing a snapshot; a time-bound external claim in durable content needs a recheck trigger —
and this doc takes the concept's name from it. This doc owns the repo-level specialization: the
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
restates move without notice on research-preview cadences, where a bare date decays silently — so
here a date alone does not qualify; a trigger names an observable event (see
[the observability bar](#the-observability-bar)). This narrows only what this repository accepts;
the upstream form list is the org standard's to change.

## A date is never authority

A dated verification stamp is an **as-of record**: it tells the reader when the claim last matched
its source, and nothing more. It never confers standing authority — a stale stamp reads identically
to a fresh one, and upstream surfaces move without notice: Claude Code changes its own conventions
between releases, sometimes with no version signal on the surface in question, and experimental
surfaces churn outright. The load-bearing part of the record is therefore the **trigger**, not the
date: anything restating a volatile upstream specific carries a stated re-derivation event, or it
is drift waiting to happen. Before acting on any stamped claim, re-fetch the cited basis — the
stamp is the ceiling on how current the claim can be, never a guarantee.

The discipline covers two record kinds, one shape:

- a **verified-fact stamp** — a restated upstream specific ("verified 2026-07-17 against \<page>");
- a **recorded decision** — a deferral or rejection derived from upstream facts as they stood on a
  date, whose premises can rot the same way the facts can.

## Required parts

A conforming record carries four parts:

1. **The claim or decision** — what exactly was verified, or what was decided and on what premise.
2. **The basis** — the specific source it was derived against: the official page URL (with anchor
   where one exists), the upstream issue, or the probe/method for an empirical finding. "Verified"
   with no stated basis is not re-checkable.
3. **The as-of date** — when the derivation happened.
4. **The recheck trigger** — the observable event that obliges re-derivation.

Prefer the pointer: where a surface can defer to the live source at read time, cite it and restate
nothing — then no stamp is needed at all. The four-part record is the fallback for surfaces that
must restate a volatile specific to function.

## The observability bar

A trigger names an event whose firing a reader — human or agent — can decide from evidence: a
release or changelog entry touching a named surface, an upstream issue changing state, a capability
shipping or leaving an experimental key, a second consumer appearing, a recurring occasion such as
each fleet audit. "Periodically", "when things change", or an unstated intention to revisit do not
qualify: a trigger whose firing cannot be checked is a date with extra words.

## When a trigger fires

A firing is a record-maintenance event, and the procedure follows what the trigger guards:

- **A four-part record.** Re-fetch the cited basis and re-derive the claim or decision from what is
  actually there — never patch the record from memory. Refresh the as-of date **with the outcome**,
  drift or no drift. On a versioned surface a drift outcome lands as a changelog entry; refreshing
  a date with no verdict change is no entry and no version bump.
- **A named trigger guarding an in-repo decision** ([Adopters](#adopters) says which rows these
  are). There is no cited basis to re-fetch and no as-of date to refresh: re-derive the decision
  from the state the trigger names — the decision guarded is in-repo; the firing event can live
  anywhere, upstream included — and record the outcome durably where the decision lives: the record
  itself or the owning surface's changelog. A re-derivation that ends up restating an upstream
  specific adopts the four required parts in the refreshed record. The durable outcome is the part
  this kind shares with the stamped kind.

Whichever the kind, where re-derivation finds drift the changed value lands in the owning record,
never silently in a consuming surface.

### Read-time validation is not a firing

The standing rule to re-fetch a cited basis before acting on a stamped claim
([a date is never authority](#a-date-is-never-authority)) is per-use validation: it protects the
act, not the record, and a lookup that finds no drift obliges no edit anywhere. A record kept
current this way states divergence as its trigger — "a read-time re-fetch finds the source no
longer matching the record" is an event decidable from evidence — so the divergence, never the
lookup, is what fires, and only a firing invokes the maintenance procedure above.

## Reading the basis — the fetch route

Re-fetching a cited basis is the first step of every firing above, so **how** the page is read is
part of the contract. A summarizing fetch of a long docs page is not a read of that page: it
truncates, and a summarizer asked what the page contains then answers from the truncated span. That
answer is indistinguishable from a genuine absence, so a truncated fetch does not merely fail — it
manufactures drift that is not there. `env-vars` produced exactly that false negative on three
independent fetches, each stopping before the `CLAUDE_CODE_MAX_*` range and each reporting those
rows missing ([#2182](https://github.com/melodic-software/claude-code-plugins/pull/2182)).

Three rules bind every read, whichever rung it comes from:

- **No verbatim quote, no claim.** A record's basis is the text, not a paraphrase of it. A verdict
  of "current" states the quoted span it matched.
- **A truncated read supports no absence claim, ever.** If the fetch stops short, say so and mark
  the item unverified. "Not in the response" is never "not on the page" — the reader cannot tell
  those apart, which is the entire failure this rung ladder exists to prevent.
- **An absence claim names the page it was checked against, and reaches no further.** A term missing
  from one page is missing from *that page*; the product may document it elsewhere, under other
  wording. Searching one page and stating the result about Claude Code is the same false negative
  one scope up — see [the scope of an absence](#the-scope-of-an-absence).

### The rungs

| Rung | Route | What it yields |
|---|---|---|
| 1 — primary | `curl` the raw-markdown channel: append `.md` to the page URL (`https://code.claude.com/docs/en/<slug>.md`), write to a file, and search the file locally | Verbatim bytes, no summarizer, no truncation |
| 2 — primary, degraded | The `.md` channel fetched through a summarizing tool, or the rendered HTML page | Truncates on long pages; usable only for a page short enough to arrive whole, and the read must show it arrived whole |
| 3 — mirror | A verbatim third-party mirror of the same docs, with the freshness step below | Verbatim text, **one rung below a primary read**; the record says so |

Rung 1 is the default. It was verified against `env-vars` on 2026-08-10: `curl` returned
`text/markdown`, 361,797 bytes over 458 lines carrying 315 variable rows including the full
`CLAUDE_CODE_MAX_*` range, and two fetches seconds apart hashed identically
(SHA-256 `43a805b4cfffd9aae5e36cec42f3a271dc92ddead26db76cd401d61ff4048584`). That same fetch
re-confirmed the header finding below — `Last-Modified` came back equal to `Date`.

The route is not new here; it is **hoisted from two surfaces that each derived it independently**.
`plugins/claude-ops/skills/changelog/context/read-actions.md` carried it page-scoped ("`curl` the
`.md` and slice locally … Never report a version 'absent from the changelog' on a truncated
fetch"), and `/knowledge:docpage-digest`'s Anthropic publisher profile carried it claim-scoped,
binding any absence-establishing fetch to the raw `.md` channel with `curl` plus a recorded length,
on the asymmetry that "a truncated fetch cannot fabricate a PRESENCE, only an ABSENCE" — after two
of its runs asserted a false absence exactly this way. Two independent derivations of one rule is
the signal that it wants an owner. Per the
[convention registry](../../PLUGIN-PHILOSOPHY.md#convention-registry)'s one-owner-per-concern rule,
the general form belongs in this doc and those surfaces keep their page-specific detail.

**The `.md` channel is per-page, not universal.** `docpage-digest`'s profile records that a
raw-markdown channel working for one doc can 404 for another, so a run verifies the channel for the
page it is reading and drops a rung when it does not resolve.

### A 200 does not mean you got the page you asked for

A rung-1 fetch can return `200`, `text/markdown`, and a complete untruncated body that is
**someone else's page**. A retired slug is silently aliased to its successor: no redirect, no
`Location` header, no notice in the body. Verified 2026-08-11 —
`https://code.claude.com/docs/en/slash-commands.md` returns `200` with 82,668 bytes whose first
heading is `# Extend Claude with skills`, **byte-identical to `skills.md`** (both SHA-256
`a833dd5c96b9b111de0daec5fc6436e210c8cdc009e51306d32438746db0b5a5`), while the rendered URL reports
`0` redirects. This is not a catch-all: an invented slug (`nonexistent-page-xyz.md`) returns a clean
`404`, so the alias is specific to slugs that once existed.

The failure this produces is worse than truncation, because truncation at least yields text you can
see is short. Here a search for a term the *requested* page owns comes back empty against a full,
healthy-looking body — a false absence carrying every outward sign of a good read. **Absence is only
ever assertable against a page whose identity was checked**, which makes identity part of rung 1
rather than a nicety.

Two checks, both cheap, and a run does them before it trusts a body:

- **Confirm the slug is canonical against `https://code.claude.com/docs/llms.txt`.** It lists the
  live pages, so a slug the index does not carry is retired or renamed — that alone flags the
  alias. Verified across ten slugs on 2026-08-11: the nine live ones each appear as
  `docs/en/<slug>.md`; `slash-commands` appears in no such entry (only an unrelated
  `agent-sdk/slash-commands`), which is exactly the one that aliased.
- **Read the body's own first heading before quoting it.** `skills.md` and a live `<slug>.md` both
  say what they are on line 5. A heading that does not match the page you asked for ends the read;
  a title that merely differs in wording from the slug does not (`sub-agents.md` is titled "Create
  custom subagents", `costs.md` "Manage costs effectively" — both correct).

A slug missing from `llms.txt` is not automatically a dead end: it may have been renamed, and the
index is the place to find the successor. Fetch the successor and cite **that** slug, rather than
the retired one that happens to still serve bytes. Because the alias is silent, an unchecked
citation of a retired slug keeps working indefinitely while pointing somewhere its author never
read — and the day the alias is dropped it becomes a `404` on a claim nobody re-derived.

Credit where the fleet found it: this surfaced in the 2026-08-11 stamp re-verification
([#2187](https://github.com/melodic-software/claude-code-plugins/pull/2187)), where a per-page
channel check noticed `slash-commands.md` serving `skills` content and recorded that a `200` is not
proof the page is the one you wanted.

### The scope of an absence

A verified absence is a fact about **the text searched**, never about the product. Two moves break
it, and both produce a claim that reads as researched:

- **Widening the subject.** Searching `hooks` and concluding "Claude Code has no X" asserts
  something about every page not searched. The honest form names the corpus: "not documented on
  `hooks`", or — if the sweep really covered the index — "not documented on any page listed in
  `llms.txt` as of `<date>`", which is a much larger and much more expensive claim.
- **Searching the phrase instead of the capability.** A literal string can be absent while the
  thing it names is documented in other words on the same page. Worked instance, verified
  2026-08-11 on `hooks.md`: the phrase "verbose hooks" appears **zero** times, yet the page itself
  documents "Async hook completion notifications are suppressed by default. To see them, enable
  verbose mode with `Ctrl+O` or start Claude Code with `--verbose`", and separately
  "set `CLAUDE_CODE_DEBUG_LOG_LEVEL=verbose` to see additional log lines such as hook matcher
  counts and query matching". A phrase search would have returned nothing and licensed "no verbose
  hooks toggle exists" — false, from a complete, untruncated read of the right page.

So an absence claim states the corpus and the terms tried, and a claim that a *capability* is
missing searches the capability's plausible vocabulary, not one phrasing of it. This bit the fleet
for real: the same 2026-08-11 sweep advertised a nonexistence claim of exactly this shape and
withdrew it on re-check ([#2190](https://github.com/melodic-software/claude-code-plugins/pull/2190)).
The conclusion it supported survived on a different premise — worth stating as its own rule, since
it is the reason to care: **a sound conclusion resting on a false premise is not safe, it is
fragile**, because the next reader who checks the premise discards the conclusion with it. Fix the
premise and keep the conclusion; never keep a premise because the conclusion it props up is
convenient.

### The mirror rung and its freshness step

A mirror read is admissible only when it is **verbatim** and its currency is **corroborated against
the page's own content** — never against the mirror's self-reported sync time alone, which is a
claim by the party whose freshness is in question. The corroboration names a fact that only a sync
later than some known upstream change could carry, and the record states it. The worked instance:
`ericbuess/claude-code-docs` `docs/env-vars.md` was accepted because it carried the v2.1.224
removal of the 200-subagent-per-session cap, which no pre-v2.1.224 sync can contain.

A record resting on a mirror **says on its face that it is one rung below a primary read**, and
states retirement of that basis as part of its trigger: a later primary read of the same range
replaces the mirror basis and the record is refreshed to say so. That is not hypothetical — the
`discipline` `sweep-all` record written this way on 2026-08-10 fired and was refreshed to a primary
basis the same day, by the rung-1 fetch above.

### Currency of a primary read

The docs serve no per-page content date ([below](#drift-signal--content-hashing-deferred)), so the
honest currency statement for a rung-1 read is the fetch itself: *fetched live from `<url>` on
`<date>`; upstream publishes no per-page content date.* Nothing stronger is available, and a stamp
that implies otherwise is the overclaim this doc's [first rule](#a-date-is-never-authority) forbids.

## Drift signal — content hashing, deferred

There is no mechanical per-page change signal on the official Claude Code docs: the raw-markdown
endpoints serve no `ETag`, and `Last-Modified` is a deploy/serving stamp rather than a per-page
content date (verified 2026-07-26 by header inspection of three `code.claude.com/docs/en/*.md`
endpoints fetched seconds apart — each returned a `Last-Modified` matching its own fetch time;
recheck trigger: those endpoints start serving an `ETag` or a stable per-page `Last-Modified`).
**Content hashing of a fetched page body is therefore the only viable mechanical drift signal** for
these pages.

The fleet **defers** storing hashes: no upstream-page hash store exists today, and every recheck is
a manual re-fetch at trigger time. Recheck trigger for the deferral itself: a stale stamp causes a
real defect a stored hash would have flagged, or a fleet audit completes without re-fetching every
stamped claim in its scope — at which point a hash store becomes its own designed issue, not an
inline addition here.

## Enforceability

Classified per `melodic-software/standards` `conventions/engineering/enforceability-tiers.md`:

| Judgment | Tier |
|---|---|
| Every verification stamp carries a recheck trigger | **Deterministic** by nature (a presence check) once stamps and triggers use greppable forms. The candidate check — flag any `Verified <date>` line or row whose surface states no trigger — is named but **not built**: per the tiers doc's routing rule, worth-mechanizing defaults to "not yet". Build trigger: a trigger-less stamp lands on `main` again after this doc. |
| The trigger clears the observability bar | **Reasoning-only** — whether an event is decidable from evidence is a judgment about meaning. |
| A trigger has fired | **Reasoning-only** today; **detect-then-judge** if a hash store lands — the hash mismatch flags, and judgment decides whether the page change touches the claim, because a changed page is not a changed fact. |

### Recorded decision — an adoption gate is deferred, and the check named above would have missed the case that prompted it

**Decided 2026-08-12 UTC: no CI gate is built for adoption of this convention, in either candidate
shape.** Recorded as a decision rather than left implicit, because this repo's `*-gate` CI pattern
is the standing precedent for promoting a convention to a check and the question was asked directly
([#2273](https://github.com/melodic-software/claude-code-plugins/issues/2273)).

The premise that settles it: the candidate check named in the table above — *flag any
`Verified <date>` line or row whose surface states no trigger* — **would not have caught
[#2207](https://github.com/melodic-software/claude-code-plugins/issues/2207)**, the finding that
prompted the question. That surface carried no stamp at all, so a stamp-anchored grep had nothing to
match on. The named check is shaped for a *half-conforming* record; the failure that actually ships
is the *zero-part* one. It therefore stays named-not-built on its own build trigger, unchanged, and
is not evidence that mechanization covers this class.

The zero-part shape has no deterministic check available. Deciding whether a sentence restates an
upstream-owned specific — as against an in-repo fact, a description of the surface's own behaviour,
or ordinary prose — is a judgment about meaning, which is **reasoning-only** under the tiers doc. A
grep for harness vocabulary (`PostToolUse`, `${CLAUDE_*}`, `settings.json`, and so on) fires on
every correct citation and every in-repo mention alike, and a gate whose false-positive rate forces
routine suppression trains authors to bypass it — worse than no gate, because it converts a real
signal into noise with an approved silencer.

- **Basis** — `melodic-software/standards` `conventions/engineering/enforceability-tiers.md` (the
  reasoning-only tier and the worth-mechanizing routing rule), plus the worked instance above.
- **Recheck trigger** — a third unstamped upstream-fact carrier reaches `main` after this decision
  (two are already on the record: `plugin-quality`, corrected in its 0.4.0, and `architecture`,
  whose false claim was removed in its 0.5.1), **or** a detector is demonstrated that separates an
  upstream restatement from an in-repo one without a suppression list. Either event reopens the
  shape question; neither is a date.

## Adopters

The rows below were migrated at this contract's 1.0.0 to the single name, each citing this doc with
content intact. **A row added after 1.0.0 is a surface that adopted on touch** — the mechanism the
note under the table already requires — and names the release that added it, so the table never
implies a surface was migrated at 1.0.0 when it was not.

**A surface is tabled only once it actually conforms.** The third column is a promise to a reader
about what they can rely on, so a carrier *known* to be unstamped belongs in a tracked issue, never
in a row: tabling it would assert the very thing the reader would then not get. The fleet's open
carriers are recorded that way in
[#2297](https://github.com/melodic-software/claude-code-plugins/issues/2297).

The rows are not all the same thing, and the table says which is which. A **conforming record**
carries the four required parts for an upstream-derived claim or decision. A **named trigger**
shares the canonical name, the observability bar, and
[its own firing procedure](#when-a-trigger-fires), but guards an in-repo decision: in scope for the
name, outside the four-part requirement, which binds only records that restate something
upstream-owned. This narrows what a row advertises; it does not widen the
contract to fit its exceptions.

| Surface | Was | What a reader can rely on |
|---|---|---|
| [hook-config-delivery](../hook-config-delivery/README.md) §Recheck triggers | already the canonical name | Conforming records — version-pinned facts table with per-fact basis, table-wide as-of dates, and fact-scoped event triggers. |
| [loop-lane](../loop-lane/README.md) §Versioning | "Re-derivation triggers" | Conforming records — dated upstream-claim stamps; drift outcomes recorded in its changelog. |
| [PLUGIN-PHILOSOPHY](../../PLUGIN-PHILOSOPHY.md) component-stances staleness disclaimer | unlabeled discipline | Conforming records — per-row claim, linked page, and verified date; the re-fetch-before-acting rule is [read-time validation](#read-time-validation-is-not-a-firing), and every row's stated trigger is a fetch diverging from the row. |
| [PLUGIN-PHILOSOPHY](../../PLUGIN-PHILOSOPHY.md#recorded-gate-runs) recorded gate runs | new with this table | Conforming records of the second kind — **recorded decisions**, one per platform surface the Native-first adoption gate has been run against, carrying an adopt/defer/decline verdict, the quoted upstream basis it rests on, and a trigger written per row rather than the generic divergence-at-fetch. A verdict is re-derived when its own trigger fires, not on any fetch that differs. |
| [OFFICIAL-DOCS](../../OFFICIAL-DOCS.md) staleness warning and per-row verified dates | unlabeled discipline | Conforming records — same shape as the component-stances table: link + date, divergence-at-fetch as the stated trigger. |
| [MIGRATION-PLAYBOOK](../../MIGRATION-PLAYBOOK.md) decision records | "Revisit trigger", and "Re-trigger" on the plugin-acceptance review record | Mixed — the dated component-decision records cite upstream bases and conform; the org-internal records (e.g. the ratification and plugin-acceptance review records) are named triggers; the skill-quality retrofit record is a third kind, terminal exclusions that state "no recheck trigger" by design — decided out, so nothing fires. |
| [ecosystem-commands](../ecosystem-commands/README.md) task-runner deferral | "Revisit triggers" | Named triggers only — an undated in-repo deferral; not a four-part record. |
| [topic-docs](../topic-docs/README.md) §Implementers restate the rules | "What would reopen it" | Named trigger only — an in-repo source-hoisting decision; not a four-part record. |
| [ai-slop tell catalog](../../../plugins/ai-slop/skills/audit/reference/catalog.md) §Upstream-drift record | new with 1.5.0 | Conforming record — revision-pinned four-part record over the Wikipedia source page (claim, `oldid` basis, as-of date, recurring recheck trigger: each `ai-slop` release and each fleet audit, chosen over per-revision after measuring the page at 50+ edits/week), plus a recorded fetch-gap note for two source sections the same trigger covers. |
| [docs-hygiene `write-for-humans` source records](../../../plugins/docs-hygiene/skills/write-for-humans/reference/sources.md) | new with docs-hygiene 0.18.0 | Conforming records — one four-part record per external writing standard the skill falls back to (Diátaxis, Google developer documentation style, ASD-STE100, Global English), each carrying claim, basis, as-of date, and an observable recheck trigger. Three are publication events (an STE issue, a Global English edition, a Diátaxis revision); the Google record's is a page-content divergence, because that guide is a continuously-edited site with no edition to pin — the contract admits either shape, and the record names which one it is. The STE record additionally states a fidelity ceiling: the layer is a principles subset, not the specification, so a document written to it is not thereby STE-conformant. |

Elsewhere the name binds on touch: living surfaces still saying "revisit trigger", "re-trigger",
"re-derivation trigger", or "what would reopen it" (several plugin reference docs already use the
canonical `## Recheck triggers` heading) adopt the canonical name, the observability bar, and their
kind's firing procedure the next time they change; a surface restating an upstream-owned specific
additionally adopts the required parts. **History is never rewritten**: `CHANGELOG.md` entries,
dated audit records, and ADR sections keep the wording they shipped with; a new ADR uses the
canonical name going forward.

## Why this name

"Recheck trigger" is what the org standard (`documentation-and-citations.md` §"Time-bound external
claims need a recheck trigger") already calls the concept — a repo-level owner doc renaming the
rule it specializes would fork the vocabulary one level up. It is also the majority name in this
fleet, and the `## Recheck triggers` heading is the one the docs-hygiene plugin's audit-noise
section-exemption list already recognizes.

## Versioning

This contract is versioned in [`CHANGELOG.md`](CHANGELOG.md). Changing a required part, the
canonical name, or an enforceability verdict is a major bump; additive guidance is a minor bump;
docs-only clarification is a patch.

## External authority

- `melodic-software/standards` `conventions/engineering/documentation-and-citations.md` — the
  org-wide read-on-demand rule and the concept's name.
- `melodic-software/standards` `conventions/engineering/enforceability-tiers.md` — the tier
  vocabulary and the routing rule.
- `melodic-software/standards` `conventions/engineering/reference-dont-duplicate.md` — the in-repo
  counterpart this doc's boundary defers to.
