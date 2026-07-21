# Recipe: Actions policy

Audits the GitHub-side Actions **admin plane** — the organization and repository policies that
govern which actions may run, how the workflow token behaves, what runners and runner groups exist
and who may reach them, the compute and cache posture, and the OIDC trust that lets workflows
exchange short-lived cloud credentials. It is an admin-surface audit, not a workflow-file review:
linting the YAML *inside* `.github/workflows` stays with `actionlint` and is out of this plugin's
scope (design decision D9). Every concrete mechanic — the exact settings surface, the current
credential requirements, whether a surface is plan-gated today — is resolved at runtime through the
[method ladder](../method-ladder.md); this recipe ships the audit judgment on top of it, never a
vendored map of endpoints or scopes. The audit only reads and reports: a finding names drift, it
never mutates the setting behind it, and any remediation the reader chooses routes through the
plugin's change path with the user in the loop.

## Credential-and-gate preflight

Run the ladder's rung-0 preflight first (`gh` present, authenticated session, credential-modality
diagnosis). Then layer the area-specific gate checks below. Diagnose each against freshly fetched
docs and live probes — never assert a fixed capability table.

- **Admin layer per surface.** Org-level Actions policy and runner-group configuration answer to
  organization administration; repository-level Actions settings answer to repository
  administration. The same session may read one layer and be blocked at the other. Confirm which
  layer the current credential actually reaches before reporting any surface as absent — a block at
  the org layer is not evidence the repo layer is clean.
- **Enterprise inheritance.** Where an enterprise sits above the organization, some Actions policy
  is set at the enterprise layer and inherited downward, capping what the org can loosen. If an
  enterprise exists in the session's reach, read the inherited posture before judging an org-level
  value — an org setting that looks permissive may be constrained from above.
- **Plan-gated compute surfaces.** At research time, several compute and networking surfaces
  (larger/custom-image runners, hosted-compute networking) were gated behind higher plans and did
  not respond on lower ones. Treat a block there as a **gate to diagnose**, not a finding: apply the
  ladder's 403/404 disambiguation to separate a plan gate from a missing scope, a wrong credential
  modality, or a genuinely unset value, and resolve the current gate from freshly fetched docs.
- **Credential-modality sensitivity.** Some runner and networking surfaces accepted only specific
  credential modalities at research time. If a whole surface family fails uniformly while the docs
  say another modality is required, that is a modality gate — degrade to guidance, do not report
  drift.

## Audit-question checklist

Curated auditor questions for this area. Each is phrased so the answer is a posture, not a lookup;
resolve the current mechanics live before answering any of them.

1. Is Actions enabled or disabled at the org and repo layers in line with the declared policy, and
   where the two layers disagree, which one is actually in force for a given repo?
2. How does the org restrict which actions may run — any action, local-only, or an explicit
   allow-list — and does that match the declared posture?
3. If an allow-list is in force, is it hygienic: scoped tightly, free of stale or overly broad
   entries, and consistent with the declared expectation about verified-creator allowances?
4. Are allow-listed third-party actions expected to be pinned to an immutable revision rather than a
   moving tag, and does the live posture enforce that expectation?
5. What is the default permission of the automatic workflow token — read-only or read-write — and
   does that default match the least-privilege posture the conventions declare?
6. Can the workflow token approve pull requests or create/approve content, and is that latitude
   intended given who effectively wields the token?
7. What is the fork-PR workflow-approval policy — which contributors trigger runs automatically
   versus requiring a maintainer's approval — and does it match the declared trust boundary?
8. What self-hosted and hosted runners are registered, and for each self-hosted runner, does it
   guard the non-ephemeral and public-repository risks the current docs warn about?
9. Are self-hosted runners ephemeral (fresh per job) where the declared posture calls for it, or are
   long-lived runners carrying state between untrusted jobs?
10. How are runner groups scoped — which repositories can reach a privileged group — and is any
    sensitive group reachable by a broader repo set than intended?
11. Where larger or custom-image runners are in use, does the sizing and image posture match the
    declared cost expectation, or is expensive compute reachable without a governing convention?
12. What is the cache usage against its limits, and is eviction pressure or an unbounded cache
    footprint contradicting a declared storage or cost posture?
13. What are the retention settings for workflow logs and artifacts, and are they tuned to the
    declared retention policy rather than left at the platform maximum?
14. What OIDC cloud trusts are configured, and does the subject-claim customization posture match
    what the declared conventions expect for that trust?
