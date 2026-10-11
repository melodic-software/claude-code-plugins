# The fan-out tier

Read this once [`../SKILL.md`](../SKILL.md) has chosen the fan-out tier and resolved its depth.
It runs in place of the inline audit and correct-forward steps: same research discipline, but it
enumerates a TYPED FULL INVENTORY of the session's claims and has fresh-context subagents verify
them against primary sources, which a self-check in the context that produced the claims cannot
do.

## The depth decides the dispatch

- **tiered**. Resolve trivial and non-load-bearing inventory items inline and cheaply (a quick
  check in this context, or an already-cited source), and fan fresh-context subagents out only
  over the load-bearing items. Most sessions want this: it spends the subagent budget where drift
  actually matters.
- **full**. Subagent-verify EVERY inventory item, trivial or not. Reach for it when the cost of a
  single wrong "trivial" item is high enough to pay for exhaustive independent checking.

Report which depth ran and why (argument / configured / default).

## The fan-out

1. **Enumerate a typed full inventory.** List EVERY claim the session rests on, as a checklist,
   each tagged with its type so coverage is provable. Not just the obviously load-bearing ones:
   - **assumptions**. Unstated premises the work took for granted;
   - **asserted facts**. Statements presented as true;
   - **concrete specifics**. Paths, filenames, defaults, flags, signatures, versions, any
     "standard/conventional X";
   - **load-bearing premises**, the conclusions the rest of the work now depends on;
   - **recommendations**. Each option, verdict, default, or next step put to the user and not
     yet settled, verified against the contract in
     [`recommendation-basis.md`](../../../context/recommendation-basis.md).

   The typing makes the inventory auditable: each item carries its type, and step 5's ledger has
   exactly one row per item. Do not spot-check one, and do not silently drop an item as
   "obvious", an obvious item is a `verified` ledger row, not an omission.
2. **Fan out, throttled. Scope set by the resolved depth.** Dispatch fresh-context subagents
   (blind to the reasoning that produced each item) to verify each against a PRIMARY source, not
   the same recall that produced it. Under **tiered**, the fan-out covers the load-bearing items
   while the trivial / non-load-bearing ones are resolved inline (and still get a ledger row);
   under **full**, every item goes through the fan-out. Dispatch per
   [`fan-out.md`](../../../context/fan-out.md): blind fresh-context subagents, bounded waves,
   failed-subset retry.
3. **Match the method to the item type.** An externally-verifiable item (an asserted fact, a
   concrete specific) resolves against a source or the live environment. An INTERNAL item (an
   assumption, or a load-bearing premise with no external referent) has no citation to fetch. Its
   honest verdict is a fresh-context re-derivation or a flag for the user to confirm, never a
   manufactured source. The 100%-coverage rule is coverage of the checklist, not a demand that
   every row name a URL.
4. **Merge and correct.** Fold the returns together, correct every falsified or unbacked item
   THIS turn, and surface anything that stays unverifiable rather than smoothing over it.
5. **Report a per-item ledger. 100% of the inventory.** One row per checklist item (no silent
   drops), keyed by claim, each carrying:
   - **verdict**. Verified / corrected / unverifiable, plus withheld for a recommendation row
     only;
   - **source**. What resolved it: a fetched primary source, the live environment, or
     "internal. Re-derived / needs user confirm" for an item with no external referent; for an
     unverifiable item, where you looked;
   - **source tier**. How authoritative that source is, per the consuming project's own research
     discipline. Resolve its source of truth by the shared method's ladder, the project's
     `CLAUDE.md` / `.claude/rules/` notion of official / authoritative / trusted, degrading to the
     portable baseline when none is declared;
   - **consensus count**. How many INDEPENDENT authoritative sources agreed; a lone source is
     weaker than a consensus, so note when only one was found;
   - **recency**. For a fact that can go stale (versions, pricing, APIs, defaults), the date or
     version the source reflects.

   A **recommendation** row also carries its outcome from the contract: `Basis: verified` or
   `Basis: judgment` (never on a consequential one), or **withheld**, with no `Basis:` label and
   the open question naming the evidence that would settle it. A corrected row adds
   old → new → why; a verified one says unchanged and why.

## Gotchas

- **Coverage is the checklist, not the URLs.** 100% coverage means every typed inventory item has
  exactly one ledger row. An internal assumption with no external source is covered by an honest
  re-derived / needs-confirm verdict, not by a fabricated citation.
- **The fan-out never manufactures a finding, or a source, to look diligent.** An honest per-item
  "verified", "internal. Needs user confirm", or "stays unverifiable" is the right output when
  true.
