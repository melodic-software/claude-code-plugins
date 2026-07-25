# D9 — Closing the 32 unverified INLINE-ONLY rows

D8 upheld 32 of its 57 rows **without opening the files** — inherited from batch rationale, not read.
This pass opens all 32 and judges each from primary text, under the same inverted burden:
**preserving the MAIN agent's context is the primary goal; INLINE-ONLY is the claim needing
justification.**

The four ratified rules are applied throughout:

- A start-of-run question is **pre-dispatch parent work**, not a blocker (parent asks, fixes the
  answer, passes it in). Only a question whose existence or content depends on what the run *finds*
  — or whose answer IS the deliverable — blocks.
- Dispatch satisfies producer ≠ critic **by construction**; a mandated fresh-context verifier is not
  a blocker.
- A skill mandating a fresh-context step it cannot spawn is not blocked; it emits a verification
  request and the orchestrator dispatches a sibling verifier.
- `disable-model-invocation: true` blocks the preload and Skill-tool paths but is **not** a reason a
  skill should stay inline.

---

## 1. Coverage — script-verified, and one thing changed underneath this pass

**32 of 32 SKILL.md files opened and read in full.** No targeted reads, no inherited rows.

| Tier | Count |
|---|---|
| Opened, full read | **32** |
| Opened, targeted read | 0 |
| Not opened | **0** |
| **Total** | **32** |

**What the script verifies, precisely** — stated this way because a true claim resting on a
verification that does not reach it is the exact defect C1 corrected in this artifact's own history:

- The 32-row set was **derived** by script as `INLINE-ONLY(57) − D8's opened(25)` via set
  difference, not hand-listed — and the complement check (opened-25 ⊄ the 57) returned empty.
- Each of the 32 **resolves** to a `plugins/<plugin>/skills/<skill>/SKILL.md` that exists and is
  readable: 32/32.
- The corpus totals **4,970 SKILL.md lines**, which is why every file could be read whole rather
  than sampled.

The script does **not** establish that the files were opened. That evidence is 32 `Read` calls on
the 32 resolved paths, made in this pass — asserted as such, not laundered through a script that
measures something else.

### 1.1 The checklist was mutated mid-pass — the 32 are unaffected, but they are now a bigger share

Between this pass's first read and its second, `LEDGER.md` was rewritten by
another agent (mtime 17:24): **D8's Group A plus the three held flips have been applied.**
INLINE-ONLY is now **42**, not 57.

Scripted diff of the 15 changed rows — every one falls inside D8's opened-25, and **none is in my
32**:

`claude-ops:plugins` · `code-tidying:tidy` · `discovery:blindspot` · `disk-hygiene:clean` ·
`docs-hygiene:compress` · `docs-hygiene:rename-references` · `event-storming:simulation` ·
`github:advise` · `planning:wayfind` · `re-anchor:point-dont-copy` · `re-anchor:reuse-or-replace` ·
`repo-hygiene:clean` · `source-control:pull-request` · `source-control:worktree` (→ DISPATCH-OPTIONAL)
· `review:quality-gate` (→ DISPATCH-DEFAULT).

All 32 of my rows were re-checked against the **current** file and all 32 are still INLINE-ONLY. The
consequence is that this pass now covers **32 of the 42 remaining INLINE-ONLY rows — 76%**, up from
56% of the original 57. The unverified fraction of the surviving INLINE-ONLY population was larger
than the "32 of 57" framing implied.

### 1.2 Finding against the artifact — B09's ten rows sit in no normalization bucket

The checklist's normalization section assigns every batch to a bucket: applied-natively
(B02, B07, B10, B11), renorm row-tested (B01, B04, B05), summary-level only (B06), never-tested-then-
renormed (B03, B08). Summing its own scripted per-batch INLINE-ONLY counts against those buckets:

```
applied-natively    B02,B07,B10,B11 = 11
renorm row-tested   B01,B04,B05     = 13
summary-level only  B06             =  8
never-tested→renorm B03,B08         = 15
                          accounted = 47 of 57
        UNACCOUNTED BATCHES: ['B09'] = 10
```

**B09's 10 INLINE-ONLY rows appear in none of the four buckets.** Eight of them are in my 32
(`review:fanout` plus all seven `session-flow` rows); the other two (`repo-hygiene:clean`,
`review:quality-gate`) were in D8's 25 and have since flipped. This is a real bookkeeping gap in the
coverage claim and should be recorded.

