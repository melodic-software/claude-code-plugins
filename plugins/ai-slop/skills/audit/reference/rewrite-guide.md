# Rewrite guide

Fix-time guidance for `/ai-slop:audit fix`: what to write INSTEAD of a flagged tell. The
[catalog](catalog.md) decides what flags; this file decides what replaces it. Loaded at fix
step 1, applied under the same semantic-diff guard as every rewrite (meaning over style: a
rewrite that changes what a sentence asserts is skipped and recorded).

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

Five classes of detector hit are legitimate as written. What the detector skips depends on the
rule's class (catalog "Quotation exemption"; the detector's rule registry assigns the class):

- Every rule skips fenced code, inline code spans, and ignore-marked lines and blocks.
- Wording rules (pattern and density) also skip blockquote lines and straight double-quoted
  spans.
- Typography rules (em dash, emoji formatting, curly artifacts, citation artifacts, `utm_*`
  params) scan blockquotes and double-quoted spans.

The classes are listed here so a fix pass recognizes the residue that still surfaces and closes
it with the right tool instead of a rewrite:

1. **Verbatim quotes** (a source's own words, block or inline). Never rewrite a quotation.
   Residue closure for a wording tell: the `ai-slop-ignore-start/end` pair with a reason, only
   where the quote form escapes the exemption (single-quoted, or unmarked quoted prose). A quote
   carrying a typography tell (an em dash) needs a marker in any form: the line marker on the
   same line, which works on a blockquote line, or a `-start`/`-end` pair on lines outside the
   blockquote. A start or end line prefixed with `>` matches neither marker form, and such an
   end line also fails to close a block opened outside, which declines the rest of
   the file.
2. **Text that documents the tell it bans** (style guides, forbidden-phrase lists, detection
   criteria, before/after examples, changelog entries citing the phrase a fix removed). The
   use/mention boundary: mentioning a tell is not using it. Marker-free closure: backtick the
   mention, which every rule skips. Double-quoting is marker-free for wording tells only; for a
   typography tell, only a backtick span is.
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
  restatement must pick one, and picking wrong inverts the criterion. Resolve the intended
  reading from surrounding context first; when the context does not settle it, keep the original
  and flag the ambiguity to the author instead of guessing.
- **Triad collapse**: keep the single strongest item ONLY when the surviving text still entails
  every deleted item. An enumeration whose items are independent claims ("no endpoint tables,
  no scope lists, no prices") loses assertions when collapsed; restate without the cadence
  ("no endpoint tables, scope lists, or prices") rather than dropping items.
- **Quoted operative phrases**: a hedge, discriminator, or trigger phrase inside quotation
  marks carries its meaning word for word ("what could possibly happen" as one arm of a
  read-vs-run discriminator). Never edit inside the quotes; the quotation exemption keeps
  wording rules out of straight double quotes, while typography rules still scan them.

## Substitution guardrails

A rewrite that swaps one tell for another is not a fix:

- **Em dashes** become periods or commas, or the sentence is restructured. Never parentheses,
  never en dashes, never a spaced hyphen: each of those is the same interruption wearing a
  different mark. When the aside needs to stand apart, give it a sentence of its own.
- **Colon crutches** are not fixed by swapping the colon for a dash or semicolon. Drop the
  two-part staging and state the point once: "The short version: the job retries three times
  before it pages anyone" becomes "The job retries three times before it pages anyone." The
  mid-sentence colon as a connector ("If you're coming from X: here's the mapping") is a crutch
  for a comparison the sentence didn't need. Rewrite so the point stands alone: rephrase it, or
  split it into two sentences. A colon that
  introduces a list or an example is not a crutch and stays, and so does a terse `rule: reason`
  line in a list of operative rules (the catalog's `rule-colon-crutch` boundary).
- **Triads** collapse toward the single strongest item (the fix flow's standing rule), not
  toward a two-item list that keeps the cadence.
- **Vocabulary swaps** must not reach for the next-fanciest synonym. "Utilize" becomes "use",
  not "employ".

## Sweep order

Read the text once for what it's actually trying to say. You can't rewrite a sentence you
haven't understood; you'll preserve the slop's shape. Sweep in order: words, then sentences, then
punctuation and formatting, then claims. Each layer hides behind the one above it. A puffed-up
claim is hard to see until the vocabulary around it is plain. The voice pass and the closing
reread below come last, and the fresh-context semantic-diff verifier checks the result after
them.

## Plain speech

The positive target the tells deviate from. A fix reaches past the flagged words to the whole
sentence a finding touches, and puts these questions to it:

| Question | When the answer is wrong | Before, then after |
|---|---|---|
| What can the reader do or know after reading it? | Write that instead. When the answer is "nothing concrete" (no step, fact, or number), delete the sentence. | "The cache feels snappy", then "a cache hit returns in under 2 ms" |
| Would it read the same in an unrelated project's docs? | It carries no information about this project. Delete it. | "Built with performance in mind" |
| Who performs the action? | Name the actor as the subject. Keep the passive only if nobody knows the actor or the actor truly does not matter. | "The token is refreshed", then "the client refreshes the token" |
| Is an adverb holding up the verb? | The verb is the wrong one. Delete the adverb, choose a stronger verb, or give the measured figure. | "Responds very rapidly", then "responds in 40 ms"; "greatly reduces load", then "cuts load by 30%" |
| Does the reader have to go back and reread it? | It holds more than one idea. Split it, or remove clauses until one idea is left. | |
| Is there a plainer word? | Use it. See the plain-word rows below. | |

## Replacements for flagged phrases

Literal replacements, by rule:

| Rule | Flagged form | Write instead |
|---|---|---|
| Plain word, in any sentence a fix touches | "utilize", "leverage" | "use" |
| | "facilitate" | "help" |
| | "in the event that" | "if" |
| | "numerous" | "many" |
| Judgment rows: the self-audit and any sentence a fix touches, whether or not a rule fired | "delve into" | "dig into", "look at" |
| | "crucial", "pivotal" | "important", or name the consequence |
| | "foster", "cultivate" | "build", "grow" |
| | "enhance" | "improve", or the specific change |
| | "showcase" | "show" |
| | "underscore" | "show", "stress" |
| | "landscape", "tapestry" (abstract) | "field", "mix", or delete the sentence |
| | "garner" | "get", "earn" |
| | "additionally" | "also", "and" |
| `rule-copulative-avoidance` | "serves as", "stands as" | "is" |
| | "boasts", "features", "offers" | "has", where the verb means only possession: "The library boasts full TypeScript support" becomes "The library has full TypeScript support". A literal use keeps its verb: "the store offers a refund" makes an offer, and "the episode features a guest" names a role |
| `rule-filler-phrases` | "due to the fact that" | "because" |
| | "in order to" | "to" |
| | "it should be noted that", "it is worth noting that", "it is important to note that" | nothing: delete the phrase and let the note stand alone |
| `rule-stacked-hedging` | "could potentially", "might possibly" | at most one hedge, attached to what is actually uncertain: "the export may time out on tables over 10 GB"; none when the claim is known |
| `rule-abstract-metaphor-jargon` | "north star" | "the goal" |
| | "evacuate" | "move out" |
| | "endgame" | "the final phase" |
| | "vector" | "way" or "method" |
| | "substrate" | "base" |
| | "wedge in" | "add" |
| | "gold-plating" | "work beyond what the task requires" |
| | "ratchet" | "a limit that can only get stricter", or the mechanism's actual name |
| | "wedge" (a way into a market or a codebase) | "way in" |
| | "flywheel" | the actual feedback loop, described |
| | "primitive" as a noun, "harness" and "scaffolding" as metaphors, "paradigm", "nexus" | the concrete word for what it names |

The metaphor rows apply to figurative uses only. A domain-literal use keeps its word: a test
harness is still a harness.

Rewrites that need more than a lookup:

- **Chat residue** (`rule-chatbot-artifacts`): delete the sentence; committed prose has no chat
  partner. If it carried content ("let me know if the retry loop misbehaves"), keep the content
  in document register ("known risk: the retry loop").
- **Model-era metaphor cues** (`rule-abstract-metaphor-jargon`, "Model-era additions" layer):
  "load-bearing" becomes what actually depends on the thing ("three consumers parse this line"
  beats "this line is load-bearing"); "seam" becomes the concrete interface, file, or boundary it
  stands in for.
  A Feathers seam in refactoring prose and a deliberately named load-bearing invariant are
  terms of art. Leave them.
- **Model-era phrases** (`rule-model-era-phrases`): state the point without the stock
  construction. "That's the unlock" becomes the mechanism it gestures at ("caching the parse
  is what makes this fast"); "the honest take is" is deleted, the take standing on its own;
  "X is the part most people skip" becomes why X matters ("X fails silently when skipped").
  The ranked-punchline closer ("two observations, and one is load-bearing") becomes the
  observations themselves, ordered by importance. The ranking shows in the order, not in a
  self-grading clause.
- **Figure for fact** (`rule-figure-for-fact`): write the claim the image stood for, with the
  detail it left out. A comparison becomes the specific difficulty ("tuning retries is herding
  cats" becomes "each service sets its own retry limit, so one change takes five pull
  requests"). A small drama becomes the trigger and its consequence ("the on-call phone lights
  up at 3 a.m." becomes "the nightly job fails and pages the on-call engineer"). A mood becomes
  the behavior ("CI gets grumpy about lockfiles" becomes "CI fails when `package-lock.json` is
  out of date"). A slogan becomes the rule, then `because` and its reason.
- **Promotional adjectives** (`rule-promotional-language`): "Vibrant", "stunning",
  "breathtaking", "groundbreaking", "renowned", "seamless", "robust", "nestled". These are
  travel-brochure words. Describe the thing; let the reader supply the adjective.
- **Vague attribution and name-drop lists** (`rule-vague-attribution`): name the person or
  report, or delete it. Same for name-drop lists ("featured in TechCrunch, Wired, and The Verge")
  with no quote attached: pick one and say what it said, and only when the source text is at
  hand. A fix never invents a quote.
- **Generic conclusions** (`rule-generic-conclusions`): end with a specific plan, a fact, or just
  end.
- **Interface copy that fits any product** (`rule-mechanism-free-claims`, interface-copy cue):
  build the rewrite only from what the surrounding copy or the source already states about the
  product, so a competitor could not run it unchanged. With nothing stated to build from, report
  the line as a proposal for its author and write nothing. The plain-speech question "would it
  read the same in an unrelated project's docs?" is the same test. The fix rewrites the scratch
  copy only; which line ships is the project's call.
- **Over-compression** (`rule-over-compression`): rebuild each sentence around a subject and a
  verb, then add back what the reader had to guess. A symbol becomes the word it stood for ("→"
  becomes "causes" or "then", "=" becomes "is"); steps are joined by the word that says how
  they relate ("then", "because", "if"); team shorthand is expanded the first time the page uses
  it ("cfg" becomes "configuration file"); and the articles go back in. The steps stay in their
  order, and every value, name and threshold stays as written.

## Adding voice

A file with every tell removed and no voice left still reads as machine-made, so deleting tells
finishes only part of a fix. This pass is a required step of the fix flow, not decoration, and
it is **register-gated**: it applies where the document has an author's voice (a README's
narrative sections, a design doc's tradeoffs, a changelog's rationale) and stays out of API
reference tables, operative skill instructions, and generated content. The techniques are
pre-LLM craft with real authority pedigree (Orwell's plain-language rules, Williams on clarity,
Zinsser on simplicity, Google and Microsoft's developer style guides; the print authorities are
cited as craft consensus rather than page-level references).

Three techniques apply wherever the pass runs. Each one adds information the reader can use:

- **Say exactly what happens.** "The migration is risky" becomes "the migration locks the orders
  table for the whole copy". The one limit: a concrete name never replaces the established term
  for a concept, which is reused exactly.
- **Keep the cost next to the benefit.** "Fast, but it doubles memory use" tells the reader more
  than "fast".
- **Reach a verdict.** After setting out trade-offs, say which way they come out, instead of
  leaving advantages and disadvantages side by side.

Four more depend on the register:

- **Writing as "I" or "we"** belongs only in a document that has an author's voice.
- **Mixing short sentences with longer ones** that take time to develop a point suits narrative
  sections. Reference prose follows Google's global-audience guidance instead: consistently
  short, translatable sentences and consistent terms, with the point first, so vary its structure
  less.
- **An aside the reader would want.** One sentence that steps off the main line to give the
  reader something useful the structure had no slot for, such as the failure the author hit in
  practice or the reason a default that looks wrong is right. The aside
  must already be in the text or its sources; a fix pass never invents one, and an aside that
  serves the writer instead of the reader is cut.
- **Say what you don't know when you don't know it.** Name the open question once, attached to
  the claim it limits ("we have not measured this on Windows"), the same one-hedge rule the
  stacked-hedging row applies. One hedge is honesty; a uniform confident surface hides where the
  reader should be careful. A fix pass states only uncertainty the source already holds.

Deliberately leaving flaws in the prose is not a voice technique, and a fix pass never adds them.
Planted imperfection, typos included, changes how the text would score, not how it reads, so it
fails this guide's improve-it-anyway test and is the evasion posture the guide refuses. It is
left off the list on purpose; do not re-add it as a technique.

This section never overrides meaning preservation: voice is added in HOW a kept claim is
phrased, never by inventing new claims during a fix pass.

## Self-audit

Last pass over each rewritten file, before the semantic-diff verification: read it asking "what
still makes this read machine-written?" and fix what surfaces, whether or not a rule flagged
it: a leftover "leverage", a triad that came back, a word from the judgment rows above, a
paragraph with no verdict in it. Then read it once more; what that second read finds is fixed or
reported, and the self-audit ends there. Findings from this pass are reported like rubric findings
(quoted text, catalog entry when one fits).
