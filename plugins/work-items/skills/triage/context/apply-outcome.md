# Step 5: apply the outcome

The terminal step of the triage workflow in [`../SKILL.md`](../SKILL.md), reached once the category
and state are settled. Every outcome here is a transition off raw intake, and each one writes to the
tracker, so nothing below runs while the interview is still open.

## Contents

- [Outcomes and their actions](#outcomes-and-their-actions)
- [Needs-info template](#needs-info-template)

## Outcomes and their actions

Every outcome is a **transition off raw**, not a layer on top of it. Applying an outcome **clears the raw-intake marker**, the default `needs-triage` label a fresh item carries before triage, resolved from the live set (whichever axis the repo files it under), in the same edit that applies the labels below, and the item leaves the unlabeled raw state. The label sets in the table are the item's **resulting** state, not deltas stacked over the raw marker, normalization replaces the raw marker, it never adds to it.

| Outcome | Action |
|---------|--------|
| Briefed, delegable | Write the brief per [`${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md), durability over precision: behavioral contracts and named interfaces, **no file paths or line numbers**, apply labels + the autonomous-eligible role label (default `agent-ready`) |
| Briefed, decision-defaulted | Same brief structure and durability rules; the brief states the RECOMMENDED answer and its maintainer-vetoable alternative. Apply labels + the autonomous-eligible role label (default `agent-ready`) + `status:ready`, and post a `Decision defaulted: X — veto before merge` comment |
| Briefed, multi-surface mechanical stub | For mechanical-class (`work-class: mechanical`) work spanning 3+ surfaces: in place of a full brief, post a one-line `sites + fix pattern` comment and apply the autonomous-eligible role label (default `agent-ready`) + `status:ready`, the stub replaces the full brief but not the ready-to-work state, so the item is picked up like any other autonomous-eligible outcome. The brief durability rule still holds, name sites by interface / symbol / domain concept, **not file paths or line numbers** (recommended default: symbol-level naming) |
| Briefed, human-gated | Same brief structure, plus why a human must act: a genuinely open decision (open design space, product intent, cross-repo policy) or a capability blocker (external access, manual QA); apply labels + the human-gated role label (default `needs-human`) |
| Needs more info | `status:needs-info` + needs-info template comment |
| Already implemented | Close pointing to where the behavior lives; do NOT ledger it (`docs/out-of-scope/` records rejections, not built features) |
| Won't fix (bug) | Close with rationale comment |
| Won't fix (enhancement) | Close with rationale comment; when the repo keeps `docs/out-of-scope/`, record the rejection in the matching concept file (re-read + append to "Prior requests", or create the concept file for a first rejection) and link it from the closing comment. Applies to enhancement PRs exactly as to issues, so the same request doesn't return as fresh code |
| Duplicate | Never `completed`. Close via the adapter's native duplicate mechanic when the provider has one (GitHub: `--duplicate-of`), else not-planned + a `## Duplicate of <ref>` body section (`#<M>` same-repo, qualified `<owner>/<repo>#<M>` or URL cross-repo) + link comment |

For a PR, the outcome addresses the attached code explicitly: adopt the diff (briefed for an agent or human to carry forward), rework it (brief describes the gap between the diff and the verified requirement), or decline it (close with rationale, and the ledger entry when it's a rejected enhancement).

**Decision-carrier clusters.** When step 1's cluster detection found members sharing one decision, apply human-gated to the **carrier only** (its body lists the member numbers). Each other member instead gets a native `blocked-by` edge to the carrier plus a `blocked by #<carrier> decision` comment, **never a per-member human-gated label**. Resolving the carrier's decision unblocks the whole cluster in one human touch.

**Umbrella-fold routing (atomic).** When routing folds a member into an umbrella, treat the fold as **one indivisible sequence** per the Title section of [`${CLAUDE_PLUGIN_ROOT}/reference/issue-conventions.md`](${CLAUDE_PLUGIN_ROOT}/reference/issue-conventions.md). Do not advance to the next item until every step completes:

1. **Item-side membership comment**, on the folded item via the adapter's comment operation, stating membership in the umbrella.
2. **Umbrella-side membership comment**, on the umbrella issue via the adapter's comment operation, matching the item-side claim (a second comment on a different item, not an optional follow-up).
3. **`blocked-by` edge**, native sub-issue / dependency link from item to umbrella.
4. **Strip the raw marker**, clear `status:needs-triage` / `priority:needs-triage` in the same edit that applies the routing labels.

The item-side comment alone is never sufficient; stopping after step 1 leaves the umbrella unaware and is the failure mode this checklist prevents (#633). Before moving to the next intake row, verify step 2 landed. Re-read the umbrella's comments or the command output if needed.

**Work-class pairing (hard).** Every mutation that applies the autonomous-eligible role label (`agent-ready` by default) MUST also apply exactly one `work-class:` label in the same edit (`work-class: read-only` / `mechanical` / `scoped` / `structural` / `untrusted-provenance`. Map C1–C5). Applying `agent-ready` without a work-class is a triage defect: the fail-closed admission gate then makes the item unreachable while it still looks frontier-available (medley#1677). **Classify** from the risk-property bundle, when the `autonomy` plugin is installed, read [`work-classes.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/autonomy/reference/guardrails/work-classes.md) (same reference the work-loop admission gate cites); otherwise use the label→class mapping in [`${CLAUDE_PLUGIN_ROOT}/reference/work-class-labels.md`](${CLAUDE_PLUGIN_ROOT}/reference/work-class-labels.md). **Preflight:** before any autonomous-eligible outcome, verify all five canonical labels exist per that reference's "Migration" section; if any are missing, stop without mutating and report remediation. `/work-items:setup apply` provisions them on repos without label-as-code, or route to the repo's declared label-as-code owner.

**Capability-tier stamp.** When triage assesses an item for the frontier capability tier, apply the provider-permissioned `capability-tier: frontier` label in the same mutation batch as other triage labels, never encode the tier only in briefing body prose. Body mentions of frontier tier are context for operators; `work-loop` reads the label only (#1716). Preflight per [`${CLAUDE_PLUGIN_ROOT}/reference/capability-tier-labels.md`](${CLAUDE_PLUGIN_ROOT}/reference/capability-tier-labels.md) "Migration": if the label is missing from the repo, stop without inventing it and report provisioning (label-as-code owner or `/work-items:setup`). Security-surface work routes to the frontier dispatch tier via work-class rules without requiring this stamp.

The canonical-role labels applied by these outcomes (autonomous-eligible default `agent-ready`, human-gated default `needs-human`) are **resolved from the binding's `config.role_labels` at action entry**, never hardcoded. Absent entries fall back to documented defaults silently, and stop on a malformed/empty/non-string value ([`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) "Canonical roles").

Label edits, comments, and closes route through the adapter's write mechanics (adapter: "Edit labels / assignees", "Comment on item / edit a comment", "Close item"); the gather + attention-view reads are bare. When triage spawns follow-up work, a fresh, orthogonal problem it surfaces but will not fix this pass, distinct from the item under evaluation and from work it has already scoped and routed, item creation goes through the seam `create-item` verb (`/work-items:track add` is the canonical path) and follows the shared self-observation contract ([`${CLAUDE_PLUGIN_ROOT}/reference/dogfood-filing.md`](${CLAUDE_PLUGIN_ROOT}/reference/dogfood-filing.md): dedupe → categorize → fixed shape → `needs-triage`). That new item is genuinely raw intake, so `needs-triage` is correct for it; the item triage is *evaluating* is never sent back to raw intake, its raw marker is cleared by the closing invariant below, and follow-up whose scope triage has already decided is routed through the outcome labels above, not filed as a self-observation.

**Closing invariant, no outcome leaves a re-selectable raw item.** The attention view lists *open* items and re-selects anything still carrying the raw marker, so every outcome must leave the item unre-selectable:

- **Every routing outcome that keeps the item open clears the raw-intake marker in the same edit that applies the outcome's labels, no exceptions across the routing space.** `status:ready` (briefed/ready and decision-defaulted), the autonomous-eligible role label, the human-gated role label (default `needs-human`), `status:needs-decision`, and `status:needs-info` each **remove the raw marker**; never leave both the raw marker and a routing label present. A raw marker alongside any routing label is a contradiction, the open-only attention view reads it as still-raw and re-triages it every cycle, so an already-decided item re-enters the needs-triage queue as if it were unrouted intake and wastes a read-and-confirm pass. If an item shows both, the routed state is the truth; clear the stale raw marker.
- **Close** (already implemented / wontfix / duplicate) drops the item from the open-only attention frontier, so the raw marker is moot, a closed item never re-triages.

## Needs-info template

When marking `status:needs-info`, post structured comment:

```markdown
**What we've established so far:**
- <preserved triage progress — verification results, decisions, what's known>

**What we still need from you (@<reporter>):**
1. <specific actionable question>
2. <specific actionable question>
```

Preserves partial-triage work so reporter re-engagement does not restart from zero. Questions must be specific and actionable, never "please provide more info".