**The honest counterweight, from actually reading them:** the exposure is low. B09's rationales
independently reason in the *amended* criteria's terms — they cite `history-fork` by name, invoke its
cost-inversion clause, and weigh degrade-to-stop (`clean-stop`: "a skill whose failure mode is 'do
nothing before the disk disappears' cannot take a posture that can silently decline to run";
`continue-in-background`: "it fires precisely when context is heavy … so dispatch cost exceeds
dispatch benefit by construction"). B09 was never *credited* with normalization, but its rows read as
though it applied it. **The checklist itself supplies the corroboration**: its transcription note
records "`/session-flow:orient`, which B09 revised to DISPATCH-OPTIONAL / `history-fork` **after the
criteria amendment**" — direct evidence that B09 was worked post-amendment even though no bucket
credits it. The gap is in the ledger, not in the reasoning.

### 1.3 Where the seam actually was

D8 predicted the unopened 32 would be thin on its read-only-sibling-action seam and thick with
dropped-tool and session-state blockers. **That prediction largely held, and reading confirmed the
three action-router hits it named.** But D8's own confidence statement did not cover the second form
of the same defect — the *phase* split it proved on `point-dont-copy` and `reuse-or-replace`, which no
action-router grep can see. Testing that form across the seven unopened `re-anchor` correctors is
where this pass found its strongest challenge, and where it also found six clean confirms.

---

## 2. Verdicts

**3 challenged · 29 upheld.** A fourth challenge (`debugging:debug`) was drafted and **withdrawn**
after checking PLAN.md — see the withdrawal note in §3. Of the 29 upheld, **5 carry a stated reason
that is wrong, void, or mis-ordered** under the ratified rules, and **2 gain phase-level carve-outs**.

Blocker map across all 32 (scripted token scan, then confirmed by reading — prose mentions
discarded): real `Workflow` dependence in 2 rows, `Task*` in 4, `ScheduleWakeup` in 1, plan-mode
transition in 1. The seven `re-anchor` correctors carry **zero** hard-blocker tokens — their blockers
are structural, not tool-shaped.

---

## 3. Challenges

### C1. `/re-anchor:reason-dont-recite` — INLINE-ONLY → DISPATCH-OPTIONAL (audit sweep)

**The strongest challenge in the set, because it is a ratified-precedent consistency failure.**

- **Dispatchable phase:** the audit sweep over inherited repo content. The re-anchor (step 1) and the
  correct-forward (step 3) stay inline.
- **Evidence:** the skill defines its subject as artifact-located, not transcript-located —
  "Inherited content — **a repo's docs, conventions, structure, processes**". Its audit signals
  require reading the repo to answer them: "a convention followed while **nobody can say what it is
  for**" and "inherited structure treated as a hard constraint when it is only the current state"
  are answerable only by sweeping the conventions and checking whether a rationale was ever recorded.
- **Why the stated reason does not reach it:** B08 gives one leg only — "**transcript-bound audit.**
  Findings are session-located justifications … which live in reasoning the model emitted this
  session, **not in files a fresh agent could read**." That last clause is contradicted by the
  skill's own definition of its subject.
- **The consistency argument:** `re-anchor:reuse-or-replace` was justified on
  "**main-context salience + transcript-bound audit**" — strictly *more* justification than this row
  — and has now been flipped to DISPATCH-OPTIONAL and applied. `point-dont-copy` likewise. This row's
  sweep is the same shape ("a divergence whose rationale was never recorded in the repo's ADR/docs
  convention" ↔ "a convention followed while nobody can say what it is for"), with a weaker stated
  justification, and it survived. Same plugin, same blocker shape, opposite verdict.
- **Pollution avoided:** a conventions-and-ADR sweep across the repo's doc corpus, plus the inherited
  structure it interrogates. The skill's stated conversation-start trigger is "legacy or inherited
  code", so the corpus is the point. Output: a handful of located findings.
- **Split shape:** subagent returns located precedent-only-justified decisions; the parent re-anchors
  and re-derives. Identical to the split already ratified for its two siblings.

**The discriminator against the six confirmed correctors — whose artifacts.** This challenge is not
"the audit touches files, therefore dispatch"; `mind-your-maxims` and `tighten-your-output` also
audit artifacts and are upheld in §4. The dividing line is whether **enumerating the target set
requires the transcript**. `mind-your-maxims` audits "agent-authored ARTIFACTS — docs, PR bodies,
prompts, commit messages" — but only those *this session produced*, and nothing but the transcript
says which those are. `tighten-your-output` is the same. `reason-dont-recite` audits the repo's
**inherited** content, which exists independent of the session and is enumerable by a fresh agent
handed a scope. That is why one flips and the other six do not.

### C2. `/planning:brainstorm` — INLINE-ONLY → DISPATCH-OPTIONAL (steps 2–3)

- **Dispatchable phase:** step 2 (Ground) + step 3 (Diverge), entire.
- **Evidence:** step 2 is a "fast breadth pass (`Glob`/`Grep`/targeted Read — survey the file
  landscape before reading anything in depth) over where the problem lives: entry points, existing
  mechanisms that already partially address it, prior art in the repo." Step 3 produces "the candidate
  list (default ~10 …) … Every candidate is **codebase-grounded** — names the files/mechanisms it
  would touch — **one line each**."
- **Why the blockers do not reach it:** B06 names two. Step 1's "ask ONE question to establish where
  they are" is a **start-of-run question** — the parent can answer "where is the user starting from"
  without reading a single file the skill reads, so it is a parameter under the ratified rule. Step
  4's "the user marks what resonates" is a genuine mid-flow gate — but it sits *after* the subagent
  has already returned, so it is parent-side by construction and costs the split nothing.
- **Pollution avoided:** an unbounded `Glob`/`Grep`/Read survey of "where the problem lives" across
  an unfamiliar area. Output: ~10 one-line candidates. Bulky input, terse output — the highest-value
  dispatch profile there is.
- **B06 named this exact slice and declined to act on it** — "Steps 2–3 (ground + diverge) are a
  **clean splittable phase**". That is the same posture B02 took on `code-tidying:tidy`'s `dry-run`,
  which has since been flipped and applied. Under the inverted burden the slice is wanted.

### C3. `/planning:questionnaire` — INLINE-ONLY → **NO-CHANGE** (wrong cell; no dispatch win)

A correction in the opposite direction, in the spirit of D8 §5.2. This does not move work off the
main thread — it removes an INLINE-ONLY row that no longer has a blocker to stand on.

- **Why the cell is wrong:** the criteria define INLINE-ONLY as "must stay in main context.
  **Justified only by a hard blocker, named explicitly.**" B06 gives three legs and the ratified
  rules void or defease all of them:
  1. "**`disable-model-invocation: true`** (frontmatter L6) — noted explicitly" → ratified rule 4:
     not a reason to stay inline.
  2. "steps 1 and 2 are both user exchanges" → both are start-of-run questions about **the send**,
     never the subject: "Who is it going to?" (recipient's role, expertise, relationship) and "What do
     you need back?". The skill's own stance is "**Interview the send, not the subject** … Interview
     the user only about the *send*, **which they can always answer**." Neither requires reading a
     file the skill reads. Both are parameters.
  3. "the artifact is one small templated document; **the split does not pay**" → a cost argument,
     and a correct one. But a cost argument supports NO-CHANGE, not INLINE-ONLY.
- **Nothing to reclaim:** the skill reads one 35-line template and writes one document. No sweep, no
  fetch, no repo walk. It is short and conversational — the criteria's own NO-CHANGE definition.
- **Net effect:** INLINE-ONLY −1, NO-CHANGE +1. No dispatch value; recorded so the ledger's
  INLINE-ONLY population means what it claims.

### Withdrawn: `/debugging:debug` — tested as a challenge, **upheld**

This pass drafted `debug` as a fourth challenge on the ground that B02's blocker — "the six-phase
loop is an iterative build/test/fix cycle … driven turn by turn", cited to *PLAN Decision 1's*
"tight turn-by-turn iteration" — was sourced **outside** the criteria's enumerated hard-blocker
list. **Opening PLAN.md refuted that.** Decision 1 reads: "`/research` and `/explore` **dispatch a
subagent by default**, with a documented inline escape hatch **for tight turn-by-turn iteration**."
The criteria section explicitly binds every verdict to "the decisions locked in PLAN.md", so B02's
reason is criteria-sourced after all. The challenge is withdrawn and the row is upheld in §4.7.

Recorded because the claim was asserted before it was checked; the check reversed it.

---

## 4. Upheld — 28 rows, blockers in the criteria's own terms

Grouped by blocker class. Every one was read in full this pass.

### 4.1 Deliverable IS the invoking context's own state (5)

The cleanest non-interaction blocker class in the set, and the one the inverted burden survives most
convincingly: dispatching arms the *child's* context and returns nothing to the one context that
needed arming.

- **`/session-flow:orchestrate`** — "Invoking this skill **arms the current session** … Do NOT
  re-emit the imperatives — **loading them IS the priming**." The "Priming addendum (current session
  only)" confirms the boundary: the main session reaches agent teams and dynamic workflows "a
  spawned worker cannot". Export modes emit fixed text — nothing to reclaim. *Stated reason correct.*
- **`/playbooks:fable-5`** — "this playbook is now part of **your standing instructions** … active
  for the rest of the session", with a chapter-routing table firing triggers across the whole
  session. `full` mode's 1,363 context lines are deliberate parent-window flooding, not a payload to
  relocate. *Stated reason correct.*
- **`/re-anchor:do-your-research`**, **`/re-anchor:script-the-deterministic-work`**,
  **`/re-anchor:tighten-your-output`** — the shared method doc is dispositive for all three: step 2
  is "**Walk back over the conversation**", and a corrector exists to "re-inject the discipline
  **near the context tail**" of the session that drifted. Their audit signals are located purely in
  the model's own emitted turns (a hand-tallied count; arithmetic worked through mid-answer; prose
  already padded). `history-fork` is the only mechanism that carries the transcript, and the criteria's
  cost-inversion clause counter-indicates it precisely here: a corrector fires *because* the session
  is long. Two of the three also route their bulk out by contract — `do-your-research` escalates to
  `do-your-research-deep` (already NO-CHANGE/dispatching), `tighten-your-output` routes batch work to
  `docs-hygiene:compress` and `code-tidying:batch-simplify`. *Stated reasons correct.*

### 4.2 Harness tools dropped in a subagent (6)

- **`/discovery:research-deep`** — states it itself: "**It must run in main context to reach the
  Workflow tool** when one is available (a subagent cannot dispatch workflows)." It *is* the
  dispatcher; dispatching it is a category error. *Stated reason correct.*
- **`/session-flow:workflow`** — step 4 tracks stages "via `TaskCreate`"; position detection reads
  "conversation context for evidence of completed stages"; the deliverable is an in-conversation next-
  stage recommendation. *Correct.*
- **`/work-items:work-loop`** — "**`ScheduleWakeup`**" at every non-exiting cycle end, dropped
  everywhere. It also flags the sibling terminal explicitly: the orchestrator never invokes
  `/source-control:worktree create`, "whose `EnterWorktree` terminal would transition the calling
  session, **acutely relevant to this long-lived loop session**". Its item volume is already offloaded
  via `/work-items:work` → `implement-dispatch`. *Correct.*
- **`/code-tidying:batch-simplify`** — `TaskCreate` (phase 5) and `TaskUpdate` ×2 (phase 6) are the
  per-group wave-tracking contract, plus its own per-group `Agent` fan-out. **It is already an
  orchestrator**: main context holds only per-group summaries and deferred lists, so the context win
  the inverted burden chases is already banked. *Correct.*
- **`/session-flow:reconcile`** and **`/session-flow:keep-going`** — both reconcile *this session's*
  task ledger through `TaskList`/`TaskGet`/`TaskUpdate` and act on off-thread work this session
  spawned. `reconcile` names the containment: "**harness control reaches only this session's own
  work**". `keep-going` additionally puts the main task back in motion (step 4). *Correct.*

### 4.3 Live user mid-flow, or the answer IS the deliverable (7)

- **`/work-items:attend-queue`** — "runs **attended by definition**"; the operator's judgment IS the
  product (answers written back as issue comments, C3 ratifications, label flips). *Correct.*
- **`/planning:interview`** — the frontier-rounds loop with a confirmation gate; "the decisions are
  the user's — put each one to them and wait." Notably it **already dispatches its heavy half** by
  contract: "When a fact lookup is slow (deep exploration, external research), **dispatch it to a
  sub-agent** and DON'T block the round." *Correct.*
- **`/planning:plan`** — step 5 is the terminal human approval gate ("The approval gate is the point
  — it's where human judgment enters the loop"), and the Step 1 "Open Decisions" round plus the Step
  4.6 confidence gate are questions **whose content depends on what the run finds and which steer the
  run** — the exact form the ratified rule preserves as blocking.
  **Stated-reason note (two of B06's three legs are defeased).** B06 gives the approval gate
  (sound), then "`AskUserQuestion` appears four times as the round surface" — the rejected
  tool-shaped form, and weaker still because every one of those four sites is gated on a
  `use_ask_user_question` config that defaults **off**, falling back to inline prose. Its "**Second
  blocker:** the skill must itself spawn subagents at Step 3 (MANDATORY plan-reviewer) and Step 4
  (devils-advocate)" is defeased by **ratified rule 2** — a mandated fresh-context verifier is not a
  blocker; record the recursion instead. The approval gate carries the verdict alone.
- **`/education:teach`** — "Ask ONE question at a time / **Wait for the answer (silence = wait, not
  assume)**" across a multi-session mission interview and ZPD scaffolding; the user's understanding
  is the deliverable. **See §5 for a stated-reason correction and a new sub-action carve-out.**
- **`/naming:name-it-better`** — two independent blockers: the terminal "**Human picks.** Stop and
  let the user choose" (answer IS the deliverable), and its own blind `Agent` fan-out as an
  anti-anchoring correctness control whose reject list is deliberately "carried by the **main
  thread** … never shared with the generators". Dispatching would either leak the reject list into
  the brief — defeating the blinding — or lose it. *Correct, and the skill is the right shape already.*
- **`/adhd:clarify`** — the anaphora default targets "the **previous assistant response**", re-read
  "this turn, in full"; the output IS the conversational response or an in-session Artifact publish.
  *Correct.*
- **`/implementation:implement`** — `TaskCreate`/`TaskUpdate` (step 4) and the plan-mode transition
  (step 3: "switch to plan mode … Exit plan mode only after the revised plan is clear") are each
  independently dispositive. **See §5 for a stated-reason re-ordering.**

### 4.4 Audit input is the live transcript or session-scoped listing (4)

- **`/re-anchor:use-your-skills`** — the strongest doc-cited confirm in the set. The skill states the
  disqualifying harness fact itself: "A fresh non-fork subagent does **not** inherit your skill
  listing." A dispatched auditor would audit a *different* listing than the one that drifted. *Correct.*
- **`/re-anchor:mind-your-maxims`** — the audit target is what was said to this user; B08's
  observation is sharp and holds on reading: "a summarized transcript would be exactly the artifact
  whose shaping is under audit." *Correct.*
- **`/re-anchor:pick-for-the-problem`** — findings are located in the session's own choices, and its
  heavy half is already routed outward by contract: "**Mandatory routing — no verdict from memory** …
  Route to `/discovery:research`, or `/discovery:research-deep`", both of which this sweep dispatches.
  Nothing left to reclaim. *Correct.*
- **`/visualization:visualize`** — step 1 is "Read **where the conversation stands**". **See §5 for a
  stated-reason correction.** Volume is below any reasonable cost threshold: 169 sidecar lines, no
  file sweep.

### 4.5 Own Agent fan-out / is itself the dispatcher (3)

- **`/review:fanout`** — states the blocker in its own text: the three orchestrator plugins "**All
  run on the MAIN THREAD** (they fan out their own agents; a subagent cannot dependably do that)",
  on top of its own leaf fan-out. Recursion recorded. It is itself the dispatcher — the context
  saving already happens at its leaves, and it persists findings to disk. *Correct — and notably
  well-reasoned given §1.2's provenance gap.*
- **`/implementation:implement-dispatch`** — it *is* the orchestration mechanism; dispatching it adds
  a third level to an already two-deep tree (orchestrator → workers → fresh-context verifier),
  requiring `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, which Decision 3 keeps optional. It also names
  `EnterWorktree` as a terminal it deliberately avoids invoking. **On the flagged NO-CHANGE-vs-
  INLINE-ONLY ambiguity: settled from primary text as a practical no-op** — the skill already
  embodies the posture this sweep proposes, so either cell produces identical downstream work. B05's
  instinct to flag rather than pick was right; the ratification is cosmetic.
- **`/session-flow:clean-stop`** — session-scoped subject ("every repository and worktree **this
  session touched**") driving irreversible outward writes it performs *without asking* (push,
  `gh pr create`, issue filing). B09's degrade-to-stop argument is the decisive one and survives the
  inverted burden intact: a loss-prevention contract cannot adopt a mechanism that can silently
  decline to run. *Correct.*

### 4.6 Cost threshold — no blocker beyond volume (3)

Listed to show the read-only-action pattern was applied with a threshold, not mechanically.

- **`/claude-memory:stateless`** — `purge` is a confirm-gated destructive delete and `disable` edits
  settings after a scope confirm. The read-only `status` sibling carries **no** blocker, but is
  already served by the `!`-precomputed `scope-report.sh` snapshot in the SKILL.md header — the data
  is in context before any dispatch decision exists, so there is nothing to reclaim. *One of D8's
  three predictor hits; reading confirms D8's call.*
- **`/session-flow:handoff`** — the save-point IS the conversation, and its triggers ("context
  heavy", "quality degrading") are exactly when `history-fork` costs most, while its own work is one
  file write plus a rails prompt. It also snapshots `TaskList`. Dispatch cost exceeds benefit by
  construction. *Correct.*
- **`/session-flow:continue-in-background`** — same engine, plus a terminal that must move the
  invoker's own session ("**this session terminates the task**") and a hard gate requiring explicit
  user intent to launch. *Correct.*

### 4.7 Covered by a named PLAN decision (1)

- **`/debugging:debug`** — upheld. B02 clears the two obvious candidates itself (phase 3's user
  checkpoint is "**not** a blocker — 'Do not block on it — proceed with your ranking if the user is
  AFK'"; the HITL script is "strategy #10 'last resort' … not the contract") and rests on
  **PLAN Decision 1's documented inline escape hatch for tight turn-by-turn iteration**, which
  covers phases 4–6. *Stated reason correct and criteria-sourced.*

  **Phase-level finding, recorded not applied.** Phases 1–3 carry no blocker and are read-heavy:
  phase 3 grounds its ranking in "recent commits in the affected area, open issues, architecture
  decision records, banned-symbol entries, known-issue / quirks notes" plus a "**walk up from the
  affected file to the repository root**" reading the closest `CLAUDE.md` / `AGENTS.md` /
  ubiquitous-language / ADRs; the product is "**3-5 ranked hypotheses**" plus a repro loop that is a
  durable on-disk artifact. **Decision 13 ("revises Decision 1") makes the dispatch unit a phase and
  the whole-skill verdict a roll-up**, so this belongs as a phase-level note — but Decision 13's two
  sanctioned declaration shapes (an execution-site column on an action-router table, or per-step
  annotation plus a handoff contract) are **both absent** here: `debug` has no action router and no
  declared `diagnose` lane. Routing it would mean *authoring* a new lane, which is a plan-step
  proposal, not a verdict correction. That is precisely what separates it from `code-tidying:tidy`,
  whose `dry-run` was an already-declared read-only action and flipped cleanly.

---

## 5. Stated reasons that are wrong, void, or mis-ordered (verdict right)

Reported so the justifications get repaired, not the verdicts flipped. All four rest on the ratified
rules.

1. **`/education:teach`** — B04 offers "`disable-model-invocation: true` **independently blocks**
   `skills:` preload" as a co-equal blocker. **Ratified rule 4 voids that leg**: the flag is a
   configuration choice in a marketplace file the user owns, not a capability limit, and the
   checklist's own criteria make runtime `Skill` invocation the fleet default anyway. The
   interactive-coaching leg carries the verdict alone. Strike the flag leg.
2. **`/visualization:visualize`** — B09's first leg is that step 4 "needs `AskUserQuestion`,
   unavailable in every subagent." That is **the exact tool-shaped form the criteria reject** ("name
   the blocker as the absence of a USER, never as the absence of `AskUserQuestion`"), and it is
   doubly weak here because step 4 is conditional by design — "**Ask only on genuine ambiguity** …
   When neither is ambiguous … proceed with the matrix's pick: good defaults, no nagging." The
   conversation-scoped target inference in step 1 is the real and sufficient blocker. Strike leg one,
   promote leg two.
3. **`/implementation:implement`** — B05 **leads** with "Step 3.5 mandates `AskUserQuestion`" (the
   rejected form) and relegates the two dispositive blockers — `TaskCreate` and the plan-mode
   transition — to "two more". Re-order: the dropped-tool legs are dispositive on their own and
   survive every criteria amendment; the `AskUserQuestion` leg is defeasible and should be restated
   as a mid-flow scope-expansion gate if kept at all.
4. **`/implementation:implement-dispatch`** — same `AskUserQuestion` leg inherited from
   `implement`'s Step 3.5. The durable blocker is the nesting depth plus its identity as the
   dispatcher.
5. **`/planning:plan`** — two of B06's three legs fall to the ratified rules (the four
   `AskUserQuestion` sites, all gated on a config defaulting off; and the Step 3/4 mandated
   fresh-context spawns, defeased by rule 2). Detail in §4.3. The Step 5 approval gate is
   dispositive alone and needs no support.

**Two phase-level carve-outs**, to be added alongside the checklist's existing four
(`event-storming:simulation --discover-bcs`, `firecrawl:update --check`, `kindle-dedrm:manage
update`, and `event-storming:methodology --<format>`, which D8 recommends striking):

- **`/education:teach` — Codebase Mode steps 1–3.** "Read the repo's own guidance … climb for the
  nearest `CLAUDE.md`/`AGENTS.md`, `README.md`, `docs/`, ADRs, convention/rules files" → "**Survey
  the structure**" across manifests and layout → "**Persist what you discover** into the workspace
  `RESOURCES.md` … **infer once, persist, reuse**." That is an explore-grade repo sweep whose product
  is a persisted file the skill explicitly designs to be computed once and reused — a clean
  pointer-returning slice. It does not move the whole-skill verdict; the teaching dialogue is still
  a live-user contract.
- **`/debugging:debug` — phases 1–3 (a `diagnose` lane).** Read-heavy, no blocker, product is a
  ranked hypothesis list plus a durable repro loop. Unlike the four existing carve-outs and unlike
  `education:teach` above, this lane **is not declared anywhere in the skill** — routing it means
  authoring a new action, so it is a plan-step proposal rather than a ledger correction. Full
  reasoning in §4.7.

---

## 6. Summary

**3 challenged · 29 upheld · 32 of 32 opened and read in full.**

| | Rows |
|---|---|
| **Challenged** | `re-anchor:reason-dont-recite` · `planning:brainstorm` · `planning:questionnaire` (cell only) |
| **Withdrawn after checking PLAN.md** | `debugging:debug` |
| **Upheld, stated reason correct** | 24 |
| **Upheld, stated reason repaired** | `education:teach` · `visualization:visualize` · `implementation:implement` · `implementation:implement-dispatch` · `planning:plan` |

Two of the three challenges move real work off the main thread (`reason-dont-recite`,
`brainstorm`); the third (`questionnaire`) is a cell correction with no dispatch value.

Distribution effect on the **current** (post-mutation) ledger, if all three are adopted:

| | DISPATCH-DEFAULT | DISPATCH-OPTIONAL | INLINE-ONLY | NO-CHANGE | Total |
|---|---|---|---|---|---|
| Today (post-D8-application) | 22 | 42 | 42 | 32 | 138 |
| + D9's three | 22 | 44 | 39 | 33 | 138 |

(Current row recomputed by script off the live checklist, not carried from D8's projection.)

Against the artifact: **one coverage-accounting gap** — B09's 10 INLINE-ONLY rows sit in no
normalization bucket (§1.2), verified arithmetically against the checklist's own per-batch counts,
with the mitigating finding that those rows independently applied the amended criteria anyway.

One item surfaced rather than resolved: `playbooks:fable-5`'s core doctrine encodes a **competing
delegation rule** — "Delegate only on genuine fan-out (5+ independent items), context-flooding side
work, or isolation-as-the-product. The stay-inline conditions override all three — except the
fresh-context verifier, which they never displace." Its context-flooding trigger agrees with this
sweep's premise, but its 5+-item fan-out floor is stricter than the checklist's DISPATCH-DEFAULT
signals. This corroborates the checklist's existing open item on `context/orchestration.md` and
extends it: the conflict is in the SKILL.md body too, not only the chapter.
