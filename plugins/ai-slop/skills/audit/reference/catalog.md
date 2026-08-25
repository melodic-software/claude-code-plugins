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

65 tells catalogued from the Wikipedia source revision, plus 7 in the "Cursor unslop additions"
section at the end of this file. Entry marker: `### rule-<slug>: <name>`. The qualified id used
in crosswalk rows and findings files is `ai-slop/audit/rule-<slug>`. Fields:

- **detectability**: `mechanical` (patterns a script can match) or `judgment` (needs a reader).
- **applicability**: `general-prose` (any markdown/docs corpus) or `wikipedia-specific`
  (only meaningful inside Wikipedia's editing model).
- **v1**: `script` (implemented in detect.sh), `rubric` (skill judgment layer), or
  `recorded-only` (catalogued, not run; reason given).

## False-positive posture (source Caveats)

Mined from the pin's Caveats section (byte-identical on the live head; extraction closed
2026-08-25). Three source statements bind how this catalog's verdicts are read:

- **The signs are descriptive, not prescriptive.** The source: "do not merely treat these signs
  as the problems to be fixed; that could just make detection harder." This plugin's fix flow
  is therefore framed as house style (better prose on its own merits), never detector evasion;
  the rewrite guide's non-evasion posture carries the operational test.
- **Expert false-positive rate.** The source's calibration figure: an experienced LLM-output
  patroller who tags 10 pages has probably made one false positive. A deterministic subset of
  those signs run over a technical corpus is not better calibrated than the experts; verdicts
  are evidence for a rewrite decision, never proof of provenance, and accusatory framing
  ("this is AI-written") is outside this plugin's vocabulary.
- **Combination over isolation.** Individual signs are weak alone; the source repeats per-sign
  that combination strengthens a verdict. Density thresholds, the minimum-hits floor, and the
  rubric's counter-sign tempering are this catalog's mechanical forms of that instruction.

## Quotation exemption (policy-level)

Stated once here and inherited by every rule; the design follows Wikipedia's MOS "principle of
minimal change" for quoted material (quotations are not the repo's own prose to restyle) and the
detector implements it mechanically. Each rule carries a class:

- **wording** — the rule judges prose the repo AUTHORS. It never scans quoted material:
  blockquote lines and double-quoted spans are removed from its input, and inline code spans
  were already exempt. Quote-exempt candidates are counted as declined, never silently dropped.
  This is also the use/mention boundary: a document that QUOTES a tell to document it (a style
  guide, a forbidden-phrase list, a changelog citing the phrase a fix removed) is mentioning,
  not using, and backticking or double-quoting the mention is the marker-free suppression.
- **typography** — the rule targets artifacts that are defects wherever they sit (em-dash
  bytes, curly-paste residue, formatting emoji, model citation tokens, tracking parameters).
  It scans quoted material too; MOS makes the same split by permitting typographic
  normalization inside quotations while forbidding wording edits.

Known limitation: the double-quoted-span exemption is per-line. A quotation wrapped across a
line break escapes it; the closures are rewrapping the quote onto one line, the blockquote
form, or the fenced marker.

The class assignments live in the detector's rule registry; the crosswalk rows are unchanged by
the exemption (it moves candidates from findings to declines, not between tiers).

## Calibration record (V1)

Calibrated 2026-08-17 against this marketplace's tracked markdown (1161 files) with neutral
defaults. Outcomes:

- All 12 `v1: script` rules ship as of this pass; none demoted. (The roster is 15 after the
  second pass below adds three, and 14 after the third pass demotes `rule-rule-of-three`.)
- Density rules gained a minimum-hits floor (3) after short files fired on a single
  normal-prose occurrence (one triad in a 201-word document hit 5.0/1000 words).
- `rule-knowledge-cutoff-disclaimer` has a known false-positive class: prose ABOUT model
  knowledge cutoffs (documentation discussing models). Remedy is the in-file marker or config
  exclusion, recorded here rather than weakening the rule. **Measured on the 1214-file dogfood
  corpus (2026-08-19): all 8 findings fall in that class** — model-spec sentences quoting a
  cutoff date, prose arguing that cutoffs are upstream-owned, and the crosswalk row naming this
  rule. Zero were genuine assistant-frame residue. The class is therefore the rule's whole yield
  on a corpus that documents models, which is the corpus type most likely to trip it; it is not
  evidence the rule is wrong, because the tell it targets is absent here rather than missed.
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

Third pass, 2026-08-25, from a full repo-wide `fix` dogfood of PR 3359 (82 findings across 45
files) plus a plugin-quality audit and a verified prior-art survey:

- `rule-rule-of-three` demoted to rubric per its own calibration clause: 18 of 18 residual
  findings after the fix pass sat on load-bearing enumerations, the ERE matched only
  single-word triads, and no surveyed prose linter implements the tell. See the entry.
- The quotation exemption (section above) was added after roughly half of the pass's ~40
  suppression markers protected quoted or tell-documenting text — one use/mention problem the
  policy now closes marker-free. Measured on the same corpus after the change: the exemption
  moved those candidate classes from findings to declines with no loss on unquoted prose.
