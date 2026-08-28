# Cycle shape

What one cycle of `/source-control:babysit-loop` is: the per-cycle step order, what each step may
mutate at the resolved autonomy tier, and where the escalation and no-progress checks attach. The
stop modes in [`../SKILL.md`](../SKILL.md) decide whether a cycle runs; this file decides what one
is.

0. **Lane-start preflight (once per lane, before the first cycle).** Keep step 5's unconditional
   record write out of the tracked tree, per §2: if `git check-ignore -q .claude/lane-escalations/`
   reports the path unignored, append `/.claude/lane-escalations/` to the clone's untracked
   `$(git rev-parse --git-common-dir)/info/exclude`. Skipped outside a git checkout, which the
   neutral-directory launch mode allows.
1. **Re-anchor.** Re-read the durable loop state block from the telemetry comment (conversation
   context is compaction-lossy, the comment is the source of truth for the counters); classify
   guard mode against the rate-limit guard floor in [`../SKILL.md`](../SKILL.md); take the cycle-start snapshot: open PRs with head SHAs,
   last-activity timestamps, and the provenance fields the rung partition consumes
   (`isCrossRepository`, `headRepositoryOwner`, `authorAssociation`, plus the author login and bot type the trust test's listed-bot arm reads), and, in drain mode, open issues with the same author-association / login / bot-type fields the issue-author test consumes.
2. **Grace-window overlay.** From the snapshot, mark every PR whose head moved or that received
   comments within the grace window (default 30 minutes), and every draft carrying a WIP signal (a
   work-in-progress title marker, a do-not-merge label, or non-green checks). Marked PRs are
   report-only this cycle: never elevated, never thread-resolved, never merged.
3. **Rung partition (deterministic, fail closed).** When the resolved tier is merge-capable,
   compute the merge-eligible set mechanically before any babysit-prs invocation: for each open
   PR in the snapshot not already excluded by step 2, resolve its close-linked work item (the
   provider's own computed close-linkage, `gh api graphql`, `closingIssuesReferences`) and read
   that item's recorded work-class classification **from its `work-class:` label only**, never
   from a `Work-class: C<n>` body trailer. The class widens merge authority, so it is read only
   from a surface whose write authority the provider enforces: labelling takes triage or write
   permission on the base repository, the same permission surface the C5 trust test below keys on,
   while a body is editable by its own author, who need hold none. A trailer supplying the class
   would make the item self-certifying, against the governing rule that "no repo-local
   (agent-writable) surface may supply any admission input. Rules, caps, or the work class used
   for admission"
   ([`admission-policy.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/autonomy/reference/guardrails/admission-policy.md)).
   A trailer stays legitimate as recorded operator context and as a proposal, and is reported as
   such, but it never partitions: an item classified only in its body counts as **unclassified
   here**, not eligible at any rung, exactly as an item with no record at all.
   A PR is merge-eligible when its item's class sits within the effective rung **and** its promotable
   cell is **effective-promoted** (**Promotion-evidence gate (trusted seam, fail-closed)**.
   [reference/promotion-evidence-resolution.md](promotion-evidence-resolution.md)): C2 at
   `c2-mechanical`, C2+C3 at `c3-autonomous`, through C3 at `full-autonomy` (never C4/C5). Before
   work-class comparison resolve each cell through the trusted seam; unqualified evidence fail-closes
   to effective-unpromoted, operators keep `--merge human-only` on launch lines (#1695); report each
   bound→effective pair at cycle start. Effective rung: tracked rung, C3 raise when `autopilot` + `--merge c3-this-run` typed (other `--merge` floors), C4/C5 floor, see "Explicit-`autopilot` widening" above. A PR with no
   close-linked item, or an item with no recorded classification, is NOT eligible, no
   classification = no merge, at any rung, including the explicit-`autopilot` widening. A PR still
   carrying the do-not-merge label at partition time is NOT eligible at any rung or class, the
   label veto binds here, in the partition, because a merge-capable babysit-prs tier's ordinary
   gate has no label input (its `--block-labels` criterion is confined to the autopilot merge
   tier); such a PR routes to the `safe` per-PR pass like any other non-eligible PR. The one
   ordered exception: when THIS invocation carries `--strip-do-not-merge`, the strip executes
   between the snapshot and this partition, the label is removed from the flag's target PRs and
   recorded in the cycle report, so a stripped PR partitions on its work-class like any other; the
   flag is a per-invocation direct order and never persists (see do-not-merge below). This is a
   deterministic pre-partition, never narrative guidance handed to the invoked skill. Two further
   withholdings bind here, both because the downstream merge gate inspects neither surface: a PR
   whose close-linked item wears the human-gated role label WITHOUT the machine escalation marker
   is operator-*parked* (Escalation below), NOT eligible at any rung, routed to the `safe` pass;
   and a PR carrying human blocking feedback, a human `CHANGES_REQUESTED` review, explicit human
   blocking language, or an unresolved inline human thread, is NOT eligible either, because a
   merge-capable tier's own runbook widens thread scope to human threads, which under this lane
   stays stop-and-ask: `safe` pass plus escalation. At
   `human-only` (including the no-tracked-adoption default), or under a non-merge-capable tier,
   the eligible set is empty, the widening does not apply without tracked adoption either
   (config-resolution.md, "Baseline activation is tracked adoption").
   **C4/C5 floor:** a PR that is C4 (structural) or C5 (untrusted-provenance) is NEVER in the
   eligible set, at any rung, under any invocation argument. Checked before, and independent of,
   the rung comparison above. **Both are tests on the PR, not lookups of the linked item's stamp**:
   `work-classes.md` assigns a class from the risk-property bundle. Blast radius, reversibility,
   provenance, and "the bundle, not the task's surface description, is what assigns a class".
   - **C5, the code's provenance.** Two tests on the cycle-start snapshot, either one marking the
     PR C5, each failing closed to C5 when its field is missing or unreadable. **Fork test:** the
     head repository is not the base (`isCrossRepository: true`, or `headRepositoryOwner` differing
     from the base owner). **Trust test:** C5 unless one arm positively passes, `authorAssociation` `OWNER`/`MEMBER`, or a structural bot (`[bot]` login suffix or provider `Bot` type) listed in the TARGET repository's team-tracked, default-branch `babysit_loop_trusted_internal_bot_logins` (grammar, binding, fail-closed empty set: config-resolution reference, "the C5 trust test's one reviewed widening").
     A listing never bypasses the fork test (a listed bot on a cross-repository head is still C5) and never weakens the dependency hold-merge invariant, which wins on intersection. Never test the author login against `babysit_watched_owners`: a repository-owner allowlist, never a trusted-author list. A fork PR closing an internally classified C2/C3 issue is still C5, the class travels with the code's provenance, not the issue it closes.
   - **C4, the diff's blast radius.** The stamp admits; the diff can still veto. A PR whose actual
     change is a refactor, migration, or contract change is C4 however its item is stamped, and a
     PR whose shape no longer matches its recorded class **fails closed** to escalation rather than
     to the stamp.
   - **The verdict authorizes a head SHA, not the PR.** This partition class-checked the snapshot
     head's diff, so eligibility is pinned to that SHA: the merge-capable invocation carries the
     partitioned head as its merge gate's `--expected-head` pin, and the gate's head-match refusal
     makes the binding deterministic rather than narrative. Any worker push, an ordinary CI or
     review-finding fix, not only the pre-escalation resolver's, moves the head off the pin; the
     pinned gate refuses the merge, and the invocation ends by reporting the new head instead of
     re-pinning (babysit-prs Autopilot step 3's lane-pin exception, `babysit-prs/reference/safety.md`). The
     lane then re-partitions the post-push head, provenance, C4-diff, rung, and only a
     still-eligible PR gets a fresh merge-capable invocation pinned to the new head.
4. **Invoke the mechanic.** Every invocation uses babysit-prs's own `[mode] [scope]` grammar in
   its single-PR scope form (`owner/repo#N`), the lane's own step-2 snapshot is the discovery
   surface, so no repo-wide invocation ever runs and a PR the lane withheld is never presented
   to the mechanic at all. Three enforcement rules bind each per-PR invocation:
   - **Report-only PRs get zero invocations.** A PR marked report-only in step 2 (grace window,
     WIP-signal draft) appears in the cycle report and nowhere else, no tier, not even `safe`,
     is invoked against it, because `safe` still makes and pushes clear branch-owned fixes.
   - **Rung binds the tier.** Merge-eligible PRs (step 3) are invoked at the resolved
     merge-capable tier, one `/source-control:babysit-prs <tier> <owner/repo>#<N>` per PR, the
     invocation brief carrying the partitioned head SHA as the merge gate's required
     `--expected-head` (the lane pin; `babysit-prs/reference/safety.md`, "Lane-pinned merge
     authorization"); every other non-report-only PR is invoked at `safe` (fixes and reports;
     never resolves threads or merges). An empty eligible set means only `safe` per-PR invocations this cycle.
     Under the explicit-`autopilot` widening, a merge-eligible PR blocked on a machine-escalated
     `needs-human` item, an open finding, or a contradictory thread gets the leased fresh-subagent
     resolution dispatch ("Explicit-`autopilot` widening" above, Escalation below) ahead of its `autopilot` per-PR invocation, not instead of it, and only where the next bullet permits it.
   - **Dimension overrides bind by tier flooring, never narrative, and bind every capability this
     step exercises, not only the tier keyword it passes on.** Before invoking, lower the tier for
     a PR to the highest babysit-prs tier whose behavior exceeds NO resolved dimension override
     (babysit-prs's tier keyword is its only enforcement surface, a natural-language narrowing
     handed to a higher tier is not enforcement). **The pre-escalation resolution dispatch is inside
     that boundary**, the lane fires it directly rather than through that keyword, and it resolves
     threads, so a thread-resolution override withholds it outright
     ([reference/pre-escalation-dispatch.md](pre-escalation-dispatch.md)). Capabilities the floor forgoes are reported as
     override-constrained; the deliberate cost, here and in the rung partition, is that coupled
     higher-tier actions (e.g. worker-tier bot-thread auto-resolution) are foregone on floored PRs,
     failing closed gives up only actions the overrides or rung already denied. The same limit cuts
     the other way: an UPWARD override on a single dimension is unenforceable when honoring it would
     exceed another. Ignored and reported as override-unenforceable, never smuggled in as narrative
     to a higher tier. Raising one dimension means raising the preset (every dimension consents),
     until the invoked mechanic exposes per-dimension enforcement (follow-up candidate).
   All per-PR mechanics, checkout, fixes, threads, gates, fan-out, run under that skill's own
   contract, and the do-not-merge stance rides every invocation.
5. **Escalate.** Anything needing an operator decision follows the convention's escalation
   contract (below); a blocked action is escalated, never routed around.
6. **Report and pace.** Update the no-progress streak, and, at the threshold, raise the stall
   escalation, per the detector below; upsert the telemetry comment (cycle report + updated state
   block + guard mode + the `usage_sample` built from step 1's cycle-start reading, whose delta
   covers the preceding interval and never this cycle's work); evaluate the stop condition; if not
   stopping, `ScheduleWakeup` the next cycle. **Ground every claim in the cycle report against a
   tool result from this cycle, and say which work is unverified rather than omitting the
   distinction.** Nobody watched this cycle, so the report is the only record of it and a fabricated
   line is indistinguishable from a true one until someone re-does the work.
