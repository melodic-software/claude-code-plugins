# Interview loop — depth-first Q&A detail

Reference detail extracted from `SKILL.md`. Read on demand when running the `me` action (full Q&A loop), executing the auto-detect Q&A branch, or designing follow-up questions for an existing Brief.

## Step 1 — Survey before you ask

Spend the first turn grounding yourself. Do NOT ask anything you can answer from the repo. In parallel where possible:

- Read the project's `CLAUDE.md` and `AGENTS.md` if not already in context
- `Glob` and `Grep` for any keywords from `$ARGUMENTS` against the repo
- Look at `git log --oneline -20` for recent direction
- Climb to the nearest domain-vocabulary file (e.g. `UBIQUITOUS-LANGUAGE.md`) if the project keeps one and the topic touches a module
- List the project's own rules files that govern the area
- Note what the topic's contract slice `<contract_dir>/<topic-slug>/` (default `docs/topics/`) already contains (prior PLAN.md, PRD, design artifacts) and what its memory slice `<memory_dir>/<topic-slug>/` (default `.work/`) holds (exploration/research artifacts, ledgers)

Classify the domain from what the survey shows before anything Brief-related — the task/build surface decides, not cwd; a general decision raised from inside a code repo is still general. See SKILL.md Step 1 "Classify the domain".

**Engineering sessions only:** if a prior `PLAN.md` with a Brief section exists for this topic, read it first and ask whether to **resume** (continue from last open question), **revise** (task shifted, update specific sections in-place), or **start fresh** (append a dated scope-change note to the top of the Brief capturing why, then rewrite it; the commit carrying the rewrite states the pivot rationale — git log is the history). A general session never creates or edits a PLAN.md Brief, so it skips this prompt.

Survey output is a one-paragraph summary in your reply: "Here is what I see in the repo about this task." Then transition to Step 1.5 (auto-detect) or Step 2 (Q&A loop), per the action.

## Step 1.5 — Auto-detect: gap analysis without asking

When the action is `auto` (default), insert between Step 1 (Survey) and Step 2 (Q&A loop). Goal: skip Q&A when nothing is actually open.

**Synthesize directly when:**

- `$ARGUMENTS` includes goal + at least one constraint or criterion phrase
- Recent conversation has explicit goal + scope statement
- Prior PLAN.md Brief exists and user said "update with X" / "add Y to the brief"
- Trigger phrase observed: "lock", "write it", "spec this", "I'm clear", "just brief it"

**Force Q&A loop when:**

- Goal phrased as solution (no outcome stated)
- Acceptance criteria absent or fuzzy ("works correctly")
- Trigger observed: "interview me", "I'm not sure", "help me think", "fuzzy"
- 2+ unstated assumptions visible (scale, users, frequency, untouchable areas)

**Mixed (ask only the residue):** a single load-bearing unknown amid otherwise-clear intent → ask that one question, then synthesize the rest.

When `lock` is invoked explicitly, skip auto-detect and synthesize. If a true gap is detected during synthesis, STOP and surface: *"Found gap: <X>. Want me to ask, or capture as assumption with revisit trigger?"* — never fudge.

**Auto-guard:** synthesize-directly applies ONLY to codebase-resolvable answers or unambiguous conventional defaults. A decision genuinely the user's (real tradeoffs, no codebase answer) is never synthesized silently — ask it inline or offer `me` mode. See SKILL.md Step 1.5 "Auto-guard".

## Step 2 — Drive the decision tree

The decision space is a TREE, not a flat list. Decisions have dependencies — resolving one branch can eliminate or unlock entire subtrees. Traverse depth-first: pick a branch, resolve it completely, then backtrack to the next sibling.

### Per-round loop

Run rounds until the stop condition is met. Each round:

1. **Restate the working understanding** in two or three sentences — what is decided, what branches remain open
2. **Pick the most load-bearing BRANCH** — not just the highest-priority item, but the decision that blocks the most downstream decisions. Resolving "single-tenant vs multi-tenant" prunes entire subtrees (tenant isolation, data partitioning, tenant-scoped auth)
3. **Codebase gate** — before asking, check if code already answers the question (Grep, Read, Glob). If it does, STATE the finding and skip to the next question. Don't ask what code can tell you
4. **Ask ONE question with a recommended answer** — if the codebase gate didn't resolve it, ground the recommendation in observed codebase state. When no code signal exists, recommend based on conventions and state the basis
5. **Capture the answer** in the working draft of the Brief (in your head or a scratch buffer, NOT on disk yet)
6. **Prune the tree** — what branches did this answer eliminate? What new branches opened? What's the next blocking decision?
7. **Domain check** — when the task touches domain concepts, run the glossary challenge (probe terms used two ways or colliding with existing definitions) + scenario exploration (invented edge cases probing concept boundaries). **Engineering sessions only:** when a term resolves, invoke `/planning:domain-modeling` for the inline vocabulary update — a general session writes no repo docs (SKILL.md "Domain-aware behaviors")

