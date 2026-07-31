# Default-on AI review: advisory lanes with earned promotion to blocking

- Status: accepted
- Date: 2026-07-20

## Context

Boris Cherny's step-2 posture ("Steps of AI Adoption", Jul 16 2026) names "Automated code
review and security review are on by default"; the AI-adoption-ladder residue items #696
(default-on review decision + wiring) and #509 (no dedicated security-review pass) carried
the two open choices: promote the LLM review lane from advisory to blocking or keep it
advisory with a recorded promotion trigger, and where a dedicated security pass runs.

Evidence in hand at decision time: the LLM code-review lane (`claude-review` reusable
workflow, consumed by this repo's caller) already auto-invokes on every PR event —
default-on is satisfied for invocation; the open question was gating. #618 documents the
noise cost of advisory bot threads blocking merges on every PR; the WP5 guardrail work
ratified the verification-promotion discipline (a gate flips from advisory to blocking only
on demonstrated precision — an earned flip with a ratified record, trust before scale).
2026-07-20 transcript mining (548 real permission prompts; #697's evidence) reinforced that
review friction compounds fast at fleet scale.

## Decision

1. **Both AI review lanes are DEFAULT-ON and ADVISORY**: the general code-review lane on
   every PR (existing caller), and the dedicated security-review lane
   (`claude-security-review` reusable workflow, ci-workflows) wired by this repo's caller
   with a PATH FILTER over security-sensitive surfaces — workflows, scripts, hooks, shell,
   and permission/settings configuration. Path filtering is the scope control that keeps
   default-on affordable in a doc-heavy repo: most PRs are prose and get the general lane
   only.
2. **Promotion to blocking is earned, not assumed**: either lane flips to a required gate
   (security: blocking on CRITICAL findings) only after its precision is proven over a
   sustained window, recorded as a reviewed change citing that evidence — mirroring the
   WP5 verification-promotion discipline. No calendar-based flip.
3. **Severity vocabulary**: the security lane reports CRITICAL/IMPORTANT/SUGGESTION with a
   confidence axis, matching the review-toolkit convention.

This is the interim posture pending #509's enforcement design session (operator-deferred,
2026-07-19): how the pipeline enforces and evidences that a security pass ran on every PR is
that session's question, and it may promote the security lane to a required gate on its own
terms without a further precision window.

## Addendum (2026-07-21): #509 enforcement ruling

The #509 enforcement design session ruled. Execution evidence — proof that the security pass
RAN on every PR — is promoted to a **required status check** on the protected base, so a PR
cannot merge without the security workflow having reported. A diff with no security-sensitive
surface gets an explicit not-applicable verdict from a **job-level conditional** inside the
always-running workflow — never workflow-level `paths` filtering, which would leave the required
check **Pending** forever and wedge every prose PR. The required check proves the pass ran; it
does not gate on the verdict.

Implementation ordering is load-bearing: as of this addendum the caller still uses
workflow-level `paths` filtering, so the ruleset must NOT mark this check required until the
caller restructure (always-running workflow, job-level conditional) has landed — flipping the
requirement first would wedge every prose PR exactly as described above. Sequence: caller
restructure (this repo) → workflow always-report shape (ci-workflows) → required check
(github-iac ruleset), each verifiable before the next.

VERDICT gating is unchanged: the security lane stays **advisory** per the guardrail matrix's
knob floors and this ADR's earned-promotion discipline (Decision §2). The ruling promotes
*execution evidence to required*, not *findings to blocking* — flipping the verdict to blocking
still requires the earned precision window.

Evidence model: the **check run** is canonical — API-queryable, and creatable only by the App
that runs the pass, so a branch cannot forge it. A workflow-applied **label** is a glance layer
only; labels are Triage-flippable — any actor with Triage access or above can add or remove one,
a lower bar than the App-only check creation — so a label is never evidence that the pass ran;
the required check is.

Attribution: this enforcement is the operator's mandate backed by verified consensus practice —
OpenSSF Scorecard's branch-protection criteria, GitHub's protected-branch documentation, and
NIST SP 800-218A's same-bar-for-agent-and-human principle — **not** the source playbook, which
never prescribes a merge gate. The playbook grounds default-on invocation (Boris step-2); the
required-check enforcement is ours. A merge-queue revisit trigger is recorded below.

## Addendum (2026-07-21): ordering correction

Implementation order is corrected to ci-workflows-first: the reusable workflow gains a
backward-compatible `paths` input plus an internal job-level gate, then this caller adopts that
input (dropping its workflow-level `paths` filter), then the github-iac ruleset flips the
execution check to required. A caller-side job-level `if:` on the `uses:` job is not viable — a
skipped `uses:` job registers a *different* check name, so the child context stays "Expected"
and wedges prose PRs (community discussion 72708); the gate must live inside the reusable
workflow. Caller-first against the old pin was also rejected: it would run a full security pass
on every prose PR in the interim. The load-bearing constraint is unchanged — the ruleset flip
stays LAST, after this caller restructure is verified
([troubleshooting-required-status-checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks)).

## Addendum (2026-07-21): step 3 applied — required check live; skip-actor exception

The execution check is live: the `security-review-gate` org ruleset (github-iac, property-gated
on `requires-security-review`; this repo is the sole opt-in) requires the
`security-review / security-review` context on main. Verified end-to-end before the flip: the
context name was captured before the restructure and unchanged after; a docs-only PR reported
the context with conclusion=skipped (name-stable, treated as passing), so prose PRs cannot
wedge.

**Skip-actor exception (operator-ratified 2026-07-21):** actors in the caller's `skip-actors`
list — `dependabot[bot]`, `melodic-standards-sync[bot]` — skip the review job, so their PRs
satisfy the required check with no review run, including changes under security-sensitive
paths. Accepted deliberately: Dependabot pin bumps are already forced through the reviewed
runner-policy contract (an input-surface change declines auto-approval and requires a
standards-reviewed policy entry), and standards-sync PRs materialize byte-exact content
reviewed upstream. Bounded scope: the exception covers exactly the listed actors; adding an
actor to `skip-actors` widens the exception and warrants the same deliberation.

Two structural bounds on what the required check proves: it evidences that the workflow-side
gate ran (or judged not-applicable) — and because `pull_request` workflows execute the PR
branch's caller file, a PR can alter its own `paths` input or `skip-actors` on its head; the
mitigation is that workflow-file diffs are themselves security-review surface and the caller
file is human-reviewed. This is the consensus-accepted bound of Actions-based required checks,
not a defect introduced here.

## Addendum (2026-07-31): skip-actor exception re-deliberated — widening rejected

The step-3 revisit trigger fired, through a channel it did not name. The v0.9.1 lane re-pin
deleted both callers' explicit `skip-actors` lists so each inherited the reusable workflow's
default — `dependabot[bot],claude[bot],melodic-ai[bot],melodic-standards-sync[bot]` — silently
widening the exception above from two actors to four (#1767).

**Ruling: the widening is REJECTED for the security lane.** The caller
(`.github/workflows/claude-security-review.yml`) restores an explicit
`skip-actors: "dependabot[bot],melodic-standards-sync[bot]"`, re-narrowing the exception to
exactly the two actors the step-3 addendum ratified. The general lane (`claude-review.yml`)
**keeps inheriting** the default: it is advisory with no required check, so its skip list is
runner-minute economy, not evidence.

Rationale:

1. **Each ratified actor carries a compensating control; the two new ones carry none.**
   Dependabot pin bumps are forced through the reviewed runner-policy contract and standards-sync
   PRs materialize byte-exact upstream-reviewed content (step-3 addendum above). `claude[bot]` and
   `melodic-ai[bot]` have no analogue — and the general review lane skips them too, so an
   AI-app-pushed commit would satisfy the required security check with zero review of any kind.
   AI-authored change is precisely the provenance class this lane exists to cover (NIST SP
   800-218A's same-bar principle, already this ADR's attribution basis).
2. **Latency is not absence.** No workflow here lets either app push today — no `@claude`
   dispatcher exists in this repo — so the channel is dormant. The path to it is charted, not
   speculative: an org-wide `@claude` mention-responder lane is proposed as
   [ci-workflows#255](https://github.com/melodic-software/ci-workflows/issues/255). Its V1 is
   deliberately read-only (no Edit/Write, no push), so adopting V1 would *not* open the channel;
   its V2 — tag-mode fix-and-push, behind that issue's own approval gate — would, and in tag mode
   the action pushes to the PR's own branch. So the activating change is a gated future step
   rather than an imminent one, which is exactly when a fail-closed exception is cheap to set:
   the bypass must not already be pre-authorized when that gate is considered on its own merits.
3. **Staleness asymmetry decides inheritance-vs-explicit for an evidence gate.** A stale explicit
   list fails **closed** (an actor gets a review it may not have needed — a visible cost); a stale
   inherited default fails **open** (an actor this repo never deliberated skips review silently —
   exactly what the re-pin did). The fleet's inheritance-over-explicit-list decision stands for
   defaults that are cost/config; an evidence-gate exception is the deliberate-divergence case the
   caller seam exists for, and the runner-policy `allowedInputs` contract makes that divergence a
   reviewed, standards-visible act.

Rejected alternatives:

- **Accept and document the widened exception** — converts a cost optimization into an
  unreviewed-provenance bypass of a required check, contradicting the step-3 addendum's own
  bounded-scope clause with no compensating control.
- **Narrow the reusable workflow's default upstream (ci-workflows)** — not chosen as *this repo's*
  fix: that default serves every consumer and its self-trigger/cost rationale is legitimate for
  advisory lanes. Whether ci-workflows should split the security reusable's default from the
  review one is ci-workflows' own deliberation, filed there as
  [ci-workflows#330](https://github.com/melodic-software/ci-workflows/issues/330) — a follow-up,
  not a blocker here.
- **Do nothing, relying on human merge review of AI-provenance PRs** — process convention, not a
  technical control. The required check exists to be evidence.

Cross-vendor advisory (Codex, gpt-5.6-sol) concurred with the explicit narrow list. Strongest
counterargument recorded: if the apps later gain push capability, the narrow list risks
self-triggering recursion, extra spend, and "independent" review by substantially the same AI
system. Accepted — those are visible availability and cost failures, while the inherited default's
failure mode is a silent security bypass, the worse direction.

Composition with the github-iac work:
[github-iac#248](https://github.com/melodic-software/github-iac/pull/248) (merged
2026-07-30) app-pins all four required contexts — `pr-title / pr-title`,
`do-not-merge / do-not-merge`, `ci-status`, and `security-review / security-review` — to the GitHub
Actions app (`integration_id` 15368), narrowing *who may report* a check. That is orthogonal and
complementary to this ruling, which narrows *when the check may be satisfied without a review run*.
[github-iac#228](https://github.com/melodic-software/github-iac/issues/228) remains open for the
live forgery test; this addendum deliberately does **not** touch the "creatable only by the App
that runs the pass, so a branch cannot forge it" sentence in the step-3 enforcement addendum — that
sentence stays github-iac#228's to update from the tested result.

Sequencing (fail-closed, deliberate): `policy.json` is a managed materialization of the standards
`runner-policy` component, and the contract for `claude-security-review.yml@c136b27` admitted only
`runner` and `paths-file`, so restoring the input is an input-surface change that lands upstream
first — standards contract PR → standards-to-here sync PR → this caller and addendum. This repo's
`runner-policy` check stays red until the sync merges.

**Residual gap (open, not fixed here):** the runner-policy validator rejects *unexpected* inputs
but cannot *require* one, so a future re-pin that again drops the caller's `skip-actors` passes CI
and silently re-widens the exception. Closing it needs a `requiredInputs`-style contract field
upstream, filed as
[standards#308](https://github.com/melodic-software/standards/issues/308); until that lands the
guard is the rewritten revisit trigger below plus the caller-side comment beside the input.

## Revisit triggers

- The security lane's findings prove precise over a sustained window → open the promotion
  change (blocking on CRITICAL) citing the evidence.
- The general lane's advisory threads measurably gate merges again (#618's class) → tune
  scope before considering demotion.
- ci-workflows ships a release changing either reusable workflow's contract → re-pin the
  callers through the ordinary Dependabot/SHA-bump path. Not a rubber stamp for the security
  caller: a re-pin is one of the two channels that widens the skip-actor exception (below).
- A merge queue is enabled on the base → the security workflow must add the `merge_group`
  trigger, or its required check is never reported for queued PRs (a required check that never
  runs blocks the merge).
- The security caller's effective `skip-actors` set gains an actor, through **either** channel →
  the skip-actor exception widens; re-deliberate before landing and record the rationale beside
  the addenda above. Channel A: the caller's explicit list is edited. Channel B (the one that
  actually fired, #1767): the caller's explicit list is deleted or the reusable workflow's pin
  moves, so the *inherited default* supplies the set — CI stays green either way, because
  runner-policy rejects unexpected inputs but cannot require one. Reviewing a re-pin of
  `.github/workflows/claude-security-review.yml` therefore means diffing the new pin's
  `skip-actors` default against the caller's explicit list, not just the SHA.
