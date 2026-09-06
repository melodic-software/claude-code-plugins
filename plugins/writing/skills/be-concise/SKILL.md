---
description: "Reshape prose so a scanning reader gets the point: bottom line first, no more words than the meaning needs, structure that survives scanning, factual tone. Two modes. Invoked bare it sets a standing posture for everything written afterwards; given any target it reshapes that text and reports before and after word counts. Never drops a decision, number, ask, error or warning, and never edits an already-posted record in place unless told to. Use when: 'write this for the PO', 'shorten this ticket', 'make this scannable', 'bottom line first', 'nobody will read this', 'rewrite this PR description for reviewers', or before writing anything a person reads in a tracker, a pull request, a doc, or a status update. Not for: in-flight chat and code terseness (discipline:tighten-your-output), word-level trimming of a repo .md (docs-hygiene:compress), restructuring without shortening (adhd:clarify), or doc genre and language standards at authoring time (docs-hygiene:write-for-humans)."
argument-hint: "[target] (empty sets the posture; otherwise pasted text, a file, a URL, a PR, or a ticket)"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Reshape prose for a scanning reader. Bottom line first, about half the words
---

# Be concise

## The reader model this rests on

People scan. They read a fifth to under a third of the words on a page, they
read the first sentence of a paragraph and skip the rest, and they decide
whether to keep going within a few seconds. Every rule below exists because of
that one fact, not because short writing is a virtue.

The measured effect was large, and the evidence behind it is thin. One 1997
study, 51 users, never replicated: cutting a page to about half its words
raised measured usability by 58% on its own, making it scannable raised it 47%,
stripping promotional language raised it 27%, and doing all three raised it
124%. State it that way when it comes up rather than as settled fact. What
holds the rules up is that six independent style authorities prescribe the same
things. Details and sources:
[`reference/doctrine.md`](reference/doctrine.md) and
[`reference/sources.md`](reference/sources.md).

## Two modes

**Bare invocation sets a standing posture.** Apply the four properties to every
piece of reader-facing prose you write for the rest of the session, without
being asked again. Say once that the posture is on, then stop narrating it.

**With a target, reshape that text.** The target is whatever you can resolve
with the tools you have: pasted text, a file, a URL, a pull request, a tracker
item. Do not ask which kind it is when you can just look.

## The four properties

Read [`reference/doctrine.md`](reference/doctrine.md) for the rules and their
thresholds. In brief:

1. **The point comes first.** The conclusion, the ask, or the status opens the
   text. A reader who stops after one sentence still knows what you needed.
2. **No more words than the meaning needs.** Aim at about half a first draft.
   Cut expletives, intensifiers, redundancy, and clauses that add nothing.
3. **Structure that survives scanning.** Informative headings, one idea per
   paragraph, lists where a reader scans for facts.
4. **Factual tone.** No hype, no selling, no filler.

Properties 2 and 4 are universal: they improve any prose, including text only
an agent will read. Properties 1 and 3 are for human readers, and are the ones
`docs-hygiene:write-for-agents` deliberately does not want.

## What never gets cut

Completeness is a floor, not a trade-off. Agency-guidance drafting, safety
procedure standards, commit-message doctrine and Claude Code's own concise
output style all say the same thing, and this skill inherits it.

Never drop, in any mode:

- A decision, a number, a date, a name, or an explicit ask.
- An error, a warning, or anything about a destructive or irreversible action.
- A caveat that changes what the reader would do.
- Any structural contract the destination imposes. A pull-request body that
  needs a closing keyword line and four named sections still has them
  afterwards.

When brevity and completeness genuinely conflict, put the bottom line first and
keep the full record below it or one link away. Do not resolve it by deleting.

## Reader and destination are inferred, not looked up

Before reshaping, settle three things from what is in front of you. Ask only
when the text itself cannot tell you.

- **Who reads this.** An executive skimming for status needs a different first
  sentence than a reviewer who has to act on specifics.
