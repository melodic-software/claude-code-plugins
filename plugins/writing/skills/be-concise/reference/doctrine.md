# Concise-writing doctrine

The rules that `writing:be-concise` applies, organized by the four properties
of prose a scanning reader can use. Every rule carries a short attribution; the
full four-part drift stamp for each source, with its URL, is in
[`sources.md`](sources.md).

## How to read the scope marks

Each property is marked once, at its heading, and the mark governs every rule
under it.

| Property | Scope | Why |
|---|---|---|
| 1. The point comes first | Human readers only | An agent reading a file does not scan it or stop after one sentence |
| 2. No more words than the meaning needs | Universal | Excess words cost every reader, human or agent |
| 3. Structure that survives scanning | Human readers only | Headings, lists and bold are scanning aids and nothing else |
| 4. Factual tone | Universal | Promotional language adds length and no information for anyone |

Properties 2 and 4 are the universal set. When the `docs-hygiene` plugin is
installed, `docs-hygiene:write-for-agents` points at those two properties and
at nothing else, so agent-facing prose gets the brevity rules without acquiring
headings, bullets and bolded keywords it has no use for.

Two later sections carry their own scope mark. The completeness floor binds
every scope, human and agent alike; it sits outside the four properties because
it bounds them rather than adding a fifth thing to improve. The seven revision
techniques are universal, because they are the edits property 2 asks for.

## The reader model this rests on

People scan. Nielsen Norman Group's usage data puts a reader at about a fifth
of the words on a page in an average visit, and at most 28%. GOV.UK restates
the same range in its own guidance. Front-loaded text, short sentences and
scannable structure exist to serve that reader, not because short writing is a
virtue in itself.

The size of the effect comes from one controlled experiment: five conditions,
51 experienced users, one seven-page site (Nielsen Norman Group, Morkes and
Nielsen, 1997). Cutting the pages to about half their words raised measured
usability 58%, making the text scannable raised it 47%, stripping promotional
language raised it 27%, and all three together raised it 124%.

State that evidence honestly when it comes up. It is a single study from 1997.
No replication and no refutation has been published. The screen-reading premise
it argued from has lost its support: of the two meta-analyses stamped in
[`sources.md`](sources.md), the one that measured reading time found no reliable
difference between screen and paper, and the other reports a comprehension gap
rather than a speed one. Every other guide cited here publishes its rules as
house convention with no experiment behind them.
The rules converge across all of them, which is the real reason to follow them.

## Property 1: the point comes first

**Scope: human readers only.**

- Open with the conclusion, the decision, the status, or the ask. A reader who
  stops after the first sentence still knows what you needed. Every source that
  speaks to ordering states this rule: bottom line up front is one of the two
  essential requirements in AR 25-50, the US federal plain-language guidelines
  say to start by stating your purpose and the bottom line, GOV.UK says to put
  the most important information first, and it is the whole of the inverted
  pyramid (Nielsen Norman Group).
- Rank what follows. Key points, then supporting detail, then background
  (inverted pyramid).
- Front-load headings and the opening words of each paragraph with the words
  that carry the information. GOV.UK asks that headings be descriptive,
  front-loaded, active, and removable, meaning the text still reads correctly
  with the headings stripped out. Nielsen Norman Group's F-pattern work gives
  the same instruction for the same reason: attention concentrates at the start
  of lines and at the top of the page.
- Do not repeat the summary in the opening paragraph (GOV.UK). Say it once, at
  the top.
- The first screen carries the most (Microsoft). Anything a reader must not
  miss belongs above the fold, not below a preamble.

## Property 2: no more words than the meaning needs

**Scope: universal.** These rules improve any prose, including text only an
agent will read.

- Challenge every word. The US federal plain-language guidelines put it as a
  question to ask of each one: do you need it?
- One idea per sentence (US federal plain-language guidelines). Two ideas in
  one sentence is the most common reason a sentence runs long.
