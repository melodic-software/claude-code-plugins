# Rewrite guide

Fix-time guidance for `/ai-slop:audit fix`: what to write INSTEAD of a flagged tell. The
[catalog](catalog.md) decides what flags; this file decides what replaces it. Loaded at fix
step 1, applied under the same semantic-diff guard as every rewrite (meaning over style: a
rewrite that changes what a sentence asserts is skipped and recorded).

<!-- ai-slop-ignore-file: this guide quotes the tells it rewrites; scanning it flags its own examples -->

Inspired by
[Cursor's `unslop` skill](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md).

## Non-evasion posture

The source catalog's own upstream warns that its signs are descriptive, not prescriptive: "do
not merely treat these signs as the problems to be fixed; that could just make detection
harder." This guide's purpose is house style, and honesty about AI assistance lives in
disclosure and accountability, not in how the prose reads. The operational test for every
rewrite: **would this edit improve the prose if AI detection did not exist?** An edit that only
launders provenance fails the test and is not applied. Perplexity and burstiness never appear
in this guide as targets: they are detector-side statistics, defined relative to a model and
tokenizer, and cannot function as writing goals.

## Legitimate-hit taxonomy (when NOT to rewrite)

Five classes of detector hit are legitimate as written. The detector's quotation exemption
(catalog "Quotation exemption") already declines the first two mechanically wherever the text
is blockquoted, double-quoted, or backticked; the classes are listed here so a fix pass
recognizes the residue that still surfaces and closes it with the right tool instead of a
rewrite:

1. **Verbatim quotes** (a source's own words, block or inline). Never rewrite a quotation.
   Residue closure: the fenced `ai-slop-ignore-start/end` pair with a reason, only where the
   quote form escapes the exemption (single-quoted, or unmarked quoted prose).
2. **Text that documents the tell it bans** (style guides, forbidden-phrase lists, detection
   criteria, before/after examples, changelog entries citing the phrase a fix removed). The
   use/mention boundary: mentioning a tell is not using it. Marker-free closure: backtick or
   double-quote the mention — inline code spans and quoted spans are exempt for wording rules.
3. **Generated files** whose prose is owned by a generator. Fix the generator or its source,
   never the output; closure is the config path exclude (`excluded_paths`) or, for one rule,
   `rule_allowed_paths`.
4. **Factual model-spec statements** ("the model's knowledge cutoff is May 2026" as a spec
   fact, not an assistant's own disclaimer). Closure: inline marker with the reason
   `factual model spec, not assistant-frame disclaimer`, or `rule_allowed_paths` for a corpus
   that documents models.
5. **Deliberate voice** (a contrast or construction that is the author's point, where the
   plain restatement blunts it). Closure: inline marker with a reason saying so. Use sparingly;
   most flagged lines are not this.

Suppression hygiene: every marker carries a reason (the fix flow requires it), and a marker
whose line no longer trips any rule is residue to remove on the next pass.

## Risky rewrite classes (disambiguate before restating)

Three flagged constructions carry systematic meaning-change risk. Each demands a
disambiguation step BEFORE the rewrite, and the semantic-diff verifier is told to treat these
classes adversarially:

- **Negative parallelism** ("not just X but Y", "not only X, but also Y"): the construction is
  ambiguous between "X alone is insufficient (X still counts)" and "X is excluded". A positive
  restatement must pick one, and picking wrong inverts a criterion — a dogfood pass turned
  "(not just facilitator)" into a blanket exclusion that external review caught. Resolve the
  intended reading from surrounding context first; when the context does not settle it, keep
  the original and flag the ambiguity to the author instead of guessing.
- **Triad collapse**: keep the single strongest item ONLY when the surviving text still entails
  every deleted item. An enumeration whose items are independent claims ("no endpoint tables,
  no scope lists, no prices") loses assertions when collapsed; restate without the cadence
  ("no endpoint tables, scope lists, or prices") rather than dropping items.
- **Quoted operative phrases**: a hedge, discriminator, or trigger phrase inside quotation
  marks is load-bearing verbatim text ("what could possibly happen" as one arm of a
  read-vs-run discriminator). Never edit inside the quotes; the quotation exemption now keeps
  wording rules out of them.

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
  that only tightens"; "endgame" becomes "the last phase"; "north star" becomes "the goal";
  "evacuate" becomes "move out".
  Leave domain-literal uses alone: a harness that is a test harness keeps its name.
- **Model-era metaphor cues** (same rule, "Model-era additions" layer): "load-bearing" becomes
  what actually depends on the thing ("three consumers parse this line" beats "this line is
  load-bearing"); "seam" becomes the concrete interface, file, or boundary it stands in for.
  A Feathers seam in refactoring prose and a deliberately named load-bearing invariant are
  terms of art — leave them.
- **Model-era phrases** (`rule-model-era-phrases`): state the point without the stock
  construction. "That's the unlock" becomes the mechanism it gestures at ("caching the parse
  is what makes this fast"); "the honest take is" is deleted, the take standing on its own;
  "X is the part most people skip" becomes why X matters ("X fails silently when skipped").
  The ranked-punchline closer ("two observations, and one is load-bearing") becomes the
  observations themselves, ordered by importance — the ranking shows in the order, not in a
  self-grading clause.

## Adding voice

Removing tells is half the job: sterile, voiceless prose is just as recognizable. This pass is
an explicit step of the fix flow, not an optional flourish, and it is **register-gated**: it
applies where the document has an author's voice (a README's narrative sections, a design
doc's tradeoffs, a changelog's rationale) and stays out of API reference tables, operative
skill instructions, and generated content. The techniques are pre-LLM craft with real
authority pedigree (Orwell's plain-language rules, Williams on clarity, Zinsser on
simplicity, Google and Microsoft's developer style guides; the print authorities are cited as
craft consensus rather than page-level references):

- **Have a position.** React to facts instead of neutrally listing pros and cons.
- **Vary rhythm.** Short sentences. Then longer ones that take their time. Docs-register
  constraint: Google's global-audience guidance prefers consistently short, translatable
  sentences and consistent terminology, so in reference prose vary structure less and lead
  with the point instead.
- **Acknowledge complexity.** "Impressive but also kind of unsettling" beats "impressive".
- **First person is allowed** where the document has an author's voice.
- **Be specific.** Not "this is concerning" but the concrete thing that concerns. In technical
  prose, specificity bows to terminology consistency: one name per concept, reused exactly.

Adapted from Cursor's unslop "Adding soul" list (six bullets there). The dropped sixth, "Let
some mess in", is the one that fails this guide's improve-it-anyway test: deliberately leaving
imperfections optimizes how the prose scores rather than how it reads, which is the evasion
posture this guide refuses. The drop is deliberate; do not re-add it.

This section never overrides meaning preservation: voice is added in HOW a kept claim is
phrased, never by inventing new claims during a fix pass.

## Self-audit

Last pass over each rewritten file, before the semantic-diff verification: read it asking "what
still makes this read machine-written?" and fix what surfaces, whether or not a rule flagged
it. Findings from this pass are reported like rubric findings (quoted text, catalog entry when
one fits).
