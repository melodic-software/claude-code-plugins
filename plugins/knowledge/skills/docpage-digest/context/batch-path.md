# Batch path: several pages through one workflow

The launch steps for the `knowledge:docpage-digest-batch` workflow that [`../SKILL.md`](../SKILL.md)
"Batch path" names. Each step ends when its value is in hand for the launch.

1. **Availability.** Launch only when the Workflow tool is in this session's toolset; otherwise run
   the pages one at a time through the skill. The switches that turn workflows off are in
   [workflows: turn workflows off](https://code.claude.com/docs/en/workflows#turn-workflows-off)
   (as of 2026-11-03; recheck when those switches are renamed).
2. **Roles.** When `/multi-agent:route` resolves, keep the `roles` object
   `/multi-agent:route all session=<alias>` prints; otherwise omit it and the workflow's
   fallbacks apply.
3. **Verifier B.** When the codex plugin's `codex:codex-rescue` agent is in this session's agent
   list, pass it as `verifierB`. Without it, or when it returns nothing, the page's verifier B runs
   as the degraded same-vendor refuter [dual-verification.md](dual-verification.md) describes,
   recorded in its header. Whether that agent resolves inside a workflow is unverified until a run
   reports `verifierB.mode: cross-vendor`.
4. **Launch** `Workflow({ name: "knowledge:docpage-digest-batch", args: { pages, workRoot, skillDir, date, verifierB, roles, maxConcurrent } })`.
   `workRoot` is the root `work-root.mjs` printed, `skillDir` is `<skill-dir>`, and `date` is
   today as `YYYY-MM-DD`. An `error` return dispatched nothing. Relaunch the `deferred` pages,
   which were past the per-run cap.
5. **Read each page's `verification`**, the same value as its checklist's `Verification status`
   line. Re-run an `unverified` page once its cause clears, take a `failed` page to the operator,
   and treat a `refused` page as a collision. Then run the Phase 5 interview once over the
   `verified` pages' handoffs.
