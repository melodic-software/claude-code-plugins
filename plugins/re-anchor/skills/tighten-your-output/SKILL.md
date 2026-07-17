---
name: tighten-your-output
description: "Re-anchor terseness discipline — say markdown in fewer words without semantic loss, write code in fewer lines when readability holds — then audit the work in flight for avoidable verbosity and tighten it. Use when: 'tighten your output', 'tighten this', 'too verbose', 'say it in fewer words', 'this is bloated', 'trim the code', 'simpler form', 'cut the wordiness', 'be more concise', or at conversation start on prose- or code-heavy work."
user-invocable: true
disable-model-invocation: false
---

# Tighten your output

A drift corrector for terseness discipline. The method — re-anchor, audit
the work in flight, correct forward, report, and the tone that firing this
is not an accusation — lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to terseness discipline.

## The discipline this re-anchors

Say it in fewer words or lines when nothing of value is lost. Two surfaces,
resolved separately per the method doc's ladder.

### Code — a standards convention owns this

The source of truth is the consuming organization's simpler-code
convention: prefer the smaller form when it costs no correctness,
readability, test coverage, observability, or convention conformance. Read
it where it lives; re-anchor its two load-bearing parts rather than
restating them:

- its **named failure modes** — the canonical smells a reduction must not
  introduce (speculative generality, the wrong abstraction, YAGNI);
- its **constraints never traded for line count** — clarity, test coverage,
  error handling at boundaries, established conventions, and observability
  survive every cut.

When the consuming project declares no such convention, re-anchor that same
shape as the portable baseline: fewer lines is the default only when none
of those constraints is spent to get there.

### Markdown — no standards doc yet (flagged gap)

Say the same thing in fewer words with **no semantic loss** — drop filler,
hedging, and restatement, never a directive, qualifier, threshold, or
example. Unlike the code side, prose terseness usually has **no dedicated
standards convention** to re-anchor: when the consuming project's standards
source declares one, route through it; when it does not, treat that as a
flagged gap (a candidate upstream standards addition), not license to invent
a rubric in this skill. The operative safety net for prose reduction is a
compress capability's semantic-diff discipline — route batch prose work
there rather than hand-rolling criteria here.

## Audit — what to look for

Name concrete, located findings (per the method doc's step 2):

- prose padded with filler, hedging, or a restatement of what an adjacent
  sentence already said;
- code carrying speculative parameters, dead branches, or hand-rolled
  boilerplate a built-in would replace;
- a long form kept where a shorter one loses nothing of value.

Correct each forward now, but only where the reduction is free: tighten the
prose without dropping a directive/qualifier/threshold/example, and shrink
the code without spending clarity, tests, error handling, conventions, or
observability. When a cut would cost any of those, leave the longer form and
say why.

## Routing — where batch and proactive work live

- **Batch prose remediation → the docs-hygiene compress capability** (its
  semantic-diff safety net is the guardrail for large prose cuts).
- **Batch code reduction → the simplify capability** over a change set.
- **Proactive code-side enforcement is NOT here.** It lives in review and
  design gates that cite the simpler-code convention; this corrector
  re-anchors the discipline and corrects the work in flight, it does not
  stand in for those gates.

## What this skill does NOT do

- **Does not trade a constraint for brevity.** A shorter form that spends
  clarity, a test, error handling, a convention, or observability is a wrong
  reduction, not a win.
- **Does not invent markdown-terseness criteria.** The markdown standard is
  a flagged gap; the skill routes to the compress capability's discipline
  rather than manufacturing its own rubric.
- **Does not fabricate a finding.** Work already at its tight form audits
  clean; say so.

## Gotchas

- Terseness is not duplication. Removing a second copy of a fact is
  `/re-anchor:point-dont-copy`; removing wasted words from a single copy is
  this skill.
- The failure mode is over-cutting: a "concise" edit that quietly drops a
  qualifier or a boundary case has traded meaning for length. Judge every
  cut by what it costs, not by how many words it saves.
