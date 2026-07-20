# Recipe: rulesets and repo-settings drift

This is the fleet-consistency recipe. Where the generic [method ladder](../method-ladder.md)
resolves *how* to read any one surface, this recipe supplies the area-specific judgment for the
`rulesets` row: the questions worth asking about repository and organization rulesets *and* about
general repo-settings drift, the heuristics that separate real exposure from noise, and a drift
procedure that compares each repo against declared conventions *and* against its siblings. It adds
curation, not mechanics — every endpoint, credential requirement, and plan gate is resolved live
through the ladder at invocation time, because those move on a timescale no vendored table survives.
Read the ladder first; this recipe assumes its rungs, its fetch-integrity rule, its 403/404
disambiguation, and its org-scale scoping already apply.

## Credential-and-gate preflight

On top of the ladder's rung 0, this area needs a few diagnoses before any finding can be trusted.
Run them as steps, resolving each requirement from freshly fetched docs plus a live probe — never
from an assumed capability table.

- **Visibility tier.** Org-level rulesets and per-repo rulesets are distinct surfaces with distinct
  read paths and distinct owner requirements. Determine which the current session can see: a session
  that reads repo rulesets fine may be blind to the org layer entirely. Do not report an unseen org
  layer as "no org rulesets" — that is a visibility gate, and the ladder's 403/404 disambiguation
  decides which.
- **Detail depth by role.** Some rule details and, in particular, the *bypass list* on a ruleset are
  only returned to a caller with sufficient administrative standing. A ruleset that reads as having
  an empty or absent bypass list may simply be under-privileged reading. Probe whether full detail
  is available before treating any bypass finding as complete; degrade honestly if not.
- **Plan gating (state qualitatively, verify live).** At research time some ruleset behaviors were
  plan-gated — for example, certain enforcement on private repositories and some ruleset *types*
  were observed to require a paid tier, and one enforcement mode was tied to the highest tier. Treat
  these only as "expect a gate here, confirm it live": fetch the current docs for the specific type
  and mode in play and probe, rather than asserting a tier from this paragraph.
- **Fork and private-repo differences.** Forks and private repositories can present a different
  effective governance surface than public repos on the same account. Note the repo's visibility and
  fork status as part of each reading so a difference is attributed to the surface, not miscalled as
  drift.

When any of these blocks a reading, name the gate (visibility, role, plan, modality) per the
ladder's honest-degradation rule and continue with the rest of the fleet rather than shrinking the
claim.

## Audit-question checklist

Curated questions for this area — each is auditable, and none reduces to "fetch the docs and look".
Ask them across the scoped set of repositories, emitting findings incrementally.

1. Which repositories carry no ruleset and no legacy branch protection at all — governed by nothing?
2. Where do org-level rulesets and per-repo one-off rules both target the same branch, and how do
   they layer — does a per-repo rule shadow, weaken, or duplicate the org baseline?
3. Who and what sits on each ruleset's bypass list — which actors, apps, and roles — and has that
   list grown beyond a small, named set with a stated reason?
4. Which rulesets are disabled or in an evaluate/non-enforcing mode, so they look protective in a
   listing but enforce nothing on a real push or merge?
5. Do sibling production repositories agree on required reviews — count, code-owner requirement,
   dismissal behavior — or does the same class of repo enforce different review floors?
6. Do those same repos agree on required status checks and on signed-commit / signature
   requirements, or does one production repo quietly require less than its peers?
7. Where do legacy branch protections and newer rulesets coexist on one repo, and do they conflict,
   double up, or leave a gap each assumed the other covered?
8. What does each ruleset actually target — only the default branch, all branches, tags, or a
   pattern — and does the target pattern leave release branches or tags unprotected?
9. Does merge-strategy configuration drift across the fleet — which merge types are allowed, and is
   auto-delete-of-merged-branches set consistently for repos in the same class?
10. Is default-branch naming consistent across sibling repos, or do some still diverge from the
    declared convention?
11. Does repository visibility match intent per repo (no repo more open than its class should be),
    and is the forking policy consistent across the fleet?
12. Are ancillary surfaces — wikis, issues, projects, discussions enablement — set consistently
    where the repo class implies they should be, rather than left at per-repo defaults?
13. Are archived repositories actually locked down (governance frozen, not silently mutable), and do
    any carry stale bypass entries or protections that no longer mean anything?
14. Do the account's new-repository defaults match what settled repos actually run, so freshly
    created repos start compliant instead of drifting from day one?
15. For every repo that deviates from its class baseline, is the deviation a declared,
    rationale-bearing exception — or an undocumented one-off nobody decided on purpose?
16. Across the whole set, does any protection or setting drift *toward the loosest* configuration
    present — i.e. is the fleet converging on the weakest sibling rather than the declared floor?

## Posture heuristics

