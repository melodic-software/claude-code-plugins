---
description: "Re-check a filled /planning:interview ledger with fresh-context agents blind to each answer's rationale; only doubtful answers come back. Use when: 'audit my interview answers', 'validate the interview answers', 'have agents check the answers', 'accept all and have agents check them', 'agent-validated interview', 'have subagents second-guess the recommendations', 'auto-answer then verify the ledger'. Plans: '/planning:devils-advocate'; first-time questions: '/planning:interview'."
argument-hint: "[topic]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: contract
  summary: Adversarially validate interview answers with fresh-context agents
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git. The dated record for that composition claim is the worktree skill's
[reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md),
"The pre-compute block runs as one shell invocation".

## Variables

Arguments: `$ARGUMENTS`

The optional `[topic]` names the interview topic to validate. With no argument, read the current
topic's interview ledger.

## Purpose

**Independent adversarial validation of a completed `/planning:interview`'s answers**, whether the
human hand-answered the rounds or the recommendations were auto-accepted. Fresh-context agents
re-examine each answer on its merits; only the answers they challenge or reclassify come back to
the human, and the rest collapse to a one-line confirmation. The value is a producer≠critic pass
over decisions the producing session is structurally the worst judge of. It matters most for
auto-accepted answers, where the orchestrator's own recommendations were taken at face value, the
producer grading its own work. A hand-answered ledger benefits too: fresh validators that never saw
the reasoning catch a decision made under the same session's blind spots.

**Validation, never derivation.** Never spawn subagents to invent answers: everything that reaches
a round is a genuine decision, the never-auto class (facts were already resolved from the
environment), and a subagent asked to derive one only reinjects the orchestrator's framing and
converges to accept-all at quadratic frontier cost with a false patina of verification.
Fresh-context independence is real only for *checking* an answer, not for producing one. Accept
the answers first, then check them.

That fact-resolution contract is the shared self-answer step,
[`${CLAUDE_PLUGIN_ROOT}/context/self-answer.md`](../../context/self-answer.md); flag an answered
row one of its sources would have settled as a fact.

## Preconditions

A completed `/planning:interview` for the topic. Validate whatever answers it persisted, in
whichever form:

- an engineering session's `## Brief` in `PLAN.md` (its resolved decisions, Captured assumptions,
  and Deferred questions with their **arbiter tags**);
- the decision-tree ledger (`interview-checklist.md` in the memory slice), present only when the
  interview emitted one (≥2 open questions or `me` mode);
- a general (non-engineering) session's shared-understanding summary in the memory slice.

