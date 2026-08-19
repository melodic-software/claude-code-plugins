# AI-writing tell catalog

The rule inventory for `/ai-slop:audit`: every sign of AI writing catalogued by the Wikipedia page
below, plus the additions in the "Cursor unslop additions" section. Each tell is classified for
detectability and applicability, with its V1 disposition. Script rules are implemented in `../scripts/detect.sh`
and carry argued severity-crosswalk rows; rubric tells are applied by the skill's judgment layer;
`recorded-only` tells are catalogued but not run in V1 (the entry says why). Fix-time rewrite
guidance (what to write INSTEAD of a tell) lives in [`rewrite-guide.md`](rewrite-guide.md), not
here: this file decides what flags, that file decides what replaces it.

<!-- ai-slop-ignore-file: this catalog quotes the tells it detects; scanning it flags its own rule corpus -->

## Attribution and license

Derived from Wikipedia, ["Wikipedia:Signs of AI writing"](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing),
revision [1369699198](https://en.wikipedia.org/w/index.php?title=Wikipedia:Signs_of_AI_writing&oldid=1369699198)
(2026-08-16). Changes were made: the page's signs are distilled, reworded, reorganized, and
classified for use outside Wikipedia; this file is not a copy of the page. The adapted material in
this file is licensed under
[Creative Commons Attribution-ShareAlike 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
(CC BY-SA 4.0), as the source requires.

The "Cursor unslop additions" section was inspired by
[Cursor's `unslop` skill](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md).

## Upstream-drift record

- **Claim**: this catalog's tell inventory derives from the source page revision cited above.
- **Basis**: the revision-pinned URL in the attribution block.
- **As of**: 2026-08-17.
- **Recheck trigger**: each `ai-slop` release and each fleet audit. Per-revision rechecking was
  rejected: the page was measured at 50+ edits/week (2026-08-17), so a per-revision trigger would
  fire continuously.
- **Known fetch gap**: the page's "Comment-specific indicators" and "Ineffective indicators"
  sections exceeded the fetch window at catalog time and are recorded as section notes below,
  without entries. The recheck trigger covers closing this gap.

## Inventory

59 tells catalogued from the Wikipedia source revision, plus 7 in the "Cursor unslop additions"
section at the end of this file. Entry marker: `### rule-<slug>: <name>`. The qualified id used
in crosswalk rows and findings files is `ai-slop/audit/rule-<slug>`. Fields:

- **detectability**: `mechanical` (patterns a script can match) or `judgment` (needs a reader).
- **applicability**: `general-prose` (any markdown/docs corpus) or `wikipedia-specific`
  (only meaningful inside Wikipedia's editing model).
- **v1**: `script` (implemented in detect.sh), `rubric` (skill judgment layer), or
  `recorded-only` (catalogued, not run; reason given).

## Calibration record (V1)

Calibrated 2026-08-17 against this marketplace's tracked markdown (1161 files) with neutral
defaults. Outcomes:

- All 12 `v1: script` rules ship as of this pass; none demoted. (The roster is 15 after the
  second pass below adds three.)
- Density rules gained a minimum-hits floor (3) after short files fired on a single
  normal-prose occurrence (one triad in a 201-word document hit 5.0/1000 words).
- `rule-knowledge-cutoff-disclaimer` has a known false-positive class: prose ABOUT model
  knowledge cutoffs (documentation discussing models). Remedy is the in-file marker or config
  exclusion, recorded here rather than weakening the rule.
- `rule-em-dash` fired 32,323 times on the calibration corpus; that is the corpus's deliberate
  house style, handled by that repo's own config when dogfooding, and confirms the shipped
  default must stay neutral (zero-tolerance) rather than inherit any one repo's taste.
- `rule-negative-parallelism` ships without the source's third pattern ("X rather than Y"):
  too common in ordinary technical prose to fire on occurrence, recorded for post-V1
  density treatment.

Second pass, 2026-08-19, for the Cursor additions, against the same corpus:

- The three new script rules calibrated clean: chatbot-artifact phrases, stacked hedges, and the
  distinctive filler phrases each measured 0 to 3 occurrences corpus-wide; "in order to" measured
  20, low enough to fire per occurrence (each hit has a mechanical fix, so volume is work, not
  noise).
- `rule-abstract-metaphor-jargon` stays rubric, not script, on measurement: "substrate" alone hit
  114 times in legitimate technical use on this corpus. A word-list scan cannot make the
  literal-versus-metaphor call the tell turns on.
- `vocab_add` candidates "utilize", "leverage", "facilitate" (the Cursor plain-word list) joined
  the shipped vocabulary default: "leverage" measured 32 occurrences here, but the density gate
  (3.0/1000 words, minimum 3 hits per file) kept the rule quiet on every file, so the shipped
  default stays neutral while saturated files still flag.

## Content

### rule-significance-inflation: Undue emphasis on significance, legacy, and broader trends

- detectability: mechanical (phrase core), judgment (residual)
- applicability: general-prose
- v1: script
- Inflates importance with stock phrases: "stands as a testament", "pivotal moment", "underscores
  its importance", "reflects broader", "enduring legacy", "marks a shift", "evolving landscape",
  "indelible mark", "deeply rooted", "setting the stage for". The phrase list is the script rule
  (`rule-significance-inflation`); inflation worded without stock phrases falls to the rubric.

### rule-canned-notability: Canned emphasis on notability, attribution, and media coverage

- detectability: judgment
- applicability: wikipedia-specific
- v1: recorded-only
- Repetitive listing of source types and phrases like "independent coverage" to argue notability.
  Wikipedia's notability model; no general-prose analogue worth a rule.

### rule-superficial-analysis: Superficial analyses

- detectability: judgment
- applicability: general-prose
- v1: rubric
- Present-participle tails making vague significance claims ("...emphasizing its role in...",
  "...highlighting the importance of...") without substantiation.

### rule-promotional-language: Promotional and advertisement-like language

- detectability: mechanical (word core), judgment (tone)
- applicability: general-prose
- v1: rubric
- Travel-guide tone: "nestled", "vibrant", "boasts a", "groundbreaking", "renowned",
  "in the heart of", "diverse array". The word core rides `rule-ai-vocabulary`'s list; the tone
  call is the rubric's. "Breathtaking", "stunning" and "must-visit" are deliberately not in the
  mechanical word core: they are travel-copy words with almost no technical-prose base rate here,
  so a script rule for them would sit dead in this corpus while the rubric already catches the
  register.

### rule-vague-attribution: Vague attributions and overgeneralization of opinions

- detectability: judgment
- applicability: general-prose
- v1: rubric
- Weasel wording implying consensus from nothing: "industry reports", "experts argue",
  "many consider", "widely regarded".

### rule-challenges-conclusion: Outline-like conclusions about challenges and future prospects

- detectability: mechanical
- applicability: general-prose
- v1: script
- The closing formula "Despite its X, Y faces challenges..." followed by speculative prospects.

### rule-list-title-as-noun: Leads treating list or article titles as proper nouns

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Defining a list page's title as if it were a standalone entity. Wikipedia lead convention.

### rule-awards-section: "Awards and recognition" section

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- A near-ubiquitous generic section in AI-drafted articles. Article-shape specific.

## Language and grammar

### rule-ai-vocabulary: High density of "AI vocabulary" words

- detectability: mechanical
- applicability: general-prose
- v1: script
- Density of model-favored words, era-grouped by the source. 2023 to mid-2024: "additionally",
  "boasts", "bolstered", "crucial", "delve", "emphasizing", "enduring", "garner", "intricate",
  "interplay", "landscape", "meticulous", "pivotal", "underscore", "tapestry", "testament",
  "valuable", "vibrant". Mid-2024 to mid-2025 adds "align with", "enhance", "fostering",
  "highlighting", "showcasing". Mid-2025 onward: "emphasizing", "enhance", "highlighting",
  "showcasing". **The shipped list is a deliberate narrowing of that union, not the union
  itself** — it keeps the distinctive words and drops the ones with heavy legitimate technical
  use: "additionally", "enhance", "emphasizing", "highlighting", "align with", "valuable", and
  "landscape" as an abstract noun (the literal phrase "evolving landscape" is still caught by
  `rule-significance-inflation`). A consuming repo that wants the full union adds them through
  `vocab_add`. The list is config-extensible either way; the density threshold is the calibrated
  condition.

### rule-copulative-avoidance: Avoidance of basic copulatives

- detectability: mechanical
- applicability: general-prose
- v1: script
- Substituting "is/are" with "serves as", "stands as", "marks", "functions as", "operates as",
  "represents", "boasts", "features", "maintains", "offers", "refers to". Density-based.

### rule-negative-parallelism: Negative parallelisms

- detectability: mechanical
- applicability: general-prose
- v1: script
- Three constructions: "not just X, but also Y"; "not X, but Y" (including "isn't X; it's Y");
  "X rather than Y" (noted by the source as characteristic of Grok output).

### rule-rule-of-three: Rule of three

- detectability: mechanical
- applicability: general-prose
- v1: script
- Triplet overuse: "adjective, adjective, adjective" runs and three-item list density. Highest
  false-positive risk in the roster; calibration decides whether it ships or demotes.

### rule-elegant-variation: Lexical diversity and elegant variation

- detectability: judgment
- applicability: general-prose
- v1: rubric
- Synonym-cycling to avoid repeating a word a human would simply repeat.

## Style

### rule-title-heading: Redundant title heading

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- An opening heading repeating the document title. Structural markdown; the markdown linter lane
  owns heading structure.

### rule-title-case: Title case in headings

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- All-main-words capitalization in section headings. Structural markdown; linter lane.

### rule-empty-headings: Headings only containing other headings

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- A section with no body text, only sub-headings. Structural markdown; linter lane.

### rule-bold-overuse: Overuse of boldface

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- Excessive bolding of terms beyond emphasis convention. Post-V1 script candidate (density rule).

### rule-inline-header-lists: Inline-header vertical lists

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- Bold-lead-in bullets substituting for prose structure. Post-V1 script candidate; high overlap
  with legitimate reference-doc style, needs careful calibration. **Calibration pre-work, not a
  live boundary** (this entry is `recorded-only`, so neither layer runs it): the tell is a bold
  label whose colon restates the line ("**Performance:** Performance improved..."); a bold
  lead-in that ends in a period, names the item, and is followed by genuinely new detail is
  reference-doc style, not a tell. Promoting this rule means running that boundary against a real
  corpus first.

### rule-em-dash: Overuse of em dashes

- detectability: mechanical
- applicability: general-prose
- v1: script
- The `—` character (`\xE2\x80\x94`) in prose. **Zero-tolerance by default** (user decision at
  plan approval): any occurrence outside code fences and inline code flags. Documents that
  require em dashes opt out per-document via config path-lists or the in-file marker; the rule is
  never threshold-calibrated and is excluded from the `recorded-only` demotion path.

### rule-emoji-formatting: Emoji as formatting

- detectability: mechanical
- applicability: general-prose
- v1: script
- Emoji used as bullets, section markers, or visual separators in prose.

### rule-unusual-tables: Unusual use of tables

- detectability: judgment
- applicability: general-prose
- v1: rubric
- Tables wrapping content that reads better as prose or a plain list.

### rule-curly-artifacts: Curly quotation marks and apostrophes

- detectability: mechanical
- applicability: general-prose
- v1: script
- Smart quotes and apostrophes plus adjacent Unicode residue characteristic of chat-interface
  copy-paste, in files whose convention is straight quotes.

### rule-skipped-heading-levels: Skipping heading levels

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- H2 jumping to H4. Owned outright by the markdown linter lane (MD001).

### rule-multiple-h1: Overuse of level 1 headings

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- Multiple H1s in one document. Owned outright by the markdown linter lane (MD025).

### rule-thematic-breaks: Thematic breaks between sections

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- Horizontal rules as section separators. Legitimate in some house styles; post-V1 candidate
  behind config.

## Communication intended for the user

### rule-collaborative-communication: Collaborative communication

- detectability: judgment
- applicability: general-prose
- v1: rubric
- Addressing the reader as a chat partner: "we explore", "let's look at", "helps readers
  understand", "this guide walks you through" in documents that are not tutorials.

### rule-knowledge-cutoff-disclaimer: Knowledge-cutoff disclaimers and source-gap speculation

- detectability: mechanical
- applicability: general-prose
- v1: script
- Assistant-frame residue: "as of my knowledge cutoff", "as of my last update", "I cannot browse",
  "based on available information up to".

### rule-placeholder-text: Phrasal templates and placeholder text

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- Unfilled template slots and placeholder phrases left in output ("[Company Name]",
  "insert X here"). Post-V1 script candidate; needs a placeholder-pattern inventory first.

## Markup

### rule-markdown-in-wikitext: Use of Markdown

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Markdown symbols inside wikitext. Meaningless in a markdown corpus (inverted meaning).

### rule-broken-wikitext: Broken wikitext

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Malformed wiki syntax. No markdown analogue in scope.

### rule-llm-citation-artifacts: Internal formatting and reference markup bugs

- detectability: mechanical
- applicability: general-prose
- v1: script
- Model-internal citation residue leaking into text: `oaicite`, `[cite:`, `grok_card`,
  `attached_file`, `contentReference`, stray dagger clusters.

### rule-nonexistent-categories: Non-existent or out-of-place categories

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Category links that do not exist or do not apply. Wikipedia taxonomy.

### rule-nonexistent-templates: Non-existent templates

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Calls to templates absent from the template library. Wikipedia infrastructure.

## Citations

### rule-broken-links: Broken external links

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- URLs resolving to 404s or unrelated pages. Already owned in this fleet by the link checker
  (lychee); duplicating it here would be a second copy of an existing lane.

### rule-invalid-identifiers: Invalid DOI and ISBNs

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Malformed or non-existent citation identifiers. Citation-corpus specific.

### rule-unrelated-doi: DOIs that lead to unrelated articles

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Valid-format DOIs resolving to a different subject. Citation-corpus specific.

### rule-pageless-book-citations: Book citations without page numbers or URLs

- detectability: judgment
- applicability: wikipedia-specific
- v1: recorded-only
- Citations too vague to verify. Citation-corpus specific.

### rule-citation-misuse: Incorrect or unconventional use of references

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Improper citation template structure. Wikipedia citation model.

### rule-utm-params: utm_source parameters

- detectability: mechanical
- applicability: general-prose
- v1: script
- Tracking parameters (`utm_source=`, and sibling `utm_*` keys) left in URLs, characteristic of
  chat-interface link copies.

### rule-unused-named-refs: Named references declared but unused

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Reference definitions never cited in the body. Wikipedia reference syntax.

## Comment-specific indicators

Section recorded as a known fetch gap (see the upstream-drift record): the source section exceeded
the fetch window at catalog time. Its scope is Wikipedia talk-page comments, so its tells are
expected to classify wikipedia-specific. Entries land when the recheck trigger next fires.

## Edit summaries

All five tells in this section concern Wikipedia's edit-summary field and classify
wikipedia-specific, recorded-only:

### rule-verbose-edit-summaries: Uncharacteristically formal edit summaries

- detectability: judgment
- applicability: wikipedia-specific
- v1: recorded-only
- Formal, verbose summaries unlike the editor's other activity.

### rule-canned-policy-assurance: Canned assurance of policy adherence

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Generic compliance claims in summaries.

### rule-preserved-information: "Preserved" or "retained" information mentions

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Summaries advertising that existing content was kept.

### rule-citation-overemphasis: Overemphasis on citation presence and reliability

- detectability: judgment
- applicability: wikipedia-specific
- v1: recorded-only
- Summaries fixated on citation counts and quality.

### rule-afc-review-reference: Reference to AfC review

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Mentions of the Articles-for-Creation process.

## Miscellaneous

### rule-style-shift: Pronounced shift in writing style

- detectability: judgment
- applicability: general-prose
- v1: rubric
- Abrupt tone, vocabulary, or structure change inside one document relative to its history.

### rule-submission-statements: "Submission statements" in AfC drafts

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Notability preambles in draft submissions.

### rule-preplaced-maintenance-templates: Pre-placed maintenance templates

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Maintenance templates inserted before the content they would flag exists.

### rule-canned-user-pages: Canned user pages

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Boilerplate user-page content.

### rule-permissions-gaming: Permissions gaming

- detectability: judgment
- applicability: wikipedia-specific
- v1: recorded-only
- Editing patterns aimed at gaining privileges.

### rule-llm-differences: Differences between LLMs

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- Meta-observation that vocabulary and error patterns vary per model. Informs other rules'
  word lists rather than being a rule itself.

## Signs of human writing

Counter-signs: evidence AGAINST AI authorship. Catalogued for the rubric's calibration, never
emitted as findings.

### rule-pre-llm-text: Age of text relative to ChatGPT launch

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- Text predating November 2022 cannot be modern-LLM output. Git history gives this for free.

### rule-explainable-choices: Ability to explain editorial choices

- detectability: judgment
- applicability: general-prose
- v1: recorded-only
- An author who can articulate why a choice was made.

### rule-human-syntax: Syntax inconsistent with LLM output

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- Constructions models rarely produce.

## Ineffective indicators

Section recorded as a known fetch gap (see the upstream-drift record): the source section exceeded
the fetch window at catalog time. Its content lists signals the page's editors consider UNRELIABLE
for detection; when the recheck fires, its items land here as guardrails on our own rules (a
signal listed there must not become a rule).

## Historical indicators

Era-bound tells the source dates to earlier model generations. Catalogued for completeness;
`recorded-only` because their base rates have collapsed in current output:

### rule-didactic-disclaimers: Didactic disclaimers

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- "I am an AI" style statements, November 2022 to 2024 era.

### rule-section-summaries: Section summaries

- detectability: judgment
- applicability: general-prose
- v1: recorded-only
- Recap paragraphs restating the section above.

### rule-prompt-refusal: Prompt refusal

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- Refusal-message residue ("I can't write that"). Post-V1 script candidate alongside
  `rule-knowledge-cutoff-disclaimer`.

### rule-abrupt-cutoffs: Abrupt cut offs

- detectability: judgment
- applicability: general-prose
- v1: recorded-only
- Content ending mid-sentence.

### rule-outdated-access-dates: Outdated access-date parameters

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Reference access dates inconsistent with publication dates.

## Cursor unslop additions

Tells from the `unslop` skill linked at the top of this file that the Wikipedia inventory does not
already carry. The overlap map first, accounting for every upstream pattern; then the new entries.

### Overlap map

Upstream patterns **catalogued by** a Wikipedia-derived entry, or routed to the rewrite guide
(fix-time guidance is not a tell inventory). "Catalogued" is deliberately weaker than "covered":
a row pointing at a `recorded-only` entry is bookkeeping, not detection — nothing runs it in
either layer, and those rows say so.

| Upstream pattern | Where it lives here |
|---|---|
| Puffery | `rule-significance-inflation` |
| Name-dropping | **Not detected — deliberately out of scope for general prose.** `rule-canned-notability` records the Wikipedia-specific form and is `recorded-only`; its own entry says there is no general-prose analogue worth a rule. Not `rule-vague-attribution`, which is the opposite tell (naming *no* source, not naming many with no content) |
| Superficial -ing phrases | `rule-superficial-analysis` |
| Promotional language | `rule-promotional-language` |
| Vague attributions | `rule-vague-attribution` |
| Formulaic challenges | `rule-challenges-conclusion` — the "Despite its X, faces challenges" formula its ERE actually matches |
| Generic conclusions | **Only the formulaic half is detected**, by the row above. A bare optimism closer ("The future looks bright") matches no shipped rule: `rule-superficial-analysis` needs a present-participle tail and does not reach it |
| AI vocabulary; prefer the plain word | `rule-ai-vocabulary` (the plain-word list joined the shipped vocabulary default; see the calibration record) |
| Fancy ways to say "is" | `rule-copulative-avoidance` |
| "Not just X, but Y" | `rule-negative-parallelism` |
| Rule of three | `rule-rule-of-three` |
| Synonym cycling | `rule-elegant-variation` |
| Em dash overuse | `rule-em-dash`; the no-substitute-tell guardrail (no parentheses or en dashes in its place) is fix guidance in `rewrite-guide.md` |
| Boldface overuse | `rule-bold-overuse` — `recorded-only`, so catalogued and dormant |
| Inline-header lists | `rule-inline-header-lists` — `recorded-only`, so catalogued and dormant; the boundary refinement in that entry is calibration pre-work, not a live boundary |
| Title case headings | `rule-title-case` — `recorded-only` here (the markdown linter lane owns heading structure) |
| Decorative emojis | `rule-emoji-formatting` |
| Curly quotes | `rule-curly-artifacts` |
| Cutoff disclaimers | `rule-knowledge-cutoff-disclaimer` |
| Adding soul; plain speech (mechanism over feeling, sentence splitting, active voice, adverbs) | `rewrite-guide.md` (rewrite disciplines, not detection tells); the mechanism-over-feeling test also flags via `rule-mechanism-free-claims` below |

### rule-chatbot-artifacts: Chat-turn residue and sycophancy

- detectability: mechanical (phrase core), judgment (tone residual)
- applicability: general-prose
- v1: script
- Assistant chat-turn phrasing committed as document prose: "I hope this helps", "Let me know if
  you...", "Feel free to ask", "I'd be happy to", "Happy to help", and the sycophancy openers
  "Great question", "You're absolutely right", and the false-triumph closer "Found the smoking
  gun". The phrase list is the script rule; overall conversational or flattering tone without a
  listed phrase falls to the rubric alongside `rule-collaborative-communication`. Merges the
  source's "chatbot phrases" and "sycophantic tone" patterns; bare "Certainly!" and "Of course!"
  were left off the phrase list as too common in legitimate prose.

### rule-filler-phrases: Filler phrases

- detectability: mechanical
- applicability: general-prose
- v1: script
- Multiword filler with a shorter exact equivalent: "in order to" (for "to"), "due to the fact
  that" (for "because"), "it is important to note that", "it is worth noting that", "it should
  be noted that" (all deletable). Fires per occurrence; each hit has a mechanical rewrite.

### rule-stacked-hedging: Stacked hedging

- detectability: mechanical (stacked core), judgment (residual)
- applicability: general-prose
- v1: script
- Two hedges propping each other up: "could potentially", "may potentially", "might possibly",
  "could possibly", "might potentially". One hedge is a claim about uncertainty; two is filler.
  Hedging spread across a sentence ("it could be argued that it might") needs a reader and falls
  to the rubric.

### rule-false-ranges: False ranges

- detectability: judgment
- applicability: general-prose
- v1: rubric
- "From X to Y" where X and Y sit on no meaningful scale ("from dashboards to microservices"):
  a list dressed as a spectrum. The construction is mechanical but the scale call is not, and
  legitimate ranges ("from 2 to 10 seconds") dominate; rubric only.

### rule-colon-crutch: Colon as mid-sentence connector

- detectability: judgment
- applicability: general-prose
- v1: rubric
- A colon splicing two clauses where neither a list nor an example follows, letting the first
  clause lean on the second instead of standing alone. Colons before lists and examples are
  fine; the connector use needs a reader to distinguish, so no script core ships.

### rule-abstract-metaphor-jargon: Abstract metaphor nouns

- detectability: mechanical (word cues), judgment (literal versus metaphor)
- applicability: general-prose
- v1: rubric
- Metaphor nouns standing in for a plainer concrete word: "substrate", "wedge", "nexus", "locus",
  "vantage", "north star", "flywheel", "bedrock", "endgame", "gold-plating", plus "primitive",
  "harness", "scaffolding", "vector", "surface", "ratchet", "paradigm", "modality", and
  "evacuate" (for moving code) in their metaphorical (not domain-literal) senses. The tell turns on the literal-versus-metaphor call:
  "harness" naming an actual test harness is not a tell. Calibration kept this out of the script
  layer (see the calibration record's second pass). Replacements live in `rewrite-guide.md`.

### rule-mechanism-free-claims: Feeling-words instead of mechanism

- detectability: judgment
- applicability: general-prose
- v1: rubric
- A sentence naming a feeling about the thing ("SQL you can read", "the database stays close at
  hand") where the reader needs the mechanism or the number ("`.toSQL()` returns the exact string
  sent to the database"). Two tests: can the sentence be restated as a concrete instruction,
  fact, or number (if not, cut it); and could it appear unchanged in another project's docs (if
  so, it says nothing about this one).
