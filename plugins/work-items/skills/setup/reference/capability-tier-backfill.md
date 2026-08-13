# Capability-tier label backfill (migration)

`apply` runs this pass at **step 5**, immediately after the capability-tier axis pass. It is
load-bearing on upgrade: triage refuses to re-triage already-triaged output, so items stamped in-body
before #1716 need the provider-permissioned label applied here. Pattern semantics and the script path
live in the reference's "Legacy body stamps" subsection.

Resolve the script:

```bash
BACKFILL="${CLAUDE_PLUGIN_ROOT}/scripts/backfill-capability-tier-labels.sh"
[[ -f "$BACKFILL" ]] || BACKFILL="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/plugins/work-items/scripts/backfill-capability-tier-labels.sh"
```

1. **Skip when `.work-item-tracker.json` is absent** — nothing is bound yet.
2. **Skip when the bound provider has no label listing or bulk open-item listing** (`local-markdown`,
   read-only `jira`) — report INFO; backfill requires GitHub-style listing.
3. **Skip when `capability-tier: frontier` is absent from the repo** — the axis pass must provision it
   first; report that backfill is blocked until the label exists.
4. **Discover** via `"$BACKFILL" check` (read-only). Report each candidate number; zero candidates →
   "no legacy frontier-tier body stamps need backfill" and continue.
5. **Label-as-code owner declared** — report candidates only; route item label writes to that owner or
   to an operator-run `"$BACKFILL" apply` after IaC lands the label. Do not mutate items ad hoc.
6. **Interactive user present** — offer to run `"$BACKFILL" apply` (RECOMMENDED: apply all candidates).
   Confirm the count applied matches the check output.
7. **No interactive user** — report candidates and name `"$BACKFILL" apply` (or re-run
   `/work-items:setup apply` with a user present) as the remediation; never mutate without
   confirmation.
