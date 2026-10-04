# Step 5: apply the outcome

The terminal step of the triage workflow in [`../SKILL.md`](../SKILL.md), reached once the category
and state are settled. Every outcome here is a transition off raw intake, and each one writes to the
tracker, so nothing below runs while the interview is still open.

## Contents

- [Outcomes and their actions](#outcomes-and-their-actions)
- [Status and provenance labels](#status-and-provenance-labels)
- [Verification comment](#verification-comment)
- [Objection window comment](#objection-window-comment)
- [Needs-info comment](#needs-info-comment)

## Outcomes and their actions

Every outcome is a **transition off raw**, not a layer on top of it. Applying an outcome **clears the raw-intake marker**, the default `needs-triage` label a fresh item carries before triage, resolved from the live set (`needs-triage`), in the same edit that applies the labels below, and the item leaves the unlabeled raw state. The label sets in the table are the item's **resulting** state, not deltas stacked over the raw marker, normalization replaces the raw marker, it never adds to it.

| Outcome | Action |
|---------|--------|
| Briefed, delegable | Write the brief per [`reference/agent-brief.md`](../../../reference/agent-brief.md), durability over precision: behavioral contracts and named interfaces, **no file paths or line numbers**, apply labels + the autonomous-eligible role label (default `agent-ready`) |
| Briefed, decision-defaulted | Same brief structure and durability rules; the brief states the RECOMMENDED answer and its maintainer-vetoable alternative. Apply labels + the autonomous-eligible role label (default `agent-ready`) + `status:ready`, and post a `Decision defaulted: X — veto before merge` comment whose next line is the answer's `Basis:` (the comment, not the brief, carries any `file:line`) |
| Briefed, multi-surface mechanical stub | For mechanical-class (`work-class: mechanical`) work spanning 3+ surfaces: in place of a full brief, post a one-line `sites + fix pattern` comment and apply the autonomous-eligible role label (default `agent-ready`) + `status:ready`, the stub replaces the full brief but not the ready-to-work state, so the item is picked up like any other autonomous-eligible outcome. The brief durability rule still holds, name sites by interface / symbol / domain concept, **not file paths or line numbers** (recommended default: symbol-level naming) |
| Briefed, human-gated | Same brief structure, plus why a human must act: a genuinely open decision (open design space, product intent, cross-repo policy, or a withheld consequential answer, stated as the open question plus the evidence that would settle it) or a capability blocker (external access, manual QA); apply labels + the human-gated role label (default `needs-human`) |
| Needs more info | `status:needs-info` + the needs-info comment below |
| Already implemented | Close pointing to where the behavior lives; do NOT ledger it (`docs/out-of-scope/` records rejections, not built features) |
| Won't fix (bug) | Close with rationale comment |
| Won't fix (enhancement) | Close with rationale comment; when the repo keeps `docs/out-of-scope/`, record the rejection in the matching concept file (re-read + append to "Prior requests", or create the concept file for a first rejection) and link it from the closing comment. An enhancement PR gets the same record as an issue, so a later PR for the rejected idea meets the earlier decision |
| Duplicate | Never `completed`. Close via the adapter's native duplicate mechanic when the provider has one (GitHub: `--duplicate-of`), else not-planned + a `## Duplicate of <ref>` body section (`#<M>` same-repo, qualified `<owner>/<repo>#<M>` or URL cross-repo) + link comment |

For a PR, the outcome addresses the attached code explicitly: adopt the diff (briefed for an agent or human to carry forward), rework it (brief describes the gap between the diff and the verified requirement), or decline it (close with rationale, and the ledger entry when it's a rejected enhancement).

**Decision-carrier clusters.** When step 1's cluster detection found members sharing one decision, apply human-gated to the **carrier only** (its body lists the member numbers). Each other member instead gets a native `blocked-by` edge to the carrier plus a `blocked by #<carrier> decision` comment, **never a per-member human-gated label**. Resolving the carrier's decision unblocks the whole cluster in one human touch.

**Umbrella-fold routing (atomic).** When routing folds a member into an umbrella, treat the fold as **one indivisible sequence** per the Title section of [`reference/issue-conventions.md`](../../../reference/issue-conventions.md). Do not advance to the next item until every step completes:

1. **Item-side membership comment**, on the folded item via the adapter's comment operation, stating membership in the umbrella.
2. **Umbrella-side membership comment**, on the umbrella issue via the adapter's comment operation, matching the item-side claim (a second comment on a different item, not an optional follow-up).
3. **`blocked-by` edge**, native sub-issue / dependency link from item to umbrella.
4. **Strip the raw marker**, clear `needs-triage` in the same edit that applies the routing labels.

The item-side comment alone is never sufficient; stopping after step 1 leaves the umbrella unaware and is the failure mode this checklist prevents (#633). Before moving to the next intake row, verify step 2 landed. Re-read the umbrella's comments or the command output if needed.

**Work-class pairing (hard).** Every mutation that applies the autonomous-eligible role label (`agent-ready` by default) MUST also apply exactly one `work-class:` label in the same edit, and it must be one of the autonomously dispatchable classes (`work-class: read-only` / `mechanical` / `scoped`. Map C1–C3). Applying `agent-ready` without a work-class is a triage defect: the fail-closed admission gate then makes the item unreachable while it still looks frontier-available (medley#1677). **Never pair `agent-ready` with `work-class: structural` (C4) or `work-class: untrusted-provenance` (C5)**: those are human-gated regardless of any other signal, so the pair contradicts itself. `list-frontier --autonomous` drops such an item on the work-class floor and the role label buys nothing; before that floor existed, each lane instance in turn claimed it, hit the admission gate, and escalated, burning a worker every pass. A C4/C5 outcome takes the human-gated role label (default `needs-human`) instead, per [`reference/work-class-labels.md`](../../../reference/work-class-labels.md) "Human-floor classes exclude the autonomous-eligible role label". **Classify** from the risk-property bundle, when the `autonomy` plugin is installed, read [`work-classes.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/autonomy/reference/guardrails/work-classes.md) (same reference the work-loop admission gate cites); otherwise use the label→class mapping in [`reference/work-class-labels.md`](../../../reference/work-class-labels.md). **Preflight:** before any autonomous-eligible outcome, verify all five canonical labels exist per that reference's "Migration" section; if any are missing, stop without mutating and report remediation. `/work-items:setup apply` provisions them on repos without label-as-code, or route to the repo's declared label-as-code owner. A lane that may not write `work-class:` labels cannot meet this pairing and never applies the role label: see "Lane barred from recording a class" below.

**Lane barred from recording a class: propose it, human-gate the item.** When the session may not record a class, because the autonomous lane's standing directive forbids writing `work-class:` labels (the conforming posture for an unattended lane: the autonomy contract's `admission-policy.md` bars any agent-writable surface from supplying "the work class used for admission"), the pairing rule above cannot be met, so the autonomous-eligible role label is never applied. A delegable, decision-defaulted, or multi-surface-stub outcome instead ends in the attended queue's `[escalated]` view:

1. **Comment first.** Post an escalation marker comment per [`reference/escalation-marker.md`](../../../reference/escalation-marker.md), first line `<!-- work-items:escalation lane=<lane> kind=escalated -->`, whose body carries the `Proposed work class:` line that reference defines (one dispatchable member, C1–C3), a one-line basis, and the ready-to-paste label edit that stamps the class and flips the role in one edit (adapter: "Edit labels / assignees"). The brief, stub, or `Decision defaulted` comment the outcome already requires is still posted. Skip posting when a marker from the seam's configured write identity already stands on the item.
2. **Then the labels, in one edit:** the outcome's labels plus `status:ready`, the human-gated role label (default `needs-human`), and removal of the raw marker. No `work-class:` label and no autonomous-eligible role label.

If the comment cannot be written, change no label: the item keeps its raw marker and the next sweep retries it. A human-gated item without the marker is a parked item no queue lists as escalated, and an item left at `status:ready` with neither role label is on no queue at all; this branch must end in neither. A C4/C5 outcome is unchanged (human-gated per the paragraph above), and the unconstrained path (interactive, or a lane permitted to stamp) keeps the pairing rule as written.

**Capability-tier stamp.** When triage assesses an item for the frontier capability tier, apply the provider-permissioned `capability-tier: frontier` label in the same mutation batch as other triage labels, never encode the tier only in briefing body prose. Body mentions of frontier tier are context for operators; `work-loop` reads the label only (#1716). Preflight per [`reference/capability-tier-labels.md`](../../../reference/capability-tier-labels.md) "Migration": if the label is missing from the repo, stop without inventing it and report provisioning (label-as-code owner or `/work-items:setup`). Security-surface work routes to the frontier dispatch tier via work-class rules without requiring this stamp.

The canonical-role labels applied by these outcomes (autonomous-eligible default `agent-ready`, human-gated default `needs-human`) are **resolved from the binding's `config.role_labels` at action entry**, never hardcoded. Absent entries fall back to documented defaults silently, and stop on a malformed/empty/non-string value ([`reference/label-taxonomy.md`](../../../reference/label-taxonomy.md) "Canonical roles").

Label edits, comments, and closes route through the adapter's write mechanics (adapter: "Edit labels / assignees", "Comment on item / edit a comment", "Close item"); the gather + attention-view reads are bare. When triage spawns follow-up work, a fresh, orthogonal problem it surfaces but will not fix this pass, distinct from the item under evaluation and from work it has already scoped and routed, item creation goes through the seam `create-item` verb (`/work-items:track add` is the canonical path) and follows the shared self-observation contract ([`reference/dogfood-filing.md`](../../../reference/dogfood-filing.md): dedupe → categorize → fixed shape → `needs-triage`). That new item is genuinely raw intake, so `needs-triage` is correct for it; the item triage is *evaluating* is never sent back to raw intake, its raw marker is cleared by the closing invariant below, and follow-up whose scope triage has already decided is routed through the outcome labels above, not filed as a self-observation.

**Closing invariant, no outcome leaves a re-selectable raw item.** The attention view lists *open* items and re-selects anything still carrying the raw marker, so every outcome must leave the item unre-selectable:

- **Every routing outcome that keeps the item open clears the raw-intake marker in the same edit that applies the outcome's labels, no exceptions across the routing space.** `status:ready` (briefed/ready and decision-defaulted), the autonomous-eligible role label, the human-gated role label (default `needs-human`), `status:needs-decision`, and `status:needs-info` each **remove the raw marker**; never leave both the raw marker and a routing label present. A raw marker alongside any routing label is a contradiction, the open-only attention view reads it as still-raw and re-triages it every cycle, so an already-decided item re-enters the needs-triage queue as if it were unrouted intake and wastes a read-and-confirm pass. If an item shows both, the routed state is the truth; clear the stale raw marker.
- **Close** (already implemented / wontfix / duplicate) drops the item from the open-only attention frontier, so the raw marker is moot, a closed item never re-triages.
- **`status: confirmed` is not a routing outcome.** Step 3 applies it beside the raw marker. The outcome edit here always clears the raw marker, and replaces `status: confirmed` when it applies another `status:` value; a human-gated outcome, which applies none, keeps `status: confirmed`.

## Status and provenance labels

Two labels this skill writes come from the live label set and are never invented:

- `status: confirmed`, applied by step 3 on a passed verification.
- `provenance: signal`, applied by the outcome edit to an item whose body carries the autonomy
  signal marker (step 1).

**Preflight.** Before the edit that would apply either one, check that it exists in the repository
(adapter: the label listing step 2 uses for `priority:`). When it is absent, stop without mutating
anything, not even the other labels of that edit, and report it as a provisioning gap for the
repository's label-as-code owner, or for a person to create in the tracker. Never fall back to a
different label.

The `status:` axis is single-valued: the edit that applies `status: confirmed`, `status: ready` or
`status:needs-info` removes every other `status:` label. `provenance: signal` is not removed by any
outcome or lane edit.

## Verification comment

Step 3 posts it on a passed verification, before the label edit that applies `status: confirmed`.
If the comment cannot be posted, apply no label. In an autonomous session it starts with the AI
disclaimer.

```markdown
**Verified: <bug reproduced | request valid | PR behaves as described>**

Default branch: <commit checked> (<failure still present | not applicable>)
Open linked PRs: <#n, ... | none>
Reproduced <n> of <n> (triage_repro_count=<n>, <layer>)

1. <steps or command> on <commit>: <what it printed>
2. <steps or command> on <commit>: <what it printed>
```

The `Reproduced` line and the numbered runs are for a bug. A request or a PR states instead what was
checked and what it showed.

## Objection window comment

Posted with the brief by every outcome that applies the autonomous-eligible role label, when
`triage_objection_window_hours` resolved above 0. `<end>` is the post time plus that many hours, in
UTC, written `YYYY-MM-DDTHH:MM:SSZ`. The marker line is first so the work-loop admission gate can
find it; in an autonomous session the AI disclaimer follows it.

Post it before the label edit that applies the autonomous-eligible role label. If the comment
cannot be posted, apply no label at all: the item keeps its raw marker and the next sweep retries
it. An item made autonomous-eligible without its window comment would be dispatched with no window.

```markdown
<!-- work-items:objection-window until=<end> -->
Objection window until <end>. Triage made this item autonomous-eligible
(triage_objection_window_hours=<h>, <layer>). The work-loop lane will not start it before then.
Reply here to object, and the lane hands it to a person instead.
```

Triage posts this and moves on; nothing in triage waits for the window.

## Needs-info comment

When an item parks at `status:needs-info`, post one comment in this shape:

```markdown
**Triage paused: waiting on @<reporter>**

Stopped at: <reproduction | scope | acceptance criteria>

Questions:
1. <one fact only the reporter can supply> (the answer decides <what triage does next>)
2. <one fact only the reporter can supply> (the answer decides <what triage does next>)

Settled, no need to repeat:
- Reproduction: <reproduced, with the observed behavior | not reproduced, with what was run | not attempted, and why>
- Decided: <facts and choices fixed in this pass, or "nothing yet">
```

Two rules decide whether the comment is ready to post:

- **Every question names a fact.** A question the reporter cannot answer with one concrete fact,
  such as a request for "more detail", is rewritten or dropped.
- **The settled list is complete.** It holds every result and decision from this pass, so the next
  pass reads it in step 1 and starts from there instead of redoing the work.