15. Where OIDC could supply short-lived credentials, are long-lived cloud secrets still stored at the
    Actions layer — a replaceable exposure the audit should flag?
16. How are reusable and required workflows governed — which are mandated org-wide, and is that
    governance consistent with the declared baseline?
17. At the Actions layer, what is the secrets exposure surface by scope (org, repo, environment) at
    an inventory level — enough to flag obviously over-scoped secrets, deferring a deep secrets audit
    to its own area?

## Posture heuristics

Area-specific defaults to weigh a finding against when the conventions are silent. These are
heuristics, not rules; the exact mechanism behind each is resolved live.

- **Default-deny allowed actions.** An explicit allow-list beats "any action"; a permissive default
  with no declared rationale is a finding waiting to be confirmed.
- **Least-privilege default token.** A read-only default workflow-token permission is the safer
  posture; a read-write default warrants an explicit justification in the conventions.
- **Ephemeral self-hosted runners.** Prefer runners that are destroyed after each job over
  long-lived hosts, especially anywhere untrusted or fork-triggered code can land on them.
- **Minimally scoped runner groups.** A privileged runner group should reach the smallest repo set
  that needs it; a broad or all-repo scope on a sensitive group is worth flagging.
- **OIDC over stored secrets.** Short-lived, workflow-issued cloud credentials are preferable to
  long-lived secrets sitting at the Actions layer; standing cloud secrets that OIDC could replace
  are a reducible exposure.
- **Retention tuned down.** Log and artifact retention set below the platform maximum, toward the
  declared need, beats leaving it at the ceiling.
- **Cost-aware runner sizing.** Larger and custom-image runners should map to a declared need;
  expensive compute reachable by default invites cost drift.

## Drift comparison against declared conventions

1. Read the layered conventions per [`../conventions-file.md`](../conventions-file.md), anchoring at
   the repo root before the repo-relative reads and concatenating every layer that exists.
2. Extract the Actions-relevant declarations — statements such as "Actions may only run from
   allow-listed actions", a required token-permission default, an ephemeral-runner rule, a retention
   ceiling, or an OIDC-over-secrets expectation.
3. Compare **org-level policy first**, then each repository's **effective** state. Org policy caps
   what a repo setting can loosen, so evaluate the layering the way the freshly fetched docs define
   it rather than reading a repo value in isolation — and where an enterprise layer exists, fold its
   inherited cap in first.
4. Run a **fleet-consistency pass** across sibling repositories: a policy honored in most repos and
   quietly absent in a few is drift even when no single repo looks wrong on its own.
5. **Cite the expectation basis** on every finding — which declared convention it came from, or, when
   none exists, that the basis is a freshly fetched official-docs recommendation (name that
   provenance; never a from-memory "best practice").
6. Apply the ladder's **403/404 disambiguation** before any drift claim: a gate, a missing scope, or
   a wrong credential modality is not drift, and must never be reported as one.
7. Honor the ladder's **org-scale scoping** rule: emit findings incrementally per surface, and on a
   rate limit or partial reach, return honest partials that name exactly what was not covered.

When no conventions file exists at any layer, compare against the recommendations on the freshly
fetched official docs and label each finding's basis as docs-derived rather than consumer-declared.

## Dated caveats (re-verify live)

Constraints observed at research time (2026-07). Each is qualitative and characterized by its
source; none is a live fact today — re-verify before relying on it.

- Hosted-compute networking and custom-image surfaces were still evolving and partly plan-gated at
  research time, per the official Actions docs read that session. Re-verify live before relying on
  this.
- Some runner and networking surfaces carried credential-modality restrictions at research time,
  per the same docs read. Re-verify live before relying on this.
- Cache and larger-runner mechanics shifted within weeks during the research window, per the
  official changelog and docs read that session — treat any recalled specific as stale. Re-verify
  live before relying on this.
- Native `gh` coverage of this admin plane was narrow at research time, with most surfaces reachable
  only through the API rungs of the ladder, per the `gh` help output inspected that session.
  Re-verify live before relying on this.

## Doc pointers

Stable entry hubs only. Resolve the exact current page live from a hub and pass it through the
ladder's fetch-integrity check before grounding on it — never treat a hub as the answer, and never
hand-carry a deep URL from memory.

- Actions hub — <https://docs.github.com/en/actions>
- Actions security guides entry — <https://docs.github.com/en/actions/security-guides>
