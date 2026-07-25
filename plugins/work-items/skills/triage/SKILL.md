---
name: triage
description: "Evaluate raw intake — any untriaged item carrying the raw marker, whoever authored it (external bug reports, incoming feature requests, unsolicited PRs, and team-authored self-observation/dogfood issues) — through a small state machine: raw → verified → briefed → autonomous-eligible, with side exits to needs-info, human-gated, and close. A PR is an item with attached code and enters the same intake as an issue. Use when: 'triage', 'what needs triage', 'triage this issue', 'triage this PR', 'evaluate this bug report', 'is this bug real', 'should we merge this unsolicited PR', 'attention view', 'what intake needs attention'. No number = attention view (untriaged intake). Sibling skills: /work-items:track (backlog CRUD), /work-items:work (auto-select + execute), /work-items:decompose (plan → tickets), /work-items:scan-todos (TODO sweep)."
argument-hint: "[<number>] — issue OR pull request number to triage; empty = attention view"
user-invocable: true
disable-model-invocation: false
---

## Variables

Arguments: `$ARGUMENTS`

## Shared tracker context

The seam, operation routing, label taxonomy, canonical-role remapping, recurring schedule, and
topic-docs binding that every work-items skill relies on live in
[`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
(and the references it links). Read it at the start of an invocation. Label edits, comments, and
closes route through the bound adapter's write mechanics; item creation goes through the seam
`create-item` verb; the core inlines no provider commands.

## Purpose

Evaluate **raw intake** — any untriaged item carrying the raw marker, whoever authored it (external bug reports, incoming feature requests, unsolicited PRs, and team-authored self-observation/dogfood issues) — through a small state machine: raw → verified → briefed → autonomous-eligible, with side exits to needs-info, human-gated, and close.

## Usage

```text
/work-items:triage <number>     # issue OR pull request
/work-items:triage              # shows attention view (untriaged intake)
```

## Scope: raw intake only

**Raw intake is defined by triage state, not authorship.** An item is raw intake when it is untriaged — unlabeled, or carrying the raw marker (`status:needs-triage` / `priority:needs-triage`, whichever axis the repo files it under) — regardless of who authored it. External bug reports, incoming feature requests, and unsolicited PRs are the common sources, but a **team-authored self-observation / dogfood issue** filed with only the raw marker ([`${CLAUDE_PLUGIN_ROOT}/reference/dogfood-filing.md`](${CLAUDE_PLUGIN_ROOT}/reference/dogfood-filing.md)) is raw intake too: it carries no routing decision yet, surfaces in the same attention view, and needs the same evaluation (priority normalization, tier routing, brief drafting). The boundary is *untriaged vs. already-triaged*, never *external vs. team-authored*.

Two rules bound what enters this flow:

- **A PR is an item with attached code.** An unsolicited or external PR enters the same intake as an issue: same states, same machine. Its diff is an **attachment to evaluate** — check it out, run the relevant tests — never an obligation to merge. Read the state names against the code: briefed means a brief exists for what to do with the diff; human-gated means a human should decide the merge.
- **Never re-triage already-triaged output.** Items born triaged — published by `/work-items:decompose`, or created by a `/work-items:track add` that leaves no raw marker — already carry a routing decision. They never re-enter this flow, and the attention view excludes them by construction (being neither unlabeled nor marked with the raw marker, they fall in none of its buckets). This exclusion keys on **absence of the raw marker**, not authorship and not the mere presence of classification labels: the raw marker (`status:needs-triage` / `priority:needs-triage`, whichever axis the repo files it under) or being unlabeled puts an item in scope even alongside default labels, so a team-authored dogfood issue filed on the status axis with a default `priority:` label *and* the raw marker is in scope (the marker wins), while a `track add` item that carries classification labels but no raw marker is out of scope for the same reason decompose output is. If someone names an already-triaged item explicitly, say it is already triaged and stop.

## Triage states

State names follow the plugin's vocabulary and the canonical roles ([`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) "Canonical roles"):

