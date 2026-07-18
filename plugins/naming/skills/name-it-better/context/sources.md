# Method sources — name-it-better

The naming CRITERIA are owned elsewhere (the consuming org's conventions —
see the skill body). This file grounds the skill's METHOD — how candidates
are generated, why generators run blind, what the `tournament` mode is
adapted from — and the RESEARCH ORDERING behind the fallback general
criteria (semantic accuracy → scope fit → comprehensibility → trigger
utility) the skill applies only when no convention is declared. Read it
when judging a method question, weighing the fallback criteria, or
extending the skill. Tiers: PRIMARY = author's own words / official
spec; AUTHORITATIVE = faithful canonical write-up by the originators or
their collaborators; SECONDARY = derivative. A source whose full text was
paywalled this pass is flagged Tier-2-for-verification regardless of its
nominal tier.

## Naming as a process (staged refinement)

The backbone of the default pass's distinct lenses. A name is refined
through stages rather than guessed in one shot: from missing/misleading,
to obvious-nonsense, to honest, to completely-honest, to
does-the-right-thing, to intent-revealing, to domain-abstraction. The
"responsibility-literal → moment-of-use → domain-lore" lenses map onto
the honest → intent → domain-abstraction progression.

- Origin, Arlo Belshee ("Read by Refactoring"):
  `https://arlobelshee.com/good-naming-is-a-process-not-a-single-step/` —
  PRIMARY. Flag: this host was DNS-unreachable during research, so Belshee's exact
  per-stage prose is corroborated by the Deep Roots rewrite below rather
  than quoted from the origin.
- Canonical rewrite, Tim Ottinger + Llewellyn Falco: [deeproots-series]
  and [deeproots-path] — AUTHORITATIVE. Confirm the ordered stages and the
  three-phase structure.

## Empirical naming studies — criteria-priority backbone

Backs the declared criteria priority (semantic accuracy → scope fit →
comprehensibility → trigger utility) and the structured brief's
concept → word → structure shape. Peer-reviewed, primary-fetched.

- Feitelson et al., "How Developers Choose Names," IEEE TSE 48(1), 2022
  (arXiv:2103.07487): [feitelson-tse] — PRIMARY. Two load-bearing findings:
  (a) median ~6.9% agreement between any two developers naming the same
  thing — no single namer converges, which validates blind multi-generator
  fan-out; (b) an explicit three-step model (select concepts → choose words
  → arrange structure) produced names judged better ~2:1, which the
  structured brief mirrors.
- Alpern et al., "Reproducing, Extending, and Analyzing Naming
  Experiments," arXiv:2402.10022, 2024: [alpern-repro] — PRIMARY.
  Independent reproduction (~6% agreement); instructing "longer names are
  better" alone produced NO improvement — the three-step process, not
  length, drives the gain.
- Avidan & Feitelson, "Effects of Variable Names on Comprehension," ICPC
  2017: [avidan-feitelson] — PRIMARY. Misleading names measured as bad as
  or worse than meaningless single letters — the evidence for ranking
  semantic accuracy above every other criterion.
- Hofmeister, Siegmund & Holt, "Shorter Identifier Names Take Longer to
  Comprehend," SANER 2017: [hofmeister] — PRIMARY. Full-word identifiers
  ~19% faster to comprehend than abbreviations/letters — bounds the
  comprehensibility tier: prefer full words, but the effect is an average,
  moderated by experience, not absolute.

## Naming criteria lineage (Ottinger / Clean Code)

Backs the scoring rubric's shape (the authoritative criteria source of
truth is the consuming org's conventions).

- Ottinger's Rules: [ottinger-rules] — AUTHORITATIVE. Intention-revealing,
  avoid disinformation, pronounceable, no encodings, one word per concept,
  meaningful in context. The fetchable stand-in for the Clean Code chapter.
