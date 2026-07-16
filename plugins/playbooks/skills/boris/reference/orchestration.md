# Orchestration & Frontier Models — Sections 78–95

Tips from Boris Cherny's Parts 13–15 threads + the Thariq/Sid workflows deep-dive + the Boris/Cat interview (May 28 – Jun 10, 2026): Opus 4.8 launch, dynamic workflows, auto-mode-retired-plan-mode, context minimalism, nested subagents, `fork: true`, Fable 5.

## 78. Opus 4.8 — Strongest Coding Model Yet

Shipped May 28, 2026. SWE-Bench Pro 64.3 → 69.2; Terminal-Bench 2.1 66.1 → 74.6. Same price as 4.7. The bigger shift is honesty: it tells you when it's unsure and catches its own bugs instead of declaring victory early — a model that overclaims at step 4 wastes the next 40 steps, so honesty is what makes async work (`/goal`, workflows) actually finish. Also shipped: Fast mode for Opus 4.8 (research preview, ~2.5× speed, toggle `/fast`) and effort control on claude.ai.

> **Superseded (Jun 9, 2026):** Fable 5 is now the strongest coding model (Section 94). Opus 4.8 details remain accurate for that release.

## 79. High-Effort Default + xhigh + Raised Rate Limits

Opus 4.8 moved the default effort UP — the old deliberate `xhigh` choice is closer to baseline. Reach for `/effort xhigh` for hard problems, async runs, and dynamic workflows; short conversational tasks don't need it. Rate limits were raised alongside the launch to cover the extra reasoning tokens.

## 80. Dynamic Workflows — Days or Weeks Instead of Quarters

Research preview (May 28, 2026) for tasks too big for one pass. Trigger: say **"use a workflow"** (refined Jun 9 — bare "workflow" had too many false positives, Section 93). Orchestrator shape, not peer-to-peer agent teams: a top-level Claude kicks off N tasks (100s possible); each task fans out implementer → two verifiers → fixer, looping until verifiers pass. Save it for the biggest jobs — migrations, refactors, perf optimization, batch bug fixes, catalogue-and-categorize sweeps. Token-intensive; don't burn it on a 20-line tweak. Auto mode is not optional — one permission prompt freezes a hundred-agent run. Cat Wu's example: catalogued 100s of A/B flags for stale rollouts in <10 minutes via parallel investigation.

## 81. Why Workflows — Three Failure Modes They Fix

From Thariq Shihipar + Sid Bidasaria (the engineers who built them): the default harness plans AND executes in one context window, and long single-window work develops (1) **agentic laziness** — declaring done after partial progress; (2) **self-preferential bias** — preferring its own results when judging; (3) **goal drift** — lossy compaction quietly drops "don't do X" constraints. A workflow orchestrates separate Claudes, each with its own context window and one focused goal: laziness loses to a deterministic loop, bias loses to a different judge, drift loses because small goals never get summarized away.

## 82. Workflow Primitives — and Dynamic vs Static

A dynamic workflow is a JavaScript file: `agent(prompt, opts?)` (options: `schema`, `model`, `isolation: "worktree"`, `agentType`), `parallel([fns])` (barrier — waits for all), `pipeline(items, ...stages)` (no barrier — items stream through stages independently). Workflows are resumable — interrupt and resume picks up where it left off. Dynamic beats static (Agent SDK / `claude -p`): static harnesses must handle every edge case so they end up generic; Opus 4.8+ writes a custom harness tailor-made for the case.

## 83. The Six Workflow Patterns Claude Composes

1. **Classify-and-act** — classifier routes to different agents/behavior. 2. **Fan-out-and-synthesize** — parallel agents, barrier, merge. 3. **Adversarial verification** — a separate agent verifies each output against a rubric (kills self-preferential bias). 4. **Generate-and-filter** — many ideas, filter by rubric, return the tested few. 5. **Tournament** — N agents compete, judge pairwise (comparative judgment beats absolute scoring). 6. **Loop-until-done** — keep spawning agents until a stop condition, not a fixed pass count. Claude mixes and nests them; knowing the names helps you nudge via prompt.

## 84. Workflow Use Cases — Often Better for Non-Coding Work

