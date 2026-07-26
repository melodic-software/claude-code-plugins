# Loop-lane convention — changelog

Notable changes to the loop-lane contract. The contract is versioned by SemVer; a change to the
topology, the escalation contract, the capability-tier vocabulary, or any loop-layer invariant is a
major bump, and additive guidance is a minor bump. A new model release re-audits the capability-tier
table (§3) and is recorded here.

## 3.0.0 — 2026-07-25

Repo-owner-ratified addition of a single named, explicit-argument exception to the seam-only merge
rung, requested and scoped in
[melodic-software/claude-code-plugins#1309](https://github.com/melodic-software/claude-code-plugins/issues/1309).
A change to the autonomy-ladder invariant is a major bump per this file's own rule.

- **Autonomy ladder** — a caller who explicitly types the literal `autopilot` tier keyword (never
  inherited, never defaulted, never seam-supplied) widens that single invocation's merge authority up
  to and including C3, in a repository that has already adopted the baseline rung. Persists nothing
  to config; is not a substitute for the recorded C3-autonomous seam flip. **C4 (structural) and C5
  (untrusted-provenance) stay unconditionally human-gated** — no rung, seam, or argument, including
  this one, ever reaches them, per the autonomy matrix's own "never promotes" cells. The exception
  lifts only the *raise* restriction: an explicitly argued lower rung is still honored after it, and
  C5 is derived from the PR's own provenance rather than the linked item's recorded class, so a fork
  PR closing an internally-classified C2/C3 item is outside the exception.
- **Human blocking feedback, operator-parked items, and merge conflicts stay outside the dispatch.**
  A `CHANGES_REQUESTED` review, explicit human blocking language, or an unresolved inline human
  thread remains a stop-and-ask condition the exception does not amend. An item wearing the §2 role
  label *without* the machine escalation marker is operator-parked and belongs to the attended
  queue, so the label alone never authorizes a dispatch. Conflicts route to a lane's merge-only
  conflict path, never a rebase.
- **The floor reads the pull request, and the dispatch holds its lease.** C5 follows the code's
  provenance and C4 the diff's blast radius, both derived from the PR rather than the linked item's
  stamp, with a class/diff mismatch failing closed; a repository-owner allowlist never substitutes
  for the provenance test. The provenance test is executable, not a vibe: a cross-repository head,
  or an author the provider does not attest as an owner or member of the base repository — an
  outside collaborator on a base-repository branch is external despite a same-repository head — and
  an unavailable signal fails closed to C5. The floor's verdict attaches to the exact head SHA it
  examined: any later push, the resolver's or the merge-capable worker's own, re-derives the
  verdict before any merge. The dispatch runs under the PR's own worker lease and resolves its
  capability tier through §3's binding, never a family alias fixed in a lane.
- **Capability tiers** — the explicit-`autopilot` exception's frontier-tier dispatch additionally
  requires context independence: no shared conversation history with whatever produced or previously
  reviewed the PR. A same-context or self-continuation dispatch does not satisfy the exception even at
  the frontier tier.

## 2.0.0 — 2026-07-24

Tier ratified as **major**. Both corrections touch a shared invariant: B4 replaces a stated
operating assumption every consuming lane inlines, and B6 alters the §Versioning trigger set that
governs when this contract must change at all. The narrower minor reading — that §6 is the guard
binding rather than a §4 loop-layer invariant, and that a new trigger is additive guidance — was
considered and not taken. Each entry below records both cases.

- **Single-account-per-machine is reframed from invariant to known gap (§6).** The previous text
  said "operation assumes one account per machine" — descriptive of how the guard happened to be
  built, and fail-**open** where the rest of the contract fail-closes. Same-machine account rotation
  is real operating practice, so the section now names the gap instead of asserting an assumption,
  and defers the account-identity design that resolves it to `TODO(#1218)`, which owns all three
  sides (writer-side identity field, reader-side invalidation of latched state, and the lane-floor
  re-audit a floor change obliges). `rate-limit-guard` 0.2.0 drops its own duplicate copy and cites
  this section. **No lane obligation changes:** naming a gap removes false assurance without adding
  a requirement any lane body would have to inline, which is why the lane-floor fan-out belongs to
  the design issue and not here. **Bump ambiguity:** §6 is the rate-limit guard binding rather than
  a §4 loop-layer invariant, and this revision is now framing-only, which reads as additive guidance
  and a **minor**; but it still revises a stated operating premise every consuming lane inlines,
  which reads as a change to a shared invariant and a **major**.
- **Second re-derivation trigger (§Versioning).** Any change relying on an upstream-sourced claim
  now re-verifies that claim against its cited page first and refreshes its date. Previously only a
  new model release triggered re-derivation, so the upstream-sourced claims — `/loop` expiry,
  `ScheduleWakeup` bounds, alias semantics, rate-limit windows — carried a dated stamp with no
  expiry, which reads as standing authority the longer it sits. **Bump ambiguity:** adding a trigger
  is additive guidance and a **minor**; but the §Versioning trigger set governs when this contract
  must change at all, so altering it changes the contract's own maintenance obligations, which reads
  as a **major**.

## 1.0.0 — 2026-07-23

Initial published contract. Lands before the second adopter, per the convention-registry rule: the
`work-items` `work-loop` / `attend-queue` skills and the `source-control` `babysit-loop` skill share
these concerns across two plugins.

- **Three-session topology** — worker loop authors PRs (never merges), babysit lane owns merges
  within the autonomy matrix's merge-policy column, attended queue holds judgment.
- **Autonomy ladder** — human merge is the shipped default for all but gate-proven C2-mechanical
  PRs (a work-class test, not an authorship one: bot authorship alone never qualifies, and C3/C4/C5/
  unclassified stay human-gated); this default is the recorded baseline rung, and every higher rung
  is opt-in per repo through the matrix's recorded human-ratified config flip.
- **Escalation contract** — `needs-human` role label resolved via `config.role_labels` plus a
  machine-marked discriminator comment; event classes owned by the autonomy guardrails.
- **Capability tiers** — order-defined (frontier / strong / fast), never family names; runtime
  resolution by model alias only, Models API as the build/audit-time path; security-surface work
  routes to frontier always; weekly-cap specifics linked to the official support article, never
  restated.
- **Loop-layer invariants** — stop shapes with a drain-terminal state; `#691` cycle budget restarts
  the session, never the loop; `#502` single edit-in-place telemetry comment with durable loop state;
  headless-config floor; seam exit 8 backoff-as-dirty; snapshot drain exit; subagent discipline
  preamble.
- **Launch surfaces** — `/loop` primary and dependency-free; `claude-ops` `lanes` a one-directional
  supporting launcher (#480), presence-gated with a `/loop` fallback.
- **Rate-limit guard binding** — each lane inlines the operable pause floor and cites the guard
  reader contract for provenance; single-account-per-machine invariant; per-cycle guard-mode
  telemetry.

Live Claude Code surfaces (model aliases, `ScheduleWakeup` bounds, `/loop` self-pacing) verified
against current official documentation on 2026-07-23.
