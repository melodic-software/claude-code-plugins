# Close-out (PR time)

Spoke for `/planning:plan`. Read this file when the skill is invoked with the `close-out` argument.

**Close-out (PR time).** `/planning:plan` owns describing the close-out. Invoke with the `close-out` argument once the plan is approved:

1. Paste the approved PLAN.md into the PR description inside a `<details>` block, and into the linked issue. PLAN.md lives only in the memory slice, so this paste is its durable home (PR bodies cap near 64 KB; paste the contract, reference the rest). Distilled values only: never cite a path into the memory slice.
2. Record durable outcomes. A decision that passes the ADR admission test becomes an ADR in the repository's declared ADR convention. Actionable follow-ups go through the work-item tracker seam.

   **ADR admission test**. A decision earns an ADR only when ALL three hold: **hard to reverse** (changing course later carries real cost), **surprising without context** (a future reader of the code would wonder why it was done this way), and **the result of a real trade-off** (genuine alternatives existed and one was picked for specific reasons). Any one missing → no ADR: an easily reversed decision just gets reversed, an unsurprising one raises no questions, and a no-alternative decision has nothing worth recording. Keep each ADR minimal. A title plus a few sentences covering context, decision, and why; optional sections (status, considered options, consequences) only when they earn their place. Prefer writing the ADR the moment the decision crystallizes during planning over batching candidates at graduation: when the `architecture` plugin is enabled, invoke `/architecture:record-decision` via the Skill tool with the decision and its rationale (it owns convention discovery and the write); otherwise write it by hand into the repository's declared ADR convention. This step then just links the already-written file from the PR body.
3. Spec-container ship ritual (presence-gated. Only when the `work-items` plugin is enabled
   AND the topic's decomposition published a spec container). **Detect the container
   mechanically, never from in-session memory** (close-out often runs in a fresh session):
   first read the topic's PLAN.md for the `**Spec container:** <qualified-id>` line
   `/work-items:decompose` records under `## Brief` at publish time; absent that line, query
   the tracker for an open item carrying the binding-resolved container label (default
   `work-map`) whose body cites the topic slug. Found → run the container's close-at-ship
   ritual through the path that owns it. `/work-items:decompose` "Container lifecycle
   (spec-on-tracker)". That section owns the mechanics (verify every sub-item closed, close-out
   review against the container body, close with a comment linking the shipping PRs. Archival
   by closure); this step only sequences it into close-out and never redefines it. When the
   shipped work covers only part of the container's sub-items, the container stays open. Close
   it only when the whole spec has shipped. Neither detection path yields a container, or no
   `work-items` plugin: skip silently. Publishing a container is `/work-items:decompose`'s
   approval-time offer, never a close-out side effect.
