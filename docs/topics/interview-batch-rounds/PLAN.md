# interview-batch-rounds

## Brief

### TLDR

- `/planning:interview` Step 2 moves from one-question-at-a-time to **frontier-rounds**: each round asks every question whose prerequisites are settled, numbered, each with a recommendation; answers recompute the frontier; done when frontier is empty.
- Prose is the default question surface; `AskUserQuestion` becomes opt-in via a new planning-plugin `userConfig` scalar (`question_surface`, default prose).
- Fact-finding goes non-blocking: facts are dispatched to background sub-agents; only questions downstream of a running lookup wait for it.
- Upstream sharpenings absorbed: facts-vs-decisions split (facts looked up, decisions always put to the user) and an explicit confirmation gate before the Brief locks.
- Question-budget guidance added (depth scales down as upstream artifacts scale up; ballooning frontier routes to `/planning:wayfind`); planning plugin bumps to 0.13.0.

### Goal

An interview session resolves the same decision tree in far fewer round-trips: the user answers a whole frontier of independent questions in one reply (dictation-friendly), dependent questions arrive only after their prerequisites settle, and the terminal "agree, agree, agree" tail collapses into a single round. The skill never asks the user for a fact it can look up, never decides a design choice on the user's behalf, and never acts before the user confirms shared understanding.

### Constraints

- Vocabulary stays "interview" — no "grill/grilling" terminology anywhere in the skill or docs.
- Scope is the interview skill only; other planning skills (prd, design, architect, brainstorm, wayfind) are untouched this change.
- Repo plugin philosophy holds: repo-agnostic, configurable without editing the plugin (`userConfig` for the personal surface preference), plugin-form-safe.
- Cross-skill references stay intra-plugin (wayfind escape valve is a sibling skill in the planning plugin); no new cross-plugin coupling.
- Fresh-docs mandate: the `userConfig` schema is verified from the current plugins docs before the manifest edit lands, not from recall.
- One discipline, not two: rounds everywhere in the skill (`me` and `auto` Q&A); a frontier of one question degenerates to the old behavior, so no per-mode fork.

### Acceptance criteria

- SKILL.md and context/loop.md describe the rounds loop: compute the frontier (all decisions whose prerequisites are settled), ask it as one numbered set in prose with a recommendation per question, wait, recompute; a question dependent on an open question in the same round is deferred to a later round.
- The canonical `me`-mode framing carries the facts-vs-decisions split: facts are resolved from the environment (non-blocking sub-agent dispatch when slow), decisions are always put to the user; the blanket "explore the environment instead of asking" line is gone.
- The stop condition requires an empty frontier AND explicit user confirmation of shared understanding before persistence/handoff.
- `plugins/planning/.claude-plugin/plugin.json` (or the manifest's documented userConfig location) declares `question_surface` with default `prose`; the skill reads it and only uses `AskUserQuestion` when the user opted in.
- gotchas.md, templates/checklist.md, and evals/evals.json are updated — no remaining assertion that questions must be asked one at a time or that batching is a failure mode; evals assert rounds behavior instead.
- Question-budget guidance present: interviews invoked after research/exploration/PRD treat those artifacts as settled prerequisites; a ballooning frontier is named as a `/planning:wayfind` signal; no numeric question cap.
- Planning plugin version is 0.13.0 and CHANGELOG.md carries a behavioral-change note (rounds default, new `question_surface` userConfig).

### Captured assumptions

- Plugin `userConfig` supports a per-user enum/string scalar readable as `${user_config.question_surface}` as the docs described at last full review — revisit (and re-verify from the fetched plugins-reference page) at implementation time before the manifest edit.
- Upstream `batch-grill-me` is still `in-progress/` and may drift after we ship — acceptable; we own the fork and re-audit upstream opportunistically.

### Out-of-scope

- Rewriting the one-question-at-a-time echoes in prd, design, architect (INTERVIEW tag), and brainstorm — deferred pattern-consistency audit.
- All other upstream ports surfaced by the gap scan (Fowler review baseline, to-questionnaire, skill-quality negation/negative-space, tdd top-up, wayfind task-type verify, git-guardrails, wizard, router) — tracked on the session's deferred agenda, each its own effort.
- A setup action for the surface preference — `userConfig` suffices for V1; setup sugar may follow later.

### Deferred questions

- Exact `question_surface` value set and any additional interview userConfig keys — defer until implementation; **arbiter: /architect**
- How an opted-in `AskUserQuestion` surface renders a frontier larger than the tool's 4-question cap (chunking vs prose fallback) — defer until implementation; **arbiter: /architect**
- Whether the confirmation gate also applies to `lock`-mode direct synthesis (no Q&A ran) — defer until implementation; **arbiter: USER-RESERVED** (could change the stop-condition contract)

## Plan

<!-- empty — populated by /architect -->
