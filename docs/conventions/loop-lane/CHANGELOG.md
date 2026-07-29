# Loop-lane convention — changelog

Notable changes to the loop-lane contract. The contract is versioned by SemVer; a change to the
topology, the escalation contract, the capability-tier vocabulary, or any loop-layer invariant is a
major bump, and additive guidance is a minor bump. A new model release re-audits the capability-tier
table (§3); drift found by that audit is recorded here.

## 6.0.0 — 2026-07-29

Adds the per-cycle usage sample to §4's loop-layer invariants, requested and scoped in
[melodic-software/claude-code-plugins#1651](https://github.com/melodic-software/claude-code-plugins/issues/1651).
Tier ratified as **major** on 2.0.0's discriminator: a new §4 loop-layer invariant is a new
obligation every loop-lane body must implement. That the recorded value drives no behavior does not
soften the tier — the *write* is the obligation. **Bump ambiguity:** a field no decision reads changes
no lane's behavior, and a purely additive telemetry key reads as additive guidance and a **minor**; but
§4 states loop-layer invariants, and this adds one every loop-lane body must carry, which reads as a
**major**. The attended `attend-queue` lane is unaffected: §4 binds loop lanes, and that lane holds
no durable-state block.

- **Per-cycle usage sample (§4).** A lane's spend was a blind spot: the cycle budget counts cycles,
  the rate-limit guard's pause is a ceiling, and nothing recorded how much of the shared
  subscription windows a cycle consumed. Each loop lane now records a `usage_sample` in its #502
  durable state every cycle, holding the two window percentages the guard step (§6) **already read**
  that cycle plus the rise since the previous sample — the reading is in hand, so the invariant costs
  a write, not an observation. Whether the data supports acting on it is a later, separately decided
  question.
- **Measure-only, with exactly one permitted readback (§4).** Deriving the delta needs the previous
  cycle's percentage, and after context compaction the telemetry block is the only durable place it
  survives — so the invariant permits reading the previous sample back for exactly one operation:
  subtracting its `five_hour_pct` to compute the new sample's `five_hour_delta_pct`. That derivation
  is the field's only permitted consumer. No other read is permitted, and the value never reaches a
  decision — not pacing, backoff, an adaptive or item cap, a merge rung, admission, escalation, a
  warning, or a pause — at any threshold, in a lane or in any gate a lane runs.
- **The delta measures the preceding interval (§4).** The guard reading a lane copies is taken at
  cycle start, before that cycle's own work, so `at` is the cycle-start observation time and the
  delta is the rise between the previous cycle's reading and this one: it covers the interval
  *preceding* the cycle whose report carries it, and that cycle's own consumption lands in the next
  cycle's sample. The alternative — a post-execution reading — was rejected because it would be a
  second observation of the guard's tee that no lane's cycle shape performs, contradicting the
  invariant's own justification that the reading is already in hand.
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

## 3.1.1 — 2026-07-29

Docs-only, no topology, escalation, tier, or invariant change: §Versioning's "Re-derivation
triggers" label becomes "Recheck triggers" and cites the
[upstream-drift convention](../upstream-drift/README.md) (#1638), the new owner of the
stamp-and-trigger discipline; the generic date-is-never-authority rationale moves there. Both
triggers stay unchanged; the recording policy aligns with the owner doc — a firing that finds
drift lands here, a no-drift firing refreshes the claim's verification date only.

## 5.0.0 — 2026-07-29

Adds the per-lane consecutive-no-progress detector to §4's loop-layer invariants, requested and
scoped in
[melodic-software/claude-code-plugins#1648](https://github.com/melodic-software/claude-code-plugins/issues/1648).
Tier ratified as **major**: a new loop-layer invariant is a new obligation every unattended lane
body must implement, which is the discriminator 2.0.0 used. The minor reading — that a new
invariant is additive guidance because no existing invariant changes — was considered and not
taken.

- **No-progress detector (§4).** Every stall mechanism below the loop layer is per-PR or per-item,
  so a lane cycling with zero aggregate progress was invisible to itself. Each unattended lane now
  persists a `no_progress_streak` counter in its #502 durable state (absent = 0): a cycle with
  actionable work in the cycle-start snapshot and no lane-defined qualifying progress increments
  it, an idle cycle — or one held, meaning the rate-limit guard (§6) barred the lane from claiming
  new work, which each lane's floor defines and which can outlive the pause window — leaves it
  unchanged, and any qualifying progress resets it. Reaching the stall
  threshold (default 3; lane-configurable) **escalates through §2's existing contract and keeps
  looping** — never a lane stop, no second channel, no new guardrail event class. At most one stall
  escalation per lane stays open at a time (author-matched dedup), and neither the stall escalation
  itself nor a lane's own repeat attempt at the same still-unresolved blocker ever counts as
  qualifying progress. The attended queue is exempt — its operator is present by definition.
- **Durable loop state (§4)** now lists the consecutive-no-progress counter among the persisted
  counters.

## 4.0.0 — 2026-07-27

Out-of-band escalation notification
([melodic-software/claude-code-plugins#1650](https://github.com/melodic-software/claude-code-plugins/issues/1650)).
A change to the escalation contract is a major bump per this file's own rule.

- **Escalation contract (§2) — escalation record write.** Every escalation an autonomous lane
  files now also writes a local JSON escalation record at
  `.claude/lane-escalations/<UTC-stamp>-<item>-<lane>.json`, created with the Write tool (never a
  shell redirect, whose `Bash` event the seam's `Write` matcher never sees), one new file per
  NEWLY filed escalation — suppression is the marker read a lane already performs before
  escalating, so a standing escalation re-encountered on a later cycle fires no second webhook. The
  record is written **immediately before** the marker comment, and the order is part of the
  contract: the two writes are not atomic, and this order fails toward a duplicate notification the
  next cycle re-files, where the reverse fails toward a standing marker that suppresses the record
  forever and loses the notification silently. The record is signal, not storage: the tracker item
  stays the single escalation of record. Keeping the record directory out of the working tree is a
  **lane-start preflight**, not a consumer obligation — a lane that finds the path unignored
  appends it to the clone's untracked `$(git rev-parse --git-common-dir)/info/exclude`, which
  repairs an existing consumer that upgraded without adding a tracked rule and alters nothing the
  repo tracks. A tracked `.gitignore` rule added through a repo's lane-enabling adoption change
  stays the durable form, and the preflight then no-ops.
- **Escalation contract (§2) — out-of-band notification seam.** A consuming repo's own tracked
  `.claude/settings.json` may register a deterministic `PostToolUse` `type: "http"` hook on the
  record write, POSTing the hook JSON to a repo-chosen endpoint — documented default shape,
  per-element grounding, and official-doc citations all in §2, verified 2026-07-27. The
  deterministic path carries no claude.ai subscription or Remote Control dependency.
  `PushNotification` and `slack`-plugin outbound are
  named as optional model-discretionary layers, never the deterministic leg. Fan-out depth on the
  one filed escalation — not a second escalation channel; degradation without a configured hook
  loses only the out-of-band leg. §2 also records the seam's egress (the POST body is the full
  hook input, session metadata included — consumer-opted by configuring the hook) and its
  silent-failure mode (empty-string env interpolation plus non-blocking non-2xx), with a
  wire-time verification step.

## 3.1.0 — 2026-07-27

Three convention notes recording distinctions and a boundary the contract already operated under,
plus one newly named gap. Tier is **minor**: no topology, escalation contract, or tier vocabulary
changes, and no consuming lane acquires an obligation. The §4 and §5 additions are descriptive —
they state what the loop layer already does, and add no invariant a lane must newly hold. **Bump
ambiguity:** §4 is headed "Every loop lane holds these" and this revision both adds a bolded
paragraph there and widens a stated bound, which reads as a change to a shared invariant and a
**major**; but correcting the *description* of a bound that already applied imposes nothing a lane
must newly hold, which reads as additive guidance and a **minor**.

- **Prompt-fresh versus session-persistent (§4).** A cycle re-sends the lane's prompt verbatim into
  the *same* session; "runs fresh every time" describes the prompt, never the context. Stated in one
  sentence anchored at `claude-ops` `lanes`, which owns the mechanism. Records that the carried-over
  context also *degrades* — auto-compaction summarizes earlier history in place — so the note does
  not read as a promise that every turn survives. Prevents the conflation for any reader arriving
  from phrasing that describes only the prompt
  ([#1655](https://github.com/melodic-software/claude-code-plugins/issues/1655)).
- **Fixed-interval and self-paced launch shapes reconciled (§5).** A supplied interval becomes a
  cron schedule (jittered); an omitted one hands the delay to Claude, and `ScheduleWakeup` paces
  only the latter. A lane always omits the interval, because two §4 properties need the self-paced
  shape: idle backoff derives the next delay from what the cycle just observed, and a self-paced loop
  can end itself, which is how the drain shape's terminal state stops a lane cleanly. A fixed
  interval is the operator's shape for invoking a single-pass mechanic directly, where the interval
  chosen once is the whole cadence policy. Records which applies where; **neither mechanism
  changes**, and the adaptive cadence is not replaced
  ([#1656](https://github.com/melodic-software/claude-code-plugins/issues/1656)).
- **Self-pacing is a named provider-conditional gap (§5).** On Bedrock, Claude Platform on AWS,
  Google Cloud's Agent Platform, and Microsoft Foundry, an omitted interval runs on a fixed
  ten-minute schedule and `ScheduleWakeup` is unavailable, so a lane launched there loses both
  properties the self-paced shape supplies — idle backoff cannot lengthen the wake, and the lane
  cannot end itself, which strands a **drain** lane on the deadlock §4's terminal state exists to
  prevent — undetected. Recorded as a gap rather than left as the unstated assumption the §5 note
  would otherwise carry — the treatment §6 already gives the single-account assumption.
- **The fresh-context review boundary is now an explicit decision (§3).** The requirement fires on
  the merge-authority exception's dispatch and deliberately not per cycle over ordinary loop output:
  independence substitutes for a *human decision*, and the ordinary path takes none — its
  correctness rests on deterministic gates that are unbiased by construction. States that a lane's
  conflict path is not a second instance, since the fresh conflict *worker* it dispatches holds a
  resolution role rather than ratifying a decision a human would otherwise make. Recorded with the
  condition that revisits it, so the absence reads as a chosen boundary rather than a gap discovered
  later ([#1658](https://github.com/melodic-software/claude-code-plugins/issues/1658)).

Per §Versioning's upstream-claim trigger, the `/loop` pacing claims this revision relies on were
re-verified against <https://code.claude.com/docs/en/scheduled-tasks> and
<https://code.claude.com/docs/en/tools-reference> on 2026-07-27 before writing, and the §4 and §5
dates are refreshed with the outcome. **No upstream drift:** every value the 2026-07-23 stamp
covered still holds — the `ScheduleWakeup` bounds, its end-of-iteration call site, its
non-operator-callability, and the seven-day expiry itself. The re-verification did change what this
document says, in two ways:

- **Two facts the prior stamp never recorded**, both now stated in §5: cron jitter, and the provider
  carve-out that turns an omitted interval into a fixed ten-minute schedule.
- **One claim the prior stamp scoped too narrowly**, now corrected in §4: the seven-day expiry was
  written as a property of the self-paced shape, where the source binds **both** launch shapes — a
  fixed-interval loop runs until stopped by hand or until the same seven days elapse. The bound
  never changed; only this document's statement of it was narrower than the source.

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