- `rule-knowledge-cutoff-disclaimer` gained the source section's missing phrase families (the
  candidate-additions research measured 0 pre-existing hits for the new families on this
  corpus, so the extension ships without a threshold change).
- `rule_allowed_paths` generalized the per-rule path exemption the em-dash rule already had,
  as the proportionate closure for density verdicts a line marker cannot quiet.

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
- Demoted from the active rubric 2026-08-25: the live source page moved this sign to its
  Historical indicators (base rate collapsed in current model output), and this catalog
  follows the upstream demotion rather than keeping an era-bound tell active.

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
- The source page's Style section (catalog pin and the 2026-08-21 recheck) treats this as a
  **valid sign**, not an ineffective one. The same section carries the qualifier *"This sign
  is most useful when taken in combination with other indicators, not by itself."* That is a
  corroboration note on a kept tell, not a listing under **Ineffective indicators** (checked
  explicitly; see that section). The shipped default stays zero-tolerance: this plugin is a
  house-style detector, not a Wikipedia AI-authorship tribunal. A consuming repo that wants the
  source's combination reading disables the rule or uses `em_dash_allowed_paths` (or the
  generalized `rule_allowed_paths`).
- **Spacing qualifier (mined 2026-08-25 from the same pinned section):** the source
  distinguishes SPACED em dashes ( — ) as the stronger AI tell, while unspaced em dashes are
  the typographically informed human convention; it cites reporting (The Economist, 2026-07-30,
  wiki-cited, not independently verified here) that among current models only Claude still
  over-uses them. The shipped rule stays character-level zero-tolerance as house style, and
  records the spacing discriminator here for any consuming repo calibrating a softer setting.
- **Zero-tolerance is a house-style choice, not a detection claim.** The false-accusation
  literature the source's Caveats cite is one more reason this rule's verdict is "this repo
  does not use em dashes", never "this text is AI-written".

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
- Assistant-frame residue, both halves of the source section (extraction completed 2026-08-25;
  the original ERE covered roughly one of the section's six words-to-watch families and missed
  even the source's own example "as of my last knowledge update"):
  - Cutoff half: "as of my knowledge cutoff", "as of my last (knowledge) update", "up to my
    last training update", "I cannot browse", "as an AI (language) model".
  - Source-gap (RAG-era) half: "while specific details are limited/scarce", "not widely
    available/documented/disclosed", "in the provided/available sources", "in the search
    results", "based on (the) available information".

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
talk-page comments, so every tell classifies `wikipedia-specific` / `recorded-only` — they have
no general-prose analogue worth a script rule. Quoted from the catalog pin (revision
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
page's own editors consider **unreliable** for LLM detection — a guardrail on our roster, not
a source of new rules. A signal listed here must not become a rule.

**Verdict: no shipped rule appears here.** Compared against all 15 `v1: script` slugs in
`detect.sh`, including the two candidates named when this gap was filed (`rule-em-dash`,
`rule-rule-of-three`). Both of those live in other source sections as *valid* signs
(Style / Language and grammar). The eight ineffective indicators are the same on the catalog
pin (revision 1369699198, parse section 80, 2026-08-16) and the live recheck (revision
1370403579, retrieved 2026-08-21 from
<https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing>).

Quoted from the pin (CC BY-SA 4.0; ellipses mark dropped citation/example markup):

> False accusations of AI use can drive away new editors and foster an atmosphere of
> suspicion. […] Here are several somewhat commonly used indicators that are ineffective
> in LLM detection—and may even indicate the opposite.

- **Perfect grammar** — skilled human writers also produce this.
- **Combination of casual and formal registers**, or language that sounds both "clinical"
  and "emotional" — technical-field casual writing, mixed registers, or multi-editor pages.
- **"Bland" or "robotic" prose** — LLM output has *specific* traits; "robotic" is not one.
- **"Fancy", "academic", or "formal" prose** — the page's own wording: LLMs favor *specific
  words*; "the correlation does not extend to all formal, academic, or 'fancy'-sounding
  prose." `rule-ai-vocabulary` is the specific-word rule, not a formality detector.
- **Transition words (in isolation)** — older output overused a few (`Additionally`,
  `Consequently`, `Notably`); "this is not a strong tell." The shipped vocabulary list
  already dropped `additionally` for legitimate technical use; there is no standalone
  transition-words rule.
- **Unsourced content** — most uncited articles predate LLMs; modern chatbots also cite.
- **Bizarre wikitext** — random HTML/VisualEditor artifacts are *not* the LLM markup tells
  already catalogued under Markup.
- **Correct wikitext** — correct formatting is normal.

None of those eight is a shipped script rule, a shipped rubric tell, or a Cursor-addition
slug. No drop or re-scope follows.

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
- **Recorded divergence from the source (2026-08-25):** the source's Syntax counter-sign list
  names "isolated wordy constructions such as 'in order to'" among signs of HUMAN writing (an
  uncited bullet, and the study its neighboring bullet cites does not measure this
  construction). This rule keeps flagging it deliberately: the plugin's goal is concise house
  style, not authorship attribution, and "in order to" -> "to" is de-verbosing every style
  authority endorses. The divergence is a house-style choice, recorded rather than hidden.

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
