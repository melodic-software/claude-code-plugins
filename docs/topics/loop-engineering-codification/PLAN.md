# PLAN — loop-engineering-codification

## Brief

### TLDR

Answer the loop-engineering question from this repository's own autonomy
corpus rather than from vendor material, and land the corrections an
eleven-corrector re-anchor sweep surfaced against that corpus and against
the `playbooks` vendored baseline.

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

### Answers derived from the corpus (Phase 2, partial)

Sourced from `plugins/autonomy/reference/trigger-dispatch.md` and
`routines.md`, both read in full. The remaining owner docs are unread; the
substrate/cost answer is therefore still open.

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

### Deferred questions

- Whether contract slices should persist on the default branch at all —
  fourteen do today, against this convention's own prune-before-merge
  lifecycle and its required-check clause. Arbiter: **USER-RESERVED** (a
  lifecycle change is a major contract change).
- Bump classification for the two corpus findings whose owner sections make
  major-vs-minor genuinely ambiguous. Arbiter: **USER-RESERVED**.

## Plan

Not yet written. `/planning:plan` fills this section.
