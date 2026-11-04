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
   run with a `reason` code and a `verification` of `unverified: not run: <reason>` each:
   `rejected` (`not-https`, `url-charset` for a character outside the shell-safe allowlist, or
   `not-public-host`) and `deferred` (`page-cap`). Relaunch the `deferred` pages.
6. **Read each page's `verification`**: `verified`, `unverified: <code>` or `failed: <code>`, built
   only from the workflow's own reason codes, never from agent text. `verified` needs both arms
   to return a written `PASS` or `PASS-WITH-FINDINGS` in this run with no `FAIL` on any attempt,
   every standing gate passed, and a close stage that wrote the checklist and handoff.
7. **Write the final status.** The close stage cannot know its own outcome, so a page heading for
   `verified` carries `Verification status: unverified: awaiting-launcher` on disk and Phase 4 stays
   unticked. For each page with a non-null `slice`, write `Verification status: <verification>` on
   `<slice>/docpage-digest-checklist.md` and, when the page has a `handoff`, as that file's first
   line; tick Phase 4 only when `verification` is `verified`. A page with a null `slice` claimed no
   slice: leave the disk alone.
8. **Route what did not verify.** The script derives each slug from the launched URL and does not
   follow a redirect. `unverified: redirect-refused` is a page whose setup reported another
   canonical URL, `failed: slug-mismatch` one whose setup reported another slug,
   `unverified: canonical-missing` one whose setup reported no canonical URL,
   `unverified: slug-collision` a second spelling of a page already in this run, and
   `unverified: setup-refused` an existing slice holding another URL. Take a redirect-refused or
   slug-mismatch page through the single-page path, which derives its own slug. Re-run another
   `unverified` page once its cause clears; a rerun redoes Phases 3 to 5, since the batch path has
   no resume. The batch path runs no correction rounds: take a `failed: verifier-fail` or
   `failed: gate-fail` page through the single-page path, which keeps them. Then run the Phase 5
   interview once over the `verified` pages' handoffs.
