# Re-decompose (rerouting)

What [`../SKILL.md`](../SKILL.md) does when the target item already carries slices from a previous
decomposition and the destination those slices serve turned out to be wrong. A first-pass
decomposition never reaches any of it.

Mid-flight review sometimes shows the **destination** is wrong, the spec no longer describes what
should be built, so the remaining slices point somewhere nobody wants to go. Rerouting is a usage
pattern of this skill and the existing seam verbs, not a separate capability or skill:
`/work-items:ship` routes here when slices no longer fit the spec, and the flow below is what it
routes to.

The doctrine, stated once: **tickets are disposable, the spec is editable.** The two artifacts have
different lifetimes, that is why they are separate. A slice is a projection of the spec at
decomposition time; when the spec moves, stale projections are closed and regenerated from the
edited spec, never hand-patched into meaning something the spec no longer says.

1. **Close unimplemented children.** Enumerate the journey's remaining slices, via the seam
   (`"$TRACKER" list-sub-items "<container-id>" --state all`) when a container exists. When the
   spec lives only in the Brief, no durable slice list exists outside the tracker (the publish
   step records no slice IDs in PLAN.md), so reconstruct the set with a provider search (the
   bound adapter's operations reference) for open items whose body cites the topic slug, the
   `## Parent` provenance line every published slice carries, and confirm the reconstructed
   set with the user before closing anything. Then close every not-yet-started slice the new
   direction obsoletes. Closing is a provider-mechanic operation
   (the bound adapter's operations reference, with the provider's not-planned state reason where
   it has one. GitHub: `not planned`), each close carrying a one-line comment linking the
   superseding direction (the container, or the item/PR that records the new direction). Skip
   items with an active claim: coordinate with the claim holder, or route a stale lease to
   `/work-items:track audit`, before closing work in flight.
2. **Keep implemented children untouched.** Completed slices and their merged PRs are history, not
   error, the reroute changes where the journey goes next, never what already landed. Do not
   reopen, re-close, relabel, or edit them.
3. **Re-interview / edit the spec.** The editable spec lives where the journey put it: the
   **container body** (spec-on-tracker, an ordinary body edit through the bound adapter, behind
   the same user approval as any tracker write) or the **topic Brief** (PLAN.md via the
   tier-selected lookup) when no container was published. Re-run the interview machinery
   (`/planning:interview` when installed, else a direct question round) or apply the user's
   directed edits. The edited spec is what legitimizes the reroute, never regenerate slices
   against a spec that still says the old thing.
4. **Regenerate remaining slices.** Run this skill's normal Steps 2–4 against the edited spec:
   draft the replacement slices, present for approval (the gate is mandatory here exactly as for
   a fresh decomposition), then publish via the seam. `create-item` with
   `--parent "<container-id>"` (when the container exists) and `--blocked-by` wiring the new
   native blocker edges. Replacement slices are born triaged like any others.
5. **Continue.** The journey resumes on the updated frontier. With a container,
   `/work-items:ship` re-states position and routes the next item; a Brief-only journey
   continues straight to the next unblocked slice (`/work-items:work`, or the Step 5 report's
   frontier ordering). `/work-items:ship` is a router over a container and has nothing to
   stand on without one.

**When NOT to reroute.** A spec that turns out wrong **after ship** is a new idea, not a routing
error: open a new spec (a new container or a new topic), never patch the closed one, the
container-lifecycle drift doctrine applies (a closed container is never edited into a living doc).
And small drift, wording, a stale count, one acceptance criterion sharpened, is an ordinary body
edit to the spec or slice, not a reroute: rerouting is for destination changes that obsolete
slices.
