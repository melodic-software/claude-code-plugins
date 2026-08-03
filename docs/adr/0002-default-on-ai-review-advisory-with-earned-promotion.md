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
<!-- Both halves of that mitigation are falsified; see the 2026-08-03 addendum. -->

## Addendum (2026-08-03): mechanism correction — the exception moved to a reusable default

Supersedes the 2026-07-21 addendum's description of WHERE the exception lives and WHICH actors
it covers. That addendum describes a **caller-side** `skip-actors` list naming two actors;
neither remained true.

The list stopped existing on 2026-07-30: #1766 re-pinned the lane callers to v0.9.1 and
dropped the caller's explicit `skip-actors` line, so the effective value silently became the
reusable's own default — which had widened from one actor to four three days earlier
(ci-workflows `cf666f67`, 2026-07-27). `claude[bot]` and `melodic-ai[bot]` thereby joined a
required-check exception without the deliberation the revisit trigger below demands. Neither
has exercised it (`claude[bot]` has authored no PRs in this org; `melodic-ai[bot]` none here
since the lane went live), so this is a record defect, not an exploited one.

Two corrections land with this amendment:

1. Both lane callers state `skip-actors` explicitly again, so the exception is readable in the
   repo it governs and cannot be rewritten by an upstream default change. **This is the
   mechanism, not just the record** — an inherited default is what failed.
2. The restored lists encode the FOUR actors currently in force, so the change is
   behavior-preserving. Whether four is the right set is the open question below.

`skip-actors` and the action's `allowed_bots` are different levers with different outcomes.
Removing an actor from `skip-actors` alone does NOT restore review of its PRs: the reusable
passes `allowed_bots: dependabot[bot]`, and the action throws on any other bot actor, which
this lane's fail-closed mapping turns into a required check red for a cause no push can fix.
Reviewing an agent's PRs instead of skipping them requires widening `allowed_bots` in
ci-workflows — a separate change, tracked below.

### Correction: what a skipped PR is actually still checked by

The 2026-07-21 addendum accepts the exception without naming the offsetting coverage. Naming
it accurately matters, because two plausible-sounding offsets do not hold here:

- **gitleaks does gate.** It is a STEP (`id: gitleaks`) in `ci.yml`'s `hygiene` job, not a
  check context of its own; its outcome is aggregated fail-closed into `hygiene`, which
  `ci-status` requires. It blocks merge under the name `ci-status`.
- **GitGuardian runs but does NOT gate.** `GitGuardian Security Checks` reports on every PR
  and is in no ruleset. A failing GitGuardian check does not block merge.
- **Human approval is NOT required.** The `base` ruleset sets
  `required_approving_review_count: 0`; the repo has a single collaborator, so author and
  reviewer are the same person and merges routinely carry zero approving reviews. What the
  ruleset does require is `required_review_thread_resolution: true`. Any argument resting on
  "a human reviews it at merge" is unavailable here and must not be used.

The complete required set on `main` is `pr-title / pr-title`, `do-not-merge / do-not-merge`,
`ci-status` (ruleset `ci-gate`), and `security-review / security-review` (ruleset
`security-review-gate`, which additionally grants `OrganizationAdmin` a pull-request bypass).

### Correction: the caller-tamper mitigation does not hold

The 2026-07-21 addendum names "workflow-file diffs are themselves security-review surface and
the caller file is human-reviewed" as the mitigation for a PR editing its own caller. Both
halves fail:

- The action refuses to run when the calling workflow file differs from the default branch
  ("Workflow validation failed… must have identical content to the version on the repository's
  default branch"), which is precisely the class of change the mitigation relies on. The step
  still reports success, so the reusable's `Fail closed on an in-scope non-run` step never
  fires and the required check goes GREEN with no review performed and no tracking comment —
  despite `track_progress: true`. Observed on this amendment's own PR and on #1766.
- Human review is not required (see above).

So the required check does not certify a security pass on any PR that edits the caller. This
is a real gap in what the gate proves, recorded here rather than papered over; the fix belongs
upstream in the ci-workflows outcome mapping and is filed as a revisit trigger below.

### OPERATOR DECISION POINT — ratify four actors, or revert to two

This amendment deliberately does NOT decide the actor set. **If the amendment lands without an
explicit pick, Branch A is what merges** — silence ratifies four. Stating that so it is a
choice, not a default reached by inattention.

- **Branch A — ratify the widened exception (keep four).** The affirmative case: both added
  actors are dormant, so the exception costs nothing observable today; and the lane's value on
  agent-authored chore PRs (dependency re-pins, sync materializations, doc-queue churn) is low
  relative to its spend. Note the 2026-07-21 rationales do NOT extend here — "byte-exact
  upstream content" is specific to `melodic-standards-sync[bot]`, and "human review at merge"
  is unavailable in this repo. Branch A must stand on dormancy and cost, not on those.
- **Branch B — revert to the ratified two.** The affirmative case: the required check's entire
  claim is that a security pass ran, and `claude[bot]` is precisely the actor whose output an
  independent pass is most useful against; two actors entered the exception with no
  deliberation, and the conservative repair is to restore the scope that was actually ratified
  rather than bless the accident. Cost: their PRs would hit the actor gate and fail closed, so
  Branch B is only coherent alongside the `allowed_bots` change — otherwise it converts a
  dormant record defect into a live merge block the moment either actor opens a PR.

On effort: Branch A needs no edit only because this amendment restored the four-actor list to
stay behavior-preserving. Had it restored two, Branch B would be the no-edit branch. The
asymmetry is an artifact of drafting, not evidence for either side.

## Revisit triggers

- The security lane's findings prove precise over a sustained window → open the promotion
  change (blocking on CRITICAL) citing the evidence.
- The general lane's advisory threads measurably gate merges again (#618's class) → tune
  scope before considering demotion.
- ci-workflows ships a release changing either reusable workflow's contract → re-pin the
  callers through the ordinary Dependabot/SHA-bump path.
- A merge queue is enabled on the base → the security workflow must add the `merge_group`
  trigger, or its required check is never reported for queued PRs (a required check that never
  runs blocks the merge).
- An actor is added to the caller's `skip-actors` list → the step-3 skip-actor exception
  widens; re-deliberate before landing, and record the rationale beside the addendum above.
  This trigger also fires when the caller STOPS stating the list: an inherited default is an
  undeclared exception, and it is what the 2026-08-03 amendment repairs.
- Agent actors begin authoring substantive changes under security-sensitive paths → the skip
  stops being cheap; widen `allowed_bots` in the ci-workflows reusable so those PRs are
  reviewed rather than skipped, instead of narrowing `skip-actors` alone (which fails closed).
- ci-workflows maps an action-side workflow-validation skip to a non-run → the caller-tamper
  gap recorded in the 2026-08-03 addendum closes, and the required check begins certifying
  execution on caller-editing PRs. Until then, treat a green `security-review` on any PR that
  touches `.github/workflows/claude-security-review.yml` as unproven and review it by hand.
