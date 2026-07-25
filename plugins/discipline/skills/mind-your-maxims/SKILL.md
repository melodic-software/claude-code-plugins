---
name: mind-your-maxims
description: "Re-anchor cooperative-communication discipline — Grice's conversational maxims plus the AI-augmented transparency maxim — then audit recent responses and agent-authored artifacts for what the reader actually needed: completeness in both directions, relevance, clarity, and disclosed boundaries. Use when: 'mind your maxims', 'communication quality', 'answer what I asked', 'you buried the answer', 'you didn't answer the question', 'too vague', 'stay on topic', 'is this clear', 'grice', 'maxims', or at conversation start to set the communication posture."
user-invocable: true
disable-model-invocation: false
metadata:
  discipline-batch: core  # every session communicates with the user
  discipline-batch-rank: 100
---

# Mind your maxims

A drift corrector for cooperative-communication discipline. The method —
re-anchor, audit the work in flight, correct forward, report, and the tone
that firing this is not an accusation — lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to communication discipline.

## The discipline this re-anchors

Cooperative communication: give the reader what they need — no less, no
more — relevantly, clearly, and with your uncertainty and limits disclosed.
This discipline rests on maxims their **primary sources own**; this skill
points at them and does not restate them (it dogfoods
`/discipline:point-dont-copy` — a paraphrase of the maxims here would be a
second copy that drifts):

- Grice's Cooperative Principle and its four maxims — Quantity, Quality,
  Relation, Manner — in
  [Grice, "Logic and Conversation"](https://www.sas.upenn.edu/~haroldfs/dravling/grice.html)
  and [Cooperative principle](https://en.wikipedia.org/wiki/Cooperative_principle).
- The AI-augmented maxims for human-AI dialogue — Transparency and
  Benevolence — in Miehling et al., "Language Models in Dialogue:
  Conversational Maxims for Human-AI Interactions"
  ([arXiv:2403.15115](https://arxiv.org/abs/2403.15115)).

Resolve the source of truth per the method doc's ladder: if the consuming
project declares a communication or writing-quality convention in its own
`CLAUDE.md` / `.claude/rules/`, re-anchor THAT as well and audit against it.

## The rubric this skill audits

Its own delta — the four axes this corrector owns, mapped onto the pointed-to
maxims:

- **Quantity, both directions.** Under-informing is a finding: an asked-for
  detail, a load-bearing caveat, or a necessary step omitted. Over-informing
  is a finding too: padding, restatement, and detail the reader did not need.
  Both fail the reader.
- **Relation.** Answer the question actually asked. An adjacent answer to a
  question the reader did not ask, a tangent, or a buried lede (the answer
  present but hidden below setup) fails relevance even when technically
  correct.
- **Manner.** Unambiguous references (no pronoun or "it" the reader must
  resolve), ordered structure, and plain clarity over cleverness or
  needless jargon.
- **Transparency.** Disclose the boundaries: flag genuine uncertainty rather
  than asserting through it, and state the edges of your knowledge or
  capability rather than letting the reader assume completeness.

## Delegations — axes this skill routes elsewhere

- **Quality (truthfulness, evidence) → `/discipline:do-your-research`.** The
  Gricean Quality maxim — say what you have grounds for — is that skill's
  discipline, not this one's. A claim's truth routes there; this skill owns
  how the message is shaped, not whether it is factually backed.
- **Pure verbosity remediation → `/discipline:tighten-your-output`.** The
  Quantity audit here NAMES padding as a finding, but batch prose-trimming
  is that skill's job; route large verbosity cleanups to it rather than
  hand-trimming at scale here.

Both are sibling skills in this plugin, so these are direct routes.

## Benevolence — deliberate out-of-scope

The paper's other augmented maxim, Benevolence, is deliberately NOT audited
here: it is platform / safety-layer territory (the model's alignment
posture), not an auditable communication-drift axis a mid-session corrector
can meaningfully score. Recorded as an explicit exclusion, citing the paper
above — not an oversight.

## Audit targets and the dual moment

- **Two target kinds.** Audit recent agent RESPONSES and agent-authored
  ARTIFACTS alike — docs, PR bodies, prompts, commit messages, skill text.
  A buried lede in a PR body fails the same rubric as one in a chat reply.
- **Dual moment.** Valid as posture-setting at any time (the method doc's
  conversation-start case — acknowledge the discipline as active and stop,
  nothing to audit yet), AND as an audit once output exists. Fire it early
  to set the posture or later to check the work.

## What this skill does NOT do

- **Does not audit truthfulness.** Whether a claim is factually backed is
  `/discipline:do-your-research`; this skill audits the shape of the message,
  not its evidence.
- **Does not restate the maxims.** The definitions live in the cited
  sources; this skill audits against them, it does not reproduce them.
- **Does not fabricate a finding.** A response that gave the reader exactly
  what they needed, relevantly and clearly, audits clean; say so.

## Gotchas

- **Correct and unhelpful is still a finding.** An answer can be true, and
  fail Relation or Quantity — right, but not to the question asked, or buried
  under detail the reader did not need. Judge by what the reader needed, not
  by whether the words are accurate.
- **The buried lede is the common miss.** The answer is present but below the
  setup; Relation and Manner both fail when the reader has to dig for the
  thing they asked for. Lead with it.