| State | Tracker marker | Meaning |
|-------|----------------|---------|
| **raw** | unlabeled or the raw marker (`status:needs-triage` / `priority:needs-triage`, whichever axis the repo files it under) | Untouched intake; every claim in it is unverified |
| **verified** | recorded in triage notes | The claim held up: bug reproduced, or PR diff confirmed to do what it says |
| **briefed** | brief posted + `status:ready` | Fully specified as a behavioral contract (per [`${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md)) |
| **autonomous-eligible** | role label (default `agent-ready`) | Briefed AND delegable — eligible for autonomous pickup from the frontier |

Side exits from any state: `status:needs-info` (returns to raw when the reporter replies), `status:needs-decision` (awaiting a human or maintainer judgment call), the human-gated role label (default `needs-human`), or close (wontfix / duplicate / already implemented).

**A briefed item takes one of three exits**, distinguished by the decision its brief carries:

- **delegable** — fully specified with no open decision → autonomous-eligible role (default `agent-ready`).
- **decision-defaulted** — a single-fork item whose brief carries a well-grounded RECOMMENDED answer with only a maintainer-vetoable (reversible) alternative → autonomous-eligible role with `status:ready`, plus a `Decision defaulted: X — veto before merge` comment. The default rides in; a maintainer vetoes before merge if it is wrong.
- **human-gated** — reserved for a genuinely open decision (open design space, product intent, or cross-repo policy), or work that cannot be delegated for a capability reason (external access, manual QA) → human-gated role (default `needs-human`).

```text
raw → verified → briefed
 |        |          ├→ delegable → autonomous-eligible (role label, default agent-ready)
 |        |          ├→ decision-defaulted → autonomous-eligible + status:ready + "Decision defaulted: … — veto before merge"
 |        |          └→ human-gated (role label, default needs-human) — briefed for a human
 |        └→ status:needs-info → raw (on reporter reply)
 ├→ status:needs-decision: awaiting a human or maintainer judgment call
 └→ close: wontfix | duplicate | already implemented
```

Claiming stays coordination state, not a label — assignee + lease via the seam (`/work-items:track start`, `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md` "Lease protocol"); `blocked` is a native `blocked-by` edge, not a `status:` label.

## Attention view (no number)

Show three buckets (oldest first, one-line summaries):

1. **Unlabeled** — never triaged
2. **Raw marker** — `status:needs-triage` / `priority:needs-triage`, whichever axis the repo files it under — explicitly tagged for evaluation
3. **`status:needs-info` with reporter activity** — reporter replied since last triage note; ready for re-evaluation

List open items and filter into buckets programmatically (adapter: "List items", bare read). When the repo treats external PRs as a request surface, include them and tag each line `[PR]` or `[issue]` — but surface only *external* PRs (a collaborator's in-flight PR is not triage work; this filter is discovery-only, and an explicitly named PR is always triaged regardless of author). Present as a compact table.

## Triage workflow (with number)

### 1. Gather context

Read the item body, comments, and any linked PRs; for a PR, the diff too (adapter: "View item", bare read). Parse prior triage notes so resolved questions are not re-asked. Then run two checks:

- **Redundancy** — search the codebase for an existing implementation of the requested behavior by domain concept (not the request's wording), and report where you looked. Found → it's an already-implemented close (step 5).
- **Rejected-concept ledger** — when the consuming repo keeps one (`docs/out-of-scope/`, one file per concept), match the request against the concept files by **concept similarity, not keyword**. On a match, answer from the ledger instead of re-litigating: "Rejected before — `docs/out-of-scope/<concept>.md`: <reason>. Still stand?" Confirmed → append this request to the file's "Prior requests" log (re-read the file from disk first; append a line, never rewrite) and close (step 5). Reconsidered → the ledger file gets updated or removed and triage proceeds. No `docs/out-of-scope/` directory → skip the check entirely.
- **Cluster detection** — cross-reference other open intake: when this item shares **one underlying decision** with other open items, do not human-gate each member individually. Designate one representative as the **decision carrier** (human-gated, with the member numbers listed in its body) and link every other member to it via the native `blocked-by` edge with a `blocked by #<carrier> decision` comment (applied in step 5). One human touch on the carrier resolves the decision for the whole cluster.

### 2. Recommend category + state

Classify **bug vs enhancement** first — it steers the rest of the flow (bugs get reproduced; rejected enhancements get ledgered). Then recommend:

- **Type** — bug → `Bug`; enhancement → `Feature` (or `Task` for tracked non-feature work). Native GitHub Issue Type on org repos, set through the seam; `type:` label on personal / non-org repos. Item title and prefix conventions: [`${CLAUDE_PLUGIN_ROOT}/reference/issue-conventions.md`](${CLAUDE_PLUGIN_ROOT}/reference/issue-conventions.md)
- **Priority label** — resolve the live `priority:` label set from the bound adapter at action entry (for the GitHub adapter, `gh label list --search 'priority:'`; members are never snapshotted here — [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) "Universal axes"). Default to the resolved set's **assessed-default** tier — the mid-urgency member when the set follows the conventional critical/high/medium/low ordering (e.g. `priority: medium`, if present) — when no directive, category rule, or severity signal sets one. Reserve the next tier up (e.g. `priority: high`) for items that block other work or carry an imminent external deadline; the top tier (e.g. `priority: critical`) keeps its existing critical semantics. A live set that doesn't follow that ordering has no default to infer by convention — ask, or omit the label the way a repo-undefined default is omitted elsewhere ([`${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md`](${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md) "Priority"). When a directive or category rule sets this label **above** the finding's self-labeled severity, record the original severity in the triage comment (e.g. `priority set to <resolved label> by <rule>; reporter severity: <sev>`) so implementers can sub-sort within a priority band. No new labels. This triage-assessed default is deliberately distinct from the `/work-items:track add` filing default (the resolved set's lowest-urgency tier, an untriaged-signal floor rather than a priority assessment)
- **Target state** — from the state machine above: needs-info, or one of the three briefed exits (delegable, decision-defaulted, human-gated). For a briefed item that carries a decision, apply the **routing test**: is the alternative reversible/maintainer-vetoable (→ **decision-defaulted**: autonomous-eligible role + `status:ready`, recorded with a `Decision defaulted: X — veto before merge` comment) or genuinely open — open design space, product intent, or cross-repo policy (→ **human-gated**)?

**Direction gate.** Recommending is read-only; the gate governs *mutation* — labels, comments, closes, item creation — and which side of it you are on is fixed by how triage was invoked:

- **Interactive session** — a human operator is present and no standing lane rules were supplied. **Brief before asking**: before presenting the recommendation, restate (1) which item (number + one-line title), (2) the decision being asked, and (3) the consequence of each option — then present the recommendation and **wait for the user's explicit direction** before mutating anything. This is the default whenever the invocation carries no autonomous mandate. The restatement is not optional compression fodder: a terse output style must never drop it, and it applies on every decision question, not only the first one of a pass — the operator working several rows in sequence (e.g. via `/work-items:attend-queue`) cannot be assumed to still be holding a prior item's context.
- **Autonomous lane** — triage is running unattended as a `/loop` or `/schedule` AFK session whose standing rules — the directive supplied with its `/loop` / `/schedule` invocation — already authorize triage mutations. Those standing rules **are** the direction this gate requires: treat the gate as satisfied and proceed through verification and outcome without a human turn, prefixing every comment and item you create with the AI disclaimer. There is no operator turn to wait for, so blocking here would deadlock the lane — the gate is met by the lane's mandate, not skipped.

The autonomous branch is the mode the AI disclaimer already anticipates: a session that mutates without a human turn. The two are one mode, not a contradiction. Formalizing this as the autonomous-mode contract — codifying that standing-lane rules constitute direction — is tracked in #459.

### 3. Verify — BEFORE any interview

Never interview anyone about the fix for a claim nobody has confirmed. Verification precedes questioning:

- **Bug** — reproduce it from the reporter's steps; confirm the failure mode matches the report
- **PR** — confirm the diff does what it claims: check it out, run the relevant tests or commands

Report the result: confirmed (with the observed behavior / code path — the item is now **verified**, which makes a far stronger brief), failed, or insufficient detail → `status:needs-info` with a structured comment (see "Needs-info template" below).

### 4. Interview (if needed)

Only after verification (or for enhancements, where the open question is scope, not fact): when the description is vague or missing acceptance criteria, ask focused questions one at a time — resolve the most load-bearing ambiguity first. Each question is a decision question and carries the same brief-before-ask restatement as the direction gate above: which item it concerns, the decision being asked, and the consequence of each answer. Post questions as item comments. Mark `status:needs-info` until the reporter responds.

### 5. Apply outcome

Every outcome is a **transition off raw**, not a layer on top of it. Applying an outcome **clears the raw-intake marker** — the default `needs-triage` label a fresh item carries before triage, resolved from the live set (whichever axis the repo files it under) — in the same edit that applies the labels below, and the item leaves the unlabeled raw state. The label sets in the table are the item's **resulting** state, not deltas stacked over the raw marker — normalization replaces the raw marker, it never adds to it.

| Outcome | Action |
|---------|--------|
| Briefed, delegable | Write the brief per [`${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md) — durability over precision: behavioral contracts and named interfaces, **no file paths or line numbers** — apply labels + the autonomous-eligible role label (default `agent-ready`) |
| Briefed, decision-defaulted | Same brief structure and durability rules; the brief states the RECOMMENDED answer and its maintainer-vetoable alternative. Apply labels + the autonomous-eligible role label (default `agent-ready`) + `status:ready`, and post a `Decision defaulted: X — veto before merge` comment |
| Briefed, T1 multi-surface stub | For a trivial (T1) fix spanning 3+ surfaces: in place of a full brief, post a one-line `sites + fix pattern` comment and apply the autonomous-eligible role label (default `agent-ready`) + `status:ready` — the stub replaces the full brief but not the ready-to-work state, so the item is picked up like any other autonomous-eligible outcome. The brief durability rule still holds — name sites by interface / symbol / domain concept, **not file paths or line numbers** (recommended default: symbol-level naming) |
| Briefed, human-gated | Same brief structure, plus why a human must act: a genuinely open decision (open design space, product intent, cross-repo policy) or a capability blocker (external access, manual QA); apply labels + the human-gated role label (default `needs-human`) |
| Needs more info | `status:needs-info` + needs-info template comment |
| Already implemented | Close pointing to where the behavior lives; do NOT ledger it (`docs/out-of-scope/` records rejections, not built features) |
| Won't fix (bug) | Close with rationale comment |
| Won't fix (enhancement) | Close with rationale comment; when the repo keeps `docs/out-of-scope/`, record the rejection in the matching concept file (re-read + append to "Prior requests", or create the concept file for a first rejection) and link it from the closing comment — applies to enhancement PRs exactly as to issues, so the same request doesn't return as fresh code |
| Duplicate | Never `completed`. Close via the adapter's native duplicate mechanic when the provider has one (GitHub: `--duplicate-of`), else not-planned + a `## Duplicate of <ref>` body section (`#<M>` same-repo, qualified `<owner>/<repo>#<M>` or URL cross-repo) + link comment |

For a PR, the outcome addresses the attached code explicitly: adopt the diff (briefed for an agent or human to carry forward), rework it (brief describes the gap between the diff and the verified requirement), or decline it (close with rationale — and the ledger entry when it's a rejected enhancement).

**Decision-carrier clusters.** When step 1's cluster detection found members sharing one decision, apply human-gated to the **carrier only** (its body lists the member numbers). Each other member instead gets a native `blocked-by` edge to the carrier plus a `blocked by #<carrier> decision` comment — **never a per-member human-gated label**. Resolving the carrier's decision unblocks the whole cluster in one human touch.

The canonical-role labels applied by these outcomes (autonomous-eligible default `agent-ready`, human-gated default `needs-human`) are **resolved from the binding's `config.role_labels` at action entry**, never hardcoded — warn loudly when a role defaults because `.work-item-tracker.json` or the entry is absent rather than applying the default string silently (a repo that remapped roles would otherwise be mislabeled), and stop on a malformed/empty/non-string value ([`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) "Canonical roles").

Label edits, comments, and closes route through the adapter's write mechanics (adapter: "Edit labels / assignees", "Comment on item / edit a comment", "Close item"); the gather + attention-view reads are bare. When triage spawns follow-up work — a fresh, orthogonal problem it surfaces but will not fix this pass, distinct from the item under evaluation and from work it has already scoped and routed — item creation goes through the seam `create-item` verb (`/work-items:track add` is the canonical path) and follows the shared self-observation contract ([`${CLAUDE_PLUGIN_ROOT}/reference/dogfood-filing.md`](${CLAUDE_PLUGIN_ROOT}/reference/dogfood-filing.md): dedupe → categorize → fixed shape → `needs-triage`). That new item is genuinely raw intake, so `needs-triage` is correct for it; the item triage is *evaluating* is never sent back to raw intake — its raw marker is cleared by the closing invariant below — and follow-up whose scope triage has already decided is routed through the outcome labels above, not filed as a self-observation.

**Closing invariant — no outcome leaves a re-selectable raw item.** The attention view lists *open* items and re-selects anything still carrying the raw marker, so every outcome must leave the item unre-selectable:

- **Every routing outcome that keeps the item open clears the raw-intake marker in the same edit that applies the outcome's labels — no exceptions across the routing space.** `status:ready` (briefed/ready and decision-defaulted), the autonomous-eligible role label, the human-gated role label (default `needs-human`), `status:needs-decision`, and `status:needs-info` each **remove the raw marker**; never leave both the raw marker and a routing label present. A raw marker alongside any routing label is a contradiction — the open-only attention view reads it as still-raw and re-triages it every cycle, so an already-decided item re-enters the needs-triage queue as if it were unrouted intake and wastes a read-and-confirm pass. If an item shows both, the routed state is the truth; clear the stale raw marker.
- **Close** (already implemented / wontfix / duplicate) drops the item from the open-only attention frontier, so the raw marker is moot — a closed item never re-triages.

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

## AI disclaimer

When creating comments or items during autonomous/agent triage sessions, prefix with:

> *This was generated by AI during triage.*
