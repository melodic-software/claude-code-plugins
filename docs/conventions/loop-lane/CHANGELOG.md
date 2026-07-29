# Loop-lane convention — changelog

Notable changes to the loop-lane contract. The contract is versioned by SemVer; a change to the
topology, the escalation contract, the capability-tier vocabulary, or any loop-layer invariant is a
major bump, and additive guidance is a minor bump. A new model release re-audits the capability-tier
table (§3) and is recorded here.

## 4.0.0 — 2026-07-28

Adds the per-cycle usage sample to §4's loop-layer invariants, requested and scoped in
[melodic-software/claude-code-plugins#1651](https://github.com/melodic-software/claude-code-plugins/issues/1651).
Tier ratified as **major** on 2.0.0's discriminator: a new §4 loop-layer invariant is a new
obligation every loop-lane body must implement. That the recorded value is inert does not soften the
tier — the *write* is the obligation. **Bump ambiguity:** a field nothing reads back changes no
lane's behavior, and a purely additive telemetry key reads as additive guidance and a **minor**; but
§4 states loop-layer invariants, and this adds one every loop-lane body must carry, which reads as a
**major**. The attended `attend-queue` lane is unaffected: §4 binds loop lanes, and that lane holds
no durable-state block.

- **Per-cycle usage sample (§4).** A lane's spend was a blind spot: the cycle budget counts cycles,
  the rate-limit guard's pause is a ceiling, and nothing recorded how much of the shared
  subscription windows a cycle consumed. Each loop lane now records a `usage_sample` in its #502
  durable state every cycle, holding the two window percentages the guard step (§6) **already read**
  that cycle plus the rise since the previous sample — the reading is in hand, so the invariant costs
  a write, not an observation. The field is deliberately **inert**: no lane reads it back and no
  pacing, backoff, adaptive cap, merge rung, or pause derives from it. Whether the data supports
  acting on it is a later, separately decided question.
- **Recorded caveats bound what the data can support.** The reading is a snapshot no fresher than
  the guard's staleness rule allows, from a machine-local, last-writer-wins tee that refreshes only
  while an interactive session renders a status line — so an unattended lane samples nothing, and an
  empty sample means unobserved rather than zero. The figures are **account-scope**, so the
  three-lane topology means concurrent lanes move the same windows and a per-cycle rise is one
  lane's own consumption only when that lane is the sole active session; and they are a percentage
  of a subscription window, not a token count, absent entirely for non-subscription auth. No lane
  claims a token count, because none is readable at a cycle boundary: the machine-readable token
  fields are current-context occupancy, not session totals. A machine-readable cumulative *cost*
  field does exist and is session-scoped, so it would attribute to a lane — but the guard's tee does
  not forward it, and widening the tee is a guard-side change this invariant deliberately does not
  make.
- **Upstream re-verification (§Versioning trigger 2).** This entry relies on the status-line stdin
  schema, so that claim was re-verified against its cited page and its stamp refreshed to
  **2026-07-28** (<https://code.claude.com/docs/en/statusline>). Confirmed unchanged:
  `rate_limits.{five_hour,seven_day}.used_percentage` is 0–100 and `resets_at` is Unix epoch
  seconds; `rate_limits` is present only for Claude.ai subscribers after the session's first API
  response, and each window may be independently absent. Confirmed still true, and the reason no
  token count is claimed: `context_window.total_input_tokens` / `total_output_tokens` are "token
  counts currently in the context window, from the most recent API response" — cumulative session
  totals only before Claude Code v2.1.132. Also recorded, because it bounds a future phase rather
  than this one: `cost.total_cost_usd` is documented as the estimated session cost accumulated
  client-side, resetting on `/clear` — machine-readable and session-scoped, and therefore the
  deferred candidate for per-lane attribution once a guard-side change forwards it. No drift found.
  `rate-limit-guard`'s reader contract carries its own 2026-07-23 stamp on the same page; it is
  unchanged by this entry and its refresh belongs to that plugin's own bump.

## 3.0.0 — 2026-07-25

Repo-owner-ratified addition of a single named, explicit-argument exception to the seam-only merge
rung, requested and scoped in
[melodic-software/claude-code-plugins#1309](https://github.com/melodic-software/claude-code-plugins/issues/1309).
A change to the autonomy-ladder invariant is a major bump per this file's own rule.

- **Autonomy ladder** — an invocation whose own argument line explicitly types both the literal
  `autopilot` tier keyword and the dedicated raise argument `--merge c3-this-run` (each never
  inherited, never defaulted, never seam-supplied, never model-composed on the caller's behalf)
  widens that single invocation's merge authority up
  to and including C3, in a repository that has already adopted the baseline rung. The raise token
  exists for this exception alone — `autopilot` predates it as a merge-inert tier keyword, so a
  saved invocation or expanded template carrying the tier keyword alone acquires no merge
  authority. Persists nothing
  to config; is not a substitute for the recorded C3-autonomous seam flip. **C4 (structural) and C5
  (untrusted-provenance) stay unconditionally human-gated** — no rung, seam, or argument, including
  this one, ever reaches them, per the autonomy matrix's own "never promotes" cells. The exception
  lifts only the *raise* restriction: every other merge-dimension value still only selects a lower
  rung, and
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
