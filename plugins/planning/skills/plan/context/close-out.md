# Close-out (PR time)

Spoke for `/planning:plan`. Read this file when the skill is invoked with the `close-out` argument.

**Close-out (PR time).** The contract slice is branch-lived; `/planning:plan` owns describing its close-out. Invoke with the `close-out` argument once the plan is approved:

1. Paste the approved PLAN.md into the PR description inside a `<details>` block. The review-surface publication (PR bodies cap near 64 KB; paste the contract, reference the rest).
2. Graduate durable outcomes through the knowledge-vault seam. Resolve the concern file's `vault_backend`: `docs` (default) → a history-preserving `git mv` of the promoted doc into `docs/adr/` or `docs/specs/` (guard the command. Create the target directory first); `gitbook` → report that writes are deferred and use the `docs` path without invoking GitBook API/MCP or Git Sync; any other enabled value → the backend the consuming repo documents, degrading to `docs` when its tools are absent (binding: [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)). Actionable follow-ups go through the work-item tracker seam.

   **ADR admission test**. A decision earns an ADR only when ALL three hold: **hard to reverse** (changing course later carries real cost), **surprising without context** (a future reader of the code would wonder why it was done this way), and **the result of a real trade-off** (genuine alternatives existed and one was picked for specific reasons). Any one missing → no ADR: an easily reversed decision just gets reversed, an unsurprising one raises no questions, and a no-alternative decision has nothing worth recording. Keep each ADR minimal. A title plus a few sentences covering context, decision, and why; optional sections (status, considered options, consequences) only when they earn their place. Prefer writing the ADR the moment the decision crystallizes during planning over batching candidates at graduation. This step then just moves the already-written file.
3. Prune with pointer: a final commit before merge deletes the contract slice `<contract_dir>/<topic-slug>/` (default `docs/topics/`), leaving context pointers (the PR body, the promoted-doc and tracker locations) in its place.
4. Spec-container ship ritual (presence-gated. Only when the `work-items` plugin is installed
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

Lifecycle detail and the redaction bar for committed evidence: [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md).
