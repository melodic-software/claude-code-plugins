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
3. **Verifier B.** The batch path runs verifier B as the degraded same-vendor refuter
   [dual-verification.md](dual-verification.md) describes, because `codex:codex-rescue` returns its
   raw stdout, which cannot carry a structured verdict; the single-page path keeps the
   cross-vendor arm.
   - **Pointer**: the forwarding rule on returning the companion's stdout in the codex plugin's
     `agents/codex-rescue.md`.
   - **As of**: 2026-11-03 (codex plugin 1.0.6).
   - **Recheck trigger**: that agent gains a structured return.
4. **Write scope.** Every stage runs as `knowledge:digest-worker`, whose writes the stage prompt
   scopes to the page's slice, in parity with the single-page path, whose digest and verifier
   subagents are scoped by their briefs alone ([`../SKILL.md`](../SKILL.md) Phase 3); no hook
   enforces either.
5. **Launch** `Workflow({ name: "knowledge:docpage-digest-batch", args: { pages, workRoot, skillDir, date, roles, maxConcurrent } })`.
   `workRoot` is the root `work-root.mjs` printed, `skillDir` is `<skill-dir>`, and `date` is
   today as `YYYY-MM-DD`. An `error` return dispatched nothing. The result lists pages it did not
   run with a `reason` and a `verification` of `unverified: not run: <reason>` each: `rejected`
   (not an https URL on a public host, or a character outside the shell-safe allowlist) and
   `deferred` (past the per-run cap). Relaunch the `deferred` pages.
6. **Read each page's `verification`**, the same value as its checklist's `Verification status`
   line: `verified`, `unverified: <reason>` or `failed: <reason>`. A page with `closed: false` had
   a close stage that returned nothing after its retry, so no checklist or handoff holds the
   status: write `Verification status: unverified: close stage returned nothing` on that slice's
   checklist yourself, write each `unwritten` entry's verdict to its `file` under the slice's
   verification records, append-only, with its `header` and `findings`, and read what Phase 4
   reached from `outcome`. Re-run an `unverified` page once its cause clears, take a `failed` page
   to the operator, and treat `unverified: refused: redirect target <reason>` as a page whose
   redirect left the checks the workflow applies to input URLs; any other `unverified: refused:`
   page is a collision. Then run the Phase 5 interview once over the `verified` pages' handoffs.