### Decision dependencies

Track which open questions BLOCK other questions. When presenting remaining branches, name the dependency: "We can't decide the caching strategy until we resolve the read/write ratio question." This gives the user structural awareness of what their answer unlocks.

Branch pruning is the tree model's biggest win: resolving one high-level decision can eliminate 3-5 downstream questions entirely. Name what was pruned: "Since we're going single-tenant, we can skip tenant isolation, data partitioning, and tenant-scoped auth."

### Categorization

Each open item is one of:

- **Resolvable** — the user can answer it now. Ask with recommended answer
- **Blocked** — depends on another unresolved decision. Name the blocker
- **Defer-with-assumption** — the user can pick a working assumption, with a known revisit trigger. Capture the assumption and the trigger ("assume Postgres for now; revisit if write throughput exceeds X")
- **Defer-fully** — out of scope for this task; record in **Deferred questions** so it doesn't silently become a hidden assumption later

**In `me` mode**, "Defer-with-assumption" is NOT available for a *consequential* branch — drive it to a decision (which may be an explicit "defer to post-V1", recorded as a surfaced decision, not a silent assumption). Defer-with-assumption stays valid only for genuinely non-consequential items.

### Highest-value question shapes

Targets that catch the most rework downstream:

| Shape | Why it matters | Example (with recommended answer) |
|---|---|---|
| Goal phrased as solution | Locks implementation before problem is named | "If we ignore the implementation — what changes for the user? I'd guess: users can reset passwords via email, based on the `ForgotPassword` endpoint stub I found." |
| Acceptance criterion not testable | "Works correctly" is not a contract | "How would we know this is working? I'd suggest: `GET /api/users/me` returns 401 when session token missing — verifiable?" |
| Implicit constraint | Stack, timing, untouchable area | "Anything we should NOT touch? I see `LegacyAuthMiddleware` hasn't changed in 6 months — off limits?" |
| Unstated scale assumption | Drives architecture | "Roughly how many per day? Your current table has 12K rows — expecting 10x growth, or staying in that range?" |
| Domain term used two ways | Will collide later | "When you say 'Order', do you mean the cart or the placed-and-paid order? Your vocabulary file doesn't have this term yet." |
| Scope creep | One PR vs three | "Is X part of this task, or its own follow-up? I'd recommend splitting — X touches a different module." |
| NFRs missing | Functional vs non-functional unclear | "Beyond the feature — constraints on latency, reliability, cost? Your current p99 is 45ms per the middleware logs." |
| Domain boundary unclear | Concept overlap between contexts | "What happens when a Customer cancels half an Order? Partial cancellation or two separate ones? Let's probe the edge case." |

## Relentless `me` mode mechanics

`me` mode (SKILL.md Stance "Relentless mode") drives every consequential branch to a decision, inline, one question at a time. The mechanics below specialize the per-round loop above.

### Inline question format

ONE question per turn, prose, NOT `AskUserQuestion`. **Template: SKILL.md Stance "Relentless mode"** — single source; not duplicated here.

`Q<N>` is a running counter across the session (Q1, Q2, … — visible depth). Wait for the answer before the next question. The closing probe is load-bearing: it invites the user to surface a hidden constraint that would flip the recommendation. Most answers come back as a one-tap "correct" — that is the format working, not under-questioning.

### Dialogue + recommendation revision

The user drives too. When they push back or reframe a decision on a new axis — most often **reversibility** ("what's hardest to roll back from?") — re-rank the options on that axis and REVISE your recommendation out loud. Worked example: recommend one-level reply threading → user asks what's irreversible → re-rank by reversibility (flat→one-level trivial; one-level→nested easy; nested→simpler hard) → flip the recommendation to pure-flat as the most reversible V1 start. The flip is the dialogue working, not indecision.

### Reversibility lens (V1 default)

For V1 / ship-fast tasks, lead with the most *reversible* option and defer the irreversible/expensive as an explicit out-of-scope decision:

| Decision kind | Reversible later? | V1 pick |
|---|---|---|
| schema / data shape | hard once data exists | shape that adds columns later, not one that migrates meaning |
| scope (feature in/out) | easy to add | defer non-essential to post-V1 explicitly |
| UI surface | easy | simplest that ships |

### Decision-tree ledger