- **Where it lands.** A tracker comment, a pull-request body, a changelog entry
  and a README each carry conventions and sometimes a hard contract.
- **What must survive.** The completeness floor above, plus anything the
  destination's own gate requires.

There is no fixed table of destinations here on purpose. The doctrine is
general; a table would go stale and would answer only the cases someone
happened to list.

## Never edit a posted record in place

If the text is already published, in a ticket, a comment, a pull request, or
anywhere a reader may have seen it, do not silently overwrite it. Offer the
reshaped version and let the user decide. Overwriting destroys the audit trail
that every completeness source above treats as load-bearing.

The exception is an explicit instruction to edit it in place.

## Guard the meaning

For anything longer than a few paragraphs, verify the rewrite with a
fresh-context semantic diff before handing it over. Dispatch a subagent that
did not write the rewrite, give it the before and after text, and ask it to
report only:

- **SEMANTIC LOSS.** Something the original stated that the rewrite does not.
- **DROPPED DECISION, NUMBER, OR ASK.** The class restructuring introduces:
  content that survived as words but moved out of the place a reader would
  look, or vanished in a merge of two paragraphs.
- **AMBIGUITY.** Something the rewrite made less determinate.
- **FALSE POSITIVE.** A flagged item that is actually fine.

Every finding cites the exact text. Restore anything confirmed lost, then hand
over. For a short comment, show the before and after inline instead; a subagent
round-trip costs more than the reader's whole message.

## Report the result

Every reshape ends with the before and after word counts, as a plain count, not
a percentage claim. It is the one measure with real evidence behind it, and it
lets the user see the size of the change without rereading both versions.

## Boundary

- **Does not shorten by dropping content.** Density is the goal, not length.
  A rewrite that loses a decision has failed even if it halves the word count.
- **Does not run in flight on chat or code.** Terseness in the current
  conversation, and code written in fewer lines, is
  `discipline:tighten-your-output` when the `discipline` plugin is installed.
- **Does not trim repo markdown word by word.** That is
  `docs-hygiene:compress` when the `docs-hygiene` plugin is installed.
- **Does not restructure a dense message without shortening it.** Chunking a
  decision-heavy artifact one decision at a time is `adhd:clarify` when the
  `adhd` plugin is installed.
- **Does not reshape agent-facing instruction prose.** A skill body, a rules
  file, or any text written for a model to follow is
  `docs-hygiene:write-for-agents` when the `docs-hygiene` plugin is installed.
  Take the two universal properties there and leave the human-only ones behind.
- **Does not set documentation genre or language standards.** Diataxis type,
  terminology, and controlled-language rules at authoring time are
  `docs-hygiene:write-for-humans` when the `docs-hygiene` plugin is installed.
- **Does not detect AI-writing tells.** Em dashes, chatbot phrasing and the
  rest of that catalog are `ai-slop:audit` when the `ai-slop` plugin is
  installed. This skill inherits whatever that plugin's config says; it adds no
  punctuation rule of its own.
- **Ships no detector script and gates nothing in CI.** Judgment plus the word
  count. A deterministic detector is a recorded post-V1 item.

## Gotchas

- **Halving the words is not the goal on a text that is already dense.** The
  target is a first draft, not a finished one. Re-running this on its own
  output cuts meaning.
- **Lists are for facts a reader scans, not for reasoning a reader follows.**
  Turning an argument into bullets breaks the thread that made it an argument.
  Bold a few keywords per screen at most, and never bold a restatement of the
  line it sits on.
- **A reader who needs the detail is not served by a summary that hides it.**
  Bottom line first means first, not instead.
- **Do not report a percentage improvement.** The word-count delta is
  measurable; a usability claim about this particular rewrite is not.

## Attribution

The rules are paraphrased, never copied, from Nielsen Norman Group's research
on concise, scannable and objective web writing, GOV.UK content design, the US
federal plain-language guidelines, Google's and Microsoft's style guides, and
BLUF. Each carries a drift stamp in
[`reference/sources.md`](reference/sources.md). No upstream article text is
vendored here.