- Active voice. AR 25-50 makes it the second of its two essential requirements
  and gives the mechanism: removing the passive removes words. Its own example
  drops a seven-word sentence to five.
- Cut placeholder and filler phrasing. Google's developer documentation style
  guide names "please note" and "at this time"; Microsoft names "there is",
  "there are", "there were", and an unnecessary "you can".
- Prefer the shorter, plainer word. The federal guidelines publish the
  substitutions: "a number of" becomes "several", "at this point in time"
  becomes "now", "is able to" becomes "can", "on a monthly basis" becomes
  "monthly".
- Match the level of detail to what the reader has to do. Nielsen Norman
  Group's brevity guidance (Taylor Dykes) reduces this to one question:
  "Does the reader need this to understand me?"
- Density is the goal, not length. Cutting a decision out of a paragraph makes
  the paragraph shorter and the writing worse. See the completeness floor.

The seven revision techniques below are the practical how for this property.

## Property 3: structure that survives scanning

**Scope: human readers only.**

- One idea per paragraph, and short paragraphs. Every guide agrees on the shape
  and disagrees on the number; see the thresholds section.
- Headings that let a reader skip to the part they need, and that still leave
  correct prose behind when removed (GOV.UK).
- **Format by purpose, not by medium.** Lists are for facts a reader scans:
  status, decisions, acceptance criteria, changed files, options. Prose is for
  reasoning a reader follows: why a design was chosen, what a risk assessment
  concluded, what a tradeoff cost. Turning an argument into bullets breaks the
  thread that made it an argument, which is why narrative-memo cultures ban
  bullets in decision documents while Nielsen Norman Group, Microsoft and
  GOV.UK prescribe them for scannable facts. Both are right about their own
  case. Route on the reader's task.
- Numbered lists for sequences, bulleted lists for everything else (Google).
- **Bold a few keywords per screen at most, and never bold a restatement of the
  line it sits on.** This bound is written to stay inside the boundaries the
  `ai-slop` catalog already records, so that promoting either rule later does
  not fire on prose written to this doctrine. When the `ai-slop` plugin is
  installed, `/ai-slop:audit` owns both: `rule-bold-overuse` records "excessive
  bolding of terms beyond emphasis convention" as a density candidate, and
  `rule-inline-header-lists` draws the boundary at "a bold label whose colon
  restates the line", while treating "a bold lead-in that ends in a period,
  names the item, and is followed by genuinely new detail" as reference-doc
  style rather than a tell.
- Push depth one link away instead of inlining it. A short overview that links
  to the full record serves both the reader who wants the answer and the reader
  who wants the evidence.

## Property 4: factual tone

**Scope: universal.**

- No promotional language. The objective condition in the 1997 experiment was
  the control stripped of exaggeration, subjective claims and boasting, and it
  was worth 27% on its own.
- State the mechanism instead of the adjective. "Cuts the retry loop from three
  calls to one" says what "dramatically faster" does not.
- No exclamation marks, no buzzwords, no jargon where a plain word exists, no
  idiom, and no humour that a translator or a non-native reader has to decode
  (Google).
- No hedging stacked on hedging. One qualifier that carries information beats
  three that carry doubt.
- This property is universal because promotional language costs an agent reader
  exactly what it costs a human reader: words, with no fact inside them.

## The completeness floor

**Scope: every mode, human and agent. This is a hard rule, not a tradeoff.**

Never drop any of these, in any rewrite:

- A decision, a number, a date, a name, or an explicit ask.
- An error, a warning, or anything describing a destructive or irreversible
  action.
- A caveat that changes what the reader would do.
- The destination's own structural contract. A pull-request body that needs a
  closing keyword line and four named sections still has all five afterwards.

