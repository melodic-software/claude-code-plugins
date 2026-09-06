---
description: "Re-anchor terseness discipline, say markdown in fewer words without semantic loss, write code in fewer lines when readability holds, then audit the work in flight for avoidable verbosity and tighten it. Use when: 'tighten your output', 'tighten this', 'too verbose', 'say it in fewer words', 'this is bloated', 'trim the code', 'simpler form', 'cut the wordiness', 'be more concise', or at conversation start on prose- or code-heavy work."
user-invocable: true
disable-model-invocation: false
metadata:
  discipline-batch: core  # every session produces output that can tighten; runs last so it never tightens text a later corrector rewrites
  discipline-batch-rank: 110
  workflow-stage: anytime
  summary: Tighten prose and code. Fewer words, no semantic loss
---

# Tighten your output

A drift corrector for terseness discipline. The method, re-anchor, audit
the work in flight, correct forward, report, and the tone that firing this
is not an accusation, lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to terseness discipline.

## The discipline this re-anchors

Say it in fewer words or lines when nothing of value is lost. Two surfaces,
resolved separately per the method doc's ladder.

### Code, a standards convention owns this

The source of truth is the consuming organization's simpler-code
convention: prefer the smaller form when it costs no correctness,
readability, test coverage, observability, or convention conformance. Read
it where it lives; re-anchor its two load-bearing parts rather than
restating them:

- its **named failure modes**, the canonical smells a reduction must not
  introduce (speculative generality, the wrong abstraction, YAGNI);
- its **constraints never traded for line count**. Clarity, test coverage,
  error handling at boundaries, established conventions, and observability
  survive every cut.

When the consuming project declares no such convention, re-anchor that same
shape as the portable baseline: fewer lines is the default only when none
of those constraints is spent to get there.

### Markdown. A flagged standards gap with a routing owner

Say the same thing in fewer words with **no semantic loss**. Drop filler,
hedging, and restatement, never a directive, qualifier, threshold, or
example. Tightening selects what to include; it does not compress prose into
fragments, abbreviations, arrow chains, or jargon, and it keeps complete
sentences a reader who did not watch the work can follow. When brevity and
readability conflict, readability wins. Unlike the code side, prose terseness usually has **no dedicated
standards convention** to discipline: when the consuming project's standards
source declares one, route through it; when it does not, that is still a
flagged gap (a candidate upstream standards addition), not license to invent
a rubric in this skill.

The gap has a routing owner. `/writing:be-concise` holds the doctrine for
prose a person reads, a ticket comment, a pull-request body, a doc, a status
update, and it is where reader-facing text goes when the `writing` plugin is
installed. Without it, reduce against the discipline above and say the
point-first shape went unapplied. The operative safety net for prose
reduction is a compress capability's semantic-diff discipline either way:
route batch prose work there when that capability is installed, and otherwise
run that same discipline in-thread rather than hand-rolling criteria here.

## Audit. What to look for

Name concrete, located findings (per the method doc's step 2, self-audit):

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

## Routing, where batch and proactive work live

- **Prose a person reads → `/writing:be-concise`** when the `writing` plugin
  is installed. It owns the point-first, scannable shape those readers need,
  which this corrector does not. Without that plugin, fall back to the
  markdown discipline above.
- **Batch prose remediation → the docs-hygiene compress capability** when
  that plugin is installed (its semantic-diff safety net is the guardrail for
  large prose cuts); otherwise run that same semantic-diff discipline as an
  explicit in-thread pass rather than hand-rolling a rubric here.
- **Batch code reduction → the code-tidying batch-simplify capability** over a
  change set when that plugin is installed; otherwise reduce in-thread against
  the simpler-code convention, spending no clarity, test, error handling,
  convention, or observability to do it.
- **Proactive code-side enforcement is NOT here.** It lives in review and
  design gates that cite the simpler-code convention; this corrector
  re-anchors the discipline and corrects the work in flight, it does not
  stand in for those gates.

## Trigger ownership. One owner per brevity phrase

Two standing brevity postures exist, so the vocabularies are split rather
than shared. The test is what the phrase names: the output in front of us, or
an artifact a reader will open. A phrase that names neither is a register
directive, and its default target is the conversation, so it stays here.
Every phrase has exactly one owner, and neither description claims a phrase
this table gives the other.

| Phrase | Owner | Why |
|---|---|---|
| `'tighten your output'` | this skill | Names the assistant's own output |
| `'tighten this'` | this skill | Unbound target, so the thing in flight |
| `'too verbose'` | this skill | A verdict on what was just produced |
| `'say it in fewer words'` | this skill | Re-saying inside the conversation |
| `'this is bloated'` | this skill | Unbound target, most often code |
| `'trim the code'` | this skill | Code terseness |
| `'simpler form'` | this skill | Code terseness |
| `'cut the wordiness'` | this skill | A register directive, no artifact named |
| `'be more concise'` | this skill | A register directive, no artifact named |
| `'write this for the PO'` | `writing:be-concise` | Names the reader |
| `'shorten this ticket'` | `writing:be-concise` | Names the artifact |
| `'make this scannable'` | `writing:be-concise` | A property only a human reader needs |
| `'bottom line first'` | `writing:be-concise` | A property only a human reader needs |
| `'nobody will read this'` | `writing:be-concise` | Names the reader |
| `'rewrite this PR description for reviewers'` | `writing:be-concise` | Names the artifact and its readers |

Once either skill is loaded, route by the target in front of you, not by the
phrase that reached it; the sections above say where.

## What this skill does NOT do

- **Does not trade a constraint for brevity.** A shorter form that spends
  clarity, a test, error handling, a convention, or observability is a wrong
  reduction, not a win.
- **Does not invent markdown-terseness criteria.** The consuming project's
  standard is still a flagged gap; the skill routes reader-facing prose to
  `/writing:be-concise` when the `writing` plugin is installed, and to the
  compress capability's discipline otherwise, rather than manufacturing its
  own rubric.
- **Does not fabricate a finding.** Work already at its tight form audits
  clean; say so.

## Gotchas

- Terseness is not duplication. Removing a second copy of a fact is
  `/discipline:point-dont-copy`; removing wasted words from a single copy is
  this skill.
- The failure mode is over-cutting: a "concise" edit that quietly drops a
  qualifier or a boundary case has traded meaning for length. Judge every
  cut by what it costs, not by how many words it saves.
