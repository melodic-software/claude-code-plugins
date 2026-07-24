---
name: do-your-research-deep
description: "Escalate research discipline to a heavy verification fan-out over a TYPED FULL INVENTORY of the session's claims — assumptions, asserted facts, concrete specifics (paths, defaults, flags, signatures), and load-bearing premises — verifying each against a primary source at a configurable depth (tiered by default, or full), then report a per-item ledger with verdict, source, source tier, consensus count, and recency. Use when: 'deep research pass', 'verify every claim', 'audit all our claims', 'fact-check everything', 'fact-check all these claims', 'go make sure those are all right', 'we've made a lot of load-bearing claims', or when your own judgement is the suspected bias across many claims. For a single or small inline fact-check ('fact-check that'), use the sibling do-your-research."
argument-hint: "[tiered|full]"
user-invocable: true
disable-model-invocation: false
metadata:
  discipline-batch: never  # heavier fan-out execution tier — invoked directly, not batched
---

# Do your research — deep

The verification-fan-out tier of the sibling `/discipline:do-your-research`.
Same research discipline; heavier execution. Where the base skill re-anchors
and audits inline in the current context, this one enumerates a TYPED FULL
INVENTORY of the session's claims and verifies them against primary sources —
the execution tier the base skill's context cannot provide from within itself.

The shared method — re-anchor, audit, correct forward, report, and the tone
that firing this is not an accusation — lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
The discipline this re-anchors and its portable baseline live in the sibling
[`do-your-research`](../do-your-research/SKILL.md). Read both; this file adds
only the fan-out delta. There is no separate copy of the discipline here —
update the sibling and this tier follows.

## When this tier, not the inline audit

Reserve the fan-out for when the accumulated claims are load-bearing enough to
justify the subagent cost: a long session with many concrete specifics the
rest of the work now rests on, a "fact-check everything" request that wants
provable coverage, or where your own judgement is the suspected source of bias
across many claims — a self-check in the context that produced the claims is
weak by construction. For a single unbacked claim or a short session, the
inline audit in the sibling is the right tool; this tier is overkill.

## Verification depth (configurable)

This tier is the expensive one by design, so its depth is configurable.
Resolve it once, before enumerating, by this precedence:

1. **Invocation argument wins.** When this skill is invoked with an explicit
   depth — `tiered` or `full` (see `argument-hint`) — honor it over the
   configured default.
2. **Otherwise the configured default:**
   `${user_config.research_deep_verification}`.
3. **Otherwise `tiered`.** Treat an empty value, a surviving literal
   `${user_config.…}` token, AND any unrecognized string (a typo like
   "teired") all as unset — fall back to `tiered`, never error.

- **tiered** (default) — resolve trivial and non-load-bearing inventory items
  inline and cheaply (a quick check in this context, or an already-cited
  source), and fan fresh-context subagents out only over the load-bearing
  items. Most sessions want this: it spends the subagent budget where drift
  actually matters.
- **full** — subagent-verify EVERY inventory item, trivial or not. Reach for
  it when the cost of a single wrong "trivial" item is high enough to pay for
  exhaustive independent checking.

Report which depth ran and why (argument / configured / default).

## The fan-out

Run this in place of the base skill's inline audit and correct-forward steps:

1. **Enumerate a typed full inventory.** List EVERY claim the session rests
   on, as a checklist, each tagged with its type so coverage is provable — not
   just the obviously load-bearing ones:
   - **assumptions** — unstated premises the work took for granted;
   - **asserted facts** — statements presented as true;
   - **concrete specifics** — paths, filenames, defaults, flags, signatures,
     versions, any "standard/conventional X";
   - **load-bearing premises** — the conclusions the rest of the work now
     depends on.
   The typing makes the inventory auditable: each item carries its type, and
   step 6's ledger has exactly one row per item. Do not spot-check one, and do
   not silently drop an item as "obvious" — an obvious item is a `verified`
   ledger row, not an omission.
2. **Fan out, throttled — scope set by the resolved depth.** Dispatch
   fresh-context subagents (blind to the reasoning that produced each item) to
   verify each against a PRIMARY source, not the same recall that produced it.
   Under **tiered**, the fan-out covers the load-bearing items while the
   trivial / non-load-bearing ones are resolved inline (and still get a ledger
   row); under **full**, every item goes through the fan-out. Throttle the
   dispatch in bounded waves rather than launching one agent per item at once —
   a sustained wide fan-out trips server-side burst overload (529s) and loses
   agents mid-run. Cap concurrency to a modest wave (roughly a dozen or fewer
   at a time); lower-tier worker models are sufficient for per-item
   verification and dodge burst overload. Process the inventory wave by wave.
3. **Match the method to the item type.** An externally-verifiable item (an
   asserted fact, a concrete specific) resolves against a source or the live
   environment. An INTERNAL item (an assumption, or a load-bearing premise with
   no external referent) has no citation to fetch — its honest verdict is a
   fresh-context re-derivation or a flag for the user to confirm, never a
   manufactured source. The 100%-coverage rule is coverage of the checklist,
   not a demand that every row name a URL.
4. **Retry the failed subset only.** If an agent errors or times out, retry
   that item once; on a second failure mark it unverifiable. Never
   blind-re-run the whole fan-out to recover a few stragglers — re-dispatch
   only the items that failed.
5. **Merge and correct.** Fold the returns together, correct every falsified
   or unbacked item THIS turn, and surface anything that stays unverifiable
   rather than smoothing over it.
6. **Report a per-item ledger — 100% of the inventory.** One row per checklist
   item (no silent drops), keyed by claim, each carrying:
   - **verdict** — verified / corrected / unverifiable;
   - **source** — what resolved it: a fetched primary source, the live
     environment, or "internal — re-derived / needs user confirm" for an item
     with no external referent;
   - **source tier** — how authoritative that source is, per the consuming
     project's own research discipline. Resolve its source of truth by the
     shared method's ladder — the project's `CLAUDE.md` / `.claude/rules/`
     notion of official / authoritative / trusted, degrading to the portable
     baseline when none is declared;
   - **consensus count** — how many INDEPENDENT authoritative sources agreed;
     a lone source is weaker than a consensus, so note when only one was found;
   - **recency** — for a fact that can go stale (versions, pricing, APIs,
     defaults), the date or version the source reflects.

## What this skill does NOT do

- **Not a lighter inline pass.** For a single re-anchor + audit without the
  subagent cost, use the sibling `/discipline:do-your-research`.
- **Does not fabricate a citation or a violation.** An honest per-item
  "verified", "internal — needs user confirm", or "stays unverifiable" is the
  right output when true; the fan-out never manufactures a finding — or a
  source — to look diligent.

## Gotchas

- **Coverage is the checklist, not the URLs.** 100% coverage means every typed
  inventory item has exactly one ledger row. An internal assumption with no
  external source is covered by an honest re-derived / needs-confirm verdict,
  not by a fabricated citation.
- **Depth is resolved once, up front.** Argument beats the configured default
  beats `tiered`; empty, an unexpanded token, and an unrecognized value all
  mean `tiered`. Never error on a bad value.
- **Throttle is not optional at scale.** The failure mode is a claim-heavy
  session firing one agent per item simultaneously; the wave cap and
  failed-subset retry above are what keep the fan-out reliable, not nice-to-
  haves.
- **Blind subagents, or it is not fresh context.** An agent handed the
  reasoning that produced a claim re-derives the same error. Verify against the
  primary source, not the argument for the claim.
