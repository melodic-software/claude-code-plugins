# Rewrite guide

Fix-time guidance for `/ai-slop:audit fix`: what to write INSTEAD of a flagged tell. The
[catalog](catalog.md) decides what flags; this file decides what replaces it. Loaded at fix
step 1, applied under the same semantic-diff guard as every rewrite (meaning over style: a
rewrite that changes what a sentence asserts is skipped and recorded).

<!-- ai-slop-ignore-file: this guide quotes the tells it rewrites; scanning it flags its own examples -->

## Attribution and license

Adapted from the `unslop` skill in Cursor's `pstack` plugin,
[cursor/plugins `pstack/skills/unslop/SKILL.md`](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md),
pinned at commit [`99559f2`](https://github.com/cursor/plugins/blob/99559f2f52047978602ef365589275831e76af07/pstack/skills/unslop/SKILL.md)
(2026-08-02), MIT-licensed. Changes were made: the guidance is reorganized around this plugin's
fix flow and its detection rules, and pattern material that duplicates the catalog is omitted.

## Substitution guardrails

A rewrite that swaps one tell for another is not a fix:

- **Em dashes** become periods or commas, or the sentence is restructured. Never parentheses,
  never en dashes, never a spaced hyphen: each of those is the same interruption wearing a
  different mark. If the thought needs separation, end the sentence.
- **Colon crutches** are not fixed by swapping the colon for a dash or semicolon. Rewrite so the
  point stands without the two-part framing: "If you're coming from traditional automation:
  instead of registering event handlers, you describe conditions" becomes "Describing when the
  scheduler should fire works best as plain English." Colons before a list or an example stay.
- **Triads** collapse toward the single strongest item (the fix flow's standing rule), not
  toward a two-item list that keeps the cadence.
- **Vocabulary swaps** must not reach for the next-fanciest synonym. "Utilize" becomes "use",
  not "employ".

## Plain speech

The positive target the tells deviate from. Apply these to every sentence a finding touches,
not only to the flagged words:

- **Say what it does, not how it feels.** "The database stays close at hand" names a feeling;
  "`.toSQL()` returns the exact string sent to the database" names a mechanism. Ask what the
  sentence tells the reader to do or know, then write that. If it cannot be restated as a
  concrete instruction, fact, or number, cut it. And if it could appear unchanged in another
  project's docs, it says nothing about this one: cut it.
- **One idea per sentence.** If the reader must backtrack to parse it, break it in two or drop
  clauses.
- **Active voice, named actor.** "Queries are validated" becomes "the compiler validates
  queries". Passive stays only when the actor is unknown or genuinely does not matter.
- **Cut the adverb or upgrade the verb.** "Runs quickly" becomes "is fast" or the measured
  number; "significantly improves" becomes the delta. An adverb propping up a weak verb means
  the verb is wrong.
- **Prefer the plain word.** "Utilize" and "leverage" become "use", "facilitate" becomes "help",
  "numerous" becomes "many", "in the event that" becomes "if".

## Replacements for flagged phrases

- **Filler** (`rule-filler-phrases`): "in order to" becomes "to"; "due to the fact that" becomes
  "because"; "it is important to note that", "it is worth noting that", and "it should be noted
  that" are deleted, the note standing on its own.
- **Stacked hedges** (`rule-stacked-hedging`): keep one hedge that states the real uncertainty.
  "Could potentially possibly be argued that it might" becomes "may".
- **Chat residue** (`rule-chatbot-artifacts`): delete the sentence; committed prose has no chat
  partner. If it carried content ("let me know if the retry loop misbehaves"), keep the content
  in document register ("known risk: the retry loop").
- **Metaphor jargon** (`rule-abstract-metaphor-jargon`): pick the concrete word. "Substrate"
  becomes "base"; "wedge in" becomes "add"; "vector" becomes "way" or "method"; "gold-plating"
  becomes "more than the job needs"; "ratchet" becomes the mechanism's real name or "a limit
  that only tightens"; "endgame" becomes "the last phase"; "north star" becomes "the goal".
  Leave domain-literal uses alone: a harness that is a test harness keeps its name.

## Adding voice

Removing tells is half the job: sterile, voiceless prose is just as recognizable. Where the
document's register allows it (a README's narrative sections, a design doc's tradeoffs, a
changelog's rationale; not API reference tables):

- **Have a position.** React to facts instead of neutrally listing pros and cons.
- **Vary rhythm.** Short sentences. Then longer ones that take their time.
- **Acknowledge complexity.** "Impressive but also kind of unsettling" beats "impressive".
- **First person is allowed** where the document has an author's voice.
- **Be specific.** Not "this is concerning" but the concrete thing that concerns.

This section never overrides meaning preservation: voice is added in HOW a kept claim is
phrased, never by inventing new claims during a fix pass.

## Self-audit

Last pass over each rewritten file, before the semantic-diff verification: read it asking "what
still makes this read machine-written?" and fix what surfaces, whether or not a rule flagged
it. Findings from this pass are reported like rubric findings (quoted text, catalog entry when
one fits).
