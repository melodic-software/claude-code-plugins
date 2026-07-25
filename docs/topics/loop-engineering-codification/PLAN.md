# PLAN — loop-engineering-codification

## Brief

### TLDR

Answer the loop-engineering question from this repository's own autonomy
corpus rather than from vendor material, and land the corrections an
eleven-corrector `/discipline:sweep-all` run surfaced against that corpus
and against the `playbooks` vendored baseline.

### Goal

A session investigating "loop engineering" (Anthropic's four loop types,
routines/`/goal`/`/loop` trigger surfaces) researched the topic from
external sources while this repository's owner docs for the same subject
went unopened. The sweep established that the corpus already owns the
subject and that several externally-derived recommendations contradict its
normative invariants.

This topic:

1. Answers the operator's open loop questions from the corpus, with vendor
   material cited rather than restated.
2. Fixes the reachability defect that made a new skill look necessary.
3. Resyncs the vendored `playbooks` baseline, whose missing sections cover
   this exact subject.
4. Records five corpus findings the sweep raised, each as a change to its
   own owner doc.

### Settled prerequisites (do not re-litigate)

- `docs/topics/boris-video-absorption/PLAN.md` — its "Extend existing
  seams, no new skill" lock is scoped to the `testing:run-e2e` /
  `verification:confirm` lane, **not** a repo-wide bar. The repo-wide
  posture is extend-over-add per `docs/PLUGIN-PHILOSOPHY.md`.
- That same Brief already records the verification self-improvement loop as
  deferred-with-trigger (trigger: accumulated recorded runs). Not novel, not
  reopened here.
- `docs/conventions/loop-lane/README.md` is the registry-named owner for
  loop topology, escalation, capability tiers, and loop invariants.
- `plugins/autonomy/reference/trigger-dispatch.md` owns the vendor-neutral
  signal-surface classes; `routines.md` owns the repetition vocabulary and
  hosting stance.

### Constraints

- **Budget $0.** Private-repo Actions minutes already exhausted; public
  repos only. `plugins/autonomy/reference/wiring-vs-advisor.md` governs:
  anything costing money is advisory plus explicit opt-in, with cost
  surfaced before the opt-in question. No surface recommendation ships
  without a cost annotation and a named free default.
- **Pointer-not-copy.** Upstream loop mechanics change on a research-preview
  cadence. Volatile specifics (character limits, schedule floors, run caps,
  trigger inventories, evaluator defaults) are cited live, never restated
  into a durable artifact. Owner docs:
  `standards/conventions/engineering/documentation-and-citations.md` and
  `reference-dont-duplicate.md`.
- **No new skill.** The lever-fit router already exists as
  `planning:draft-goal-condition` Step 0; only its entry point is too narrow.
- **Corpus is not self-justifying.** Two of the five findings hold that a
  corpus invariant is the weaker claim and should yield. Incumbency is not
  an argument.

### Acceptance criteria

- Each open question is answered from a named owner doc or an upstream page
  fetched this session, with unverified claims flagged inline at the claim.
- `planning:draft-goal-condition` is reachable from lever-selection intent;
  every existing trigger phrase preserved (`skill-quality` check 3).
- Vendored `playbooks` baseline matches live upstream; the hub SKILL.md's
  hardcoded section and tip counts and its Topic Index are updated with it.
- Each of the five corpus findings has a written remedy in its own owner
  doc, with a CHANGELOG entry and a bump classification — or an explicitly
  surfaced ambiguity where the tier is genuinely unclear.
- Every touched plugin has a CHANGELOG entry; `skill-quality:check`,
  markdownlint, and lychee pass.

### Captured assumptions

- Sibling-external worktree placement follows the source-control plugin's
  convention; the `worktree_root` config key is unset on this machine, so
  the worktree was created through the documented manual path rather than
  the shared helper. Configuring that key is a follow-up, not part of this
  topic.
- Branch base is the remote default rather than local `HEAD`, diverging
  from the committed `worktree.baseRef: "head"` setting because local
  `main` trailed the remote.

### Out of scope

- The skill-listing budget overflow that made several near-fit skills
  surface as bare names. A separate session owns the display-name and
  metadata audit.
- Building any loop, routine, or trigger. This topic answers and corrects;
  it does not wire.
