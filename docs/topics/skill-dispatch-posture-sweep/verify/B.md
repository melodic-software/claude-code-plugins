# Independent re-audit — batches B03 + B09 (27 skills)

Second-pass verdicts produced from the artifacts alone: `PLAN.md`, the checklist's **Audit criteria**
section, and each `SKILL.md` read in full. Nothing under `audit/` was opened.

## Contamination disclosure — read first

The checklist was read with a line cap that overshot the instructed boundary. Lines 88–160 were
seen, i.e. everything through `## Results`, the merge-time-normalization section, and the first rows
of `## Rows`. Specifically seen:

- the aggregate Results table (20 / 29 / 57 / 32 over 138);
- the merge-time normalization narrative, including the "re-tested B01/B04/B05/B06's 21 INLINE-ONLY
  rows, zero flips" claim and the named examples in it;
- the two surfaced-not-resolved items (`/implementation:implement-dispatch`; the four INLINE-ONLY
  rows with dispatchable sub-actions);
- the B01 and B02 row blocks (not in this batch);
- **`/session-flow:orient` — the explicit statement that B09 revised it to DISPATCH-OPTIONAL /
  `history-fork` after the criteria amendment.**

Only the last item touches a row in this batch. The reasoning recorded for `orient` below was
derived from the criteria text and the skill body, and stands on its own — but this row cannot be
claimed as blind. **Recommend a third blind read of `/session-flow:orient` specifically.** Every
other row in this batch is uncontaminated.

## Verdict counts

| Verdict | Count |
|---|---|
| DISPATCH-DEFAULT | 5 |
| DISPATCH-OPTIONAL | 5 |
| INLINE-ONLY | 15 |
| NO-CHANGE | 2 |
| **Total** | **27** |

## Rows

| Skill | Verdict | Mechanism |
|---|---|---|
| `/discovery:blindspot` | DISPATCH-OPTIONAL | plugin-agent |
| `/discovery:explore` | DISPATCH-DEFAULT | plugin-agent |
| `/discovery:explore-deep` | NO-CHANGE | — |
| `/discovery:research` | DISPATCH-DEFAULT | plugin-agent |
| `/discovery:research-deep` | INLINE-ONLY | — |
| `/disk-hygiene:clean` | INLINE-ONLY | — |
| `/docs-hygiene:audit-derivability` | INLINE-ONLY | — |
| `/docs-hygiene:audit-encapsulation` | DISPATCH-OPTIONAL | plugin-agent |
| `/docs-hygiene:audit-noise` | DISPATCH-DEFAULT | plugin-agent |
| `/docs-hygiene:compress` | INLINE-ONLY | — |
| `/docs-hygiene:extract-ssot` | INLINE-ONLY | — |
| `/docs-hygiene:rename-references` | INLINE-ONLY | — |
| `/repo-fleet-hygiene:audit` | DISPATCH-DEFAULT | plugin-agent |
| `/repo-hygiene:clean` | INLINE-ONLY | — |
| `/review:fanout` | INLINE-ONLY | — |
| `/review:quality-gate` | DISPATCH-OPTIONAL | plugin-agent |
| `/session-flow:clean-stop` | INLINE-ONLY | — |
| `/session-flow:continue-in-background` | INLINE-ONLY | — |
| `/session-flow:handoff` | INLINE-ONLY | — |
| `/session-flow:keep-going` | INLINE-ONLY | — |
| `/session-flow:orchestrate` | INLINE-ONLY | — |
| `/session-flow:orient` | DISPATCH-OPTIONAL | history-fork |
| `/session-flow:reanchor` | DISPATCH-DEFAULT | plugin-agent |
| `/session-flow:reconcile` | INLINE-ONLY | — |
| `/session-flow:retro` | DISPATCH-OPTIONAL | plugin-agent |
| `/session-flow:running-retro` | NO-CHANGE | — |
| `/session-flow:workflow` | INLINE-ONLY | — |

Preload vs. runtime for the ten dispatch verdicts: **runtime invocation** for all except
`/session-flow:reanchor` and `/docs-hygiene:audit-encapsulation`, the only two carrying no load-time
machinery. See F1.

## The fan-out discriminator (applied to four rows)

The criteria's "its own `Agent` fan-out" blocker is applied here through one test, stated once so
the four affected rows read as principled rather than inconsistent:

> **Does the dispatched agent repeat the contaminating act, or did that act already happen in the
> parent?**

