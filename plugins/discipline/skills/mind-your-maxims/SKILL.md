---
description: "Re-anchor cooperative communication (Grice's maxims plus AI-augmented transparency): audit recent responses and artifacts for completeness (neither too little nor too much), relevance, clarity, and disclosed boundaries. Use when: 'mind your maxims', 'communication quality', 'answer what I asked', 'you buried the answer', 'you didn't answer the question', 'too vague', 'stay on topic', 'is this clear', 'grice', 'maxims', or at conversation start to set the communication posture."
user-invocable: true
disable-model-invocation: false
metadata:
  discipline-batch: core  # every session communicates with the user
  discipline-batch-rank: 100
  workflow-stage: anytime
  summary: Re-anchor cooperative communication and audit recent responses for clarity
---

# Mind your maxims

A drift corrector for cooperative-communication discipline. The shared method
(re-anchor, audit the work in flight, correct forward, report) lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to communication discipline.

## The discipline this re-anchors

Cooperative communication: give the reader what they need. No less, no
more. Relevantly, clearly, and with your uncertainty and limits disclosed.
The maxims are owned by their **primary sources**; point at them, do not
restate them (this skill dogfoods `/discipline:point-dont-copy`: a paraphrase
here would be a second copy that drifts):

- Grice's Cooperative Principle and its four maxims. Quantity, Quality,
  Relation, Manner. In
  [Grice, "Logic and Conversation"](https://web.archive.org/web/20210117181544/https://www.sas.upenn.edu/~haroldfs/dravling/grice.html)
  and [Cooperative principle](https://en.wikipedia.org/wiki/Cooperative_principle).
- The AI-augmented maxims for human-AI dialogue. Transparency and
  Benevolence. In Miehling et al., "Language Models in Dialogue:
  Conversational Maxims for Human-AI Interactions"
  ([arXiv:2403.15115](https://arxiv.org/abs/2403.15115)).

Resolve the source of truth per the method doc's ladder: if the consuming
project declares a communication or writing-quality convention in its own
`CLAUDE.md` / `.claude/rules/`, re-anchor THAT as well and audit against it.

## The rubric this skill audits

The four axes this corrector owns, mapped onto the pointed-to maxims:

- **Quantity, both directions.** Under-informing is a finding: an asked-for
  detail, a load-bearing caveat, or a necessary step omitted. Over-informing
  is a finding too: padding, restatement, and detail the reader did not need.
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

## Delegations. Axes this skill routes elsewhere

Route each axis below by invoking the named sibling skill via the Skill tool.

- **Quality (truthfulness, evidence) → `/discipline:do-your-research`.** A
  claim's truth routes there; this skill owns how the message is shaped, not
  whether it is factually backed.
- **Pure verbosity remediation → `/discipline:tighten-your-output`.** The
  Quantity audit here NAMES padding as a finding; route large verbosity
  cleanups there rather than hand-trimming at scale here.

## Benevolence. Deliberate out-of-scope

The paper's other augmented maxim, Benevolence, is NOT audited here: it is
platform / safety-layer territory, not a communication-drift axis a
mid-session corrector can score.

## Audit targets and the dual moment

- **Two target kinds.** Audit recent agent RESPONSES and agent-authored
  ARTIFACTS alike: docs, PR bodies, prompts, commit messages, skill text.
  A buried lede in a PR body fails the same rubric as one in a chat reply.
- **Dual moment.** Valid as posture-setting at any time (the method doc's
  conversation-start case: acknowledge the discipline as active and stop,
  nothing to audit yet), AND as an audit once output exists.

## Gotchas

- **Correct and unhelpful is still a finding.** An answer can be true, and
  fail Relation or Quantity. Right, but not to the question asked, or buried
  under detail the reader did not need. Judge by what the reader needed, not
  by whether the words are accurate.
- **The buried lede is the common miss.** The answer is present but below the
  setup; Relation and Manner both fail when the reader has to dig for the
  thing they asked for. Lead with it.