- Retiring or amending the `boris-video-absorption` slice beyond repointing
  its two citations of the retired `consumer-config-layering` path.

### Answers derived from the corpus (Phase 2)

Sourced from the `plugins/autonomy/reference/` corpus and
`docs/conventions/loop-lane/README.md`, all read in full, with upstream
pages fetched this session cited rather than restated.

- **"Loops that generate prompts" is the wrong frame.** The load-bearing
  split is by lifetime, not by a four-rung progression: session-scoped
  (`loop`, `goal`, `batch`, `dynamic workflow`) versus standing (`schedule`,
  `routine`). The vendor's "time-based" bucket straddles that boundary —
  `/loop` dies with its session, `/schedule` does not — which is the
  conflation `routines.md` is annotated to prevent.
- **Nothing generates prompts at run time.** A routine is a standing schedule
  plus a saved task definition firing a fresh session per run, and
  §Instruction provenance requires the stored prompt be a thin pointer to a
  version-controlled artifact; pasted prose is non-compliant because a
  scheduling surface exposes no prompt history, diff, or rollback.
- **Jira and any other tracker resolve through `tracker-vcs-event`.** The
  conforming shape is an adapter that normalizes and enqueues. A central
  webhook application that prompts headless executors is the second
  signal-to-execution path adapter obligation 1 forbids. Note that a routine
  `/fire` payload is caller-supplied, while `signal.producer_identity` must
  resolve from the platform's authenticated run context — so fired
  provenance can never come from the payload.
- **Post-merge triggering is not justified for PR queue work.**
  `pr-queue-tending` is a `v1` class whose trigger slot is `schedule`, daily.
  Event-riding wakes the routine's own ratified surface and the run stays
  `temporal` with identity and classification invariant, so an event trigger
  adds no observation the daily sweep lacks. The earlier
  `pull_request.closed` recommendation is withdrawn rather than narrowed.
- **Vendor-hosted executors cap at human-gated merge policy**
  (§Hosting stance). Cloud routines are vendor-hosted, so they can never
  auto-merge regardless of configuration. This is a structural ceiling on any
  design that puts merge authority behind a hosted routine.

#### Substrate and cost posture under $0

**$0 excludes one knob, not a substrate.** Cloud routines are entitlement-
included on Pro, Max, Team, and Enterprise with Claude Code on the web
enabled, and their runs draw down subscription usage the same way an
interactive session does — no separate billing
(<https://code.claude.com/docs/en/routines#usage-and-limits>, verified
2026-07-24). The single paid path is **usage credits**: metered overage once
a run hits the per-account daily routine cap or the subscription usage limit.
Under $0 that toggle stays off, which is `wiring-vs-advisor.md`'s ADVISE
branch by construction, and the declined opt-in falls back to a defined
behavior rather than silence — further runs are rejected until the window
resets.

**The scarce resource is the shared subscription window, not money.** Cloud
routine runs, Desktop scheduled tasks, `/loop` iterations, and interactive
work all draw the same rolling five-hour and weekly budget
(`loop-lane/README.md` §3). The $0 constraint therefore reappears as
contention with the operator's own interactive sessions and with the lanes'
rate-limit guard. This is the axis finding B5 turned on, and B5 has since
landed on this branch: `routines.md` now fixes the property — *no agent
session, zero agent tokens* — where it previously prescribed plain cron, so
the catalog's `not-a-routine` rows and the detection portion of every hybrid
row satisfy it on any substrate.

**Named free default, already fixed by the corpus.** `runner/topology.md`
§Launch backend set requires one free self-run `L2` backend — a
container-class substrate with default-deny egress at no standing cost — and
makes every paid or cloud backend advisory plus explicit opt-in. $0 changes
nothing about it.

**What each substrate buys and what it caps** — the Cloud / Desktop / `/loop`
comparison is upstream at
<https://code.claude.com/docs/en/scheduled-tasks#compare-scheduling-options>
(verified 2026-07-24); the contract consequences are:

- A cloud routine is a **vendor-hosted executor**, so every class caps at
  human-gated merge (`routines.md` §Hosting stance,
  `runner/topology.md`). Upstream behavior is consistent: routine pushes are
  restricted to `claude/`-prefixed branches unless unrestricted branch pushes
  are enabled.
