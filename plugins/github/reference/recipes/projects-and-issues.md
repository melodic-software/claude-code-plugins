# Recipe: projects, boards, issues, and labels

Audits the GitHub **planning and issue-management surface** for the `projects-and-issues` area:
native issue statuses, repository boards, organization Projects, issue artifacts, native issue
relationships, issue types and fields, issue templates, and label lifecycle (including label
archiving). Every concrete CLI subcommand, REST/GraphQL endpoint, field name, and plan gate is
resolved live through the [method ladder](../method-ladder.md). This recipe ships curated audit
questions, posture heuristics, and drift procedures with zero vendored GitHub mechanics.

## Credential-and-gate preflight

Run the ladder's rung-0 preflight first, then layer these area-specific diagnoses before treating
any empty result as absence or drift:

- **Org versus repo layer.** Issue types, organization Projects, and org-wide `.github` issue
  templates live at the organization layer; native issue statuses, repository boards, labels, issue
  artifacts, and issue links live on each repository. Confirm which layers the current credential
  can read before concluding a surface is unset.
- **Mixed CLI, REST, GraphQL, and UI-only reachability.** Planning features span all rungs of the
  ladder. Some surfaces (such as issue artifacts) may have native `gh` subcommands, others (such as
  label archive metadata, native issue statuses, or symmetric issue links) may sit on REST or
  GraphQL, and others (such as Repository Board views) may be settings/web-UI-only. Resolve live
  reachability per surface before reporting a gap.
- **Feature and preview gating.** Native issue statuses, issue artifacts, issue types, custom issue
  fields, and label archiving can vary by repository visibility, organization plan, or rollout
  state. Apply the ladder's 403/404 disambiguation so a feature or plan gate is never reported as
  drift.
- **Actor-provenance boundary.** Not every planning mutation leaves a persisted actor-identity
  event in the issue timeline or audit trail. Before treating any planning field (especially native
  issue statuses) as a trusted gate for privileged automation, verify actor attribution live from
  the fetched docs and a real transition read.

## Audit-question checklist

Curated auditor questions for this area. Resolve exact mechanics live via the ladder before
answering; report blocked surfaces as gates, never silent passes.

1. Are native issue statuses (`planning-statuses`) enabled and configured consistently across
   sibling repositories in the same class, matching the declared lifecycle states?
2. Is automatic syncing between native issue statuses and linked pull requests configured as
   intended, and free of conflicting workflows or bots overwriting statuses?
3. Does any privileged workflow, merge gate, or automation lane rely on native issue statuses as a
   trust boundary without verified, persisted actor-identity attribution on status transitions?
4. Are native Repository Boards enabled and configured consistently on repositories whose declared
   posture uses single-repo boards, rather than duplicating identical status tracking in an org
   Project?
5. For organization Projects (Projects v2), does each active project map to a real team or
   cross-repo workstream, and are custom status fields free of stale duplicates that conflict with
   native issue statuses?
6. Where repositories attach structured specs, plans, or reports as native Issue Artifacts, do
   artifact names and types follow declared conventions, and do automation readers remain compatible
   (preserving required machine-parsed comment markers when artifacts act as additive companions)?
7. Are native non-hierarchical symmetric links (`"Relates to"`) and hierarchical sub-issues used
   consistently instead of fragile ad-hoc cross-references buried in issue body prose?
8. Are organization-level issue types and custom issue fields aligned with repository issue forms
   and templates, without drifted or orphaned definitions across sibling repos?
9. Do sibling repositories of the same class share the declared canonical label catalog (names,
   colors, descriptions), or have ad-hoc one-off labels drifted across the fleet?
10. Are retired or superseded labels archived (carrying archived-timestamp metadata that preserves
    historical issue classification) rather than left active to clutter triage, or deleted outright
    when history should stay intact?
11. Do any active workflows, issue templates, or automation rules still reference archived labels
    that need migration or cleanup?
