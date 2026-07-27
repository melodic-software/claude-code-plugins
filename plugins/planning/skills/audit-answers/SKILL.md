---
name: audit-answers
description: "Adversarially validate a completed /planning:interview's answers with independent fresh-context agents — runs over any filled decision ledger, whether the human hand-answered the rounds or the recommendations were auto-accepted. Validators re-examine each answer with its rationale withheld and return a per-answer verdict (confirmed / challenged / reclassified-to-human), so only the doubtful answers come back as real questions and user-reserved decisions always do; if open branches remain, it accepts the recommended answers to fill them first, holding the never-auto floor. Use when: 'audit my interview answers', 'validate the interview answers', 'have agents check the answers', 'accept all and have agents check them', 'agent-validated interview', 'have subagents second-guess the recommendations', 'auto-answer then verify the ledger'. Not for stress-testing a plan artifact (that is '/planning:devils-advocate') or asking the human the questions the first time ('/planning:interview'); needs a filled interview ledger."
argument-hint: "[topic] (no args reads the current topic's interview ledger)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  cheatsheet-stage: contract
  cheatsheet-summary: Adversarially validate interview answers with fresh-context agents
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

A completed `/planning:interview` for the topic. The skill validates whatever answers that interview persisted, in whichever form it wrote them — it does not require any single artifact:

- an engineering session's `## Brief` in `PLAN.md` (its resolved decisions, Captured assumptions, and Deferred questions with their **arbiter tags**);
- the decision-tree ledger (`interview-checklist.md` in the memory slice), present only for sessions the interview emitted one for (≥2 open questions or `me` mode);
- a general (non-engineering) session's shared-understanding summary in the memory slice.

The answer set to validate is the resolved decisions in whichever of these exists — the ledger when present, else the Brief's decisions, else the general summary. A **Brief-only** interview (an `auto`/`lock` session with no checklist) and a **summary-only** general interview are both valid inputs, not a reason to stop. Derive `<topic-slug>` from `$ARGUMENTS` or the current branch (kebab-case, ≤40 chars; shared with `/planning:interview`); resolve the slices per the topic-docs binding [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md). If the topic has NO persisted interview output at all, STOP with a message pointing at `/planning:interview` — there is nothing to validate. If output exists but has open consequential branches, Step 1 fills them under the never-auto floor before validating.

## The validation loop

### Step 1 — Assemble the answer set, holding the never-auto floor

Validation needs a complete answer set. If the interview is already fully answered — every consequential branch resolved, whether by hand or by a prior accept-all — validate it as it stands. If open branches remain, drive the interview's accept-recommended path to fill them into a **working, in-session** set of *provisional* answers — for each open branch, take the orchestrator's recommended answer, NOT persisted to the tracked Brief / ledger / summary yet (an auto-accepted answer is unvalidated, and writing it into the contract before validation is exactly what this skill exists to prevent). **The mechanical never-auto floor is held out of any auto-accept, and no validator ever resolves it:**

- a Deferred question tagged **`USER-RESERVED`** stays **deferred** — it is a carry-forward item whose arbiter re-confirms at the `/planning:plan` approval gate *with plan-time context*, so it is not auto-accepted, not validated, and **not turned into an audit question here**; it passes through untouched, arbiter tag intact.
- a decision the interview's **auto-guard** class covers — a genuine user choice with real tradeoffs and no codebase answer — is held out of the auto-accept and routed to the human as a real question in the confirm round (Step 4).

Everything else enters the provisional set as an accepted answer for validation.

### Step 2 — Dispatch fresh-context validators

