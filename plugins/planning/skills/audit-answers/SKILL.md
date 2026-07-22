---
name: audit-answers
description: "Adversarially validate a completed /planning:interview's answers with independent fresh-context agents — runs over any filled decision ledger, whether the human hand-answered the rounds or the recommendations were auto-accepted. Validators re-examine each answer with its rationale withheld and return a per-answer verdict (confirmed / challenged / reclassified-to-human), so only the doubtful answers come back as real questions and user-reserved decisions always do; if open branches remain, it accepts the recommended answers to fill them first, holding the never-auto floor. Use when: 'audit my interview answers', 'validate the interview answers', 'have agents check the answers', 'accept all and have agents check them', 'agent-validated interview', 'have subagents second-guess the recommendations', 'auto-answer then verify the ledger'. Not for stress-testing a plan artifact (that is '/planning:devils-advocate') or asking the human the questions the first time ('/planning:interview'); needs a filled interview ledger."
argument-hint: "[topic] (no args reads the current topic's interview ledger)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

**Independent adversarial validation of a completed `/planning:interview`'s answers.** It runs over any filled decision ledger — whether the human hand-answered the rounds or the recommendations were auto-accepted — and hands each answer to fresh-context agents that re-examine it on its merits. Only the answers they challenge or reclassify come back to the human; the rest collapse to a one-line confirmation.

The value is a producer≠critic pass over decisions the producing session is structurally the worst judge of. It is sharpest when the answers were auto-accepted — `/planning:interview`'s accept-shorthand takes the *orchestrator's own* recommendations at face value, the producer grading its own work — but a hand-answered ledger benefits too: fresh validators that never saw the reasoning catch a decision made under the same session's blind spots.

**This is validation, never derivation.** It does NOT spawn subagents to *invent* answers. The interview contract already resolves every fact from the environment, so anything that reaches a round is a genuine decision — the never-auto class — and a subagent asked to derive it only reinjects the orchestrator's framing and converges to accept-all at quadratic frontier cost with a false patina of verification. Fresh-context independence is real only for *checking* an answer, not for producing one. So the answers are accepted first, then checked.

## Preconditions

A filled interview ledger. This skill consumes what `/planning:interview` produces:

