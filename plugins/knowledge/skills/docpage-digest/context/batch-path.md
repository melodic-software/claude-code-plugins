# Batch path: several pages through one workflow

The launch steps for the `knowledge:docpage-digest-batch` workflow that [`../SKILL.md`](../SKILL.md)
"Batch path" names. Each step ends when its value is in hand for the launch.

1. **Availability.** Launch only when the Workflow tool is in this session's toolset; otherwise run
   the pages one at a time through the skill. The switches that turn workflows off are in
   [workflows: turn workflows off](https://code.claude.com/docs/en/workflows#turn-workflows-off).
2. **Roles.** When `/multi-agent:route` resolves, keep the `roles` object
   `/multi-agent:route all session=<alias>` prints; otherwise omit it and the workflow's
   fallbacks apply.
3. **Verifier B.** The batch path runs verifier B as the degraded same-vendor refuter
   [dual-verification.md](dual-verification.md) describes, because `codex:codex-rescue` returns its
   raw stdout, which cannot carry a structured verdict; the single-page path keeps the
   cross-vendor arm.
   - **Pointer**: the forwarding rule on returning the companion's stdout in the codex plugin's
     `agents/codex-rescue.md`.
4. **Write scope.** Every stage runs as `knowledge:digest-worker`, whose writes the stage prompt
   scopes to the page's slice, in parity with the single-page path, whose digest and verifier
   subagents are scoped by their briefs alone ([`../SKILL.md`](../SKILL.md) Phase 3); no hook
   enforces either.
5. **Launch.** Record the start with `date -u +%Y-%m-%dT%H:%M:%SZ`, then launch
   `Workflow({ name: "knowledge:docpage-digest-batch", args: { pages, workRoot, skillDir, date, roles, maxConcurrent } })`.
   `workRoot` is the root `work-root.mjs` printed, `skillDir` is `<skill-dir>`, and `date` is
   today as `YYYY-MM-DD`. An `error` return dispatched nothing. The result lists pages it did not
   run with a `reason` code and a `verification` of `unverified: not run: <reason>` each:
   `rejected` (`not-https`, `url-charset` for a character outside the shell-safe allowlist, or
   `not-public-host`) and `deferred` (`page-cap`). Relaunch the `deferred` pages.
6. **Read each page's `status`**: `claimed`, `unverified` or `failed`, built only from the
   workflow's own reason codes, never from agent text. A workflow script cannot read the disk, so
   `claimed` means only that every stage reported success, and its `verification` is
   `unverified: awaiting-check`. The workflow never says `verified`.
7. **Run the check.** For each page with a non-null `slice`, write the page's entry from the result
   as JSON to `<workRoot>/.work/batch-<date>-<label>.json`, then run:

   ```bash
   python3 "<skill-dir>/scripts/verify-batch-page.py" --result <that file> --slice <slice> --root <workRoot> --started-at <the recorded start>
   ```

   It reads the verdict files, the pin and the checklist and handoff, re-runs the standing gates,
   and alone writes `verified`. It prints the final status, writes it as the checklist's
   `Verification status` line and the handoff's first line over whatever is there, and ticks Phase 4
   only for `verified`. Exit 0 is `verified`, 1 any other status, and 2 a usage error that wrote
   nothing, so fix the arguments and run it again. Run it once per workflow run: it requires the
   `unverified: awaiting-check` close left, so a second run over the same slice ends
   `unverified: status-not-awaiting`. For a page that is not `claimed` it writes the status the
   result already carries. A page with a null `slice` claimed no slice: leave the disk alone, so a
   status an earlier run wrote there stays, and it says nothing about this run. A page whose close
   recorded `unverified: awaiting-check` and whose check never ran keeps that line with Phase 4
   unticked, which every later step reads as unverified.
8. **Route what did not verify.** The script derives each slug from the launched URL and does not
   follow a redirect. `unverified: redirect-refused` is a page whose setup reported another
   canonical URL, `failed: slug-mismatch` one whose setup reported another slug,
   `unverified: canonical-missing` one whose setup reported no canonical URL,
   `unverified: slug-collision` a second spelling of a page already in this run, and
   `unverified: setup-refused` an existing slice holding another URL. Take a redirect-refused or
   slug-mismatch page through the single-page path, which derives its own slug, and a page rejected
   as `not-https` or `url-charset` too, since that path needs only what single-quoting needs. The batch path runs
   no correction rounds: take a `failed: verifier-fail` or `failed: gate-fail` page, or a page the
   check ended `unverified: verifier-<arm>-fail`, `verifier-<arm>-high` or `gate-<gate>-fail`,
   through the single-page path, which keeps them. Re-run another `unverified` page once its cause
   clears; a rerun redoes Phases 3 to 5, since the batch path has no resume. Then run the Phase 5
   interview once over the handoffs of this run's pages the check printed `verified` for, never any
   other handoff on disk.