- Clean Code, ch. 2 "Meaningful Names" (Martin, with Ottinger):
  `https://www.oreilly.com/library/view/clean-code-a/9780136083238/chapter02.xhtml`
  — nominally PRIMARY (the authors' own chapter), but the full text is
  paywalled and was NOT obtained this pass; its specific rules rest on
  secondary write-ups, so treat it as Tier-2-for-verification.

## Domain language

Backs the domain-lore lens and the "name from the shared domain
vocabulary" criterion.

- DDD Reference (Eric Evans): [ddd-reference] — PRIMARY.
- Ubiquitous Language (Fowler): [fowler-ubiquitous] — AUTHORITATIVE.

## Blind generation → human convergence (anti-anchoring)

Why generators run BLIND to the conversation and the human always makes
the final pick: diverge widely from independent perspectives, then
converge once — and keep the first-seen suggestion from anchoring the
choice.

- Double Diamond (diverge/converge), UK Design Council: [double-diamond]
  — AUTHORITATIVE.
- Anchoring bias, Tversky & Kahneman (1974), "Judgment under Uncertainty":
  `https://www.science.org/doi/10.1126/science.185.4157.1124`
  (open PDF: [tk-1974-pdf]) — PRIMARY. First value seen biases
  the final judgment; independent-before-shared review reduces it.

## `tournament` mode — adapted, NOT a documented naming technique

HONEST FLAG: there is no primary source describing a "naming tournament"
or "naming bracket" method for choosing identifiers. The mode is an
ADAPTATION, presented as a local convergence mechanism, not an
established naming standard. It borrows two documented, unrelated things:

- Elimination brackets (single/double elimination): [elim-bracket] —
  SECONDARY (generic, not naming).
- Pairwise social-choice aggregation (Condorcet / Copeland / Minimax) for
  turning head-to-head judgements into a ranking: [condorcet] — the
  rigorous basis if judges score candidates pairwise.

## Modality layer — semantic vs syntactic

Backs the skill's semantic/syntactic split and the rule that documented
style conflicts route to the consuming ecosystem, not a house verdict.

- CLI naming conventions, clig.dev: [clig] — PRIMARY (community standard).
  Lowercase-dash names, noun-verb subcommands, a full `--flag` for every
  short flag — syntactic conventions that do not transfer to other
  modalities.
- Claude Code skills, official docs: [cc-skills] — PRIMARY. The
  `description`, not the `name`, is what Claude uses to decide when to load
  a skill (combined description text truncated at 1,536 chars in the skill
  listing). So the name serves the human; the trigger phrases live in the
  description. HIGH confidence — falsification survived in the research pass.
- Documented, unresolved style conflicts — route to the consuming
  ecosystem's guide, do not pick a side:
  - abbreviation policy — .NET forbids ([dotnet-naming]) vs Go endorses
    short scope-local names ([effective-go]);
  - acronym casing — Go `URL`/`appID` ([go-initialisms]) vs .NET/Java
    `Xml`/`Html` ([dotnet-naming], [google-style]);
  - camelCase vs snake_case — no settled comprehension verdict; PEP 8
    ([pep8]) and each ecosystem's guide decide it locally.

## Framework / style-guide naming (supporting)

- .NET naming guidelines (Microsoft): [dotnet-naming] — PRIMARY. Reproduces
  the 2008 2nd-edition text (self-flagged); the 3rd edition (2020) is not
  freely available, so treat the specific DO/DO NOT rules as Tier-2 pending
  the current edition.
- Kevlin Henney, "Seven Ineffective Coding Habits" (naming): [henney] —
  PRIMARY. Meaning over word-count; "adding words is not adding meaning".
- Google style guides (per-language naming): [google-style] — PRIMARY.

[deeproots-series]: https://www.digdeeproots.com/articles/naming-process/naming-as-a-process/
[deeproots-path]: https://www.digdeeproots.com/articles/naming-process/naming-as-a-process-learning-path/
[ottinger-rules]: https://exelearning.org/wiki/OttingersNaming/
[ddd-reference]: https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf
[fowler-ubiquitous]: https://martinfowler.com/bliki/UbiquitousLanguage.html
[double-diamond]: https://en.wikipedia.org/wiki/Double_Diamond_(design_process_model)
[tk-1974-pdf]: https://www.cs.tufts.edu/comp/150AIH/pdf/TverskyKa74.pdf
[elim-bracket]: https://en.wikipedia.org/wiki/Double-elimination_tournament
[condorcet]: https://en.wikipedia.org/wiki/Condorcet_method
[dotnet-naming]: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/naming-guidelines
[henney]: https://www.infoq.com/presentations/7-ineffective-coding-habits/
[google-style]: https://google.github.io/styleguide/
[feitelson-tse]: https://www.cs.huji.ac.il/~feit/papers/Names22TSE.pdf
[alpern-repro]: https://arxiv.org/abs/2402.10022
[avidan-feitelson]: https://www.cs.huji.ac.il/~feit/papers/Names17ICPC.pdf
[hofmeister]: https://brains-on-code.github.io/shorter-identifier-names.pdf
[clig]: https://clig.dev/
[cc-skills]: https://code.claude.com/docs/en/skills
[effective-go]: https://go.dev/doc/effective_go#names
[go-initialisms]: https://go.dev/wiki/CodeReviewComments
[pep8]: https://peps.python.org/pep-0008/