Repeated by the dispatched agent → the nested fan-out is still required, the blocker bites. Already
happened in the parent → dispatch *satisfies* the control by construction, the blocker does not bite
(the criteria's own Independence signal).

| Row | Contaminating act | Repeated? | Effect |
|---|---|---|---|
| `docs-hygiene:audit-derivability` | reading the doc under audit | yes — the dispatched agent must read it | blocker bites → INLINE-ONLY |
| `docs-hygiene:compress` | producing the edits | yes — the dispatched agent produces them | blocker bites → INLINE-ONLY |
| `review:quality-gate` (self mode) | having written the code | no — a fresh agent did not write it | blocker does not bite |
| `review:fanout` | — | the fan-out IS the deliverable, not a correctness control | blocked on other grounds |

## Cross-cutting findings

### F1 — The Brief's `skills:` preload acceptance criterion contradicts the amended criteria, on the Brief's own two headline skills

PLAN.md's acceptance criteria require `discovery:researcher` and `discovery:explorer` to "preload
their skill via `skills:`". The amended criteria say the opposite: prefer runtime invocation, and
"reserve `skills:` preload for skills carrying none of that load-time machinery."

Measured across this batch by script:

- `research/SKILL.md` carries 1 `!`-precompute block; `explore/SKILL.md` carries 3. Both are
  therefore preload-contraindicated — the two skills the acceptance criteria name.
- 20 of 27 skills in this batch carry at least one `!`-precompute block.
- Among this batch's dispatch verdicts, exactly two skills carry no load-time machinery at all (no
  `!`-precompute, no `allowed-tools`, no `${user_config.…}`, no `hooks:`): `session-flow:reanchor`
  and `docs-hygiene:audit-encapsulation`. Every other dispatch verdict defaults to runtime
  invocation.

A Brief-vs-criteria conflict, not a per-row aside; it needs explicit ratification.

### F2 — The four-verdict vocabulary cannot express the dominant shape in this batch

Seven of 27 rows (26%) are skills whose **read-only lane is dispatchable and whose mutating or
interactive lane is not**. Forcing a whole-skill verdict discards the useful half of the answer:

| Skill | Dispatchable lane | Lane that must stay inline |
|---|---|---|
| `discovery:blindspot` | step 2 scan (both lanes) | step 1 intake calibrates the scan |
| `disk-hygiene:clean` | steps 1–3, the read-only audit (the default without `--execute`) | steps 4–6 deletion |
| `docs-hygiene:audit-encapsulation` | `detect` | `fix`, `file-issues` |
| `docs-hygiene:compress` | `audit` (explicitly "read-only — no dispatch") | default action |
| `docs-hygiene:rename-references` | every `audit` sub-mode + `blocklist` (phases 1–3, no Edit) | apply mode's per-match confirmation |
| `repo-hygiene:clean` | `scan`, `stash` (read-only) | every mutating tier |
| `session-flow:retro` | phases 1–3 analysis; `trends` | phase 4 codification checkpoint |

Recommend a per-action verdict axis, or an explicit `DISPATCH-DEFAULT (action: <x>)` form. This
independently reproduces the four sub-action rows the checklist surfaced from other batches, so the
gap is structural rather than an artifact of one batch's corpus.

### F3 — `disable-model-invocation` sweep (verified by script, not by eye)

One skill in this batch carries `true`: **`disk-hygiene:clean`**. Per PLAN Amendment 2 that bars both
preload and `Skill`-tool invocation, so it is undispatchable without flipping the flag — an
independent blocker on top of its interaction and destructiveness blockers. Two skills omit the field
entirely (`repo-fleet-hygiene:audit`, `repo-hygiene:clean`); the harness default applies. The other
24 declare `false`.

### F4 — `discovery:explore-deep` and `discovery:explore` assert harness facts PLAN.md verified as false