Area-specific judgment for turning readings into findings. These frame *what good looks like*; the
exact mechanism behind each is resolved live.

- **Org-ruleset-first over per-repo copies.** A rule that belongs to a whole class of repos is
  better expressed once at the org layer than copied into each repo, where copies drift apart. Flag
  per-repo rules that merely re-implement an org baseline as consolidation candidates, and flag
  classes with no org-layer baseline at all.
- **Smallest possible bypass lists, each with a named rationale.** A bypass entry is a hole in the
  rule by design; every actor, app, or role on it should trace to a specific, stated reason.
  Unexplained or broad bypass membership is a finding even when nothing has misused it yet.
- **Enforce over evaluate for settled rules.** Evaluate/non-enforcing mode is for rules still being
  trialed. A rule that has been in evaluate mode long enough to be considered policy but never
  promoted to enforcing is protection theater — surface it as such.
- **Consistency classes, not one global baseline.** Production, sandbox, and archived repos are
  legitimately held to different declared baselines. Compare each repo against its own class's
  expectation, and treat a repo that appears mis-classed (a sandbox setting on a production repo)
  as its own finding.
- **Prefer declarative governance where the consumer routes for it.** When the consumer's routing
  declares that governance is managed as code, hand-drift away from that source is itself the
  finding; report the divergence rather than proposing an out-of-band fix.
- **Detect drift toward the loosest.** When siblings disagree, the risk is the fleet quietly
  standardizing on the weakest member. Call the direction of drift, not just its existence.

## Drift comparison against declared conventions

This is the recipe's core procedure. It runs after the preflight has established what the session
can actually see.

1. **Load the declared posture.** Read the layered conventions per
   [`../conventions-file.md`](../conventions-file.md) and extract every governance declaration that
   bears on this area — statements like "every production repo carries the org default ruleset",
   review floors, required checks, signing, merge-strategy and default-branch conventions, and any
   declared exceptions with their rationale.
2. **Enumerate the target repositories** per the ladder's org-scale scoping rule: area-scoped by
   default, confirm before an all-org sweep, emit findings incrementally, and on rate limiting stop
   cleanly and name exactly which repos were not reached. A partial fleet pass is honest; a silently
   shrunk one is not.
3. **Read each repo's effective state**, applying the ladder's fetch-integrity check to any docs
   used for grounding and its 403/404 disambiguation to every gap *before* it becomes a claim — an
   unseen surface is a gate, not an absence, and never a drift finding on its own.
4. **Compare against the declared baseline.** For each repo, measure its effective governance
   against its class's declared expectation. Every finding cites its expectation basis — which
   convention layer and statement it rests on — so a reader can tell a consumer standard from a
   docs-derived one.
5. **Compare against siblings — the fleet-consistency pass.** Independently of any declared
   convention, compare repos of the same class against each other. Mutual disagreement is its own
   finding *class*: report it as an inconsistency (with the direction of drift), not as a violation,
   since without a declared baseline there is no "correct" side — only divergence worth a decision.
6. **When no conventions exist at all,** compare each repo against the recommendations in the
   freshly fetched official docs and name that provenance explicitly, exactly as
   [`../conventions-file.md`](../conventions-file.md) prescribes — never a from-memory "best
   practice".
7. **Attribute every deviation before reporting it.** A gap is drift only once the preflight and the
   ladder's disambiguation have ruled out visibility, role, plan, and modality causes. Anything
   still ambiguous is reported as a gate to resolve, not as a violation.

## Dated caveats (re-verify live)

Constraints observed at research time (2026-07), from official GitHub docs and live CLI/API probes.
Each is a starting expectation, not a current fact — the mechanics move on a weeks-scale timescale.

- Some ruleset types and some enforcement behavior on private repositories appeared to be
  plan-gated, and one non-enforcing evaluation mode appeared tied to the highest tier. The exact
  tiers had already shifted at least once before research time. Re-verify live before relying on it.
- Legacy branch protections and newer rulesets coexisted, with layered evaluation semantics that the
  official docs — not this recipe — own. Which layer wins in a given conflict is doc-owned and was
  changing. Re-verify live before relying on it.
- Full rule detail and bypass-list contents were only returned to sufficiently privileged callers,
  so an under-privileged read could understate a ruleset's real configuration. Re-verify live before
  relying on it.
- Some organization-governance surfaces required elevated or specific credentials, and native CLI
  coverage of this area was uneven versus the underlying API. Which operations had first-class CLI
  support was drifting release to release. Re-verify live before relying on it.

## Doc pointers

Stable entry hubs only. Resolve the exact current page live from the hub (or the site's own search)
and pass every fetch through the ladder's fetch-integrity check before grounding on it — never treat
a hub as the answer, and never substitute a from-memory deep link.

- Repositories hub — <https://docs.github.com/en/repositories>
- Organizations hub — <https://docs.github.com/en/organizations>