- A cloud run has **no local files** — each run clones the selected
  repositories from their default branch — so the instruction artifact must be
  committed to a selected repository. That is exactly the first illustrative
  binding under `routines.md` §Instruction provenance, and it is a
  requirement rather than a preference on this substrate.
- A **Desktop scheduled task** is self-operated with local file access and a
  one-minute floor, so merge policy stays ownable: the `C2` auto-merge
  promotion is reachable only on a self-run backend.
- **`/loop` can never host a standing class** — it is session-scoped and
  expires seven days after creation (`loop-lane/README.md` §4 already binds
  this).

**Multi-account fan-out is blocked by an existing invariant.** Routines belong
to an individual claude.ai account and count against that account's daily run
allowance, so spreading standing work across the operator's several
subscriptions is the obvious way to buy headroom at $0. `loop-lane/README.md`
§6 previously assumed one account per machine and simply trusted whichever
account last wrote the rate-limit tee file — the fail-open posture finding B4
challenged, and this the sharpest practical case against it. §6 now records
that as a known **gap** rather than a safe assumption, which removes the false
assurance without changing any lane's obligations. Detection is not built: the
tee still carries no account identifier, and the design that would add one —
writer-side field, reader-side latch invalidation, lane-floor re-audit — is
`TODO(#1218)`. Until it lands, multi-account fan-out remains undetectable, so
this lever stays unavailable rather than merely unwise.

**Unverified — flagged at the claim.** Whether the cloud environment satisfies
the ladder's `L3` bar is NOT established. Its shape matches the "hosted
ephemeral executor surface" the isolation ladder names as an `L3` substrate
class, but the upstream documentation describes network allowlisting and
per-run ephemerality, never kernel separation. Treat the level as a
security-binding verdict, not a doc-derived fact.

#### Do the existing verification skills feed the governed queue?

**No, and the gap is a missing join rather than a missing output format.**

- **What they emit today.** `/toolchain:check` reports build results as prose.
  `/verification:confirm` emits an outcome report and a `CONFIRMED` /
  `NEEDS WORK` verdict, plus — only when `/testing:run-e2e` ran — an
  assertion-only manifest keyed by topic slug and `verified_at_sha`.
  `/verification:measure` emits comparison tables over baselines that are
  machine-bound and never committed.
- **What the queue's promotion apparatus requires.**
  `guardrails/work-classes.md` §Promotion and demotion fixes one shape: an
  evidence predicate over queryable telemetry, whose evidence base is
  verification outcomes recorded per `telemetry.md` — an emission carrying
  `autonomy.work_item.url`, joined query-side.
- **The blocking mismatch.** None of the three skills knows a work item
  exists; `plugins/verification/` carries no tracker or work-item reference at
  all. `telemetry.md` Pillar 2 fixes the join key as the WORK ITEM's URL,
  never a change URL, so nothing these skills persist yields a join.
- **Emitting a signal from skill-side would not conform either.** Skill output
  is repo-local, agent-writable content, and
  `trigger-dispatch.md` §Work-class classification refuses that surface as a
  source of `signal.work_class` — such an emission stays unclassified and
  fail-closes to human-gated.
- **The conforming route is not skill-side.** `telemetry.md` §Native-surface
  principle requires wrapping native emission rather than re-deriving it, and
  the emission templates and conformance scripts already ship under
  `plugins/autonomy/skills/setup/`. The association these skills lack comes
  from the lease, which Pillar 2 names as the granularity guarantor and which
  exists only on the autonomous path; `runner/seams.md`
  §Outcome-verification gate is where a verification result acquires its work
  item.
- **This is by design, not an oversight.** `return-accounting.md` §Capture
  scope exempts interactive work explicitly. These are interactive-lane
  skills, and asking them to feed the queue asks them to cross that boundary.

Conclusion: this topic warrants no change to the verification skills. The
promotion evidence base is blocked on an executor behind the
invocation-adapter seam, not on an output format — the same
deferred-with-trigger shape `boris-video-absorption` already records.

### Deferred questions

- Whether contract slices should persist on the default branch at all —
  fifteen do today, against this convention's own prune-before-merge
  lifecycle and its required-check clause. Arbiter: **USER-RESERVED** (a
  lifecycle change is a major contract change). **Still open.**
