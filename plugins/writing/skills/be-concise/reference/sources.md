# Sources for the concise-writing doctrine

## Contents

- [Nielsen Norman Group](#nielsen-norman-group)
- [Government and vendor writing standards](#government-and-vendor-writing-standards)
- [Completeness-floor sources](#completeness-floor-sources)
- [Evidence on the reader model](#evidence-on-the-reader-model)

Every rule in [`doctrine.md`](doctrine.md) is paraphrased from one of the
sources below. Nothing upstream is vendored into this repository, and no
article is reproduced. An entry that records a figure from its basis is a
stored value under this repository's upstream-drift convention, so it carries
the claim, the basis with its URL, the as-of date and the recheck trigger that
obliges re-deriving the claim. Every other entry says how the doctrine uses its
source and points to it, and stores nothing from it.

The as-of date on each such entry is the verified research run of 2026-09-05,
which fetched each basis directly. A date is not authority. Re-fetch the basis
before relying on a claim; the stamp is a ceiling on how current the claim can
be.

Three entries carry no rule of the doctrine. The licensing entry records our rule
for quoting Nielsen Norman Group and why nothing is vendored. The two
meta-analysis entries record the evidence that contradicts the 1997
screen-reading premise, which the doctrine states rather than hides.

Quoted runs attributed to nngroup.com are kept to a few words each, with the
company, the author and the link credited, per the licensing rule below.

## Nielsen Norman Group

### Concise, Scannable, and Objective (Morkes and Nielsen, 1997)

Claim: A five-condition, 51-user experiment on one seven-page site measured
usability at 58% higher for concise text, 47% higher for scannable text, 27%
higher for objective text, and 124% higher for all three combined. The concise
condition was the control cut to about half its word count. This is the only
controlled experiment behind the doctrine's four properties.

Basis: https://www.nngroup.com/articles/concise-scannable-and-objective-how-to-write-for-the-web/

As of: 2026-09-05

Recheck when: a replication, a retraction, or a published refutation of the
1997 study appears, or the article's own figures change.

### Be Succinct! Writing for the Web (Nielsen, 1997)

Claim: The size target is no more than half the text a print draft would carry,
plus write for scannability and split long content across linked pages. The
article's stated rationale, that screen reading is about 25% slower than paper,
is not supported by current evidence; see the two meta-analysis entries below.

Basis: https://www.nngroup.com/articles/be-succinct-writing-for-the-web/

As of: 2026-09-05

Recheck when: the article changes its 50% guideline, or newer evidence
restores or further undermines the screen-reading premise.

### Rewriting Digital Content for Brevity (Dykes, 2023)

Claim: Seven revision techniques (kill your darlings, cut unnecessary words
including expletives and redundant modifiers, remove redundancy, evaluate
dependent clauses, match detail to purpose, cut excess information, rearrange)
with the governing question "Does the reader need this to understand me?". No
numeric targets are given.

Basis: https://www.nngroup.com/articles/rewriting-content-brevity/

As of: 2026-09-05

Recheck when: the article adds, drops or renumbers a technique, or introduces
a numeric target.

### Inverted Pyramid (Schade, 2018)

Our use: property 1 cites this article as one of the four sources for its
point-first rule, which is the whole of the inverted pyramid, and as the model
for its ranking rule (key points, then supporting detail, then background).

- **Pointer**: when checking property 1's ordering against its source, fetch
  [Inverted Pyramid](https://www.nngroup.com/articles/inverted-pyramid/) live.

### F-Shaped Pattern of Reading (Pernice, 2017, last reviewed 2026-08-19)

Our use: the rule to front-load headings and the opening words of each
paragraph cites this article. The doctrine keeps that rule even where the F
shape itself is disputed, because the rule needs only that attention falls at
the start of lines, not any one scan shape.

- **Pointer**: when checking the front-loading rule against its source, fetch
  [F-Shaped Pattern of Reading](https://www.nngroup.com/articles/f-shaped-pattern-reading-web-content/)
  live.

### How Little Do Users Read? (Nielsen, 2008)

Claim: Users have time to read at most 28% of the words during an average
visit, and 20% is the likelier figure. Derived from 45,237 page views in a
2008 ACM study, with a university-employee sample and pages of 30 to 1,250
words.

Basis: https://www.nngroup.com/articles/how-little-do-users-read/

As of: 2026-09-05

Recheck when: the article restates the figure from newer data, or a newer
large-sample study of reading proportion is published.

### Plain Language Is for Everyone, Even Experts (Loranger, 2017)

Claim: Domain experts preferred plain, succinct content in usability sessions.
The article gives 15 to 20 words per sentence and fewer than half the words of
a printed publication, as targets rather than tests.

Basis: https://www.nngroup.com/articles/plain-language-experts/

As of: 2026-09-05

Recheck when: the article changes either number, or withdraws the finding that
expert readers prefer plain language.

### Nielsen Norman Group licensing terms

Our rule: this repository vendors no Nielsen Norman Group article text. The
doctrine paraphrases, and any quoted run is a few words long and credits the
company, the author and the link, so that no file here ever depends on a
license grant.

- **Pointer**: before quoting more than a few words, or vendoring any article
  text, fetch the licensor's own
  [terms and conditions](https://www.nngroup.com/terms-and-conditions/) live.

## Government and vendor writing standards

### GOV.UK content design

Claim: Split sentences over 25 words; no more than 5 sentences per paragraph;
put the most important information first; headings must be descriptive,
front-loaded, active and removable; do not repeat the summary in the opening
paragraph; readers with higher literacy still prefer plain English. The
structure page also restates the scanning proportion, that users read only 20
to 28% of the text on a web page. The old `gov.uk/guidance/content-design` URL
now redirects to the guidance site below.

Basis: https://guidance.publishing.service.gov.uk/writing-to-gov-uk-standards/writing-guidelines/clear-language/
and https://guidance.publishing.service.gov.uk/writing-to-gov-uk-standards/writing-guidelines/clear-structure/

As of: 2026-09-05

Recheck when: either page changes the 25-word or 5-sentence number, or the
guidance moves again to a new host or slug.

### US federal plain-language guidelines

Claim: Challenge every word; express only one idea per sentence; start by
stating your purpose and the bottom line; keep paragraphs to no more than 150
words in three to eight sentences and never over 250 words; prefer active
voice, base verbs and short words, and uncover hidden verbs; the published
substitution table replaces "a number of" with "several", "at this point in
time" with "now", "is able to" with "can", and "on a monthly basis" with
"monthly". A resource article, not the guidelines themselves, suggests an
average sentence of about 20 words.

Basis: https://digital.gov/guides/plain-language (the carried-forward subset;
`plainlanguage.gov` guideline URLs redirect here) and
https://github.com/GSA/plainlanguage.gov (the archived source repository
holding the full guideline text under `_pages/guidelines/`).

As of: 2026-09-05

Recheck when: digital.gov publishes a fuller replacement for the guidelines,
or the archived GSA repository is removed or unarchived and edited.

### Google developer documentation style guide

Our use: the doctrine credits this guide for three of its rules: the
placeholder phrases cut under property 2, the numbered-versus-bulleted list rule
under property 3, and the tone rules (no exclamation marks, buzzwords, jargon,
idiom or humor) under property 4. It takes no sentence-length number from it.

- **Pointer**: when checking a rule the doctrine credits to Google, fetch
  [Google developer documentation style guide highlights](https://developers.google.com/style/highlights)
  live.

### Microsoft Writing Style Guide

Claim: Bigger ideas, fewer words; get to the point fast and then stop; prune
every excess word; avoid weak phrasing such as "there is", "there are", "there
were", and an unnecessary "you can"; content on the first screen is the most
likely to be read; three to seven lines is about the right paragraph length.

Basis: https://learn.microsoft.com/en-us/style-guide/top-10-tips-style-voice
and https://learn.microsoft.com/en-us/style-guide/scannable-content/

As of: 2026-09-05

Recheck when: either page's `ms.date` advances and a rule the doctrine states
has changed.

### AR 25-50, Preparing and Managing Correspondence (BLUF)

Claim: Effective writing is understood in a single rapid reading. The two
essential requirements are putting the main point at the beginning, the bottom
line up front, and using the active voice, which shortens sentences by removing
the passive; the regulation's own example drops a seven-word passive sentence
to five words in the active. The plain-language techniques set an average
sentence of about 15 words and paragraphs of no more than 10 lines, and define
the passive as a form of "to be" plus a past participle.

Basis: https://www.armywriter.com/AR25-50.pdf (the 2020 edition; the
`armypubs.army.mil` original returned 403, so this is a third-party mirror and
therefore one rung below a primary read)

As of: 2026-09-05

Recheck when: a primary read of the regulation becomes reachable, which
replaces this basis, or the Army publishes a new edition.

## Completeness-floor sources

### ACUS Recommendation 2017-3 (plain language in agency guidance)

Our use: one of four unrelated fields the completeness floor cites. The floor
takes from it that brevity never outranks a reader understanding the text, and
the "one link away" remedy for a brevity-completeness conflict.

- **Pointer**: when checking the floor's government-guidance basis, fetch
  [ACUS Recommendation 2017-3](https://www.govinfo.gov/content/pkg/FR-2017-12-29/pdf/2017-28124.pdf)
  live.

### DOE-STD-1029, Writer's Guide for Technical Procedures

Our use: the completeness floor cites it as the field where concise and complete
are one requirement, and takes from it two rules: set the level of detail from
what the reader already knows, and never cut a warning or caution.

- **Pointer**: when checking the floor's technical-procedures basis, fetch the
  Department of Energy record for the 1992 standard,
  [OSTI 308015](https://www.osti.gov/biblio/308015), live. The full text was read
  from a third-party mirror, one rung below a primary read.

### Linux kernel patch-submission guidance

Our use: the completeness floor cites it for change descriptions. A pull
request or commit body keeps the problem that motivated the change and its
user-visible effect at any size, because that record is what a body shortened
past the floor destroys.

- **Pointer**: when checking the floor's change-description basis, fetch
  [Describe your
  changes](https://www.kernel.org/doc/html/latest/process/submitting-patches.html#describe-your-changes)
  live.

### Claude Code concise output style

Our use: the completeness floor cites Claude Code's Concise output style as the
fourth of its unrelated fields, one that sets a content floor of its own. Which content that style keeps is the
page's to state, and this skill's floor governs its own rewrites wherever the
two differ, so compare them live rather than from a copy here.

- **Pointer**: when checking our floor against the Concise style, fetch
  [Output styles, Concise](https://code.claude.com/docs/en/output-styles#concise)
  live.

## Evidence on the reader model

### Delgado, Vargas, Ackerman and Salmeron 2018 (screen versus paper)

Claim: A meta-analysis of 54 studies and 171,055 participants found a paper
advantage on comprehension of g = -0.21, present for informational texts and
not narrative ones, and larger under time pressure. The abstract is silent on
reading speed.

Basis: https://api.semanticscholar.org/graph/v1/paper/DOI:10.1016/j.edurev.2018.09.003

As of: 2026-09-05

Recheck when: a later meta-analysis on the same question is published, or this
record is superseded by the publisher.

### Clinton 2019 (reading from paper compared to screens)

Claim: A meta-analysis of 33 studies found reading from screens worse for
performance than paper (g = -0.25), limited to expository texts, and reported
"No reliable differences were found for reading time (g = 0.08)". The 1997
premise that screen reading is 25% slower therefore has no current support,
while the comprehension result still favors shorter, better-structured
expository text.

Basis: https://api.ies.ed.gov/eric/?search=title%3A%22Reading%20from%20Paper%20Compared%20to%20Screens%22&format=json
(the ERIC API query that returns record EJ1212958 and its abstract)

As of: 2026-09-05

Recheck when: a later meta-analysis reports on reading time, or the ERIC record
for EJ1212958 changes.
