# Close-out (PR time)

Spoke for `/planning:plan`. Read this file when the skill is invoked with the `close-out` argument.

**Close-out (PR time).** `/planning:plan` owns describing the close-out. Invoke with the `close-out` argument once the plan is approved:

1. Paste the approved plan's published copy (SKILL.md "Reader depth": PLAN.md at `step-by-step`, else the derived file re-rendered from it) into the PR description inside a `<details>` block, and into the linked issue. PLAN.md lives only in the memory slice, so this paste is its durable home (PR bodies cap near 64 KB; paste the contract, reference the rest). Distilled values only: never cite a path into the memory slice. When `plan_store` resolves `tracker` (SKILL.md "Plan store" gives the layers), the linked issue's copy is the `publish-plan` comment: rerun `/work-items:track publish-plan <id> <published copy>` so it carries the final plan, and post no second paste to that issue.
2. Record durable outcomes. Actionable follow-ups go through the work-item tracker seam.

   **ADRs.** For each decision the plan made about the system over a weighed alternative, invoke `/architecture:record-decision` via the Skill tool with the decision, its rationale and the alternatives, when the `architecture` plugin is enabled. That skill owns and applies the admission test, the template and convention discovery; this step carries no copy of the test. Prefer invoking it the moment the decision crystallizes during planning over batching candidates at graduation; this step then just links the already-written file from the PR body. Without the `architecture` plugin, list the decisions as ADR candidates in the PR body for a human to judge.
3. Spec-container ship ritual (presence-gated. Only when the `work-items` plugin is enabled
   AND the topic's decomposition published a spec container). **Detect the container
   mechanically, never from in-session memory** (close-out often runs in a fresh session):
   first read the topic's PLAN.md for the `**Spec container:** <qualified-id>` line
   `/work-items:decompose` records under `## Brief` at publish time; absent that line, query
   the tracker for an open item carrying the binding-resolved container label (default
   `spec-container`) whose body cites the topic slug and carries the `**Execution shape:**` line
   `/work-items:decompose` appends to every container it publishes (a wayfind map that also
   carries the label never writes that line). A labeled item without the line is skipped and named in
   the report, never adopted. Found → run the container's close-at-ship
   ritual through the path that owns it. `/work-items:decompose` "Container lifecycle
   (spec-on-tracker)". That section owns the mechanics (verify every sub-item closed, close-out
   review against the container body, close with a comment linking the shipping PRs. Archival
   by closure); this step only sequences it into close-out and never redefines it. When the
   shipped work covers only part of the container's sub-items, the container stays open. Close
   it only when the whole spec has shipped. Neither detection path yields a container, or no
   `work-items` plugin: skip silently. Publishing a container is `/work-items:decompose`'s
   approval-time offer, never a close-out side effect.