12. Are issue templates, issue forms, blank-issue restrictions, and org-level `.github` defaults
    configured consistently across repositories of the same class?

## Posture heuristics

Area-specific judgment when conventions are silent; resolve the exact mechanism live.

- **Separate universal lifecycle from trusted automation gates.** Native issue statuses and
  Repository Boards fit human workflow visibility and PR auto-sync. Keep privileged automation
  admission or hold gates on a surface with verified, persisted actor provenance unless live docs
  and probes confirm native status transitions record the acting identity.
- **Archive retired labels instead of deleting or leaving them active.** Archiving retired labels
  removes them from active triage while keeping historical issue associations intact; pair label
  archiving with a check that active workflows no longer apply archived labels.
- **Use Issue Artifacts as additive companions when automation reads comments.** Native Issue
  Artifacts keep long plans or specifications structured and discoverable, but verify every
  downstream automation reader (such as comment-marker or trusted-author checks) before removing
  canonical content from issue comments.
- **Prefer native issue links over prose references.** Native symmetric `"Relates to"` links and
  sub-issues stay bidirectional and queryable without brittle body-text parsing.
- **Repository Boards for single-repo flow; org Projects for cross-repo rollups.** Avoid creating a
  heavyweight org Project that mirrors one repository's native status flow when a Repository Board
  already covers it.
- **Class-scoped planning baselines.** Production, library, and sandbox repositories may legitimately
  use different label sets and templates, but sibling repositories in the same class should not
  drift silently.

## Drift comparison against declared conventions

1. Read the layered conventions per [`../conventions-file.md`](../conventions-file.md), anchoring at
   the repo root before repo-relative reads and concatenating every layer that exists.
2. Extract planning-surface declarations: canonical native issue statuses, Repository Board versus
   org Project rules, trust-boundary separation rules, Issue Artifact conventions, canonical label
   and archival expectations, and issue type/template baselines.
3. Evaluate **org-level defaults first** (issue types, org Projects, org `.github` templates), then
   each repository's **effective** state (native issue statuses, Repository Board posture, active
   versus archived labels, issue templates, and sample artifact/link usage where relevant).
4. Run a **fleet-consistency pass** across sibling repositories of the same class to surface quiet
   taxonomy, status, or label-archiving drift.
5. Apply the ladder's **403/404 disambiguation** and **honest degradation**: report UI-only
   surfaces (such as web-only Repository Board settings) or gated features as gates, never as drift.
6. **Cite the expectation basis** on every finding (which convention layer it came from, or freshly
   fetched official docs when no conventions exist).

## Dated caveats (re-verify live)

Constraints observed at research time (2026-11). Each is qualitative and must be re-verified live
through the ladder before relying on it.

- Native issue statuses (`planning-statuses`), Repository Boards, Issue Artifacts, symmetric
  `"Relates to"` issue links, and label archiving (`archived_at` metadata) were newer or evolving
  surfaces as of 2026-11, with uneven coverage across native `gh` subcommands, REST, GraphQL, and
  web UI. Re-verify current CLI/API reachability and response fields live before relying on this.
- Native issue status transitions were observed as of 2026-11 not to emit persisted actor-identity
  timeline events, making them unsuitable on their own for trusted-actor automation gates.
  Re-verify timeline and audit-log actor attribution live before treating native statuses as a
  security or admission boundary.
- Repository Board configuration was primarily a web/settings-UI surface as of 2026-11. Re-verify
  programmatic read/write availability live through the ladder before reporting an unreadable board
  as absent.

## Doc pointers

Stable entry hubs only. Resolve exact pages live from each hub and pass every fetch through the
ladder's fetch-integrity check before grounding on it.

- Issues and planning hub: <https://docs.github.com/en/issues>
- Projects hub: <https://docs.github.com/en/issues/planning-and-tracking-with-projects>
- REST reference hub (for the API rungs): <https://docs.github.com/en/rest>