The sources are consistent across four unrelated fields. The Administrative
Conference of the United States (Recommendation 2017-3) tells agencies to
balance brevity, usefulness and completeness, says guidance should be
comprehensible even where that costs brevity, and prescribes citations and
hyperlinks so a reader can reach the underlying requirement. The Department of
Energy's writer's guide for technical procedures (DOE-STD-1029) states accurate,
complete and usable together, sets the level of detail from the user's training,
and exists partly to place warnings and cautions where they will be read. The
Linux kernel's patch-submission guidance says a body must describe the problem
that motivated the work and its user-visible impact, which is the record a
shorter body destroys. Claude Code's own concise output style keeps error
reports, security warnings and destructive-action confirmations in full.

When brevity and completeness genuinely conflict, put the bottom line first and
keep the full record below it or one link away. Do not resolve the conflict by
deleting.

## Thresholds: a labelled fallback, not a finding

**These numbers are a house choice.** The published guides disagree with each
other about sentence length and about paragraph length, and only one of them
publishes a size target at all. None of them cites an experiment for any of its
numbers. Where they conflict, this set follows GOV.UK because it is the most
recent and the hardest-edged, not because it is the evidence-backed answer.
There is no evidence-backed answer.

**The consuming repository overrides them in prose.** A statement in a project's
own `CLAUDE.md` or rules that sets different numbers wins outright, with no
ceremony and no reconciliation with this file. Where the project says nothing,
use these.

| Fallback | Value | Source |
|---|---|---|
| Sentence length | Split sentences over 25 words | GOV.UK |
| Paragraph length | At most 5 sentences | GOV.UK |
| Placement of the point | Bottom line in the first sentence | AR 25-50, inverted pyramid |
| Target size | About half a first draft's words | Nielsen Norman Group |

The disagreement, so that nobody cites one of these as settled:

| Rule | The published range |
|---|---|
| Sentence length | About 15 words average (AR 25-50); 15 to 20 (Nielsen Norman Group); about 20 average (US federal plain-language resource); split over 25 (GOV.UK) |
| Paragraph length | 3 to 7 lines (Microsoft); no more than 10 lines (AR 25-50); no more than 5 sentences (GOV.UK); 150 words in 3 to 8 sentences and never over 250 (US federal plain-language guidelines) |

Two cautions on the size target. It measures a first draft, not a finished
text: halving an already dense document cuts meaning, and re-running a rewrite
on its own output cuts it twice. And the count is the measure to report, never
a claim about how much the rewrite improved anything.

## The seven revision techniques

**Scope: universal.** These are the moves that turn property 2 into edits. They
regroup Nielsen Norman Group's brevity-rewriting guidance (Taylor Dykes), with
two moves from elsewhere: hidden verbs come from the US federal plain-language
guidelines, and the test for the passive comes from AR 25-50. Two moves in that
guidance, matching the level of detail to the purpose and cutting excess
information, are stated under property 2 rather than repeated here. The
numbering is this repository's and does not line up one for one with the seven
techniques that guidance lists.

1. **Kill your darlings.** The sentence you are proudest of is the one most
   likely to be there for you rather than for the reader.
2. **Cut expletive constructions.** "There is a check that validates the token"
   becomes "a check validates the token".
3. **Cut unnecessary modifiers.** Intensifiers ("very", "really", "quite",
   "significantly") and adjectives that repeat the noun's own meaning.
4. **Uncover hidden verbs.** A verb buried in a noun phrase costs words and
   hides who acts (US federal plain-language guidelines). "Perform a validation
   of the input" becomes "validate the input"; "made a decision" becomes
   "decided".
5. **Turn passive into active.** Name who acts. AR 25-50 recognizes the passive
   as a form of "to be" plus a past participle, which makes it easy to find.
6. **Remove redundancy.** Say it once. A point restated in the summary and
   again in the body is one point and two places to update.
7. **Cut non-essential clauses, then rearrange what is left.** Dependent
   clauses that survive the first pass often carry no load. Rearranging after
   the cuts exposes verbosity that the original word order hid.

Every one of these cuts words. A technique that removes a decision, a number or
an ask has been misapplied, and the completeness floor overrides it.