Maintain a live ledger of branches as checkboxes in `<memory_dir>/<topic-slug>/interview-checklist.md` (default `.work/`; the topic's memory slice):

```markdown
**Decision tree:**
- [x] who can read/write — enrolled + instructor + admin
- [x] threading — flat (most reversible)
- [ ] content format
- [ ] moderation (blocked by: admin-role scope)
```

Tick on resolve. Surface the open set periodically (every few questions, or on request) — not every turn, which would clutter the one-question flow. Loop until zero open *consequential* branches. No question cap.

### Incremental persistence + branch-out

- **Persist per lock-in.** The moment a branch resolves, write the answer to its ledger checkbox + the relevant Brief section. Overrides the per-round loop's "NOT on disk yet" — that applies to `auto`/`lock`, not `me`. Resolved branches must survive a crash / context clear / overflow.
- **Context-pressure flush.** If the conversation is getting heavy, force-flush the ledger + partial Brief to disk and offer a handoff (`/session-flow:handoff` if installed, otherwise a resume note) before continuing.
- **Branch out to ground a recommendation.** If a question needs more than the lightweight codebase gate — external best-practice, library API surface, deeper exploration — pause, run the research/exploration capability (or do the lookup inline), then return with a recommendation grounded in code read this session or an official source fetched this session. Never recommend a load-bearing technical choice from training recall.
- **Handoff for long sessions.** If branches outgrow one session, hand off (save-point + resume prompt) → clear → resume from the first open ledger checkbox.

## Step 3 — Recognize the stop condition

Stop when ALL hold:

- Every load-bearing unknown is **resolved** or **explicitly captured as a named assumption** with a revisit trigger
- The user can describe the goal in one paragraph without contradicting the constraints or acceptance criteria
- Acceptance criteria are testable — each points at a check, observation, or measurement
- The user signals readiness ("good, write it", "that's the task", or simply stops adding)

Do NOT stop early because the user gets impatient. If a real load-bearing unknown remains, name it ("one open item: X — willing to ship as an assumption?") and let them choose. Do NOT keep asking past the stop condition — that is its own anti-pattern.

**`me` mode:** the stop condition is an empty decision-tree ledger (every consequential branch decided) plus user readiness — never a question count.

## Step 4 — Section guidance for the Brief

Each section in the PLAN.md Brief captures a specific shape. Keep tight.

**Goal** — one paragraph. What success looks like in plain language. Describe the OUTCOME, not the implementation:

- ✅ "Users can reset their password via email" (outcome)
- ❌ "Add PasswordResetHandler with IDispatcher" (implementation)

**Constraints** — bullet list. What the solution must respect OR avoid. Sub-categories worth probing:

- **Non-goals** — explicitly out of scope (often surfaces during interview)
- **Untouchable code/areas** — don't modify X, don't break Y
- **Performance / API contracts** — e.g. "must stay under 200ms p99", "must not break existing webhook clients"
- **Ecosystem / stack constraints** — e.g. "no new languages", "no new mapping library"
- **Timeline constraints** — e.g. "must ship before mobile release freeze"

**Acceptance criteria** — bullet list. How to verify done. Each criterion must map to a test or verifiable observation:

- ✅ "`GET /api/users/me` returns 401 when the session token is missing" (testable)
- ❌ "Authentication works correctly" (fuzzy)

**Captured assumptions** — what was deferred-with-assumption. Each captures the assumption AND the trigger forcing a revisit. The load-bearing innovation: what would otherwise be silent becomes explicit, and `/devils-advocate` and `/planning:plan` can attack it later.

**Out-of-scope** — things raised during the interview and explicitly excluded. Distinct from non-goals (constraints up-front); these surfaced in conversation.

**Deferred questions** — questions deferred-fully. Out of scope for this task but recorded so they don't silently become hidden assumptions.

### Brief template (the literal shape)

Write this into `<contract_dir>/<topic-slug>/PLAN.md` (default `docs/topics/`; the topic's contract slice, joining the memory slice under `contract_tier: local`). `/interview` writes only `## Brief` and leaves `## Plan` empty for `/planning:plan`.

```markdown
## Brief

### TLDR
<≤5 bullets — what's shipping. Load-bearing scope-review surface for dense briefs (>100 lines). A reviewer reading ONLY TLDR + Goal must know scope. If the summary grows beyond 5 bullets, the brief is too sprawling — surface back to the user and ask which items to defer>

### Goal
<one paragraph — outcome, not implementation>

### Constraints
- <untouchable code, deadline, contract, stack, performance budget>

### Acceptance criteria
- <testable criterion>

### Captured assumptions
- <assumption> — revisit if <trigger>

### Out-of-scope
- <thing the user raised and explicitly excluded>

### Deferred questions
- <question> — defer until <when>; **arbiter: /planning:plan** (default — /planning:plan resolves unilaterally during planning) OR **arbiter: USER-RESERVED** (user must re-confirm at /planning:plan approval gate; /planning:plan proposes, user resolves)

## Plan
<empty — populated by /planning:plan>
```

**Arbiter tag is load-bearing.** Default `/planning:plan` is fine for execution-shape decisions (orchestration shape, agent rosters, phase nesting) within already-approved scope. Use `USER-RESERVED` for any deferred question whose resolution could change the brief's acceptance criteria, out-of-scope list, or constraints. When in doubt, mark `USER-RESERVED` and let `/planning:plan` surface it at approval time.
