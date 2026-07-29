---
name: babysit-loop
description: "Run one repository's pull-request queue as the merge lane of the loop-lane three-session topology: a self-paced standing or drain loop that invokes /source-control:babysit-prs each cycle at the resolved autonomy tier, layered with an activity grace window, do-not-merge respect, escalation, and lane telemetry. Merge authority is human-only until the target repo's tracked config adopts the lane; the adopted baseline is human merge for everything except gate-proven C2-mechanical PRs, and standing merge-rung raises bind only from the tracked config seam. One named exception: an invocation whose own argument line carries BOTH the 'autopilot' tier keyword AND the dedicated raise argument '--merge c3-this-run' (never a config value, never model-supplied, never inferred from a drain/merge phrasing) widens that single invocation's merge authority up to C3, with a fresh independent frontier-tier subagent resolving needs-human/thread/finding blockers first — C4-structural and C5-untrusted-provenance stay unconditionally human-merge regardless, and 'autopilot' alone leaves merge authority at the tracked rung. Use when: 'babysit loop', 'run the babysit loop', 'stand up the merge lane', 'babysit the PR queue continuously', 'drain the PR queue', 'keep merges flowing'. Required argument: <owner/repo>. Launch via /loop (self-paced). Sibling skills: /source-control:babysit-prs (the single-pass tiered mechanic), /source-control:pull-request (single-PR lifecycle)."
argument-hint: "<owner/repo> [safe|worker|autopilot] [--drain] [--strip-do-not-merge] [--<dimension> <value>] · repo is required; default: standing mode at the configured tier"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: operator
  summary: Run one repo's PR queue as a standing merge lane
  cadence: continuous
---

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Wrap the single-pass `/source-control:babysit-prs` mechanic in a self-paced loop over one
repository's pull-request queue. This skill is the **merge lane** (babysit lane) of the loop-lane
three-session topology: it advances PRs and owns merges within the autonomy ladder. It never
claims backlog items or authors work-item PRs (the worker lane's authority), and never decides operator-owned questions (the attended queue's authority).

## Loop-lane contract (cited, never restated)

Every shared cross-lane concern is owned by the loop-lane convention —
`docs/conventions/loop-lane/README.md` in this plugin's marketplace repository — and this skill
holds those contracts **by citation**: the three-session topology and the autonomy merge ladder
(including seam-only rung raises and the one named explicit-`autopilot` exception, bounded by the
unconditional C4/C5 floor), the escalation contract, order-defined capability tiers (frontier /
strong / fast; runtime resolution by model alias only, never a hard-coded model ID), stop shapes
including the drain-terminal state, the `/loop` seven-day expiry, the `#691` cycle-budget semantics
(a budget hit restarts the session, never ends the loop; today every budget hit is a terminal
manual-restart state), the `#502` telemetry comment and durable loop state, the headless-config
floor, and the subagent discipline preamble. Where this document says "per the convention", that file is the contract.

## Owned mechanics (invoked, never restated)

The single-pass mechanics belong to `/source-control:babysit-prs`: the tier matrix, scope
resolution, the guarded mutation wrappers and deterministic gates, fan-out and the worker contract,
review discipline, and the cross-tier safety invariants. Each cycle **invokes**
`/source-control:babysit-prs <tier> <owner/repo>` with the resolved tier and scope; this loop
restates none of that. Two disciplines in particular are babysit-prs's own, held here by citation:
the head-move yield (expected-head pins and HEAD assertion; its SKILL.md "Guarded mutations" and
its [loop reference](../babysit-prs/reference/loop.md) §5.1.2–§5.1.3), and the foreign-activity
discipline (the `foreign_activity` dispatch suppressor — never race a foreign session for the same
PR; its [orchestration reference](../babysit-prs/reference/orchestration.md)). The grace window
below is an additional loop-level overlay, never a replacement for them.

## Required argument and config resolution

`<owner/repo>` is required — the lane is scoped to exactly one repository per invocation. A launch
without it stops (usage guidance interactively, a logged error headless), never guessing a repository.

Everything else resolves in order:

1. **Invocation arguments** — the tier keyword (babysit-prs vocabulary) and any per-dimension or
   loop-knob override mirroring the seam keys (e.g. `--drain`, `--grace-window-minutes 45`, `--merge human-only`).
2. **The layered config seam** — the `babysit_loop_*` keys on the `.claude/source-control.md`
   surface (user-global → team-tracked → local overlay, merged per key). The key table, defaults, and
   layering semantics live in
   [`${CLAUDE_PLUGIN_ROOT}/reference/config-resolution.md`](../../reference/config-resolution.md).
3. **Tier defaults** — the resolved tier's own dimension values (`safe` when nothing resolves a tier).

**The merge dimension is the exception**: raises to the *standing* rung bind from the team-tracked
layer only — every other source may only select a *lower* (safer) rung, per the convention
("Merge-rung raises are seam-only"). The convention carries one named paired-argument exception:
an invocation whose own argument line types **both** the literal `autopilot` tier keyword **and**
the dedicated raise argument `--merge c3-this-run` widens *this single invocation's* merge
dimension up to C3, bounded by the unconditional C4/C5 floor. Either token alone is merge-inert;
the pair persists nothing, substitutes for no recorded standing raise, is never inherited from any
config key or tier default, and is never composed by a model on the caller's behalf. The full token
mechanics — why the raise has its own dedicated token, `c3-this-run` being invalid in every config
layer, and `babysit_default_tier` never supplying this lane's tier — are owned by the
config-resolution reference cited above ("The one named exception", "No config layer or key ever
supplies the exception's tokens").
**And that team-tracked layer is the TARGET repository's, never the caller's.** The lane's
required `<owner/repo>` argument may name a repository other than the current checkout (or the
lane may launch from a neutral directory), and the config resolver's ambient team layer reads the
current git root — so for every policy key that can raise behavior (the merge rung and its
tracked-adoption activation above all), the lane reads the TARGET repository's tracked
`.claude/source-control.md` from its default branch (`gh api` contents) whenever the current
checkout is not that repository. Unreadable or absent = no tracked adoption = merges stay
human-only (fail closed); a caller-side tracked file can never enable merges for a target that did
not adopt the lane. Full precedence mechanics are owned by the config reference above. Report the
effective config, which source supplied each value, and which repository's team layer bound the
merge rung, at lane start.

**Interactive ambiguity** — an interactive launch with absent or ambiguous config (no stop mode,
no tier, or conflicting signals) runs a short `AskUserQuestion` mini-interview over exactly the
unresolved keys, then offers to persist the answers: repo policy (stop mode, tier, merge rung) to
the team-tracked layer, personal deviations to the local overlay. A merge-rung raise persists to the team-tracked layer only — that write is the recorded ratification.

**Headless never blocks** (headless-config floor, per the convention): take explicit or persisted
config, else tier defaults, and log the assumption.

## Autonomy dimensions, tiers, and knobs

Autonomy is decomposed into seven dimensions; a **tier is a named preset** over them, in the
babysit-prs tier vocabulary (`safe`, `worker`, `autopilot`). What each tier grants per dimension is
owned by babysit-prs's "Autonomy tiers (per action class)" table and is not restated here. The
dimensions: 1 — discovery scope (which PRs enter the queue); 2 — fixing (branch-owned CI/review
fixes); 3 — thread resolution; 4 — draft elevation; 5 — barrier handling (escalate vs
attempt-with-research); 6 — merge authority (the autonomy-ladder rung); 7 — escalation posture.
Each has a per-dimension override key on the layered seam; the key table, defaults, and precedence
— including the merge dimension's policy-floor exception — are owned by the config reference above.

**Dimension 6 ships safe: with no tracked adoption, every merge is human.** The convention's
baseline rung — human merge for everything except gate-proven C2-mechanical PRs — is what a
repository gets by *adopting* the lane in its team-tracked config: while the target repo's tracked
`.claude/source-control.md` carries no loop-lane keys, the merge dimension resolves to
`human-only`, and a merge-capable tier from the invocation or any other source never substitutes
for that recorded adoption — the lane merges nothing and reports why. Once tracked adoption is in
place, the C2-mechanical exception is a work-class test irrespective of author: a PR qualifies only
when its work item classifies C2 mechanical, whoever authored it; bot authorship alone never
qualifies. Higher rungs (`c3-autonomous`, `full-autonomy`) are further tracked-seam flips —
recorded, human-ratified — per the convention's autonomy ladder. The rung composes with the tier,
never overrides it: a merge happens only when the resolved babysit-prs tier is merge-capable AND
its deterministic gate proves the PR ready AND the PR's work item sits within the rung. The rung
is enforced by the cycle's deterministic pre-partition (Cycle shape, step 3) — merge-capable
invocations only ever receive rung-eligible PR refs — never by standing instructions the invoked skill is trusted to honor.

**Explicit-`autopilot` widening (single-invocation, non-standing, paired-token).** Independent of
the tracked rung, an invocation whose own argument line types both `autopilot` as the tier argument
and `--merge c3-this-run` as the merge argument (in an adopted repo) raises this cycle's merge rung
to C3-equivalent when that is higher than the tracked rung, never reaching C4/C5. Either token
alone does nothing to the merge dimension. A safer argument still wins and is mutually exclusive
with the raise by grammar: every `--merge` value other than `c3-this-run` only ever selects a
*lower* rung, so `autopilot --merge human-only` merges nothing; the order is tracked rung → paired
raise → the unconditional C4/C5 ceiling (config-resolution reference, "The exception lifts the
raise restriction only").

The deterministic gate is not weakened: checks, thread resolution, and mergeability still all have
to pass. What changes is only *who tries first* on a blocked but otherwise-eligible PR — one fresh
frontier-tier resolution dispatch before it falls through, scoped by Escalation below and owned in
full by [reference/pre-escalation-dispatch.md](reference/pre-escalation-dispatch.md). A C4/C5 PR,
and any blocker left unresolved or uncertain, escalates exactly as it would without the exception.

**Always-on safety knobs** — never configurable off, whatever the tier or rung: the activity grace
window (width configurable, existence not), babysit-prs's head-move yield and expected-head
pinning, its no-background-monitor clause ("Once ready, stop"), and its watched-owner boundary.

**Loop knobs**: stop mode, cycle budget (`#691` semantics per the convention), grace-window width,
and the `#502` telemetry contract below — seam keys and defaults in the config reference above.

## Stop modes

**Standing (default).** The lane keeps watching indefinitely; idle cycles back the wakeup delay off
toward the one-hour `ScheduleWakeup` ceiling. The `/loop` seven-day expiry bounds a standing lane per
the convention: `loop_started_at` in durable state makes the approaching expiry visible, and an expiry hit is handled exactly like a budget hit (restart-request + clean stop).

**Drain (`--drain`).** The lane stops when the cycle-start snapshot shows **0 open PRs AND 0 open
issues** in the target repository — deliberately outliving the worker lane's own exit (all issues
closed or PR'd): the merge lane finishes merging the tail. Lane-infrastructure issues never gate
the drain: the per-lane telemetry tracking issues (the `Lane telemetry: <lane>` title contract,
this lane's and any sibling's) are excluded from the 0-open-issues evaluation, exactly as the
work-items lanes exclude them. The **drain-terminal state** (per the convention) also ends the
loop: every remaining open item human-gated or escalated and no PR in flight — report and stop
cleanly rather than idling forever. The exit is evaluated against the cycle-start snapshot; new
intake arriving mid-cycle is reported, never chased.

## Cycle shape

1. **Re-anchor.** Re-read the durable loop state block from the telemetry comment (conversation
   context is compaction-lossy — the comment is the source of truth for the counters); classify
   guard mode against the floor below; take the cycle-start snapshot: open PRs with head SHAs,
   last-activity timestamps, and the provenance fields the rung partition consumes
   (`isCrossRepository`, `headRepositoryOwner`, `authorAssociation`), and — in drain mode — open issues.
2. **Grace-window overlay.** From the snapshot, mark every PR whose head moved or that received
   comments within the grace window (default 30 minutes), and every draft carrying a WIP signal (a
   work-in-progress title marker, a do-not-merge label, or non-green checks). Marked PRs are
   report-only this cycle: never elevated, never thread-resolved, never merged.
3. **Rung partition (deterministic, fail closed).** When the resolved tier is merge-capable,
   compute the merge-eligible set mechanically before any babysit-prs invocation: for each open
   PR in the snapshot not already excluded by step 2, resolve its close-linked work item (the
   provider's own computed close-linkage — `gh api graphql`, `closingIssuesReferences`) and read
   that item's recorded work-class classification (the triage stamp in the item body or labels).
   A PR is merge-eligible only when its item's class sits within the effective rung: at
   `c2-mechanical`, C2 mechanical only; at `c3-autonomous`, C2 and C3; at `full-autonomy`, every
   class up to and including C3 — **`full-autonomy` never reaches C4/C5, per the unconditional
   floor below; there is no rung name that does.** The effective rung for this computation resolves
   in three ordered steps: the tracked rung, raised to C3-equivalent if this invocation's own
   argument line typed both the `autopilot` tier keyword and `--merge c3-this-run` (any other
   explicitly argued `--merge` value floors instead of raises), then floored to the unconditional C4/C5
   ceiling — see "Explicit-`autopilot` widening" above. A PR with no
   close-linked item, or an item with no recorded classification, is NOT eligible — no
   classification = no merge, at any rung, including the explicit-`autopilot` widening. A PR still
   carrying the do-not-merge label at partition time is NOT eligible at any rung or class — the
   label veto binds here, in the partition, because a merge-capable babysit-prs tier's ordinary
   gate has no label input (its `--block-labels` criterion is confined to the autopilot merge
   tier); such a PR routes to the `safe` per-PR pass like any other non-eligible PR. The one
   ordered exception: when THIS invocation carries `--strip-do-not-merge`, the strip executes
   between the snapshot and this partition — the label is removed from the flag's target PRs and
   recorded in the cycle report, so a stripped PR partitions on its work-class like any other; the
   flag is a per-invocation direct order and never persists (see do-not-merge below). This is a
   deterministic pre-partition, never narrative guidance handed to the invoked skill. Two further
   withholdings bind here, both because the downstream merge gate inspects neither surface: a PR
   whose close-linked item wears the human-gated role label WITHOUT the machine escalation marker
   is operator-*parked* (Escalation below) — NOT eligible at any rung, routed to the `safe` pass;
   and a PR carrying human blocking feedback — a human `CHANGES_REQUESTED` review, explicit human
   blocking language, or an unresolved inline human thread — is NOT eligible either, because a
   merge-capable tier's own runbook widens thread scope to human threads, which under this lane
   stays stop-and-ask: `safe` pass plus escalation. At
   `human-only` (including the no-tracked-adoption default), or under a non-merge-capable tier,
   the eligible set is empty — the widening does not apply without tracked adoption either
   (config-resolution.md, "Baseline activation is tracked adoption").
   **C4/C5 floor:** a PR that is C4 (structural) or C5 (untrusted-provenance) is NEVER in the
   eligible set, at any rung, under any invocation argument — checked before, and independent of,
   the rung comparison above. **Both are tests on the PR, not lookups of the linked item's stamp**:
   `work-classes.md` assigns a class from the risk-property bundle — blast radius, reversibility,
   provenance — and "the bundle — not the task's surface description — is what assigns a class".
   - **C5 — the code's provenance.** Two tests on the cycle-start snapshot, either one marking the
     PR C5, each failing closed to C5 when its field is missing or unreadable. **Fork test:** the
     head repository is not the base (`isCrossRepository: true`, or `headRepositoryOwner` differing
     from the base owner). **Trust test:** the provider-computed `authorAssociation` is anything
     other than `OWNER` or `MEMBER` — an outside collaborator's push to a base-repository branch
     passes the fork test yet is exactly the same-repository external contribution C5 includes.
     These two fields are the executable surface; absence of either is C5. Never test the author login against
     `babysit_watched_owners`: that key is a repository-owner allowlist, not a trusted-author list
     (`babysit-prs/SKILL.md`, "Scope resolution"), so on an org-owned repository it would call
     every internally authored PR C5. A fork PR closing an internally classified C2/C3 issue is
     still C5 — the class travels with the code's provenance, not the issue it closes.
   - **C4 — the diff's blast radius.** The stamp admits; the diff can still veto. A PR whose actual
     change is a refactor, migration, or contract change is C4 however its item is stamped, and a
     PR whose shape no longer matches its recorded class **fails closed** to escalation rather than
     to the stamp.
   - **The verdict authorizes a head SHA, not the PR.** This partition class-checked the snapshot
     head's diff, so eligibility is pinned to that SHA: the merge-capable invocation carries the
     partitioned head as its merge gate's `--expected-head` pin, and the gate's head-match refusal
     makes the binding deterministic rather than narrative. Any worker push — an ordinary CI or
     review-finding fix, not only the pre-escalation resolver's — moves the head off the pin; the
     pinned gate refuses the merge, and the invocation ends by reporting the new head instead of
     re-pinning (babysit-prs Autopilot step 3's lane-pin exception, `babysit-prs/reference/safety.md`). The
     lane then re-partitions the post-push head — provenance, C4-diff, rung — and only a
     still-eligible PR gets a fresh merge-capable invocation pinned to the new head.
4. **Invoke the mechanic.** Every invocation uses babysit-prs's own `[mode] [scope]` grammar in
   its single-PR scope form (`owner/repo#N`) — the lane's own step-2 snapshot is the discovery
   surface, so no repo-wide invocation ever runs and a PR the lane withheld is never presented
   to the mechanic at all. Three enforcement rules bind each per-PR invocation:
   - **Report-only PRs get zero invocations.** A PR marked report-only in step 2 (grace window,
     WIP-signal draft) appears in the cycle report and nowhere else — no tier, not even `safe`,
     is invoked against it, because `safe` still makes and pushes clear branch-owned fixes.
   - **Rung binds the tier.** Merge-eligible PRs (step 3) are invoked at the resolved
     merge-capable tier, one `/source-control:babysit-prs <tier> <owner/repo>#<N>` per PR, the
     invocation brief carrying the partitioned head SHA as the merge gate's required
     `--expected-head` (the lane pin; `babysit-prs/reference/safety.md`, "Lane-pinned merge
     authorization"); every other non-report-only PR is invoked at `safe` (fixes and reports;
     never resolves threads or merges). An empty eligible set means only `safe` per-PR invocations this cycle.
     Under the explicit-`autopilot` widening, a merge-eligible PR still blocked on a
     machine-escalated `needs-human` item, an open finding, or a contradictory thread gets the
     leased fresh-subagent resolution dispatch ("Explicit-`autopilot` widening" above, Escalation
     below) ahead of its `/source-control:babysit-prs autopilot <owner/repo>#<N>` invocation, not
     instead of it.
   - **Dimension overrides bind by tier flooring, never narrative.** Before invoking, lower the
     tier for a PR to the highest babysit-prs tier whose behavior exceeds NO resolved dimension
     override (babysit-prs's tier keyword is its only enforcement surface — a natural-language
     narrowing handed to a higher tier is not enforcement). Capabilities the floor forgoes are
     reported as override-constrained this cycle; the deliberate cost, here and in the rung
     partition, is that coupled higher-tier actions (e.g. worker-tier bot-thread auto-resolution)
     are foregone on floored PRs — failing closed gives up only actions the overrides or rung
     already denied. The same limit cuts the other way: an UPWARD override on a single dimension
     is unenforceable when honoring it would exceed another — ignored and reported as
     override-unenforceable, never smuggled in as narrative to a higher tier. Raising one
     dimension means raising the preset (every dimension consents), until the invoked mechanic
     exposes per-dimension enforcement (follow-up candidate).
   All per-PR mechanics — checkout, fixes, threads, gates, fan-out — run under that skill's own
   contract, and the do-not-merge stance rides every invocation.
5. **Escalate.** Anything needing an operator decision follows the convention's escalation
   contract (below); a blocked action is escalated, never routed around.
6. **Report and pace.** Upsert the telemetry comment (cycle report + updated state block + guard
   mode), evaluate the stop condition; if not stopping, `ScheduleWakeup` the next cycle.

## do-not-merge

A do-not-merge label is respected by default in every tier and at every rung — the PR is reported,
never merged, and the label is never removed. Stripping it happens only behind the explicit
`--strip-do-not-merge` invocation flag: a per-invocation direct order, never a config key, never
persisted.

## Escalation

Escalation is the convention's contract (`docs/conventions/loop-lane/README.md` §2), held by
citation: a tracker item carrying the human-gated role label — resolved from the consumer's
`.work-item-tracker.json` `config.role_labels` map, never compared as a literal; when that file is
absent, the canonical `needs-human` default applies with a loud notice — plus a machine-marked
escalation comment whose first line is
`<!-- work-items:escalation lane=babysit-loop kind=escalated -->`. That marker grammar is the
attended queue's escalated-view data contract; the sentinel names the contract owner, not the
writer (the same one-directional pattern as the `claude-ops:lane-telemetry` sentinel below), so
babysit escalations surface in the same attention view as worker escalations. Telemetry is the
report surface, never the escalation channel.

**Pre-escalation resolution attempt, explicit-`autopilot` only.** When — and only when — this
invocation's own argument line typed both the literal `autopilot` tier argument and
`--merge c3-this-run` (the widening pair above), a merge-eligible (C1-C3) PR blocked on a
**machine-escalated** `needs-human` item, an open machine-authored finding, or a
contradictory/unresolved **bot** review thread draws one fresh **frontier-tier** subagent dispatch —
context-independent, and run under the PR's worker lease — before it escalates. **Four blocker
classes it never touches**, each owned by a contract this exception does not amend:
operator-*parked* items (the role label without the machine escalation marker — the attended queue's,
and step 3 withholds the PR), human blocking feedback (stop-and-ask until GitHub state resolves it,
also withheld at step 3), merge conflicts (the dedicated merge-only conflict worker), and C4/C5 PRs
(already excluded at the rung partition). A resolution that lands re-runs step 3's provenance,
C4-diff and rung partition before any merge-capable invocation; an unresolved *or uncertain* blocker
escalates exactly as it would without the exception. This widens *who tries first*, never what the
gate requires. The full contract — frontier-tier resolution and its escalate-rather-than-dispatch
rule, the lease and independence requirements, each blocker class's rationale, the code-change
worker lifecycle, and the re-partition rule — is owned by
[reference/pre-escalation-dispatch.md](reference/pre-escalation-dispatch.md).

## Telemetry and durable loop state

The telemetry home is a **per-lane tracking issue in the target repository**, resolved from launch
config; default: the open issue titled `Lane telemetry: babysit-loop` (exact match), created with
`gh issue create` when absent (announce the creation). Maintain exactly ONE status comment on it,
sentinel-identified and edited in place (the `claude-ops` lane-telemetry contract; one writer
identity owns a marker). The upsert is inlined here because an installed plugin cannot invoke a sibling plugin's scripts:

```bash
MARKER="source-control:babysit-loop"
SENT="<!-- claude-ops:lane-telemetry marker=$MARKER -->"   # first line of $BODY_FILE
LOOKUP() { gh api --paginate "repos/$REPO/issues/$ISSUE/comments" \
  --jq ".[] | select(.body | startswith(\"$SENT\")) | .id"; }
if ! LIST=$(LOOKUP); then
  echo "telemetry: comment lookup failed; skipping upsert this cycle (fail closed)" >&2
else
  if [ -z "$LIST" ]; then
    gh api -X POST "repos/$REPO/issues/$ISSUE/comments" -F body=@"$BODY_FILE" >/dev/null
    LIST=$(LOOKUP) || LIST=""   # re-list; a failure here converges next cycle
  fi
  CANON=$(printf '%s\n' "$LIST" | sort -n | head -n1)
  if [ -n "$CANON" ]; then
    gh api -X PATCH "repos/$REPO/issues/comments/$CANON" -F body=@"$BODY_FILE"
    for DUP in $(printf '%s\n' "$LIST" | sort -n | tail -n +2); do
      gh api -X PATCH "repos/$REPO/issues/comments/$DUP" \
        -f body="Superseded duplicate - canonical telemetry comment: $CANON" || true
    done
  fi
fi
```

**Creation race reconcile (encoded above).** Two sessions racing the first-ever upsert can both
see an empty lookup and both POST, forking the singleton. The upsert converges every cycle
duplicates are visible: the LOWEST comment id is canonical (numeric sort, deterministic for
every session), the canonical comment receives the current cycle's full state, and every other
sentinel comment is edited to a one-line tombstone so it never matches a lookup again — this
covers a racer that died between its POST and its own re-list, because the NEXT session's
ordinary upsert performs the same reconcile. A crashed racer's unmerged counters are an
accepted loss (durable state re-derives over a cycle); nothing is deleted.

The comment carries the human-readable cycle report plus a machine-readable **durable loop state**
block, re-read at every cycle start:

```json
{"schema":"source-control/babysit-loop-state@1","cycle":12,"backoff_level":2,
 "stop_mode":"standing","tier":"worker","merge_rung":"c2-mechanical",
 "rate_limit_latch":false,"guard_mode":"proactive",
 "loop_started_at":"2026-07-23T15:00:00Z","restart_request":null}
```

`cycle` and `backoff_level` are the loop's durable counters; `loop_started_at` makes the
approaching seven-day expiry visible; `restart_request` is where a budget or expiry hit records the
relaunch ask; `guard_mode` is recorded every cycle.

## Rate-limit guard floor (inlined)

This lane consumes the shared subscription rate-limit windows. The operable floor below is inlined
**verbatim** per the convention's inline-floor rule (byte-identical across lanes and to the reader
contract's floor); provenance is the `rate-limit-guard` plugin's reader contract
(`plugins/rate-limit-guard/reference/reader-contract.md` in the marketplace repository) — cited for
provenance only, since an installed plugin cannot read a sibling plugin's files at runtime.

- **Tee file (fixed path):** `~/.claude/rate-limit-guard/rate-limits.json`
- **Pause threshold (fixed):** pause when **either** window reports `used_percentage >= 90`
- **Pause end:** the **tripped** window's `resets_at`; when **both** windows trip, the **later**
  `resets_at`
- **Staleness rule:** a snapshot whose `captured_at` is older than **10 minutes** is stale — treat
  the windows as **unknown** (reactive-only) for that decision; a `resets_at` already latched from a
  fresh snapshot stays valid through the pause (no refresh happens while paused). While paused, a
  consumer **must** arm a session Monitor on the tee file and re-evaluate on every write — the file
  carries **no account-identifier field**, so a write is the only signal that the windows changed
  under you (account switch, another session's refresh).
- **Drain-then-pause:** on a trip, finish in-flight work, stop claiming new work, pause until the
  pause end, and report; a hard stop happens only on explicit user request.

Two further reader-contract rules apply alongside the floor (outside the byte-audited block):

- **Fail-open capability detection, per window** (reader contract, "Capability detection"): tee file
  absent, stale, or missing `rate_limits` → whole guard **unknown → reactive-only**. An absurd
  `used_percentage` or `resets_at` makes only **that window** unknown: keep applying the floor to
  every still-plausible window, and drop to reactive-only only when no window is plausible. Never
  throttle proactively on untrusted data and never fabricate a pause.
- **Untrusted fields** (reader contract, "Tee file shape"): session-distinguishing fields (`session_id`,
  `session_name`, any future account field) are user/AI-influenced — parse them only with a JSON
  parser; never string-interpolate them into a shell command, another interpreter, or a prompt.

A trip additionally latches `rate_limit_latch` in durable state: while it is set the lane schedules
at the idle ceiling and starts no new mutating work; clear it on a fresh healthy snapshot after the
pause end.

## Subagents

Dedicated resolution dispatches through babysit-prs's own fan-out. A merge conflict routes through
its Merge Conflict Resolution contract, under which the dispatched conflict worker never pushes —
the dispatching context does; every other blocker worker, the pre-escalation resolver included,
runs the regular per-PR worker lifecycle and lands its own commit and refspec push (Escalation
above). This loop adds two lane rules, per the convention: the subagent runs at the **frontier
capability tier** (order-defined, resolved at runtime by model alias only, never a hard-coded
model ID), and every dispatch prompt carries the subagent discipline preamble — when the
`discipline` plugin is installed, invoke its sweep (sweep-all, use-your-skills, do-your-research); when absent, inline the equivalent standing instructions (verify claims against authoritative sources, prefer installed skills, re-check against active conventions), per the convention.

The explicit-`autopilot` pre-escalation dispatch (Escalation, above) adds one further requirement:
**context independence**, per the convention's §3 — the dispatched subagent must share no
conversation history with the session that authored the PR or with whatever session previously
replied on the thread being resolved. A continuation of the PR-authoring session, or a
re-invocation of the subagent that already commented on the blocker, never qualifies; spawn fresh.

## Pacing and session budget

Launch via `/loop` with the interval omitted (self-paced). At the end of every cycle that does not
stop, schedule the next with `ScheduleWakeup`, whose delay clamps to `[60, 3600]` seconds. When the
babysit-prs engine snapshot supplies `recommended_cadence`, map it per the cadence table in the
babysit-prs [loop reference](../babysit-prs/reference/loop.md) §5.3 — that mapping owns the
seconds. Idle backs off toward the 3600s ceiling (standing mode's one-hour wakeups), and a genuine
daily-scale cadence belongs to `/schedule`, not a single-session `/loop` (same section). On a
cycle-budget or seven-day-expiry hit, write a restart-request into the telemetry state block and
stop the loop cleanly — the budget restarts the session, never ends the loop, and today every
budget hit is a terminal manual-restart state, per the convention.

## Gotchas

- **The loop never merges — babysit-prs does, through its pinned gate.** This layer holds no merge
  command; the rung binds by scoping — a merge-capable invocation only ever receives the
  rung-eligible PR refs the pre-partition computed. A rung can never make the safe tier merge, and
  no rung ever bypasses the deterministic gate.
- **Unlinked or unclassified PRs never auto-merge.** Rung eligibility requires a close-linked work
  item with a recorded classification; missing either fails closed to the non-merge pass.
- **A tier keyword is never a merge raise — the raise is its own token, and the pair lasts the
  invocation that typed it.** `autopilot` alone widens dimensions 1–5 and 7 only; the typed pair
  `autopilot` + `--merge c3-this-run` widens dimension 6 up to C3, per the convention's one named
  exception — persisting nothing, never reaching C4/C5, never substituting for a tracked raise.
  The pair holds for **every cycle of the invocation that typed it** (each `/loop` wakeup
  re-invokes the same prompt in the same session, carrying the same explicit authorization) and
  ends when a newly launched invocation omits either token — a `babysit_loop_tier: autopilot`
  config value with no typed pair is that case, and stays at the seam rung.
- **C4/C5 never merge autonomously, full stop.** Not at `full-autonomy`, not under the
  explicit-`autopilot` exception, not through any future rung name. This is a floor from the
  autonomy matrix's own promotion contract, not a `babysit_loop_merge` value — no config edit in
  this plugin can remove it.
- **Dependency-manager PRs stay held even at the C2 rung.** babysit-prs's cross-tier dependency
  hold-merge invariant survives this loop: a Dependabot/Renovate-class PR is never merged
  autonomously regardless of work class — it lands on the merge-ready report instead; the C2-mechanical rung is a work-class ceiling, not a route around an owner invariant.
- **The grace window is an overlay, not a substitute.** Excluding recently-active PRs at cycle
  level does not relax babysit-prs's expected-head pins or HEAD assertions inside the cycle; both disciplines hold simultaneously.
- **Drain counts issues, not just PRs.** 0 open PRs alone never exits a drain — the worker lane
  may still be authoring; only 0 open PRs AND 0 open non-excluded issues (or the drain-terminal
  state) ends the loop.
- **An open telemetry issue is the lane operating, not backlog.** Never work, close, or wait on a `Lane telemetry: <lane>` issue, and never count one against the drain exit.