- ~~Bump classification for the two corpus findings.~~ **Resolved before the
  PR opened:** `autonomy` **minor** (`0.10.0` — under its `0.x` scheme the
  breaking/vocabulary slot) and the `loop-lane` convention **major**
  (`2.0.0`). Each CHANGELOG heading records the narrower reading that was
  considered and not taken.

### Follow-ups this topic surfaced but did not take

Recorded here because the memory tier is gitignored and does not survive the
checkout; each is unclaimed work with a named owner surface.

- **`docs/topics/github-plugin-candidates/` still cites the retired
  `consumer-config-layering` path** (~6 sites). This topic's scope named only
  `boris-video-absorption`. Changelog mentions of the old name are historical
  and stay.
- **The `worktree_root` config key is unset on this machine**, so
  `worktree-create.sh` exits 3 and the documented manual worktree path is the
  only one that works. The key lands in chezmoi-managed `settings.json`, so it
  needs the dotfiles repo's `add-dotfile` / backfill flow rather than a live
  edit.
- **The skill-listing budget overflow** — declared out of scope at the top of
  this Brief, and owned by `TODO(#1271)`, which measures it rather than
  estimating it. It is a live condition and it constrains every future
  description widening, including this topic's.
- **Two pre-existing `skill-quality:check` warnings on the `playbooks` boris
  hub** — unquoted `Use when:` triggers and no Gotchas surface. Left
  deliberately, and `#1271` confirms the call: boris is one of only two skills
  in the tree that populate `when_to_use` at all, so it is that issue's good
  example rather than an offender. Quoting `'skills'` / `'hooks'` /
  `'workflows'` would lock generic phrases into check 3's drop-protection
  permanently.

### Adjacent work this must not collide with

- **`TODO(#1218)`** owns the account-identity design that loop-lane §6 defers
  to. §6 here is framing-only for exactly that reason.
- **`TODO(#1219)`** instantiates routine catalog `v1` classes and should adopt
  the determinism vocabulary this topic corrected — the invariant is *no agent
  session, zero agent tokens*, and the substrate is a deployment binding.
- **`TODO(#1220)`** adds a blocked-lever protocol to this same convention and
  will land on top of its version bump.

### Interview branches never closed

The interview reached neither its stop condition nor its hand-off step, so
these stay open rather than being silently dropped:

- **The Jira / day-job path.** The adapter shape is answered above —
  `tracker-vcs-event`, an adapter that normalizes and enqueues, and a
  `producer_identity` that can never come from the caller-supplied `/fire`
  payload. The operator-facing question, whether the day-job tracker is in
  scope at all, was never asked.
- **Turn 1's three-part question, re-answered without the handoff-ladder
  framing.** The ladder was dropped as a framing (it collapses four
  orthogonal questions into one progression); the original question was never
  re-answered on the replacement axis.

## Plan

No forecast plan was written — the work was sequenced directly from the
Brief's acceptance criteria, and this section is the record of what executed.

1. **Phase 1 — corpus read.** Every `plugins/autonomy/reference/` hub, all
   four `guardrails/` leaves, all four `runner/` leaves, all ten `routines/`
   v1 leaves, and `docs/conventions/loop-lane/README.md`.
2. **Phase 2 — answers.** Substrate/cost and the verification-skill
   assessment, recorded above with upstream cited rather than restated.
3. **Phase 3 — reachability.** `planning:draft-goal-condition` (0.26.0).
4. **Phase 4 — vendored baseline.** `playbooks` boris pack 8.8.1 → 8.13.0
   (0.5.0); upstream had moved past the 8.12.0 recorded at hand-off, so the
   delta figures were re-derived. The bump was renumbered from `0.4.0` when
   #1261 merged first and claimed that number; the minor tier is unchanged.
5. **Phase 5 — the five findings.** `autonomy` 0.10.0, `loop-lane` 2.0.0, and
   `rate-limit-guard` 0.2.0 (added under review — it carried its own copy of
   the assumption `loop-lane` §6 retired).
6. **Phase 6 — PR.** Opened as one PR after the review-surface concern was
   re-raised and both bump tiers were ratified.
