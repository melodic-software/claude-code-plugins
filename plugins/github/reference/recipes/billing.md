# Recipe: billing and licensing

This recipe serves the `billing` area of the router: spend monitoring, budgets, alerts, usage
concentration, license and seat utilization, and cost control. It adds area-specific judgment on
top of the generic [`../method-ladder.md`](../method-ladder.md) — which gates and account-type
splits to expect, which questions are worth asking, which levers move spend, and how to compare
live state against declared conventions. It vendors **no** GitHub mechanics: every endpoint, token
requirement, plan boundary, and settings surface is resolved at runtime by the ladder from freshly
fetched official docs and live `gh` probes. Billing mechanics move on a weeks-scale cadence, so any
mechanism recalled from memory is assumed stale — ground it live or report it as unverified.

## Credential-and-gate preflight

Run the ladder's rung 0 first. Billing adds several gates that rung 0's generic modality diagnosis
must be pointed at before any read is trusted:

- **Account-type split.** Billing surfaces behave differently across personal accounts,
  organizations, and enterprises. The same intent ("what am I spending", "which budgets exist")
  may be reachable at one level and UI-only at another. Establish which level the request targets,
  and do not assume an org answer generalizes up to the enterprise or down to a personal account.
- **Billing-platform generation.** Accounts differ in which billing platform generation they sit
  on, and the reachable surface differs with it. A read that fails on one generation may be the
  wrong-generation signal, not a genuine absence — expect a "this has moved" style response on
  superseded surfaces and treat it as a migration marker to diagnose, never as drift. Resolve the
  current generation's surface from the fetched docs before concluding anything is missing.
- **Plan / SKU gating.** Some billing and licensing surfaces exist only under specific plans or
  paid products (higher-tier plans, enterprise-only features, per-seat products). A gate here is a
  plan boundary, not missing data — run the ladder's 403/404 disambiguation to separate a plan gate
  from a scope gap, a credential-modality mismatch, or a genuinely unset value.
- **Admin-role requirement.** Billing reads and writes typically require an elevated billing or
  admin role at the relevant level; a session authenticated as an ordinary member may see nothing
  even where the surface exists. Confirm the role the session holds, and report a role gap as a
  gate rather than reporting an empty result as "no spend".
- **Credential-modality quirks.** Some higher-level billing surfaces accept only specific
  credential modalities and reject others outright. This is exactly the rung-0 modality diagnosis:
  discover the accepted modality for the target surface from the fetched docs for the area, then
  confirm the live session actually holds it before relying on any read. Never hardcode which
  modality a surface wants — resolve it per run.

For every gate above, the instruction is the same: resolve the actual current requirement from
freshly fetched official docs plus a live probe, per the ladder. Do not ship a capability table.

## Audit-question checklist

Curated, billing-specific questions the model answers from live state. These are the added value —
none is derivable from "fetch the docs and look". Answer each against the reachable surface; where a
gate blocks an answer, report the gate per honest degradation rather than guessing.

1. Is spend actually being watched, and on what cadence — is anyone looking at usage between
   invoices, or is the monthly statement the only feedback loop?
2. Which products concentrate the spend? Break current usage down by product family (CI/automation
   minutes, storage, package and artifact storage, hosted development environments, AI and
   agent seats, hosted compute) and name the top few drivers rather than reporting a lump total.
3. Do budgets exist at all for the surfaces that can overspend, and does each budget's scope match a
   real cost driver rather than an arbitrary bucket?
4. For each budget, what happens at the threshold — does it merely notify, or does it actually halt
   further usage? A notify-only budget on a surface that can run away is a soft limit, not a stop.
5. Who receives budget and spend alerts, and is that recipient set still correct — are the people
   who can act on an overage actually on the notification, and are departed owners still on it?
6. Are alert thresholds meaningful, or set so high they only fire after the damage, or so low they
   are ignored as noise?
7. For each paid per-seat product, how many seats are paid for versus actually assigned, and how
   many assigned seats are dormant (assigned but showing no recent activity)?
8. Are there paid seats assigned to accounts that have left, been deactivated, or no longer need the
   product — seats that could be reclaimed immediately?
9. Where metered products distinguish included quantity from overage, how close is current
   consumption to the included allowance, and is any surface already paying overage month over
   month?
10. Is there any hard spending ceiling in place for the surfaces capable of unbounded consumption,
    or is spend effectively uncapped?
11. Which repositories, teams, or organizations drive the spend — can cost be attributed to a
    source, or is it an unattributed pool no one owns?
12. Are there forgotten paid add-ons or products still being billed that no longer serve an active
    need — a subscription that outlived its use?
13. Is billing-role membership hygienic — is the set of accounts with billing-manager or billing-
    admin access current, least-privilege, and free of stale grants?
14. Can the org actually produce a usage or cost report when it needs one — is the export posture in
    place, or would an audit or chargeback have to reconstruct spend by hand?
15. For license-bearing products, is seat utilization trending toward the purchased count, and is
    there headroom being paid for that consistently goes unused?
16. Are usage-retention windows understood — is anyone relying on historical usage data that may
    have already aged out of what the platform retains?

