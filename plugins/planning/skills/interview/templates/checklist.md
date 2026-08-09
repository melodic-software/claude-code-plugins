# /interview Checklist

Copy into `<memory_dir>/<topic-slug>/interview-checklist.md` (default `.work/`; the topic's memory slice). Tick as each step completes.

## Steps

- [ ] Step 1: Survey before you ask — read existing context, the topic's contract and memory slices, conversation history; identify what's already settled
- [ ] Step 1.5: Auto-detect (default action only) — if intent already crisp from survey, route to direct synthesis (skip Q&A loop)
- [ ] Step 2: Drive the frontier-rounds loop — each round asks every settled-prerequisite question as one numbered set in **inline prose** (`AskUserQuestion` only via the `use_ask_user_question` opt-in; `lock` synthesizes without Q&A); order rounds by blast radius; restate decided/open after each round
- [ ] Step 3: Recognize the stop condition — the open-question register grades clean (`check-open-questions.sh` exits 0; skipped only when the run asked no question at all and so wrote no register), the frontier is empty (every load-bearing unknown resolved or captured as a named assumption) AND user has confirmed the restated shared understanding (`me`/`auto`; `lock` is exempt — invoking it IS the confirmation)
- [ ] Step 4: Persist the contract — engineering: write the PLAN.md Brief section with goal + constraints + acceptance criteria + captured assumptions; general: write the shared-understanding summary, never a Brief (`me` mode: persist each answer incrementally as it locks in; flush before context overflows)
- [ ] Step 5: Hand off — engineering: recommend the next skill (exploration/research for engineering-internal; chain after `/prd` for product-driven); general: deliver the summary and stop, no pipeline handoff. Both: recommend model / effort / advisor per the live-doc-sourced session-config guidance (never a pinned model name) — engineering configures the **downstream execution session** it hands off to; general/terminal configures the **current/next session**, applied now (nothing downstream exists) — first surfaced early, post-survey, so it could shape the rounds themselves; here refresh it and, if raised only now, offer to re-evaluate the result under the raised config

## Open-question register

**Write a row the moment a round is ASKED — before any reply arrives.** The register is a byproduct of asking, not of resolving: a question that only lands on disk once it is answered cannot record the failure of never being answered. Statuses: `open` | `answered` | `deferred` | `withdrawn` | `blocked`. `Q<N>` matches the terminal numbering and runs continuously across rounds with no gaps.

```text
- Q1 | answered | round 1 | Who can write comments? | enrolled + instructor + admin
- Q2 | open | round 1 | What content format? |
- Q3 | deferred | round 2 | Moderation model? | post-V1 — also in the Brief's Deferred questions
```

Gate twice — a non-zero exit halts either time:

```bash
# Step 3, before locking the contract (the Brief is not written yet).
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" \
  --ledger <memory_dir>/<topic-slug>/interview-checklist.md

# Step 4, right after writing the Brief (engineering sessions only).
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" \
  --ledger <memory_dir>/<topic-slug>/interview-checklist.md \
  --brief <contract_dir>/<topic-slug>/PLAN.md
```

## Decision tree (`me` mode only)

Relentless `me` mode expands Step 2 into one checkbox per branch (not a single step box). Maintain in `interview-checklist.md`; tick on resolve; loop until zero open consequential branches:

- [ ] <branch 1> — <decision once resolved>
- [ ] <branch 2> (blocked by: <branch>)
- [ ] <branch N>

No question cap. If branches outgrow the session, hand off (save-point + resume prompt) → clear → resume from the first open box.

## Skip criteria

- Step 2 SKIPPED when Step 1.5 auto-detect routes to direct synthesis
- Step 1.5 SKIPPED when user explicit-mode (`lock` forces synthesis; `me` forces Q&A loop)
- Step 3 confirmation gate SKIPPED only for `lock` (invoking it IS the confirmation) — direct synthesis in `auto` still passes through it
- Step 3 **register** gate SKIPPED only when the run asked no question and wrote no register (`lock` synthesizing with no gap; `auto` routing to synthesize-directly with no open decision). Any question at all — asked, surfaced mid-synthesis, or blocked unattended — means a register exists and the gate applies. This is about the absence of questions, not about the action

## How to use

Copy at session start; tick boxes as steps complete; a resuming session reads the unticked boxes to know where to continue.