`explore-deep/SKILL.md` frontmatter is `context: fork`. Its body (line 22) states "You inherit the
parent's full toolset", and its `description` plus `explore/SKILL.md`'s routing bullet (line 24) both
state it "Requires `CLAUDE_CODE_FORK_SUBAGENT=1`". PLAN.md's verified constraints say a `context:
fork` skill "receives the narrow background tool set unless it sets `background: false`" and that
"only the `fork` subagent type (`/subtask`, `CLAUDE_CODE_FORK_SUBAGENT`) inherits the parent's exact
tool pool."

Both claims are inverted. This is precisely the "silent narrow-tool-set trap" Decision 2 cited when
rejecting `context: fork` — and the skill's own text denies the trap exists. Three places carry the
wrong claim: `explore-deep` description, `explore-deep` line 22, `explore` line 24.

### F5 — `research/SKILL.md` still instructs the posture Decision 1 overrides

Two live passages contradict dispatch-by-default: the research principle "**Main-context vs. agent
trade-off** — prefer direct research when results inform decisions (avoids summarization loss)", and
Phase 1's "**Prefer direct-context web** (WebSearch / WebFetch in the main session) for the
highest-value queries". Decision 1 records the override; the skill text is unamended.

### F6 — `research`'s Tier-3 rule turns self-referential under dispatch-by-default

The outcome gate closes with "Subagent returns are Tier 3 (synthesis), not corroborators, until their
cited primaries are fetched this turn." Read literally after Decision 1, a dispatched research run's
*entire* return is a subagent return, so the parent must treat every finding as Tier 3 and re-fetch —
defeating the dispatch. The rule is aimed at nested subagents *inside* a run; it needs explicit
scoping to that.

### F7 — `explore`'s user-facing contract degrades in three places, not one

PLAN.md anticipates one degradation (open questions re-surfaced by the parent). `explore/SKILL.md`
carries three:

1. Output-format item 7: "**Surface these to the USER** … Silent downstream resolution of surfaced
   open questions is an anti-pattern."
2. Outcome gate: "**Open questions surfaced to the user**, each with a recommended default" — a
   binary gate criterion a dispatched agent cannot pass on its own terms.
3. Purpose: "switch into plan mode for harness-level read-only protection" — `EnterPlanMode` /
   `ExitPlanMode` are dropped in every subagent.

(1) and (2) are re-surfaceable by the parent; (3) is not, and is unrecorded in the Brief.

## Per-skill rationale

### discovery

#### `/discovery:blindspot` — DISPATCH-OPTIONAL / `plugin-agent` (runtime)

Step 1's intake is a *start*-gate, not the criteria's mid-flow gate — the run never stalls partway,
and the parent passing the disclosure is the shape `explore-deep` already uses ("Scope comes
exclusively from `$ARGUMENTS`"). The codebase lane reads a whole area (DEFAULT signal), but the skill
writes no artifact by design ("Writing an artifact by reflex" is a named gotcha) and its deliverable
is in-conversation copy-paste prompt text. Both axes land on OPTIONAL.

#### `/discovery:explore` — DISPATCH-DEFAULT / `plugin-agent` (runtime; 3 `!`-precompute blocks)

Decision 1 names it, and the skill concedes the case itself: "Exploration reads many files; keeping
that out of the main conversation is what subagents are for," with inline reserved for "≤~5 known
files." Writes a durable `EXPLORE.md`; output is a 7-section report. Its own overflow rule already
splits past ~2000 words — Decision 4 makes that unconditional. Text defects: F4, F7.

#### `/discovery:explore-deep` — NO-CHANGE / — (currently `context-fork`; Decision 2 rejected that mechanism; should become `plugin-agent`)

Already dispatches, so the posture verdict is NO-CHANGE — but the mechanism is the one Decision 2
explicitly rejected, and the body asserts the inverse of PLAN.md's verified tool-filter facts (F4).
Its read-only boundary is "by instruction, not tool-enforced," which is more true than it knows:
`Edit` and `Write` survive the background filter, so nothing structural stops a violation.

#### `/discovery:research` — DISPATCH-DEFAULT / `plugin-agent` (runtime; 1 `!`-precompute block)

Decision 1 names it. No tool blocker — `WebSearch`, `WebFetch`, `Bash`, `Skill` and every MCP tool
survive the background filter, which is the whole Phase-1/Phase-3 toolset. Writes `RESEARCH.md`;
output is an evidence table; its own text warns about context cost. Contradictions F5 and F6 live in
this file.

#### `/discovery:research-deep` — INLINE-ONLY / —

Two independent hard blockers. Tier 1 dispatches `Workflow`, unavailable in every subagent — the
skill states the reason correctly ("a subagent cannot dispatch workflows"). And the multi-topic path
spawns N parallel `Agent`-tool topic agents, stripped by filter 1 unless
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` is set, which Decision 3 keeps optional. PLAN.md already
ratifies this row.

### disk-hygiene / docs-hygiene / repo-*-hygiene

#### `/disk-hygiene:clean` — INLINE-ONLY / —