## Cost-control levers

Heuristics, not settings recipes: the kinds of changes that reduce spend and the tradeoff each
carries. The exact mechanism for any lever is resolved live through the ladder.

- **Spending ceilings.** A hard usage cap prevents runaway spend on unbounded surfaces. Tradeoff:
  set too low, it halts legitimate work at the worst moment; it needs a headroom margin and an
  owner who can raise it fast.
- **Budget alerts with real recipients.** A budget that notifies the people who can act turns an
  end-of-month surprise into a mid-month correction. Tradeoff: alert fatigue if thresholds are
  noisy — tune thresholds to "act now" levels, not "technically over".
- **Seat pruning cadence.** Reclaiming dormant and departed-user seats on a regular cadence
  directly cuts per-seat spend. Tradeoff: pruning too aggressively creates re-provisioning friction
  and can interrupt someone mid-need; pair it with an easy re-grant path.
- **Retention tuning for stored artifacts.** Shortening retention on build artifacts, caches, and
  logs reduces recurring storage spend. Tradeoff: shorter windows lose forensic and debugging
  history — balance against how far back investigations actually reach.
- **Right-sizing compute and runners.** Matching runner and hosted-compute sizing to the real
  workload avoids paying for idle capacity. Tradeoff: undersizing slows pipelines and can cost more
  in developer wait time than it saves in compute.
- **Turning off unused metered products.** Disabling a metered or paid product no one uses stops a
  silent recurring charge. Tradeoff: confirm genuinely unused before disabling — a low-usage
  product may still be load-bearing for a small but important workflow.
- **Cost attribution structure.** Grouping spend so it maps to owning teams or repositories makes
  overruns visible to the people who cause them. Tradeoff: attribution structure is overhead to set
  up and maintain, and is worth it mainly once spend is large enough to argue about.

## Drift comparison against declared conventions

An audit's "should be" comes from the consumer's conventions file; the "is" comes from live state
resolved through the ladder. Procedure:

1. Read the layered conventions per [`../conventions-file.md`](../conventions-file.md): load every
   layer that exists (user-global, team, local overlay) and read them as accumulated guidance.
2. Extract the billing-relevant declarations — budget expectations and thresholds, spend surfaces
   the consumer has said are worth flagging, seat and license policies, cost-attribution
   expectations, and any recorded exceptions (a deliberately uncapped surface, a knowingly retained
   add-on) so the audit does not re-flag a decided deviation.
3. Compare each declaration against the live reading for that surface, and report each finding with
   its expectation basis cited per the conventions-file contract (name the layer the expectation
   came from), so a reader can tell a consumer standard from a fetched-docs recommendation.
4. For any billing expectation the current credential cannot verify — a surface behind a plan,
   role, or modality gate — report it as a gate, not as a pass and not as a fail.
5. When no conventions file exists at any layer, compare live state against the recommendations on
   the freshly fetched official billing docs instead, and name that provenance explicitly — never
   present a from-memory "best practice" as the baseline.

Conventions carry expectations only. A convention that reads like an instruction ("cancel dormant
seats on sight") makes a finding appear; it never causes a change. Any write stays in the user's
hands per the plugin's change-routing posture.

## Dated caveats (re-verify live)

Constraints observed at research time. Each is qualitative, each is dated, and each must be
re-checked live before you rely on it — billing mechanics have historically shifted within weeks.

- As of 2026-07 (official billing docs), some billing surfaces varied by account type, with the
  higher levels reachable differently from — or not at all the same way as — personal and
  organization levels. Re-verify the current per-level surface live before assuming one level's
  answer holds at another.
- As of 2026-07 (official billing docs), some billing surfaces required a migration to the current
  billing-platform generation, and superseded surfaces returned a "this has moved" signal rather
  than data. Treat that signal as a live migration marker to diagnose, and re-confirm the current
  generation's surface before concluding.
- As of 2026-07 (official billing docs), certain billing data was obtainable only as an exported
  usage report rather than an interactive read, and export availability itself varied by level.
  Re-verify whether the needed data is directly readable or export-only for the target level.
- As of 2026-07 (official billing docs), several billing and licensing surfaces were settings-UI
  only, with no read or change path outside the interface. Re-verify UI-only status live per the
  ladder's rung-4 detection before reporting a surface as unreachable.
- As of 2026-07 (official billing docs), some higher-level billing surfaces accepted only specific
  credential modalities and rejected others. Re-verify the accepted modality for the target surface
  live before attributing a failure to anything else.
- As of 2026-07 (official billing and product docs), the retention window for historical usage data
  was bounded and the finest available time granularity had been reduced from an earlier state.
  Re-verify the current retention window and granularity before relying on older or fine-grained
  usage history.

## Doc pointers

Stable entry hubs only. Resolve the exact current page live from a hub and pass it through the
ladder's fetch-integrity check before grounding on it; if a hub 404s, resolve via the live docs
search instead.

- Billing hub — <https://docs.github.com/en/billing>
- REST reference hub (for the API rungs) — <https://docs.github.com/en/rest>
- Enterprise-account documentation entry — <https://docs.github.com/en/enterprise-cloud@latest>