- the decision-tree ledger (`interview-checklist.md` in the topic's memory slice), and
- the `## Brief` in `PLAN.md` (Captured assumptions, and Deferred questions with their **arbiter tags**).

Derive `<topic-slug>` from `$ARGUMENTS` or the current branch (kebab-case, ≤40 chars; shared with `/planning:interview`); resolve the slices per the topic-docs binding [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md). If no interview ledger exists for the topic, STOP with a message pointing at `/planning:interview` — there is nothing to validate. If the ledger is partial (open consequential branches remain), Step 1 fills them under the never-auto floor before validating.

## The validation loop

### Step 1 — Ensure a filled ledger, holding the never-auto floor

Validation needs a filled ledger. If the interview is already fully answered — every consequential branch resolved, whether by hand or by a prior accept-all — validate it as it stands. If open branches remain, drive the interview's accept-recommended path to fill them into a **working, in-session filled ledger** — for each open branch, take the orchestrator's recommended answer as a *provisional* accepted answer, NOT persisted to the tracked ledger or Brief yet (an auto-accepted answer is unvalidated, and writing it into the contract before validation is exactly what this skill exists to prevent). **The mechanical never-auto floor is held out of any auto-accept — it always routes to the human, never to a validator:**

- any Deferred question tagged **`USER-RESERVED`** (its resolution could change acceptance criteria, out-of-scope, or constraints), and
- any decision the interview's **auto-guard** class covers — a genuine user choice with real tradeoffs and no codebase answer.

These stay OPEN as human questions regardless of what the validators say; a CONFIRMED verdict can never collapse one. Everything else enters the ledger as an accepted answer for validation.

### Step 2 — Dispatch fresh-context validators

Dispatch **1–3 fresh-context (non-fork) adversarial validator subagents** — one for a small ledger, up to three to split coverage of a large one. A fork inherits this session's reasoning and would carry its bias forward, so a validator MUST be a fresh-context (non-fork) subagent that never saw the interview happen — this is the self-grade fresh-eyes rule the marketplace mandates for any step that judges its own context's work. Where the verdict is high-stakes and correlated blind spots are the risk, prefer a cross-vendor advisor for a validator **when one is installed and set up** — e.g. the OpenAI Codex plugin, when its documented surface can take this input, invoked per its own docs — with the fresh-context same-vendor subagent as the stated fallback, never a route to a command that may not resolve.

Each validator receives the filled ledger (the accepted answers) and the Brief, **with the recommendation's persuasive rationale WITHHELD** — it audits the decision, not the story that sold it. Hand it *what* was decided, never *why the orchestrator liked it*: a validator handed the pitch inherits the pitch's blind spot.

Each validator applies `/planning:devils-advocate`'s evidence discipline — every verdict backed by a code path, doc reference, bug number, or concrete logical argument, never training-data recall; unverified is a finding, not a pass. That discipline is **reused by reference, not restated here.** The dispatch and verdict contract are purpose-built rather than an invocation of `/planning:devils-advocate` because the input and output genuinely differ: `/planning:devils-advocate` *extracts* assumptions from one plan artifact and emits severity-ranked findings plus revised-plan recommendations, whereas this skill validates a *pre-enumerated* per-answer ledger and emits per-answer verdicts that feed back as interview questions.

### Step 3 — Per-answer verdict

Each validator returns, for every accepted answer, one of:

- **CONFIRMED** — the accepted answer is sound on the evidence.
- **CHALLENGED** *(why)* — a specific, evidence-backed reason the accepted answer is wrong or unsupported.
- **RECLASSIFIED-TO-HUMAN** — not an agent's call: a taste, policy, scope, or tradeoff decision only the human should make (the validator caught an auto-guard miss).

Validators also flag **shaky dependency chains** — an answer whose soundness rests on another answer that is itself CHALLENGED — so the human sees the blast radius, not just the leaf.

### Step 4 — Merge and triage

Merge the validators' verdicts. Independence means one dissent is signal: any CHALLENGED or RECLASSIFIED from *any* validator wins over another's CONFIRMED.

- **CONFIRMED by all** → collapse to a one-line summary per answer. The human skims, does not re-decide.
- **CHALLENGED / RECLASSIFIED / the never-auto floor** → become real numbered human questions, asked in the `/planning:interview` round format (its recommendation-per-question, single-verdict-marker, and dependency-surfacing rules apply). Each challenge's *why* rides along so the human decides informed.

### Step 5 — Human confirmation

Present the triaged result: the collapsed CONFIRMED block, then the real questions. The human answers only the questions. **Persistence happens here and only here:** once the human confirms, the provisional accepted answers plus the human's answers are written to the tracked ledger and Brief exactly as an interview round would — nothing reaches the contract on a bare invocation, ahead of this confirmation. This gate is mandatory — a CONFIRMED collapse is a summary to skim, never a licence to skip the human. Then hand back to the interview's stop/handoff path.

## What this skill does NOT do

- **Does not derive answers** — validation only (see Purpose). The ledger's answers are the input, not a subagent's invented ones.
- **Does not auto-resolve a reserved decision** — the never-auto floor (USER-RESERVED + auto-guard) always routes to the human; no verdict overrides it.
- **Does not stress-test a plan** — that is `/planning:devils-advocate` over a `/planning:plan` artifact. This validates interview *answers*, upstream of the plan.
- **Does not ask the questions itself the first time** — that is `/planning:interview`. This runs only over answers already in the ledger (hand-answered or auto-accepted), to check them.
- **Does not block or auto-apply** — it emits findings that gate a human confirmation round; the human decides.

## Composition

| When | Skill | How it composes |
|---|---|---|
| Produce the answers to validate | `/planning:interview` | Writes the ledger + Brief this consumes; the human confirmation round hands back to its stop/handoff path |
| Evidence discipline each validator applies | `/planning:devils-advocate` | Its evidence-backed, no-recall, fresh-eyes discipline is cited, not duplicated |
| Plan the implementation | `/planning:plan` | Downstream: the confirmed Brief feeds planning, exactly as a hand-answered interview's would |

## Gotchas

- A validator handed the recommendation's rationale validates the *pitch*, not the decision — withholding the narrative is load-bearing, not optional.
- Forks are not validators: a fork inherits this session's context and reproduces its blind spot. Use fresh-context (non-fork) subagents.
- A CONFIRMED verdict on a USER-RESERVED or auto-guard decision is a floor violation — those never collapse, however clean they look.
- One validator's CHALLENGED outweighs another's CONFIRMED: independence means a lone dissent is signal to surface, not a vote to average away.
- Do not treat the collapsed CONFIRMED block as the finish — the human confirmation round is the stop condition, same as an interview's confirmation gate.