Dispatch **1–3 fresh-context (non-fork) adversarial validator subagents**, **each reviewing the whole answer set** — the count scales independent redundancy (more validators = more independent cross-checks on *every* answer), never a sharding of the work. Every validator sees every answer, so the Step 4 merge can require agreement across all of them; splitting coverage would make "confirmed by all" indistinguishable from "unseen by some" and is not done. A fork inherits this session's reasoning and would carry its bias forward, so a validator MUST be a fresh-context (non-fork) subagent that never saw the interview happen — this is the self-grade fresh-eyes rule the marketplace mandates for any step that judges its own context's work. Where the verdict is high-stakes and correlated blind spots are the risk, prefer a cross-vendor advisor for a validator **when one is installed and set up** — e.g. the OpenAI Codex plugin, when its documented surface can take this input, invoked per its own docs — with the fresh-context same-vendor subagent as the stated fallback, never a route to a command that may not resolve.

Each validator receives the whole provisional answer set and the interview's persisted context (Brief or general summary), **with the recommendation's persuasive rationale WITHHELD** — it audits the decision, not the story that sold it. Hand it *what* was decided, never *why the orchestrator liked it*: a validator handed the pitch inherits the pitch's blind spot.

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
- **CHALLENGED / RECLASSIFIED / auto-guard-held decisions** → become real numbered human questions, asked in the `/planning:interview` round format (its recommendation-per-question, single-verdict-marker, and dependency-surfacing rules apply). Each challenge's *why* rides along so the human decides informed.
- **USER-RESERVED deferred questions** → listed as carry-forward items (arbiter tag intact), NOT resolved here — they re-confirm at the `/planning:plan` approval gate with plan-time context, so asking them now would strip that context and rewrite the Brief prematurely.

### Step 5 — Human confirmation

Present the triaged result: the collapsed CONFIRMED block, the real questions, and the untouched USER-RESERVED carry-forward list. The human answers only the questions. **Persistence happens here and only here:** once the human confirms, the provisional accepted answers plus the human's answers are written back to the interview's persisted artifact(s) — the Brief or the general summary, and the ledger when the interview kept one — exactly as an interview round would, leaving USER-RESERVED deferrals in place; nothing reaches the contract on a bare invocation, ahead of this confirmation. This gate is mandatory — a CONFIRMED collapse is a summary to skim, never a licence to skip the human. Then hand back to the interview's stop/handoff path.

## What this skill does NOT do

- **Does not derive answers** — validation only (see Purpose). The interview's answers are the input, not a subagent's invented ones.
- **Does not auto-resolve — or prematurely resolve — a reserved decision** — auto-guard choices route to the human, and USER-RESERVED deferrals stay deferred to `/planning:plan`; no verdict overrides either.
- **Does not stress-test a plan** — that is `/planning:devils-advocate` over a `/planning:plan` artifact. This validates interview *answers*, upstream of the plan.
- **Does not ask the questions itself the first time** — that is `/planning:interview`. This runs only over answers already in the interview's output (hand-answered or auto-accepted), to check them.
- **Does not block or auto-apply** — it emits findings that gate a human confirmation round; the human decides.

## Composition

| When | Skill | How it composes |
|---|---|---|
| Produce the answers to validate | `/planning:interview` | Writes the Brief / general summary / ledger this consumes; the human confirmation round hands back to its stop/handoff path |
| Evidence discipline each validator applies | `/planning:devils-advocate` | Its evidence-backed, no-recall, fresh-eyes discipline is cited, not duplicated |
| Plan the implementation | `/planning:plan` | Downstream: the confirmed Brief feeds planning, exactly as a hand-answered interview's would |

## Gotchas

- A validator handed the recommendation's rationale validates the *pitch*, not the decision — withholding the narrative is load-bearing, not optional.
- Forks are not validators: a fork inherits this session's context and reproduces its blind spot. Use fresh-context (non-fork) subagents.
- The never-auto floor is not validator territory: an auto-guard decision never collapses on a CONFIRMED verdict, and a USER-RESERVED deferral is never even turned into an audit question — it carries forward to `/planning:plan` untouched.
- One validator's CHALLENGED outweighs another's CONFIRMED: independence means a lone dissent is signal to surface, not a vote to average away.
- Do not treat the collapsed CONFIRMED block as the finish — the human confirmation round is the stop condition, same as an interview's confirmation gate.
