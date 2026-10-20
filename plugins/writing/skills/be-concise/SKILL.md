---
description: "Reshape prose so a scanning reader gets the point: bottom line first, no more words than the meaning needs, structure that survives scanning, factual tone. Two modes. Invoked bare it sets a standing posture for everything written afterwards; given any target it reshapes that text and reports before and after word counts. Never drops a decision, number, ask, error or warning, and never edits an already-posted record in place unless told to. Use when: 'write this for the PO', 'shorten this ticket', 'make this scannable', 'bottom line first', 'nobody will read this', 'rewrite this PR description for reviewers', or before writing anything a person reads in a tracker, a pull request, a doc, or a status update. Not for: in-flight chat and code terseness (discipline:tighten-your-output), word-level trimming of a repo .md (docs-hygiene:compress), restructuring without shortening (adhd:clarify), or doc genre and language standards at authoring time (docs-hygiene:write-for-humans)."
argument-hint: "[target]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Reshape prose for a scanning reader. Bottom line first, about half the words
---

# Be concise

## Two modes

**Bare invocation sets a standing posture.** Apply the four properties to all
reader-facing prose you write for the rest of the session. Say once that the
posture is on, then stop narrating it.

**With a target, reshape that text.** The target is anything your tools can
resolve: pasted text, a file, a URL, a pull request, a tracker item. Look
instead of asking which kind it is.

## The four properties

Read [`reference/doctrine.md`](reference/doctrine.md) for the rules and their
thresholds. In brief:

1. **The point comes first.** The conclusion, ask, or status opens the text, so
   a reader who stops after one sentence still knows what you needed.
2. **No more words than the meaning needs.** Aim at about half a first draft.
   Cut expletives, intensifiers, redundancy, and clauses that add nothing.
3. **Structure that survives scanning.** Informative headings, one idea per
   paragraph, lists where a reader scans for facts.
4. **Factual tone.** No hype, no selling, no filler.

Properties 2 and 4 apply to any prose, including text only an agent reads.
Properties 1 and 3 are for human readers only.

Readers scan, which is why these rules exist. The evidence for the size of the
effect is one unreplicated 1997 study of 51 users; say so when it comes up
rather than presenting it as settled. Details and sources: the doctrine file
and [`reference/sources.md`](reference/sources.md).

## What never gets cut

Completeness is a floor, not a trade-off. Never drop, in any mode:

- A decision, a number, a date, a name, or an explicit ask.
- An error, a warning, or anything about a destructive or irreversible action.
- A caveat that changes what the reader would do.
- A structural contract the destination imposes. A pull-request body that
  needs a closing keyword line and four named sections still has them
  afterwards.

When brevity and completeness conflict, put the bottom line first and keep the
full record below it or one link away. Never resolve it by deleting.

## Infer reader and destination

Settle three things from the text in front of you; ask only when it cannot tell
you:

- **Who reads this.** An executive skimming for status needs a different first
  sentence than a reviewer acting on specifics.
- **Where it lands.** A tracker comment, a pull-request body, a changelog entry
  and a README each carry conventions, sometimes a hard contract.
- **What must survive.** The completeness floor, plus anything the
  destination's own gate requires.

Apply the general doctrine; keep no fixed table of destinations, which would go
stale and answer only the cases someone listed.

## Never edit a posted record in place

If the text is already published (a ticket, a comment, a pull request, anywhere
a reader may have seen it), do not overwrite it. Offer the reshaped version and
let the user decide, because overwriting destroys the audit trail. Edit in
place only on an explicit instruction to.

## Guard the meaning

For anything longer than a few paragraphs, verify the rewrite with a
fresh-context semantic diff before handing it over. Dispatch a subagent that
did not write the rewrite, give it the before and after text, and have it
report only:

- **SEMANTIC LOSS.** Something the original stated that the rewrite does not.
- **DROPPED DECISION, NUMBER, OR ASK.** Content that survived as words but
  moved out of the place a reader would look, or vanished when two paragraphs
  merged.
- **AMBIGUITY.** Something the rewrite made less determinate.
- **FALSE POSITIVE.** A flagged item that is actually fine.

Every finding cites the exact text. Restore anything confirmed lost, then hand
over. For a short comment, show the before and after inline instead; a
subagent round-trip costs more than the reader's whole message.

## Report the result

End every reshape with the before and after word counts as plain counts, never
a percentage claim.

## Boundary

- **Never shortens by dropping content.** Density is the goal, not length. A
  rewrite that loses a decision has failed even if it halves the word count.
- **In-flight chat and code terseness:** `discipline:tighten-your-output` when
  the `discipline` plugin is enabled.
- **Word-by-word trimming of repo markdown:** `docs-hygiene:compress` when the
  `docs-hygiene` plugin is installed.
- **Restructuring a dense message without shortening it** (chunking a
  decision-heavy artifact one decision at a time): `adhd:clarify` when the
  `adhd` plugin is enabled.
- **Agent-facing instruction prose** (a skill body, a rules file, any text a
  model follows): `docs-hygiene:write-for-agents` when the `docs-hygiene`
  plugin is installed. Take properties 2 and 4 there and leave 1 and 3 behind.
- **Documentation genre and language standards** (Diataxis type, terminology,
  controlled language at authoring time): `docs-hygiene:write-for-humans` when
  the `docs-hygiene` plugin is installed.
- **AI-writing tells** (em dashes, chatbot phrasing, the rest of that catalog):
  `ai-slop:audit` when the `ai-slop` plugin is enabled. This skill inherits
  that plugin's config and adds no punctuation rule of its own.
- **No detector script, no CI gate.** Judgment plus the word count.

## Gotchas

- **Halving the words is not the goal on text that is already dense.** The
  target is a first draft. Re-running this on its own output cuts meaning.
- **Lists are for facts a reader scans, not reasoning a reader follows.**
  Bulleting an argument breaks its thread. Bold a few keywords per screen at
  most, and never bold a restatement of the line it sits on.
- **Bottom line first means first, not instead.** A reader who needs the
  detail is not served by a summary that hides it.
- **Do not report a percentage improvement.** The word-count delta is
  measurable; a usability claim about this rewrite is not.

## Attribution

The rules paraphrase, never copy, Nielsen Norman Group's research on concise,
scannable and objective web writing, GOV.UK content design, the US federal
plain-language guidelines, Google's and Microsoft's style guides, and BLUF.
Each carries a drift stamp in [`reference/sources.md`](reference/sources.md).
No upstream article text is vendored here.
