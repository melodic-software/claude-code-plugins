# Capability-tier label axis (migration)

`apply` runs this pass at **step 4** of its numbered flow, after the work-class pass and before the
legacy backfill. Triage's capability-tier stamp and the work-loop frontier quota guard require
`capability-tier: frontier` from
[`${CLAUDE_PLUGIN_ROOT}/reference/capability-tier-labels.md`](${CLAUDE_PLUGIN_ROOT}/reference/capability-tier-labels.md).

1. **Skip when `.work-item-tracker.json` is absent** — nothing is bound yet.
2. **Skip when the bound provider has no label listing** (`local-markdown`, read-only `jira`) — report
   INFO and continue; triage verifies at item-edit time.
3. **Discover** via the adapter's label listing (GitHub: `gh label list --limit 200`, filter
   `capability-tier:`). Compare against the canonical member in the reference.
4. **Present** — report "capability-tier axis provisioned" and continue.
5. **Missing — label-as-code owner declared** — stop. Name the missing label and route remediation to
   that owner; never `gh label create` ad hoc.
6. **Missing — no label-as-code owner, interactive user present** — offer to create the label via the
   adapter's label-creation mechanics (GitHub: `gh label create "capability-tier: frontier"
   --description "<description>" --color "<color>"` using the reference table). RECOMMENDED: create
   it — this pass is the upgrade migration for repos adopting the #1716 reader flip. Re-list after
   creation and confirm the member exists before continuing.
7. **Missing — no label-as-code owner, no interactive user** — stop per `apply`'s "Autonomous
   invocation" rule: "capability-tier axis needs provisioning; run `/work-items:setup apply` with a
   user present".