Thariq: sometimes more useful for non-technical work. Migrations/refactors (Bun's Zig→Rust rewrite used workflows); deep research + the inverse, deep verification ("verify every technical claim in my blog draft against the codebase"); sorting 1,000+ items via tournament/pairwise pipeline; memory/rule adherence (one verifier per rule + a skeptic persona); root-cause investigation (independent hypotheses, each facing refuters); triage/taste/evals/routing (quarantine pattern for untrusted content).

## 85. Pair Workflows with /goal, /loop, and Token Budgets

`/goal` sets the exit condition, the workflow does the parallel work, `/loop` keeps it going. Cap token spend by prompting a budget directly ("use 10k tokens"). When a long run eats limits faster than expected, `/usage` breaks down which skills/MCPs/plugins are spending. "Quick workflow" works for small jobs (fast adversarial review of one assumption). When NOT: most traditional coding tasks don't need a panel of 5 reviewers.

## 86. Saving and Sharing Workflows

Press **"s"** in the workflow menu to save; files land in `~/.claude/workflows`, or distribute via a skill (reference the JS files in SKILL.md — prompt Claude to treat them as a *template*, not a verbatim script). The **"ultracode"** trigger word guarantees Claude builds a workflow rather than a single pass.

## 87. Auto Mode Retired Plan Mode (Opus 4.6+)

Boris no longer uses plan mode: older models needed an explicit plan to stay on track; 4.6+ plan implicitly, so the planning step became overhead. He starts in auto mode, lets it work, moves to the next Claude. Plan mode still earns its place if you want the written artifact of intent. Updates Section 3 (Plan Mode); pairs with 42/68 (Auto Mode).

## 88. Context Minimalism — Tell the Model Less

The progression: Sonnet 3.5 = prompt engineering; Opus 4 = context engineering; today's models need neither. Boris: minimal system prompt, minimal tools, give the model a *way to fetch* context, get out of the way. Cat: "When you give the model too much context, you're micromanaging it — sometimes the model knows a better way." Minimal ≠ vague — give the goal, not the micro-steps (pairs with 65, 66).

## 89. When Claude Errs, Write It Down — Don't Re-Prompt

Boris's single most important idea for long-running work: when Claude makes a mistake, don't tell it to do it differently — tell it to write the fix into CLAUDE.md or a skill. A conversational correction patches *this run*; a written rule fixes *every future run*. The rule set compounds, so the error rate trends down instead of resetting each session. Pairs with 4 (CLAUDE.md), 5 (Skills), 62 (/rewind).

## 90. Why Auto Mode Is Trustworthy — Red-Teaming and Evals

The team collected thousands of agent transcripts + permission prompts, classified each safe/unsafe, then red-teamed with prompt injection until auto mode caught every constructed attack (attacks became evals). Counterintuitive safety argument: "When you accept 99% of requests, your eyes glaze over. Auto mode is more safe than reading every single permission prompt." Trust is what makes parallel autonomous work possible.

## 91. Nested Subagents — Agents Kicking Off Agents

Shipped Jun 9, 2026: a subagent can spawn its own subagents, capped at **depth=5** to start. Nesting is a context-management tool — each layer keeps its own window so deep work doesn't bloat the parent. Monitor via arrow-down in the terminal. Model choice propagates to nested agents; thinking weights don't (yet). Works with forked sessions and Chrome tools. The lower-level primitive under the workflows arc (80–86); pairs with 6, 76, 28.

## 92. fork: true — Run a Skill in Its Own Context Window (Experimental)

Add `fork: true` to a skill's frontmatter so the skill runs in its own context window, then have the skill use agents to isolate context per step. Boris is adding it to the built-in `/code-review` skill. Why: a heavy skill (deep research, code review) pollutes or blows out the main context. Experimental — treat as preview, not stable API. Pairs with 5, 91; echoes 88's minimalism.

## 93. The Dynamic-Workflows Trigger Is Now "use a workflow"

Correction to Section 80's launch guidance: say **"use a workflow"**, not the bare word "workflow" — the single word triggered workflows when users didn't mean to. Mechanics unchanged.

## 94. Fable 5 — The Best Coding Model, By a Wide Margin

Launched Jun 9, 2026 — a "Mythos-class" model made safe for general use, in Claude Code and Cowork. Boris: "the best model I have used for coding, by a wide margin… less prompts and steers, more efficient token use, better code quality, better tool use, more intelligent self-verification, longer running sessions, and higher trust & autonomy." A day later: "Fable has judgement, taste, and dimensionality… the first model I've used that was so methodical and precise [debugging] — taking measurements and adding logs then verifying that it truly fixed the issue before declaring victory… It really has this 'big model smell.'"

Benchmarks (Fable 5 → Opus 4.8): SWE-Bench Pro **80.3%** → 69.2%; FrontierCode/Diamond (xhigh) **29.3%** → 13.4%; GDPval-AA **1932** → 1890; OSWorld-Verified **85.0%** → 83.4%. On starred benchmarks (cybersecurity, biology, Terminal-Bench, HLE, HealthBench) Fable performs closer to Opus 4.8 due to safety fallbacks — those higher figures are Mythos 5. Boris confirms the safety classifiers are currently "trigger-happy" (flagging ordinary debugging as cyber/bio) and being improved.

Specs: model id `claude-fable-5`; 1M context; 128K max output; adaptive thinking; knowledge cutoff Jan 2026; no fast mode yet. **Pricing: $10/M input · $50/M output — exactly 2× Opus 4.8**; cache write $12.50, cache read $1; full 1M context at standard rate. Karpathy: "SOTA on everything by a margin… a major-version-bump-deserving step change… You can give it a lot more ambitious tasks — the model 'gets it' and it will just go."

## 95. What Fable 5 Changes for You

- **New default for coding** — updates Section 2 (Model Selection) and 78 (Opus 4.8 "strongest yet").
- **"Less prompts and steers"** — lean into context minimalism (88) and delegation over guidance (65): give it the goal, not the micro-steps.
- **Longer sessions + higher trust** — the autonomy stack (auto mode 42/68, `/goal` 77, nested subagents 91, workflows 80–86) pays off more on a base model that self-verifies better.
- **Cost** — 2× Opus 4.8; for high-volume routine work Opus 4.8 / Sonnet may be better economics. Reach for Fable where the quality jump pays for itself.
- **Caveat** — Fable-specific effort levels and usage tactics aren't documented yet.