Three stacked blockers: `disable-model-invocation: true` bars both dispatch paths (F3); the apply
lane gates irreversible deletion behind `AskUserQuestion` on an exact tier and path list ("a prior
general request, `--execute`, 'clean everything,' approval of another tier, or silence is not
confirmation"); and the skill self-excludes unattended contexts — "Automated, scheduled, remote,
unattended, or no-human-in-loop sessions always audit and stop." Phase note: F2.

#### `/docs-hygiene:audit-derivability` — INLINE-ONLY / —

Every DISPATCH-DEFAULT signal fires and the fan-out blocker still bites, because the contaminating
act is *reading the doc* and the dispatched agent repeats it: "After reading a doc you know its
answers, so it always *looks* re-derivable. Never confirm a load-bearing deletion from this
context — delegate to a fresh, non-fork subagent that has not seen the doc." Recursion recorded:
`sweep` also mandates "a fresh read-only subagent per document (bounded concurrency)." **With
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` set this is a prime DISPATCH-DEFAULT** — the batch's strongest
case for Amendment 4's hard-prerequisite reading over a flat INLINE-ONLY.

#### `/docs-hygiene:audit-encapsulation` — DISPATCH-OPTIONAL / `plugin-agent` (preload-eligible)

`detect` is a read-only report, but `scripts/detect.sh` does the heavy reading, so the context saving
is one Bash call's worth — real but small, which keeps it off DEFAULT. `fix` is per-hit interactive
remediation and `file-issues` mutates a tracker. One of only two skills in this batch carrying no
load-time machinery, so genuinely preload-eligible.

#### `/docs-hygiene:audit-noise` — DISPATCH-DEFAULT / `plugin-agent` (runtime; 3 `!`-precompute blocks + `allowed-tools`)

Read-only by hard rule ("No `Edit`, no `Write`, no mutating `Bash` ops"), output is a per-file tier
table, batch/dir mode reads a whole markdown corpus, no user gate, no mandated fan-out. Textbook
DEFAULT. Its `allowed-tools` grant is not a blocker per the criteria but, with the `!`-precompute,
forces runtime invocation over preload.

#### `/docs-hygiene:compress` — INLINE-ONLY / —

The fan-out blocker bites on the repeated-act test: the mandated semantic-diff verifier exists
because the model that produced the edits cannot audit them, and a dispatched agent produces those
edits. "**Semantic-diff dispatch is mandatory for default action**" is a hard rule, and the skill
lists "**Subagent context invoking `/compress` for batch fan-out**" under "When NOT to use", noting
"Subagents cannot reliably spawn the verifier themselves." Phase note: `audit` is explicitly
read-only with no dispatch.

#### `/docs-hygiene:extract-ssot` — INLINE-ONLY / —

Two blockers, plus a self-referential third. (1) `identify` defaults to "an exhaustive subagent
survey" and `batch` runs "sequential-by-default dispatch, lesson injection between subagents" —
mandated `Agent` fan-out that is the action's substance, not an optimization. (2) `execute` mutates
files under a hard rule against skipping "per-phase user diff review". (3) Its own evidence
discipline says "a subagent's survey summary … is NOT Tier 0 — promote it via your own grep before it
drives a plan or an edit," so by the skill's own rule a dispatched run's return could not drive the
edit it just made.

#### `/docs-hygiene:rename-references` — INLINE-ONLY / —

Apply mode's Phase 4 routes three triage buckets through `AskUserQuestion`, per-match for the
ambiguous bucket, and the skill calls it non-negotiable: "**Ambiguous bucket is mandatory triage, not
optional.**" A mid-flow load-bearing gate protecting file mutations; the bare-invocation smart default
also resolves the rename pair via `AskUserQuestion`. Phase note: all `audit` sub-modes and `blocklist`
run phases 1–3 with no Edit.

#### `/repo-fleet-hygiene:audit` — DISPATCH-DEFAULT / `plugin-agent` (runtime; `allowed-tools`, no `!`-precompute)

Read-only by charter, with a script that "has no mutation mode" and an explicit boundary listing every
command it must never run. Output is one fleet report with five grouped finding lists plus per-repo
handoffs. Executes `gh pr list` per local branch per repo across a fleet — the "fetches many pages
whose raw content the parent never re-reads" signal. Progressive disclosure applies strongly: a
multi-repo report should be an index with per-repository sidecars.

#### `/repo-hygiene:clean` — INLINE-ONLY / —

Destructive by design with mandatory `AskUserQuestion` gates before every `--apply` (§1.5, §4.2, §4.3,
§6, §6.5, §7), each closing "Autonomous sessions: abort." A frontmatter PreToolUse guard blocks
destructive Bash until re-issued with `CLEAN_GUARD_ACK=1`, which must "never" be added "without the
user's explicit confirmation in this session" — an irreversible-action gate that is enforced, not just
documented. Phase note: `scan` and `stash` are read-only.

### review

#### `/review:fanout` — INLINE-ONLY / —

Its `Agent` fan-out is not a degradable correctness control — it *is* the deliverable. Independently,
the orchestrator plugins are main-thread-only by the skill's own statement: "All run on the MAIN
THREAD (they fan out their own agents; a subagent cannot dependably do that)." Dispatched without
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, it becomes a fan-out skill that cannot fan out. The `fix`
action is *not* the blocker — `--yes` is the documented headless opt-in, and without it the action
"emits its classification plan and STOPs," the criteria's dispatchable shape.

#### `/review:quality-gate` — DISPATCH-OPTIONAL / `plugin-agent` (runtime; 3 `!`-precompute blocks + `allowed-tools`)

The contested row. Its hard rule — "**Self mode never runs the checklist on the producing thread.**
Dispatch a fresh-context read-only subagent; the thread that wrote the code rubber-stamps its own
recap" — looks like the fan-out blocker but is its inverse under the discriminator: the contaminating
act is *having written the code*, which a dispatched agent did not do, so dispatch satisfies producer
≠ critic by construction. It stops short of DEFAULT because Step 1 sources "the original task,
approved plan, or user intent **from conversation**", and because "Delegated modes synthesize, never
substitute — … verify each finding against the actual diff" puts verification back on the parent
regardless.

### session-flow

#### `/session-flow:clean-stop` — INLINE-ONLY / —

Two blockers. Its scope is "every repository and worktree **this session touched**" — a live
transcript input, and its idempotency requirement depends on knowing what this session already did.
And it makes irreversible outward-facing writes unattended by policy — pushes, `gh pr create`, filed
issues — plus gated worktree/branch deletion. `history-fork` is the only mechanism that could carry
the first, and clean-stop fires at end-of-session when the transcript is longest, so the fork's cost
is maximal exactly where the skill is invoked.

#### `/session-flow:continue-in-background` — INLINE-ONLY / —

Three blockers: the save-point's content is the live transcript ("what was tried and ruled out"); the
terminal moves the invoker's own session ("The background agent is the continuation; this session
terminates the task"); and it launches a detached `claude --bg` process behind a hard user-intent gate
("NEVER self-elected").

#### `/session-flow:handoff` — INLINE-ONLY / —

The archetypal case, and the clearest cost inversion. Input is the conversation; the terminal is a
`/clear` boundary in the invoker's own session ("**Mandatory STOP gate** … EXECUTION STOPS HERE"), and
a subagent cannot stop its parent. `history-fork` could read the transcript but not deliver the
stop — and the skill's own trigger is context bloat, so the fork's cost peaks precisely when the skill
fires. Dispatching handoff would consume the context handoff exists to relieve.

#### `/session-flow:keep-going` — INLINE-ONLY / —

Three blockers: intent comes from the transcript by explicit design ("Infer *what* to resume or check
from the conversation … not from an argument"); step 4 **continues the main task**, which a subagent
cannot do for its parent; and re-firing side effects or killing off-thread work is gated on evidence
("when that cannot be proven, stop and ask").

#### `/session-flow:orchestrate` — INLINE-ONLY / —

Its default action's entire effect is loading the seven imperatives "into active working context" of
**this** session — "loading them IS the priming." A subagent priming its own throwaway context
delivers nothing to the parent. The skill even names surfaces a dispatched copy could not reach:
"agent teams (lead-only) and dynamic workflows (main-session-only)." NO-CHANGE is defensible; a
nameable hard blocker makes INLINE-ONLY preferred.

#### `/session-flow:orient` — DISPATCH-OPTIONAL / `history-fork`

**Contaminated row — see the disclosure.** Reasoning as derived: read #1 of three is "The
conversation — the goal, the load-bearing decisions … Synthesize these inline," and part of the
deliverable is the *comparison* — "Where the durable state and the conversation disagree, surface the
discrepancy rather than picking one." A fresh-context mechanism cannot produce that comparison, so if
dispatched the mechanism must be `history-fork`. Inline stays default because the durable reads are
small and a `history-fork`'s cost scales with the transcript while orient is most wanted in a long
session — the escape hatch can cost more than it saves.

#### `/session-flow:reanchor` — DISPATCH-DEFAULT / `plugin-agent` — the batch's only clean `skills:` preload candidate

Inputs are durable, not conversational: "the handoff / plan / memory files and any PRs, issues,
branches, skills, or plugin versions they name." Execution is network- and output-heavy — `git fetch`
per base ref, `gh` queries per referenced PR/issue, installed-vs-source manifest comparison — none of
which the parent re-reads. Output is a drift report and it explicitly does not act ("**Does not
auto-fix drift.** It reports; the session decides"). No user gate, no fan-out, no filtered tool, and
no load-time machinery. The strongest DISPATCH-DEFAULT in the `session-flow` half.

#### `/session-flow:reconcile` — INLINE-ONLY / —

Two blockers. Its subject is "the off-thread work **this session** spawned" and its mutation target is
"**this session's** task ledger" — `TaskCreate`/`TaskGet`/`TaskList`/`TaskUpdate` are dropped by the
background filter, so a dispatched agent has no ledger to reconcile; the skill states the scoping
problem from the other side itself ("A spawned subagent owns an internal task list the parent cannot
see"). Killing still-running work is separately gated on unprovable evidence.

#### `/session-flow:retro` — DISPATCH-OPTIONAL / `plugin-agent` (runtime; 5 `!`-precompute blocks)

Decisive evidence: its input is the transcript **on disk** (`<session-id>.jsonl`, read by
`parse_transcript.py`), not live context — which is why the mechanism is `plugin-agent` rather than
`history-fork`, and why the sibling `running-retro` already dispatches exactly this analysis to a
fresh general-purpose subagent. That same-plugin precedent is the row's best argument. It stops at
OPTIONAL because "**Phase 4 is an interactive checkpoint** — never persist codifications without
explicit user approval" gates edits to the consumer's rules and `CLAUDE.md` mid-flow. **Bounded
claim:** this verdict rests on `SKILL.md` only; the skill states each mode carries "its own phases,
outputs, and interactive checkpoints" in four `context/` files that were not read.

#### `/session-flow:running-retro` — NO-CHANGE / — (already dispatches)

The heavy half already runs off-thread: step 3 spawns a general-purpose subagent that reads the
transcript and returns "a compact findings block only; the verbose transcript stays in its context."
What remains in main context is irreducible — step 1's subjective-state note is "the one thing disk
cannot capture … the only signal the analysis subagent cannot get for itself," and skipping it is a
named gotcha. The `arm` action separately launches a detached observer from the session's own context.

#### `/session-flow:workflow` — INLINE-ONLY / —

Two blockers: position detection reads the live transcript ("Check conversation context for evidence
of completed stages" across nine signals), and step 4 tracks progress "via TaskCreate", dropped by the
background filter. The saving would be near-zero regardless — a short navigator that executes no stage
("it is the map, not the territory"). NO-CHANGE is defensible on the short-and-conversational clause.

## Rows where a reasonable auditor could land differently

| Skill | This verdict | Plausible alternative | What breaks the tie |
|---|---|---|---|
| `docs-hygiene:audit-derivability` | INLINE-ONLY | DISPATCH-DEFAULT | Whether Decision 3's optional nesting or Amendment 4's hard-prerequisite reading governs. Under Amendment 4 this becomes DISPATCH-DEFAULT-with-nesting-required; every other signal points to DEFAULT. |
| `review:quality-gate` | DISPATCH-OPTIONAL | INLINE-ONLY | Whether the fan-out discriminator is accepted. Reading the hard rule literally gives INLINE-ONLY; reading its *purpose* gives dispatch-satisfies-it-by-construction. |
| `session-flow:orient` | DISPATCH-OPTIONAL / `history-fork` | INLINE-ONLY | Whether transcript-dependence is terminal or merely forces `history-fork`. Also contaminated — see the disclosure. |
| `discovery:blindspot` | DISPATCH-OPTIONAL | INLINE-ONLY | Whether step 1's intake is a "mid-flow" gate. As a start-gate the parent satisfies, it is not; as load-bearing calibration, it is. |
| `discovery:explore-deep` | NO-CHANGE | DISPATCH-DEFAULT / `plugin-agent` | Whether the verdict axis is posture (already dispatches) or mechanism (uses the mechanism Decision 2 rejected). F4 makes this more than cosmetic. |
| `session-flow:workflow` | INLINE-ONLY | NO-CHANGE | Practical outcome identical; only the blocker record differs. |
| `session-flow:orchestrate` | INLINE-ONLY | NO-CHANGE | Same — no-op either way. |
