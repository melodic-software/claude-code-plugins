# Independent re-audit — batch A (22 skills)

Second-pass verdicts produced without reading `audit/*.md`. Inputs: `PLAN.md`, the checklist's
`## Audit criteria` section, and each `SKILL.md` read in full (plus
`architecture/skills/improve/actions/deepening.md`, which holds that skill's load-bearing phases).

## Blindness disclosure (read this before weighing the agreements)

The checklist read overshot the instructed boundary: `## Rows` begins at line 135 and the read window
ran to line 160, so **B01's eleven rows (`adhd:clarify` … `claude-memory:stateless`) were seen** —
verdict and mechanism columns only, no rationale. Nothing from B02 onward in this batch was seen.

Against those eleven visible rows this pass lands **three divergences and eight agreements**. Weigh
them asymmetrically:

- The **three divergences are strong independence evidence** — reached against a visible prior
  verdict, not in ignorance of it. Two are substantive (`bug-report:write`,
  `claude-config:audit-instructions`); one is label-only (`adhd:clarify`, INLINE-ONLY → NO-CHANGE,
  same practical outcome).
- The **eight agreements are weak evidence.** Anchoring cannot be ruled out. Do not count them as
  confirmation.
- The **eleven planning-plugin rows carry no contamination** and are clean second opinions.

## Interpretive line applied throughout — the recursion blocker's discriminator

The criteria block dispatch when a skill "mandates fresh-context subagents as a correctness
control." Applied literally this would sweep in every skill that spawns anything, so the operative
question is **whether outer dispatch discharges the independence requirement the inner fan-out
exists to satisfy**:

- **Artifact graded was produced OUTSIDE this run** (a plan authored in another session, an
  incumbent already living in the codebase). Dispatching the whole skill to a fresh context makes
  the outer agent the fresh pair of eyes; the inner hop was only ever compensating for the
  producing context. → **not a blocker.** (`planning:devils-advocate`)
- **Artifact graded is produced INSIDE this run** (Phase C grades the proposals Phase B just made;
  Step 3 grades the plan Step 2 just wrote). Outer dispatch relocates the producer but does not
  separate producer from critic — one dispatched agent still grades its own output. →
  **blocker.** (`claude-config:audit-instructions`, `planning:plan`)
- **Fan-out framed as throughput, not independence** → **not a blocker.**
  (`claude-config:audit-automation-gaps`, whose research fan-out explicitly says "prefer direct
  research in main context over agent delegation when capacity allows.")

Where a row rests on this line it is cited by name.

**Mechanism note applied fleet-wide in this batch.** Every dispatch row here carries load-time
machinery — `!`-precompute blocks and/or `${user_config.…}` substitution — so per the criteria's
preload-vs-runtime paragraph each is recorded as `plugin-agent (runtime invocation)`. None qualifies
for `skills:` preload.

## Verdicts

| Skill | Verdict | Mechanism |
|---|---|---|
| `/adhd:clarify` | NO-CHANGE | — |
| `/adhd:shape` | NO-CHANGE | — |
| `/ai-briefing:generate` | DISPATCH-DEFAULT | plugin-agent (runtime invocation) |
| `/architecture:improve` | INLINE-ONLY | — (phase-granularity finding — see row) |
| `/bug-report:write` | DISPATCH-OPTIONAL | plugin-agent (runtime invocation) |
| `/claude-config:audit` | DISPATCH-DEFAULT | plugin-agent (runtime invocation) |
| `/claude-config:audit-automation-gaps` | DISPATCH-DEFAULT | plugin-agent (runtime invocation) |
| `/claude-config:audit-instructions` | INLINE-ONLY | — |
| `/claude-config:audit-permission-grants` | NO-CHANGE | — |
| `/claude-memory:audit` | DISPATCH-DEFAULT | plugin-agent (runtime invocation) |
| `/claude-memory:stateless` | INLINE-ONLY | — |
| `/planning:audit-answers` | INLINE-ONLY | — |
| `/planning:brainstorm` | NO-CHANGE | — |
| `/planning:design` | INLINE-ONLY | — |
| `/planning:design-handoff` | DISPATCH-OPTIONAL | plugin-agent (runtime invocation) |
| `/planning:devils-advocate` | DISPATCH-DEFAULT | plugin-agent (runtime invocation) |
| `/planning:draft-goal-condition` | NO-CHANGE | — |
| `/planning:interview` | INLINE-ONLY | — |
| `/planning:plan` | INLINE-ONLY | — |
| `/planning:prd` | INLINE-ONLY | — |
| `/planning:questionnaire` | INLINE-ONLY | — |
| `/planning:wayfind` | INLINE-ONLY | — |

Counts:

- DISPATCH-DEFAULT — 5
- DISPATCH-OPTIONAL — 2
- INLINE-ONLY — 10
- NO-CHANGE — 5
- Total — 22

## Rationale

### `/adhd:clarify` — NO-CHANGE

Decided on cost/benefit, **not** on a transcript blocker. Input is one artifact; output is a decision
table the user answers from by row number, so it must land in the parent's context whole — dispatch
saves nothing and costs a hop. The transcript shape is a supporting observation only: the empty
argument targets "the assistant's own previous response," so dispatch would want `history-fork`,
which degrades to *stop* rather than to inline. Deliberately not blocked on conversation-as-input,
since that same shape is waived one row over for `devils-advocate`. Progressive disclosure N/A
(Amendment 5 — no persisted artifact set).

### `/adhd:shape` — NO-CHANGE

Sets a standing output posture over the invoker's own future responses ("shape **every** response for
the rest of this session"). It produces no work product at all, so there is nothing to move off
context; a subagent could not relocate the parent's posture even if there were. Nothing to change.

### `/ai-briefing:generate` — DISPATCH-DEFAULT / plugin-agent (runtime invocation)

Every DISPATCH-DEFAULT signal fires: it fetches many vendor blogs, RSS feeds, and GitHub release
pages whose raw content the parent never re-reads, and it already writes a durable markdown briefing
plus a seen-item registry, reporting "collected, excluded, deduplicated, and secondary-only counts
plus the output path." Interaction is not a blocker — the step-2 confirmation gate has an explicit
documented bypass (`--yes` / `-y`, "Required for headless runs"), which is the skill's own
non-interactive path rather than an inferred degrade. Tools needed (WebFetch, WebSearch, Bash,
Write, MCP) all survive the background filter. Runtime invocation is mandatory here: the body reads
`${user_config.active_profile}`, whose behavior under `skills:` preload is unverified.
**Progressive disclosure:** yes — provider sections with HIGH/MEDIUM/LOW tiers are already a natural
index-plus-sidecar split.

### `/architecture:improve` — INLINE-ONLY (whole-skill verdict is the wrong granularity)

Two blockers on the whole skill. (1) **Mid-flow load-bearing gate**: `actions/deepening.md` Phase 2
ends "Do NOT propose interfaces yet. After the report is written, ask: 'Which of these would you like
to explore?'" — Phase 3's entire interview loop is scoped to the candidate the user picks, so the run
cannot proceed correctly without that answer. (2) **Its own mandated `Agent` fan-out as a
correctness control**: Phase 1 instructs "Use the Agent tool with `subagent_type=Explore`", and
Design-It-Twice "fan[s] out 3–4 parallel subagents each under a deliberately orthogonal design
constraint" — orthogonality across independent contexts is the mechanism, unreproducible by one
agent reasoning to itself.

**Phase-granularity finding, stated sharply:** Phases 1 → 1.5 → 2 are exactly the DISPATCH-DEFAULT
shape (heavy codebase scan, adversarial reproduction gate, an HTML report plus a durable
`deepening-candidates-<ts>.md` in the memory slice) and terminate at a clean user-pick boundary. But
that segment is **not unconditionally dispatchable** — it is the segment carrying the Explore fan-out,
so dispatching it is conditional on `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, which Decision 3 keeps
optional. The correct shape is a scan/report phase dispatched under a nesting prerequisite, with the
Phase-3 interview staying in main context — not a whole-skill verdict either way.
**Progressive disclosure:** the candidate artifact is already one-entry-per-candidate; the HTML
report is the index over it.

### `/bug-report:write` — DISPATCH-OPTIONAL / plugin-agent (runtime invocation)

Deliberately **not** blocked on interaction, and the strongest evidence is in the skill itself: every
field that cannot be backed gets `(unknown — needs reporter confirmation)`, and `--no-survey` means
"trust the description." That is a documented in-skill degrade path — the exact shape the criteria
say must not be read as a mid-flow gate. Step 5 hand-off is explicitly "recommend the next step (do
NOT auto-invoke)", so no irreversible action is gated either. What holds it back from
DISPATCH-DEFAULT is cost, not permissibility: the skill states its own survey is "a fast grounding
pass, not deep work" and "does not run a broad exploration or research pass," so there is little raw
content to keep out of the parent, while the reporter who saw the bug is present and the Q&A is
cheap in-line. Dispatch earns its place for batch write-ups or when the survey turns out heavy.
**Progressive disclosure:** N/A — a five-field report is already minimal.

### `/claude-config:audit` — DISPATCH-DEFAULT / plugin-agent (runtime invocation)

Report-shaped by default and read-heavy: parses four config files, runs two bundled scripts, fetches
two official doc pages live, and runs `gh issue view` per entry in `known-issues.md` — raw material
the parent never needs. Output is a severity-rated findings table. The interactive checkpoint and
Phase 5 edits are both gated behind `--fix`, which is not the default (`Phase 5 is SKIPPED in default
report-only mode`), so `--fix` is the documented inline escape hatch rather than a whole-skill
blocker. Runtime invocation: the frontmatter carries a `!`-precompute block (`claude --version`)
whose behavior under preload is unverified. **Progressive disclosure:** yes — seven validation
categories A–G map cleanly onto an index plus one sidecar per category.

### `/claude-config:audit-automation-gaps` — DISPATCH-DEFAULT / plugin-agent (runtime invocation)

Same shape: an inventory script, per-candidate codebase reads, `git log --grep` incident counting,
tool timing runs, and doc fetches, condensing to a PASS/CONDITIONAL/REJECT verdict table plus a
maturity paragraph. The 2.2 research fan-out is **not** a recursion blocker under the discriminator
above — it is framed as throughput and the skill explicitly prefers the inline alternative ("Prefer
direct research in main context over agent delegation when capacity allows"), so degrading it to
sequential research costs speed, not correctness. Phase 4 (`--implement`) mutates and is not the
default (`--recommend-only` is), making it the inline escape hatch. **Progressive disclosure:** yes —
the summary table is the index, per-candidate detailed verdicts are the sidecars.

### `/claude-config:audit-instructions` — INLINE-ONLY

**This is my sharpest disagreement with the visible B01 row (DISPATCH-DEFAULT) and the finding I most
want ratified.** Every surface signal does point at DISPATCH-DEFAULT — report-only by contract, no
`--fix`, persists to `${CLAUDE_PLUGIN_DATA}/audit-instructions/last-audit.md`, sweeps a large
instruction surface. It is blocked anyway, by the recursion criterion under the inside-the-run half
of the discriminator: **Phase C grades proposals Phase B produced in the same run**, and the skill
says so in the words the criterion was written for — "Dispatch **fresh-context, non-fork**
subagents — this is a self-grade of the audit's own proposals, so a fork that inherits the producing
context would not be independent." Outer dispatch cannot discharge that; a single dispatched agent
without `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` silently collapses Phase B's per-surface lanes and
Phase C's refutation pass into inline self-critique, and the gotchas name that exact failure
("Behavioral findings ship as proposals, not confident cuts … that is why the verify pass … exist[s]").
Secondary: "Before the total dispatch count … would exceed ~20, confirm with the user first" is a
mid-flow cost gate.

Two escalation notes. First, this row was **not covered by the merge-time normalization** — that pass
re-tested only B01's INLINE-ONLY rows against the amended interaction rule, so a DISPATCH-DEFAULT row
was never checked against the Phase C independence control. Second, if Amendment 4 ("nesting is a
hard prerequisite for dispatching that subset") is confirmed, this row becomes DISPATCH-DEFAULT
*gated on* `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` rather than INLINE-ONLY — it is a prime candidate
for that treatment, and the current INLINE-ONLY verdict should be read as "blocked under the locked
criteria," not "never dispatchable."
**Progressive disclosure:** yes — findings table as index, per-surface diffs as sidecars.

### `/claude-config:audit-permission-grants` — NO-CHANGE

The whole skill is one deterministic script (`permission-rule-check.sh`) plus a table of its output.
Report-only with no `--fix` by design. There is no bulk raw content to keep out of the parent — the
script's finding lines *are* the report — so dispatch buys nothing and adds a hop. Short and
mechanical; no blocker either.

### `/claude-memory:audit` — DISPATCH-DEFAULT / plugin-agent (runtime invocation)

Reads `CLAUDE.md`, `CLAUDE.local.md`, every file under `.claude/rules/**`, and the auto-memory tree
against a codified checklist, and already persists a durable artifact
(`${CLAUDE_PLUGIN_DATA}/audit/last-audit.md`) that a separate `report` action re-reads — the parent
needs the findings, never the swept files. `fix` mode ("asks for approval") and `update` mode are
non-default actions and form the inline escape hatch; bare invocation is report-only. Runtime
invocation is firmly indicated: six `!`-precompute blocks run in this frontmatter, none of them
verified to fire under `skills:` preload. **Progressive disclosure:** yes — the deterministic spine
(C1/M1/M2/RD1) and the judgment tier (C2–C8, R1–R4, M3–M4) are a natural index/sidecar split, and the
skill already labels the two tiers distinctly.

### `/claude-memory:stateless` — INLINE-ONLY

Blocker: an **irreversible action behind a live-user gate**. `purge` is "Destructive … deletes only
after explicit confirmation," and `purge all` requires "ONE combined gate stating the total count and
every directory." `disable` writes settings at a scope the user must pick first. A dispatched agent
cannot obtain that confirmation, and deferring it to the parent either stalls the run or leaves it
poised over a delete — precisely the irreversible-action half of the interaction test.

Sub-action note, mirroring the treatment the normalization already gave `firecrawl:update --check`
and `kindle-dedrm:manage update`: `status` and `status all` are explicitly read-only and would
dispatch cleanly (`status all` enumerates every per-project store machine-wide, the most
content-heavy path here). Recorded as further evidence for the phase-granularity problem, **not** as
a verdict flip.

### `/planning:audit-answers` — INLINE-ONLY

Two blockers, led by the one outer dispatch cannot discharge. (1) **Mandated multi-validator
cross-check**: Step 2 dispatches "1–3 fresh-context (non-fork) adversarial validator subagents, each
reviewing the whole answer set — the count scales independent redundancy," and Step 4 merges on the
rule that "any CHALLENGED or RECLASSIFIED from *any* validator wins over another's CONFIRMED." A
single dispatched agent cannot produce independent cross-checks of itself; the merge rule becomes
vacuous. Note the outer-dispatch argument does partly apply here — validators read a *persisted*
ledger, not this run's output — which is why the cross-check, not the fork/fresh-context sentence, is
the load-bearing half. (2) **Mandatory human gate mid-flow**: Step 5 states "Persistence happens here
and only here … This gate is mandatory — a CONFIRMED collapse is a summary to skim, never a licence
to skip the human," and the triaged challenges return as real interview-format questions. The run
cannot complete without them.

### `/planning:brainstorm` — NO-CHANGE

Dispatch would be pure loss independent of any blocker: the deliverable is roughly ten
codebase-grounded candidates that the user reacts to by number, so the full list must land in the
parent's context verbatim — there is nothing to summarize. Output is session-only by default ("no
persisted artifact by default"), and the grounding pass is explicitly a "fast breadth pass." The
step-4 reaction gate is genuinely mid-flow load-bearing, but the cost/benefit call already settles
this row without leaning on it.

### `/planning:design` — INLINE-ONLY

Blocker: **a live user, mid-flow load-bearing**, and the skill states it as an invariant —
"Collaborative always. Never autonomously decide design. Ask in frontier rounds." Each round's
answers recompute the next frontier and are what get written into `design-threads.md` /
`type-inventory.md`; a run that defers them either stalls or writes a design the user never chose.
Phase 2 additionally requires "Confirm the seam sketch with the user before design output is
finalized." Correctly not blocked on `AskUserQuestion` — the skill's default surface is inline prose
and the card is opt-in behind `${user_config.use_ask_user_question}`; the blocker is the absence of a
USER either way.
**Progressive disclosure** (recorded independent of the verdict): yes, and it is the batch's clearest
case — the skill already emits `capability-matrix.md`, `type-inventory.md`, `design-threads.md`, and
`library-topology.md` as a sidecar set with **no index over them**, so a consumer must open all four
to find one decision.

### `/planning:design-handoff` — DISPATCH-OPTIONAL / plugin-agent (runtime invocation)

The deciding question is whether reading the gate off the artifact already discharges producer≠critic.
**Concluded: it reduces but does not eliminate it.** The skill itself names the risk — "a producing
model rubber-stamps its own recap, so the gate must be read off the file rather than judged from
memory" — and its gotchas warn "Do not soften a FAIL into a warning because the offending thread
'feels minor'." Reading off the file constrains *what* is judged; a producing session still decides
whether a thread's recorded rationale counts as RESOLVED, and it has an incentive to pass its own
design. Dispatching makes the gate independent by construction. Inline stays the default because the
input is one file and the entire output (PASS/FAIL, plus a plan-ready summary the parent must hand to
`/planning:plan` in full) has to land in context anyway — there is no summarization saving.
**Progressive disclosure:** N/A.

### `/planning:devils-advocate` — DISPATCH-DEFAULT / plugin-agent (runtime invocation)

The **independence** signal decides this, on the outside-the-run half of the discriminator. The skill
already requires a fresh pair of eyes and dispatches for it — "if the plan under review was produced
in THIS context/session … dispatch the stress-test to a fresh-context sub-agent," and in `incumbent`
mode "always dispatch." Because the artifact under attack (a plan, an incumbent already in the
codebase) was produced *outside* the stress-test run, outer dispatch satisfies that requirement by
construction and the inner hop becomes unnecessary — the dispatched agent is itself the fresh context
and can invoke `/discovery:explore` through the `Skill` tool without needing `Agent`. On top of
independence: Round 2 is explicitly "the research-heavy round" (issue trackers, doc fetches, web
search) and the output is a severity-ranked findings set, not an in-conversation decision.

One packaging requirement, not a blocker: invoked bare, the skill works "from the current
conversation context — the most recent plan, proposal, or design being discussed." The dispatch must
therefore carry the plan text (or path) in the prompt — which the skill's own sub-dispatch contract
already mandates ("the dispatch prompt carries only WHAT to investigate … never your conclusions").
**Progressive disclosure:** yes — Risk Summary as index, per-finding blocks as sidecars.

### `/planning:draft-goal-condition` — NO-CHANGE

One doc fetch, one draft, one character-count script, and the deliverable is a single short
paste-ready `/goal <condition>` string the user must see verbatim. Nothing to keep out of the
parent's context; a dispatch hop would cost more than the whole run. No blocker either — the
doc-fetch-failure path asks the user for the shape and limit, but that degrades cleanly to returning
an open question.

### `/planning:interview` — INLINE-ONLY

The archetype of the mid-flow load-bearing blocker. Frontier rounds are "ask the whole frontier as
one numbered round, **wait for the answers**, recompute the frontier"; `me` mode has no question cap
and stops only on "an **empty decision-tree ledger** plus the confirmation gate"; and Step 3's
confirmation gate is explicit — "Do not act on the interview's output until they confirm." The
auto-guard makes the failure mode named: "Silently capturing such a choice as an assumption is the
failure mode this guard prevents" — which is exactly what a dispatched run deferring its questions
would do. Blocker named as the absence of a USER, not of `AskUserQuestion` (prose rounds are the
default surface here; the card is opt-in and equally unreachable).

### `/planning:plan` — INLINE-ONLY

Two blockers. (1) **Own `Agent` fan-out as a correctness control, inside-the-run**: Step 3 is titled
"MANDATORY — never skip" and reads "the producing main thread MUST NOT self-attack the plan inline —
fresh-context verifiers outperform self-critique; the model that just wrote the plan rubber-stamps
it," with the gotcha "NEVER skip Step 3 … MANDATORY regardless of blast radius." The plan being
reviewed is authored in Step 2 of the same run, so outer dispatch relocates the producer without
separating it from the critic; without nesting the step silently degrades to the self-critique it
forbids. Step 4 dispatches `/devils-advocate` the same way. (2) **Terminal user-approval gate**:
Step 5 is the skill's stated purpose ("The plan is a proposal, not a commitment"; "Never start
executing without user approval. The approval gate is the point"). Also worth recording: the Step 1
design gate offers a user override via `AskUserQuestion`, and the post-approval branch-name check
would move the invoker's own session.
**Progressive disclosure** (independent of the verdict): yes — PLAN.md is one flat document carrying
Brief, Plan phases, Blast radius, Stress-test summary, Execution shape, Open questions, and Handoff,
and its own close-out step already concedes the size problem ("PR bodies cap near 64 KB; paste the
contract, reference the rest").

### `/planning:prd` — INLINE-ONLY

Blocker: **a live user, mid-flow load-bearing.** Step 4's frontier-rounds Q&A does not merely inform
the artifact — the answers *are* the artifact's seven required sections (problem, users, success
metrics with threshold and window …), so a run that defers them produces an empty PRD. Step 1's
skip-condition check is a hard stop requiring an explicit user override. The `synthesize` action
looks like a non-interactive path but is not one for a dispatched agent: it "produce[s] the PRD from
existing conversation context — prior discussion, explored files, research findings, user statements
already captured in the session," which fresh-context mechanisms discard. Tier selection likewise
asks when unspecified.
**Progressive disclosure** (independent of the verdict): mild — PRD.md holds seven required sections
in one file, but tier-1 is a line per section, so the flat shape earns its place until tier-3.

**Amendment 5 note for this batch:** the progressive-disclosure check is recorded only on rows that
actually persist an artifact set. `adhd:shape`, `adhd:clarify`, `planning:brainstorm`,
`planning:draft-goal-condition`, `planning:questionnaire`, `planning:wayfind`,
`claude-config:audit-permission-grants`, `planning:interview`, and `claude-memory:stateless` produce
a conversational answer, a single short document, or tracker state — index-plus-sidecars does not
apply and is not forced on them.

### `/planning:questionnaire` — INLINE-ONLY

Two blockers, the first mechanical and absolute. (1) `disable-model-invocation: true` in the
frontmatter — per PLAN.md Amendment 2 this bars **both** dispatch paths, `skills:` preload *and*
`Skill`-tool invocation, so the skill is undispatchable by any of the four mechanisms without first
flipping the flag. (2) Its loop is two mid-flow load-bearing exchanges with the user — "Who is it
going to?" and "What do you need back?" — and the document is written from those answers alone
("Done when you have a concrete list of what the user must walk away able to do or decide"), with a
route-away branch that only the user's answers can trigger. Even with the flag flipped, blocker (2)
stands.

### `/planning:wayfind` — INLINE-ONLY

Blocker: **a live user, declared by the skill itself.** `chart` mode "refuses non-interactive
sessions" and says why — "If the session is non-interactive (`CLAUDE_CODE_REMOTE`, `claude -p`, an
autonomous loop), STOP and report that charting needs an interactive session — do not fabricate a
map." `work` mode carries the inviolable "Does not resolve a HITL item for the human," filters
`needs-human` items out of a non-interactive frontier, and STOPs truthfully when that empties it —
and the HITL types route straight into `/planning:interview` / `/planning:design`, themselves
INLINE-ONLY here. Secondary: work mode mutates the tracker (issue creation, `@me` claim leases,
comment→index→close sequences) — outward-facing writes. Correctly **not** blocked on its
`allowed-tools` grant, per the B07 adjudication.

Sub-action note (phase-granularity evidence, not a flip): a `wayfind: research`-typed item is
explicitly labelled "autonomous-capable" and routes to `/discovery:research`, so that one branch of
`work` is dispatchable while `chart` and the HITL branches are not.

## Where a reasonable auditor could land differently

| Skill | My verdict | The plausible alternative, and what turns it |
|---|---|---|
| `/claude-config:audit-instructions` | INLINE-ONLY | DISPATCH-DEFAULT, if the recursion criterion is read as covering only fan-outs the dispatched agent *cannot* approximate, or once Amendment 4 lands and the row becomes dispatch-gated-on-nesting. Every non-recursion signal points at dispatch. Highest-value row to ratify. |
| `/planning:devils-advocate` | DISPATCH-DEFAULT | NO-CHANGE ("already dispatches — its fresh-context requirement is the dispatch"). Turns on whether an internally-mandated conditional sub-dispatch counts as the skill already dispatching, or as a mechanism that should be lifted to the skill's own default posture. |
| `/bug-report:write` | DISPATCH-OPTIONAL | INLINE-ONLY on the ambiguous-symbol / severity questions, or DISPATCH-DEFAULT on the report-shaped-output signal. I read the `(unknown — needs reporter confirmation)` placeholder as a decisive in-skill degrade path against the former, and the skill's own "fast grounding pass, not deep work" against the latter. |
| `/planning:design-handoff` | DISPATCH-OPTIONAL | NO-CHANGE, if reading the gate off the artifact is taken to fully discharge producer≠critic. I concluded it does not — the skill's own "do not soften a FAIL" gotcha implies residual producer incentive. |
| `/adhd:clarify` | NO-CHANGE | INLINE-ONLY on a live-transcript blocker. I declined that basis on consistency grounds (the same conversation-as-input shape is waived for `devils-advocate`, where the parent packages the artifact) and decided it on cost/benefit instead. Practical outcome is identical. |
| `/planning:brainstorm` | NO-CHANGE | INLINE-ONLY on the step-4 reaction gate. Same practical outcome; NO-CHANGE is the more honest label because dispatch fails on cost/benefit before the gate is even reached. |
| `/architecture:improve` | INLINE-ONLY | Not a verdict alternative so much as a granularity objection: the whole-skill verdict hides that Phases 1–2 are dispatchable *conditional on nesting*. Recorded above as a phase-granularity finding. |
