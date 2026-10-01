# Session-config recommendation: model, effort, advisor

Reference detail for the `## Session-config recommendation (model, effort, advisor)`
section of `SKILL.md`.
Read on demand when forming the recommendation, at the stop/handoff boundary for an
engineering session, or at the early post-survey surface (and again at the stop
boundary) for a general/terminal session. The interview already reads task complexity
and ambiguity to drive its rounds; this turns that read into a recommendation for how
the session that carries the work forward should be configured: the **downstream
execution session** an engineering session hands off to, or, when the session is
terminal with no downstream consumer (a general decision, per SKILL.md Step 5), the
**current/next session**, applied now.

## Two orthogonal knobs

This skill treats model and effort as two separate levers. Recommend against the right one,
because they are not interchangeable:

- **Model tier (capability).** Raise the model when the assistant would be
  **confidently wrong despite full context**, where the failure is a reasoning ceiling,
  not missing information. Signals from the interview: the task turned on subtle
  correctness, dense cross-module invariants, or tradeoffs the user themselves found
  hard to adjudicate. Residual ambiguity is its own signal in this direction: ambiguity
  the rounds could not retire argues up, and a Brief precise enough to execute from
  argues down.
- **Effort level (thoroughness).** Raise effort when the assistant would
  **under-explore or under-verify**, reaching the right answer but tending to stop
  short. Signals: broad surface area, many files, a verification-heavy acceptance
  criteria list, or a task where the risk is a missed case rather than a wrong model.

A task can want both, one, or neither. State which knob each recommendation turns and
why, in the interview's own evidence terms.

**Neither knob is the first move.** This skill checks the context before either knob: a
vague prompt, wrong tools, or missing skills explain a miss before model or effort do. That
prior step is this skill's own product: the Brief **is** the context fix, so recommend a
knob only for what a sharper Brief would not have caught. Between the knobs, the skill asks
whether the assistant failed to *try* hard enough (effort) or failed to *know* enough
(model), and holds that test as a starting point rather than a hard rule. It weighs an
effort raise most when the session runs below the model's default effort.