The answer set is the resolved decisions in the ledger when present, else the Brief's decisions,
else the general summary. A **Brief-only** interview (an `auto`/`lock` session with no checklist)
and a **summary-only** general interview are both valid inputs. Derive `<topic-slug>` from
`$ARGUMENTS` or the current branch (kebab-case, ≤40 chars; shared with `/planning:interview`); read
the memory slice `<memory_dir>/<topic-slug>/` (default `.work/`) per
[`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md).
If the topic has NO persisted interview output, STOP with a message pointing at
`/planning:interview`. If output exists with open consequential branches, Step 1 fills them under
the never-auto floor before validating.

When the caller names the question ids to audit (the interview page's `accept-audit` event lists
them), the answer set is exactly those answers: fill or validate no other open branch, and leave the
rest of the interview open.

## The validation loop

### Step 1. Assemble the answer set, holding the never-auto floor

Validation needs a complete answer set. If the interview is already fully answered, every consequential branch resolved, whether by hand or by a prior accept-all, validate it as it stands. If open branches remain, drive the interview's accept-recommended path to fill them into a **working, in-session** set of *provisional* answers. For each open branch, take the orchestrator's recommended answer, NOT persisted to the tracked Brief / ledger / summary yet (an auto-accepted answer is unvalidated, and writing it into the contract before validation is exactly what this skill exists to prevent). **The mechanical never-auto floor is held out of any auto-accept, and no validator ever resolves it:**

- a Deferred question tagged **`USER-RESERVED`** stays **deferred**. It is a carry-forward item whose arbiter re-confirms at the `/planning:plan` approval gate *with plan-time context*, so it is not auto-accepted, not validated, and **not turned into an audit question here**; it passes through untouched, arbiter tag intact.
- a decision the interview's **auto-guard** class covers, a genuine user choice with real tradeoffs and no codebase answer, is held out of the auto-accept and routed to the human as a real question in the confirm round (Step 4).
- an open row asking a fact no self-answer source settled (the shared step's **Needs the user** outcome) is held out of the auto-accept with the auto-guard decisions and routed to the human the same way. The orchestrator's recommendation never becomes the fact, and no validator supplies one.
- a register row at **`superseded-by-plan`** (a plan change displaced the user's answer) is held out of the auto-accept, never validated into `answered`, and routed to the human as a real question showing both the proposed and the displaced answer. Only the user's reply to that row moves it.
- a register row whose resolution carries `hedged:` anywhere (including the page's `hedged:` answer and the legacy `free-text: hedged:` export) is validated, but it never closes on a CONFIRMED verdict: it is routed to the human in the Step 4 confirm round whatever the validators return. Its `open` commitment rows are held out of the auto-accept like any other floor item.

A `free-text:` row is validated like any answer and flagged in its verdict, so the human sees which answers were given in the user's own words rather than picked from the authored options.

Everything else enters the provisional set as an accepted answer for validation.

### Step 2. Dispatch fresh-context validators

Dispatch **1–3 fresh-context (non-fork) adversarial validator subagents**, **each reviewing the
whole answer set**. More validators add independent cross-checks on every answer; never shard the
answers between them, or "confirmed by all" becomes indistinguishable from "unseen by some". A fork
inherits this session's reasoning and bias, so a validator MUST be a fresh-context subagent that
never saw the interview (the marketplace's self-grade fresh-eyes rule). Where the verdict is
high-stakes and correlated blind spots are the risk, prefer a cross-vendor advisor **when one is
enabled and set up** (e.g. the OpenAI Codex plugin, when its documented surface can take this
artifact, invoked per its own docs), with the fresh-context same-vendor subagent as the fallback,
never a route to a command that may not resolve (per `docs/plugin-philosophy.md` "Fresh-eyes
checkpoints" in the marketplace repository).

Each validator receives the whole provisional answer set and the interview's persisted context
(Brief or general summary), **with the recommendation's persuasive rationale WITHHELD**: hand it
*what* was decided, never *why the orchestrator liked it*.

Each validator applies `/planning:devils-advocate`'s evidence discipline, by reference: every
verdict backed by a code path, doc reference, bug number, or concrete logical argument, never
training-data recall; unverified is a finding, not a pass. Do not invoke `/planning:devils-advocate`
itself: it extracts assumptions from one plan and emits severity-ranked findings, while this skill
needs per-answer verdicts over a pre-enumerated ledger.

### Step 3. Per-answer verdict

Each validator returns, for every accepted answer, one of:

- **CONFIRMED**. The accepted answer is sound on the evidence.
- **CHALLENGED** *(why)*. A specific, evidence-backed reason the accepted answer is wrong or
  unsupported.
- **RECLASSIFIED-TO-HUMAN**. Not an agent's call: a taste, policy, scope, or tradeoff decision
  only the human should make (an auto-guard miss).

Validators also flag **shaky dependency chains**, an answer whose soundness rests on another answer
that is itself CHALLENGED, so the human sees the blast radius, not just the leaf.

### Step 4. Merge and triage

Merge the validators' verdicts. Independence means one dissent is signal: any CHALLENGED or RECLASSIFIED from *any* validator wins over another's CONFIRMED.

- **CONFIRMED by all** → collapse to a one-line summary per answer. The human skims, does not re-decide. A `free-text:` row in this block keeps its flag.
- **`hedged:` rows** → real questions whatever the verdict, restating what the headline commits to and which of its rows are still open.
- **CHALLENGED / RECLASSIFIED / auto-guard-held / unsettled-fact / `superseded-by-plan` rows** → become real numbered human questions, asked in the `/planning:interview` round format (its recommendation-per-question, single-verdict-marker, and dependency-surfacing rules apply). Each challenge's *why* rides along so the human decides informed.
- **USER-RESERVED deferred questions** → listed as carry-forward items (arbiter tag intact), NOT resolved here. They re-confirm at the `/planning:plan` approval gate with plan-time context, so asking them now would strip that context and rewrite the Brief prematurely.

### Step 5. Human confirmation

Present the collapsed CONFIRMED block, the real questions, and the untouched USER-RESERVED
carry-forward list. The human answers only the questions. **Persist here and only here:** once the
human confirms, write the provisional accepted answers plus the human's answers back to the
interview's persisted artifact(s) (the Brief or the general summary, and the ledger when the
interview kept one) exactly as an interview round would, leaving USER-RESERVED deferrals in place.
Nothing reaches the contract on a bare invocation ahead of this confirmation. This gate is
mandatory: a CONFIRMED collapse is a summary to skim, never a license to skip the human. Then hand
back to the interview's stop/handoff path.

## What this skill does NOT do

- **Derive answers**. Validation only; the interview's answers are the input.
- **Resolve a reserved decision, automatically or early**. Auto-guard choices route to the human,
  and USER-RESERVED deferrals stay deferred to `/planning:plan`; no verdict overrides either.
- **Stress-test a plan**. That is `/planning:devils-advocate` over a `/planning:plan` artifact.
- **Ask the questions the first time**. That is `/planning:interview`; this runs only over answers
  already in its output.
- **Block or auto-apply**. It emits findings that gate a human confirmation round.

## Composition

| When | Skill | How it composes |
|---|---|---|
| Produce the answers to validate | `/planning:interview` | Writes the Brief / general summary / ledger this consumes; the confirmation round hands back to its stop/handoff path. Its Step 3 recap and `--procedure` check show the Q&A and that the procedure ran; this skill re-validates the answers, and neither composes nor duplicates the other |
| Evidence discipline each validator applies | `/planning:devils-advocate` | Cited, not duplicated |
| Plan the implementation | `/planning:plan` | Downstream, after `/planning:design`: the confirmed Brief feeds planning as a hand-answered interview's would |

## Next

/planning:design takes the confirmed Brief next, as it would after a hand-answered interview; it
records a one-line early exit when no design question is open.

## Gotchas

- A validator handed the recommendation's rationale validates the *pitch*, not the decision.
  Withhold the narrative.
- Forks are not validators: a fork inherits this session's context and reproduces its blind spot.
  Use fresh-context (non-fork) subagents.
- The never-auto floor is not validator territory: an auto-guard decision never collapses on a
  CONFIRMED verdict, and a USER-RESERVED deferral is never turned into an audit question. It
  carries forward to `/planning:plan` untouched.
- One validator's CHALLENGED outweighs another's CONFIRMED: surface a lone dissent, never average
  it away.
- The collapsed CONFIRMED block is not the finish. The human confirmation round is the stop
  condition, same as an interview's confirmation gate.
