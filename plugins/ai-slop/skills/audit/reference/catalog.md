# AI-writing tell catalog

## Contents

- [Attribution and license](#attribution-and-license)
- [Upstream-drift record](#upstream-drift-record)
- [Inventory](#inventory)
- [False-positive posture (source Caveats)](#false-positive-posture-source-caveats)
- [Quotation exemption (policy-level)](#quotation-exemption-policy-level)
- [Calibration record (V1)](#calibration-record-v1)
- [Content](#content)
- [Language and grammar](#language-and-grammar)
- [Style](#style)
- [Communication intended for the user](#communication-intended-for-the-user)
- [Markup](#markup)
- [Citations](#citations)
- [Comment-specific indicators](#comment-specific-indicators)
- [Edit summaries](#edit-summaries)
- [Miscellaneous](#miscellaneous)
- [Signs of human writing](#signs-of-human-writing)
- [Ineffective indicators](#ineffective-indicators)
- [Historical indicators](#historical-indicators)
- [General-prose additions](#general-prose-additions)
- [Model-era additions (repo-owned)](#model-era-additions-repo-owned)

The rule inventory for `/ai-slop:audit`: every sign of AI writing catalogued by the Wikipedia page
below, plus the additions in the "General-prose additions" section. Each tell is classified for
detectability and applicability, with its V1 disposition. Script rules are implemented in `../scripts/detect.sh`
and carry argued severity-crosswalk rows; rubric tells are applied by the skill's judgment layer;
`recorded-only` tells are catalogued but not run in V1 (the entry says why). Fix-time rewrite
guidance (what to write INSTEAD of a tell) lives in [`rewrite-guide.md`](rewrite-guide.md), not
here: this file decides what flags, that file decides what replaces it.

## Attribution and license

Derived from Wikipedia, ["Wikipedia:Signs of AI writing"](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing),
revision [1369699198](https://en.wikipedia.org/w/index.php?title=Wikipedia:Signs_of_AI_writing&oldid=1369699198)
(2026-08-16). Changes were made: the page's signs are distilled, reworded, reorganized, and
classified for use outside Wikipedia; this file is not a copy of the page. The adapted material in
this file is licensed under
[Creative Commons Attribution-ShareAlike 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
(CC BY-SA 4.0), as the source requires.

## Upstream-drift record

This catalog's tell inventory derives from the pinned source revision named in the attribution
block. Each tell is this repository's own firing rule, reworded and classified for use outside
Wikipedia; the page's text is read at the pointer, not stored here.

- **Pointer**: for the source inventory, see revision
  [1369699198](https://en.wikipedia.org/w/index.php?title=Wikipedia:Signs_of_AI_writing&oldid=1369699198)
  of <https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing>.
- **As of**: 2026-08-17
- **Recheck trigger**: each `ai-slop` release and each fleet audit. Per-revision rechecking was
  rejected: the page was measured at 50+ edits/week (2026-08-17), so a per-revision trigger would
  fire continuously.
- **Known fetch gap**: closed 2026-08-21 for both leftover sections. The catalog-time fetch
  window missed "Comment-specific indicators" and "Ineffective indicators"; this recheck
  retrieved them from the catalog pin and from the live page. See those sections below.
- **Recheck logged (2026-08-21)**:
  - Live page: <https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing>, MediaWiki
    revisions query returned revision
    [1370403579](https://en.wikipedia.org/w/index.php?title=Wikipedia:Signs_of_AI_writing&oldid=1370403579)
    (`timestamp=2026-08-20T23:13:41Z`, user `Superb Owl`). Retrieved via WebFetch of the
    article URL plus `action=query&prop=revisions`.
  - Catalog pin: revision
    [1369699198](https://en.wikipedia.org/w/index.php?title=Wikipedia:Signs_of_AI_writing&oldid=1369699198)
    (2026-08-16). Retrieved via `action=parse&oldid=1369699198&prop=wikitext` (section 80 =
    Ineffective indicators; section 62 = Comment-specific indicators; section 29 = Overuse of
    em dashes).
  - The inventory pin stays `1369699198`. This recheck closes the two-section gap; it does
    not re-derive the rest of the inventory.
- **Recheck logged (2026-08-25, fleet audit + verified research pass)**: live head revision
  [1371235958](https://en.wikipedia.org/w/index.php?title=Wikipedia:Signs_of_AI_writing&oldid=1371235958)
  (2026-08-25). Measured drift since the pin: 4 heading changes across 29 edits; the sections
  this catalog draws on are byte-identical between pin and head. The research verdict was that
  the catalog's defects were under-extraction from the pin, not staleness, and this recheck
  closed them: the source Caveats posture (section below), the em-dash spacing qualifier, the
  knowledge-cutoff words-to-watch families, and the upstream demotion of lexical diversity.
  The pin stays `1369699198`. One new live-page general-prose tell ("Vague expression of
  connection or association") measured 0 qualifying hits on this corpus and is recorded as a
  candidate for the next recheck rather than a rule.

## Inventory

65 tells catalogued from the Wikipedia source revision, plus 9 in the "General-prose additions"
section and 4 in the "Model-era additions (repo-owned)" section at the end of this file. Entry
marker: `### rule-<slug>: <name>`. The qualified id used
in crosswalk rows and findings files is `ai-slop/audit/rule-<slug>`. Fields:

- **detectability**: `mechanical` (patterns a script can match) or `judgment` (needs a reader).
- **applicability**: `general-prose` (any markdown/docs corpus) or `wikipedia-specific`
  (only meaningful inside Wikipedia's editing model).
- **v1**: `script` (implemented in detect.sh), `rubric` (skill judgment layer), or
  `recorded-only` (catalogued, not run; reason given).

Model-era entries carry four further fields: `era`, `models`, `evidence`, and an attribution
note inside the prose where a harness confound applies. The evidence grades and their
placement gate are defined at the top of that section.

## False-positive posture (source Caveats)

Derived from the pin's Caveats section (byte-identical on the live head; extraction closed
2026-08-25), which is read at the pointer in the upstream-drift record. Three postures bind how
this catalog's verdicts are read:

- **The signs are descriptive, not prescriptive.** This plugin's fix flow is framed as house
  style (better prose on its own merits), never detector evasion; the rewrite guide's
  non-evasion posture carries the operational test.
- **Expert false-positive rate.** The Caveats section gives a false-positive rate for
  experienced human reviewers. A deterministic subset of those signs run over a technical corpus
  is not better calibrated than those reviewers; verdicts are evidence for a rewrite decision,
  never proof of provenance, and accusatory framing ("this is AI-written") is outside this
  plugin's vocabulary.
- **Combination over isolation.** This catalog treats an individual sign as weak alone and a
  combination as stronger. Density thresholds, the minimum-hits floor, and the rubric's
  counter-sign tempering are its mechanical forms of that posture.

## Quotation exemption (policy-level)

Stated once here and inherited by every rule; the design follows the Wikipedia Manual of Style's
principle of minimal change for quoted material (quotations are not the repo's own prose to
restyle) and the detector implements it mechanically. No rule scans fenced code, inline code
spans, or ignore-marked lines, whatever its class. Each rule carries a class:

- **wording**: the rule judges prose the repo AUTHORS. It never scans quoted material:
  blockquote lines and double-quoted spans are removed from its input.
  Quote-exempt candidates are counted as declined, never silently dropped.
  This is also the use/mention boundary: a document that QUOTES a tell to document it (a style
  guide, a forbidden-phrase list, a changelog citing the phrase a fix removed) is mentioning,
  not using, and backticking or double-quoting the mention is the marker-free suppression.
- **typography**: the rule targets artifacts that are defects wherever they sit (em-dash
  bytes, curly-paste residue, formatting emoji, model citation tokens, tracking parameters).
  It scans quoted material too; MOS makes the same split by permitting typographic
  normalization inside quotations while forbidding wording edits.

Known limitation: the double-quoted-span exemption covers straight `"` only, and a span open at
a blank line or at the start of a new block (heading, list item, table row) closes there. A
quotation that crosses one of those boundaries escapes the exemption; the closures are the
blockquote form or the fenced marker.

The class assignments live in the detector's rule registry. The exemption moves candidates from
findings to declines and never changes a rule's crosswalk tier.

## Calibration record (V1)

Calibrated 2026-08-17 against this marketplace's tracked markdown (1161 files) with neutral
defaults. Outcomes:

- All 12 `v1: script` rules measured in this pass ship; none demoted. `detect.sh` is the
  authoritative list of shipped script rules.
- Density rules gained a minimum-hits floor (3) after short files fired on a single
  normal-prose occurrence (one triad in a 201-word document hit 5.0/1000 words).
- `rule-knowledge-cutoff-disclaimer` has a known false-positive class: prose ABOUT model
  knowledge cutoffs (documentation discussing models). Remedy is the in-file marker or config
  exclusion, recorded here rather than weakening the rule. **Measured on the 1214-file dogfood
  corpus (2026-08-19): all 8 findings fall in that class**. They are model-spec sentences
  quoting a cutoff date, prose arguing that cutoffs are upstream-owned, and the crosswalk row
  naming this rule. Zero were genuine assistant-frame residue. The class is therefore the
  rule's whole yield on a corpus that documents models, which is the corpus type most likely
  to trip it; it is not evidence the rule is wrong, because the tell it targets is absent here
  rather than missed.
- `rule-em-dash` fired 32,323 times on the calibration corpus; that is the corpus's deliberate
  house style, handled by that repo's own config when dogfooding, and confirms the shipped
  default must stay neutral (zero-tolerance) rather than inherit any one repo's taste.
- `rule-negative-parallelism` ships without the source's third pattern ("X rather than Y"):
  too common in ordinary technical prose to fire on occurrence, recorded for post-V1
  density treatment.

Second pass, 2026-08-19, for the general-prose additions, against the same corpus:

- The three new script rules calibrated clean: chatbot-artifact phrases, stacked hedges, and the
  distinctive filler phrases each measured 0 to 3 occurrences corpus-wide; "in order to" measured
  20, low enough to fire per occurrence (each hit has a mechanical fix, so volume is work, not
  noise).
- `rule-abstract-metaphor-jargon` stays rubric, not script, on measurement: "substrate" alone hit
  114 times in legitimate technical use on this corpus. A word-list scan cannot make the
  literal-versus-metaphor call the tell turns on.
- `vocab_add` candidates "utilize", "leverage", "facilitate" (the plain-word trio) joined
  the shipped vocabulary default: "leverage" measured 32 occurrences here, but the density gate
  (3.0/1000 words, minimum 3 hits per file) kept the rule quiet on every file, so the shipped
  default stays neutral while saturated files still flag.

Third pass, 2026-08-25, over a full repo-wide `fix` run (82 findings across 45 files), a
plugin-quality audit, and a verified prior-art survey:

- `rule-rule-of-three` demoted to rubric per its own calibration clause: 18 of 18 residual
  findings after the fix pass sat on enumerations whose every item the reader needs, the ERE
  matched only single-word triads, and no surveyed prose linter implements the tell. See the
  entry.
- The quotation exemption (section above) was added after roughly half of the pass's ~40
  suppression markers protected quoted or tell-documenting text, one use/mention problem the
  policy now closes marker-free. Measured on the same corpus after the change: the exemption
  moved those candidate classes from findings to declines with no loss on unquoted prose.
- `rule-knowledge-cutoff-disclaimer` gained the source section's missing phrase families (the
  candidate-additions research measured 0 pre-existing hits for the new families on this
  corpus, so the extension ships without a threshold change).
- `rule_allowed_paths` generalized the per-rule path exemption the em-dash rule already had,
  as the proportionate closure for density verdicts a line marker cannot quiet.

Fourth pass, 2026-08-27, for the "Model-era additions (repo-owned)" section, against the
then-current 1,361-file tracked-markdown corpus:

- `rule-model-era-phrases` shipped with its anchored three-fragment roster and measured **0
  findings corpus-wide**. The chatbot-artifacts precedent (0-3 corpus-wide ships clean)
  holds for the new phrase class.
- `pre-existing` joined the shipped vocabulary list on the leverage precedent: 61 files
  contain the word and the density gate (3.0/1000, minimum 3 hits) fired on none of them.
  The rest of the frequency cluster stays `recorded-only`; measured with the pruned 7-word
  distinctive core added, the rule's yield was dominated by domain-literal use
  (`uncommitted` in a git-reset document, `dedup` in a dedup-pass reference), and the broad
  21-word list flagged 636 findings across 47% of the corpus.
- Rubric-cue base rates recorded for the two new metaphor cues, since the rubric layer is
  where this pass's real cost lands and the detector delta cannot measure it:
  `load-bearing` 527 occurrences across 273 files, `seam(s)` 1,429 across 328 files (36% of
  the corpus in union). The cue entries' literal-sense boundaries and the saturation rule
  defined in `rule-abstract-metaphor-jargon` are the control.

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
  itself**. It keeps the distinctive words and drops the ones with heavy legitimate technical
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
  "X rather than Y" (the source ties this one to a particular model family).

### rule-rule-of-three: Rule of three

- detectability: judgment
- applicability: general-prose
- v1: rubric
- Triplet overuse: "adjective, adjective, adjective" runs and rhythmic three-item cadence.
- **Demoted from script to rubric (2026-08-25), per this entry's own calibration clause.** The
  dogfood fix pass ended with 18 of 18 residual findings on load-bearing enumerations; the
  shipped ERE matched only single-word triads, selecting for exactly the terse operative lists
  the boundary protects; and a survey of comparable prose linters (Vale, textlint, proselint,
  write-good, alex, markdownlint) found no tricolon implementation anywhere to learn from.
  The boundary the rubric applies: enumerating three actual things the reader needs is not a
  tell; three parallel items used for rhythm, where the survivors would entail the deleted
  ones, is. A reader can make that call; a density regex demonstrably cannot.

### rule-elegant-variation: Lexical diversity and elegant variation

- detectability: judgment
- applicability: general-prose
- v1: recorded-only
- Synonym-cycling to avoid repeating a word a human would simply repeat.
- Demoted from the active rubric 2026-08-25, following the live source page's own move of this
  sign to its historical section, rather than keeping an era-bound tell active.

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
  live boundary** (this entry is `recorded-only`, so neither layer runs it). Reference docs
  often start an item with a short bold name and a full stop, then give detail the name does not
  already carry; that is ordinary style. The test for the tell: delete the bold label and its
  colon, and see whether the line lost anything. If the sentence after the label says the same
  thing again ("**Retries:** The client retries..."), nothing was lost and the label is the tell.
  Promoting this rule means running that test against a real corpus first.

### rule-em-dash: Overuse of em dashes

- detectability: mechanical
- applicability: general-prose
- v1: script
- The `—` character (`\xE2\x80\x94`) in prose. **Zero-tolerance by default**: any occurrence
  outside code fences and inline code flags. Documents that require em dashes opt out
  per-document via config path-lists or the in-file marker; the rule is never
  threshold-calibrated and is excluded from the `recorded-only` demotion path.
- The source page's Style section (catalog pin and the 2026-08-21 recheck) lists this as a
  **valid sign**, not an ineffective one, with its own qualifier about weighing it alongside
  other signs. That qualifier is a corroboration note on a kept tell, not a listing under
  **Ineffective indicators** (checked explicitly; see that section). The shipped default stays
  zero-tolerance: this plugin is a house-style detector, not a Wikipedia AI-authorship tribunal.
  A consuming repo that wants the source's combination reading disables the rule or uses
  `em_dash_allowed_paths` (or the generalized `rule_allowed_paths`).
- **Spacing qualifier (mined 2026-08-25 from the same pinned section):** the source's section
  separates spaced from unspaced em dashes as tells; read the distinction there. The shipped rule
  stays character-level zero-tolerance as house style. A consuming repo calibrating a softer
  setting can match only spaced em dashes (`—` with a space on each side).
- **Zero-tolerance is a house-style choice, not a detection claim.** The false-accusation
  literature the source's Caveats cite is one more reason this rule's verdict is "this repo
  does not use em dashes", never "this text is AI-written".

### rule-emoji-formatting: Emoji as formatting

- detectability: mechanical
- applicability: general-prose
- v1: script
- Emoji used as bullets, section markers, or visual separators in prose.
- A leading `U+26A0` (warning sign) opening a caveat line is in scope. It is an emoji used as a
  section marker, and the fix is a text label such as "Caveat:". The rubric never counts it as
  a human counter-sign; "Signs of human writing" carries the same ruling for rubric agents.

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
- Assistant-frame residue, both halves of the source section (extraction completed 2026-08-25;
  the original ERE covered roughly one of the section's six words-to-watch families and missed
  even one of the source's own examples, now in the cutoff list below):
  - Cutoff half: "as of my knowledge cutoff", "as of my last (knowledge) update", "up to my
    last training update", "I cannot browse", "as an AI (language) model".
  - Source-gap (RAG-era) half: "while specific details are limited/scarce", "not widely
    available/documented/disclosed", "in/from the provided/available sources (or search
    results)", "based on (the) available information". The bare, unqualified "in the search
    results" is deliberately NOT matched: it is ordinary prose in any document describing a
    search feature, so the ERE requires the provided/available qualifier that marks the
    RAG-disclaimer register.

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

Fetch gap closed 2026-08-21 (see the upstream-drift record). The source section is Wikipedia
talk-page comments, so every tell classifies `wikipedia-specific` / `recorded-only`. They have
no general-prose analogue worth a script rule. Distilled from the catalog pin (revision
1369699198, parse section 62) and confirmed on the live page (revision 1370403579).

One of the seven tells already has a slug under Edit summaries: downplaying AI use by
claiming policy adherence is `rule-canned-policy-assurance`. The other six land here.

### rule-misquoted-policies: Misquoted policies and invented shortcuts

- detectability: judgment
- applicability: wikipedia-specific
- v1: recorded-only
- Talk-page comments that cite made-up policy shortcuts or misstate existing ones. Wikipedia
  project-page namespace; no markdown-corpus analogue.

### rule-maintenance-banner-transclusion: Transcluded maintenance banners in comments

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Transcluding a maintenance banner whenever the comment mentions it. Wikitext talk-page
  convention.

### rule-sectioned-comments: Lengthy comments divided into titled sections

- detectability: mechanical
- applicability: wikipedia-specific
- v1: recorded-only
- Talk-page comments split into titled sections in Markdown, plain text, or level-2/3
  subheadings. Distinct from `rule-verbose-edit-summaries`, which is the edit-summary field.

### rule-request-critic-input: Requests for critics to specify improvements

- detectability: judgment
- applicability: wikipedia-specific
- v1: recorded-only
- Asking critics or other editors to say exactly what to improve, as a deflection. Talk-page
  register.

### rule-dismiss-origin-speculation: Dismissing AI-origin concerns as speculation

- detectability: judgment
- applicability: wikipedia-specific
- v1: recorded-only
- Treating questions about whether the comment is AI-generated as "unsubstantiated
  speculation" rather than addressing the content tells. Talk-page register.

### rule-redirect-to-content: Redirecting AI concerns toward content improvement

- detectability: judgment
- applicability: wikipedia-specific
- v1: recorded-only
- Urging critics to improve the content instead of worrying that it is AI-generated.
  Talk-page register.

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

A leading `U+26A0` (warning sign) opening a caveat line is NOT a counter-sign. It is an emoji
used as a section marker, which the detector reports under `rule-emoji-formatting` (the fix is
a text label such as "Caveat:"), so it never lowers a rubric verdict.

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

Fetch gap closed 2026-08-21 (see the upstream-drift record). This section lists signals the
page's own editors consider **unreliable** for LLM detection. It is a guardrail on our roster,
not a source of new rules. A signal listed here must not become a rule.

**Verdict: no shipped rule appears here.** Compared against all 15 `v1: script` slugs in
`detect.sh`, including the two candidates named when this gap was filed (`rule-em-dash`,
`rule-rule-of-three`). Both of those live in other source sections as *valid* signs
(Style / Language and grammar). The eight ineffective indicators are the same on the catalog
pin (revision 1369699198, parse section 80, 2026-08-16) and the live recheck (revision
1370403579, retrieved 2026-08-21 from
<https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing>).

The eight, named only; the page's reasons for each are read at the pointer in the
[upstream-drift record](#upstream-drift-record), not stored here. Each line states what this
catalog does about it:

- **Perfect grammar**: no rule.
- **Combination of casual and formal registers**: no rule.
- **Bland or robotic prose**: no rule.
- **Fancy, academic, or formal prose**: no rule. `rule-ai-vocabulary` is the specific-word rule,
  not a formality detector.
- **Transition words (in isolation)**: no standalone transition-words rule. The shipped
  vocabulary list already dropped `additionally` for legitimate technical use.
- **Unsourced content**: no rule.
- **Bizarre wikitext**: no rule; these are not the LLM markup tells already catalogued under
  Markup.
- **Correct wikitext**: no rule.

None of those eight is a shipped script rule, a shipped rubric tell, or a slug from the
general-prose additions. No drop or re-scope follows.

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

## General-prose additions

Tells the Wikipedia inventory lacks, for prose outside Wikipedia. The overlap map below places
common general-prose patterns that an earlier entry already covers, and the new entries follow it.

### Overlap map

Patterns **catalogued by** a Wikipedia-derived entry, or routed to the rewrite guide
(fix-time guidance is not a tell inventory). "Catalogued" is deliberately weaker than "covered":
a row pointing at a `recorded-only` entry is bookkeeping, not detection. Nothing runs it in
either layer, and those rows say so.

| Pattern | Where it lives here |
|---|---|
| Puffery | `rule-significance-inflation` |
| Name-dropping | **Not detected. Deliberately out of scope for general prose.** `rule-canned-notability` records the Wikipedia-specific form and is `recorded-only`; its own entry says there is no general-prose analogue worth a rule. Not `rule-vague-attribution`, which is the opposite tell (naming *no* source, not naming many with no content) |
| Superficial -ing phrases | `rule-superficial-analysis` |
| Promotional language | `rule-promotional-language` |
| Vague attributions | `rule-vague-attribution` |
| Formulaic challenges | `rule-challenges-conclusion`, the "Despite its X, faces challenges" formula its ERE actually matches |
| Generic conclusions | **Only the formulaic half is detected**, by the row above. A bare optimism closer ("The future looks bright") matches no shipped rule: `rule-superficial-analysis` needs a present-participle tail and does not reach it |
| AI vocabulary; prefer the plain word | `rule-ai-vocabulary` (the plain-word list joined the shipped vocabulary default; see the calibration record) |
| Fancy ways to say "is" | `rule-copulative-avoidance` |
| "Not just X, but Y" | `rule-negative-parallelism` |
| Rule of three | `rule-rule-of-three` |
| Synonym cycling | `rule-elegant-variation` |
| Em dash overuse | `rule-em-dash`; the no-substitute-tell guardrail (no parentheses or en dashes in its place) is fix guidance in `rewrite-guide.md` |
| Boldface overuse | `rule-bold-overuse`, which is `recorded-only` and so catalogued and dormant |
| Inline-header lists | `rule-inline-header-lists`, which is `recorded-only` and so catalogued and dormant; the boundary refinement in that entry is calibration pre-work, not a live boundary |
| Title case headings | `rule-title-case`, which is `recorded-only` here (the markdown linter lane owns heading structure) |
| Decorative emojis | `rule-emoji-formatting` |
| Curly quotes | `rule-curly-artifacts` |
| Cutoff disclaimers | `rule-knowledge-cutoff-disclaimer` |
| Adding soul (voice); plain speech (mechanism over feeling, sentence splitting, active voice, adverbs) | `rewrite-guide.md` (rewrite disciplines, not detection tells); the mechanism-over-feeling test also flags via `rule-mechanism-free-claims` below |

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
- Currency note (2026-08): "You're absolutely right" and "Found the smoking gun" remain the two
  headline Claude tells of the 2025-2026 era. Anthropic's own account acknowledges the former
  and vendor-repo issues track it; the latter is documented defying an explicit CLAUDE.md ban
  mid-sentence. Both resist user-level suppression instructions; sources in the
  "Model-era additions" record below.

### rule-filler-phrases: Filler phrases

- detectability: mechanical
- applicability: general-prose
- v1: script
- Multiword filler with a shorter exact equivalent: "in order to" (for "to"), "due to the fact
  that" (for "because"), "it is important to note that", "it is worth noting that", "it should
  be noted that" (all deletable). Fires per occurrence; each hit has a mechanical rewrite.
- **Recorded divergence from the source (2026-08-25):** the source's Syntax counter-sign list
  counts the "in order to" construction among signs of HUMAN writing (an uncited bullet, and the
  study its neighboring bullet cites does not measure this construction). This rule keeps
  flagging it deliberately: the plugin's goal is concise house
  style, not authorship attribution, and "in order to" -> "to" is de-verbosing every style
  authority endorses. The divergence is a house-style choice, recorded rather than hidden.

### rule-stacked-hedging: Stacked hedging

- detectability: mechanical (stacked core), judgment (residual)
- applicability: general-prose
- v1: script
- Two hedges propping each other up: "could potentially", "may potentially", "might possibly",
  "could possibly", "might potentially". One hedge is a claim about uncertainty; two is filler.
  Hedging spread across a sentence ("one might say it could perhaps") needs a reader and falls
  to the rubric.

### rule-false-ranges: False ranges

- detectability: judgment
- applicability: general-prose
- v1: rubric
- A "from X to Y" construction whose endpoints share no scale ("from dashboards to microservices"):
  a list dressed as a spectrum. The construction is mechanical but the scale call is not, and
  legitimate ranges ("from 2 to 10 seconds") dominate; rubric only.

### rule-colon-crutch: Colon as mid-sentence connector

- detectability: judgment
- applicability: general-prose
- v1: rubric
- A colon splicing two clauses for rhythm. The rule's one test: report when the text after
  the colon neither lists items nor gives an example of the clause before it, AND the pair
  reads as one sentence spliced for rhythm in explanatory prose. Whether the first clause
  could stand alone is not this rule's test. Colons before lists and examples are fine; the
  connector use needs a reader to distinguish, so no script core ships.
- Reported, from a skill body's explanatory paragraph: "This step matters more than it looks:
  a skipped list leaves the rubric nothing to read." Nothing is listed or exemplified, and the
  colon stages a reveal where "because" or a full stop would serve.
- Declined, from a CLAUDE.md rule list: "Never push from a worktree you did not create:
  another session may own it." A terse `rule: reason` line in a list of operative rules is out
  of scope in any file, whether CLAUDE.md, AGENTS.md, a `.claude/rules/` file, a skill step, or
  a "Rules" list inside ordinary docs. There the colon is the usual way to pair a rule with its
  reason, and reporting it would flood every instruction file.

### rule-abstract-metaphor-jargon: Abstract metaphor nouns

- detectability: mechanical (word cues), judgment (literal versus metaphor)
- applicability: general-prose
- v1: rubric
- Metaphor nouns used where a literal word exists: "substrate", "wedge", "nexus", "locus",
  "vantage", "north star", "flywheel", "bedrock", "endgame", "gold-plating", plus "primitive",
  "harness", "scaffolding", "vector", "surface", "ratchet", "paradigm", "modality", and
  "evacuate" (for moving code) in their metaphorical (not domain-literal) senses. The tell turns on the literal-versus-metaphor call:
  "harness" naming an actual test harness is not a tell. Calibration kept this out of the script
  layer (see the calibration record's second pass). Replacements live in `rewrite-guide.md`.
- **Model-era cues (2026-08, from the "Model-era additions" section)**: "load-bearing" and
  "seam" join the cue list as the flagship 2026 Claude-family metaphor words (both measured far
  above their Stack Overflow base rate in Claude Code output; the figures are at the
  archiewood/claudeisms pointer under "Model-era additions"). Their
  literal boundary is BROAD, deliberately: a Feathers seam in refactoring/testing prose, a
  load-bearing wall, and a load-bearing invariant or instruction NAMED as such deliberately in
  architecture prose are all terms of art, not tells. The tell is the reflexive metaphor where
  a plainer word served ("this comment is load-bearing" for "this comment matters"). These cues
  carry no config lever, because the rubric layer reads no config. The boundary text here and
  the saturation rule below are the only way to suppress a finding.
- **Seam examples.** Declined as a term of art: "introduce a seam at the constructor so the
  test can substitute the clock", a Feathers seam in testing prose. Reported: "the seam
  between the billing service and the account service", a system boundary described by
  metaphor, where "boundary" is the plainer word.
- **Saturation.** Counted per audit scope, over the prose the rubric reads. Excluded: YAML
  frontmatter (closed by a `---` or `...` line), fenced and indented code, code spans,
  straight and curly double-quoted spans (also when wrapped across lines), blockquotes, HTML
  comment interiors (a comment opener escaped with a backslash opens nothing), raw HTML tags on one line
  (the text between tags counts), link and image destinations (the link text counts),
  reference definitions (also as a list item's first content), and autolinks. Known gaps: a
  cue split across a line break is not counted; a few rare CommonMark shapes (indented code
  right after a fence or paragraph line, an unclosed comment block inside a list item, a
  definition continued on the next line, destinations with nested parens, a raw HTML tag
  split across lines) are counted as prose; and an inline comment's `-->` is sought past a
  block start up to the next blank line. The usage
  text of `rubric-fanout.sh` states the exact rules. A cue is saturated
  when it appears in at least 10 files AND in at least 10% of the readable files in scope.
  `rubric-fanout.sh plan` computes the counts and the verdict into `cues.txt` in the batch
  directory; a batch reads the verdict there and never judges saturation from its own batch.
  Saturated hits are not reported per finding. The batch records one
  `declined: rule-abstract-metaphor-jargon <cue> reason=saturated` line instead, and cleanup
  is a fix-pass decision for that repo. A hit dropped by the per-file or per-batch finding cap
  is recorded with `reason=cap`. Unsaturated hits are judged per instance: a reflexive
  metaphor is reported, and a term-of-art use is declined with
  `declined: rule-abstract-metaphor-jargon <cue> reason=boundary`. Counts cover only
  "load-bearing" and "seam" because only they carry this saturation clause. Other cues are
  not counted, since counting them would add suppression this entry never grants. An audit with no `cues.txt` (a single file, no fan-out) treats both cues as
  unsaturated.

### rule-figure-for-fact: An image the reader must turn back into a claim

- detectability: judgment
- applicability: general-prose
- v1: rubric
- The writer had a plain claim and wrote a picture of it instead, so the reader has to work the
  claim out again. Four kinds are reported:
  - a comparison to an unrelated scene: "upgrading the ORM was like defusing a bomb", "tuning
    retries is herding cats";
  - a consequence told as a small drama: "skip the migration check and the on-call phone lights
    up at 3 a.m.";
  - a program, file or service credited with moods or opinions: "the scheduler hates overlapping
    jobs", "CI gets grumpy about lockfiles";
  - a slogan where the rule and its reason belong: "ship small, sleep well", "green builds or
    bust".
- Before reporting, write the literal sentence. Report the original when the literal one is about
  as long and tells the reader something the picture hid, such as an error code, a count or a
  step: "the scheduler hates overlapping jobs" hides "the scheduler skips a run while the previous
  run of the same job is still going". The fix is in `rewrite-guide.md`.
- Not reported: a field's own term that only looks figurative (a process forks, a queue drains, a
  cache is warm, a thread starves), since each names a defined behavior, and quoted text, as for
  every rubric tell. When a sentence's only figure is a noun from the list in
  `rule-abstract-metaphor-jargon` ("seam", "load-bearing", "north star"), that rule takes the
  finding and this one says nothing about the sentence.
- Reported, from a billing runbook: "Let the cron job drift and the unpaid invoices pile up like
  snow." Declined, from the same runbook: "The worker thread starves when the pool holds fewer
  than four connections", where starvation is the scheduling term.

### rule-mechanism-free-claims: Feeling-words instead of mechanism

- detectability: judgment
- applicability: general-prose
- v1: rubric
- A sentence that names how the thing feels where the reader needs its mechanism or a number
  ("the config feels lightweight" where "the config file has four keys" would serve). Report it
  when it gives the reader nothing to act on or check (no step, fact, or number), or when it is
  generic enough to fit any project's docs.

### rule-over-compression: Clipped prose the reader has to rebuild

- detectability: judgment
- applicability: general-prose
- v1: rubric
- Prose for people, cut so short that the reader has to work out how its parts fit. Report it
  when a reader cannot tell, without guessing:
  - what a term stands for: team shorthand such as "cfg", "impl", "w/o" or "b/c" on a page
    written for newcomers;
  - how two steps connect: clauses lined up with no "then", "because" or "if", so order, cause
    and condition all read the same;
  - what a symbol means: "→", "=", "+" or "/" used for "causes", "is", "and" or "or"
    ("rollback = previous tag");
  - which thing is meant and who acts: a run of bare nouns with no article, subject or verb
    ("image build, registry push, tag bump").
- It applies to running prose for people: READMEs, guides, design docs and release notes. The fix
  is in `rewrite-guide.md`; in a release note, "Auth svc moved to new IdP, sessions dropped,
  re-login req'd" becomes "We moved the authentication service to the new identity provider.
  Existing sessions ended, so every user has to sign in again."
- Out of scope: tables, command and option references, code and code comments, commit subjects,
  and operative lists kept terse for an agent reader (rules files, skill steps). A repository
  that compresses agent-read files with `/docs-hygiene:compress` and its `compress_articles`
  setting at `cut` drops articles there on purpose; that setting's default, `keep`, does not
  produce this tell.
- Reported, from a contributor guide: "Fork, branch per fix, PR w/ tests, wait CI green."
  Declined: the same steps as a numbered checklist in a skill's operative instructions.

## Model-era additions (repo-owned)

The repo-owned, evolving inventory of CURRENT-generation model-vocabulary tells, the layer
the Wikipedia source page has not absorbed yet (verified against its head; see the model-era record below). This section is
this repository's own work, not adapted from the Wikipedia page, so the CC BY-SA statement at the
top of this file (scoped to "the adapted material in this file") does not cover it; each entry
cites the community sources it rests on. It exists to move faster than the upstream
inventories: when a new model generation
introduces a tic, the entry lands here first, graded by its evidence, and migrates to the
Wikipedia-derived inventory only if upstream later absorbs it.

Every entry in this section carries an **evidence grade**, and the grade gates placement:

- `locally-observed`: seen by this repo's owner in the wild; no indexed external attestation.
  Eligible for `recorded-only` or the rubric ONLY. Never a shipped script rule on one
  observer's evidence.
- `community-attested`: documented by independent community sources (threads, catalogs,
  filter lists). Eligible for any layer its false-positive measurement supports.
- `measured`: carried by at least one quantitative frequency measurement. A SINGLE pool is
  still single-pool: the measured-narrowing gate (density stays quiet on legitimate files AND
  firing files are genuine residue, measured on a real corpus) governs promotion into any
  shipped default word list.

Consumer repos extend the phrase layer via `phrase_add`/`phrase_remove` and the vocabulary
layer via `vocab_add` (README "Configuration"); the update workflow for THIS section is in the
README's "Updating the model-era inventory".

### rule-model-era-phrases: Distinctive model-phrase constructions

- detectability: mechanical
- applicability: general-prose
- v1: script
- era: 2025-2026
- models: Claude family (the community record dates the layer to Opus 4.6 onward and attests it
  through the Opus 5 / Fable era); "unlock" also appears on GPT cliché lists, so that phrase is
  cross-model
- evidence: community-attested
- Multiword constructions distinctive enough to fire per occurrence. The shipped roster is the
  ANCHORED forms only (apostrophes spelled `.` per the detector's ERE convention):
  - `the part most people skip`: "X is the part most people skip" and kin. Four in-the-wild
    hits on HN, all 2025-2026, all in AI-tooling threads; no catalog documents it yet. Rare in
    human prose; near-zero expected yield is accepted.
  - `(the|my) honest take`: the opinion-opener construction ("The honest take is..."). The
    bare bigram "honest take" is recognized but NOT shipped: in blog-register prose it is
    ordinary human writing, and this corpus (which measured 0 hits) is the wrong corpus to
    prove otherwise.
  - `that.s the unlock`: the punchline form. The bare "the unlock" is recognized but NOT
    shipped: it has a measured domain-literal false positive in this very repo (prose about an
    actual worktree lock), and any corpus documenting locks, auth, or feature flags would fire
    the same way.
- Sources: the Hacker News Claude-ism thread (id 48905248, 609 points) and Ask HN 49045140;
  jola.dev's filter hook; Ivo Velitchkov's "A catalog of Claude cliches"; the
  archiewood/claudeisms inventory. Consumers add or remove phrases via
  `phrase_add`/`phrase_remove`. Fragments are EREs, and the joined roster is validated at
  config-read time (an invalid or empty fragment is skipped with a warning, never allowed to
  flood or silently kill the rule).

### rule-ranked-punchline: Enumerated observations with a ranked punchline

- detectability: mechanical (construction core), judgment (residual)
- applicability: general-prose
- v1: recorded-only
- era: 2025-2026
- models: Claude family (composition of two documented behaviors)
- evidence: locally-observed
- "Two observations, and one is load-bearing": an enumeration whose closer ranks one item as
  the one that matters ("N observations/problems/things, and one is load-bearing / fatal / the
  real problem"). Zero indexed attestations as a named tell (checked: HN Algolia exact
  queries, general web search; unchecked: X full-text, private corpora); its components are
  separately documented: self-ranking claims (Velitchkov's catalog) plus the load-bearing
  vocabulary below. Recorded on the repo owner's observation, which is exactly what this
  section's `locally-observed` grade is for; promotes toward a script phrase when independent
  attestations land.

### rule-belt-and-suspenders: "Belt and suspenders"

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- era: 2025-2026
- models: Claude family (attested in the HN thread)
- evidence: community-attested (disputed)
- The redundancy idiom, deployed by current Claude output at noticeable frequency, but the
  attestation is disputed in the same thread that raises it: commenters attest pre-LLM usage
  ("heard it since way before LLMs"), and it is a legitimate engineering idiom decades old.
  Recorded with the dispute; if ever promoted, density treatment only, never occurrence.

### rule-model-era-vocabulary: Frequency-cluster words (single-pool, corroborate before shipping)

- detectability: mechanical
- applicability: general-prose
- v1: recorded-only
- era: 2025-2026
- models: Claude family (Claude Code agentic output specifically)
- evidence: measured (single pool)
- The archiewood/claudeisms measurement: one author's Claude Code transcripts ranked against a
  Stack Overflow comment corpus. The word list, ratios and the author's own caveats are at
  <https://github.com/archiewood/claudeisms> (README and `claudeisms.csv`). We class it
  single-pool: one author, one workflow. As of: 2026-10-01. Recheck trigger: the README's ranked
  tables change, or a second independent frequency pool appears.
- ONE of these ships in the default vocabulary list: `pre-existing` passed the measured
  quiet-gate test on this corpus (2026-08-27: 61 files contain the word, the density gate
  fired on none of them, the same measurement that admitted "leverage"), so it joined the
  shipped `rule-ai-vocabulary` list. The rest do NOT ship. Measured on this repository's
  corpus, even the pruned distinctive core fires on domain-literal prose (`uncommitted` in a
  git document, `dedup` in a dedup-pass reference), the exact class the shipped list's own
  admission rule excludes. The broad list would flag 47% of the corpus. Each remaining
  word is a per-word candidate behind the measured-narrowing gate; until a word passes on a
  real corpus, the closure for a repo that wants it is `vocab_add` (the README lists the
  candidates). Promotion of the cluster as a class additionally waits on a second independent
  frequency pool (see the record's recheck trigger).

### Model-era record

This section holds the model-vocabulary layer this repository tracks from community sources, and
keeps it here because the Wikipedia page did not carry it when checked.

- **Pointer**: the per-entry sources named in each entry and in the record below; for the
  absence check, the live Wikipedia page.
- **As of**: 2026-08-26
- **Recheck trigger**: each `ai-slop` release, each new frontier-model generation, and, for
  `rule-model-era-vocabulary`, whether a second independent frequency pool has landed (the
  cluster's promotion condition, which no other trigger would look for).
- **Record (2026-08-26, initial)**: layer established from the Hacker News thread 48905248
  (609 points), archiewood/claudeisms (two-measurement corroboration for "load-bearing": its
  lower-bound ratio and Marek Suppa's independent count),
  anthropics/claude-code issue 53454 (maintainer-reproduced), Velitchkov's cliché catalog,
  crystl.dev's hacker-idiom catalog, and jola.dev's filter hook. Wikipedia "Signs of AI
  writing" head revision 1371415133 (fetched 2026-08-26) carries none of it. Harness confound recorded on the metaphor
  cues: the version-tracked Piebald-AI system-prompt mirror uses the word "load-bearing" in its
  progress-update instruction, so "load-bearing" in Claude Code output is partly prompt-primed
  rather than purely model-weight; the frequency spike aligns
  with the Opus 4.6 release date and the word appears in non-Code output, so the weights-side
  claim stays alive at MEDIUM. A harness prompt change can therefore collapse a phrase's base
  rate overnight. Attribution notes exist so a recheck knows which entries die that way.