- **Pointer**: for which model and effort level fit which work, see
  <https://code.claude.com/docs/en/model-config#choose-an-effort-level> and
  <https://platform.claude.com/docs/en/about-claude/models/choosing-a-model#choose-the-best-model-to-start-with>
  (correlate with [choosing a Claude model and effort level in Claude Code](https://claude.com/blog/claude-model-and-effort-level-in-claude-code),
  which the model-config page links for this guidance).
- **As of**: 2026-08-04
- **Recheck trigger**: either page changes how it orders model against effort, or the
  model-config page stops linking the post for this guidance.

No docs page states the try-versus-know test itself as of 2026-08-04; the docs pages above order
the levers, and ordering a lever is not diagnosing which failure you have. The test stays this
skill's own rule.

## Advisor pairing

For non-trivial work this skill does not recommend a faster main model running
**without** a stronger advisor: it recommends the faster main model paired with a
stronger advisor that the main model escalates hard decisions to, rather than paying
for the stronger model on every routine turn (for when the advisor is consulted, see
<https://code.claude.com/docs/en/advisor#when-claude-consults-the-advisor>).
The concrete tier names that fill this **faster-main + stronger-advisor** shape are
exactly the values that drift between versions, and which specific pairings are
accepted drifts with them. Source them live (below), never pin them here: the durable
fact is the *shape* of the pairing, not the names that fill it.

When the recommendation is "keep the faster main model," pair it with the advisor
recommendation. When it is "raise the main model to the top tier," the advisor adds
less, so note that and let the user decide.

## Read the live contract, never pin

Current model names, tiers, effort levels, and accepted advisor pairings change
between Claude Code versions. Source them at recommendation time from the official
docs; do not bake them into this skill (the durable *distinction* above is stable, the
*names and tiers* are not). This mirrors `draft-goal-condition`'s never-pin,
live-doc discipline, though its fetch-**failure** handling differs (below): there the
fetched value is the deliverable so it halts, here the recommendation is auxiliary so
it degrades.

Primary sources, fetched once when you form the recommendation (not per round):

- `https://code.claude.com/docs/en/model-config`: model aliases and the effort setting
- `https://claude.com/blog/claude-model-and-effort-level-in-claude-code`: correlate only, for which model and effort fit which work
- `https://code.claude.com/docs/en/advisor`: advisor enablement and accepted main+advisor pairings
- `https://claude.com/blog/the-advisor-strategy`: correlate only, for why a faster main + stronger advisor works

**Fetch failure degrades, never halts.** The recommendation is an auxiliary output, so
a doc-fetch failure must not block the interview or the Brief. Fall back to the
durable distinction above and tell the user, in the same breath, that the current
model names and pairings could not be verified live (cite the URL) so they confirm
against `/model` and `/advisor` themselves. This is a visible degrade, not a silent
one, and never a guessed-from-memory model name.

## Advisory framing: effort is readable, advisor state is not

The skill knows its own main model, stated in the system prompt. It reads effort from
`${CLAUDE_EFFORT}` in its body, or from `CLAUDE_EFFORT` in a Bash subprocess, and treats an absent
value as a model without effort support rather than an unset level. It knows of no surface that
reads the configured advisor back, so it treats advisor state as unknown.

- **Pointer**: for the effort values, see
  <https://code.claude.com/docs/en/skills#available-string-substitutions> and
  <https://code.claude.com/docs/en/env-vars#variables>; for choosing and disabling the advisor,
  see <https://code.claude.com/docs/en/advisor#enable-the-advisor> and
  <https://code.claude.com/docs/en/advisor#turn-the-advisor-off>.
- **As of**: 2026-09-06
- **Recheck trigger**: the skills page drops the `${CLAUDE_EFFORT}` substitution row, a surface for
  reading the configured advisor appears on the advisor or environment-variables page, or a
  release note names either.

So split the framing. Where effort is readable, say what it is and recommend from there. Where
advisor state is not, frame the recommendation as a delta the user applies rather than a fact about
their current state: "if you are not already on X, consider it," plus how to apply it, `/model` for
the model, the effort setting for effort, `/advisor` for the advisor. Do not instruct a capability
that does not exist, and do not carry the old blanket claim that neither is readable.

## Both domains

Complexity and ambiguity apply to engineering and general sessions alike: a hard
general decision can warrant the top model just as a subtle refactor can. Surface the
recommendation for both; it is orthogonal to the engineering/general domain split and
to the `me`/`auto`/`lock` action. Framing differs by what the session hands off to
(SKILL.md Step 5): an engineering session's recommendation configures the
**downstream execution session** it hands off to. A general session is **terminal**,
with nothing downstream, so its recommendation configures the **current or next
session**, applied now (`/model` for the model, the effort setting for effort,
`/advisor` for the advisor), not a session that will never exist.

**Timing differs with the consumer.** The engineering recommendation configures a
session that has not started yet, so the stop/handoff boundary is early enough. A
general session's consumer is the session already running the interview, so a
recommendation first emitted at the stop boundary lands after the work it was derived
from is complete. Surface a first read early, right after the Step 1 survey
classifies the domain as general, whenever the survey's complexity/ambiguity signals
warrant a config change. Applied then, it improves the substantive rounds
themselves. Refresh it at the stop boundary as config for the current/next session.
When the config was raised only at the end, or the user declined a mid-session
change, offer to re-evaluate the reached understanding under the raised config
instead of leaving the recommendation purely prospective.

## Inverse direction: mid-task

The same two signals keep mattering mid-task, past the interview boundary, but the
interview terminates at handoff (SKILL.md Step 5) and nothing wires this context into
whatever session executes next. Hand it to the **user** as a watch-for at handoff,
not as an instruction to an executing actor: tell them that if execution starts
showing **confidently-wrong-despite-context** (a signal to raise the model) or
**under-exploration / under-verification** (a signal to raise effort), that is their
cue to raise the corresponding knob, by the same knob-picking logic as above, rather than
grinding on under a config the task has outgrown.
